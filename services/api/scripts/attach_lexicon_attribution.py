"""Attach credits from the Tatoeba detailed sentence archive to a staging database."""
import argparse
import sqlite3
import tarfile
from contextlib import closing


def attach(database, archive):
    with closing(sqlite3.connect(database)) as db:
        ids = {str(row[0]).encode() for row in db.execute(
            'SELECT DISTINCT example_id FROM entries WHERE example_id IS NOT NULL'
        )}
        credits = []
        with tarfile.open(archive, 'r|bz2') as tar:
            for member in tar:
                if not member.name.endswith('sentences_detailed.csv'):
                    continue
                with tar.extractfile(member) as stream:
                    for line in stream:
                        fields = line.rstrip(b'\n').split(b'\t', 4)
                        if len(fields) >= 4 and fields[0] in ids and fields[1] == b'eng':
                            if fields[3] not in (b'', b'\\N'):
                                credits.append((fields[3].decode(), int(fields[0])))
                            ids.remove(fields[0])
                break
        db.execute('CREATE INDEX IF NOT EXISTS entries_example_idx ON entries(example_id)')
        db.executemany('UPDATE entries SET example_author = ? WHERE example_id = ?', credits)
        db.commit()
        print('Attributed sentence IDs:', len(credits))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('database')
    parser.add_argument('archive')
    args = parser.parse_args()
    attach(args.database, args.archive)
