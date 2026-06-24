#!/usr/bin/env bash
# todo_postgres_smoke.sh — operator-grade local Postgres smoke for examples/todo_postgres_app.
# LAB-TODOAPP-API-LOCAL-POSTGRES-SMOKE-P13 / hardened by LAB-TODOAPP-API-OPERATOR-SMOKE-P21.
#
# One command runs the real product path (`igweb-serve --host-config` against a real local Postgres)
# and prints a compact PASS/FAIL receipt covering health, list, show, create-title, done, and replay.
# It reuses the committed, secret-free examples/todo_postgres_app/host.example.toml, so it writes NO
# config file: the only secrets are env vars, never on disk and never echoed.
#
# Usage:
#   IGNITER_TODO_PG_DSN="host=localhost user=alex dbname=igniter_todo_test" \
#   IGNITER_TODO_EFFECT_TOKEN="dev-token" \
#     server/igniter-web/scripts/todo_postgres_smoke.sh
#
# Safety: requires a DEDICATED local test DB. Refuses a non-local host (unless
# IGNITER_TODO_SMOKE_ALLOW_NONLOCAL=1) and refuses a dbname that looks like spark/prod/production or is
# empty. These checks target the libpq key=value conninfo form (host=… dbname=…) and do a coarse
# extraction for postgres:// URLs; they are conservative, not a full parser.
#
# Exit codes: 0 = PASS, 1 = a check failed, 2 = preflight refusal (bad/missing env or missing tool).

set -uo pipefail

fail2() { echo "todo_postgres_smoke: REFUSED — $1" >&2; exit 2; }

# ── Preflight (runs BEFORE any tool/DB use, so refusals are hermetic) ──────────────────────────────
[[ -n "${IGNITER_TODO_PG_DSN:-}"   ]] || fail2 "IGNITER_TODO_PG_DSN must be set (a dedicated LOCAL test DB; never production / never SparkCRM)."
[[ -n "${IGNITER_TODO_EFFECT_TOKEN:-}" ]] || fail2 "IGNITER_TODO_EFFECT_TOKEN must be set (a local bearer token; not echoed)."

# Extract host + dbname (key=value conninfo, or a coarse postgres:// URL parse).
if [[ "$IGNITER_TODO_PG_DSN" == *"://"* ]]; then
  _u="${IGNITER_TODO_PG_DSN#*://}"; _hp="${_u#*@}"; _hp="${_hp%%/*}"
  DSN_HOST="${_hp%%:*}"; _rest="${_u#*/}"; DSN_DB="${_rest%%\?*}"
else
  DSN_HOST="$(printf '%s' "$IGNITER_TODO_PG_DSN" | grep -oE '(^|[[:space:]])host=[^[:space:]]+' | head -1 | sed 's/.*host=//')"
  DSN_DB="$(printf '%s' "$IGNITER_TODO_PG_DSN" | grep -oE '(^|[[:space:]])dbname=[^[:space:]]+' | head -1 | sed 's/.*dbname=//')"
fi
DSN_HOST_LC="$(printf '%s' "$DSN_HOST" | tr '[:upper:]' '[:lower:]')"
DSN_DB_LC="$(printf '%s' "$DSN_DB" | tr '[:upper:]' '[:lower:]')"

[[ -n "$DSN_DB" ]] || fail2 "could not find a dbname in IGNITER_TODO_PG_DSN (expected 'dbname=<name>')."
case "$DSN_DB_LC" in
  *spark*|*prod*|*production*) fail2 "dbname '$DSN_DB' looks like a production/SparkCRM database — refusing. Use a dedicated test DB." ;;
esac
if [[ -n "$DSN_HOST" ]]; then
  case "$DSN_HOST_LC" in
    localhost|127.0.0.1|::1|"") : ;;
    *) [[ "${IGNITER_TODO_SMOKE_ALLOW_NONLOCAL:-0}" == "1" ]] \
         || fail2 "host '$DSN_HOST' is not local — refusing (set IGNITER_TODO_SMOKE_ALLOW_NONLOCAL=1 to override for a lab box)." ;;
  esac
fi

for tool in psql curl cargo; do
  command -v "$tool" >/dev/null 2>&1 || fail2 "required tool not found: $tool"
done

echo "todo_postgres_smoke: preflight ok (db=$DSN_DB, loopback only; DSN/token not echoed)"

# ── Config + identifiers ──────────────────────────────────────────────────────────────────────────
CRATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$CRATE_DIR/examples/todo_postgres_app"
HOST_CFG="$APP_DIR/host.example.toml"

ACCT="acct-smoke"
# A distinct never-populated account for the empty-list read. As of P23 this is only for clarity, NOT a
# correctness workaround: the staged read host now runs each uncorrelated read fresh (replay is opt-in
# via an explicit x-correlation-id), so a same-account `list → create → list` would observe the new row
# rather than replay an earlier empty result. Using a separate empty account just keeps the receipt
# obviously empty for the 404 check.
ACCT_EMPTY="acct-smoke-empty"
CREATE_KEY="smoke-create-1"   # create idempotency key — the receipt/replay identity ONLY. As of P36 the
                              # created row id is the host-minted surrogate `todo_<blake3(...)>`, NOT this
                              # key; the smoke discovers the real id from the list response below.
DONE_KEY="smoke-done-1"        # done idempotency key (write business key = the todo id, P15)
# Canonical create body contract (P35): a JSON OBJECT carrying the todo title. The legacy string body is
# deprecated (P40); the smoke exercises the canonical shape so it proves the current product surface.
WRITE_TITLE="Buy milk via smoke"

psql_dsn() { psql "$IGNITER_TODO_PG_DSN" -v ON_ERROR_STOP=1 "$@"; }

cleanup_rows() {
  # FK-safe order. Test-owned ids only; never a blanket wipe.
  # Receipts key by idempotency key (P36: business_key is now the surrogate todo id, not these keys).
  psql_dsn -qtAc "DELETE FROM effect_receipts WHERE idempotency_key LIKE '${CREATE_KEY}%' OR idempotency_key LIKE '${DONE_KEY}%';" >/dev/null 2>&1 || true
  psql_dsn -qtAc "DELETE FROM todos WHERE account_id IN ('$ACCT','$ACCT_EMPTY');" >/dev/null 2>&1 || true
  psql_dsn -qtAc "DELETE FROM accounts WHERE id IN ('$ACCT','$ACCT_EMPTY');" >/dev/null 2>&1 || true
}

SERVER_PID=""
LOG="$(mktemp)"; FOUND_BODY="$(mktemp)"; SHOW_BODY="$(mktemp)"
teardown() {
  [[ -n "$SERVER_PID" ]] && kill "$SERVER_PID" >/dev/null 2>&1 || true
  cleanup_rows
  rm -f "$LOG" "$FOUND_BODY" "$SHOW_BODY" >/dev/null 2>&1 || true
}
trap teardown EXIT

# ── Schema + seed (test-owned DDL; `done` is TEXT to match the app's values; account only, no todos) ─
psql_dsn -q >/dev/null <<'SQL'
CREATE TABLE IF NOT EXISTS accounts (id text PRIMARY KEY, name text NOT NULL);
CREATE TABLE IF NOT EXISTS todos (
  id text PRIMARY KEY, account_id text NOT NULL REFERENCES accounts(id),
  title text, done text NOT NULL DEFAULT 'false', inserted_at timestamptz DEFAULT now());
CREATE TABLE IF NOT EXISTS effect_receipts (
  idempotency_key text PRIMARY KEY, correlation_id text, target text NOT NULL,
  business_key text NOT NULL, committed_at timestamptz NOT NULL DEFAULT now());
SQL
cleanup_rows
psql_dsn -qtAc "INSERT INTO accounts(id,name) VALUES ('$ACCT','Smoke');" >/dev/null
echo "todo_postgres_smoke: schema ready"

# ── Build + start the bounded loopback server (real read+write executors under --features postgres) ─
echo "todo_postgres_smoke: building igweb-serve (--features postgres) ..."
if ! ( cd "$CRATE_DIR" && cargo build --quiet --features postgres --bin igweb-serve ) >>"$LOG" 2>&1; then
  echo "todo_postgres_smoke: FAIL — cargo build failed:" >&2; cat "$LOG" >&2; exit 1
fi
BIN="$CRATE_DIR/target/debug/igweb-serve"

REQS=8
"$BIN" --host-config "$HOST_CFG" --addr 127.0.0.1:0 --max-requests "$REQS" "$APP_DIR" >"$LOG" 2>&1 &
SERVER_PID=$!
PORT=""
for _ in $(seq 1 60); do
  PORT="$(grep -oE 'listening http://127\.0\.0\.1:[0-9]+' "$LOG" 2>/dev/null | head -1 | grep -oE '[0-9]+$' || true)"
  [[ -n "$PORT" ]] && break
  kill -0 "$SERVER_PID" >/dev/null 2>&1 || break
  sleep 0.5
done
[[ -n "$PORT" ]] || { echo "todo_postgres_smoke: FAIL — server did not report a listening port:" >&2; cat "$LOG" >&2; exit 1; }
BASE="http://127.0.0.1:$PORT"
echo "todo_postgres_smoke: serving on $BASE (bounded to $REQS loopback requests)"

# ── Drive exactly $REQS requests, in order ────────────────────────────────────────────────────────
get_code()  { curl -s -o "${2:-/dev/null}" -w '%{http_code}' "$BASE$1" || echo ERR; }
# POST with bearer + idempotency-key. $1=path, $2=request body, $3=idempotency key. The create body is
# the CANONICAL object form (P35), not the deprecated string body.
post_code() {
  curl -s -o /dev/null -w '%{http_code}' \
    -H "Authorization: Bearer $IGNITER_TODO_EFFECT_TOKEN" -H "idempotency-key: $3" \
    --data "$2" -X POST "$BASE$1" || echo ERR
}

CREATE_BODY="{\"title\":\"$WRITE_TITLE\"}"   # canonical object create body (P35)

c_health="$(get_code  "/health")"
c_empty="$(get_code   "/accounts/$ACCT_EMPTY/todos")"
c_create="$(post_code "/accounts/$ACCT/todos" "$CREATE_BODY" "$CREATE_KEY")"
c_creplay="$(post_code "/accounts/$ACCT/todos" "$CREATE_BODY" "$CREATE_KEY")"
c_found="$(get_code   "/accounts/$ACCT/todos" "$FOUND_BODY")"

# Discover the ACTUAL created Todo id from the product read response (P36: the id is the host surrogate
# `todo_<32-hex>`, decoupled from the idempotency key). This reads the id from the product path's own
# answer — no jq dependency, and no duplication of the host's blake3 recipe in bash.
TODO_ID="$(grep -oE 'todo_[0-9a-f]{32}' "$FOUND_BODY" | head -1)"
[[ -n "$TODO_ID" ]] || TODO_ID="__not_discovered__"

c_show="$(get_code    "/accounts/$ACCT/todos/$TODO_ID" "$SHOW_BODY")"
c_done="$(post_code   "/accounts/$ACCT/todos/$TODO_ID/done" "{}" "$DONE_KEY")"
c_dreplay="$(post_code "/accounts/$ACCT/todos/$TODO_ID/done" "{}" "$DONE_KEY")"

wait "$SERVER_PID" 2>/dev/null || true
SERVER_PID=""

# ── DB truth (done persisted; replays performed no second mutation) — keyed by the ACTUAL todo id ───
db_done="$(psql_dsn -qtAc "SELECT done FROM todos WHERE id='$TODO_ID';" | tr -d '[:space:]')"
n_create_rcpt="$(psql_dsn -qtAc "SELECT count(*) FROM effect_receipts WHERE business_key='$TODO_ID' AND target='todos' AND idempotency_key LIKE '$CREATE_KEY%';" | tr -d '[:space:]')"
n_done_rcpt="$(psql_dsn -qtAc "SELECT count(*) FROM effect_receipts WHERE idempotency_key LIKE '$DONE_KEY%';" | tr -d '[:space:]')"
show_has_title=no; grep -qF "$WRITE_TITLE" "$SHOW_BODY" 2>/dev/null && show_has_title=yes
found_has_title=no; grep -qF "$WRITE_TITLE" "$FOUND_BODY" 2>/dev/null && found_has_title=yes

cleanup_rows
echo "todo_postgres_smoke: cleanup done"

# ── Receipt ────────────────────────────────────────────────────────────────────────────────────────
pass=1
chk() { if [[ "$2" == "$3" ]]; then printf '  PASS  %-34s %s\n' "$1" "$3"; else printf '  FAIL  %-34s expected=%s actual=%s\n' "$1" "$2" "$3"; pass=0; fi; }
echo "todo_postgres_smoke: results"
chk "health -> 200"                        200 "$c_health"
chk "list empty -> 404"                    404 "$c_empty"
chk "create -> 200"                        200 "$c_create"
chk "create replay -> 200"                 200 "$c_creplay"
chk "list found -> 200"                    200 "$c_found"
chk "list found carries title"             yes "$found_has_title"
chk "discovered surrogate todo id"         yes "$([[ "$TODO_ID" == todo_* ]] && echo yes || echo no)"
chk "show -> 200"                          200 "$c_show"
chk "create title persisted (read back)"   yes "$show_has_title"
chk "done -> 200"                          200 "$c_done"
chk "done replay -> 200"                    200 "$c_dreplay"
chk "done persisted (db done=true)"        true "$db_done"
chk "create replay: one receipt"           1    "$n_create_rcpt"
chk "done replay: one receipt"             1    "$n_done_rcpt"

if [[ "$pass" == 1 ]]; then
  echo "todo_postgres_smoke: PASS"
  exit 0
else
  echo "todo_postgres_smoke: FAIL — server log:" >&2; cat "$LOG" >&2; exit 1
fi
