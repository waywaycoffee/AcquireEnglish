# Fingerprint GPU Embedding (RTX 5060 Ti)

Serves semantic embeddings for `services/api` material fingerprint cache.

- **URL (Tailscale):** `http://100.115.252.55:8092/embed`
- **Model default:** `BAAI/bge-small-zh-v1.5` (512-d, CUDA)
- **Fallback on ECS:** hashing-trick if this URL is down

## Start

Uses LiveTalking’s CUDA Python (`third_party/LiveTalking/.venv`) so the 5060 Ti torch build is reused.

```powershell
cd D:\AcquireEnglish\tools\fingerprint_embed
.\start.ps1
```

Keep this process running while ECS fingerprint cache needs semantic vectors.

Health: `http://127.0.0.1:8092/health` · Tailscale: `http://100.115.252.55:8092/health`

First model download may need `HF_ENDPOINT=https://hf-mirror.com` (set in `start.ps1`).

## ECS

```
FINGERPRINT_EMBED_URL=http://100.115.252.55:8092/embed
FINGERPRINT_EMBED_DIM=512
```

After switching from hashing vectors, clear `media/misc/asset_embedding/*.json` (or re-register packs) so dims match.
