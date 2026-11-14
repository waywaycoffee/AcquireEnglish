#!/bin/bash
grep '^DATABASE_URL=' /opt/acquireenglish/services/api/.env | sed -E 's#(postgresql\+asyncpg://[^:]+:)[^@]+@#\1***@#'
sudo -u postgres psql -d acquireenglish -c 'SELECT count(*) AS users FROM users; SELECT count(*) AS prefs FROM user_preferences;'
curl -fsS http://127.0.0.1:5200/api/health; echo
curl -fsS https://acquireenglish.curlhairai.com/api/health; echo
