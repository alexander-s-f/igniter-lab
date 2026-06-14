# LAB-AIR-COMBAT-ENTRYPOINT-REBASELINE-v0

**Status:** CLOSED -- PROVED (115/115 PASS)  
**Route:** lab / app baseline / air_combat rebaseline after entrypoint  
**Date:** 2026-06-14  
**Authority:** evidence rebaseline only; no implementation

---

## Executive Summary

`air_combat` remains a positive dual-toolchain lab baseline after the source-level
`entrypoint RunDuel` refactor.

The refactor is metadata/control-surface only: it names the default program
selector for tooling. It does not introduce runtime execution authority, rich run
profiles, ServiceLoop runtime work, IO, or app-source migration.

## Verification Results

| Metric | Value |
|---|---|
| Ruby | `ok` / 0 diagnostics |
| Rust | `ok` / 0 diagnostics |
| source files | 8 |
| types | 9 |
| contracts | 31 |
| call_contract sites | 61, all PascalCase string literals |
| fold sites | 6 |
| map / filter sites | 2 / 2 |
| entrypoint | `RunDuel` |
| source_hash | `sha256:b3c2bdd046475442d1b78705fbcb9bfda55da09b070df93a3d36ff8f825b0c55` |

## Hash Drift Note

The dispatch card listed:

```text
sha256:8b698e66d8635f83306d209c702f7231c8184b1e6ffddb8a63f3a147ed9600f8
```

Live P2 evidence from both Ruby and Rust compilers now agrees on:

```text
sha256:b3c2bdd046475442d1b78705fbcb9bfda55da09b070df93a3d36ff8f825b0c55
```

The `8b698e...` value is therefore superseded by this rebaseline. The app `.ig`
files have no git diff in P2; the rebaseline updates evidence metadata only.

## Entrypoint Evidence

Source:

```igniter
entrypoint RunDuel
```

Rust manifest:

- `entrypoint.kind`: `default_entrypoint`
- `entrypoint.declared_target`: `RunDuel`
- `entrypoint.resolved_contract`: `RunDuel`
- `entrypoint.contract_path`: `contracts/run_duel.json`

Ruby and Rust SemanticIR both carry `RunDuel` as the program entrypoint. `TrackBogey`
remains a normal contract and is routed to future named run-profile pressure rather
than a second bare entrypoint.

## Pressure Routing

AC-P01..AC-P10 are preserved.

- AC-P01 / AC-P02 / AC-P03 remain fold-to-struct and fold-over-state pressure.
- AC-P05 remains entity/state-threading pressure.
- AC-P06 remains intentional fail-closed dynamic dispatch pressure.
- AC-P07 remains stdlib math pressure.
- AC-P08 remains IO membrane pressure.
- AC-P09 remains ServiceLoop / PROP-037 direction pressure.
- AC-P10 routes to PROP-029 rich named run profiles, not host-loop config.

## Proof

Runner:

```text
/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-view-engine/proofs/verify_lab_air_combat_baseline_p2.rb
```

Command:

```bash
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab
ruby igniter-view-engine/proofs/verify_lab_air_combat_baseline_p2.rb
```

Result:

```text
RESULT: 115/115 PASS  |  0 FAIL
```

The runner uses `Open3.capture3` and fresh `Dir.mktmpdir` package output paths.
It does not pipe compiler stdout through a truncating consumer.

## Closed Surfaces

- No compiler changes.
- No `.ig` app source migration.
- No rich entrypoint / named profile implementation.
- No ServiceLoop runtime work.
- No IO/runtime/capability work.
- No dynamic dispatch widening.
- No host-loop configuration.
