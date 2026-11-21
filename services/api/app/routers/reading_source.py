"""Bounded ECS cache for public licensed reading catalog sources."""
import hashlib
import re
from pathlib import Path
from urllib.parse import urlparse,unquote
import httpx
from fastapi import APIRouter, HTTPException, Query
from fastapi.responses import Response
from app.config import settings
router=APIRouter(prefix='/reading',tags=['reading'])

def allowed(url):
    u=urlparse(url)
    try: port=u.port
    except ValueError:return False
    if any(p in ('.','..') for p in unquote(u.path).split('/')):return False
    if u.scheme!='https' or u.username or u.password or port not in (None,443):return False
    if u.hostname=='github.com':return bool(re.fullmatch(r'/standardebooks/[a-z0-9_-]+/archive/refs/heads/(master|main)\.zip',u.path))
    if u.hostname=='codeload.github.com':return bool(re.fullmatch(r'/standardebooks/[a-z0-9_-]+/zip/refs/heads/(master|main)',u.path))
    if u.hostname=='raw.githubusercontent.com':return any(u.path.startswith('/'+r+'/') for r in ['nishkalavallabhi/OneStopEnglishCorpus','xckevin/magic-english-buddy'])
    if u.hostname=='api.github.com':return any(u.path.startswith('/repos/'+r+'/contents') for r in ['nishkalavallabhi/OneStopEnglishCorpus','xckevin/magic-english-buddy'])
    return u.hostname=='standardebooks.org' and u.path.startswith(('/ebooks/','/feeds/'))

@router.get('/source')
async def source(url:str=Query(max_length=2048)):
    if not allowed(url):raise HTTPException(400,'Unsupported reading source')
    cache=Path(settings.media_cache_dir)/'reading'/'source-cache'
    cache.mkdir(parents=True,exist_ok=True)
    key=hashlib.sha256(url.encode()).hexdigest()
    data_path=cache/(key+'.bin');type_path=cache/(key+'.type')
    if data_path.exists() and type_path.exists():return Response(data_path.read_bytes(),media_type=type_path.read_text(),headers={'Cache-Control':'public,max-age=3600'})
    try:
      async with httpx.AsyncClient(timeout=45,follow_redirects=False,headers={'User-Agent':'AcquireEnglish-ReadingCatalog','Accept':'*/*'}) as client:
        current=url
        for _ in range(4):
          async with client.stream('GET',current) as r:
            if r.is_redirect:
              target=str(r.url.join(r.headers['location']))
              if not allowed(target):raise HTTPException(502,'Unsupported source redirect')
              current=target;continue
            r.raise_for_status();chunks=[];size=0
            async for chunk in r.aiter_bytes():
              size+=len(chunk)
              if size>20*1024*1024:raise HTTPException(413,'Reading file too large')
              chunks.append(chunk)
            raw=b''.join(chunks);content_type=r.headers.get('content-type','application/octet-stream').split(';')[0]
            # Atomic replacement avoids incomplete cached downloads.
            import uuid
            tmp=cache/(key+'.'+uuid.uuid4().hex+'.tmp');tmp.write_bytes(raw);tmp.replace(data_path)
            type_path.write_text(content_type)
            return Response(raw,media_type=content_type,headers={'Cache-Control':'public,max-age=3600'})
        raise HTTPException(502,'Too many source redirects')
    except HTTPException:raise
    except Exception:raise HTTPException(502,'书库源暂时不可用，请稍后重试')

@router.get('/starter')
async def starter():
    entries=[
      ('first-morning','A Quiet Morning','A1','I wake up early on Saturday. The house is quiet. I make some tea and open the window. A small bird sits in the tree outside. I read a short story while my tea cools. I do not need to hurry today. After breakfast, I put on my shoes and walk to the park.'),
      ('small-cafe','The Small Cafe','A1','There is a small cafe near my home. The owner knows my name. Today I order a coffee and a sandwich. I sit by the window and watch people walk past. A student asks if the next chair is free. I say yes, and we begin to talk about our favourite books.'),
      ('new-route','A Different Way Home','A2','Mina usually takes the bus home, but one evening she decides to walk. She follows a quiet street and discovers a little bookshop. A handwritten sign in the window says that every book has a story beyond its pages. She goes inside and finds an old travel journal. That small change in her routine gives her a new idea for the weekend.'),
    ]
    return {'version':1,'documents':[{'id':'starter-'+key,'title':title,'level':level,'plainText':text,'sourceType':'catalog','sourceLabel':'入门推荐 · 自编短文','courseTitle':'Acquire English 原创入门阅读','segments':[{'text':sentence.strip()+'.'} for sentence in text.split('.') if sentence.strip()]} for key,title,level,text in entries]}
