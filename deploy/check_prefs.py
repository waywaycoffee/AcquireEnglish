from pathlib import Path

from sqlalchemy import create_engine, text

e = create_engine("sqlite:///acquire_english.db")
with e.connect() as c:
    rows = c.execute(
        text(
            "select user_id, "
            "case when bilibili_cookie is null or bilibili_cookie='' then 0 else 1 end, "
            "case when asr_api_key is null or asr_api_key='' then 0 else 1 end "
            "from user_preferences"
        )
    ).fetchall()
    print("prefs_has_cookie_asr", rows)
    links = c.execute(
        text("select id, source, external_id, length(coalesce(subtitle_en_srt,'')), length(coalesce(subtitle_zh_srt,'')) from user_link_courses")
    ).fetchall()
    print("links", links)

env = Path(".env").read_text(encoding="utf-8")
for line in env.splitlines():
    if "DASH" in line.upper() or "ASR" in line.upper() or "SECRET" in line.upper():
        key = line.split("=", 1)[0]
        print("env", key, "set" if "=" in line and len(line.split("=", 1)[1].strip()) > 0 else "empty")
