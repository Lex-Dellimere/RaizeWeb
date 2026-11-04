#!/usr/bin/env bash
# raize_session end to end (reports/020): cookie, rotation on login, values across
# requests, logout, idle expiry, the CSRF guard and its exempt prefix, flash once, and
# a Signal mount (first GET and socket) reading the session.
#   ./tests/fixtures/app/session/test.sh [binary] [port] [rzpp]
# Run from the repository root.
set -u
BIN=${1:-build/session}
PORT=${2:-8076}
[ -n "$PORT" ] || PORT=8076
DIR=$(dirname "$0")
LOG=$(mktemp)
HDR=$(mktemp)
PID=""
PASS=0
FAIL=0
B=http://127.0.0.1:$PORT

cleanup() {
  if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then kill "$PID" 2>/dev/null; wait "$PID" 2>/dev/null; fi
  rm -f "$LOG" "$HDR"
}
trap cleanup EXIT

ok()  { echo "PASS  $1"; PASS=$((PASS + 1)); }
bad() { echo "FAIL  $1: $2"; FAIL=$((FAIL + 1)); }
# req <curl args...>: sets CODE, BODY, and the headers in $HDR
req() {
  local out
  out=$(curl -s -D "$HDR" -w '\n%{http_code}' "$@")
  CODE=${out##*$'\n'}; BODY=${out%$'\n'*}
}
# want <label> <status> <body-substring> <curl args...>
want() {
  local label=$1 status=$2 sub=$3; shift 3
  req "$@"
  if [ "$CODE" = "$status" ] && [[ "$BODY" == *"$sub"* ]]; then ok "$label -> $CODE"
  else bad "$label" "want $status ~$sub, got $CODE ${BODY:0:300}"; fi
}
setcookie() { grep -i '^set-cookie: rz_sid=' "$HDR" | tr -d '\r' | sed 's/^[^:]*: //'; }
sid() { setcookie | sed 's/^rz_sid=//; s/;.*//'; }
field() { printf '%s\n' "$BODY" | sed -n "s/^$1=//p"; }

"$BIN" --port "$PORT" >"$LOG" 2>&1 &
PID=$!
for _ in $(seq 1 50); do grep -q listening "$LOG" && break; sleep 0.1; done
grep -q "session: listening on 127.0.0.1:$PORT" "$LOG" && ok "listening line" || { bad "listening line" "$(cat "$LOG")"; exit 1; }

want "GET /peek without a cookie: no session, none created" 200 $'user=\npresent=no' "$B/peek"
[ -z "$(setcookie)" ] && ok "  ... and no Set-Cookie" || bad "peek set a cookie" "$(setcookie)"

want "GET / creates a session for its CSRF token" 200 'csrf=' "$B/"
A=$(sid); T1=$(field csrf)
SC=$(setcookie)
[ ${#A} -ge 43 ] && ok "  ... Set-Cookie carries an opaque token (${#A} chars)" || bad "token" "$SC"
[[ "$SC" == *"Path=/"* && "$SC" == *"Max-Age="* && "$SC" == *"HttpOnly"* && "$SC" == *"SameSite=Lax"* && "$SC" != *"Secure"* ]] \
  && ok "  ... Path=/, Max-Age, HttpOnly, SameSite=Lax (Secure off for this plain-HTTP app)" || bad "cookie attributes" "$SC"
[ ${#T1} -eq 43 ] && ok "  ... CSRF token is 43 characters" || bad "csrf token" "$T1"

want "POST /echo without a token" 403 'CSRF' -b "rz_sid=$A" -X POST "$B/echo"
want "POST /echo with a wrong token" 403 'CSRF' -b "rz_sid=$A" -H "x-csrf-token: AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA" -X POST "$B/echo"
want "POST /echo without a session" 403 'CSRF' -H "x-csrf-token: $T1" -X POST "$B/echo"
want "POST /echo with the x-csrf-token header" 200 'ok' -b "rz_sid=$A" -H "x-csrf-token: $T1" -X POST "$B/echo"
want "POST /echo with the _csrf form field" 200 'ok' -b "rz_sid=$A" --data-urlencode "_csrf=$T1" "$B/echo"
want "DELETE /echo without a token" 403 'CSRF' -b "rz_sid=$A" -X DELETE "$B/echo"
want "POST /api/ping (exempt prefix) without session or token" 200 'pong' -X POST "$B/api/ping"

want "POST /login" 303 '' -b "rz_sid=$A" --data-urlencode "_csrf=$T1" --data-urlencode "user=ann" "$B/login"
S=$(sid)
[ -n "$S" ] && [ "$S" != "$A" ] && ok "  ... login rotated the session id" || bad "rotation" "old $A new $S"
want "the pre-login id is dead" 200 $'user=\npresent=no' -b "rz_sid=$A" "$B/peek"
want "GET / after login: the value and the flash (once per take)" 200 $'user=ann\nflash=welcome ann\nagain=\n' -b "rz_sid=$S" "$B/"
T2=$(field csrf)
[ -n "$T2" ] && [ "$T2" != "$T1" ] && ok "  ... rotation changed the CSRF token" || bad "csrf after rotate" "$T1 / $T2"
want "GET / again: the value persists, the flash is gone" 200 $'user=ann\nflash=\n' -b "rz_sid=$S" "$B/"
want "the pre-login CSRF token no longer works" 403 'CSRF' -b "rz_sid=$S" -H "x-csrf-token: $T1" -X POST "$B/echo"
want "the new CSRF token works" 200 'ok' -b "rz_sid=$S" -H "x-csrf-token: $T2" -X POST "$B/echo"

want "GET /me: the Signal's 2-arg mount reads the session" 200 '<p class="user">ann</p>' -b "rz_sid=$S" "$B/me"
want "GET /me without a session: empty user" 200 '<p class="user"></p>' "$B/me"
if python3 "$DIR/client.py" "$PORT" "$S"; then ok "session client (socket mount)"; else bad "session client" "see above"; fi

want "POST /logout" 200 'bye' -b "rz_sid=$S" -H "x-csrf-token: $T2" -X POST "$B/logout"
[[ "$(setcookie)" == "rz_sid=;"*"Max-Age=0"* ]] && ok "  ... logout clears the cookie" || bad "logout cookie" "$(setcookie)"
want "after logout the session is gone" 200 $'user=\npresent=no' -b "rz_sid=$S" "$B/peek"

want "a new session for the expiry check" 200 'csrf=' "$B/"
C=$(sid); T3=$(field csrf)
want "  ... login" 303 '' -b "rz_sid=$C" --data-urlencode "_csrf=$T3" --data-urlencode "user=bob" "$B/login"
D=$(sid)
want "  ... bob is signed in" 200 $'user=bob\npresent=yes' -b "rz_sid=$D" "$B/peek"
sleep 4
want "after the 3 s idle timeout the session is gone" 200 $'user=\npresent=no' -b "rz_sid=$D" "$B/peek"
[[ "$(setcookie)" == "rz_sid=;"*"Max-Age=0"* ]] && ok "  ... and the stale cookie is cleared" || bad "stale cookie" "$(setcookie)"

kill -0 "$PID" 2>/dev/null && ok "server still up" || bad "server" "exited: $(cat "$LOG")"

echo
if [ "$FAIL" -eq 0 ]; then echo "SESSION APP OK ($PASS checks)"; exit 0; fi
echo "SESSION APP FAILED ($FAIL of $((PASS + FAIL)))"; exit 1
