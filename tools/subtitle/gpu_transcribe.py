"""GPU subtitle transcription CLI for the RTX worker; outputs UTF-8 SRT."""
import argparse
import os
from pathlib import Path
from faster_whisper import WhisperModel

def timestamp(seconds):
    ms=max(0,round(seconds*1000))
    hours,ms=divmod(ms,3600000)
    minutes,ms=divmod(ms,60000)
    seconds,ms=divmod(ms,1000)
    return f'{hours:02}:{minutes:02}:{seconds:02},{ms:03}'

def transcribe(audio, destination, model='small.en'):
    from gpu_worker import cuda_libraries
    cuda_libraries()
    recognizer=WhisperModel(model,device='cuda',compute_type='float16')
    segments,info=recognizer.transcribe(str(audio),language='en',vad_filter=True,beam_size=5)
    rows=[]
    for segment in segments:
        text=segment.text.strip()
        if text:
            rows.append(f'{len(rows)+1}\n{timestamp(segment.start)} --> {timestamp(segment.end)}\n{text}\n')
    if not rows: raise RuntimeError('No English speech recognized')
    destination=Path(destination)
    destination.parent.mkdir(parents=True,exist_ok=True)
    temporary=destination.with_suffix(destination.suffix+'.partial')
    temporary.write_text('\n'.join(rows),encoding='utf-8')
    os.replace(temporary,destination)
    print(f'GPU transcription complete: {len(rows)} cues, {info.duration:.1f}s')
if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--audio',required=True,type=Path)
    parser.add_argument('--output',required=True,type=Path)
    parser.add_argument('--model',default='small.en')
    args=parser.parse_args()
    transcribe(args.audio,args.output,args.model)
