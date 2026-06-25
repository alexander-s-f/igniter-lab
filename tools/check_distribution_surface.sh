#!/usr/bin/env bash
# check_distribution_surface.sh — fast anti-rot guard that the documented distribution / control-center
# surface is LIVE. LAB-DISTRIBUTION-DOC-GUARD-HYGIENE-P38.
#
# Purpose: a future agent who greps an old "reserved / deferred / placeholder" proof card can run ONE
# command to confirm what `bin/igniter` actually does today (P33-P35: `igniter env`, the agent `env_*`
# tools, `igniter app admit`). It starts from the front-door doc (NOT old proof prose) + runs bounded,
# DB-free, secret-free live checks. Old historical docs are never read, so they can never make this fail.
#
# Usage:  tools/check_distribution_surface.sh [--with-tests]
#           --with-tests  also run the bounded, DB-free smoke suites (heavier; off by default)
# Exit:   0 = all anchors + live checks green, 1 = a missing anchor / failed live check.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOC="$ROOT/lab-docs/lang/lab-distribution-implemented-surface-v0.md"
IGN="$ROOT/bin/igniter"
pass=1

# 0. start from the front door, not old proof docs
if [[ -f "$DOC" ]]; then
  echo "dist-surface: front door present ok"
else
  echo "dist-surface: front door MISSING: $DOC"; exit 1
fi

# 1. stable anchors that must be named in the front door (current surfaces only; historical docs untouched)
anchors=(
  "igniter env doctor" "igniter env template" "igniter env check"
  "env_doctor" "env_check"
  "igniter app admit" "igniter app bundle" "igniter doctor" "igniter toolchain"
)
for a in "${anchors[@]}"; do
  if grep -qF "$a" "$DOC"; then
    echo "dist-surface: anchor '$a' ok"
  else
    echo "dist-surface: anchor '$a' MISSING from front door"; pass=0
  fi
done

# 2. live command checks — DB-free, secret-free (help text + the structured doctor report)
step() {
  local label="$1"; shift
  if "$@" >/dev/null 2>&1; then echo "dist-surface: $label ok"
  else echo "dist-surface: $label FAILED"; pass=0; fi
}
step "igniter --help"        "$IGN" --help
step "igniter env --help"    "$IGN" env --help
step "igniter app --help"    "$IGN" app --help
step "igniter doctor --json" "$IGN" doctor --json

# 2b. the live CLI (not just the doc) must advertise the P33/P34 env verbs
if "$IGN" env --help 2>&1 | grep -qE "doctor|template|check"; then
  echo "dist-surface: env --help names its verbs ok"
else
  echo "dist-surface: env --help does not name doctor/template/check"; pass=0
fi

# 3. (opt-in) bounded, DB-free smoke suites — proves the LIVE behaviour, not just the help/anchors
if [[ "${1:-}" == "--with-tests" ]]; then
  if ( cd "$ROOT/server/igniter-web" \
       && cargo test --test igniter_env_smoke_tests \
                     --test igniter_agent_mcp_smoke_tests \
                     --test igniter_app_bundle_smoke_tests ) >/dev/null 2>&1; then
    echo "dist-surface: bounded smoke suites ok (env / agent-mcp / app-bundle)"
  else
    echo "dist-surface: bounded smoke suites FAILED"; pass=0
  fi
fi

if [[ "$pass" == 1 ]]; then
  echo "dist-surface: ALL GREEN"
  exit 0
else
  echo "dist-surface: DRIFT DETECTED — front-door doc and live CLI disagree on a P33-P35 surface"
  exit 1
fi
