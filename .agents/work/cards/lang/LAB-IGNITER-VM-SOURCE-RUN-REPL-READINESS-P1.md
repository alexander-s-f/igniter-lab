# LAB-IGNITER-VM-SOURCE-RUN-REPL-READINESS-P1

Status: OPEN
Route: standard / main-audit / VM-DX / source-run
Skill: idd-agent-protocol

## Goal

Turn audit-control-board row A23 into a concrete DX plan: source-to-run and/or
REPL for Igniter, without sneaking in dynamic dispatch or bypassing compile-time
authority.

This is a readiness card first. The board marks `.igapp` runtime implemented but
direct source-run / REPL missing. The goal is to decide the smallest useful
surface and name the implementation card.

## Current Authority

Live source wins. Read first:

- `lab-docs/lang/lab-audit-control-board-v1.md`
- `runtime/igniter-machine/IMPLEMENTED_SURFACE.md`
- `lang/igniter-vm/IMPLEMENTED_SURFACE.md` if present
- `runtime/igniter-machine/src/` load/dispatch paths
- compiler CLI source/project compile paths under `lang/igniter-compiler/src/`
- existing REPL/headless tests under `runtime/igniter-machine/tests/`

Known facts to re-verify:

- fleet sweep and `.igapp` runtime are green;
- source-run is a DX surface, not an audit-safety blocker;
- dynamic contract dispatch remains governance-gated and must not be smuggled in
  as "REPL convenience".

## Scope

Allowed:

- Produce a readiness packet.
- Compare direct `igc run <source>`, machine `run-source`, and REPL shell
  options.
- Define how entrypoint/contract/input are selected.
- Define what is compiled each turn and what is cached.
- Name the first implementation card.

Closed:

- No implementation unless the live path is trivially ready and explicitly
  bounded.
- No dynamic dispatch governance shortcut.
- No package manager policy changes.
- No server/web changes.
- No public release claim.

## Questions To Answer

1. Which binary should own source-run: `igc`, `igniter-machine`, or future
   `igniter` command center?
2. What is the minimal UX: source file + contract + JSON input, or a session
   REPL?
3. Does source-run compile to `.igapp` in tempdir and then dispatch, or execute
   in-memory artifacts?
4. What security/authority boundaries apply to effects/capabilities?
5. What first implementation card has the best DX payoff with least authority
   risk?

## Acceptance

- [ ] Live compile/load/dispatch paths characterized.
- [ ] At least three UX/ownership options compared.
- [ ] Dynamic dispatch and capability authority boundaries are explicit.
- [ ] One first implementation card named.
- [ ] No code changes unless explicitly justified as readiness helper.
- [ ] Proof/readiness packet created.
- [ ] `git diff --check` passes.
- [ ] Card is closed with a concise report.

## Suggested Verification

```bash
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab
cargo test --manifest-path runtime/igniter-machine/Cargo.toml --test machine_tests test_machine_fleet_sweep
cargo test --manifest-path lang/igniter-compiler/Cargo.toml --test project_mode_tests
git diff --check
```

## Required Packet

Create:

```text
lab-docs/lang/lab-igniter-vm-source-run-repl-readiness-p1-v0.md
```

Packet must include:

- current runnable surfaces;
- UX/ownership options;
- authority boundaries;
- first implementation card.
