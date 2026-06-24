#!/usr/bin/env bash
# check_todo_product_surface.sh — bounded, NO-DB CI guard for the examples/todo_postgres_app PRODUCT
# surface. LAB-TODOAPP-API-PRODUCT-SMOKE-CI-P27.
#
# Sibling to check_implemented_surface.sh, with a DIFFERENT scope:
#   - check_implemented_surface.sh  → the igniter-web RUNNER machinery (ReadThen/effect host/diagnostics).
#   - check_todo_product_surface.sh → the Todo PRODUCT contract (body shape, idempotency conflict, error
#                                     contract, list-empty, host-example parse, operator-smoke refusal).
#
# It NEVER touches a live database and NEVER requires IGNITER_TODO_PG_DSN / IGNITER_TODO_EFFECT_TOKEN.
# All proof runs on fake adapters (`--features machine`) + sync/lib tests. The real local-Postgres smoke
# (scripts/todo_postgres_smoke.sh) stays separate and operator-gated — this guard only asserts that the
# smoke *preflight refuses* when no DSN is set (a negative, DB-free check).
#
# Usage:  server/igniter-web/scripts/check_todo_product_surface.sh
# Exit:   0 = all product-surface evidence green, 1 = a check failed.

set -uo pipefail

CRATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$CRATE_DIR"

pass=1

# step "<receipt label>" <command...>  — runs a command, expects exit 0.
step() {
  local label="$1"; shift
  local out
  if out="$("$@" 2>&1)"; then
    echo "todo-product: $label ok"
  else
    echo "todo-product: $label FAILED"
    printf '%s\n' "$out" | tail -25
    pass=0
  fi
}

# 1. Routes compile + body contract (P18) + list-empty 200 [] (P24) + loopback behavior table (sync, no DB).
step "app builds + body contract + list-empty (todo_postgres_app_tests)" \
  cargo test --features machine --test todo_postgres_app_tests --quiet

# 2. Error contract (P20): app-owned 404/405/400 shapes, no DSN/token/SQL leak (sync, no DB).
step "error contract (todo_error_contract_tests)" \
  cargo test --features machine --test todo_error_contract_tests --quiet

# 3. Idempotency conflict (P19) + rejected-body-before-effect-host (fake machine effect host, no DB).
step "idempotency conflict + effect host (todo_postgres_effect_host_tests)" \
  cargo test --features machine --test todo_postgres_effect_host_tests --quiet

# 4. ReadThen fake path: found 200 / empty 200 [] / write committed / replay no-2nd-mutation (no DB).
step "ReadThen + write + replay (todo_postgres_async_runner_smoke_tests)" \
  cargo test --features machine --test todo_postgres_async_runner_smoke_tests --quiet

# 5. host.example.toml parses + parser fail-closed cases (lib unit tests, no DB).
step "host.toml parser + committed host.example.toml (host_config)" \
  cargo test --features machine --lib host_config --quiet

# 6. Operator smoke PREFLIGHT refuses with no DSN — DB-free negative check (expects exit 2 "REFUSED").
#    Env is explicitly cleared so this can never reach a database.
smoke_out="$(env -u IGNITER_TODO_PG_DSN -u IGNITER_TODO_EFFECT_TOKEN \
  bash scripts/todo_postgres_smoke.sh 2>&1)"
smoke_code=$?
if [[ "$smoke_code" -eq 2 && "$smoke_out" == *"REFUSED"* && "$smoke_out" != *"PASS"* ]]; then
  echo "todo-product: operator smoke refuses without DSN (exit 2) ok"
else
  echo "todo-product: operator smoke refuses without DSN FAILED (exit=$smoke_code)"
  printf '%s\n' "$smoke_out" | tail -5
  pass=0
fi

# 7. Doc-contract markers (P41) — DB-free guard that API.md still states the CURRENT product contract and
#    carries no superseded claim. Catches doc drift the test steps above cannot (the docs are the surface
#    agents read). Fixed-string, case-insensitive greps; no DB, no build.
API_MD="examples/todo_postgres_app/API.md"
doc_has() { # <label> <fixed-string marker that MUST be present>
  if grep -qiF "$2" "$API_MD"; then
    echo "todo-product: doc marker [$1] ok"
  else
    echo "todo-product: doc marker [$1] MISSING — expected '$2' in $API_MD"
    pass=0
  fi
}
doc_absent() { # <label> <superseded string that must NOT be present>
  if grep -qiF "$2" "$API_MD"; then
    echo "todo-product: stale doc claim [$1] PRESENT — '$2' in $API_MD"
    pass=0
  else
    echo "todo-product: no stale [$1] ok"
  fi
}
# body contract (P35 object body), id (P36 surrogate), account-existence (P38), error contract (P20),
# delete route (P44), legacy create body removed (P45).
doc_has    "body: object via body_json"  'req.body_json'
doc_has    "id: host surrogate"          'surrogate id'
doc_has    "account-existence 404"       'account not found'
doc_has    "error contract table"        'Error contract'
doc_has    "delete route"                'DELETE /accounts'
doc_has    "legacy create body removed"  'Legacy v0 (REMOVED)'
doc_has    "keyset pagination"           'Keyset pagination'
# superseded claims that must never creep back in.
doc_absent "stale P18 string-only body"  'must be a non-empty JSON string title'
doc_absent "stale idem-key-as-id"        'create key = idempotency'
doc_absent "stale legacy body accepted"  'legacy non-empty JSON string) | accepted'

echo "----"
if [[ "$pass" -eq 1 ]]; then
  echo "todo-product: PASS"
  exit 0
else
  echo "todo-product: FAIL"
  exit 1
fi
