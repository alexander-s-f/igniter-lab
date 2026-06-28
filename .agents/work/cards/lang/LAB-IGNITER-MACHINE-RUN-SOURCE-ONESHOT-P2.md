# LAB-IGNITER-MACHINE-RUN-SOURCE-ONESHOT-P2

Status: CLOSED (2026-06-28)
Route: standard / igniter-lab / runtime / igniter-machine / source-run DX
Skill: idd-agent-protocol

## Goal

Close the remaining A23 DX gap with a non-interactive one-shot source-run command that reuses the
existing `IgniterMachine::load_contract_source` + `dispatch` path.

The earlier readiness pass overturned the old audit claim that REPL/source-run was missing:
`igniter-repl --script` already exercises real machine functionality headlessly. What remains is a
simple command for "run this `.ig` contract with this JSON input and print JSON output" without
writing a REPL script.

## Current Authority

Live source wins over this card if it has moved.

Read first:

- `lab-docs/lang/lab-igniter-vm-source-run-repl-readiness-p1-v0.md`
- `runtime/igniter-machine/src/machine.rs`
- `runtime/igniter-machine/src/bin/repl.rs`
- `runtime/igniter-machine/tests/repl_headless_smoke_tests.rs`
- any current `runtime/igniter-machine/Cargo.toml` binary/feature definitions

Known live facts:

- `IgniterMachine::load_contract_source(source, entry)` parses/classifies in-memory source.
- `IgniterMachine::dispatch(contract, json)` dispatches any registered contract async.
- `igniter-repl` is gated behind feature `repl` and already has `--script` headless tests.

## Requirements

- Add the smallest one-shot CLI surface under the existing machine-owned binary surface.
- Prefer extending `igniter-repl` only if that is the smallest coherent CLI home; otherwise create a
  clearly named machine binary. Verify before choosing.
- The command must accept:
  - source file path,
  - entry/contract name,
  - JSON input, either inline or file-based.
- It must print machine dispatch output as JSON and exit 0 on success.
- It must fail non-zero with a clear diagnostic on parse/classify/runtime/input JSON errors.
- It must remain pure dispatch: no capability host, no Postgres, no passport shortcut, no dynamic
  dispatch hack.
- Do not attempt to unify with `igc run` in this card.

## Acceptance

- [x] One-shot command runs a simple `.ig` contract and prints JSON output.
- [x] One-shot command runs a contract from a multi-contract source file by name.
- [x] Input JSON object crosses into contract inputs with current machine semantics.
- [x] Bad JSON fails non-zero and names the input problem.
- [x] Bad source/classification fails non-zero and names the compiler/classifier problem.
- [x] Unknown entry/contract fails non-zero.
- [x] Existing `--script` REPL tests remain green.
- [x] Default/no-feature behavior remains consistent with the current binary feature gate.
- [x] `git diff --check` clean.

## Report (2026-06-28)

Implemented the smallest coherent CLI home: `igniter-repl --run <source.ig> <ContractName>
<json|@file>`, behind the existing `repl` feature and binary gate. The path is pure in-memory machine
dispatch: read source, `IgniterMachine::new(None, "in_memory")`, `load_contract_source`, parse JSON,
`dispatch`, print only result JSON to stdout. No capability host, Postgres, passport shortcut,
`.igapp` artifact, dynamic dispatch, or `igc run` unification.

Tests added to `repl_headless_smoke_tests.rs`: simple success, multi-contract contract selection,
`@file` input, bad JSON, bad source, unknown contract. Existing `--script` headless tests remained
green. Proof packet: `lab-docs/lang/lab-igniter-machine-run-source-oneshot-p2-v0.md`.

## Suggested Verification

```bash
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab

cargo test -p igniter-machine --features repl --test repl_headless_smoke_tests
cargo test -p igniter-machine --features repl
git diff --check
```

Use the actual package/test commands if the workspace has drifted, and record them exactly in the
proof packet.

## Required Packet

Create:

```text
lab-docs/lang/lab-igniter-machine-run-source-oneshot-p2-v0.md
```

Packet must include:

- final CLI syntax,
- examples for success/failure,
- feature-gate decision,
- proof that the implementation reuses `load_contract_source` + `dispatch`,
- explicit deferral of `igc run` / unified `igniter run`.
