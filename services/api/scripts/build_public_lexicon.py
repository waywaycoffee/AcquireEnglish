"""Build a read-only public dictionary from SUBTLEX-US, ECDICT and Tatoeba."""
import argparse
import bz2
import csv
import json
import re
import sqlite3
from pathlib import Path

import xlrd

LEVELS = (
    (500, '学龄前'), (1800, '小学'), (3500, '中学'), (5000, '高考'),
    (6500, '四级'), (8500, '六级'), (11000, '考研'), (16000, '雅思'),
    (float('inf'), '雅思以上'),
)
TOKEN = re.compile(r"[a-z]+(?:'[a-z]+)*")


def build(workbook, dictionary, sentences, output):
    sheet = xlrd.open_workbook(workbook).sheet_by_index(0)
    labels = sheet.row_values(0)
    slots = [labels.index(label) for label in ('Word', 'FREQcount', 'SUBTLWF', 'SUBTLCD')]
    rows = {}
    for index in range(1, sheet.nrows):
        word, count, frequency, diversity = [sheet.cell_value(index, i) for i in slots]
        if isinstance(word, str) and word.strip() and isinstance(count, (int, float)):
            key = word.strip().lower().replace('’', "'")
            candidate = (word.strip(), int(count), float(frequency), float(diversity))
            if key not in rows or candidate[1] > rows[key][1]:
                rows[key] = candidate

    ranked = sorted(rows, key=lambda key: (-rows[key][1], -rows[key][3], key))
    definitions = {}
    if dictionary.suffix == '.csv':
        with dictionary.open(encoding='utf-8-sig', newline='') as stream:
            for row in csv.DictReader(stream):
                word = row['word'].lower()
                if word in rows and word not in definitions:
                    clean = lambda value: (value or '').replace(r'\n', '\n').strip()
                    definitions[word] = (
                        clean(row['translation']), clean(row['definition']),
                        clean(row['phonetic']), clean(row['pos']),
                    )
    else:
        entries = json.loads(dictionary.read_text())['entries']
        definitions = {word: (fields[0], '', fields[1], fields[2])
                       for word, fields in entries.items() if word in rows}

    examples = {}
    with bz2.open(sentences, 'rt', encoding='utf-8') as stream:
        for raw in stream:
            fields = raw.rstrip('\n').split('\t', 2)
            if len(fields) != 3 or fields[1] != 'eng':
                continue
            sentence_id, _, sentence = fields
            if len(sentence) > 200 or not sentence.endswith(('.', '?', '!')):
                continue
            tokens = TOKEN.findall(sentence.lower().replace('’', "'"))
            if not 2 <= len(tokens) <= 30:
                continue
            priority = (abs(len(tokens) - 9), len(sentence), int(sentence_id))
            for word in set(tokens):
                if word not in rows:
                    continue
                if word not in examples or priority < examples[word][0]:
                    examples[word] = priority, sentence, int(sentence_id)

    temporary = output.with_suffix('.tmp')
    temporary.unlink(missing_ok=True)
    with sqlite3.connect(temporary) as db:
        db.execute('''CREATE TABLE entries (
            word TEXT PRIMARY KEY, display_word TEXT NOT NULL, rank INTEGER NOT NULL UNIQUE,
            frequency_count INTEGER NOT NULL, per_million REAL NOT NULL,
            contextual_diversity REAL NOT NULL, level TEXT NOT NULL,
            definition_cn TEXT, definition_en TEXT, phonetic TEXT, part_of_speech TEXT,
            example_en TEXT, example_id INTEGER, phonetic_source TEXT, example_author TEXT
        )''')
        db.execute('CREATE TABLE audio (word TEXT PRIMARY KEY, wav BLOB NOT NULL)')
        db.executemany('INSERT INTO entries VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)', (
            (word, *rows[word][:1], rank, *rows[word][1:],
             next(label for limit, label in LEVELS if rank <= limit),
             *definitions.get(word, (None,) * 4),
             *examples.get(word, (None,) * 3)[1:],
             'ECDICT' if definitions.get(word, (None,) * 4)[2] else None, None)
            for rank, word in enumerate(ranked, 1)
        ))
        print(db.execute('''SELECT count(*), count(nullif(definition_cn,'')),
            count(nullif(definition_en,'')), count(nullif(phonetic,'')),
            count(example_id) FROM entries''').fetchone())
        assert db.execute('PRAGMA integrity_check').fetchone() == ('ok',)
    temporary.replace(output)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('workbook', type=Path)
    parser.add_argument('dictionary', type=Path)
    parser.add_argument('sentences', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    build(args.workbook, args.dictionary, args.sentences, args.output)
