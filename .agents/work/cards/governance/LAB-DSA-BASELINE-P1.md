# LAB-DSA-BASELINE-P1 — DSA Regression Baseline

**Track:** lab / regression baseline
**Route:** BASELINE PROOF ONLY / NO IMPLEMENTATION
**Status:** CLOSED — PROVED 81/81 PASS
**Date:** 2026-06-12
**Predecessor:** LAB-APP-PRESSURE-ROLLUP-P1 (recommended this card)

---

## Decision: PROVED — Baseline Frozen

DSA is frozen as a Rust full-pipeline regression baseline for collection/algorithm workloads.

---

## Proof Result

| Metric | Baseline Value |
|--------|---------------|
| status | ok |
| source units | 6 |
| contracts | 12 |
| stages | parse ok / classify ok / typecheck ok / emit ok / assemble ok |
| diagnostics | 0 |
| source_hash | `sha256:06afdd6e758f3c687af95051f54b69689709cdbc9c75642c66044a16b029e490` |
| artifact_hash | `sha256:7afc3a520876f01e94a0d5b8ff6fc5eba2cad86a43a46170f41fee9104580310` |
| proof checks | 81/81 PASS |

---

## Proof Matrix

| Section | Topic | Checks |
|---------|-------|--------|
| A | Preconditions | 7 |
| B | Compilation status | 4 |
| C | Pipeline stages | 6 |
| D | Source units | 10 |
| E | Contracts | 8 |
| F | Artifact files | 8 |
| G | Hash stability (2 runs) | 9 |
| H | Semantic IR integrity | 6 |
| I | Sourcemap | 3 |
| J | Array literals (DSA-P02) | 5 |
| K | Collection concat compiles (DSA-P03 note) | 4 |
| L | Ruby parity gap | 4 |
| M | Manifest metadata | 7 |
| **Total** | | **81** |

---

## Key Findings

### Array Literals as Collection[T] Proved (DSA-P02)

Five `array_literal` SIR nodes across RunArrayExample, RunSetExample, RunGraphExample,
RunStringExample, and SetInsert. All compile without diagnostic. Array literal syntax is
a valid Collection[T] constructor in Rust without bootstrapping via empty/append.

### Collection Concat Compiles — Semantic Mislabeling Documented (DSA-P03)

`concat(s.elements, [new_elem])` in SetInsert compiles with zero diagnostics, but SIR
emits `"fn": "stdlib.text.concat"` with `"resolved_type": {"name": "Text"}`. The call
is accepted as text concat, not collection concat. This is a semantic gap, not a
compilation failure. Route: `LANG-STDLIB-COLLECTION-CONCAT-P1`.

### Ruby Status Documented as Parity Pressure

Ruby CompilerOrchestrator emits `JSON::GeneratorError: "\xE2" on US-ASCII` on the
UTF-8 box-drawing characters in `types.ig` comments. This blocks Ruby before semantic
analysis. Semantic parity gaps (call_contract × 9, == × 6) are documented in
`dsa/report.md`. Neither gap affects the Rust baseline.

---

## Deliverables

| Artifact | Location |
|----------|----------|
| Proof runner | `igniter-lab/igniter-view-engine/proofs/verify_lab_dsa_baseline_p1.rb` |
| Lab doc | `igniter-lab/lab-docs/governance/lab-dsa-compilation-baseline-v0.md` |
| Agent card | this file |
| Portfolio entry | `igniter-lab/.agents/portfolio-index.md` |

---

## Closed Surfaces

- No DSA stdlib promotion
- No indexed access implementation
- No Ruby parity implementation
- No source edits (all app files read-only)
- No new stdlib inventory entries

---

## Next Routes

- `LANG-STDLIB-COLLECTION-CONCAT-P1` — collection vs text concat disambiguation (DSA-P03)
- `LANG-STDLIB-TEXT-EQUALITY-P1` — Integer == parity in Ruby (DSA-P04)
- `LANG-STDLIB-IS-EMPTY-PROP-P2/P3` — Set semantics gate (DSA-P05)
- `LAB-STDLIB-FIND-ONE-P1` — scalar extraction (DSA-P06)
