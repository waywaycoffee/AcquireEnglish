# Third-party subtitle engines

This directory vendors source from:

1. **auto-subs** — https://github.com/mateusz-kow/auto-subs  
   License: MIT (see `vendor/auto-subs/LICENSE`)

2. **whisper-subtitle-generator** — https://github.com/giakinh0823/whisper-subtitle-generator  
   License: see upstream repository (`vendor/whisper-subtitle-generator`)

AcquireEnglish uses them for **import-time fill of missing English subtitles** on
developer / desktop machines. Mobile builds use on-device Whisper.cpp with the
same “fill only what’s missing” rules.
