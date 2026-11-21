#!/bin/sh
# Railway wrapper for Shiori.
# 1. Normalises the database URL (Shiori accepts postgres:// but not postgresql://).
# 2. On a private loopback port, replaces Shiori's built-in shiori/gopher owner
#    account with SHIORI_ADMIN_USERNAME / SHIORI_ADMIN_PASSWORD before the app
#    is ever reachable from outside.
#    The calls use BusyBox nc (already in the official image), so the image
#    adds no packages.
# 3. Execs Shiori on $PORT, so a crash or OOM kill ends the container with a
#    non-zero code and Railway's ON_FAILURE policy restarts it.
set -eu

log() { echo "[start.sh] $*"; }

mkdir -p "${SHIORI_DIR:=/shiori}"
export SHIORI_DIR

if [ -z "${SHIORI_HTTP_SECRET_KEY:-}" ]; then
  log "SHIORI_HTTP_SECRET_KEY is empty: sessions would end on every restart. Set it." >&2
  exit 1
fi

# --- database URL ---------------------------------------------------------
DB="${SHIORI_DATABASE_URL:-}"
case "$DB" in
  postgresql://*) DB="postgres://${DB#postgresql://}" ;;
esac
case "$DB" in
  postgres://*)
    case "$DB" in *sslmode=*) ;; *\?*) DB="$DB&sslmode=disable" ;; *) DB="$DB?sslmode=disable" ;; esac
    ;;
  "") log "SHIORI_DATABASE_URL is empty, using SQLite in $SHIORI_DIR" ;;
esac
[ -n "$DB" ] && export SHIORI_DATABASE_URL="$DB"

# --- replace the default shiori/gopher owner account ---------------------
ADMIN_USER="${SHIORI_ADMIN_USERNAME:-}"
ADMIN_PASS="${SHIORI_ADMIN_PASSWORD:-}"
SETUP_PORT=18080
BASE="http://127.0.0.1:$SETUP_PORT"

start_setup() {
  SHIORI_HTTP_ADDRESS=127.0.0.1: SHIORI_HTTP_PORT=$SETUP_PORT SHIORI_HTTP_ACCESS_LOG=false \
    /usr/bin/shiori server >/tmp/shiori-setup.log 2>&1 &
  SETUP_PID=$!
}
stop_setup() { kill "$SETUP_PID" 2>/dev/null || true; wait "$SETUP_PID" 2>/dev/null || true; }

# Start Shiori privately. If the database isn't ready yet, Shiori exits: retry for up to ~3 minutes.
attempt=0
while :; do
  attempt=$((attempt+1))
  start_setup
  i=0; up=0
  while [ "$i" -lt 60 ]; do
    if wget -q -T 3 -O /dev/null "$BASE/system/liveness" 2>/dev/null; then up=1; break; fi
    kill -0 "$SETUP_PID" 2>/dev/null || break
    i=$((i+1)); sleep 1
  done
  [ "$up" = 1 ] && break
  stop_setup
  if [ "$attempt" -ge 30 ]; then
    log "Shiori did not start for account setup:" >&2; tail -n 20 /tmp/shiori-setup.log >&2; exit 1
  fi
  log "Shiori not ready yet (database still starting?), retrying ($attempt/30): $(tail -n 1 /tmp/shiori-setup.log)"
  sleep 5
done

json_esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

# http METHOD PATH JSON_BODY [TOKEN] -> sets HTTP_STATUS and HTTP_BODY (Shiori answers one JSON line)
http() {
  auth=""; [ -n "${4:-}" ] && auth="Authorization: Bearer $4\r\n"
  # Keep our side open for 2 s after the request: when BusyBox nc half-closes the socket,
  # Go's server cancels the request context and the login query fails.
  resp=$( { printf "%s %s HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: application/json\r\n${auth}Content-Length: %s\r\nConnection: close\r\n\r\n%s" \
    "$1" "$2" "$(printf '%s' "$3" | wc -c)" "$3"; sleep 2; } | nc -w 10 127.0.0.1 "$SETUP_PORT" 2>/dev/null || true)
  HTTP_STATUS=$(printf '%s\n' "$resp" | head -n 1 | cut -d' ' -f2)
  HTTP_BODY=$(printf '%s\n' "$resp" | tail -n 1)
}

login() { # $1 user, $2 password -> prints token or nothing
  http POST /api/v1/auth/login "$(printf '{"username":"%s","password":"%s"}' "$(json_esc "$1")" "$(json_esc "$2")")"
  [ "$HTTP_STATUS" = 200 ] && printf '%s' "$HTTP_BODY" | sed -n 's/.*"token":"\([^"]*\)".*/\1/p'
  return 0
}

default_login_works() { # fails closed: anything but a clear 400 counts as "still works"
  http POST /api/v1/auth/login '{"username":"shiori","password":"gopher"}'
  [ "$HTTP_STATUS" != 400 ]
}

TOKEN=$(login shiori gopher)
if [ -z "$TOKEN" ] && default_login_works; then
  log "could not check Shiori's default shiori/gopher account (login answered '${HTTP_STATUS:-nothing}'). Refusing to start." >&2
  stop_setup; exit 1
fi
if [ -n "$TOKEN" ]; then
  if [ -z "$ADMIN_USER" ] || [ -z "$ADMIN_PASS" ]; then
    log "Shiori still has its default shiori/gopher account and SHIORI_ADMIN_USERNAME / SHIORI_ADMIN_PASSWORD are not set. Refusing to start." >&2
    stop_setup; exit 1
  fi
  patch() { http PATCH /api/v1/auth/account "$1" "$TOKEN"; [ "$HTTP_STATUS" = 200 ]; }
  if patch "$(printf '{"username":"%s","old_password":"gopher","new_password":"%s"}' "$(json_esc "$ADMIN_USER")" "$(json_esc "$ADMIN_PASS")")"; then
    log "replaced the default shiori/gopher account with owner account '$ADMIN_USER'"
  elif patch "$(printf '{"old_password":"gopher","new_password":"%s"}' "$(json_esc "$ADMIN_PASS")")"; then
    log "username '$ADMIN_USER' is taken: kept username 'shiori' and set its password to SHIORI_ADMIN_PASSWORD"
  else
    log "could not replace the default shiori/gopher account. Refusing to start." >&2
    stop_setup; exit 1
  fi
  if default_login_works; then
    log "default shiori/gopher login still works. Refusing to start." >&2
    stop_setup; exit 1
  fi
fi
stop_setup

# --- run Shiori on the public port ----------------------------------------
export SHIORI_HTTP_PORT="${PORT:-8080}"
unset SHIORI_HTTP_ADDRESS 2>/dev/null || true
log "starting Shiori on port $SHIORI_HTTP_PORT"
exec /usr/bin/shiori server
