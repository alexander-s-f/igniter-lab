#!/usr/bin/env bash
# todo_postgres_smoke.sh — repeatable local Postgres operator smoke for examples/todo_postgres_app.
# LAB-TODOAPP-API-LOCAL-POSTGRES-SMOKE-P13.
#
# Runs the SAME product command an operator would (real `igweb-serve --host-config` against a real
# local Postgres) and prints a compact PASS/FAIL receipt. This is the human-runnable companion to the
# P12 Cargo subprocess test — it lives outside the test harness so it can be run ad hoc.
#
# Requires a DEDICATED local test database via IGNITER_TODO_PG_DSN — NEVER a production or SparkCRM DB.
# Reuses the committed, secret-free examples/todo_postgres_app/host.example.toml, so this script writes
# NO config file: the only secrets are env vars (the DSN and a local bearer token), never on disk.
#
# Usage:
#   export IGNITER_TODO_PG_DSN="host=localhost user=alex dbname=igniter_todo_test"
#   server/igniter-web/scripts/todo_postgres_smoke.sh
#
# Exit codes: 0 = PASS, 1 = a check failed, 2 = misuse (missing DSN / missing tool).

set -euo pipefail

# ── 0. Require a dedicated local test DSN ─────────────────────────────────────────────────────────
if [[ -z "${IGNITER_TODO_PG_DSN:-}" ]]; then
  echo "FAIL: IGNITER_TODO_PG_DSN is not set." >&2
  echo "  Set it to a DEDICATED local test database (never production / never SparkCRM), e.g.:" >&2
  echo '    export IGNITER_TODO_PG_DSN="host=localhost user=alex dbname=igniter_todo_test"' >&2
  exit 2
fi
for tool in psql curl cargo; do
  command -v "$tool" >/dev/null 2>&1 || { echo "FAIL: required tool not found: $tool" >&2; exit 2; }
done

# Local-only bearer token for the effect passport (not a secret; never written to a committed file).
export IGNITER_TODO_EFFECT_TOKEN="${IGNITER_TODO_EFFECT_TOKEN:-smoke-tok}"

CRATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$CRATE_DIR/examples/todo_postgres_app"
HOST_CFG="$APP_DIR/host.example.toml"

ACCT="acct-smoke"
ACCT_EMPTY="acct-smoke-empty"
TODO_SEED="todo-smoke-seed"
WRITE_KEY="smoke-k1"
# v0 create body contract (P16): the request body is a JSON string literal carrying the todo title.
WRITE_TITLE="Buy milk via smoke"

psql_dsn() { psql "$IGNITER_TODO_PG_DSN" -v ON_ERROR_STOP=1 "$@"; }

cleanup_rows() {
  # FK-safe order: receipts (by stable business_key), then child todos, then accounts. Test-owned only.
  psql_dsn -qtAc "DELETE FROM effect_receipts WHERE business_key = '$WRITE_KEY';" >/dev/null 2>&1 || true
  psql_dsn -qtAc "DELETE FROM todos WHERE account_id IN ('$ACCT','$ACCT_EMPTY');" >/dev/null 2>&1 || true
  psql_dsn -qtAc "DELETE FROM accounts WHERE id IN ('$ACCT','$ACCT_EMPTY');" >/dev/null 2>&1 || true
}

SERVER_PID=""
LOG="$(mktemp)"
BODY="$(mktemp)"
teardown() {
  [[ -n "$SERVER_PID" ]] && kill "$SERVER_PID" >/dev/null 2>&1 || true
  rm -f "$LOG" "$BODY" >/dev/null 2>&1 || true
  cleanup_rows
}
trap teardown EXIT

# ── 1. Ensure schema in the dedicated DB (test-owned DDL; `done` is TEXT to match the app's values) ─
psql_dsn -q >/dev/null <<'SQL'
CREATE TABLE IF NOT EXISTS accounts (id text PRIMARY KEY, name text NOT NULL);
CREATE TABLE IF NOT EXISTS todos (
  id text PRIMARY KEY, account_id text NOT NULL REFERENCES accounts(id),
  title text, done text NOT NULL DEFAULT 'false', inserted_at timestamptz DEFAULT now());
CREATE TABLE IF NOT EXISTS effect_receipts (
  idempotency_key text PRIMARY KEY, correlation_id text, target text NOT NULL,
  business_key text NOT NULL, committed_at timestamptz NOT NULL DEFAULT now());
SQL

# ── 2. Seed: a fresh account with one todo (read-found); the empty account is never created ─────────
cleanup_rows
psql_dsn -qtAc "INSERT INTO accounts(id,name) VALUES ('$ACCT','Smoke');" >/dev/null
psql_dsn -qtAc "INSERT INTO todos(id,account_id,title) VALUES ('$TODO_SEED','$ACCT','Smoke seed');" >/dev/null

# ── 3. Build + start the bounded loopback server (real read+write executors under --features postgres)
echo "todo_postgres_smoke: building igweb-serve (--features postgres) ..."
if ! ( cd "$CRATE_DIR" && cargo build --quiet --features postgres --bin igweb-serve ) >>"$LOG" 2>&1; then
  echo "FAIL: cargo build failed. Build log:" >&2
  cat "$LOG" >&2
  exit 1
fi
BIN="$CRATE_DIR/target/debug/igweb-serve"

"$BIN" --host-config "$HOST_CFG" --addr 127.0.0.1:0 --max-requests 4 "$APP_DIR" >"$LOG" 2>&1 &
SERVER_PID=$!

PORT=""
for _ in $(seq 1 60); do
  PORT="$(grep -oE 'listening http://127\.0\.0\.1:[0-9]+' "$LOG" 2>/dev/null | head -1 | grep -oE '[0-9]+$' || true)"
  [[ -n "$PORT" ]] && break
  # If the server died during startup (e.g. DSN connect failure), stop waiting.
  kill -0 "$SERVER_PID" >/dev/null 2>&1 || break
  sleep 0.5
done
if [[ -z "$PORT" ]]; then
  echo "FAIL: server did not report a listening port. Server log:" >&2
  cat "$LOG" >&2
  exit 1
fi
BASE="http://127.0.0.1:$PORT"
echo "todo_postgres_smoke: serving on $BASE (bounded to 4 loopback requests)"

# ── 4. Drive exactly four requests, in order: read found, read empty, write, replay ────────────────
post_args=(-X POST -H "Authorization: Bearer $IGNITER_TODO_EFFECT_TOKEN" -H "idempotency-key: $WRITE_KEY" --data "\"$WRITE_TITLE\"")
code_found="$(curl -s -o "$BODY" -w '%{http_code}' "$BASE/accounts/$ACCT/todos" || echo ERR)"
found_body="$(cat "$BODY" 2>/dev/null || true)"
code_empty="$(curl -s -o /dev/null -w '%{http_code}' "$BASE/accounts/$ACCT_EMPTY/todos" || echo ERR)"
code_write="$(curl -s -o /dev/null -w '%{http_code}' "${post_args[@]}" "$BASE/accounts/$ACCT/todos" || echo ERR)"
code_replay="$(curl -s -o /dev/null -w '%{http_code}' "${post_args[@]}" "$BASE/accounts/$ACCT/todos" || echo ERR)"

# The server is bounded to 4 requests; it exits on its own after the replay response.
wait "$SERVER_PID" 2>/dev/null || true
SERVER_PID=""

# ── 5. DB truth: exactly one business row + one receipt for the written key (replay = no 2nd row) ───
n_row="$(psql_dsn -qtAc "SELECT count(*) FROM todos WHERE id='$WRITE_KEY';" | tr -d '[:space:]')"
n_rcpt="$(psql_dsn -qtAc "SELECT count(*) FROM effect_receipts WHERE business_key='$WRITE_KEY';" | tr -d '[:space:]')"
db_title="$(psql_dsn -qtAc "SELECT title FROM todos WHERE id='$WRITE_KEY';" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

# ── 6. Receipt ─────────────────────────────────────────────────────────────────────────────────────
pass=1
chk() { # label expected actual
  if [[ "$2" == "$3" ]]; then printf '  PASS  %-26s %s\n' "$1" "$3"
  else printf '  FAIL  %-26s expected=%s actual=%s\n' "$1" "$2" "$3"; pass=0; fi
}
echo "todo_postgres_smoke: results"
chk "read found -> 200"        200 "$code_found"
if grep -q "$TODO_SEED" <<<"$found_body"; then
  printf '  PASS  %-26s %s\n' "read found body has seed" "$TODO_SEED"
else
  printf '  FAIL  %-26s seed=%s\n' "read found body has seed" "$TODO_SEED"; pass=0
fi
chk "read empty -> 404"        404 "$code_empty"
chk "write -> 200"             200 "$code_write"
chk "replay same key -> 200"   200 "$code_replay"
chk "business row committed"   1   "$n_row"
chk "effect receipt written"   1   "$n_rcpt"
chk "create body -> db title"  "$WRITE_TITLE" "$db_title"

if [[ "$pass" == 1 ]]; then
  echo "todo_postgres_smoke: PASS"
  exit 0
else
  echo "todo_postgres_smoke: FAIL — server log:" >&2
  cat "$LOG" >&2
  exit 1
fi
