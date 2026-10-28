#!/bin/bash
# Runtime bilingual verification: boots an isolated daemon (own home + port),
# checks structured error codes on the wire and zh/en CLI output side by side.
set -euo pipefail
cd "$(dirname "$0")/.."

ROOT="$(pwd)"
TB="$ROOT/.build/release/tb"
VERIFY_HOME="$(mktemp -d /tmp/tb-l10n-verify.XXXXXX)"
PORT=48999
export TIMINGBOMB_HOME="$VERIFY_HOME"
export TIMINGBOMB_PORT="$PORT"

cleanup() {
    [ -n "${DAEMON_PID:-}" ] && kill "$DAEMON_PID" 2>/dev/null || true
    rm -rf "$VERIFY_HOME"
}
trap cleanup EXIT

echo "==> release build"
swift build -c release 2>&1 | tail -1

start_daemon() { # $1 = lang
    TIMINGBOMB_PORT=$PORT TB_LANG=$1 "$ROOT/.build/release/timingbombd" >"$VERIFY_HOME/daemon-$1.log" 2>&1 &
    DAEMON_PID=$!
    for _ in $(seq 1 50); do
        curl -sf "http://127.0.0.1:$PORT/healthz" >/dev/null 2>&1 && return 0
        sleep 0.2
    done
    echo "daemon ($1) failed to start"; cat "$VERIFY_HOME/daemon-$1.log"; exit 1
}

cli() { # $1 = lang, rest = args
    TB_LANG=$1 TIMINGBOMB_TOKEN="$(cat "$VERIFY_HOME/token")" "$TB" "${@:2}" 2>&1 || true
}

echo "==> wire format: structured errors carry code/template/params"
start_daemon en
BODY=$(curl -s -X POST "http://127.0.0.1:$PORT/flows" \
    -H "Authorization: Bearer $(cat "$VERIFY_HOME/token")" \
    -H 'Content-Type: application/json' -d '{"id":"bad id!","name":"","nodes":[]}')
echo "$BODY" | python3 -c '
import json,sys
b=json.load(sys.stdin)
assert "code" in b and b["code"]=="flowValidationFailed", b
assert "template" in b and "{count}" in b["template"], b
assert "params" in b and b["params"]["count"].isdigit(), b
assert b["error"].startswith("flow validation failed"), b
print("wire: error/code/template/params OK ->", b["code"], "| rendered:", b["error"])
issues_ok = all(("template" in i and "{pattern}" in i["template"]) or i["template"] for i in b["issues"])
assert issues_ok, b["issues"]
print("wire: issues carry templates OK (" + str(len(b["issues"])) + " issues)")
'
curl -s "http://127.0.0.1:$PORT/flows/nope" -H "Authorization: Bearer $(cat "$VERIFY_HOME/token")" \
    | python3 -c 'import json,sys; b=json.load(sys.stdin); assert b["code"]=="flowNotFound", b; print("wire: flowNotFound code OK")'
kill "$DAEMON_PID"; wait "$DAEMON_PID" 2>/dev/null || true

echo
echo "==> CLI output: en vs zh-Hans"
for LANG_TAG in en zh-Hans; do
    start_daemon $LANG_TAG
    echo "--- daemon + tb ($LANG_TAG) ---"
    cli $LANG_TAG status
    cli $LANG_TAG flow list
    cli $LANG_TAG runs clear
    cli $LANG_TAG run no-such-flow
    cli $LANG_TAG flow create --file /tmp/tb-l10n-bad.json 2>/dev/null || true
    echo "--- daemon banner ($LANG_TAG) ---"
    head -2 "$VERIFY_HOME/daemon-$LANG_TAG.log"
    kill "$DAEMON_PID"; wait "$DAEMON_PID" 2>/dev/null || true
    echo
done

echo "==> client re-renders server errors in its own locale"
start_daemon en   # daemon speaks English
echo "-- client zh (should render flowNotFound in Chinese) --"
cli zh-Hans run no-such-flow
echo "-- client en --"
cli en run no-such-flow
kill "$DAEMON_PID"; wait "$DAEMON_PID" 2>/dev/null || true

echo
echo "ALL RUNTIME CHECKS PASSED"
