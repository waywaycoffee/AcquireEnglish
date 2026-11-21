"""RTX 5060 Ti worker. ECS SSH credentials supply authenticated queue access."""
import argparse
import json
import os
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path

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

def main(once=False,model='small.en'):
    import httpx
    cuda_libraries()
    from faster_whisper import WhisperModel
    recognizer=WhisperModel(model,device='cuda',compute_type='float16')
    while True:
        try:
            job=rpc({'action':'claim'})
        except Exception as exc:
            print('Queue unavailable',type(exc).__name__,flush=True)
            if once: raise
            time.sleep(15)
            continue
        if not job:
            if once:return
            time.sleep(10)
            continue
        stopped=threading.Event()
        def heartbeat():
            while not stopped.wait(120):
                try: rpc({'action':'heartbeat','job':job})
                except Exception: pass
        thread=threading.Thread(target=heartbeat,daemon=True)
        thread.start()
        try:
            with tempfile.TemporaryDirectory(prefix='acquire-gpu-') as folder:
                audio=Path(folder)/'source.m4a'
                with httpx.stream('GET',job['url'],headers={'User-Agent':'Mozilla/5.0',
                    'Referer':'https://www.bilibili.com/'},follow_redirects=True,timeout=60) as response:
                    response.raise_for_status()
                    with audio.open('wb') as output:
                        for chunk in response.iter_bytes(): output.write(chunk)
                segments,_=recognizer.transcribe(str(audio),language='en',vad_filter=True,beam_size=5)
                cues=[dict(start=s.start,end=s.end,text=s.text.strip()) for s in segments if s.text.strip()]
                if not cues:raise ValueError('Empty transcription')
                stopped.set()
                thread.join()
                result=rpc({'action':'complete','job':job,'cues':cues})
                print(job['bvid'],job['page'],result,flush=True)
        except Exception as exc:
            print('Job failed',job['id'],type(exc).__name__,flush=True)
            try: rpc({'action':'fail','job':job})
            except Exception: pass
        finally:
            stopped.set()
        if once:return

if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--once',action='store_true')
    parser.add_argument('--model',default='small.en')
    args=parser.parse_args()
    main(args.once,args.model)
