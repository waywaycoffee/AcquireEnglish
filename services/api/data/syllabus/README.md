# First-party syllabus JSON (served by API)

App downloads via `GET /api/syllabus/catalog` and `GET /api/syllabus/books/{id}`.
Do not embed these media-heavy or large word-book dumps in the mobile APK.

## Word books

Regenerate frequency-band word books (PEP/课标/高频/中高考/留学等 **适配带**):

```bash
python3 tools/syllabus/build_word_books.py
```

Sources: HermitDave FrequencyWords (MIT) + ECDICT glosses under
`apps/mobile/assets/dictionary/`. Disclaimers in each JSON state these are
self-curated study bands, not MoE / PEP / exam-board verbatim dumps.

## Other JSON

`foundation_*` / `chunks_*` / `daily_patterns.json` are hand-maintained or
built by sibling tools under `tools/syllabus/`.
