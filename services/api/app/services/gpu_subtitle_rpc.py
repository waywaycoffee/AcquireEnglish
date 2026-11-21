"""ECS-side worker RPC. JSON goes over SSH; secrets stay on ECS."""
import asyncio
import json
import sys
import httpx
from app.services import gpu_subtitle_queue as queue
from app.config import settings
from app.database import SessionLocal
from app.shared_subtitle_store import upsert_shared_bilibili_pack
from app.link_import import _bilibili_headers

async def run(command):
    action=command['action']
    if action=='claim':
        job=queue.claim()
        if job is None: return None
        async with httpx.AsyncClient(headers=_bilibili_headers(settings.bilibili_cookie),timeout=40) as client:
            view=(await client.get('https://api.bilibili.com/x/web-interface/view',params={'bvid':job['bvid']})).json()
            pages=(view.get('data') or {}).get('pages') or []
            page=next((p for p in pages if p['page']==job['page']),None)
            if page is None:
                queue.update(job,'failed','Video page unavailable')
                return {'error':'Video page unavailable'}
            play=(await client.get('https://api.bilibili.com/x/player/playurl',
              params={'bvid':job['bvid'],'cid':page['cid'],'fnval':16,'qn':16})).json()
            tracks=(((play.get('data') or {}).get('dash') or {}).get('audio') or [])
            if not tracks:
                queue.update(job,'retry','Audio unavailable')
                return {'error':'Audio unavailable'}
            track=min(tracks,key=lambda x:x.get('bandwidth',0))
            return {**job,'url':track.get('baseUrl') or track.get('base_url'),
              'cid':page['cid'],'duration':page['duration']}
    job=command['job']
    if action=='heartbeat':
        queue.update(job,command.get('state','transcribing'))
        return {'ok':True}
    if action=='fail':
        queue.update(job,'retry','GPU worker failed')
        return {'ok':True}
    if action=='complete':
        queue.update(job,'translating')
        # Translation uses the configured coach LLM; only text leaves the GPU.
        from dotenv import dotenv_values
        values=dotenv_values('/opt/acquireenglish/tools/oral_coach/.env')
        key=values.get('DEEPSEEK_API_KEY') or values.get('OPENAI_API_KEY')
        base=values.get('OPENAI_BASE_URL') or 'https://api.deepseek.com/v1'
        model=values.get('DEEPSEEK_MODEL') or values.get('OPENAI_MODEL') or 'deepseek-chat'
        if not key: raise RuntimeError('Translation LLM unavailable')
        cues=command['cues']
        translated=[]
        async with httpx.AsyncClient(timeout=120) as client:
            for offset in range(0,len(cues),25):
                chunk=cues[offset:offset+25]
                response=await client.post(base.rstrip('/')+'/chat/completions',
                  headers={'Authorization':'Bearer '+key},
                  json={'model':model,'temperature':0,'messages':[
                    {'role':'system','content':'Translate each English string into Simplified Chinese. Return a JSON object with key translations containing an array of strings in exactly the same order and length. Do not add explanations.'},
                    {'role':'user','content':json.dumps([c['text'] for c in chunk])}],
                    'response_format':{'type':'json_object'}})
                response.raise_for_status()
                rows=json.loads(response.json()['choices'][0]['message']['content'])['translations']
                if len(rows)!=len(chunk) or not all(isinstance(r,str) and r.strip() for r in rows):
                    raise ValueError('Translation alignment failed')
                translated.extend(rows)
                queue.update(job,'translating')
        def stamp(t):
            n=round(t*1000); h,n=divmod(n,3600000);m,n=divmod(n,60000);s,n=divmod(n,1000)
            return f'{h:02}:{m:02}:{s:02},{n:03}'
        def srt(texts):
            return '\n\n'.join(f"{i+1}\n{stamp(c['start'])} --> {stamp(c['end'])}\n{text}" for i,(c,text) in enumerate(zip(cues,texts)))
        async with SessionLocal() as db:
            result=await upsert_shared_bilibili_pack(db,bvid=job['bvid'],page=job['page'],
              cid=job['cid'],duration_sec=job['duration'],subtitle_en_srt=srt([c['text'] for c in cues]),
              subtitle_zh_srt=srt(translated),source_origin='asr')
            if not result.stored and result.reason!='existing pack has equal or better quality':
                raise ValueError('Subtitle quality gate rejected')
        queue.update(job,'completed')
        return {'stored':result.stored,'reason':result.reason,'cues':len(cues)}
    raise ValueError('Unknown action')

if __name__=='__main__':
    try:
        print(json.dumps(asyncio.run(run(json.load(sys.stdin)))))
    except Exception as exc:
        print(json.dumps({'error':type(exc).__name__}))
        raise SystemExit(1)
