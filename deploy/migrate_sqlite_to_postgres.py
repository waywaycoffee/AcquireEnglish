#!/usr/bin/env python3
"""Copy AcquireEnglish SQLite rows into PostgreSQL (same table/column names).

Usage on ECS (after createuser/createdb + asyncpg install):
  cd /opt/acquireenglish/services/api
  .venv/bin/python /tmp/migrate_sqlite_to_postgres.py \
    --sqlite ./acquire_english.db \
    --pg-url 'postgresql+psycopg2://acquireenglish:***@127.0.0.1:5432/acquireenglish'

Uses sync drivers (sqlite3 + psycopg2) so it can run before the API restarts.
Does not drop existing PG data unless --wipe is passed.
"""

from __future__ import annotations

import argparse
import sqlite3
import sys
from urllib.parse import urlparse, unquote

TABLES = [
    "users",
    "lesson_progress",
    "vocab_items",
    "user_preferences",
    "user_link_courses",
]


def _normalize_pg_url(url: str) -> str:
    raw = url
    for prefix in (
        "postgresql+asyncpg://",
        "postgresql+psycopg2://",
        "postgresql+psycopg://",
        "postgres+asyncpg://",
        "postgres+psycopg2://",
        "postgres+psycopg://",
    ):
        if raw.startswith(prefix):
            raw = "postgresql://" + raw.split("://", 1)[1]
            break
    if raw.startswith("postgres://"):
        raw = "postgresql://" + raw[len("postgres://") :]
    return raw


def _pg_connect(url: str):
    raw = _normalize_pg_url(url)
    parsed = urlparse(raw)
    kwargs = dict(
        dbname=(parsed.path or "/").lstrip("/") or "acquireenglish",
        user=unquote(parsed.username or ""),
        password=unquote(parsed.password or ""),
        host=parsed.hostname or "127.0.0.1",
        port=parsed.port or 5432,
    )
    # Prefer psycopg3 (py3.14 wheels); fall back to psycopg2.
    try:
        import psycopg

        return psycopg.connect(
            dbname=kwargs["dbname"],
            user=kwargs["user"],
            password=kwargs["password"],
            host=kwargs["host"],
            port=kwargs["port"],
        )
    except ImportError:
        pass
    try:
        import psycopg2
    except ImportError as exc:  # pragma: no cover
        raise SystemExit(
            "Need psycopg or psycopg2: pip install 'psycopg[binary]'"
        ) from exc
    return psycopg2.connect(**kwargs)


def _columns(sqlite_conn: sqlite3.Connection, table: str) -> list[str]:
    rows = sqlite_conn.execute(f"PRAGMA table_info({table})").fetchall()
    return [r[1] for r in rows]


def migrate(sqlite_path: str, pg_url: str, wipe: bool) -> dict:
    src = sqlite3.connect(sqlite_path)
    src.row_factory = sqlite3.Row
    dst = _pg_connect(pg_url)
    dst.autocommit = False
    cur = dst.cursor()
    summary: dict[str, int] = {}

    if wipe:
        for table in reversed(TABLES):
            cur.execute(f'TRUNCATE TABLE "{table}" RESTART IDENTITY CASCADE')

    for table in TABLES:
        cols = _columns(src, table)
        if not cols:
            summary[table] = 0
            continue
        rows = src.execute(f"SELECT * FROM {table}").fetchall()
        if not rows:
            summary[table] = 0
            continue
        col_list = ", ".join(f'"{c}"' for c in cols)
        placeholders = ", ".join(["%s"] * len(cols))
        # Preserve PKs; ON CONFLICT DO NOTHING keeps existing rows safe.
        sql = (
            f'INSERT INTO "{table}" ({col_list}) VALUES ({placeholders}) '
            f"ON CONFLICT DO NOTHING"
        )
        payload = [tuple(r[c] for c in cols) for r in rows]
        cur.executemany(sql, payload)
        summary[table] = len(payload)

    # Reset sequences to max(id)
    for table in TABLES:
        cur.execute(
            f"""
            SELECT setval(
              pg_get_serial_sequence('"{table}"', 'id'),
              COALESCE((SELECT MAX(id) FROM "{table}"), 1),
              true
            )
            """
        )

    dst.commit()
    cur.close()
    dst.close()
    src.close()
    return summary


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--sqlite", required=True)
    parser.add_argument("--pg-url", required=True)
    parser.add_argument(
        "--wipe",
        action="store_true",
        help="TRUNCATE target tables before import (destructive)",
    )
    args = parser.parse_args()
    # Never print password
    masked = args.pg_url
    if "@" in masked and "://" in masked:
        head, tail = masked.split("://", 1)
        if "@" in tail and ":" in tail.split("@", 1)[0]:
            user = tail.split(":", 1)[0]
            rest = tail.split("@", 1)[1]
            masked = f"{head}://{user}:***@{rest}"
    print(f"Migrating {args.sqlite} -> {masked} wipe={args.wipe}")
    summary = migrate(args.sqlite, args.pg_url, wipe=args.wipe)
    print("rows:", summary)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
