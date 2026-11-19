"""Pre-render US English pronunciation into an unpublished lexicon SQLite file."""
import argparse
import ctypes as c
import ctypes.util
import io
import sqlite3
import wave
import zlib
from contextlib import closing


def render(database):
    library = ctypes.util.find_library('espeak-ng')
    if library is None:
        raise RuntimeError('Install eSpeak NG before rendering')
    engine = c.CDLL(library)
    callback_type = c.CFUNCTYPE(c.c_int, c.POINTER(c.c_short), c.c_int, c.c_void_p)
    pieces = []

    @callback_type
    def collect(samples, count, _events):
        if samples and count:
            pieces.append(c.string_at(samples, count * c.sizeof(c.c_short)))
        return 0

    engine.espeak_Initialize.argtypes = [c.c_int, c.c_int, c.c_char_p, c.c_int]
    engine.espeak_SetVoiceByName.argtypes = [c.c_char_p]
    engine.espeak_SetSynthCallback.argtypes = [callback_type]
    engine.espeak_Synth.argtypes = [
        c.c_char_p, c.c_size_t, c.c_uint, c.c_int, c.c_uint,
        c.c_uint, c.c_void_p, c.c_void_p,
    ]
    engine.espeak_TextToPhonemes.argtypes = [
        c.POINTER(c.c_void_p), c.c_int, c.c_int,
    ]
    engine.espeak_TextToPhonemes.restype = c.c_char_p
    rate = engine.espeak_Initialize(2, 0, None, 0)
    if rate <= 0 or engine.espeak_SetVoiceByName(b'en-us') != 0:
        raise RuntimeError('Could not initialize the en-us voice')
    engine.espeak_SetSynthCallback(collect)
    try:
        with closing(sqlite3.connect(database)) as db:
            words = db.execute('''SELECT word, display_word, phonetic FROM entries
                WHERE NOT EXISTS (SELECT 1 FROM audio WHERE audio.word = entries.word)
                ORDER BY rank''').fetchall()
            for index, (word, display, phonetic) in enumerate(words, 1):
                pieces.clear()
                value = display.encode('utf-8')
                if not phonetic:
                    text = c.c_char_p(value)
                    cursor = c.cast(text, c.c_void_p)
                    ipa = engine.espeak_TextToPhonemes(c.byref(cursor), 1, 2)
                    if ipa and ipa.strip():
                        db.execute(
                            'UPDATE entries SET phonetic = ?, phonetic_source = ? WHERE word = ?',
                            (ipa.decode('utf-8').strip(), 'eSpeak NG en-us', word),
                        )
                result = engine.espeak_Synth(value, len(value) + 1, 0, 1, 0, 1, None, None)
                if result != 0 or not pieces:
                    raise RuntimeError(f'Could not synthesize {word!r}')
                buffer = io.BytesIO()
                with wave.open(buffer, 'wb') as writer:
                    writer.setparams((1, 2, rate, 0, 'NONE', 'not compressed'))
                    writer.writeframes(b''.join(pieces))
                db.execute('INSERT INTO audio VALUES (?,?)',
                           (word, zlib.compress(buffer.getvalue(), 1)))
                if index % 1000 == 0:
                    db.commit()
            db.commit()
            assert db.execute('PRAGMA integrity_check').fetchone() == ('ok',)
            print('Audio entries:', db.execute('SELECT count(*) FROM audio').fetchone()[0])
    finally:
        engine.espeak_Terminate()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('database')
    render(parser.parse_args().database)
