"""Bounded ECS cache for public licensed reading catalog sources."""
import hashlib
import re
from pathlib import Path
from urllib.parse import urlparse,unquote
import httpx
from fastapi import APIRouter, HTTPException, Query
from fastapi.responses import Response
from pydantic import BaseModel, Field
from app.config import settings
from app.services import content_media as cm
from app.services import reading_book_covers as covers_svc
router=APIRouter(prefix='/reading',tags=['reading'])


class CoverBookIn(BaseModel):
    title: str = Field(..., min_length=1, max_length=300)
    author: str = ""
    doc_id: str = Field("", max_length=200)
    force: bool = False


class CoverEnsureIn(BaseModel):
    books: list[CoverBookIn] = Field(default_factory=list, max_length=40)
    seed_classics: bool = False

def allowed(url):
    u=urlparse(url)
    try: port=u.port
    except ValueError:return False
    if any(p in ('.','..') for p in unquote(u.path).split('/')):return False
    if u.scheme!='https' or u.username or u.password or port not in (None,443):return False
    if u.hostname=='github.com':return bool(re.fullmatch(r'/standardebooks/[a-z0-9_-]+/archive/refs/heads/(master|main)\.zip',u.path))
    if u.hostname=='codeload.github.com':return bool(re.fullmatch(r'/standardebooks/[a-z0-9_-]+/zip/refs/heads/(master|main)',u.path))
    _gh_repos = (
        'nishkalavallabhi/OneStopEnglishCorpus',
        'xckevin/magic-english-buddy',
        'lilinji/English',
    )
    if u.hostname=='raw.githubusercontent.com':return any(u.path.startswith('/'+r+'/') for r in _gh_repos)
    if u.hostname=='api.github.com':return any(u.path.startswith('/repos/'+r+'/contents') for r in _gh_repos)
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

@router.get('/covers/resolve')
async def resolve_cover(
    title: str = Query(..., min_length=1, max_length=300),
    author: str = Query('', max_length=200),
    doc_id: str = Query('', max_length=200),
    force: bool = Query(False),
):
    """Search Open Library for a cover and cache it under media/reading/covers/."""
    return await covers_svc.resolve_cover(
        title=title,
        author=author,
        doc_id=doc_id,
        force=force,
    )


@router.post('/covers/ensure')
async def ensure_covers(body: CoverEnsureIn):
    """Resolve covers for a batch of books (App shelf / catalog background)."""
    books = [item.model_dump() for item in body.books]
    if body.seed_classics:
        known = {
            (b.get('doc_id') or '', (b.get('title') or '').lower())
            for b in books
        }
        for classic in covers_svc.FEATURED_CLASSICS:
            key = (classic['doc_id'], classic['title'].lower())
            if key not in known:
                books.append(dict(classic))
    if not books:
        return {'count': 0, 'found': 0, 'covers': []}
    return await covers_svc.ensure_covers(books)


@router.post('/covers/seed-classics')
async def seed_classic_covers():
    """Fill featured Standard Ebooks classics into ECS cover cache."""
    result = await covers_svc.ensure_covers(list(covers_svc.FEATURED_CLASSICS))
    return {'message': 'seeded', **result}


@router.get('/covers/index')
async def covers_index():
    """List cached cover entries (ops / App prefetch)."""
    index = covers_svc._load_index()
    items = []
    for key, entry in index.items():
        if not isinstance(entry, dict):
            continue
        rel = str(entry.get('relative') or '')
        items.append(
            {
                'key': key,
                'title': entry.get('title') or '',
                'author': entry.get('author') or '',
                'doc_id': entry.get('doc_id'),
                'cover_url': cm.public_url('reading', rel) if rel else None,
                'source': entry.get('source') or 'cache',
            }
        )
    return {'count': len(items), 'covers': items}


@router.get('/starter')
async def starter():
    # Permanent free reading starters (~5). Each is a short chapter: readable,
    # look-up-able, and reviewable — not a bare file download.
    entries=[
      ('first-morning','A Quiet Morning','A1','I wake up early on Saturday. The house is quiet. I make some tea and open the window. A small bird sits in the tree outside. I read a short story while my tea cools. I do not need to hurry today. After breakfast, I put on my shoes and walk to the park.'),
      ('small-cafe','The Small Cafe','A1','There is a small cafe near my home. The owner knows my name. Today I order a coffee and a sandwich. I sit by the window and watch people walk past. A student asks if the next chair is free. I say yes, and we begin to talk about our favourite books.'),
      ('new-route','A Different Way Home','A2','Mina usually takes the bus home, but one evening she decides to walk. She follows a quiet street and discovers a little bookshop. A handwritten sign in the window says that every book has a story beyond its pages. She goes inside and finds an old travel journal. That small change in her routine gives her a new idea for the weekend.'),
      ('rainy-afternoon','A Rainy Afternoon','A1','Rain taps on the window while I sit at my desk. I open a notebook and write three new English words. Outside, umbrellas move like colorful flowers. I listen to a short podcast and repeat each sentence aloud. When the rain slows, I feel proud of this quiet practice.'),
      ('library-corner','The Library Corner','A2','Leo finds a quiet corner behind the history shelves. He chooses a thin novel and reads the first chapter slowly. When he meets an unknown word, he looks it up and writes a simple example. Before leaving, he reviews the five new words on a small card. The library corner becomes his favourite place to learn.'),
    ]
    return {'version':2,'documents':[{'id':'starter-'+key,'title':title,'level':level,'plainText':text,'sourceType':'catalog','sourceLabel':'免费体验 · 入门推荐','courseTitle':'Acquire English 原创入门阅读','freeTrial':True,'learningPath':['阅读一章','查词','收藏难词','复习'],'segments':[{'text':sentence.strip()+'.'} for sentence in text.split('.') if sentence.strip()]} for key,title,level,text in entries]}
