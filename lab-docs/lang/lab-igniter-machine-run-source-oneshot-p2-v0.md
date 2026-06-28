# LAB-IGNITER-MACHINE-RUN-SOURCE-ONESHOT-P2

Date: 2026-06-28
Status: DONE
Route: standard / igniter-lab / runtime / igniter-machine / source-run DX
Implements: LAB-IGNITER-MACHINE-RUN-SOURCE-ONESHOT-P2 (follow-on to P1 readiness)

## Headline

Adds `igniter-repl --run <source.ig> <ContractName> <json|@file>` — a non-interactive one-shot
command that compiles a `.ig` source in-memory and dispatches a single contract, printing ONLY
the JSON result to stdout. Exits 0 on success, non-zero with a diagnostic to stderr on any error.

## Final CLI syntax

```
igniter-repl --run <source.ig> <ContractName> <json-string|@path>
```

- `<source.ig>` — path to a `.ig` source file (single or multi-contract).
- `<ContractName>` — exact contract name (literal static lookup, no dynamic dispatch).
- `<json-string|@path>` — inline JSON object, or `@<path>` to read JSON from a file.

## Examples

### Success — simple contract

```bash
# add.ig contains contract Add { input a: Integer; input b: Integer; compute sum = a + b; output sum: Integer }
igniter-repl --run add.ig Add '{"a":19,"b":23}'
# stdout:
42
# exit 0
```

### Success — multi-contract source, select by name

```bash
# multi.ig contains contract Double { … } and contract Triple { … }
igniter-repl --run multi.ig Triple '{"x":7}'
# stdout:
21
# exit 0
```

### Success — input from file

```bash
echo '{"a":100,"b":1}' > inputs.json
igniter-repl --run add.ig Add @inputs.json
# stdout:
101
# exit 0
```

### Failure — bad JSON input

```bash
igniter-repl --run add.ig Add 'not-json{'
# stderr: error: input JSON is invalid: …
# exit 2
```

### Failure — source compile/classify error

```bash
igniter-repl --run broken.ig Broken '{}'
# stderr: error: compile/classify failed for 'Broken': …
# exit 1
```

### Failure — unknown contract

```bash
igniter-repl --run add.ig DoesNotExist '{}'
# stderr: error: dispatch 'DoesNotExist' failed: …
# exit 1
```

## Feature-gate decision

`--run` lives on `igniter-repl` (the same binary, same `repl` Cargo feature). No new feature gate
was introduced. Rationale: `igniter-repl` already carries `load_contract_source` + `dispatch`
semantics under the `repl` feature; extending it is the smallest coherent CLI home, exactly as
decided in P1. A separate `run-source` binary would add a new binary entry + redundant dep graph
with zero benefit at this stage.

## Proof: reuses `load_contract_source` + `dispatch`

`run_oneshot()` in `src/bin/repl.rs`:

1. Reads the source file.
2. Calls `IgniterMachine::new(None, "in_memory")` — pure in-memory, no Postgres, no TLS, no
   capability executor registry.
3. Calls `machine.load_contract_source(&source, contract_name)` — the full front-end pipeline
   (lex → parse → monomorphize → classify → typecheck → emit → assemble → register).
4. Parses the JSON input with `serde_json::from_str`.
5. Calls `futures::executor::block_on(machine.dispatch(contract_name, inputs))`.
6. Prints the result JSON and exits 0.

No capability wiring, no passport shortcut, no dynamic dispatch, no `.igapp` artifact written to
disk. Pure dispatch only.

## Explicit deferral: `igc run` / unified `igniter run`

Shipping a unified `igc run` (Option A in P1) or a unified `igniter` command center (Option D)
remains deferred. Both require new coupling between the compiler crate and the runtime (Option A)
or a new binary entry point with its own sub-command infrastructure (Option D). Neither is
warranted by the A23 gap. The current surface is the smallest correct close.

## Acceptance checklist

- [x] One-shot command runs a simple `.ig` contract and prints JSON output.
- [x] One-shot command runs a contract from a multi-contract source file by name.
- [x] Input JSON object crosses into contract inputs with current machine semantics.
- [x] Bad JSON fails non-zero and names the input problem (stderr: `error: input JSON is invalid`).
- [x] Bad source/classification fails non-zero and names the compiler/classifier problem.
- [x] Unknown entry/contract fails non-zero.
- [x] Existing `--script` REPL tests remain green (3/3 unchanged).
- [x] Default/no-feature behavior consistent — `--run` is gated behind `repl` feature (same gate
      as the binary itself; default build has no `repl` feature).
- [x] `git diff --check` clean.

## Verification run

```text
cargo test --manifest-path runtime/igniter-machine/Cargo.toml --features repl --test repl_headless_smoke_tests

running 9 tests
test run_oneshot_bad_json_fails_nonzero ... ok
test run_oneshot_bad_source_fails_nonzero ... ok
test script_with_bad_command_fails_nonzero ... ok
test script_with_bad_resume_path_fails_nonzero ... ok
test script_exercises_write_checkpoint_resume_roundtrip ... ok
test run_oneshot_unknown_contract_fails_nonzero ... ok
test run_oneshot_prints_result_and_exits_zero ... ok
test run_oneshot_accepts_at_file_input ... ok
test run_oneshot_selects_contract_by_name ... ok

test result: ok. 9 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0.54s

git diff --check → PASS (no whitespace errors)
```
