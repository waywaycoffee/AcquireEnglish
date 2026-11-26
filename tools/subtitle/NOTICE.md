# Third-party subtitle engines

This directory vendors source from:

1. **auto-subs** — https://github.com/mateusz-kow/auto-subs  
   License: MIT (see `vendor/auto-subs/LICENSE`)

2. **whisper-subtitle-generator** — https://github.com/giakinh0823/whisper-subtitle-generator  
   License: see upstream repository (`vendor/whisper-subtitle-generator`)

3. **subfinder** — https://github.com/ausaki/subfinder
   Copyright 2018 ausaki; License: MIT. AcquireEnglish's ECS integration uses
   the compatible four-block Shooter fingerprint algorithm over HTTP Range
   requests, so a full netdisk movie does not need to be downloaded first.

AcquireEnglish uses them for **import-time fill of missing English subtitles** on
developer / desktop machines. Mobile builds use shared cloud ZH+EN packs and ECS
GPU ASR generation (no on-device Whisper models in the APK).
