import base64
import binascii
import asyncio
import time
from collections import defaultdict, deque
from fastapi import APIRouter, Depends, HTTPException, Response
from pydantic import BaseModel, Field
from app.config import settings
from app.deps import get_current_user
from app.models import User
from app.services.tencent_soe import evaluate
from app.services.tencent_soe_v2 import evaluate as evaluate_v2
router=APIRouter(prefix='/pronunciation',tags=['pronunciation'])
_limits=defaultdict(deque)
_slots=asyncio.Semaphore(4)
class Recording(BaseModel):
    reference: str=Field(min_length=1,max_length=500)
    pcm_base64: str=Field(min_length=1,max_length=2_600_000)

@router.get('/status')
async def status(response: Response,user:User=Depends(get_current_user)):
    response.headers['Cache-Control']='no-store'
    return {'configured':bool(settings.tencent_soe_secret_id and settings.tencent_soe_secret_key),'provider':'tencent-soe'}

@router.post('/evaluate')
async def assess(body: Recording,user:User=Depends(get_current_user)):
    if not settings.tencent_soe_secret_id or not settings.tencent_soe_secret_key:raise HTTPException(503,'腾讯云评测尚未配置，请联系管理员')
    reference=body.reference.strip()
    if not reference or len(reference.split())>30:raise HTTPException(422,'每次请朗读一个单词或不超过30词的句子')
    try: pcm=base64.b64decode(body.pcm_base64,validate=True)
    except (ValueError,binascii.Error):raise HTTPException(422,'录音格式无效')
    if len(pcm)%2 or not 6400<=len(pcm)<=1_920_000:raise HTTPException(422,'录音必须为16kHz、16位单声道PCM，时长0.2至60秒')
    recent=_limits[user.id];now=time.monotonic()
    while recent and now-recent[0]>60:recent.popleft()
    if len(recent)>=6:raise HTTPException(429,'每分钟最多评测6次，请稍后重试')
    recent.append(now)
    try:
        async with _slots:
            if settings.tencent_soe_app_id:
                return await evaluate_v2(
                    settings.tencent_soe_app_id,
                    settings.tencent_soe_secret_id,
                    settings.tencent_soe_secret_key,
                    pcm,
                    reference,
                )
            return await evaluate(settings.tencent_soe_secret_id, settings.tencent_soe_secret_key, pcm, reference)
    except ValueError as e:raise HTTPException(502,'腾讯云评测未成功（'+str(e)[:80]+'），请管理员检查服务开通与权限')
    except Exception:raise HTTPException(502,'腾讯云评测暂时不可用，请稍后重试')
