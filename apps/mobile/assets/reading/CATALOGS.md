# Online reading catalogs

In-app「在线书库」sources (**text only** into the app cache):

| Source | Access | License note |
|---|---|---|
| OneStopEnglishCorpus | GitHub raw TXT by level | CC BY-SA 4.0 |
| CEFR Levelled English Texts | Import `cefr_leveled_texts.csv` from Kaggle | Marked CC0 on Kaggle; personal study |
| Magic English Buddy | GitHub story `index.ts` (text; **no** Magicaudio into APK) | CC BY-NC-SA 4.0 (non-commercial) |
| Standard Ebooks | Featured classics + Atom new-releases EPUB | Public domain text + CC0 typesetting |
| Readseasy / ClickBook | External browser only | Third-party sites; import EPUB back into the app |

Accompanying **audio/video** must be uploaded to ECS (`namespace=reading`) and played via `/api/content/media/*`. See `docs/MEDIA_ECS.md`.

Do not redistribute Magic English content commercially.
