# LAB-IGNITER-VM-SOURCE-RUN-REPL-READINESS-P1

Date: 2026-06-28
Status: DONE (readiness)
Route: standard / main-audit / VM-DX / source-run
Implements: audit-control-board row A23 (VM direct source-run / REPL) — readiness/decision

Lab evidence + DX decision. No dynamic-dispatch governance shortcut, no package-manager policy
change, no server/web change, no public release claim. One **incidental code fix** was made
(not the source-run feature): a `String`/`Text` assignability bug that P1's verify-first surfaced
in the machine fleet sweep — see §6.

## Headline (verify-first overturns "REPL missing")

A23 / the VM surface doc say "single `source → run` command / REPL ❌ missing". **This is
stale.** Live source shows a working REPL that compiles `.ig` **source** in-memory and
dispatches — plus a headless script mode:

- `runtime/igniter-machine/src/bin/repl.rs` → binary **`igniter-repl`** (feature `repl`): an
  interactive TUI workspace. `load <path.ig> [Name]` calls
  `IgniterMachine::load_contract_source(src, name)` — the **full front-end in-process**
  (lex → parse → monomorphize → classify → typecheck → emit → assemble → register); `dispatch
  <Name> [json]` executes; plus `facts/write/history/contracts/observations/checkpoint/resume/
  backend`, command history, tab-complete.
- The same binary has a **headless `--script <file>`** mode (P20): runs a file of REPL
  commands non-interactively, prints `OK`/`ERROR`/`SCRIPT OK|FAILED`, exits nonzero on error.
  Proven by `tests/repl_headless_smoke_tests.rs` (load+dispatch+write+checkpoint+resume
  round-trip; bad-command → nonzero).

So the real gap is narrower than "no source-run": there is **no clean, non-interactive,
single-command one-shot** `source → result` that prints just the result JSON for CI/scripting
(today you write a 2-line REPL `--script`).

## 1. Current runnable surfaces (characterized, file:line)

| Surface | Owner binary | Input | How | Anchor |
| --- | --- | --- | --- | --- |
| Compiled one-shot run | `igniter-vm` | a compiled **`.igapp` dir** (`semantic_ir_program.json` + `manifest.json`) | `igniter-vm run --contract <app.igapp> --inputs in.json [--entry N] [--as-of T] [--json]` | `lang/igniter-vm` `main.rs`; surface doc Runtime table |
| Trace / bytecode map | `igniter-vm` | `.igapp` | `igniter-vm trace …` / `igniter-vm bytecode-map …` | same |
| Source → `.igapp` (compile) | `igniter-compiler` (`igc`) | `.ig` source(s) | `igc compile <sources…> --out <app.igapp>` (+ `package graph|pack|verify|admit`); **no `run`** | `lang/igniter-compiler/src/main.rs` |
| Source → in-memory registered contracts | `igniter-machine` (lib) | `.ig` **source** string | `IgniterMachine::load_contract_source(src, name)` → full front-end → register; `dispatch(name, inputs)` executes | `runtime/igniter-machine/src/machine.rs:99,302`; surface "compile + load source ✅" |
| Interactive REPL | `igniter-repl` (feat `repl`) | `.ig` source files, JSON inputs | `load`/`dispatch`/facts/write/checkpoint/resume/backend TUI | `runtime/igniter-machine/src/bin/repl.rs` |
| Headless script | `igniter-repl --script <f>` | a file of REPL commands | runs commands, OK/ERROR + exit code | `repl.rs::run_script`; `tests/repl_headless_smoke_tests.rs` |

Baseline green (this session): machine fleet sweep **13/13**, `project_mode_tests` 9/9, VM
suite 167/0, machine suite 362/0, compiler suite 0 failures.

## 2. UX / ownership options compared

| # | Option | Owner | UX | Compile model | Pros | Cons |
| --- | --- | --- | --- | --- | --- | --- |
| A | `igc run <src> <Contract> <json>` | `igniter-compiler` | one-shot | compile to temp `.igapp`, then run | single front-end home | compiler has **no runtime** — must link VM/machine or shell to `igniter-vm run`; new coupling/deps |
| B | `run-source <file.ig> <Contract> <json>` (non-interactive one-shot) | `igniter-machine` | one-shot, machine-readable stdout | **in-memory** `load_contract_source` + `dispatch` (tempdir-internal, no user `.igapp`) | reuses the **proven** path; no new deps; pure-dispatch; closes the CI/scripting gap | lives on the machine binary, not literally "vm" |
| C | REPL shell | `igniter-machine` (`igniter-repl`) | interactive session **+ `--script`** | in-memory `load_contract_source` + `dispatch` | **already shipped**; live workspace, facts/checkpoint | not a clean one-shot; `--script` is command-oriented + verbose; needs `repl` feature (ratatui/crossterm) |
| D | Unified `igniter` command center | new binary | sub-commands | delegates | clean long-term home | new binary infra; out of scope now |

`igniter-vm` is a poor owner for *source*-run: it deliberately consumes compiled `.igapp` and
does **not** depend on the front-end (parse/classify/typecheck live in `igniter-compiler`);
adding source compile would pull the whole front-end into the runtime crate. `igniter-machine`
already depends on the front-end (that is exactly what `load_contract_source` uses).

## 3. Authority boundaries

- **Dynamic dispatch stays gated.** `dispatch`/`call_contract` resolve a **literal/static**
  contract name against the registry; there is no dynamic dispatch (`rule_engine` stays
  fail-closed; recursive self-call/TCO on hold). A one-shot must take a literal contract name
  (static lookup) — it must not become a "REPL convenience" backdoor to dynamic dispatch.
- **Capabilities/effects are not auto-granted.** The REPL's `IgniterMachine` has **no**
  `CapabilityExecutorRegistry` / passport wired, so `dispatch` runs the contract's pure
  computation only; an effectful/capability-IO contract would be observed/unbound, never
  silently executed. A one-shot must keep this — **pure dispatch only**; effectful runs require
  explicit capability wiring (a separate, gated surface), never an implicit grant.
- **Compile-time authority is preserved, not bypassed.** Source-run goes through the FULL
  front-end (`classify` must be `ok`, `typecheck` must be `ok`, OOF gates fire) before any
  execution. (This is precisely why P1's verify-first surfaced the P8 `String`/`Text` bug — the
  real front-end runs on real app sources; see §6.)

## 4. In-memory vs `.igapp`

`load_contract_source` compiles **in-memory** but internally assembles into a tempdir and
resumes — the user never manages a `.igapp`. Option B is in-memory (tempdir-internal); Option A
would materialize a temp `.igapp` then `igniter-vm run` it. For a one-shot, in-memory (B) is
simpler and leaves no artifact to clean up.

## 5. Decision + first implementation card

**Decision:** A23 is **largely already met** (interactive REPL + headless `--script`, both
source-compiling and gated). Correct the stale "REPL missing" claim and ship only the thin
missing ergonomic: a non-interactive one-shot. Choose **Option B** (machine-owned) — best DX
payoff, least authority risk, least new surface. Defer `igc run` (Option A) and the unified
`igniter` command center (Option D).

First implementation card:

```text
LAB-IGNITER-MACHINE-RUN-SOURCE-ONESHOT-P2
  Goal: a non-interactive one-shot `source → result` for CI/scripting.
  Shape: `igniter-repl --run <file.ig> <Contract> <json>` (or a sibling `run-source` subcommand)
    that reuses load_contract_source + dispatch, prints ONLY the result JSON to stdout, and exits
    nonzero with a coded message on compile/dispatch error.
  Allowed: thin arg-parse + reuse of the existing in-memory path; unit/subprocess tests; correct
    the VM IMPLEMENTED_SURFACE row.
  Closed: no dynamic dispatch (literal contract name, static registry lookup); no capability/effect
    auto-grant (pure dispatch only); no `.igapp` user artifact; no igc/runtime coupling; no new deps
    beyond the existing `repl` feature; no public release claim.
```

## 6. Incidental fix found by verify-first (P8 regression)

Running the card's own verification (`test_machine_fleet_sweep`) showed **12/13**, not the
surface doc's 13/13. The failing app was `erp_logistics`, rejected by the **P8 `call_contract`
arg-typing** check I added in `LAB-IGNITER-COMPILER-CALL-CONTRACT-ARG-TYPING-P8`:

```
call_contract: callee 'MakeWarehouse' parameter 'id' expects Text, got String
```

Root cause: `IgType::structurally_assignable` compared scalar names raw, so `String` (string
literal tag) was not assignable to `Text` (declaration scalar) — yet they are the **same**
scalar (existing code already treats the `"String"`/`"Text"` literal tags interchangeably,
`stdlib_calls.rs:2750`). P8's verification (compiler suite + igweb lowering) did not exercise a
real app passing string literals to `Text` `call_contract` inputs; the machine fleet sweep did.

Fix (correct, general — also strengthens P6 `def`-calls and P7 record-literal field typing):
added `canonical_scalar_name` in `type_ir.rs` so `String` canonicalizes to `Text` in
`structurally_assignable`. Re-verified: fleet sweep **13/13**, P8 arg-typing tests still pass
(genuine wrong types — `String` vs `Float` — still rejected), compiler 0 failures, VM 167/0,
machine 362/0. Recorded as a P8 follow-up (`…-call-contract-arg-typing-p8-v0.md` addendum) and
on board A19.

## Verification run

```text
cargo test --manifest-path runtime/igniter-machine/Cargo.toml --test machine_tests test_machine_fleet_sweep   # 13/13 OK
cargo test --manifest-path lang/igniter-compiler/Cargo.toml --test project_mode_tests                          # 9/9
cargo test --manifest-path lang/igniter-compiler/Cargo.toml                                                    # 0 failures
cargo test --manifest-path lang/igniter-vm/Cargo.toml                                                          # 167/0
cargo test --manifest-path runtime/igniter-machine/Cargo.toml                                                  # 362/0
git diff --check                                                                                               # PASS
```
