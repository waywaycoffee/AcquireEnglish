"""Explicitly published, public learning cards without private media URLs."""
import html
import re
import secrets
from datetime import timedelta
from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import HTMLResponse
from pydantic import BaseModel, Field
from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession
from app.database import get_db
from app.deps import get_current_user
from app.models import PublicLearningCard, CommunityPost, User
from app.routers.community_social import visible_post
from app.routers.study_desk import name, now, no_store

router = APIRouter(tags=['learning-cards'], dependencies=[Depends(no_store)])


class CardIn(BaseModel):
    post_id: int
    expression: str = Field(min_length=1, max_length=240)
    meaning: str = Field(min_length=1, max_length=500)


async def card_data(db, token):
    card = await db.get(PublicLearningCard, token)
    if card is None or not card.active:
        raise HTTPException(404, '学习卡已撤回或不存在')
    post = await db.get(CommunityPost, card.post_id)
    if post is None or post.status != 'visible' or not re.fullmatch(r'BV[A-Za-z0-9]{10}', post.bvid or ''):
        raise HTTPException(404, '原内容已不可用')
    owner = await db.get(User, card.user_id)
    return {'token': token, 'title': post.title or post.link_title or '一起练一句英语',
            'expression': card.expression, 'meaning': card.meaning, 'author': name(owner),
            'watch_url': 'https://www.bilibili.com/video/' + post.bvid,
            'app_link': 'acquireenglish://app/shared/' + token}


@router.post('/learning-cards', status_code=201)
async def publish(payload: CardIn, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    post = await visible_post(db, user.id, payload.post_id)
    if not re.fullmatch(r'BV[A-Za-z0-9]{10}', post.bvid or ''):
        raise HTTPException(400, '目前只支持经过验证的公开B站视频帖生成学习卡')
    if not payload.expression.strip() or not payload.meaning.strip():
        raise HTTPException(400, '表达与释义不能为空')
    count = await db.scalar(select(func.count()).select_from(PublicLearningCard).where(PublicLearningCard.user_id == user.id, PublicLearningCard.created_at >= now() - timedelta(days=1)))
    if count >= 30:
        raise HTTPException(429, '每天最多创建30张学习卡')
    row = PublicLearningCard(token=secrets.token_hex(16), user_id=user.id, post_id=post.id, expression=payload.expression.strip(), meaning=payload.meaning.strip(), active=1)
    db.add(row)
    await db.commit()
    return {'token': row.token, 'public_path': '/api/public/learning-cards/' + row.token}


@router.get('/learning-cards/mine')
async def mine(user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    rows = (await db.execute(select(PublicLearningCard).where(PublicLearningCard.user_id == user.id).order_by(PublicLearningCard.created_at.desc()).limit(50))).scalars()
    return {'cards': [{'token': r.token, 'expression': r.expression, 'active': bool(r.active)} for r in rows]}


@router.get('/learning-cards/{token}')
async def read_card(token: str, db: AsyncSession = Depends(get_db)):
    return await card_data(db, token)


@router.delete('/learning-cards/{token}')
async def revoke(token: str, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    card = await db.get(PublicLearningCard, token)
    if card is None or card.user_id != user.id:
        raise HTTPException(404, '学习卡不存在')
    card.active = 0
    await db.commit()
    return {'status': 'revoked'}


@router.get('/public/learning-cards/{token}', response_class=HTMLResponse)
async def landing(token: str, db: AsyncSession = Depends(get_db)):
    data = await card_data(db, token)
    esc = lambda key: html.escape(data[key], quote=True)
    return HTMLResponse(f'''<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>{esc('title')} · 爱快英语</title>
<style>body{{font-family:system-ui,sans-serif;margin:0;background:#f7f2e8;color:#26352b}}main{{max-width:520px;margin:auto;padding:28px 20px}}article{{background:white;padding:24px;border-radius:20px;margin:20px 0}}h1{{font-size:28px}}.phrase{{font-size:30px;overflow-wrap:anywhere}}a,summary{{display:block;padding:16px;margin:12px 0;border-radius:12px;background:#58cc02;color:#17300b;text-decoration:none;cursor:pointer}}p{{line-height:1.7;white-space:pre-wrap}}small{{color:#52645a}}</style></head>
<body><main><small>ACQUIRE ENGLISH / {esc('author')}分享</small><h1>{esc('title')}</h1><p>不用先登录，试着回忆这句话的意思。</p><article><p class="phrase">{esc('expression')}</p><details><summary>我想好了，核对释义</summary><p>{esc('meaning')}</p><small>刚才没想起来也没关系，再读一遍。</small></details></article><a href="{esc('watch_url')}" rel="noreferrer">前往原视频</a><a href="{esc('app_link')}">在已安装的爱快英语中继续学习</a><small>浏览器练习不会自动保存成绩或发布内容。打开App后可登录、收藏表达、导入原视频；没有安装时请先安装爱快英语。</small></main></body></html>''', headers={'Content-Security-Policy': "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; frame-ancestors 'none'", 'X-Content-Type-Options': 'nosniff'})
