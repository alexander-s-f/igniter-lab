# Card: LANG-MODULE-IDENTITY-P1

**Category:** governance / lang
**Track:** module-identity-hash-discipline-and-multifile-prerequisite-v0
**Status:** CLOSED — readiness assessment complete; CONDITIONAL verdict; next route stated
**Gate result:** N/A — readiness research (no proof runner)
**Date closed:** 2026-06-11
**Route:** GOVERNANCE / READINESS / NO IMPLEMENTATION

---

## Goal

Establish the current identity/hash discipline for Igniter programs, modules,
imports, and compiled artifacts, and decide what must be unified before
multi-file compilation, package claims, stdlib-as-import, or public/internal
visibility can safely open.

Core question: **what is the stable identity unit in Igniter, and is it coherent
enough to open multi-file compilation?**

---

## Depends On

| Source | Used for |
|--------|----------|
| Ch6 igapp schema (`ch6-appendix-igapp-schema.md`) | canonical field patterns and SHA256 requirements |
| Ch2 source surface (`ch2-source-surface.md`) | module/import grammar; OOF-M1/M2 reservation |
| Ch6 SemanticIR (`ch6-semanticir.md`) | ContractIR contract_ref shape |
| PROP-036/038 | compiler_profile_id algorithm and non-authority statement |
| PROP-017 | contract versioning and CompatibilityReport foundation |
| Gov triage 2026-06-10 (C24) | blake3/SHA256 divergence flagged |
| `igniter-lab/igniter-compiler/src/classifier.rs:178` | blake3 usage confirmed in Rust lab |
| `igniter-lab/lab-docs/governance/igniter-packaging-and-library-reuse-proposal-readiness-v0.md` | import inertia evidence; copy-paste corpus evidence |
| RES-001 / RES-002 / RES-003 | triad research; prerequisite dependencies |

---

## Deliverables

| Artifact | Path | Status |
|----------|------|--------|
| Readiness doc | `igniter-lab/lab-docs/governance/lang-module-identity-hash-discipline-readiness-v0.md` | ✅ DONE |
| This card | `igniter-lab/.agents/work/cards/governance/LANG-MODULE-IDENTITY-P1.md` | ✅ DONE |
| Portfolio update | `igniter-lab/.agents/portfolio-index.md` | ✅ DONE |

---

## Key Findings

| # | Finding |
|---|---------|
| F1 | Content-addressed substrate is **sound**: `source_hash` / `contract_ref` / `artifact_hash` are SHA256, algorithm-fixed in Ch6 schema, consistent across toolchains |
| F2 | `program_id` is **divergent**: Rust lab uses blake3; Ruby canon uses SHA256 seed prefix. Same source → different values. Flagged C24 by gov triage. Small fix: unify to SHA256 |
| F3 | **Import is semantically inert**: parsed, never resolved. `SparkCRM.Types` undefined, no error. OOF-M1/M2 reserved but not fired. Root cause of 8+ copy-pasted `QueryResult` declarations in lab |
| F4 | **Module name is a display label, not an identity unit**: no uniqueness enforcement; two files may declare the same module name with no detection |
| F5 | Capability/authority does **not** flow through import; consumer-side binding is a closed design decision (PROP-033/040 pattern) |
| F6 | Visibility design must wait for multi-file identity; the prerequisite chain is: unified identity → cross-file resolution → module boundary → visibility |
| F7 | `compiler_profile_id` (PROP-036) is the right compiler-context anchor; algorithm already fixed (SHA256); gap is completing `profile_required` rollout |
| F8 | Stdlib-as-import, component declarations, and application form all gate on multi-file compilation (RES-001/002/003 triad confirms) |

---

## Decision

**CONDITIONAL** — the core identity substrate is sound enough for multi-file P1, subject to two pre-conditions:

| Condition | Required before multi-file P1? |
|---|---|
| C1: Unify `program_id` algorithm to SHA256 across Ruby + Rust | YES — otherwise baking in divergence |
| C2: Enforce OOF-M1 (circular import) and OOF-M2 (unknown import) | YES — import correctness prerequisite |
| C3: OOF-M3 (duplicate module name) | Can ship with multi-file driver |

---

## Next Route

```
LANG-MODULE-IDENTITY-P2
  Goal: unify program_id algorithm to SHA256 across toolchains +
        add canonical pattern to Ch6 schema
  Precondition: none
  Size: small

LAB-MULTIFILE-COMPILATION-P1  (after LANG-MODULE-IDENTITY-P2)
  Goal: multi-file compiler driver: N .ig files → one .igapp +
        OOF-M1/M2/M3 enforcement +
        canonical multi-file source_hash rule
  Precondition: LANG-MODULE-IDENTITY-P2 closed
  Size: moderate (≥15 fixture proof cases)
```

---

## Closed Surfaces (not in scope for either next card)

- Registry, semver policy, distribution, trust store
- Visibility/public/internal keywords
- Cross-module profile imports (PROP-040 §9 deferred)
- Dynamic loading (PROP-038 §16 forbidden)
- Stdlib numeric content (RES-001, separate track)
- Application form / component declarations (RES-003, separate track)
- VM bytecode artifact identity (deferred to Reference Runtime)
