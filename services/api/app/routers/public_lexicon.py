import os
import sqlite3
import zlib
from contextlib import closing
from pathlib import Path

from fastapi import APIRouter, HTTPException, Path as PathParameter, Query
from fastapi.responses import Response

router = APIRouter(prefix='/public-lexicon', tags=['public-lexicon'])


def _connect():
    path = Path(os.environ.get(
        'PUBLIC_LEXICON_PATH',
        str(Path(__file__).resolve().parents[2] / 'public-lexicon.sqlite3'),
    )).resolve()
    try:
        db = sqlite3.connect(f'{path.as_uri()}?mode=ro', uri=True)
    except sqlite3.Error:
        raise HTTPException(503, 'Public lexicon unavailable') from None
    db.row_factory = sqlite3.Row
    return db


# Band widths estimate recognized word forms from ~100 through 60k+.
# Low bands resolve beginner levels; high bands unlock 20k+ ceilings.
PLACEMENT_BANDS = (
    (1, 100),
    (101, 400),
    (401, 1000),
    (1001, 2500),
    (2501, 5000),
    (5001, 9000),
    (9001, 14000),
    (14001, 20000),
    (20001, 32000),
    (32001, 50000),
)
# Sum of band widths ≈ 50,000 recognized forms (reportable 100–60,000).
PLACEMENT_ESTIMATE_MIN = 100
PLACEMENT_ESTIMATE_MAX = 60000


@router.get('/placement')
def placement():
    with closing(_connect()) as db:
        return [
            {'size': hi - lo + 1, 'items': [dict(row) for row in db.execute(
                """SELECT word, rank, definition_cn FROM entries
                   WHERE rank BETWEEN ? AND ? AND length(word) >= 2
                     AND word NOT GLOB '*[^a-z]*'
                     AND display_word = word AND trim(definition_cn) <> ''
                   ORDER BY random() LIMIT 3""", (lo, hi)
            )]}
            for lo, hi in PLACEMENT_BANDS
        ]


@router.get('/recommendations')
def recommendations(start: int = Query(ge=1, le=60383),
                    limit: int = Query(default=100, ge=1, le=150)):
    with closing(_connect()) as db:
        return [dict(row) for row in db.execute(
            """SELECT word, rank, definition_cn FROM entries
               WHERE rank >= ? AND length(word) >= 2
                 AND word NOT GLOB '*[^a-z]*'
                 AND display_word = word AND trim(definition_cn) <> ''
               ORDER BY rank LIMIT ?""", (start, limit)
        )]


@router.get('/{word}')
def lookup(word: str = PathParameter(min_length=1, max_length=120)):
    key = word.strip().lower().replace('’', "'")
    with closing(_connect()) as db:
        row = db.execute('SELECT * FROM entries WHERE word = ?', (key,)).fetchone()
        if row is None:
            raise HTTPException(404, 'Word not found')
        result = dict(row)
        audio = db.execute('SELECT 1 FROM audio WHERE word = ?', (key,)).fetchone()
    result['level_method'] = 'estimated_from_subtlex_us_frequency_rank'
    result['frequency_source'] = 'SUBTLEX-US, Brysbaert and New (2009)'
    result['dictionary_source'] = 'ECDICT (MIT)'
    author = result.pop('example_author')
    result['example_source'] = (
        {
            'url': f"https://tatoeba.org/en/sentences/show/{result['example_id']}",
            'author': author,
            'license': 'CC BY 2.0 FR',
            'license_url': 'https://creativecommons.org/licenses/by/2.0/fr/',
        } if result['example_id'] else None
    )
    result['audio_available'] = audio is not None
    result['audio_voice'] = 'eSpeak NG en-us' if audio else None
    return result


@router.get('/{word}/audio')
def pronunciation(word: str = PathParameter(min_length=1, max_length=120)):
    key = word.strip().lower().replace('’', "'")
    with closing(_connect()) as db:
        row = db.execute('SELECT wav FROM audio WHERE word = ?', (key,)).fetchone()
    if row is None:
        raise HTTPException(404, 'Pronunciation not found')
    return Response(zlib.decompress(row['wav']), media_type='audio/wav',
                    headers={'Cache-Control': 'public, max-age=86400'})
