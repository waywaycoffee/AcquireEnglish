"""ECS-side worker RPC. JSON goes over SSH; secrets stay on ECS."""
import asyncio
import json
import sys
import httpx
from app.services import gpu_subtitle_queue as queue
from app.config import settings
from app.database import SessionLocal
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
            play=(await client.get('https://api.bilibili.com/x/player/playurl',
              params={'bvid':job['bvid'],'cid':page['cid'],'fnval':16,'qn':16})).json()
            tracks=(((play.get('data') or {}).get('dash') or {}).get('audio') or [])
            if not tracks:
                queue.update(job,'retry','Audio unavailable')
                return {'error':'Audio unavailable'}
            track=min(tracks,key=lambda x:x.get('bandwidth',0))
            return {**job,'url':track.get('baseUrl') or track.get('base_url'),
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
        # Default: do NOT burn cloud LLMs. Worker must send local `zh`.
        # Opt-in only: SUBTITLE_ALLOW_CLOUD_TRANSLATE=1 on ECS.
        import os
        allow_cloud = (os.environ.get('SUBTITLE_ALLOW_CLOUD_TRANSLATE') or '').strip().lower() in (
            '1', 'true', 'yes', 'on',
        )
        if not allow_cloud:
            queue.update(job, 'retry', 'local_zh_missing_no_cloud_fallback')
            return {
                'error': 'local_zh_missing_no_cloud_fallback',
                'hint': 'Run tools/subtitle/gpu_worker.py with Ollama qwen2.5:3b; '
                        'set SUBTITLE_ALLOW_CLOUD_TRANSLATE=1 only if you accept cloud cost.',
            }
        # Opt-in fallback: the configured coach LLM; only text leaves the GPU.
        from dotenv import dotenv_values
        values=dotenv_values('/opt/acquireenglish/tools/oral_coach/.env')
        key=values.get('DEEPSEEK_API_KEY') or values.get('OPENAI_API_KEY')
        base=values.get('OPENAI_BASE_URL') or 'https://api.deepseek.com/v1'
        model=values.get('DEEPSEEK_MODEL') or values.get('OPENAI_MODEL') or 'deepseek-chat'
        if not key: raise RuntimeError('Translation LLM unavailable')
        translated=[]
        prompt_tokens=0
        completion_tokens=0
        async with httpx.AsyncClient(timeout=120) as client:
            for offset in range(0,len(cues),25):
                chunk=cues[offset:offset+25]
                response=await client.post(base.rstrip('/')+'/chat/completions',
                  headers={
                    'Authorization':'Bearer '+key,
                    'X-Acquire-Module':'subtitle_translate',
                    'X-Acquire-Client-Id':'ecs-gpu-subtitle',
                  },
                  json={'model':model,'temperature':0,'messages':[
                    {'role':'system','content':'Translate each English string into Simplified Chinese. Return a JSON object with key translations containing an array of strings in exactly the same order and length. Do not add explanations.'},
                    {'role':'user','content':json.dumps([c['text'] for c in chunk])}],
                    'response_format':{'type':'json_object'}})
                response.raise_for_status()
                payload=response.json()
                usage=(payload.get('usage') or {}) if isinstance(payload,dict) else {}
                prompt_tokens+=int(usage.get('prompt_tokens') or 0)
                completion_tokens+=int(usage.get('completion_tokens') or 0)
                rows=json.loads(payload['choices'][0]['message']['content'])['translations']
                if len(rows)!=len(chunk) or not all(isinstance(r,str) and r.strip() for r in rows):
                    raise ValueError('Translation alignment failed')
                translated.extend(rows)
                queue.update(job,'translating')
        try:
            from app.services import api_usage as usage_svc
            async with SessionLocal() as usage_db:
                await usage_svc.record_usage(
                    usage_db,
                    user_id=None,
                    kind='translation',
                    provider='deepseek' if 'deepseek' in (base or '').lower() else 'openai',
                    model=model,
                    module='subtitle_translate',
                    prompt_tokens=prompt_tokens,
                    completion_tokens=completion_tokens,
                    api_key=key,
                    key_owner='platform',
                    note=f"subtitle_translate:{job.get('bvid')}",
                )
        except Exception:
            pass
        return await _store(job,cues,translated)
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
