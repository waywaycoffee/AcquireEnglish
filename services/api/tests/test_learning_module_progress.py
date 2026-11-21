import pytest
from httpx import AsyncClient, ASGITransport
from test_study_desk import clean, account
from app.main import app

@pytest.mark.asyncio
async def test_progress_is_private_versioned_and_independent_by_module():
    async with AsyncClient(transport=ASGITransport(app=app),base_url='http://test') as client:
        a, _ = await account(client,'13900001001')
        b, _ = await account(client,'13900001002')
        path='/api/learning-modules/ipa/progress'
        assert (await client.get(path)).status_code == 401
        assert (await client.get(path,headers=a)).json()['state'] is None
        state={'lesson':3,'line':1,'completed':[0,1,2]}
        saved=await client.put(path,headers=a,json={'revision':0,'state':state})
        assert saved.status_code == 200 and saved.json()['revision']==1
        assert (await client.put(path,headers=a,json={'revision':0,'state':state})).status_code==409
        assert (await client.get(path,headers=b)).json()['state'] is None
        assert (await client.get('/api/learning-modules/phonics/progress',headers=a)).json()['state'] is None
        saved=await client.put(path,headers=a,json={'revision':1,'state':{**state,'lesson':4}})
        assert saved.json()['revision']==2
        assert (await client.put(path,headers=a,json={'revision':1,'state':state})).status_code==409
        assert (await client.get(path,headers=a)).json()['state']['lesson']==4
        assert (await client.put(path,headers=a,json={'revision':2,'state':{**state,'completed':[-1]}})).status_code==422

@pytest.mark.asyncio
async def test_tencent_requires_auth_and_configuration(monkeypatch):
    from app.config import settings
    monkeypatch.setattr(settings,'tencent_soe_secret_id','')
    monkeypatch.setattr(settings,'tencent_soe_secret_key','')
    async with AsyncClient(transport=ASGITransport(app=app),base_url='http://test') as client:
        assert (await client.get('/api/pronunciation/status')).status_code==401
        a,_=await account(client,'13900001001')
        assert (await client.get('/api/pronunciation/status',headers=a)).json()['configured'] is False
        result=await client.post('/api/pronunciation/evaluate',headers=a,json={'reference':'hello','pcm_base64':'AA=='})
        assert result.status_code==503

@pytest.mark.asyncio
async def test_tencent_parses_acoustic_word_and_phone_results():
    import httpx
    from app.services.tencent_soe import evaluate
    async def handler(request):
        import json
        body=json.loads(request.content)
        assert body['ServerType']==0 and body['VoiceFileType']==1 and body['WorkMode']==1
        assert body['EvalMode']==0 and body['RefText']=='hello'
        assert request.headers['Authorization'].startswith('TC3-HMAC-SHA256 Credential=test-id/')
        assert b'test-secret' not in request.content
        return httpx.Response(200,json={'Response':{'SuggestedScore':87.5,'PronAccuracy':90,'Words':[{'Word':'hello','PronAccuracy':89,'PhoneInfos':[{'Phone':'hh','PronAccuracy':75}]}]}})
    result=await evaluate('test-id','test-secret',b'\x00\x00'*8000,'hello',transport=httpx.MockTransport(handler))
    assert result['provider']=='tencent-soe' and result['score']==87.5
    assert result['words'][0]['phones'][0]['accuracy']==75
