# LAB-AUDIT-FOUNDATION-STATUS-REFRESH-P2

Status: DONE
Route: standard / main-audit / assimilation / status refresh
Skill: idd-agent-protocol

## Goal

Refresh the foundation-audit status after the recent hardening wave so agents no
longer route around stale blockers that are already closed.

This is not a new audit. It is a verify-first assimilation pass over the existing
audit packets and living surface docs.

## Current Authority

Live source, current cards, and package-local `IMPLEMENTED_SURFACE.md` files win
over older audit text.

Read first:

- `lab-docs/igniter-foundation-hardening-roadmap-p1.md`
- `lab-docs/igniter-compiler-core-foundation-audit-p1.md`
- `lab-docs/igniter-vm-core-foundation-audit-p1.md`
- `lab-docs/igniter-stdlib-core-foundation-audit-p1.md`
- `lab-docs/igniter-machine-core-foundation-audit-p1.md`
- `lab-docs/igniter-web-core-foundation-audit-p1.md`
- `lab-docs/igniter-server-core-foundation-audit-p1.md`
- `lab-docs/lang/current-waves-index.md`
- package-local `IMPLEMENTED_SURFACE.md` files

Known recent closures to verify, not assume:

- compiler parser depth / float crash-safety
- VM checked arithmetic / eval depth / collection budget
- Decimal money safety
- render-html `safe_url` C0-control rejection
- machine signed passport data-plane
- IgWeb signed effect passport
- server live-bind gate P31
- VM map-lambda-call_contract parity P1

## Scope

Allowed:

- Update roadmap/status docs to mark closed vs still-open findings.
- Add a compact "closed by" table with card/proof refs.
- Add "still open" next cards only where live source confirms the gap remains.
- Write a proof/update packet if needed.

Closed:

- No code changes.
- No new feature design.
- No broad rewrite of audit docs into history books.
- Do not edit public emergence/home-lab/SparkCRM docs.

## Questions To Answer

1. Which audit blockers are still live after the recent commits?
2. Which audit blockers are closed but still described as open in front-door
   docs?
3. Which next cards are still valid, and which should be retired or renamed?
4. Does `current-waves-index.md` still point agents at stale work?

## Acceptance

- [x] At least the seven source audit packets are checked against live source or
      closed cards.
- [x] `current-waves-index.md` is updated only where stale.
- [x] `igniter-foundation-hardening-roadmap-p1.md` is updated or annotated with
      current closure status.
- [x] New next-card list contains only live, verified gaps.
- [x] No code changes.
- [x] `git diff --check` passes.

## Suggested Verification

```bash
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab
rg -n "Status: DONE|Status: CLOSED" .agents/work/cards/lang | rg "CHECKED|DEPTH|DECIMAL|SIGNED|SAFE-URL|LIVE-BIND|MAP-LAMBDA"
rg -n "safe_url|authorize_bind|verify_passport_signed|OOF-VM-EVAL-DEPTH|MAX_COLLECTION|Decimal" \
  frame-ui server runtime lang -g '*.rs' -g '*.md'
git diff --check
```

## Required Packet

Create if the changes are more than a few lines:

```text
lab-docs/lang/lab-audit-foundation-status-refresh-p2-v0.md
```

## Closing Report

Closed in:

```text
lab-docs/lang/lab-audit-foundation-status-refresh-p2-v0.md
```

Updated front doors:

- `lab-docs/igniter-foundation-hardening-roadmap-p1.md`
- `lab-docs/lang/current-waves-index.md`
- `lang/igniter-vm/IMPLEMENTED_SURFACE.md`
- `runtime/igniter-machine/IMPLEMENTED_SURFACE.md`

Annotated the seven lab foundation audit packets with a 2026-06-27 refresh note.
The old VM/machine fleet HOLD 11/13 route is retired: live recheck is 13/13 OK.
No code files were changed for this card.

Verification:

```text
cargo test --manifest-path runtime/igniter-machine/Cargo.toml --test machine_tests test_machine_fleet_sweep -- --nocapture
git diff --check
```

Results: machine fleet 13/13 OK; `git diff --check` PASS.
