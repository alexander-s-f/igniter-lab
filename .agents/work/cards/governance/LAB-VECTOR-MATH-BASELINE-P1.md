# Agent Card: LAB-VECTOR-MATH-BASELINE-P1

**Lane:** governance / regression baseline  
**Mode:** FREEZE — no implementation, no source edits  
**Status:** CLOSED — PROVED 83/83 PASS  
**Date closed:** 2026-06-12  
**Proof runner:** `igniter-lab/igniter-view-engine/proofs/verify_lab_vector_math_baseline_p1.rb`  
**Lab doc:** `igniter-lab/lab-docs/governance/lab-vector-math-compilation-baseline-v0.md`

---

## Goal

Freeze `vector_math` as a full Rust multi-file app compilation baseline — proving that
the compiler produces a deterministic, clean output for a known 6-file / 37-contract app.

---

## What Was Proved

| Claim | Result |
|-------|--------|
| Rust compile status ok | PASS |
| All 5 stages ok (parse / classify / typecheck / emit / assemble) | PASS |
| Exactly 6 source units | PASS |
| Exactly 37 contracts | PASS |
| manifest.json exists and valid | PASS |
| semantic_ir_program.json exists and valid | PASS |
| sourcemap.json exists and valid | PASS |
| artifact_hash present and stable (2-run check) | PASS |
| source_hash present and stable (2-run check) | PASS |
| No diagnostics | PASS |
| Liveness counters non-breaching (tc_infer=8, fr_walk=7; limit=1000) | PASS |
| No liveness breaches | PASS |
| Ruby parity gap documented (not failure) | PASS (informational) |

---

## Frozen Baseline Values

```
source_hash:   sha256:14f7a9c13173eee88dc168103f9e44791bb1b3916a1da96dbc39c61b5edd48b5
artifact_hash: sha256:1f9daf1875c1e4dda41f388fce3d866ef096958e1b1a3353999cab28b3daf23c
```

---

## Closed Surfaces

- No vector stdlib promotion
- No numeric semantics change
- No Ruby parity implementation (gap documented)
- No source edits to app files
- No new stdlib import authority

---

## Next Route

Freeze complete. This baseline can be imported into future multi-file regression runners.
If the `vector_math` app is extended, re-freeze under **LAB-VECTOR-MATH-BASELINE-P2**.
