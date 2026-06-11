# Lang: Module Identity and Hash Discipline — Readiness Assessment

**Track:** module-identity-hash-discipline-and-multifile-prerequisite-v0
**Card:** LANG-MODULE-IDENTITY-P1
**Category:** governance / lang
**Date:** 2026-06-11
**Route:** GOVERNANCE / READINESS / NO IMPLEMENTATION
**Status:** CLOSED — assessment complete; decision matrix and next route produced

---

## Authority Boundary

This document is readiness research only.

- No parser, compiler, VM, or source changes authorized.
- No canon PROP authored.
- No package registry, semver policy, or distribution scheme designed.
- No import resolution implementation authorized.
- No public/internal visibility semantics designed.
- No canon authority created by this document.

Lab and ecosystem evidence is cited as evidence, not authority. Source paths
and verbatim quotes are included so a future PROP author can verify independently.

---

## 1. Current Identity Inventory

Every hash-like or identity-bearing field found across the three repositories:

| Field | Location | Algorithm | Input material | Stability claim | Authority level | Consumer(s) | Drift risk |
|---|---|---|---|---|---|---|---|
| `source_hash` | Ch6 manifest schema (required); all passes carry it | SHA256 — `^sha256:[a-f0-9]{64}$` | Source `.ig` file text | Deterministic; same source → same hash | **Canon** — normative pattern in schema | All downstream passes; loader; proof harness | LOW — algorithm is fixed in schema regex |
| `program_id` | Ch6 manifest schema; each pass emits its own | **DIVERGENT**: blake3 (Rust lab); SHA256 seed (Ruby canon) | `grammar_version \| pass_version` at each pass; chained pass-to-pass | Deterministic per toolchain; NOT cross-toolchain | Lab-only for blake3 variant; canon schema says `semanticir/<16 hex>` but does not fix algorithm | Manifest, CompilationReport, proof fixtures | **HIGH** — C24 flagged in gov triage; same source → different value across toolchains |
| `artifact_hash` | Ch6 manifest schema (required) | SHA256 — `^sha256:[a-f0-9]{64}$` | All assembled `.igapp/` content | Deterministic; pins full artifact | **Canon** | Loader integrity check; PROP-036 signs over it | LOW — algorithm fixed in schema regex |
| `contract_ref` | Ch6 manifest schema + SemanticIR ContractIR | SHA256 truncated to 24 hex — `^contract/[A-Za-z0-9_]+/sha256:[a-f0-9]{24}$` | Contract definition body | Deterministic per contract shape | **Canon** — normative pattern in schema and SemanticIR spec | Manifest `contract_refs`/`contract_index`; SemanticIR `contract_ref`; Loader | LOW — algorithm fixed in two schema patterns |
| `source_contract_ref` | Assembled contract JSON (Ch6 appendix §assembled-contract schema) | SHA256 24 hex (same pattern as `contract_ref`) | Source-level contract definition | Same as `contract_ref` | Canon | Loader cross-checks with manifest `contract_ref` | LOW |
| `compiler_profile_id` | Manifest optional field (PROP-036 accepted partial-impl) | `compiler_profile_unified/sha256:<24+ hex>` | Compiler profile slot schema | Deterministic per profile snapshot | Canon (partial) — PROP-036 non-authority statement; rollout = `legacy_optional` | Manifest; future Loader gate (not active) | LOW once fully landed |
| `semantic_ir_ref` | Manifest field | `semanticir/<16 hex>` | Derived from `program_id` of emitter pass | Follows `program_id` | Lab-only (algorithm not fixed in canon spec) | Manifest cross-reference | HIGH — inherits `program_id` divergence |
| `compilation_report_ref` | Manifest field | `compilation_report/<16 hex>` | Derived from `program_id` | Follows `program_id` | Lab-only | Manifest cross-reference | HIGH — inherits divergence |
| `module name` (ModPath) | Ch2 grammar: `ModuleDecl := "module" ModPath` | None — display label | Dotted string declared in source | No uniqueness enforcement; no deduplication | **Display label only** — no semantic identity | ParsedProgram `"module"` field; SemanticIR `"module"` field | HIGH — two files may declare same name; compiler does not detect this |
| `import path` | Ch2 grammar: `ImportDecl := "import" ModPath ...` | None — parsed string | Dotted path + selective names | **No resolution**; OOF-M1/M2 reserved but NOT fired | **None** — import is semantically inert today | ParsedProgram `"imports"` array (stored, unused by classifier/typechecker) | HIGH — undefined import produces no error |
| `IGV definition hash` | Lab only: `.igv` compiled bundle | SHA256 64 hex | View definition content | Lab-only N→1 dedup (LAB-IGV-TAILMIX-P4) | Lab-only | IGV render/oracle/interpreter | N/A (lab boundary) |
| Proof fixture names | `experiments/*/fixtures/`, `assembled/*.igapp/manifest.json` | Hand-authored string literal (e.g., `"sha256:history-valid-temporal-fixture"`) | Human-chosen label | Stable by convention, not by computation | Proof-local only — not carried to production | Proof harnesses, golden comparison | LOW for proofs; not suitable for any production identity claim |

---

## 2. Hash Algorithm Findings

### Where SHA256 is used

All canonical manifest schema fields:
- `source_hash`: `^sha256:[a-f0-9]{64}$` (Ch6 appendix schema, required)
- `artifact_hash`: `^sha256:[a-f0-9]{64}$` (Ch6 appendix schema, required)
- `contract_refs` values: `^contract/[A-Za-z0-9_]+/sha256:[a-f0-9]{24}$` (Ch6 appendix schema)
- `source_contract_ref`: same pattern (Ch6 appendix schema)
- `compiler_profile_id` suffix: `compiler_profile_unified/sha256:<24+ hex>` (PROP-036)
- IGV definition hashes in lab (SHA256 64 hex, lab-only)

### Where blake3 is used

Rust lab compiler passes only:

```rust
// igniter-lab/igniter-compiler/src/classifier.rs:178
let program_id = format!("classifier_pass/{}", blake3::hash(
    format!("{}|{}", parsed.grammar_version, self.version).as_bytes()
));
```

`Cargo.toml`: `blake3 = "1.5"`

Same pattern in `typechecker.rs` (chained from classifier output).

### Are both active?

**Yes.** SHA256 governs all content-addressed manifest fields. blake3 governs `program_id` inside the Rust lab toolchain. Both are live simultaneously.

### Is the separation intentional or accidental?

Intentional for performance (blake3 is faster for incremental hashing). **Unresolved for cross-toolchain reproducibility.** The Ruby canon implementation uses a SHA256-seed prefix at `classifier.rb:89-97`; the Rust lab uses blake3. Same source file → different `program_id` values across implementations.

### Is any cross-toolchain identity claim blocked by divergence?

**Yes.** Any claim of the form "this `.igapp` was produced from source S by any conforming compiler" breaks at `program_id`, `semantic_ir_ref`, and `compilation_report_ref` — all three inherit the divergence.

The content-addressed fields (`source_hash`, `artifact_hash`, `contract_ref`) are **not** affected; their algorithm is fixed in the schema regex and is the same (SHA256) in both toolchains.

Gov triage finding C24 (2026-06-10): *"Real cross-implementation reproducibility risk. Route to STAB-P4 decision."*

---

## 3. Identity Unit Findings

| Candidate | Classification | Notes |
|---|---|---|
| `source_hash` (SHA256 of source file text) | **Source-file identity** — stable, content-addressed | Single source of truth for "which source produced this artifact" |
| `program_id` | **Compilation-unit identity** — unstable across toolchains | Must be unified before cross-toolchain claims; currently pass-scoped, not source-scoped |
| `contract_ref` (`contract/<Name>/sha256:<24 hex>`) | **Contract identity** — stable, content-addressed | Safe to use for contract-level versioning/caching; PROP-017 can build on it |
| `artifact_hash` (SHA256 over full `.igapp/`) | **Artifact identity** — stable | End-to-end fingerprint; PROP-036 signs over it |
| `compiler_profile_id` | **Compilation-context identity** — stable once fully landed | Identifies which compiler profile understood this artifact; non-authority per PROP-036 §11 |
| `module name` (ModPath dotted string) | **Display label only** — NOT an identity unit | No uniqueness, no resolution; dangerous to treat as identity before cross-file compilation exists |
| `import path` (ModPath in import decl) | **Parsed token, not identity** — semantically inert | Zero resolution; OOF-M1/M2 not enforced |
| `semantic_ir_ref`, `compilation_report_ref` | **Pass-local artifact identity** — unstable across toolchains | Inherit `program_id` divergence; usable within one toolchain, not across |
| `source_contract_ref` (in assembled contract JSON) | **Contract identity at source level** — stable | SHA256 24 hex; same family as `contract_ref` |
| Proof fixture names | **Unstable/local proof identity** — hand-authored | Proof-local only; not a production identity mechanism |

---

## 4. Multi-File Prerequisite Analysis

**What identity must exist before N .ig files can form one compilation unit?**

The current architecture is strictly one-file-in, one-`.igapp`-out. A multi-file compilation unit requires:

1. **A multi-file `source_hash`** — currently computed from a single file's text. For N files, the canonical answer is a deterministic, order-stable hash of all input source files: either a sorted-by-module-path hash of all file contents, or a Merkle-style composition. Algorithm must be SHA256 (consistent with all canonical fields). The spec must state the input-ordering rule explicitly.

2. **Module name uniqueness enforcement** — today two files may declare `module Lang.Examples.Foo` with zero detection. Before the compiler resolves cross-file symbols, it must reject duplicate module declarations (new OOF code required, likely OOF-M3). This is a compiler driver change, not a grammar change.

3. **Import resolution enforcement** — OOF-M1 (circular import) and OOF-M2 (unknown import path) are reserved but not fired. They must be active before a multi-file compilation unit means anything. An import that silently no-ops is a silent authority void — the Postulate 20 evidence-DAG property requires all composition to be declared; import is a composition declaration.

4. **`contract_ref` remains stable** — already content-addressed per contract body; no change needed for multi-file.

5. **`program_id` unification** — does NOT block multi-file P1 compilation (the driver change is independent of the hash algorithm), but blocks any cross-toolchain reproducibility claim about the resulting artifact. Recommendation: unify algorithm (SHA256) before shipping multi-file P1 to avoid baking in the divergence.

**Does module name participate in identity?**
Not yet, and it should not be the primary identity carrier. Module name → module content → `source_hash` is the correct chain. The module name is a routing label for import resolution, not a content-addressed identity.

**Does import order affect identity?**
It should not. Import declarations are a set, not a sequence. The canonical multi-file `source_hash` must be order-independent (sorted by module path).

**Do comments and `intent` metadata affect identity?**
`source_hash` is computed from raw source text, so yes — comments change `source_hash` today. This is correct for source-fidelity but means refactoring comments changes the artifact. A future PROP may want a `semantic_hash` that excludes comments; for P1, source_hash-as-raw-text is acceptable and honest.

**What happens with duplicate module or contract names?**
Currently: nothing (silently accepted). Required pre-P1: OOF-M3 for duplicate module declaration within a compilation unit; existing contract-name uniqueness within a single program (already enforced) extends naturally to the multi-file case.

**What identity should `.igapp` carry for a multi-file program?**
The manifest's `source_hash` becomes the composite hash of all input source files (per the ordering rule above). `artifact_hash` remains SHA256 of all assembled content. `contract_refs` remains per-contract (unchanged). `program_id` uses the unified algorithm (SHA256-based).

---

## 5. Import Boundary

**What does import mean today?**

Grammar only. The parser builds a complete `Import { module_path, names, hiding, overriding }` struct. The classifier and typechecker have **zero references** to it. Compiler evidence (`igniter-lab/lab-docs/governance/igniter-packaging-and-library-reuse-proposal-readiness-v0.md`):

> "`availability_projection.ig` does `import SparkCRM.Types.{ GeoSignal, TimeSlot, ScheduleFact, AvailabilitySnapshot }` — and `SparkCRM.Types` **is never defined anywhere in the codebase**, yet compilation produces **no error**."

**Is import semantically inert?**
Yes, completely. Imports are stored in ParsedProgram and carried through all passes unchanged. No symbol is ever resolved from an import path.

**Should unresolved imports fail before multi-file opens?**
Yes. OOF-M2 (unknown import path) must be enforced before multi-file P1 ships. The reason: a silent no-op import in a multi-file world is a latent authorization void. A program author who writes `import Auth.Contracts.{ VerifyToken }` intends a dependency; if that import silently succeeds while resolving to nothing, the program's honest account is false. Honesty (Axiom 1) requires import resolution to be complete or explicitly fail.

**Does import confer authority?**
No. Import is a compile-time name-resolution mechanism. It does not bind capabilities, grant effect authority, or change fragment classification. A dependency's `effect`/`privileged`/`irreversible` contracts are inert in the consumer until the consumer declares its own `profile` and supplies `capability` parameters (the consumer-side binding model from PROP-033/040, per RES-002 §2.2).

**Does import bind capabilities?**
No, consumer-side only. This is a closed design decision: the consumer's `effect contract X via profile { capability c: IO.T }` declaration is the trust suture point. Import alone confers no capability authority.

---

## 6. Package Boundary

**Why package ≠ code drop**

In conventional ecosystems a dependency import is an execution grant — imported code can do anything the runtime allows. This model is incompatible with:
- Postulate 10: "Profiles cannot be bypassed at runtime."
- Ch12 / PROP-035: effect authority requires explicit capability parameters.
- The fragment classification model: a `pure` import cannot silently become an `effect` consumer.

**Why a package should be a sealed claim**

The content-addressed identity substrate already exists: `source_hash`, `contract_ref` (per contract), `artifact_hash` (per `.igapp`). A package is the same thing at a larger granularity: a named, versioned set of modules whose identity is its hash, whose authority surface is declared (maximum tier, declared external effects, capability requirements), and whose consumers verify, not trust.

The content-addressed foundation is already Unison/Nix-style in spirit: the language hashes everything. `QueryResult` is re-declared 8+ times in lab fixtures because import resolution is inert — the moment import resolution is live, content-addressed reuse eliminates copy-paste naturally.

**What evidence/receipts would a package eventually carry**

- Module-level `source_hash` per contributing file
- `artifact_hash` of the package bundle
- `contract_refs` for all public contracts (stable, carries CompatibilityReport — PROP-017)
- `compiler_profile_id` (PROP-036) pinning the compiler that understood and assembled the package
- Effect summary: maximum authority tier + declared external system names + capability types required
- Fragment summary: CORE/ESCAPE/OOF census (consumers can verify no unexpected ESCAPE contracts)
- Proof receipts: which experiments/conformance suites passed (evidence, not authority)

**Explicitly deferred**

Registry, semver policy, distribution infrastructure, trust store, dynamic loading (forbidden per PROP-038 §16), and third-party certification are all explicitly out of scope for the identity unification work. They belong to Phase 2/3 (gov triage, 2026-06-10 report).

---

## 7. Public/Internal Implication

Visibility (public/internal/export) requires a stable module identity before it can be meaningful. The reason: a visibility declaration like "this contract is internal to module Foo" is a claim about what crosses the module boundary. If module names are display labels with no uniqueness enforcement and no cross-file resolution, there is no module boundary to be internal to.

The prerequisite chain is:
1. Module name uniqueness enforced (OOF-M3 fires on duplicate)
2. Import resolution live (OOF-M1/M2 active)
3. Multi-file compilation unit stable (source_hash and program_id unified)
→ Only then does "internal to this module" mean something checkable.

Visibility design does not belong in P1. The right slot is P2 (igpack manifest export list) per RES-002 §3.2: a module export list at the package boundary is the minimal visibility mechanism consistent with "no hidden scoping" (Ch2 §2.2.1 constraint).

---

## 8. Stdlib Implication

Stdlib-as-import (`import stdlib.collection.{ fold, map }`) requires:
1. Multi-file compilation unit (P1) — stdlib is a set of modules, not a compiler built-in forever.
2. Unified `source_hash` for the stdlib bundle — the consumer's artifact must pin exactly which stdlib version it was compiled against.
3. The stdlib inventory hash (RES-001 §3.1 "stdlib entry contract") becomes the identity anchor: stdlib-as-package is the first real consumer of the igpack format.

Until P1 lands, stdlib remains compiler-intrinsic (current state). The self-hosting gate study (RES-001 §3.3 slice 4) gates on this same prerequisite.

---

## 9. Decision Matrix

**Verdict: CONDITIONAL**

### Rationale

The content-addressed identity substrate is **coherent and sound**:
- `source_hash` (SHA256 of source text) — canonical, deterministic, fixed algorithm, carried through all passes.
- `contract_ref` (`contract/<Name>/sha256:<24 hex>`) — canonical, deterministic, per-contract identity; safe foundation for contract versioning (PROP-017) and multi-file cross-references.
- `artifact_hash` (SHA256 over full `.igapp/`) — canonical, end-to-end fingerprint.

Multi-file compilation P1 can proceed on this foundation. The grammar already has `module`/`import`. The compilation driver change (read N files, resolve imports, emit one `.igapp`) does not require a new hash algorithm.

**Two pre-conditions must be satisfied first** (these are the "conditional"):

| # | Condition | Work required | Urgency |
|---|---|---|---|
| C1 | `program_id` algorithm unified to SHA256 across Ruby and Rust toolchains | Small: align Rust lab classifier/typechecker to use SHA256 with same input format as Ruby; add pattern to Ch6 schema | HIGH — baking in divergence during multi-file P1 makes every subsequent identity claim cross-toolchain-unreliable |
| C2 | OOF-M1/M2 enforcement active | Moderate: compiler driver must reject circular and unknown imports before declaring multi-file support; otherwise "import is a no-op" silently continues and the program's honest account is false | HIGH — correctness prerequisite, not just cleanliness |

**One condition is parallel** (can happen during or after P1, does not block it):

| # | Condition | Notes |
|---|---|---|
| C3 | Module name uniqueness check (OOF-M3) | Can ship with the multi-file driver; does not need a pre-pass |

---

## 10. Summary Findings

1. **Content-addressed substrate is sound and SHA256-based.** `source_hash`, `contract_ref`, `artifact_hash` are canonical, algorithm-fixed, and consistent across both toolchains. Multi-file can build directly on this.

2. **`program_id` divergence is the only blocking issue.** Ruby uses SHA256-seed prefix; Rust uses blake3. Same source → different `program_id` values. This breaks cross-toolchain reproducibility for `semantic_ir_ref`, `compilation_report_ref`, and any claim that requires a single stable program identity. Fix is small: unify to SHA256 in the Rust lab toolchain.

3. **Import is semantically inert — this is the largest gap.** The parser supports full import syntax; the classifier and typechecker ignore it entirely. Undefined imports produce no error. This is the root cause of 8+ copy-pasted `QueryResult` declarations in lab fixtures. Multi-file compilation is meaningless without OOF-M1/M2 enforcement.

4. **Module name is a display label, not an identity unit.** No uniqueness enforcement exists. A module name alone cannot be trusted as a stable identity before cross-file symbol resolution is live.

5. **Packages must be sealed claims, not code drops.** Capability authority does not flow through import. Consumer-side capability binding (PROP-033/040 pattern, lifted to package level) is the correct model. This is a closed design decision, consistent with Postulate 10 and Ch12.

6. **Visibility/public-API design must wait for multi-file identity.** The prerequisite chain is: unified identity → cross-file resolution → module boundary → visibility. Skipping ahead produces meaningless syntax.

7. **Stdlib-as-import shares the same prerequisite.** Self-hosting and import-resolution are the same unlock (RES-001, RES-002, RES-003 triad all block on this).

8. **`compiler_profile_id` (PROP-036) is the right anchor for compiler-context identity.** Already accepted, partially implemented, algorithm-fixed (SHA256). The only gap is completing the `profile_required` rollout (currently `legacy_optional`).

---

## 11. Next Route

**CONDITIONAL → two sequential cards:**

```
LANG-MODULE-IDENTITY-P2
  Goal: unify program_id algorithm (SHA256) across Ruby/Rust toolchains
        + add canonical pattern to Ch6 schema
  Route: GOVERNANCE / SMALL IMPLEMENTATION
  Precondition: none
  Output: updated Ch6 schema pattern; aligned Rust lab classifier/typechecker;
          regression: all existing golden fixtures still match

LAB-MULTIFILE-COMPILATION-P1
  Goal: multi-file compilation driver: N .ig files → one .igapp
        + OOF-M1/M2 enforcement
        + OOF-M3 (duplicate module name)
        + canonical multi-file source_hash rule
  Route: LAB / EXPERIMENTAL
  Precondition: LANG-MODULE-IDENTITY-P2 closed (program_id unified)
  Output: proof suite with ≥15 fixture cases (cross-file import, circular
          import OOF-M1, unknown import OOF-M2, duplicate module OOF-M3,
          multi-contract multi-file .igapp)
```

**Explicitly closed surfaces (not in scope for either card):**

- Registry, semver policy, distribution infrastructure
- Visibility/public/internal keywords or per-declaration modifiers
- Cross-module profile imports (PROP-040 §9 explicitly deferred)
- Dynamic loading (PROP-038 §16 explicitly forbidden)
- Stdlib numeric content (RES-001) — gates on multi-file, tracked separately
- Application form / component declarations (RES-003) — gates on multi-file, tracked separately
- Trust store or third-party certification
- VM bytecode identity (no stable format; deferred to Reference Runtime)

---

## Sources

Canon: `igniter-lang/docs/spec/ch2-source-surface.md` (§2.2 grammar, §2.6 module/OOF-M1/M2),
`igniter-lang/docs/spec/ch6-appendix-igapp-schema.md` (all field patterns),
`igniter-lang/docs/spec/ch6-semanticir.md` (ContractIR contract_ref shape),
`igniter-lang/docs/language-covenant.md` (P10, P20, Axiom 1).
Proposals: PROP-017 (contract versioning), PROP-033/040 (authority binding),
PROP-036/038 (compiler profile identity and non-authority).
Gov (evidence): `igniter-gov/portfolio/governance/2026-06-10-external-ecosystem-report-triage-v0.md`
(C24 hash divergence, C25 lab-only pipeline stages).
Lab (evidence): `igniter-lab/lab-docs/governance/igniter-packaging-and-library-reuse-proposal-readiness-v0.md`
(import inertia, copy-paste evidence);
`igniter-lab/igniter-compiler/src/classifier.rs:178` (blake3 usage);
`igniter-lab/.agents/portfolio-index.md` (IGV definition hash; LAB-LANGFORM-RESEARCH-P1 triad).
Research: `igniter-lang/.agents/work/research/RES-001`, `RES-002`, `RES-003`.
