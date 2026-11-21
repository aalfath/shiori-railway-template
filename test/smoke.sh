#!/bin/sh
# Smoke test: liveness, default login refused, owner login, add a bookmark with archive, list it.
# Usage: BASE=https://YOUR-DOMAIN SUSER=admin PASS=... sh test/smoke.sh
set -eu
BASE="${BASE:-http://localhost:8080}"
curl -fsS "$BASE/system/liveness"; echo
if curl -fsS -X POST -H 'Content-Type: application/json' -d '{"username":"shiori","password":"gopher"}' "$BASE/api/v1/auth/login" >/dev/null 2>&1; then
  echo "FAIL: default shiori/gopher login works"; exit 1
fi
echo "ok: default shiori/gopher login refused"
TOKEN=$(curl -fsS -X POST -H 'Content-Type: application/json' -d "{\"username\":\"$SUSER\",\"password\":\"$PASS\"}" "$BASE/api/v1/auth/login" | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')
[ -n "$TOKEN" ] || { echo "FAIL: owner login"; exit 1; }
echo "ok: owner login"
if [ "${ADD:-1}" = 1 ]; then
  curl -fsS -X POST -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
    -d '{"url":"https://github.com/go-shiori/shiori","create_archive":true,"tags":[{"name":"smoke"}]}' "$BASE/api/bookmarks" | head -c 300; echo
fi
curl -fsS -H "Authorization: Bearer $TOKEN" "$BASE/api/bookmarks" | head -c 400; echo
curl -fsS -H "Authorization: Bearer $TOKEN" "$BASE/api/v1/system/info"; echo
