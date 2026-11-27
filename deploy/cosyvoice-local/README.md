# Local CosyVoice-300M-SFT (GPU box)

Open-source FunAudioLLM CosyVoice runs on the Windows **5060 Ti** host at:

**`D:\cosyvoice`**

| | |
|--|--|
| Start | `powershell -File D:\cosyvoice\start_api.ps1` |
| Stop | `powershell -File D:\cosyvoice\stop.ps1` |
| API | http://127.0.0.1:9880 (`/health`, `/speakers`, `/inference_sft`) |
| Gradio | http://127.0.0.1:9886 |
| Speakers | `中文女` `中文男` `日语男` `粤语女` `英文女` `英文男` `韩语女` |

Full ops note: Project store `docs/cosyvoice-300m-sft-deploy.md` and `D:\cosyvoice\README.md`.

This is separate from Aliyun DashScope CosyVoice used by `tools/reading/tts_worker.py`. Do not change reading TTS providers without an explicit cutover.
