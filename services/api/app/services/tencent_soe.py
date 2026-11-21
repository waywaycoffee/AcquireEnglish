"""Tencent SOE non-streaming evaluation; secrets never leave ECS."""
import base64
import hashlib
import hmac
import json
import time
import uuid
from datetime import datetime, timezone
import httpx

HOST = 'soe.tencentcloudapi.com'

def signed_headers(secret_id, secret_key, body, stamp):
    date = datetime.fromtimestamp(stamp, timezone.utc).strftime('%Y-%m-%d')
    scope = date + '/soe/tc3_request'
    canonical = 'POST\n/\n\ncontent-type:application/json; charset=utf-8\nhost:' + HOST + '\n\ncontent-type;host\n' + hashlib.sha256(body).hexdigest()
    to_sign = 'TC3-HMAC-SHA256\n' + str(stamp) + '\n' + scope + '\n' + hashlib.sha256(canonical.encode()).hexdigest()
    def mac(key, text): return hmac.new(key, text.encode(), hashlib.sha256).digest()
    signature = hmac.new(mac(mac(mac(('TC3'+secret_key).encode(), date),'soe'),'tc3_request'),to_sign.encode(),hashlib.sha256).hexdigest()
    return {'Content-Type':'application/json; charset=utf-8','Host':HOST,'X-TC-Action':'TransmitOralProcessWithInit','X-TC-Version':'2018-07-24','X-TC-Timestamp':str(stamp),'Authorization':f'TC3-HMAC-SHA256 Credential={secret_id}/{scope}, SignedHeaders=content-type;host, Signature={signature}'}

async def evaluate(secret_id, secret_key, pcm, reference, *, transport=None):
    params = {'SeqId':1,'IsEnd':1,'VoiceFileType':1,'VoiceEncodeType':1,'UserVoiceData':base64.b64encode(pcm).decode(),'SessionId':str(uuid.uuid4()),'RefText':reference,'WorkMode':1,'EvalMode':0 if len(reference.split()) == 1 else 1,'ScoreCoeff':1.0,'ServerType':0}
    body=json.dumps(params,ensure_ascii=False,separators=(',',':')).encode()
    async with httpx.AsyncClient(timeout=45,transport=transport) as client:
        response=await client.post('https://'+HOST,content=body,headers=signed_headers(secret_id,secret_key,body,int(time.time())))
        response.raise_for_status()
        result=response.json()['Response']
    if 'Error' in result:
        raise ValueError(result['Error'].get('Code','TencentError'))
    return {'provider':'tencent-soe','score':result.get('SuggestedScore'),'accuracy':result.get('PronAccuracy'),'fluency':result.get('PronFluency'),'completion':result.get('PronCompletion'),'request_id':result.get('RequestId'),'words':[{'word':w.get('Word'), 'accuracy':w.get('PronAccuracy'), 'match_tag':w.get('MatchTag'), 'phones':[{'phone':p.get('Phone'),'reference_phone':p.get('ReferencePhone'),'accuracy':p.get('PronAccuracy')} for p in w.get('PhoneInfos',[])]} for w in result.get('Words',[])]}
