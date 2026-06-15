# App Pressure Rollup v0

**Date:** 2026-06-12
**Card:** LAB-APP-PRESSURE-ROLLUP-P1
**Route:** GOVERNANCE / BACKLOG SHAPING / NO IMPLEMENTATION
**Scope:** advanced_logistics, vector_editor, decision_tree, vector_math, spreadsheet, bookkeeping, erp_logistics
**Status:** closed — decisions recorded

---

## 1. Pressure IDs by App

### advanced_logistics (4 files; AL)

Blocked at multifile_resolve: `OOF-IMP2 stdlib.collection` in 2 modules.
Probe (import removed): Rust ok; Ruby `call_contract` + `<` gaps.

| ID | Status | Cluster | Summary |
|----|--------|---------|---------|
| AL-P01 | ACTIVE | stdlib-import | `import stdlib.collection.{ map/filter }` → OOF-IMP2 |
| AL-P02 | POSITIVE | map/filter | bare filter/map work in Rust probe — import is the barrier |
| AL-P03 | ACTIVE | call_contract | `call_contract("FindFeasibleOrders", ...)` — Ruby OOF-TY0 |
| AL-P04 | ACTIVE | numeric-operator | Ruby `Unsupported operator: <` — Integer capacity check |
| AL-P05 | HISTORICAL | inline-record-HOF | inline record in map lambda avoided; no current proof |
| AL-P06 | DESIGN | method-call-syntax | `stdlib.collection.map(...)` not valid call target |
| AL-P07 | DEFERRED | math | `sqrt` avoided via squared distance; deferred |

---

### vector_editor (4 files; VE)

Blocked at multifile_resolve: `OOF-IMP2 stdlib.collection` in `VectorDocument`.
Probe: Rust → `append` unknown callee; Ruby → `call_contract` + `==` operator.

| ID | Status | Cluster | Summary |
|----|--------|---------|---------|
| VE-P01 | ACTIVE | stdlib-import | `import stdlib.collection.{ append, map }` → OOF-IMP2 |
| VE-P02 | ACTIVE | append | `append` unknown — after import fix → OOF-IMP3 then Rust unknown callee |
| VE-P03 | ACTIVE | call_contract | `call_contract("AddObjectToDoc", ...)` × 3 — Ruby OOF-TY0 |
| VE-P04 | ACTIVE | text-equality | `state.active_tool == "draw_rect"` — Ruby `Unsupported operator: ==` |
| VE-P05 | WATCH | adt-variant | `kind: String` + optional payload fields — unsafe ADT surrogate |
| VE-P06 | WATCH | app-state | `(Document, ToolState, Point) -> Document` reducer shape |
| VE-P07 | WATCH | numeric | Integer coordinates workaround for Float/Decimal gaps |

---

### decision_tree (4 files; DT)

Blocked at multifile_resolve: `OOF-IMP2 stdlib.collection` in 3 modules.
Probe: Rust → `append` × 4; Ruby → `label` keyword + `==` operator.

| ID | Status | Cluster | Summary |
|----|--------|---------|---------|
| DT-P01 | ACTIVE | stdlib-import | `import stdlib.collection.{ append/filter }` → OOF-IMP2 × 3 modules |
| DT-P02 | ACTIVE | ruby-parser | Ruby `ParseError: Expected name, got keyword(label)` — reserved keyword |
| DT-P03 | ACTIVE | append | `append` OOF-IMP3 after import fix + Rust unknown callee × 4 |
| DT-P04 | ACTIVE | find-one | `FindNodeById` / `LookupFeature` return `Collection[T]`; no head/first/find_one |
| DT-P05 | ACTIVE | text-equality | feature names, node kind tags — Ruby `Unsupported operator: ==` |
| DT-P06 | WATCH | traversal | fixed-depth unrolled traversal; no safe bounded recursion for trees |
| DT-P07 | ACTIVE | adt-variant | `TreeNode` uses `kind` + sentinel fields — unsafe ADT surrogate |
| DT-P08 | WATCH | invocation-shape | single-output `call_contract` collapses to scalar shape |

---

### vector_math (6 files; VM)

**Status: RUST BASELINE OK** — full compilation, 37 contracts, artifact hash verified.
Ruby blocked by `call_contract` (26) and `<` (8). Treated as positive regression fixture.

| ID | Status | Cluster | Summary |
|----|--------|---------|---------|
| VM-P01 | BASELINE | regression | Full Rust compile ok — artifact `sha256:289a586a...` |
| VM-P02 | POSITIVE | architecture | Pure contract math — no IO/capability/state |
| VM-P03 | WATCH | numeric | Integer milli-unit model (1000 = 1.0) — informal scale |
| VM-P04 | ACTIVE | unary-minus | `0 - N` instead of `-N`; parser unary minus gap |
| VM-P05 | ACTIVE | numeric-operator | `>=` / `<=` rewritten as nested `<`/`>` — ergonomic gap |
| VM-P06 | ACTIVE | call_contract | 26 Ruby `Unknown function: call_contract` — dominant Ruby blocker |
| VM-P07 | ACTIVE | numeric-operator | Ruby `Unsupported operator: <` × 8 |
| VM-P08 | WATCH | ruby-cascade | Record-shape diagnostics downstream of call_contract Unknown cascade |

---

### spreadsheet (3 files; SS)

**Rust: status ok** (after LAB-FUNCTION-RECURSION-P4 + LAB-RUBY-FUNCTION-RECURSION-P2).
Ruby blocked by `call_contract` and `map`.

| ID | Status | Cluster | Summary |
|----|--------|---------|---------|
| SS-P01 | POSITIVE | recursive-types | Recursive structural types (`Expr?`) compile in Rust |
| SS-P02 | RESOLVED | recursion | Managed recursion (`eval_expr` decreases fuel) — both toolchains |
| SS-P03 | RESOLVED | recursion | Mutual SCC (`eval_ref` + `eval_expr`) — both toolchains |
| SS-P04 | ACTIVE | option-arithmetic | `Float? + Float?` — Rust accepts silently; Ruby not yet reached |
| SS-P05 | ACTIVE | map/filter | Ruby `Unknown function: map` — blocks `CalculateGrid` |
| SS-P06 | DESIGN | call_contract | `call_contract("CalculateGrid", grid)` at API layer |
| SS-P07 | HISTORICAL | inline-record-HOF | Record literal vs block ambiguity — not exercised in current fixture |

---

### bookkeeping (3 files; BK)

Rust: oof on Decimal equality + Float literal.
Ruby: broadly blocked (call_contract, filter/map/sum/fold, ok/err, ==).

| ID | Status | Cluster | Summary |
|----|--------|---------|---------|
| BK-P01 | IMPROVED | multifile | Multi-file type visibility resolved in Rust multi-file mode |
| BK-P02 | ACTIVE | decimal | Rust: `cannot compare Decimal with Decimal` (==) |
| BK-P03 | ACTIVE | decimal | `0.00` inferred as Float; output expects `Decimal[2]` |
| BK-P04 | ACTIVE | map/filter/fold/sum | Ruby: unknown filter/map/sum/fold (hidden behind other blockers) |
| BK-P05 | ACTIVE | result-constructors | `ok(tx)` / `err(text)` — Ruby unknown function |
| BK-P06 | DESIGN | call_contract | `call_contract("VerifyBalancing", tx)` |
| BK-P07 | SUSPECTED | ruby-multifile-diag | Ruby attributes ledger nodes to `PostTransaction` — context smear |

---

### erp_logistics (4 files; ERP)

Rust: oof on Float operators. Ruby: broadly blocked (call_contract, filter/fold, <).

| ID | Status | Cluster | Summary |
|----|--------|---------|---------|
| ERP-P01 | POSITIVE | multifile | Full closure compile works in Rust |
| ERP-P02 | ACTIVE | float-operator | Rust `Type mismatch for <: expected Integer, got Float < Float` |
| ERP-P03 | ACTIVE | float-operator | Rust `Float*Float` path returns Integer — type mismatch |
| ERP-P04 | HISTORICAL | unary-minus | `-1.0` parser failure — not in current fixture; needs fresh proof |
| ERP-P05 | ACTIVE | map/filter/fold | Ruby: unknown filter/fold (hidden behind call_contract) |
| ERP-P06 | DESIGN | call_contract | `call_contract("CheckCapacity", shipment)` |
| ERP-P07 | TOOLING | build-closure | Compiler needs full source closure from tooling |
| ERP-P08 | SUSPECTED | ruby-multifile-diag | Ruby attributes warehouse nodes to `DispatchShipment` — context smear |

---

## 2. Duplicate-Pressure Clusters

### Cluster A — Stdlib Import Surface
**IDs:** AL-P01, VE-P01, DT-P01
**Count:** 3 apps — all blocked before TC by `OOF-IMP2 stdlib.collection`
**Status of route:** LANG-STDLIB-IMPORT-SURFACE-P1/P2 CLOSED — **P3 READY**
After P3: advanced_logistics fully unblocked; VE/DT hit OOF-IMP3 for `append` next.

### Cluster B — `append` Collection Helper
**IDs:** VE-P02, DT-P03
**Count:** 2 apps — collection building requires single-element append
**Status:** not in inventory; after import fix → OOF-IMP3 (inventory gap) + Rust unknown callee
**Route:** LANG-STDLIB-COLLECTION-APPEND-P1 (inventory entry + proof)
**Note:** `stdlib.collection.append` signature: `Collection[T] × T → Collection[T]`

### Cluster C — map / filter / count (regular-call)
**IDs:** AL-P02 (positive probe), BK-P04 (partial), ERP-P05 (partial), SS-P05
**Count:** 4 apps — dispatched in Ruby TC (LANG-STDLIB-COLLECTION-MAP-FILTER-PROP-P3)
**Status:** Ruby TC dispatch DONE; apps don't surface it cleanly because other blockers hide it
**Remaining:** inventory gap for fold/sum (see Cluster D); SS-P05 re-check needed after `map` is confirmed dispatched

### Cluster D — fold / sum (regular-call)
**IDs:** BK-P04 (fold), ERP-P05 (fold), plus fold/sum inventory gap
**Count:** 2 apps use fold; Ruby TC dispatches both (P3 done); NOT importable (not in inventory)
**Route:** LANG-STDLIB-FOLD-PROP-P4 (inventory amendment) + LANG-STDLIB-SUM-PROP-P4 (same)
**Note:** `import stdlib.collection.{ fold }` → OOF-IMP3 until P4 adds entries

### Cluster E — call_contract / Typed Refs / Forms
**IDs:** AL-P03, VE-P03, DT-P08, VM-P06, SS-P06, BK-P06, ERP-P06
**Count:** ALL 7 APPS — single most cross-cutting pressure
**Current state:** LANG-TYPED-CONTRACT-REF-PROP-P5 closed (cross-module typed refs); Ruby still emits OOF-TY0 for bare `call_contract`
**Gap:** Ruby `call_contract` dispatch parity — VM-P06 is the sharpest signal (26 diagnostics, pure app, no other blockers)
**Route:** LAB-RUBY-CALL-CONTRACT-PARITY-P1 or typed invocation follow-up

### Cluster F — Text Equality
**IDs:** VE-P04, DT-P05
**Count:** 2 apps active; Ruby `Unsupported operator: ==` for Text/String identifiers
**Route:** LANG-STDLIB-TEXT-EQUALITY-P1 (narrow deterministic equality over Text; not numeric ==)

### Cluster G — Numeric / Operator Parity
Three sub-clusters, distinct scope:

**G1 — Integer comparison (Ruby only):**
IDs: AL-P04, VM-P05, VM-P07 — Ruby `<` + `>=` / `<=` ergonomics
Route: LANG-NUMERIC-COMPARISON-PARITY-P1 / LAB-RUBY-OPERATOR-PARITY-P1

**G2 — Float operators (both toolchains):**
IDs: ERP-P02 (`Float < Float`), ERP-P03 (`Float * Float`)
Route: LAB-STDLIB-FLOAT-P1 (gated on numeric readiness)

**G3 — Decimal semantics:**
IDs: BK-P02 (Decimal ==), BK-P03 (Decimal literal: `0.00` → Float)
Route: LAB-STDLIB-DECIMAL-P1 (distinct from Float; financial domain)

### Cluster H — find_one / head / first
**IDs:** DT-P04
**Count:** 1 app active; `Collection[T]` → only `Collection[T]` outputs; no scalar extraction
**Route:** LAB-STDLIB-FIND-ONE-P1 (after append lands)

### Cluster I — ADT / Variant Surface
**IDs:** VE-P05, DT-P07
**Count:** 2 apps — both use `kind: String` + optional payload / sentinel fields as ADT surrogate
**Route:** PROP-044 P2+ variant/match extension; not a quick fix

### Cluster J — App-State / App-Assembly
**IDs:** VE-P06
**Count:** 1 app active; `(Document, ToolState, Point) -> Document` pure reducer shape
**Route:** app-state / app-assembly research track; no immediate card

---

## 3. Ranking Table

### MAINLINE — Unblock multiple apps; clear route; authorized or ready

| Rank | Card | Cluster | Apps unblocked | Why now |
|------|------|---------|----------------|---------|
| M1 | **LANG-STDLIB-IMPORT-SURFACE-P3** | A | AL, VE, DT (OOF-IMP2 removed) | P2 done; READY FOR P3; 3 apps blocked at resolver before TC |
| M2 | **LAB-VECTOR-MATH-BASELINE-P1** | — | VM (regression freeze) | Only app with Rust full-compile; must be frozen before more TC changes |
| M3 | **LANG-STDLIB-COLLECTION-APPEND-P1** | B | VE, DT (OOF-IMP3 + Rust) | Post-import next blocker; inventory entry needed before any other collection work in those apps |
| M4 | **LANG-STDLIB-TEXT-EQUALITY-P1** | F | VE, DT | Ruby == for Text — 2 apps, well-scoped, no numeric dependency |
| M5 | **LAB-RUBY-CALL-CONTRACT-PARITY-P1** | E | VM, SS, BK, ERP, AL, VE, DT | 7-app reach; VM is the cleanest signal (no other blockers in Rust) |

### NEAR BACKLOG — Clear route; currently upstream-blocked or secondary

| Rank | Card | Cluster | Apps | Why |
|------|------|---------|------|-----|
| B1 | **LANG-NUMERIC-COMPARISON-PARITY-P1** | G1 | AL, VM | Ruby `<` / `>=` / `<=` for Integer; well-scoped; VM unblocked after call_contract |
| B2 | **LAB-RUBY-MULTIFILE-DIAGNOSTICS-P1** | BK-P07, ERP-P08 | BK, ERP | Diagnostic attribution smear — undermines debuggability in multi-file mode; fix is parallel to other work |
| B3 | **LANG-STDLIB-FOLD-PROP-P4 + LANG-STDLIB-SUM-PROP-P4** | D | BK, ERP | Inventory amendments so fold/sum are importable; small scope |
| B4 | **LAB-STDLIB-FIND-ONE-P1** | H | DT | After append lands; DT-P04 is explicit; no other apps yet |
| B5 | **LAB-STDLIB-DECIMAL-P1** | G3 | BK | Decimal == + literal — financial domain; independent of Float track |

### WATCH — Design questions, single-app signals, or gated behind upstream

| Entry | Cluster | Apps | Gate |
|-------|---------|------|------|
| Variant/ADT surface | I | VE, DT | PROP-044 P2+ sum types; not quick |
| App-state/assembly | J | VE | Research track; not actionable yet |
| LAB-STDLIB-OPTION-P1 | — | SS | SS-P04: Rust accepts `Float? + Float?` silently — needs audit |
| LAB-STDLIB-FLOAT-P1 | G2 | ERP | Float < + Float * — gated on numeric readiness; don't conflate with Decimal |
| LANG-PARSER-UNARY-MINUS-P1 | VM-P04 | VM, ERP | Unary minus — both apps avoid it; needs fresh minimal fixture |
| DT-P02 (Ruby keyword `label`) | — | DT | Ruby parser reserved-keyword hygiene; fix is narrow but gated on Ruby parser work |
| LAB-PARSER-RECORD-IN-HOF-P1 | AL-P05, SS-P07 | AL, SS | Historical — needs fresh minimal fixture before opening |
| LAB-STDLIB-MATH-P1 | AL-P07, VM-P03 | AL, VM | sqrt / scale-aware numeric; well after operator work |
| Result constructors (ok/err) | BK-P05 | BK | Gated on Option/Result reconciliation (LAB-STDLIB-OPTION-P1) |
| ERP-P07 (build closure tooling) | — | ERP | Tooling, not language semantics |

---

## 4. Recommended Next 10-Card Sequence

Order is sequencing recommendation, not strict dependency. Cards marked `(parallel)` can start concurrently.

| # | Card | Priority lane | Gate | Expected outcome |
|---|------|---------------|------|-----------------|
| 1 | **LANG-STDLIB-IMPORT-SURFACE-P3** | mainline | P2 READY | Ruby MultifileResolver stdlib table; ≥61 proof checks; AL/VE/DT pass OOF-IMP2 barrier |
| 2 | **LAB-VECTOR-MATH-BASELINE-P1** | mainline (parallel) | none | Freeze VM as Rust 37-contract regression fixture; artifact hash locked |
| 3 | **LANG-STDLIB-COLLECTION-APPEND-P1** | mainline | after import P3 | Inventory entry `stdlib.collection.append: Collection[T]×T→Collection[T]`; OOF-IMP3 resolved; VE+DT unblocked |
| 4 | **LANG-STDLIB-TEXT-EQUALITY-P1** | mainline (parallel with 3) | none | Text == operator in Ruby; VE-P04 + DT-P05; narrow deterministic equality only |
| 5 | **LAB-RUBY-CALL-CONTRACT-PARITY-P1** | mainline | after VM baseline | Decision card: Ruby call_contract dispatch parity; uses VM as cleanest single-signal fixture |
| 6 | **LANG-NUMERIC-COMPARISON-PARITY-P1** | near backlog | after call_contract | Ruby `<`, `<=`, `>=` for Integer; AL-P04 + VM-P07; scoped to Integer only |
| 7 | **LAB-RUBY-MULTIFILE-DIAGNOSTICS-P1** | near backlog (parallel) | none | Minimal fixture for diagnostic attribution in merged universe; BK-P07 + ERP-P08 |
| 8 | **LANG-STDLIB-FOLD-PROP-P4 + LANG-STDLIB-SUM-PROP-P4** | near backlog | after P3 import | Inventory amendments for fold+sum; makes `import stdlib.collection.{ fold }` valid |
| 9 | **LAB-STDLIB-FIND-ONE-P1** | near backlog | after append | DT-P04; `head`/`first`/`find_one` semantics; distinct from filter |
| 10 | **LAB-STDLIB-DECIMAL-P1** | near backlog | after integer parity | BK-P02 + BK-P03; Decimal equality + Decimal literal; parallel with Float track |

**Not in the 10:** Float operator parity (ERP-P02/P03) — important but gates on broader numeric readiness and should not absorb the same slot as Decimal.

---

## 5. Stale and Contradictory Findings

### S1 — Optional-Field Omission: Silent Rust Leniency (HIGH CONCERN)

**Location:** SS-P04 (spreadsheet); `Float? + Float?`
**Finding:** After recursion was resolved, Rust reports `status: ok` for the spreadsheet, which includes `left_val.num_val + right_val.num_val` where `num_val : Float?`. Rust accepts this without diagnostic.

**Problem:** This may indicate that the Rust typechecker silently treats `Float?` as `Float` for arithmetic — dropping the optionality without error. If so, the "clean" compile is incorrect: arithmetic over nullable fields should either require explicit unwrapping or produce a typed `Float?` result, not silently succeed as `Float`.

**Contradicts:** The spreadsheet's "Rust ok" status is cited as a positive signal across multiple findings. If Rust is silently coercing `Float?` → `Float` in arithmetic, this positive signal may be masking a type safety gap.

**Recommendation:** Before using `SS-P01` (recursive types) or the spreadsheet Rust clean-compile as evidence for anything numeric, audit `Float? + Float?` behavior with a minimal fixture. Route to LAB-STDLIB-OPTION-P1 for resolution.

---

### S2 — Optional-Field Omission: Unsafe ADT Surrogate (STRUCTURAL STALE)

**Location:** VE-P05, DT-P07 — `kind: String` + optional payload fields
**Finding:** Both apps use optional fields to simulate variant records. The pressure reports acknowledge this is "ergonomically valuable, but not enough." Both compilers accept the pattern without complaint.

**Stale aspect:** The registries log this as a "watch" or "design pressure" — implying it works *and* is just ergonomically awkward. But it is not merely ergonomic: a record with `kind: "text"` and a populated `rect_data` field is *semantically invalid* and the compiler currently accepts it without error. This is a correctness gap, not an ergonomics gap.

**Recommendation:** Re-classify VE-P05 and DT-P07 as `CORRECTNESS` not `WATCH`. The PROP-044 P2+ route is correct, but framing matters — this is not "variant/ADT is optional comfort" but "variant/ADT is required for correctness in these apps."

---

### S3 — BK-P01 "Improved" Framing May Be Misleading

**Location:** BK-P01 (bookkeeping)
**Finding:** Marked "improved / monitor" because Rust multi-file mode resolves `Transaction.postings` field visibility. Single-file mode still fails.

**Stale aspect:** "improved" suggests partial progress toward a fix. But the real situation is: single-file compilation with missing imports was always broken by design; multi-file compilation was designed to require the full source closure. There is no partial fix here — the behavior is correct. BK-P01 should be marked CLOSED with the note "expected behavior; single-file without full closure is designed to fail."

---

### S4 — Unary Minus: Two Stale Parallel Findings

**Location:** VM-P04, ERP-P04
**VM-P04:** Source uses `0 - N` forms instead of `-N` — Rust compiles with this workaround.
**ERP-P04:** Original report mentioned `-1.0` parser failure; *current fixture does not exercise it*.

**Contradiction:** VM-P04 confirms the workaround is live; ERP-P04 is historical and may no longer reflect current behavior. They are treated as separate pressures in separate registries when they are the same root cause.

**Recommendation:** Merge into a single route: `LANG-PARSER-UNARY-MINUS-P1`. Verify with a current minimal fixture covering both integer (`-200`) and float (`-1.0`) forms. Until that fixture exists, ERP-P04 should be classified `historical/needs-fresh-proof`, not `active`.

---

### S5 — Inline Record in HOF: Two Stale Parallel Findings

**Location:** AL-P05, SS-P07
**AL-P05:** App avoids `{ ... }` inside map lambda after "parser ambiguity reports."
**SS-P07:** `cell -> { id: cell.id, val: eval_expr(...) }` might parse as a block.

**Issue:** Neither current fixture exercises the shape. Both are workarounds that may no longer be needed — or may still be needed but are untested. There is no current proof either way.

**Recommendation:** Merge into one pressure: `LAB-PARSER-RECORD-IN-HOF-P1`. Require a current minimal fixture before treating as active. The workaround absence makes it invisible in app pressure, not resolved.

---

### S6 — SS-P05 (`map` Unknown in Ruby) — Potentially Stale After P3

**Location:** SS-P05 (spreadsheet)
**Finding:** "Ruby: Unknown function: map" — logged as active pressure for the spreadsheet app.
**Stale risk:** LANG-STDLIB-COLLECTION-MAP-FILTER-PROP-P3 added `map` dispatch to Ruby TC. If the spreadsheet Ruby compile were re-run today, `map` may no longer be "Unknown function." Instead, Ruby might be blocked by `call_contract` (SS-P06) before it even reaches the `map` call.

**Recommendation:** Re-run spreadsheet Ruby compile and update SS-P05 to reflect current state. The pressure registry's "active" label likely reflects the state before PROP-P3. If `map` is now dispatched, SS-P05 should be reclassified to "cascade from call_contract" or marked resolved pending call_contract parity.

---

### S7 — Ruby Multi-File Diagnostic Attribution: Under-Weighted Finding

**Location:** BK-P07, ERP-P08
**Finding:** Both are "suspected toolchain issue" — Ruby appears to attribute ledger/warehouse contract nodes to the entrypoint contract (PostTransaction / DispatchShipment).

**Problem:** This is treated as a minor quality issue. But if diagnostic `contract` attribution is wrong in multi-file mode, it corrupts the diagnostic context for every multi-file Ruby compile. Developers debugging a bookkeeping issue would see errors pointing to the wrong contract. This is not a "suspected" issue — it is a confirmed UX defect in merged-universe TypeChecker diagnostics.

**Recommendation:** Raise priority to NEAR BACKLOG. The fix (`LAB-RUBY-MULTIFILE-DIAGNOSTICS-P1`) is probably narrow — the TypeChecker needs to preserve the declaring contract's identity during merged-universe inference rather than propagating the entrypoint's context. This should be fixed before Ruby multi-file diagnostics are trusted in any debugging context.

---

## 6. App Status Snapshot

| App | Rust | Ruby | First blocker | Unblock card |
|-----|------|------|---------------|-------------|
| **vector_math** | ✅ OK (37 contracts) | ❌ call_contract × 26, `<` × 8 | call_contract | LAB-RUBY-CALL-CONTRACT-PARITY-P1 |
| **spreadsheet** | ✅ OK (recursion resolved) | ❌ call_contract, map | call_contract → map (cascade) | LAB-RUBY-CALL-CONTRACT-PARITY-P1 |
| **advanced_logistics** | ❌ OOF-IMP2 | ❌ OOF-IMP2 | stdlib.collection import | LANG-STDLIB-IMPORT-SURFACE-P3 |
| **vector_editor** | ❌ OOF-IMP2 | ❌ OOF-IMP2 | stdlib.collection import | LANG-STDLIB-IMPORT-SURFACE-P3 |
| **decision_tree** | ❌ OOF-IMP2 × 3 | ❌ OOF-IMP2 + keyword | stdlib.collection import | LANG-STDLIB-IMPORT-SURFACE-P3 |
| **erp_logistics** | ❌ Float `<` + `*` | ❌ call_contract, filter/fold | Float operators | LAB-STDLIB-FLOAT-P1 (gated) |
| **bookkeeping** | ❌ Decimal == + literal | ❌ call_contract, filter/map/sum/fold | Decimal semantics | LAB-STDLIB-DECIMAL-P1 |

---

## 7. Authority Closed

No implementation. No app source edits. No stdlib, TC, parser, VM, or import resolver changes.
This document is routing evidence only.
