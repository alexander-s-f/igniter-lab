#!/usr/bin/env bash
# check_todo_demo_surface.sh — bounded, NO-DB, NO-SOCKET guard for the TodoApp DEMO DX surface.
# LAB-TODOAPP-DEMO-DX-GUARD-P57.
#
# Sibling to check_todo_product_surface.sh, with a DIFFERENT scope:
#   - check_implemented_surface.sh   → the igniter-web RUNNER machinery.
#   - check_todo_product_surface.sh  → the Todo PRODUCT contract (body/idempotency/error/docs).
#   - check_todo_demo_surface.sh     → the DEMO DX (scripts/todo_demo.sh + DEMO.md): the demo
#                                      fails closed on missing/unsafe env BEFORE any socket bind,
#                                      active docs point at the demo path, no committed secrets.
#
# It NEVER touches a live database, NEVER binds a socket, and NEVER requires IGNITER_TODO_PG_DSN /
# IGNITER_TODO_EFFECT_TOKEN. Every demo invocation here is a REFUSAL path (the safety preflight runs
# before cargo build / psql / bind), so the guard is hermetic. The real local-Postgres demo
# (scripts/todo_demo.sh start|smoke|html) stays operator-gated and is NOT run here.
#
# Usage:  server/igniter-web/scripts/check_todo_demo_surface.sh
# Exit:   0 = all demo-DX evidence green, 1 = a check failed.

set -uo pipefail

CRATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$CRATE_DIR"

DEMO="scripts/todo_demo.sh"
APP_DIR="examples/todo_postgres_app"
DEMO_MD="$APP_DIR/DEMO.md"
RUNBOOK_MD="$APP_DIR/RUNBOOK.md"

pass=1
ok()   { echo "todo-demo: $1 ok"; }
bad()  { echo "todo-demo: $1 FAILED${2:+ — $2}"; pass=0; }

# refusal "<label>" <expected_exit> -- ENV... -- <demo args...>
#   Runs the demo with the given env scrubbed/overridden, asserts the exit code, that the output
#   says REFUSED/MISSING, and that it NEVER reached a socket ("serving"/"listening" must be absent).
refusal() {
  local label="$1" want="$2"; shift 2
  local env_args=() ; while [[ "$1" != "--" ]]; do env_args+=("$1"); shift; done; shift
  local out code
  out="$(env "${env_args[@]}" bash "$DEMO" "$@" 2>&1)"; code=$?
  if [[ "$code" -ne "$want" ]]; then
    bad "$label" "exit=$code want=$want :: $(printf '%s' "$out" | tail -1)"
  elif printf '%s' "$out" | grep -qiE 'serving on|listening http'; then
    bad "$label" "reached a socket bind (must refuse before bind)"
  elif printf '%s' "$out" | grep -qiE 'REFUSED|MISSING'; then
    ok "$label"
  else
    bad "$label" "no REFUSED/MISSING line :: $(printf '%s' "$out" | tail -1)"
  fi
}

echo "todo-demo: guarding $DEMO (no DB, no socket) ..."

# 1. Demo script exists and is executable.
if [[ -x "$DEMO" ]]; then ok "demo script exists + executable"; else bad "demo script exists + executable" "$DEMO not -x"; fi

# 2. doctor refuses (exit 1, actionable MISSING) when env is absent. DB-free (no bind).
doctor_out="$(env -u IGNITER_TODO_PG_DSN -u IGNITER_TODO_EFFECT_TOKEN bash "$DEMO" doctor 2>&1)"; doctor_code=$?
if [[ "$doctor_code" -eq 1 && "$doctor_out" == *"MISSING"* ]]; then
  ok "doctor refuses missing prerequisites (exit 1, MISSING)"
else
  bad "doctor refuses missing prerequisites" "exit=$doctor_code"
fi

# 3. start fails closed on MISSING env, BEFORE any socket bind (exit 2).
refusal "start refuses missing DSN/token (exit 2, pre-bind)" 2 \
  -u IGNITER_TODO_PG_DSN -u IGNITER_TODO_EFFECT_TOKEN -- start

# 4. start fails closed on an UNSAFE (spark/prod/production) dbname (exit 2).
refusal "start refuses prod/spark dbname (exit 2, pre-bind)" 2 \
  IGNITER_TODO_PG_DSN=host=localhost\ dbname=spark_prod IGNITER_TODO_EFFECT_TOKEN=t -- start

# 5. start fails closed on a NON-LOOPBACK host (exit 2).
refusal "start refuses non-loopback host (exit 2, pre-bind)" 2 \
  IGNITER_TODO_PG_DSN=host=db.example.com\ dbname=igniter_todo_demo IGNITER_TODO_EFFECT_TOKEN=t -- start

# 6. The other DB-touching verbs also fail closed on missing env (consistency; pre-bind).
refusal "smoke refuses missing env (exit 2)" 2 -u IGNITER_TODO_PG_DSN -u IGNITER_TODO_EFFECT_TOKEN -- smoke
refusal "html refuses missing env (exit 2)"  2 -u IGNITER_TODO_PG_DSN -u IGNITER_TODO_EFFECT_TOKEN -- html
refusal "reset refuses missing env (exit 2)" 2 -u IGNITER_TODO_PG_DSN -u IGNITER_TODO_EFFECT_TOKEN -- reset

# 7. Active docs point at the demo path (not only stale manual steps).
doc_has() { # <label> <file> <fixed marker>
  if grep -qF "$3" "$2"; then ok "$1"; else bad "$1" "expected '$3' in $2"; fi
}
doc_has "DEMO.md drives todo_demo.sh start"  "$DEMO_MD" "todo_demo.sh start"
doc_has "DEMO.md drives todo_demo.sh smoke"  "$DEMO_MD" "todo_demo.sh smoke"
doc_has "DEMO.md drives todo_demo.sh html"   "$DEMO_MD" "todo_demo.sh html"
doc_has "RUNBOOK points to the demo path"    "$RUNBOOK_MD" "DEMO.md"

# 8. No user-facing committed file carries a raw token or inline-secret DSN. Scope = the demo surface
#    that ships to a human: the whole app dir + the demo script + the operator smoke. The CI guard
#    scripts (check_*surface.sh) are tooling, not demo surface, and legitimately quote these patterns,
#    so they are out of scope. Conservative patterns: inline-secret TOML keys, a literal password=,
#    a literal Bearer token. Env-var refs ($IGNITER…/$TOK), placeholders (<token>), *_env keys are OK.
SECRET_TARGETS=("$APP_DIR" "$DEMO" "scripts/todo_postgres_smoke.sh")
secret_hits="$(
  {
    grep -rnE '^[[:space:]]*(dsn|password|secret|token|passport|api_key)[[:space:]]*=' "$APP_DIR" --include='*.toml' 2>/dev/null
    grep -rnE 'password=[^[:space:]"'"'"']' "${SECRET_TARGETS[@]}" 2>/dev/null
    grep -rnE 'Bearer[[:space:]]+[A-Za-z0-9]' "${SECRET_TARGETS[@]}" 2>/dev/null | grep -vE 'Bearer[[:space:]]+(\$|<)'
  } || true
)"
if [[ -z "$secret_hits" ]]; then
  ok "no committed raw token/DSN in app dir or scripts"
else
  bad "no committed raw token/DSN" "see below"
  printf '%s\n' "$secret_hits" | sed 's/^/    /' | head -10
fi

echo "----"
if [[ "$pass" -eq 1 ]]; then
  echo "todo-demo: PASS"
  exit 0
else
  echo "todo-demo: FAIL"
  exit 1
fi
