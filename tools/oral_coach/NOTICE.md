# Notice

`tools/oral_coach` is an AcquireEnglish orchestration layer for video-topic
oral coaching. It is designed to plug in:

- ASR: WhisperX, Deepgram
- Pronunciation: wav2vec2 / phoneme alignment
- LLM: OpenAI-compatible or Ollama
- TTS: XTTS, FishSpeech
- Avatar: MuseTalk, LivePortrait, LiveTalking

Heavy model weights are **not** vendored. Providers ship as thin adapters;
install upstream packages and set env vars before leaving `mock` mode.

Sentence-level shadowing Whisper feedback remains in `tools/voice`
([Zemksh/voice](https://github.com/Zemksh/voice)).
