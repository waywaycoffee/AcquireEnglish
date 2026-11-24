"""Tencent SOE-N recording-mode evaluation."""
import asyncio
import base64
import hmac
import json
import secrets
import time
import uuid
from urllib.parse import urlencode

from websockets.asyncio.client import connect


def signed_url(app_id: str, secret_id: str, secret_key: str, reference: str) -> str:
    host = f"soe.cloud.tencent.com/soe/api/{app_id}"
    now = int(time.time())
    params = sorted({
        "eval_mode": 0 if len(reference.split()) == 1 else 1,
        "expired": now + 300,
        "nonce": secrets.randbelow(2**31),
        "rec_mode": 1,
        "ref_text": reference,
        "score_coeff": "1.0",
        "secretid": secret_id,
        "server_engine_type": "16k_en",
        "timestamp": now,
        "voice_format": 0,
        "voice_id": uuid.uuid4().hex,
    }.items())
    signing_text = host + "?" + "&".join(f"{key}={value}" for key, value in params)
    signature = base64.b64encode(
        hmac.digest(secret_key.encode(), signing_text.encode(), "sha1")
    ).decode()
    return f"wss://{host}?{urlencode([*params, ('signature', signature)])}"


def _checked_message(raw: str | bytes) -> dict:
    message = json.loads(raw)
    if message.get("code") != 0:
        code = message.get("code")
        raise ValueError(f"SOE-N-{code}" if isinstance(code, int) else "SOE-N-invalid-response")
    return message


async def evaluate(app_id: str, secret_id: str, secret_key: str, pcm: bytes, reference: str) -> dict:
    async with asyncio.timeout(45):
        async with connect(signed_url(app_id, secret_id, secret_key, reference)) as socket:
            _checked_message(await socket.recv())
            await socket.send(pcm)
            await socket.send('{"type":"end"}')
            async for raw in socket:
                message = _checked_message(raw)
                if message.get("final") == 1:
                    result = message.get("result")
                    if isinstance(result, str):
                        result = json.loads(result)
                    if not isinstance(result, dict) or type(result.get("SuggestedScore")) not in (int, float):
                        break
                    return {
                        "provider": "tencent-soe",
                        "score": result["SuggestedScore"],
                        "accuracy": result.get("PronAccuracy"),
                        "fluency": result.get("PronFluency"),
                        "completion": result.get("PronCompletion"),
                        "request_id": message.get("voice_id"),
                        "words": [
                            {
                                "word": word.get("Word"),
                                "reference_word": word.get("ReferenceWord"),
                                "accuracy": word.get("PronAccuracy"),
                                "match_tag": word.get("MatchTag"),
                                "phones": [
                                    {
                                        "phone": phone.get("Phone"),
                                        "reference_phone": phone.get("ReferencePhone"),
                                        "accuracy": phone.get("PronAccuracy"),
                                    }
                                    for phone in word.get("PhoneInfos") or []
                                ],
                            }
                            for word in result.get("Words") or []
                        ],
                    }
    raise ValueError("SOE-N-missing-score")
