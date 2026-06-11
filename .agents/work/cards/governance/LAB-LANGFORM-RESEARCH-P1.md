# Card: LAB-LANGFORM-RESEARCH-P1
**Category:** governance / lang
**Track:** lab-language-form-research-triad-v0 (out-of-track research)
**Status:** CLOSED — three proposal-readiness docs authored
**Gate result:** N/A — research (no proof runner); no code/canon changes
**Date closed:** 2026-06-10
**Route:** PROPOSAL READINESS / RESEARCH / LAB-ONLY / NO CANON PROP AUTHORED

---

## Goal

Research and prepare proposal-readiness documents for three language-form blind spots surfaced by
the recent application pressure (esp. LAB-PURSUIT-P1): **stdlib coverage**, **packaging / library
reuse**, and **application form/structure** (entrypoint, hierarchy, public-vs-internal, module
composition). These are lab/governance *readiness* docs — they map the gap, propose the shape, name
preconditions, and recommend PROP routes. They do **not** author canon PROPs (governance gate owns that).

---

## Deliverables

| Doc | Path | Status |
|-----|------|--------|
| 1 — Stdlib & numeric core | `lab-docs/governance/igniter-stdlib-numeric-coverage-proposal-readiness-v0.md` | ✅ DONE |
| 2 — Packaging & library reuse | `lab-docs/governance/igniter-packaging-and-library-reuse-proposal-readiness-v0.md` | ✅ DONE |
| 3 — Application structure & module form | `lab-docs/governance/igniter-application-structure-and-module-form-proposal-readiness-v0.md` | ✅ DONE |
| This card | `.agents/work/cards/governance/LAB-LANGFORM-RESEARCH-P1.md` | ✅ DONE |
| Portfolio update | `.agents/portfolio-index.md` | ✅ DONE |

---

## Findings (grounded by 3 read-only source sweeps)

**Doc 1 — stdlib ~85% done; the gap is numeric math.** Text/Option/Result/Collection/DateTime
complete and VM-executable (VM is a superset of canon Ch8 for Option/Result); Map read-only.
**No `abs/min/max/clamp/compare/sign/isqrt/pow/sqrt/trig`** — only `+−×÷`. LAB-PURSUIT-P1 proved this
empirically (forced sqrt-free integer fixed-point). **Precondition: dual-toolchain OPERATOR PARITY**
(Float rejected both; Decimal Rust-yes/Ruby-no; `==`/`<`/`||` Rust-yes/Ruby-no — STAB-P4 family)
gates ALL numeric canon promotion. Proposed: N0 (abs/min/max/clamp/compare/sign) + N1
(isqrt/ipow/imuldiv), Integer+Decimal, pure CORE; N2 (CORDIC-integer trig + sqrt) deferred.

**Doc 2 — `import` parses but is INERT; reuse = copy-paste.** Zero classifier/TC resolution; an
undefined import produces no error; `QueryResult` re-declared 8+× ("for lab independence"). Three
fused concerns to sequence: **(a) module resolution [KEYSTONE]** / (b) visibility-export /
(c) distribution [deferred]. **Design lean: content-addressed reuse (Unison/Nix-style)** over
semver — Igniter already hashes everything; fits determinism/replay/honesty. (a) alone ends
copy-paste and unblocks docs 1 & 3.

**Doc 3 — flat plane confirmed.** Only module→contract→io; contracts flat siblings; entrypoint is
CLI-only (`--entry`/`contracts[0]`), language-absent; ZERO public/private; composition stringly-typed
(`call_contract("Name")` — compiler knows the DAG, source hides it). Diagnosis: the DAG is
compiler-real / source-invisible; an undeclared public surface is a hidden assumption → a
**structural honesty gap** (Covenant-aligned). Three orthogonal needs: entrypoint / visibility /
grouping. Proposed: PROP-ENTRYPOINT (standalone first win, helps the debugger-textbook) →
PROP-MODULE-VISIBILITY (public/internal, default internal) → typed contract-refs (later) → grouping
(deferred).

---

## Cross-doc dependency ordering (the triad's spine)

```
KEYSTONE:  PROP-IMPORT-RESOLUTION (doc 2a) — cross-file symbol resolution
           ├─ unblocks stdlib-as-import (doc 1)  — a stdlib you re-declare per file is not a stdlib
           └─ gives visibility cross-file meaning (doc 2b ≡ doc 3 visibility)

PARALLEL:  STAB-P4-OPERATOR-PARITY (doc 1 precondition) — gates numeric canon promotion
           PROP-NUMERIC-CORE (doc 1)                    — independent; embed/math unlock
           PROP-ENTRYPOINT (doc 3)                      — standalone; smallest first structural win

SHARED:    PROP-MODULE-VISIBILITY — public/internal — appears in BOTH doc 2 and doc 3
DEFERRED:  distribution/registry (doc 2c) | section/grouping (doc 3) | numeric trig N2 (doc 1)
```

Recommended first moves (any order): **PROP-ENTRYPOINT** (cheapest, standalone, immediate legibility
+ tooling/debugger win) and **PROP-IMPORT-RESOLUTION** (keystone, ends copy-paste, unblocks the rest).

---

## Authority

lab-only — proposal-readiness research; no canon claim, no stable surface, no PROP authored, no
code/VM/compiler changes. Operator divergence flagged (STAB-P4), not resolved. `entrypoint`/`section`
remain non-canon (designed, not reserved). Lab behavior not accepted as canon. Informs future gate
decisions; does not make them.
