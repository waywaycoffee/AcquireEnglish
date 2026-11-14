#!/usr/bin/env bash
set -euo pipefail
echo "== listeners =="
ss -lntp | grep -E '5200|8770|8001|8010' || true
echo "== process cmdline =="
ps -ef | grep -E 'uvicorn|oral|coach|livekit|agent' | grep -v grep || true
echo "== nginx coach locs =="
grep -Rni "coach\|8770\|proxy_pass" /etc/nginx/sites-enabled /etc/nginx/conf.d 2>/dev/null | head -80 || true
echo "== curl local ports =="
for p in 5200 8770 8001 8010; do
  code=$(curl -sS -o /tmp/c_$p.out -w "%{http_code}" --max-time 3 "http://127.0.0.1:$p/" || echo ERR)
  echo "port_$p root=$code"
  code2=$(curl -sS -o /tmp/c2_$p.out -w "%{http_code}" --max-time 3 "http://127.0.0.1:$p/health" || echo ERR)
  echo "port_$p /health=$code2"
  code3=$(curl -sS -o /tmp/c3_$p.out -w "%{http_code}" --max-time 3 "http://127.0.0.1:$p/api/health" || echo ERR)
  echo "port_$p /api/health=$code3"
done
echo "== filesystem =="
ls -la /opt/acquireenglish 2>/dev/null | head
ls -la /opt/acquireenglish/tools 2>/dev/null | head || echo no_tools
ls -la /opt/oral* /opt/*coach* 2>/dev/null | head || true
find /opt -maxdepth 3 -type d -iname '*coach*' 2>/dev/null | head
echo "== systemd units =="
systemctl list-units --type=service --all | grep -Ei 'acquire|coach|oral|livekit' || true
