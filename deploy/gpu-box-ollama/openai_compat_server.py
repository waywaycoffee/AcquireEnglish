#!/usr/bin/env python3
"""OpenAI-compatible /v1 server for local qwen2.5:3b (App「本地 Ollama」).

Default: http://0.0.0.0:11434  → Tailscale http://100.115.252.55:11434/v1

Loads Qwen2.5-3B-Instruct via ModelScope + transformers 4-bit (bitsandbytes)
so it shares the 5060 Ti with LiveTalking without needing the Ollama installer.
"""

from __future__ import annotations

import argparse
import os
import time
import uuid
from pathlib import Path
from typing import Any

import torch
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

MODEL_ID = os.environ.get("OLLAMA_MODEL", "qwen2.5:3b")
HOST = os.environ.get("OLLAMA_HOST", "0.0.0.0")
PORT = int(os.environ.get("OLLAMA_PORT", "11434"))
MS_MODEL = os.environ.get("MODELSCOPE_MODEL", "Qwen/Qwen2.5-3B-Instruct")
CACHE_DIR = Path(
    os.environ.get(
        "OLLAMA_MODEL_DIR",
        str(Path(__file__).resolve().parent / "models"),
    )
)

app = FastAPI(title="AcquireEnglish local Qwen OpenAI shim")
from usage_monitor import install_monitor, normalize_json_response

usage_store = install_monitor(app)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

_tokenizer = None
_model = None
_model_path: str | None = None


def get_model():
    global _tokenizer, _model, _model_path
    if _model is not None:
        return _tokenizer, _model

    from modelscope import snapshot_download
    from transformers import AutoModelForCausalLM, AutoTokenizer, BitsAndBytesConfig

    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    print(f"Downloading/loading {MS_MODEL} → {CACHE_DIR}", flush=True)
    local = snapshot_download(MS_MODEL, cache_dir=str(CACHE_DIR))
    _model_path = local

    quant = BitsAndBytesConfig(
        load_in_4bit=True,
        bnb_4bit_compute_dtype=torch.float16,
        bnb_4bit_use_double_quant=True,
        bnb_4bit_quant_type="nf4",
    )
    _tokenizer = AutoTokenizer.from_pretrained(local, trust_remote_code=True)
    _model = AutoModelForCausalLM.from_pretrained(
        local,
        quantization_config=quant,
        device_map="auto",
        trust_remote_code=True,
    )
    _model.eval()
    print("Model ready", flush=True)
    return _tokenizer, _model


class ChatMessage(BaseModel):
    role: str
    content: str


class ChatCompletionRequest(BaseModel):
    model: str = MODEL_ID
    messages: list[ChatMessage]
    temperature: float = 0.2
    max_tokens: int = Field(default=768, ge=1, le=2048)
    stream: bool = False
    response_format: dict[str, Any] | None = None


@app.get("/health")
def health() -> dict[str, Any]:
    return {
        "status": "ok",
        "model": MODEL_ID,
        "backend": MS_MODEL,
        "path": _model_path,
        "cuda": torch.cuda.is_available(),
    }


@app.get("/v1/models")
@app.get("/models")
def list_models() -> dict[str, Any]:
    return {
        "object": "list",
        "data": [
            {
                "id": MODEL_ID,
                "object": "model",
                "created": int(time.time()),
                "owned_by": "local",
            }
        ],
    }


@app.get("/api/tags")
def ollama_tags() -> dict[str, Any]:
    return {
        "models": [
            {
                "name": MODEL_ID,
                "model": MODEL_ID,
                "modified_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                "size": 0,
            }
        ]
    }


@app.post("/v1/chat/completions")
@app.post("/chat/completions")
def chat_completions(body: ChatCompletionRequest) -> dict[str, Any]:
    if body.stream:
        raise HTTPException(status_code=400, detail="stream=false only")
    tokenizer, model = get_model()
    messages = [{"role": m.role, "content": m.content} for m in body.messages]
    try:
        prompt = tokenizer.apply_chat_template(
            messages,
            tokenize=False,
            add_generation_prompt=True,
        )
        inputs = tokenizer(prompt, return_tensors="pt")
        inputs = {k: v.to(model.device) for k, v in inputs.items()}
        with torch.inference_mode():
            out = model.generate(
                **inputs,
                max_new_tokens=body.max_tokens,
                do_sample=body.temperature > 0.05,
                temperature=max(body.temperature, 1e-5),
                top_p=0.9,
                pad_token_id=tokenizer.eos_token_id,
            )
        gen = out[0][inputs["input_ids"].shape[-1] :]
        text = tokenizer.decode(gen, skip_special_tokens=True).strip()
        if (body.response_format or {}).get('type') == 'json_object':
            try:
                text = normalize_json_response(text)
            except (ValueError, TypeError) as exc:
                raise HTTPException(status_code=502, detail='Model returned invalid JSON; retry the request') from exc
    except HTTPException:
        raise
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(status_code=500, detail=str(exc)) from exc

    return {
        "id": f"chatcmpl-{uuid.uuid4().hex[:12]}",
        "object": "chat.completion",
        "created": int(time.time()),
        "model": MODEL_ID,
        "choices": [
            {
                "index": 0,
                "message": {"role": "assistant", "content": text},
                "finish_reason": "length" if int(gen.shape[-1]) >= body.max_tokens else "stop",
            }
        ],
        "usage": {
            "prompt_tokens": int(inputs["input_ids"].shape[-1]),
            "completion_tokens": int(gen.shape[-1]),
            "total_tokens": int(inputs["input_ids"].shape[-1] + gen.shape[-1]),
        },
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default=HOST)
    parser.add_argument("--port", type=int, default=PORT)
    parser.add_argument("--preload", action="store_true")
    args = parser.parse_args()
    if args.preload:
        get_model()
    import uvicorn

    uvicorn.run(app, host=args.host, port=args.port, log_level="info")


if __name__ == "__main__":
    main()
