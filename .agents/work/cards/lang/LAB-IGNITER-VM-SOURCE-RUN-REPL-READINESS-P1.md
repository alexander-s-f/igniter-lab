# LAB-IGNITER-VM-SOURCE-RUN-REPL-READINESS-P1

Status: CLOSED (2026-06-28)
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

- [x] Live compile/load/dispatch paths characterized.
- [x] At least three UX/ownership options compared (A `igc run`, B machine one-shot, C REPL, D unified).
- [x] Dynamic dispatch and capability authority boundaries are explicit.
- [x] One first implementation card named (`LAB-IGNITER-MACHINE-RUN-SOURCE-ONESHOT-P2`).
- [x] No code changes unless explicitly justified (one incidental P8 regression fix — see report).
- [x] Proof/readiness packet created.
- [x] `git diff --check` passes.
- [x] Card is closed with a concise report.

## Report (2026-06-28)

**Verify-first overturned the premise.** A23 / the VM surface doc claimed "source-run / REPL
missing" — stale. `igniter-machine`'s `igniter-repl` (feat `repl`) already compiles `.ig`
**source** in-memory via `load_contract_source` (full front-end) and `dispatch`es, with a
headless `--script` mode proven by `repl_headless_smoke_tests`. The only genuine gap is a
**non-interactive one-shot single command** (`source → result` JSON for CI/scripting).

Decision: A23 LARGELY MET; ship only the thin one-shot. Options compared (full table in packet
§2): A `igc run` (compiler has no runtime → coupling), **B machine-owned `--run`/`run-source`
one-shot (chosen — reuses proven path, pure-dispatch, no deps)**, C REPL (already shipped),
D unified `igniter` (defer). First impl card: `LAB-IGNITER-MACHINE-RUN-SOURCE-ONESHOT-P2`.

Authority boundaries (packet §3): literal/static contract name only (no dynamic dispatch);
no capability/effect auto-grant (REPL machine wires no executor registry → pure dispatch); full
front-end gates preserved (classify/typecheck/OOF run — no bypass).

**Incidental fix (P8 regression, found by this card's own verification).** The card's
`test_machine_fleet_sweep` step ran 12/13: my prior P8 `call_contract` arg-typing rejected
`erp_logistics` because `IgType::structurally_assignable` treated `String`≠`Text`. Fixed
generally with `canonical_scalar_name` (`String`≡`Text`) in `type_ir.rs` (also strengthens
P6/P7). Re-verified 13/13 + full green. Recorded in the P8 packet "P8a follow-up", P8 card, and
board A19.

Doc corrections (verify-first hygiene): `lang/igniter-vm/IMPLEMENTED_SURFACE.md` stale
"REPL missing" rows corrected; board A23 updated; packet
`lab-docs/lang/lab-igniter-vm-source-run-repl-readiness-p1-v0.md` created.

Verification: fleet 13/13; `project_mode_tests` 9/9; compiler suite 0 failures; VM 167/0;
machine 362/0; `git diff --check` PASS.

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
