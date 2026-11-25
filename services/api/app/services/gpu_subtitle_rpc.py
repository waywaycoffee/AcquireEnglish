"""ECS-side worker RPC. JSON goes over SSH; secrets stay on ECS."""
import asyncio
import json
import sys
import httpx
from app.services import gpu_subtitle_queue as queue
from app.config import settings
from app.database import SessionLocal
from app.models import UserLinkCourse
from sqlalchemy import select
from app.shared_subtitle_store import (
    fanout_gpu_pack_to_personal,
    upsert_shared_bilibili_pack,
)
from app.link_import import _bilibili_headers

async def run(command):
    action=command['action']
    if action=='claim':
        job=queue.claim()
        if job is None: return None
        if job.get('kind')=='translate':
            payload=json.loads(job.pop('payload') or '{}')
            return {**job,'cues':payload.get('cues') or [],'title':payload.get('title') or job['bvid'],
              'cid':payload.get('cid'),'duration':payload.get('duration')}
        job.pop('payload',None)
        if job['bvid'].startswith('YT:'):
            return job
        async with httpx.AsyncClient(headers=_bilibili_headers(settings.bilibili_cookie),timeout=40) as client:
            view=(await client.get('https://api.bilibili.com/x/web-interface/view',params={'bvid':job['bvid']})).json()
            data=(view.get('data') or {})
            pages=data.get('pages') or []
            page=next((p for p in pages if p['page']==job['page']),None)
            if page is None:
                queue.update(job,'failed','Video page unavailable')
                return {'error':'Video page unavailable'}
            title=(data.get('title') or '').strip() or job['bvid']
            part=str(page.get('part') or '').strip()
            if part and part not in title:
                title=f'{title} · {part}'
            # Prefer DASH audio; some episodes only expose progressive mp4 (durl)
            # with muxed A/V — Whisper still accepts that URL as source.
            play=(await client.get('https://api.bilibili.com/x/player/playurl',
              params={'bvid':job['bvid'],'cid':page['cid'],'fnval':16,'qn':16})).json()
            data=(play.get('data') or {})
            tracks=(((data.get('dash') or {}).get('audio')) or [])
            url=None
            if tracks:
                track=min(tracks,key=lambda x:x.get('bandwidth',0))
                url=track.get('baseUrl') or track.get('base_url')
            if not url:
                durl=(data.get('durl') or [])
                if durl:
                    url=durl[0].get('url') or durl[0].get('backup_url')
                    if isinstance(url,list):
                        url=next((u for u in url if u),None)
            if not url:
                # Retry once with a richer fnval before giving up.
                play2=(await client.get('https://api.bilibili.com/x/player/playurl',
                  params={'bvid':job['bvid'],'cid':page['cid'],'fnval':4048,'qn':16})).json()
                data2=(play2.get('data') or {})
                tracks2=(((data2.get('dash') or {}).get('audio')) or [])
                if tracks2:
                    track=min(tracks2,key=lambda x:x.get('bandwidth',0))
                    url=track.get('baseUrl') or track.get('base_url')
                if not url:
                    durl2=(data2.get('durl') or [])
                    if durl2:
                        url=durl2[0].get('url') or durl2[0].get('backup_url')
                        if isinstance(url,list):
                            url=next((u for u in url if u),None)
            if not url:
                queue.update(job,'retry','Audio unavailable')
                return {'error':'Audio unavailable'}
            return {**job,'url':url,
              'cid':page['cid'],'duration':page['duration'],'title':title}
    job=command['job']
    if action=='heartbeat':
        queue.update(
            job,
            command.get('state','transcribing'),
            progress_pct=command.get('progress_pct'),
            progress_message=command.get('progress_message'),
        )
        return {'ok':True}
    if action=='fail':
        queue.update(job,'retry','GPU worker failed')
        return {'ok':True}
    if action=='complete':
        queue.update(job,'translating')
        cues=command['cues']
        local_zh=command.get('zh')
        if (isinstance(local_zh,list) and len(local_zh)==len(cues)
                and all(isinstance(t,str) and any('\u4e00'<=ch<='\u9fff' for ch in t) for t in local_zh)):
            # Translated on the 5060 Ti; no cloud LLM call.
            return await _store(job,cues,local_zh)
        queue.update(job, 'retry', 'local_zh_missing_no_cloud_fallback')
        return {
            'error': 'local_zh_missing_no_cloud_fallback',
            'hint': 'Check the subtitle worker and its local Qwen model.',
        }
    raise ValueError('Unknown action')


async def _store(job,cues,translated):
    def stamp(t):
        n=round(t*1000); h,n=divmod(n,3600000);m,n=divmod(n,60000);s,n=divmod(n,1000)
        return f'{h:02}:{m:02}:{s:02},{n:03}'
    def srt(texts):
        return '\n\n'.join(f"{i+1}\n{stamp(c['start'])} --> {stamp(c['end'])}\n{text}" for i,(c,text) in enumerate(zip(cues,texts)))
    duration=job.get('duration') or int(max((c['end'] for c in cues),default=0))+1
    en_srt=srt([c['text'] for c in cues])
    zh_srt=srt(translated)
    requesters=queue.job_requesters(job['id'])
    if job['bvid'].startswith('YT:'):
        video_id = job['bvid'][3:]
        async with SessionLocal() as db:
            for uid in requesters:
                row = await db.scalar(select(UserLinkCourse).where(
                    UserLinkCourse.user_id == uid,
                    UserLinkCourse.source == 'youtube',
                    UserLinkCourse.external_id == video_id,
                ))
                if row is None:
                    row = UserLinkCourse(
                        user_id=uid, source='youtube', external_id=video_id,
                        title=video_id,
                        watch_url=f'https://www.youtube.com/watch?v={video_id}',
                        duration_sec=duration,
                    )
                    db.add(row)
                row.subtitle_en_srt = en_srt
                row.subtitle_zh_srt = zh_srt
            await db.commit()
        queue.update(job, 'completed')
        return {'stored': True, 'personal': len(requesters)}
    async with SessionLocal() as db:
        result=await upsert_shared_bilibili_pack(db,bvid=job['bvid'],page=job['page'],
          cid=job.get('cid'),duration_sec=duration,subtitle_en_srt=en_srt,
          subtitle_zh_srt=zh_srt,title=job.get('title'),
          source_origin='mixed' if job.get('kind')=='translate' else 'asr',
          commit=False)
        if not result.stored and result.reason!='existing pack has equal or better quality':
            raise ValueError('Subtitle quality gate rejected')
        # Dual library: shared cache + every requester / existing personal BV owner.
        personal=await fanout_gpu_pack_to_personal(
            db,
            bvid=job['bvid'],
            page=job['page'],
            subtitle_en_srt=en_srt,
            subtitle_zh_srt=zh_srt,
            title=job.get('title'),
            duration_sec=duration,
            requester_user_ids=requesters,
            commit=False,
        )
        await db.commit()
    queue.update(job,'completed')
    return {
        'stored':result.stored,
        'reason':result.reason,
        'cues':len(cues),
        'personal':personal,
    }

if __name__=='__main__':
    try:
        print(json.dumps(asyncio.run(run(json.load(sys.stdin)))))
    except Exception as exc:
        print(json.dumps({'error':type(exc).__name__}))
        raise SystemExit(1)
