#!/bin/bash
grep '^DATABASE_URL=' /opt/acquireenglish/services/api/.env | sed -E 's#(postgresql\+asyncpg://[^:]+:)[^@]+@#\1***@#'
curl -fsS http://127.0.0.1:5200/api/health; echo
sudo -u postgres psql -d acquireenglish -c "SELECT 'users' t, count(*) FROM users UNION ALL SELECT 'prefs', count(*) FROM user_preferences;"
