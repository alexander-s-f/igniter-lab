# lab-igniter-experiment-runner-provenance-p9-v0

**Card:** `LAB-IGNITER-EXPERIMENT-RUNNER-PROVENANCE-P9`  
**Status:** CLOSED (implementation proof)  
**Date:** 2026-06-22

## Summary

Extended `igniter-vm experiment kuramoto` result bundles with a stable `provenance.json` and a provenance
section in `REPORT.md`.

New provenance shape:

```json
{
  "schema": "igniter.experiment.provenance.v1",
  "runner": "igniter-vm experiment kuramoto",
  "runner_mode": "node_tick",
  "entry": "NodeTick",
  "kernel_source": "...",
  "kernel_digest": "...",
  "config_digest": "...",
  "compiler_version": "format/grammar",
  "stdlib_version": "...",
  "artifact_digest": null
}
```

## Implementation

- `lang/igniter-vm/src/experiment.rs`
  - extracts compiler provenance from loaded Semantic IR (`format_version/grammar_version`);
  - records stdlib version via `igniter_stdlib::VERSION`;
  - writes `provenance.json` next to `config.json`, `summary.json`, `series.csv`, and `timings.json`;
  - adds a `REPORT.md` provenance table;
  - tests both `node_tick` and `all_to_all_tick` provenance shape plus digest determinism.
- `lang/igniter-stdlib/src/lib.rs`
  - exposes `pub const VERSION: &str = env!("CARGO_PKG_VERSION");`.

## Verification

```text
cd lang/igniter-vm
cargo test provenance
=> 3 passed

cargo test experiment::tests
=> 10 passed

git diff --check
=> clean
```

The tests prove:

- stable provenance schema for `node_tick`;
- provenance shape for `all_to_all_tick`;
- deterministic digest helper behavior;
- compiler-version extraction from Semantic IR fields;
- fallback to `unknown/unknown` when old SIR lacks version fields.

Warnings seen during test runs are pre-existing crate warnings.

## Closed Scope

No new experiment model, package packing, remote execution, plotting, UI, DB, network, registry, or scientific
claim change. `artifact_digest` is present but remains `null` until package admission identity is wired in a
future slice.

## Next

Wire package admission artifact identity from `LAB-IGNITER-PACKAGE-EMERGENCE-PACK-P24` into experiment
provenance when the runner starts consuming admitted `.igpkg` artifacts.
