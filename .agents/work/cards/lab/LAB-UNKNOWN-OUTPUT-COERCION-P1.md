# LAB-UNKNOWN-OUTPUT-COERCION-P1 — Unknown / Collection[Unknown] Output Boundary Safety Proof

**Track:** lab / safety  
**Route:** SAFETY PROOF / GAP DOCUMENTATION  
**Status:** CLOSED — PROVED 36/36 — HOLD / SAFETY-HIGH  
**Date:** 2026-06-12  
**Predecessors:** LANG-STDLIB-TEXT-EQUALITY-P3, LAB-RACK-P6

---

## Goal

Prove whether `Unknown` / `Collection[Unknown]` can silently cross a typed output
boundary in the Ruby and Rust TypeCheckers, using the `rule_engine` app as evidence.

---

## Deliverables

| Artefact | Path | Status |
|----------|------|--------|
| Proof runner | `igniter-lang/experiments/unknown_output_coercion_proof/verify_unknown_output_coercion_p1.rb` | 36/36 PASS |
| Governance doc | `igniter-lang/.agents/work/proposals/LAB-UNKNOWN-OUTPUT-COERCION-P1-unknown-collection-output-gap-v0.md` | Written |
| This card | `igniter-lab/.agents/work/cards/lab/LAB-UNKNOWN-OUTPUT-COERCION-P1.md` | Written |
| Portfolio update | `igniter-lab/.agents/portfolio-index.md` | Updated |

---

## Verdict: PROVED 36/36 — HOLD / SAFETY-HIGH

```
Result: 36/36 PASS
VERDICT: PASS — LAB-UNKNOWN-OUTPUT-COERCION-P1 PROVED
  Scalar Unknown → T at output:            CAUGHT by Ruby TC (OOF-TY0)
  Collection[Unknown] → Collection[T]:     SILENT on Ruby TC and Rust TC (SAFETY-HIGH GAP)
  Rust TC scalar Unknown:                  SILENT (LAB-RACK-P9 intentional guard)
  Proposal surface:                        element-type check at Collection output boundary
```

---

## Proof Matrix (36 checks / 8 sections)

| Section | Checks | Result |
|---------|--------|--------|
| A — Scalar Unknown at typed output (CAUGHT) | 4 | 4/4 PASS |
| B — Collection[Unknown] at typed output (GAP) | 5 | 5/5 PASS |
| C — call_contract as Unknown source | 4 | 4/4 PASS |
| D — Rule-engine exact fixture (engine.ig pattern) | 4 | 4/4 PASS |
| E — Ruby TC type_name anatomy | 5 | 5/5 PASS |
| F — Rust TC parity | 5 | 5/5 PASS |
| G — No validation receipt | 4 | 4/4 PASS |
| H — Safety classification / authority closed | 5 | 5/5 PASS |

---

## Key Technical Findings

**Root cause:** `type_name()` reads only the top-level `"name"` field of a type hash.
For `Collection[Unknown]` and `Collection[RuleDecision]`, both return `"Collection"`.
The output check `type_name(actual) != type_name(expected)` is false → no OOF-TY0.

**Scalar vs Collection asymmetry in Ruby TC:**
- Scalar `Unknown → T`: `"Unknown" != "RuleDecision"` → OOF-TY0 fires (correctly caught)
- `Collection[Unknown] → Collection[T]`: `"Collection" == "Collection"` → silent pass (gap)

**Rust TC differs on scalar Unknown:**
- Rust has explicit LAB-RACK-P9 guard: `type_name(&actual) != "Unknown"` → scalar Unknown also silent
- Both toolchains share the Collection element-type gap

**Evidence app:** `rule_engine/engine.ig` — `call_contract` maps to `Collection[Unknown]`,
output declared as `Collection[RuleDecision]` — both TCs compile without diagnostic.

**Not call_contract-specific:** Any expression returning Unknown that ends up in a
Collection will exhibit the same silent coercion at the output boundary.

---

## OOF Codes

| Code | In this card |
|------|-------------|
| OOF-TY0 | Fires for scalar Unknown → T (Ruby) / not fired for Collection element gap |
| (gap) | No OOF code covers Collection element-type mismatch at output |

No new OOF codes in this deliverable.

---

## Authority Closed

No changes to any source file. HOLD/SAFETY-HIGH classification.  
No dynamic dispatch proposal. No plugin model. No new OOF codes.

---

## Open (Future Card)

Element-type extraction at Collection output boundary:
- `element_name(type)` helper reading `type.dig("of", "name")`
- Check element type when outer name is "Collection"  
- New OOF code or extend OOF-TY0 with collection-element message
- Rust TC parity needed (aligned with LAB-RACK-P9 Unknown guard scope)
