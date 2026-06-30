#!/usr/bin/env bash
# todo_demo.sh — 5-minute local DX demo for examples/todo_postgres_app.
# LAB-TODOAPP-DEMO-DX-P55
#
# Commands: doctor | start | smoke | html | status | stop | reset
#
# Quick start:
#   export IGNITER_TODO_PG_DSN="host=localhost user=$USER dbname=igniter_todo_demo"
#   export IGNITER_TODO_EFFECT_TOKEN="dev-token"
#   createdb igniter_todo_demo
#   scripts/todo_demo.sh start
#   scripts/todo_demo.sh smoke
#   scripts/todo_demo.sh html
#   scripts/todo_demo.sh stop
#
# Safety:
#   - Loopback-only. Dedicated local DB only (default: igniter_todo_demo).
#   - Refuses DBs / hosts that look like spark/prod/production.
#   - No DSN or token is echoed in any output.
#   - No production route added. Does not weaken todo_postgres_smoke.sh.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CRATE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_DIR="$CRATE_DIR/examples/todo_postgres_app"
HOST_CFG="$APP_DIR/host.example.toml"
BIN="$CRATE_DIR/target/debug/igweb-serve"

STATE_FILE="/tmp/igniter_todo_demo.state"
LOG_FILE="/tmp/igniter_todo_demo.log"

DEMO_ACCOUNT="acct-demo"
DEMO_ACCOUNT_MISSING="acct-demo-never-seeded"
DEMO_MAX_REQUESTS=500

CMD="${1:-}"

# ── Low-level helpers ────────────────────────────────────────────────────────

die()    { echo "todo_demo: ERROR — $*" >&2; exit 1; }
refuse() { echo "todo_demo: REFUSED — $*" >&2; exit 2; }

extract_dsn_parts() {
  local dsn="${IGNITER_TODO_PG_DSN:-}"
  DSN_HOST="" DSN_DB=""
  if [[ "$dsn" == *"://"* ]]; then
    local u="${dsn#*://}"; local hp="${u#*@}"; local hp="${hp%%/*}"
    DSN_HOST="${hp%%:*}"; local rest="${u#*/}"; DSN_DB="${rest%%\?*}"
  else
    DSN_HOST="$(printf '%s' "$dsn" | grep -oE '(^|[[:space:]])host=[^[:space:]]+' | head -1 | sed 's/.*host=//')"
    DSN_DB="$(printf '%s' "$dsn" | grep -oE '(^|[[:space:]])dbname=[^[:space:]]+' | head -1 | sed 's/.*dbname=//')"
  fi
}

check_dsn_safety() {
  [[ -n "${IGNITER_TODO_PG_DSN:-}"        ]] || refuse "IGNITER_TODO_PG_DSN must be set (a dedicated local DB, e.g. igniter_todo_demo; never production/SparkCRM)."
  [[ -n "${IGNITER_TODO_EFFECT_TOKEN:-}"  ]] || refuse "IGNITER_TODO_EFFECT_TOKEN must be set (a local bearer token; not echoed)."
  extract_dsn_parts
  [[ -n "${DSN_DB:-}" ]] || refuse "could not find 'dbname=' in IGNITER_TODO_PG_DSN (expected key=value conninfo or postgres:// URL)."
  local db_lc; db_lc="$(printf '%s' "$DSN_DB" | tr '[:upper:]' '[:lower:]')"
  case "$db_lc" in
    *spark*|*prod*|*production*) refuse "dbname '$DSN_DB' looks like a production/SparkCRM DB — refusing. Use a dedicated demo DB." ;;
  esac
  if [[ -n "${DSN_HOST:-}" ]]; then
    local h_lc; h_lc="$(printf '%s' "$DSN_HOST" | tr '[:upper:]' '[:lower:]')"
    case "$h_lc" in
      localhost|127.0.0.1|::1|"") : ;;
      *) refuse "host '$DSN_HOST' is not loopback — demo is loopback-only." ;;
    esac
  fi
}

psql_dsn() { psql "$IGNITER_TODO_PG_DSN" -v ON_ERROR_STOP=1 "$@"; }

read_state() {
  [[ -f "$STATE_FILE" ]] || return 1
  # shellcheck source=/dev/null
  source "$STATE_FILE"
}

server_running() {
  DEMO_PID="" DEMO_PORT=""
  read_state 2>/dev/null || return 1
  [[ -n "${DEMO_PID:-}" ]] && kill -0 "$DEMO_PID" 2>/dev/null
}

chk() {
  if [[ "$2" == "$3" ]]; then
    printf '  PASS  %-42s %s\n' "$1" "$3"
  else
    printf '  FAIL  %-42s expected=%s actual=%s\n' "$1" "$2" "$3"
    _SMOKE_PASS=0
  fi
}

# ── doctor ───────────────────────────────────────────────────────────────────

cmd_doctor() {
  echo "todo_demo doctor: checking prerequisites ..."
  local ok=1
  for tool in cargo curl psql; do
    if command -v "$tool" >/dev/null 2>&1; then
      echo "  ok       $tool"
    else
      echo "  MISSING  $tool — install it to continue"
      ok=0
    fi
  done
  if [[ -n "${IGNITER_TODO_PG_DSN:-}" ]]; then
    extract_dsn_parts
    echo "  ok       IGNITER_TODO_PG_DSN set (db=${DSN_DB:-<undetected>}; DSN not echoed)"
    local db_lc; db_lc="$(printf '%s' "${DSN_DB:-}" | tr '[:upper:]' '[:lower:]')"
    case "$db_lc" in
      *spark*|*prod*|*production*)
        echo "  WARN     dbname looks like a production/SparkCRM DB — use a dedicated demo DB"
        ok=0 ;;
    esac
  else
    echo "  MISSING  IGNITER_TODO_PG_DSN — export before running 'start'"
    echo "           example: export IGNITER_TODO_PG_DSN=\"host=localhost user=\$USER dbname=igniter_todo_demo\""
    ok=0
  fi
  if [[ -n "${IGNITER_TODO_EFFECT_TOKEN:-}" ]]; then
    echo "  ok       IGNITER_TODO_EFFECT_TOKEN set (not echoed)"
  else
    echo "  MISSING  IGNITER_TODO_EFFECT_TOKEN — export before running 'start'"
    echo "           example: export IGNITER_TODO_EFFECT_TOKEN=\"dev-token\""
    ok=0
  fi
  if [[ "$ok" == 1 ]]; then
    echo "todo_demo doctor: OK — prerequisites met; next: 'createdb igniter_todo_demo' then './scripts/todo_demo.sh start'"
  else
    echo "todo_demo doctor: prerequisites missing (see above)"
    exit 1
  fi
}

# ── start ────────────────────────────────────────────────────────────────────

cmd_start() {
  check_dsn_safety
  echo "todo_demo start: preflight ok (db=$DSN_DB; DSN/token not echoed)"

  if server_running; then
    echo "todo_demo start: server already running (PID=$DEMO_PID)"
    echo "  BASE=http://127.0.0.1:$DEMO_PORT"
    return 0
  fi

  # Build the real product binary
  echo "todo_demo start: building igweb-serve --features postgres ..."
  ( cd "$CRATE_DIR" && cargo build --quiet --features postgres --bin igweb-serve ) \
    || die "cargo build failed — check output above"

  # Ensure schema + demo account (idempotent DDL)
  echo "todo_demo start: ensuring schema + demo account ..."
  psql_dsn -q >/dev/null <<'SQL'
CREATE TABLE IF NOT EXISTS accounts (
  id   text PRIMARY KEY,
  name text NOT NULL
);
CREATE TABLE IF NOT EXISTS todos (
  id          text PRIMARY KEY,
  account_id  text NOT NULL REFERENCES accounts(id),
  title       text,
  done        text NOT NULL DEFAULT 'false',
  inserted_at timestamptz DEFAULT now()
);
CREATE TABLE IF NOT EXISTS effect_receipts (
  idempotency_key text PRIMARY KEY,
  correlation_id  text,
  target          text NOT NULL,
  business_key    text NOT NULL,
  committed_at    timestamptz NOT NULL DEFAULT now()
);
SQL
  psql_dsn -qtAc "INSERT INTO accounts(id,name) VALUES ('$DEMO_ACCOUNT','Demo') ON CONFLICT DO NOTHING;" >/dev/null

  # Start bounded loopback server (real postgres product path)
  >"$LOG_FILE"
  "$BIN" --host-config "$HOST_CFG" --addr 127.0.0.1:0 \
    --max-requests "$DEMO_MAX_REQUESTS" "$APP_DIR" >"$LOG_FILE" 2>&1 &
  local pid=$!

  local port=""
  for _ in $(seq 1 60); do
    port="$(grep -oE 'listening http://127\.0\.0\.1:[0-9]+' "$LOG_FILE" 2>/dev/null | head -1 | grep -oE '[0-9]+$' || true)"
    [[ -n "$port" ]] && break
    kill -0 "$pid" 2>/dev/null || die "server exited — see $LOG_FILE"
    sleep 0.5
  done
  [[ -n "$port" ]] || die "server did not report a listening port — see $LOG_FILE"

  printf 'DEMO_PID=%s\nDEMO_PORT=%s\n' "$pid" "$port" >"$STATE_FILE"
  echo "todo_demo start: serving on http://127.0.0.1:$port (PID=$pid, max $DEMO_MAX_REQUESTS requests)"
  echo "  BASE=http://127.0.0.1:$port"
}

# ── smoke ────────────────────────────────────────────────────────────────────

cmd_smoke() {
  check_dsn_safety
  server_running || die "server is not running — run 'scripts/todo_demo.sh start' first"
  local BASE="http://127.0.0.1:$DEMO_PORT"
  echo "todo_demo smoke: driving $BASE ..."

  _SMOKE_PASS=1

  local found_body show_body
  found_body="$(mktemp)" show_body="$(mktemp)"
  # shellcheck disable=SC2064
  trap "rm -f '$found_body' '$show_body'" RETURN

  # Unique keys per run (PID + timestamp sub-second) to avoid receipt collisions
  local RUN="${$}-$(date +%s)"
  local CREATE_KEY="demo-smoke-create-$RUN"
  local DONE_KEY="demo-smoke-done-$RUN"
  local DELETE_KEY="demo-smoke-delete-$RUN"
  local CREATE_BODY='{"title":"Demo task — smoke run"}'
  local TOK="$IGNITER_TODO_EFFECT_TOKEN"

  # Reads carry NO client x-correlation-id. Under the app's `trace = true` the host derives a
  # correlation for observability but MARKS it trace-source, so the read host runs each read FRESH —
  # an identical GET after a write observes the new state, never a stale replay
  # (LAB-IGNITER-WEB-TRACE-CORRELATION-READ-FRESHNESS-P58). Read replay stays opt-in for a genuine
  # client retry that sends its OWN x-correlation-id (P23). The earlier P55 unique-correlation-per-read
  # workaround is no longer needed.
  get() { # $1=path  $2=output file (optional)
    curl -s -o "${2:-/dev/null}" -w '%{http_code}' "$BASE$1" || echo ERR
  }

  local c_health c_missing c_empty c_create c_creplay c_found c_show \
        c_done c_dreplay c_delete c_delreplay c_show_gone

  c_health="$(  get "/health" )"
  c_missing="$( get "/accounts/$DEMO_ACCOUNT_MISSING/todos" )"
  c_empty="$(   get "/accounts/$DEMO_ACCOUNT/todos" )"

  c_create="$(  curl -s -o /dev/null -w '%{http_code}' \
                  -H "Authorization: Bearer $TOK" -H "idempotency-key: $CREATE_KEY" \
                  --data "$CREATE_BODY" -X POST "$BASE/accounts/$DEMO_ACCOUNT/todos" || echo ERR)"
  c_creplay="$( curl -s -o /dev/null -w '%{http_code}' \
                  -H "Authorization: Bearer $TOK" -H "idempotency-key: $CREATE_KEY" \
                  --data "$CREATE_BODY" -X POST "$BASE/accounts/$DEMO_ACCOUNT/todos" || echo ERR)"
  c_found="$(   get "/accounts/$DEMO_ACCOUNT/todos" "$found_body" )"

  local TODO_ID
  TODO_ID="$(grep -oE 'todo_[0-9a-f]{32}' "$found_body" | head -1)"
  [[ -n "$TODO_ID" ]] || TODO_ID="__not_discovered__"

  c_show="$(    get "/accounts/$DEMO_ACCOUNT/todos/$TODO_ID" "$show_body" )"
  c_done="$(    curl -s -o /dev/null -w '%{http_code}' \
                  -H "Authorization: Bearer $TOK" -H "idempotency-key: $DONE_KEY" \
                  --data '{}' -X POST "$BASE/accounts/$DEMO_ACCOUNT/todos/$TODO_ID/done" || echo ERR)"
  c_dreplay="$( curl -s -o /dev/null -w '%{http_code}' \
                  -H "Authorization: Bearer $TOK" -H "idempotency-key: $DONE_KEY" \
                  --data '{}' -X POST "$BASE/accounts/$DEMO_ACCOUNT/todos/$TODO_ID/done" || echo ERR)"
  c_delete="$(  curl -s -o /dev/null -w '%{http_code}' \
                  -H "Authorization: Bearer $TOK" -H "idempotency-key: $DELETE_KEY" \
                  --data '{}' -X DELETE "$BASE/accounts/$DEMO_ACCOUNT/todos/$TODO_ID" || echo ERR)"
  c_delreplay="$(curl -s -o /dev/null -w '%{http_code}' \
                  -H "Authorization: Bearer $TOK" -H "idempotency-key: $DELETE_KEY" \
                  --data '{}' -X DELETE "$BASE/accounts/$DEMO_ACCOUNT/todos/$TODO_ID" || echo ERR)"
  c_show_gone="$(get "/accounts/$DEMO_ACCOUNT/todos/$TODO_ID" )"

  local found_has_title=no show_has_title=no
  grep -qF "Demo task" "$found_body" 2>/dev/null && found_has_title=yes
  grep -qF "Demo task" "$show_body"  2>/dev/null && show_has_title=yes
  local id_ok=no; [[ "$TODO_ID" == todo_* ]] && id_ok=yes

  chk "health -> 200"                            200 "$c_health"
  chk "missing account -> 404"                   404 "$c_missing"
  chk "existing acct, no todos -> 200 []"        200 "$c_empty"
  chk "create -> 200"                            200 "$c_create"
  chk "create replay (same key) -> 200"          200 "$c_creplay"
  chk "list after create -> 200"                 200 "$c_found"
  chk "list carries title"                       yes "$found_has_title"
  chk "surrogate todo id discovered"             yes "$id_ok"
  chk "show -> 200"                              200 "$c_show"
  chk "show carries title"                       yes "$show_has_title"
  chk "done -> 200"                              200 "$c_done"
  chk "done replay -> 200"                       200 "$c_dreplay"
  chk "delete -> 200"                            200 "$c_delete"
  chk "delete replay -> 200"                     200 "$c_delreplay"
  chk "show after delete -> 404"                 404 "$c_show_gone"

  # Clean up smoke-owned rows (demo account rows + smoke receipts)
  psql_dsn -q >/dev/null 2>&1 <<SQL || true
DELETE FROM effect_receipts
  WHERE idempotency_key LIKE 'demo-smoke-create-$RUN%'
     OR idempotency_key LIKE 'demo-smoke-done-$RUN%'
     OR idempotency_key LIKE 'demo-smoke-delete-$RUN%';
DELETE FROM todos WHERE account_id = '$DEMO_ACCOUNT';
SQL

  if [[ "$_SMOKE_PASS" == 1 ]]; then
    echo "todo_demo smoke: PASS"
  else
    echo "todo_demo smoke: FAIL — server log: $LOG_FILE"
    exit 1
  fi
}

# ── html ─────────────────────────────────────────────────────────────────────

cmd_html() {
  check_dsn_safety
  server_running || die "server is not running — run 'scripts/todo_demo.sh start' first"
  local BASE="http://127.0.0.1:$DEMO_PORT"
  local URL="$BASE/accounts/$DEMO_ACCOUNT/todos.html"

  _SMOKE_PASS=1

  local body headers
  body="$(mktemp)" headers="$(mktemp)"
  # shellcheck disable=SC2064
  trap "rm -f '$body' '$headers'" RETURN

  local RUN="${$}-$(date +%s)"
  local TOK="$IGNITER_TODO_EFFECT_TOKEN"
  # Seed ONE demo todo whose title carries markup, so the page has a real row + per-row detail
  # link AND the escape check is meaningful (a raw '<script>' in the title must come back as
  # '&lt;script&gt;'). The row is written through the real product write path and removed at the
  # end — the saved artifact keeps the rendered snapshot for human inspection.
  local HTML_TITLE='Demo <script>alert(1)</script> task'
  local SEED_KEY="demo-html-seed-$RUN"
  echo "todo_demo html: seeding one demo todo (title carries markup, to prove escaping) ..."
  curl -s -o /dev/null \
    -H "Authorization: Bearer $TOK" -H "idempotency-key: $SEED_KEY" \
    --data "{\"title\":\"Demo <script>alert(1)</script> task\"}" \
    -X POST "$BASE/accounts/$DEMO_ACCOUNT/todos" || true

  echo "todo_demo html: fetching $URL ..."
  # No client x-correlation-id needed: trace-derived correlations run fresh (see cmd_smoke / P58).
  local code
  code="$(curl -s -D "$headers" -o "$body" -w '%{http_code}' "$URL" || echo ERR)"

  # Persist an openable local artifact (ignored path; see .gitignore '.todo_demo/').
  local ART_DIR="$CRATE_DIR/.todo_demo"
  local ART="$ART_DIR/todos.html"
  mkdir -p "$ART_DIR"
  cp "$body" "$ART" 2>/dev/null || true

  local ct_ok=no
  grep -qi 'content-type:.*text/html' "$headers" 2>/dev/null && ct_ok=yes

  # The renderer always emits structural HTML tags.
  local has_html=no
  grep -qi '<html\|<!doctype\|<body\|<ul\|<li\|<h1\|<p' "$body" 2>/dev/null && has_html=yes

  # Escape proof: the seeded markup title must be ESCAPED (&lt;script&gt;) and the page must
  # carry NO raw executable <script> tag (the renderer is safe-by-construction).
  local escaped=no
  grep -qF '&lt;script&gt;' "$body" 2>/dev/null && escaped=yes
  local no_raw_script=yes
  grep -qi '<script' "$body" 2>/dev/null && no_raw_script=no

  # At least one per-row detail link to the JSON show route (href="/accounts/<acct>/todos/<id>").
  local has_link=no
  grep -qF "href=\"/accounts/$DEMO_ACCOUNT/todos/todo_" "$body" 2>/dev/null && has_link=yes

  chk "HTML route status -> 200"                 200  "$code"
  chk "Content-Type is text/html"               yes  "$ct_ok"
  chk "response contains HTML structure"         yes  "$has_html"
  chk "user content escaped (&lt;script&gt;)"    yes  "$escaped"
  chk "no raw <script> tag (safe renderer)"      yes  "$no_raw_script"
  chk "at least one per-row detail link"         yes  "$has_link"

  # Remove the seeded row + receipt (demo-owned); the saved artifact already captured the render.
  psql_dsn -q >/dev/null 2>&1 <<SQL || true
DELETE FROM effect_receipts WHERE idempotency_key LIKE 'demo-html-seed-$RUN%';
DELETE FROM todos WHERE account_id = '$DEMO_ACCOUNT';
SQL

  echo "todo_demo html: saved artifact → $ART"
  echo "                open: file://$ART"

  if [[ "$_SMOKE_PASS" == 1 ]]; then
    echo "todo_demo html: PASS"
  else
    echo "todo_demo html: FAIL — server log: $LOG_FILE"
    exit 1
  fi
}

# ── status ───────────────────────────────────────────────────────────────────

cmd_status() {
  if server_running; then
    echo "todo_demo status: RUNNING"
    echo "  PID   $DEMO_PID"
    echo "  BASE  http://127.0.0.1:$DEMO_PORT"
    echo "  LOG   $LOG_FILE"
  else
    echo "todo_demo status: NOT RUNNING"
    if [[ -f "$STATE_FILE" ]]; then
      echo "  (stale state file at $STATE_FILE — run 'stop' to clean up)"
    fi
  fi
}

# ── stop ─────────────────────────────────────────────────────────────────────

cmd_stop() {
  if ! read_state 2>/dev/null; then
    echo "todo_demo stop: no state file — nothing to stop"
    return 0
  fi
  if [[ -n "${DEMO_PID:-}" ]] && kill -0 "$DEMO_PID" 2>/dev/null; then
    echo "todo_demo stop: stopping PID=$DEMO_PID ..."
    kill "$DEMO_PID" 2>/dev/null || true
    for _ in $(seq 1 20); do
      kill -0 "$DEMO_PID" 2>/dev/null || break
      sleep 0.3
    done
    # Force if still alive
    kill -0 "$DEMO_PID" 2>/dev/null && { kill -9 "$DEMO_PID" 2>/dev/null || true; }
    echo "todo_demo stop: stopped"
  else
    echo "todo_demo stop: PID=${DEMO_PID:-?} was not running"
  fi
  rm -f "$STATE_FILE"
  echo "todo_demo stop: state cleared (no listener remains)"
}

# ── reset ────────────────────────────────────────────────────────────────────

cmd_reset() {
  check_dsn_safety
  echo "todo_demo reset: removing demo-owned rows from db=$DSN_DB ..."
  psql_dsn -q >/dev/null <<SQL
DELETE FROM effect_receipts WHERE idempotency_key LIKE 'demo-%';
DELETE FROM todos       WHERE account_id = '$DEMO_ACCOUNT';
DELETE FROM accounts    WHERE id         = '$DEMO_ACCOUNT';
SQL
  psql_dsn -qtAc "INSERT INTO accounts(id,name) VALUES ('$DEMO_ACCOUNT','Demo') ON CONFLICT DO NOTHING;" >/dev/null
  echo "todo_demo reset: done (demo account re-seeded; server not touched)"
}

# ── dispatch ─────────────────────────────────────────────────────────────────

case "$CMD" in
  doctor|check) cmd_doctor ;;
  start)        cmd_start  ;;
  smoke)        cmd_smoke  ;;
  html)         cmd_html   ;;
  status)       cmd_status ;;
  stop)         cmd_stop   ;;
  reset)        cmd_reset  ;;
  *)
    echo "Usage: $0 {doctor|start|smoke|html|status|stop|reset}" >&2
    echo "" >&2
    echo "  doctor  check prerequisites" >&2
    echo "  start   build + start the demo server (loopback, dedicated DB)" >&2
    echo "  smoke   drive the API: health/list/create/replay/show/done/delete" >&2
    echo "  html    fetch the HTML route, save an openable artifact, verify text/html + escaping + links" >&2
    echo "  status  print server state (no secrets echoed)" >&2
    echo "  stop    stop the demo server; no listener remains" >&2
    echo "  reset   delete demo-owned rows; re-seed demo account" >&2
    exit 1
    ;;
esac
