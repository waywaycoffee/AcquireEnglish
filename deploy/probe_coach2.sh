#!/usr/bin/env bash
set -euo pipefail
echo "== oral-coach unit =="
systemctl --no-pager -l status acquireenglish-oral-coach.service | head -40
echo "== unit file =="
systemctl cat acquireenglish-oral-coach.service
echo "== nginx snippet =="
cat /etc/nginx/snippets/acquireenglish-oral-coach.conf 2>/dev/null || echo MISSING_SNIPPET
echo "== oral_coach dir =="
ls -la /opt/acquireenglish/tools/oral_coach | head -40
echo "== oral_coach env (keys only) =="
if [ -f /opt/acquireenglish/tools/oral_coach/.env ]; then
  sed -E 's/=.*/=***/' /opt/acquireenglish/tools/oral_coach/.env | head -40
else
  echo NO_ENV
fi
echo "== public coach paths =="
for path in /coach /coach/ /coach/api/health /coach/health /api/health; do
  code=$(curl -sS -o /tmp/pc.out -w "%{http_code}" --max-time 5 "https://acquireenglish.curlhairai.com$path" || echo ERR)
  echo "$path -> $code"
done
echo "== 8770 who =="
tr '\0' ' ' < /proc/153884/cmdline; echo
ls -l /proc/153884/cwd 2>/dev/null || true
