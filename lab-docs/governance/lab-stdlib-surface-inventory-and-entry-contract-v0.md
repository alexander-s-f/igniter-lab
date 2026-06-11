# LAB-STDLIB-FOUNDATION-P1: Stdlib Surface Inventory and Entry Contract

**Track:** stdlib-surface-inventory-and-entry-contract-v0
**Route:** RESEARCH / DESIGN BOUNDARY / NO IMPLEMENTATION
**Date:** 2026-06-11
**Status:** CLOSED — SPLIT
**Predecessor evidence:** RES-001 (stdlib foundations research), PROP-013 (accepted), PROP-042/043 (experiment-pass), Ch8, LAB-LANGFORM-RESEARCH-P1 doc 1, LAB-PURSUIT-P1

---

## 1. Problem Statement

The stdlib today is an accumulation, not a design. Every entry arrived because a
specific proof slice needed it: `Map[String,V]` exists because LAB-RACK-P12 needed
HTTP headers; `or_else` exists because Map v0 needed an Option unwrap; `count`
exists because PROP-042 needed a numeric measure. RES-001 already named this
structurally: *"a list of proven operations, not a designed library."*

What P1 adds beyond RES-001: a **status-classified inventory across all five
surfaces** (canon spec, Ruby production, Rust lab, fixtures, docs), an explicit
**false-stdlib partition** (things that look like stdlib but must not be treated
as such), a concrete **entry contract schema**, and **drift decisions** that block
the entry-contract proposal until resolved.

Why this is separate from package distribution: stdlib is the **language-owned
surface the compiler vouches for** (LAB-PACKAGE-MODEL-P1-a2 finding 10: same
mechanism as a package, different trust position — pinned via compiler_profile_id,
not resolved via a registry). Package identity work (LANG-CONTRACT-NAMESPACE-P1,
LAB-PACKAGE-MODEL-P2) governs *external* artifacts; nothing there blocks defining
what the *internal* surface is. The two must not be conflated: stdlib functions are
compiler-known names with TypeChecker resolution rules; package contents are
source-units verified by recomputation. Distribution remains closed for both.

---

## 2. Current Surface Inventory

Five surfaces were swept. Classification statuses: **canon** (Ch8 normative),
**production-implemented** (Ruby pipeline registry), **rust-lab-implemented**
(VM dispatch or lab compiler), **proof-local**, **doc-only**, **orphaned**,
**inconsistent / needs triage**.

### 2.1 The real stdlib (uniform evidence on at least two surfaces)

| Surface | Names | Canon | Ruby prod | Rust VM | Status |
|---|---|---|---|---|---|
| `stdlib.text.*` (14 ops) | concat, trim, contains, starts_with, ends_with, split, replace, replace_all, byte/rune/grapheme_length, byte/rune/grapheme_slice | Ch8 §8.10 | `TEXT_STDLIB_FNS` (typechecker.rb) | all 14 in vm.rs dispatch | **canon + production + rust-lab** — the reference-quality entry; the only category with full three-way agreement |
| `stdlib.map.*` (4 ops) | map_get, map_has_key, map_from_pairs, map_empty | PROP-043 design-lock | `MAP_STDLIB_FNS` (short→qualified) | get/has_key in vm.rs (from_pairs/empty handlers per PROP-043 v0 close) | **canon-track + production + rust-lab** |
| `stdlib.integer.*` arithmetic | add, sub, mul, div (+ gt in VM) | Ch8 §8.5 monomorphic names | numeric resolution in TC | vm.rs dispatch | **canon + production + rust-lab**; `gt` is VM-only (see §2.3) |
| `stdlib.collection.count` | count | PROP-042 `NUMERIC_MEASURE_BUILTINS` | yes (typechecker registry) | vm.rs | **canon-track + production + rust-lab** |
| `or_else` | Option[V] unwrap with default | Ch8 §8.3 | typechecker.rb:836 (`infer_or_else`) | VM | **canon + production + rust-lab — but namespace-inconsistent** (Decision D1: emitted in SIR as bare `"or_else"`, explicitly *"no stdlib. prefix — v0 design"*, typechecker.rb:2092) |

### 2.2 Kernel-proven but not VM-executable (canon ahead of lab)

Ch8 §8.2 collection surface: `fold, map, filter, sum, avg, min, max, group_by,
sort_by, take, first, last` — accepted via PROP-013, 12 kernel cases PASS, but
**"pending Slice A"**: not connected to the RuntimeMachine evaluate path, and only
`count` + `concat` appear in the Rust VM dispatch. Status: **canon, kernel-proven,
NOT production-executable**. This is the largest stability-marking gap: the spec
reads as if these exist; only a proof kernel ever ran them.

Same class: `stdlib.option`/`stdlib.result` monadic surface (`some, none, some?,
map, flat_map, ok, err, ok?, err?, unwrap_or`) — proven in
`source/monadic_extension.ig`, **no VM dispatch entries under those names**.

### 2.3 Orphaned names (single-surface, no canon anchor)

| Name | Where it lives | Why orphaned |
|---|---|---|
| `stdlib.option.wrap` | Rust vm.rs only | Ch8 names the constructors `some`/`none`; `wrap` appears nowhere in canon. Lab invented a parallel constructor name. **Decision D2.** |
| `stdlib.bool.and` | Rust vm.rs only | No `stdlib.bool` module exists in Ch8 at all. Operator lowering leaked into a stdlib-shaped name. |
| `stdlib.collection.concat` | Rust vm.rs + `source/collection_extension.ig` example | Example-proven, absent from Ch8 §8.2 list. |
| `stdlib.integer.gt` | Rust vm.rs only | Comparison ops are exactly the STAB-P4 operator-parity divergence zone (`==`/`<` Rust-yes/Ruby-no); a stdlib-shaped name for one comparison on one toolchain. |
| `stdlib.unsupported.*` | Rust vm.rs | Deliberate refusal namespace — fine as mechanism, but it is load-bearing evidence that the VM needs a *closed list* to refuse against, i.e. an inventory artifact. |

### 2.4 Doc-only / example-only names

- Ch8 §8.6 temporal: `add_duration`, `diff`, `as_of` — spec names.
  `source/datetime_extension.ig` proves `diff_seconds`, `add_seconds`,
  `parse_datetime`, `format_datetime`, `is_before`, `is_after`. **Disjoint name
  sets for the same domain** (RES-001 §1.2). Neither set is wrong; no artifact says
  which is canonical. **Decision D3.**
- `find, any, all` (collection_extension.ig), `zip, range`
  (stdlib_extension.ig) — example-proven, never entered Ch8.

### 2.5 False stdlib (must NOT be treated as stdlib)

This partition is the point of the card. Four classes:

1. **Proof-local helpers.** LAB-PURSUIT-P1's sqrt-free integer fixed-point
   machinery (isqrt-avoidance, milli-unit scaling, ZEM computation) — hand-written
   *contracts* inside fixtures, born precisely because stdlib.math does not exist.
   They are demand evidence for `stdlib.numeric` extensions (abs/min/max/clamp/
   isqrt), not stdlib entries. Similarly `tools/proof_harness` helpers and runner
   utilities.
2. **Domain-local helpers.** Query helpers (filter/order/limit/projection
   surfaces from LAB-QUERY-*), storage adapter helpers, outcome/KDR `kind:`-record
   recognizers hand-rolled per proof domain, HTTP header manipulation in RACK
   fixtures. Some are *candidates* (outcome combinators — see §7), but today they
   are domain vocabulary, and promoting them without the entry contract repeats
   the accretion pattern.
3. **Orphaned names** (§2.3) — single-toolchain inventions wearing the
   `stdlib.` prefix without canon anchor.
4. **Doc-sketch declarations.** `igniter-lab/igniter-stdlib/stdlib/*.ig` uses
   `module stdlib.Math` + `def add(a: Decimal[S], ...)` syntax. **`def` is not
   canon Igniter** (contracts are the unit); `stdlib.Math` capitalization clashes
   with the canonical `stdlib.numeric` lowercase scheme. The crate's own README
   correctly marks all of it lab-only. These files are design sketches in a
   stdlib costume; they must never be cited as surface evidence.
   `stdlib/io.ig` (`read_text(path, capability)`) is the same class — valuable
   *shape* evidence for L3 (capability-parameterized, Result-returning), zero
   surface authority.

### 2.6 Drift decisions (blockers to surface explicitly)

| # | Drift | Decision needed |
|---|---|---|
| **D1** | SIR namespace inconsistency: every stdlib call lowers to a qualified name (`stdlib.text.concat`, `stdlib.map.get`) EXCEPT `or_else`, deliberately emitted bare. Two namespace regimes inside one SIR. | Before the entry-contract proposal: qualify `or_else` → `stdlib.option.or_else` (alias-recorded), or document bare names as a permanent legacy class. Recommend qualify; pre-v1 is the cheapest moment. |
| **D2** | Option constructor split: canon `some`/`none` vs VM `stdlib.option.wrap`. The only executable Option constructor in the lab uses a name canon never defined. | Reconcile at entry-contract authoring: canon names win; `wrap` recorded as lab alias, slated for removal. |
| **D3** | Temporal naming: Ch8 §8.6 set vs datetime_extension proven set are disjoint. | Triage card (LAB-STDLIB-DATETIME-P1) decides per name: promote, rename, or drop. Do not grow temporal surface before this. |
| **D4** | Operator parity (STAB-P4 family): Float rejected by both TCs, Decimal Rust-yes/Ruby-no, `==`/`<`/`\|\|` Rust-yes/Ruby-no. Yet Ch8 §8.5 lists `stdlib.float.add` and `stdlib.decimal.*` as canon monomorphs. | Canon lists names that neither toolchain (Float) or only one toolchain (Decimal) accepts. The numeric category is **HOLD until parity** — confirmed independently by LAB-LANGFORM-RESEARCH-P1 and LAB-PURSUIT-P1. |
| **D5** | Executable-truth inversion: the only fully executable stdlib is lab Rust (explicitly non-canonical per README), while canon's kernel-proven surface largely does not run. Stability labels conflating "accepted" with "executable" hide this. | Entry contract's `stability` + `lowering` fields make the distinction first-class (§4). |

---

## 3. Namespace / Naming Model

Current regimes observed:

1. **Source-level short names** → **qualified SIR names**: `concat` →
   `stdlib.text.concat`; `map_get` → `stdlib.map.get`. The `map_` prefix exists
   only to disambiguate at source level (bare `get` is too generic).
2. **Bare names end-to-end**: `or_else` (D1).
3. **Generic pre-resolution → monomorphic post-resolution**:
   `stdlib.numeric.add` → `stdlib.integer.add` (TypeChecker-resolved). The only
   two-stage scheme, and it is good — keep it.
4. **Predicate `?` suffix** in Ch8 (`some?`, `ok?`) — never proven in any
   parser; pure doc convention.
5. **Lab sketches**: `stdlib.Math` capitalized module + `def` (false stdlib).

**Recommended discipline (firm enough to recommend, not HOLD):**

- Canonical identity of every entry = fully qualified lowercase dotted name
  `stdlib.<category>.<fn>`. This is what SIR, the VM dispatch, the inventory, and
  diagnostics key on. No exceptions (resolves D1 by rule).
- Source-level surface MAY use a short name; the short→qualified mapping is part
  of the entry record (`source_name` field), exactly the existing
  `TEXT_STDLIB_FNS` / `MAP_STDLIB_FNS` pattern, now made uniform.
- Monomorphization (`stdlib.numeric.*` → `stdlib.<type>.*`) is the one sanctioned
  case of a name rewrite inside the pipeline; both names are recorded
  (`generic_name` / `monomorph_names`).
- `?`-suffix predicates: do not adopt until a parser accepts them anywhere;
  rename to `is_some` / `is_ok` style at reconciliation if promoted.

---

## 4. Stdlib Entry Contract

The core artifact. One machine-readable record per entry; the sorted, canonical-
JSON inventory of all records is hashed → `stdlib_surface_digest` (PROP-036
pattern; RES-001 §3.1 seed, extended here). The compiler pins the digest; the VM's
`stdlib.unsupported.*` refusal checks against the same inventory.

```jsonc
{
  "canonical_name": "stdlib.option.or_else",          // qualified, lowercase, REQUIRED
  "source_name": "or_else",                           // short form accepted in source; null if same
  "aliases": ["or_else (bare SIR name, legacy v0)"],  // every historical name, never silently dropped
  "category": "option",                               // one of the category model (§6)
  "fragment_class": "core",                           // CORE | ESCAPE — fixed, never context-dependent
  "purity": "pure",                                   // pure | effect (effect ⇒ capability param required)
  "signature": {
    "type_params": ["V"],
    "inputs": ["Option[V]", "V"],
    "output": "V"
  },
  "deterministic": true,                              // false requires an explicit entropy capability
  "totality": "total",                                // total | "partial: <honest surface>" (Option/Result/outcome-kind — never exception/UB)
  "failure_behavior": "none — fallback covers empty", // what the caller observes on the partial path
  "diagnostics": ["OOF-MAP3"],                        // OOF codes this entry can emit at typecheck
  "authority_surface": "none",                        // none | "capability: <type>" — grant fields do not exist (schema-absent, same rule as packages)
  "lowering": {
    "ruby_production": "typechecker infer_or_else + evaluator",
    "rust_vm": "vm.rs dispatch",
    "kernel_only": false                              // true = proven in kernel, no runtime path (D5)
  },
  "stability": "production",                          // canon-accepted | production | kernel-proven | experiment-pass | example-only | convention | reserved
  "proof": ["experiments/...", "PROP-043 P1"],        // every proof artifact backing the entry
  "lineage": "PROP-043",                              // owning proposal
  "since": "stdlib-surface 0.1.0"
}
```

Field notes:
- `stability` is ordered and honest about D5: `canon-accepted` (Ch8 normative) is
  *not* above `production` — they are orthogonal axes collapsed today; the
  `lowering` block carries the executable truth separately.
- `authority_surface` follows the package model's mechanism-not-policy rule:
  there is no "grants" field to misuse; an effectful entry names the capability
  *type it consumes as a parameter*, nothing else.
- `aliases` is the churn ledger (§9): renames are recorded, never erased.

---

## 5. Inclusion Criteria

An entry qualifies for stdlib iff ALL hold (RES-001 Q2 base, tightened):

1. **Cross-domain demand** — needed by ≥2 independent proof domains (the
   PROP-047 method). Single-domain need stays domain-local. (Map v0 passes
   retroactively: RACK headers + query projections. LAB-PURSUIT fixed-point
   passes for abs/min/max/clamp: pursuit + any numeric domain.)
2. **Tier-decidable** — fragment_class fixed at declaration, never inferred from
   context.
3. **Total or honestly partial** — partiality surfaces as Option/Result/
   outcome-kind. No exceptions, no UB, no silent saturation.
4. **Deterministic or explicitly capability-gated** — no ambient clock
   (`now()` is OOF-L6 precedent), no ambient randomness, no ambient IO.
5. **Typed signature expressible today** — if the signature needs machinery the
   type system lacks (higher-order `fn` params for `map`/`fold` at runtime,
   trait bounds), the entry stays `reserved` until the substrate lands. This is
   why §8.2 collection ops are stuck pre-Slice-A: honest `reserved`/
   `kernel-proven` marking beats pretending.
6. **Proof coverage at the bar of §8** before any stability above
   `example-only`.
7. **No hidden authority, no domain-local leakage** — names and semantics must
   make sense outside the domain that demanded them (`map_get` yes;
   `zem_intercept_time` never).

---

## 6. Category Model

| Category | Ready? | Evidence basis |
|---|---|---|
| `text` | **READY** — reference category | full three-way agreement, 14 ops, OOF set, unit-qualified model |
| `map` | **READY** | PROP-043 v0 closed; String keys only; OOF-MAP2 boundary holds |
| `option` / `result` | **READY for reconciliation** (not growth) | proven monadic surface; needs D1/D2 resolved + entry records; growth waits for sum-types (PROP-044 P2+) |
| `collection` | **SPLIT** | count: production. fold/map/filter/...: kernel-proven, `reserved`-marked until Slice A or higher-order signatures; find/any/all/zip/range: example-only triage |
| `numeric` / `math` | **HOLD (D4)** | operator parity (STAB-P4) gates everything; demand is proven (LAB-PURSUIT N0/N1 lists: abs/min/max/clamp/compare/sign + isqrt/ipow/imuldiv) but inclusion before parity bakes divergence in |
| `datetime` / `temporal` | **HOLD (D3)** | disjoint spec/example name sets; triage first; `as_of`/TemporalCtx discipline (OOF-L6) is the fixed point to preserve |
| `outcome` (KDR helpers) | **OPEN as `stability: convention`** | RES-001 Q3: the deepest gap — canon defines the unknown-state model (Ch12+P15), stdlib gives zero combinators, so proofs flatten epistemic outcomes into ad-hoc `kind:` records (memory: igniter-epistemic-outcome-canon-vs-lab). Recognizers (`is_unknown`, `requires_reconciliation`, `partition_partial`) shippable convention-level pre-sum-types, whole module marked superseded-by-variants |
| `query` helpers | **DOMAIN-LOCAL** | stays in the query surface (LAB-QUERY-* boundary), not stdlib |
| `capability`/`effect` helpers, `io`/`net`/`storage` | **DOMAIN-LOCAL / L3-reserved** | lab io.ig shape (capability param + Result) is the right *pattern*; surface stays closed until effect-surface stdlib is separately authorized |
| `bool` | **DO NOT CREATE** | `stdlib.bool.and` is operator lowering, not a library category; fold into operator semantics |

---

## 7. Blind Spot Inventory

Named gaps, with demand evidence:

- **Outcome/KDR combinators** — the canon-defined model nobody can use from
  stdlib (Ch12, P15, PROP-044/047). Highest-leverage gap; every effectful proof
  domain re-invents it.
- **Numeric core N0**: `abs, min, max, clamp, compare, sign` — forced into
  hand-written fixture contracts by LAB-PURSUIT-P1. Blocked by D4, but the
  *entry records* can be authored now with `stability: reserved`.
- **Numeric N1**: `isqrt, ipow, imuldiv` (integer fixed-point kernel) — same.
- **Option ergonomics**: only `or_else` is executable; `is_some/map/flat_map`
  proven-but-shelf-bound; asymmetry pushes fixtures toward Map-shaped
  workarounds.
- **Predicate/filter helpers** — `find/any/all` example-proven, in limbo.
- **Collection structural ops** — `zip/range/concat` example-or-VM-only.
- **Text gaps** acknowledged in Ch8 §8.10.8 (deferred items) — correctly
  deferred, just listing for completeness.
- **Error/failure naming helpers** — no stdlib vocabulary for constructing
  honest failure records; interacts with outcome combinators, same route.

---

## 8. Proof Requirements

Bar for any entry to reach a given stability (each level includes the previous):

| Stability | Required proof |
|---|---|
| `example-only` | appears in a passing example fixture |
| `experiment-pass` | dedicated proof runner: typechecker positive + negative (each declared OOF fires), SemanticIR shape (qualified name present, correct type), determinism (re-run hash-stable) |
| `kernel-proven` | + kernel execution cases (PROP-013 pattern) |
| `production` | + Ruby pipeline lowering proven end-to-end (parse→TC→SIR→manifest), regression suites of adjacent categories re-run |
| `canon-accepted` + executable | + Rust VM dispatch parity case (same inputs, same outputs both toolchains — the dual-toolchain parity rule that STAB-P4 enforces for operators, applied per stdlib entry), closed-authority assertion (no capability/profile/runtime fields emitted), entry record present in inventory and inventory hash updated |

Plus per-category regression matrix: any change to a category's entries re-runs
that category's full proof set. Aggregates must additionally prove
`aggregated_from` evidence preservation (Ch8 §8.7).

---

## 9. Compatibility / Versioning Boundary

- **Pre-v1: no external compatibility promise.** Consistent with the package
  research (versions are labels on digests) and the namespace card (pre-v1
  breaking corrections are routine).
- **But canonical names must stop churning now.** The `String`→`Text`
  supersession worked because nothing external existed; the entry contract's
  `aliases` field is the mechanism that makes future renames recorded rather than
  silent. Rule: a canonical_name may change only with the old name appended to
  `aliases` and the inventory hash bumped — deletion of a name from the record
  is forbidden.
- **Stdlib surface identity**: `stdlib_surface_digest` = hash of the canonical
  inventory (PROP-036 pattern). Compiler profiles pin it; this is also exactly
  the object LAB-PACKAGE-MODEL-P1-a2 needs for "stdlib = the package the
  compiler vouches for" (finding 10) — the digest slots into compiler_profile
  pinning without any package machinery.
- No package manager, no registry, no distribution: closed, unchanged.

---

## 10. Relationship To Packages

Explicit separation (one rule each):

- **Stdlib** is language-owned: identity = inventory digest pinned by the
  compiler profile; trust = the compiler vouches; resolution = compiler-known
  names; growth = PROP + proof, never installation.
- **Packages** are external sealed claim artifacts: identity = package_digest
  over source units; trust = recomputation by the consumer; resolution = module
  import; growth = acquisition outside the compiler.
- Stdlib is **not** "just a package in v0": it has no source_units to recompute
  (intrinsics), and its trust position is constitutive, not verified. The
  RES-001 Q1 target state (self-hosted stdlib written in Igniter) would
  *converge* the mechanisms later — at that point stdlib becomes the first
  first-party package, pinned by digest like any other but vouched via the
  profile. That convergence is design direction, not v0.
- Distribution remains closed for both.

---

## 11. Relationship To Forms / Typed Refs

- **Typed refs** (`uses ContractName`) anchor to *contracts*; stdlib entries are
  *functions*, not contracts, so today they cannot be `uses` targets — correct
  and no change proposed. If RES-001's option C (contract-shaped stdlib) ever
  lands, stdlib entries gain contract_refs and become typed-ref targets
  naturally; the entry contract's `signature` block is written to be forward
  compatible with that (inputs/outputs shape mirrors contract ports).
- **Form vocabularies** (LANG-FORM-VOCABULARY-P1/P2): vocabulary triggers must
  resolve to contract refs (V-5/OOF-FORM1), so stdlib functions cannot be form
  targets in v0 either. V-9 (language-primitive reservation) and C-7
  (MultiKeyword restricted to System/Stdlib) already anticipate stdlib's special
  position: the inventory gives V-9 a concrete closed list of reserved names to
  check against — a free consumer of this card's artifact.
- No implementation opened on either edge.

---

## 12. Recommendation

**CLOSED — SPLIT.** Not HOLD (the entry-contract shape is concrete and two
categories are reference-quality); not a single OPEN proposal (D1–D4 drift must
be resolved by named owners, and the numeric/datetime categories are explicitly
gated).

The split: one proposal track for the entry contract + inventory (resolving
D1/D2/D5 inside it), and targeted proof/triage tracks per gated category
(D3 datetime, D4 numeric), plus the outcome-combinator track that RES-001 Q3 and
the epistemic-outcome lineage both demand.

---

## 13. Next Routes

| Card | Scope | Gate |
|---|---|---|
| **LANG-STDLIB-ENTRY-CONTRACT-P1** | Author the entry-contract schema + reconciled inventory as a canon proposal; resolve D1 (qualify `or_else`), D2 (`wrap`→alias), D5 (stability/lowering axes); produce `stdlib_surface_digest` definition | none — ready now |
| **LAB-STDLIB-OUTCOME-P1** | Convention-level KDR recognizers/combinators proof (`is_unknown`, `requires_reconciliation`, `partition_partial`); `stability: convention`, superseded-by-variants marked | PROP-044/047 conventions (present) |
| **LAB-STDLIB-OPTION-P1** | Option/Result reconciliation proof: executable parity for the proven monadic surface, D2 closure evidence | entry-contract P1 |
| **LAB-STDLIB-COLLECTION-P1** | Triage example-only names (find/any/all/zip/range/concat); mark §8.2 ops `reserved` vs promotable; Slice A dependency stated honestly | entry-contract P1 |
| **LAB-STDLIB-MATH-P1** | Numeric inventory proof: author N0/N1 entry records as `reserved`; parity prerequisite explicit | **D4 — STAB-P4 operator parity** |
| **LAB-STDLIB-DATETIME-P1** | D3 triage: per-name promote/rename/drop between Ch8 §8.6 and datetime_extension sets | entry-contract P1 |

Acceptance bar of this card: inventory classified (§2), entry contract concrete
(§4), inclusion criteria explicit (§5), blind spots named (§7), next route
concrete (§13), packages separated (§10) — all met.
