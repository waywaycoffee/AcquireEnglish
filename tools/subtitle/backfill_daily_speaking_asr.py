#!/usr/bin/env python3
"""Resume missing curated EN subtitles using DashScope; run on the API host."""
import asyncio
import fcntl
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

API = Path('/opt/acquireenglish/services/api')
os.chdir(API)
sys.path.insert(0, str(API))
from app.config import settings
from app.database import SessionLocal
from app.models import SharedBilibiliSubtitle
from app.shared_subtitle_store import upsert_shared_bilibili_pack
from app.link_import import _bilibili_headers, fetch_bilibili_official_subs
from app.asr_dashscope import transcribe_file_to_srt
from sqlalchemy import select
import httpx

async def main():
    lock = open('/tmp/acquire-daily-asr.lock', 'w')
    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    assert settings.dashscope_api_key, 'DashScope ASR key required'
    headers = _bilibili_headers(settings.bilibili_cookie)
    failed = 0
    async with httpx.AsyncClient(headers=headers, timeout=60, follow_redirects=True) as client:
      for bvid in ('BV1CS4y1v7sQ', 'BV1Aw4m1k7qU'):
        response = await client.get('https://api.bilibili.com/x/web-interface/view', params={'bvid':bvid})
        root=response.json()
        if root.get('code') != 0: raise RuntimeError('Bilibili metadata unavailable')
        pages=root['data']['pages']
        for page in pages:
          number=int(page['page'])
          async with SessionLocal() as db:
            existing=await db.scalar(select(SharedBilibiliSubtitle).where(
              SharedBilibiliSubtitle.bvid==bvid.upper(), SharedBilibiliSubtitle.page==number))
            if existing and existing.subtitle_en_srt:
              print(bvid,number,'already stored',flush=True)
              continue
          try:
            play=await client.get('https://api.bilibili.com/x/player/playurl',params={
              'bvid':bvid,'cid':page['cid'],'fnval':16,'qn':16})
            audio=((play.json().get('data') or {}).get('dash') or {}).get('audio') or []
            if not audio: raise RuntimeError('No accessible audio stream')
            track=min(audio,key=lambda item:item.get('bandwidth',0))
            url=track.get('baseUrl') or track.get('base_url')
            with tempfile.TemporaryDirectory(prefix='daily-asr-') as folder:
              source=Path(folder)/'source.m4a'
              async with client.stream('GET',url) as stream:
                stream.raise_for_status()
                with source.open('wb') as output:
                  async for chunk in stream.aiter_bytes(): output.write(chunk)
              wav=Path(folder)/'audio.wav'
              subprocess.run(['ffmpeg','-loglevel','error','-i',str(source),'-ar','16000','-ac','1',str(wav)],check=True)
              english=await transcribe_file_to_srt(wav,api_key=settings.dashscope_api_key,language='en')
            _,chinese=await fetch_bilibili_official_subs(client,bvid=bvid,cid=page['cid'])
            async with SessionLocal() as db:
              result=await upsert_shared_bilibili_pack(db,bvid=bvid,page=number,cid=page['cid'],
                duration_sec=page['duration'],subtitle_en_srt=english,subtitle_zh_srt=chinese,source_origin='asr')
              if not result.stored: raise RuntimeError('Subtitle quality gate rejected: '+result.reason)
            print(bvid,number,'ASR stored',flush=True)
          except Exception as exc:
            failed+=1
            print(bvid,number,'FAILED',type(exc).__name__,flush=True)
    print('Completed. Failed pages:',failed,flush=True)
    return int(failed>0)
if __name__=='__main__':
    raise SystemExit(asyncio.run(main()))
