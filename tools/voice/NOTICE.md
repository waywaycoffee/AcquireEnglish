# Notice

This directory vendors [Zemksh/voice](https://github.com/Zemksh/voice)
(`vendor/zemksh-voice`) for local speaking practice (faster-whisper + optional
Gemma/Ollama rubric feedback).

Upstream is a private, local-first speaking-practice app. AcquireEnglish adds:

- LAN access (`VOICE_ALLOW_LAN`) so a phone can reach a laptop sidecar
- `POST /api/shadow` for sentence-level 影子跟读 transcript + overlap scoring
  (does not require the 20-word Gemma essay path)

Upstream source remains under `vendor/zemksh-voice/`. Prefer upstream updates
via re-sync; keep AcquireEnglish patches in `patches/` and re-apply with
`./bootstrap.sh`.
