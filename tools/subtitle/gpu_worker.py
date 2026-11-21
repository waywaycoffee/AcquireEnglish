"""RTX 5060 Ti worker. ECS SSH credentials supply authenticated queue access.

ASR jobs: download Bilibili audio → faster-whisper (CUDA) → EN→ZH on the local
Qwen shim (deploy/gpu-box-ollama, :11434/v1) → store on ECS.
Translate jobs: English cues arrive from ECS; only the local EN→ZH runs.

Translation + upload of one job overlaps the download/ASR of the next. If the
local LLM is unreachable the cues go up without Chinese and ECS falls back to
its configured cloud LLM.
"""
import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
import threading
import time
from concurrent.futures import Future, ThreadPoolExecutor
from pathlib import Path

LLM_BASE = os.environ.get('SUBTITLE_LLM_BASE', 'http://127.0.0.1:11434/v1').rstrip('/')
LLM_MODEL = os.environ.get('SUBTITLE_LLM_MODEL', 'qwen2.5:3b')
TRANSLATE_BATCH = 12
_HAN = re.compile(r'[\u4e00-\u9fff]')

_DLL_HANDLES=[]
def cuda_libraries():
    for path in (Path(sys.prefix)/'Lib/site-packages/nvidia').glob('*/bin'):
        os.environ['PATH']=str(path)+os.pathsep+os.environ.get('PATH','')
        _DLL_HANDLES.append(os.add_dll_directory(str(path)))

def rpc(payload):
    result=subprocess.run(['ssh','-o','BatchMode=yes','-o','ConnectTimeout=10','acquireenglish',
      'cd /opt/acquireenglish/services/api && .venv/bin/python -m app.services.gpu_subtitle_rpc'],
      input=json.dumps(payload),text=True,capture_output=True,timeout=3600 if payload.get('action')=='complete' else 120)
    if result.returncode: raise RuntimeError('ECS queue RPC failed')
    data=json.loads(result.stdout)
    if isinstance(data,dict) and data.get('error'): raise RuntimeError(data['error'])
    return data


def _translate_batch(client, texts):
    """One numbered batch → list of Chinese strings (same length) or None."""
    numbered='\n'.join(f'{i+1}. {t}' for i,t in enumerate(texts))
    response=client.post(f'{LLM_BASE}/chat/completions',json={
        'model':LLM_MODEL,'temperature':0,'max_tokens':120*len(texts),
        'response_format':{'type':'json_object'},
        'messages':[
          {'role':'system','content':(
            'You translate English video subtitles into natural Simplified Chinese. '
            'Return JSON {"translations": [...]} with exactly one Chinese string per '
            'input line, same order, no numbering, no explanations.')},
          {'role':'user','content':numbered}]},
      headers={'Authorization':'Bearer ollama','X-Acquire-Module':'subtitle_translate',
               'X-Acquire-Client-Id':'gpu-subtitle-worker'})
    response.raise_for_status()
    content=response.json()['choices'][0]['message']['content']
    content=re.sub(r'^```(?:json)?|```$','',content.strip()).strip()
    rows=json.loads(content).get('translations')
    if not isinstance(rows,list) or len(rows)!=len(texts):
        return None
    rows=[re.sub(r'^\s*\d+[.)、]\s*','',str(r)).strip() for r in rows]
    if not all(_HAN.search(r) for r in rows):
        return None
    return rows


def translate_local(cues):
    """EN→ZH on the local Qwen shim; None when any batch cannot be aligned."""
    import httpx
    texts=[c['text'] for c in cues]
    out=[]
    try:
        with httpx.Client(timeout=120) as client:
            for offset in range(0,len(texts),TRANSLATE_BATCH):
                batch=texts[offset:offset+TRANSLATE_BATCH]
                rows=None
                for _ in range(2):
                    try:
                        rows=_translate_batch(client,batch)
                    except (httpx.HTTPError,ValueError,KeyError):
                        rows=None
                    if rows: break
                if rows is None and len(batch)>1:
                    # Small model drifted on the batch; retry line by line.
                    rows=[]
                    for line in batch:
                        one=None
                        try: one=_translate_batch(client,[line])
                        except (httpx.HTTPError,ValueError,KeyError): one=None
                        if not one: return None
                        rows.extend(one)
                if not rows: return None
                out.extend(rows)
    except httpx.HTTPError:
        return None
    return out


class Heartbeat:
    def __init__(self, job):
        self.job=job
        self.stopped=threading.Event()
        self.thread=threading.Thread(target=self._run,daemon=True)
        self.thread.start()
    def _run(self):
        while not self.stopped.wait(120):
            try: rpc({'action':'heartbeat','job':self.job,'state':self.job.get('_state','transcribing')})
            except Exception: pass
    def stop(self):
        self.stopped.set()
        self.thread.join()


def finalize(job, cues, beat):
    """Translate locally, then store on ECS. Runs on the background thread."""
    try:
        job['_state']='translating'
        started=time.time()
        zh=translate_local(cues)
        took=round(time.time()-started,1)
        payload={'action':'complete','job':{k:v for k,v in job.items() if not k.startswith('_')},'cues':cues}
        if zh is not None:
            payload['zh']=zh
        beat.stop()
        result=rpc(payload)
        print(job['bvid'],job['page'],job.get('kind','asr'),
              'zh=local' if zh is not None else 'zh=ecs-fallback',f'{took}s',result,flush=True)
    except Exception as exc:
        beat.stop()
        print('Job failed',job['id'],type(exc).__name__,exc,flush=True)
        try: rpc({'action':'fail','job':{k:v for k,v in job.items() if not k.startswith('_')}})
        except Exception: pass


def transcribe(recognizer, job):
    import httpx
    with tempfile.TemporaryDirectory(prefix='acquire-gpu-') as folder:
        audio=Path(folder)/'source.m4a'
        with httpx.stream('GET',job['url'],headers={'User-Agent':'Mozilla/5.0',
            'Referer':'https://www.bilibili.com/'},follow_redirects=True,timeout=60) as response:
            response.raise_for_status()
            with audio.open('wb') as output:
                for chunk in response.iter_bytes(): output.write(chunk)
        segments,_=recognizer.transcribe(str(audio),language='en',vad_filter=True,beam_size=5)
        cues=[dict(start=s.start,end=s.end,text=s.text.strip()) for s in segments if s.text.strip()]
    if not cues: raise ValueError('Empty transcription')
    return cues


def main(once=False,model='small.en'):
    cuda_libraries()
    from faster_whisper import WhisperModel
    recognizer=WhisperModel(model,device='cuda',compute_type='float16')
    finisher=ThreadPoolExecutor(max_workers=1,thread_name_prefix='finalize')
    pending: Future | None=None
    while True:
        try:
            job=rpc({'action':'claim'})
        except Exception as exc:
            print('Queue unavailable',type(exc).__name__,flush=True)
            if once: raise
            time.sleep(15)
            continue
        if not job:
            if once: break
            time.sleep(10)
            continue
        beat=Heartbeat(job)
        try:
            if job.get('kind')=='translate':
                cues=job.pop('cues',None) or []
                if len(cues)<2: raise ValueError('Translate job has no cues')
            else:
                cues=transcribe(recognizer,job)
        except Exception as exc:
            beat.stop()
            print('Job failed',job['id'],type(exc).__name__,flush=True)
            try: rpc({'action':'fail','job':job})
            except Exception: pass
            if once: break
            continue
        # Keep at most one job finalizing while the next one transcribes.
        if pending is not None:
            pending.result()
        pending=finisher.submit(finalize,job,cues,beat)
        if once: break
    if pending is not None:
        pending.result()
    finisher.shutdown(wait=True)


if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--once',action='store_true')
    parser.add_argument('--model',default='small.en')
    args=parser.parse_args()
    main(args.once,args.model)
