#!/usr/bin/env bash
# check_implemented_surface.sh — fast guard that the documented IgWeb implemented surface is LIVE.
# LAB-IGNITER-WEB-IMPLEMENTED-SURFACE-GUARD-P33.
#
# Purpose: a future agent who greps an old "deferred / observed only / not implemented" proof doc can
# run ONE command to confirm what the code actually does today. It starts from IMPLEMENTED_SURFACE.md
# (the P31 front door), runs the bounded evidence commands that doc cites, and prints a compact receipt.
#
# Bounded + fast: only machine-gated unit/integration tests + a dependency-tree check. Does NOT require
# IGNITER_TODO_PG_DSN and never touches a live database (the real-Postgres e2e is intentionally out of
# scope here — see IMPLEMENTED_SURFACE.md "Evidence commands" for that). It does not read or grade any
# historical doc, so old proof prose can never make this guard fail.
#
# Usage:  server/igniter-web/scripts/check_implemented_surface.sh
# Exit:   0 = all surface evidence green, 1 = a check failed or the front door is missing.

set -uo pipefail

CRATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SURFACE="$CRATE_DIR/IMPLEMENTED_SURFACE.md"
cd "$CRATE_DIR"

pass=1

# 0. Start from the front door, not old proof docs.
if [[ -f "$SURFACE" ]]; then
  echo "implemented-surface: front door IMPLEMENTED_SURFACE.md present ok"
else
  echo "implemented-surface: IMPLEMENTED_SURFACE.md MISSING — restore it (see card P31)"
  exit 1
fi

# step "<receipt label>" <command...>
step() {
  local label="$1"; shift
  local out
  if out="$("$@" 2>&1)"; then
    echo "implemented-surface: $label ok"
  else
    echo "implemented-surface: $label FAILED"
    printf '%s\n' "$out" | tail -25
    pass=0
  fi
}

# 1. ReadThen staged-read dispatch (found→continuation / empty→404 / denied→403 / raw-sql refused).
step "ReadThen dispatch tests" \
  cargo test --features machine --test readthen_dispatch_tests --quiet

# 2. ReadThen over a real loopback socket (200 / 404 / 403; serve_loop multiple staged reads).
step "socket runner tests" \
  cargo test --features machine --test readthen_socket_runner_tests --quiet

# 3. Final InvokeEffect through MachineEffectHost over a socket (+ replay = no second mutation).
step "effect path (MachineEffectHost) tests" \
  cargo test --features machine --test async_machine_runner_tests --quiet

# 4. Runner startup diagnostics: stable codes + redaction + fail-before-bind.
step "diagnostics tests" \
  cargo test --features machine --test igweb_serve_diagnostics_tests --quiet

# 5. host.toml parser + committed host.example.toml parses (feature-free lib unit tests; run under the
#    machine artifacts already built above to avoid a second compile).
step "host example parses" \
  cargo test --features machine --lib host_config --quiet

# 6. Boundary: the DEFAULT dependency tree must not pull the Postgres driver (postgres is opt-in only).
tree_out="$(cargo tree -e normal 2>/dev/null || true)"
if grep -qi 'tokio-postgres' <<<"$tree_out"; then
  echo "implemented-surface: default tree postgres-free FAILED (tokio-postgres leaked into default build)"
  pass=0
else
  echo "implemented-surface: default tree postgres-free ok"
fi

if [[ "$pass" == 1 ]]; then
  echo "implemented-surface: PASS"
  exit 0
else
  echo "implemented-surface: FAIL"
  exit 1
fi
