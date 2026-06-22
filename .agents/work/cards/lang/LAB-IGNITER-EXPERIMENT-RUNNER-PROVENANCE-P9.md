# LAB-IGNITER-EXPERIMENT-RUNNER-PROVENANCE-P9 - stable experiment result lineage

Status: CLOSED
Lane: VM / experiment runner / science reproducibility
Type: implementation proof
Delegation code: OPUS-IGNITER-EXPERIMENT-RUNNER-PROVENANCE-P9
Date: 2026-06-22
Skill: idd-agent-protocol

## Context

The in-process Kuramoto runner and `node_tick` mode are live. Result bundles already contain useful config, summary, series, timings, and reports, but the science repo now needs a stronger result-lineage contract.

The public emergence repo should be able to point at a result and answer:

```text
which kernel source?
which config?
which compiler?
which stdlib?
which runner mode/version?
which package/artifact digest, when available?
```

## Goal

Extend `igniter-vm experiment kuramoto` result bundles with stable provenance fields and tests.

Minimum fields:

- kernel source path as provided plus a stable kernel source digest;
- config digest;
- compiler version;
- stdlib version;
- runner name and runner mode;
- entry contract;
- optional package/admission artifact digest when supplied;
- output bundle schema version.

## Verify first

Read:

- `lang/igniter-vm/src/experiment.rs`
- `lang/igniter-vm/src/main.rs`
- existing Kuramoto runner tests, if any
- `lab-docs/lang/lab-igniter-package-remote-trust-readiness-p22-v0.md`
- `lab-docs/lang/lab-igniter-package-remote-trust-p23*` if present
- private home-lab result bundles only as evidence, not as authority.

Confirm current bundle shape before editing.

## Recommended shape

Add a `provenance` object to `config.json` or a separate `provenance.json`. Prefer one stable JSON shape; do not scatter fields across report prose only.

Example:

```json
{
  "schema": "igniter.experiment.provenance.v1",
  "runner": "igniter-vm experiment kuramoto",
  "runner_mode": "node_tick",
  "entry": "NodeTick",
  "kernel_digest": "...",
  "config_digest": "...",
  "compiler_version": "...",
  "stdlib_version": "...",
  "artifact_digest": null
}
```

## Acceptance

- [x] New provenance fields are emitted for both `all_to_all_tick` and `node_tick` modes.
- [x] Re-running the same config yields identical provenance digests.
- [x] `series.csv` and scientific values are unchanged except for metadata additions.
- [x] `REPORT.md` names the provenance file/fields.
- [x] A regression test or smoke test proves the provenance shape.
- [x] No network, remote host, DB, package registry, or scientific claim changes.
- [x] `cargo test` for the touched crate/target is green.
- [x] `git diff --check` clean.

## Closed scope

No new experiment model, no package packing, no remote execution, no public repo edits, no plotting/UI.

## Next

Consume `artifact_digest` from package admission once `LAB-IGNITER-PACKAGE-EMERGENCE-PACK-P24` lands.

## Closing report

Implemented stable result lineage for `igniter-vm experiment kuramoto`.

New bundle artifact:

```text
provenance.json
```

Fields: schema, runner, runner_mode, entry, kernel_source, kernel_digest, config_digest, compiler_version,
stdlib_version, artifact_digest. `REPORT.md` now names `provenance.json` and includes a provenance table.
`series.csv` and scientific values are not touched by the change path; this is metadata-only at bundle level.

Verification:

```text
lang/igniter-vm cargo test provenance         -> 3 passed
lang/igniter-vm cargo test experiment::tests  -> 10 passed
git diff --check                              -> clean
```

No network, DB, package registry, remote host, plotting/UI, package packing, or scientific claim changes.
Proof doc: `lab-docs/lang/lab-igniter-experiment-runner-provenance-p9-v0.md`.
