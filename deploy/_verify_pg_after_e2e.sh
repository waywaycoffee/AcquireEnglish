#!/bin/bash
grep '^DATABASE_URL=' /opt/acquireenglish/services/api/.env | sed -E 's#(postgresql\+asyncpg://[^:]+:)[^@]+@#\1***@#'
sudo -u postgres psql -d acquireenglish -c "SELECT 'users' t, count(*) FROM users UNION ALL SELECT 'prefs', count(*) FROM user_preferences UNION ALL SELECT 'progress', count(*) FROM lesson_progress UNION ALL SELECT 'vocab', count(*) FROM vocab_items UNION ALL SELECT 'links', count(*) FROM user_link_courses;"
sudo -u postgres psql -d acquireenglish -c "SELECT id, email, left(coalesce(display_name,''),40) AS name FROM users ORDER BY id DESC LIMIT 5;"
ls -la /opt/acquireenglish/backups/ | tail -8
