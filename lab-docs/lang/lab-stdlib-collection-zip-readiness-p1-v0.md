# Collection `zip` / paired-iteration — readiness packet (P1 v0)

Card: `LAB-STDLIB-COLLECTION-ZIP-READINESS-P1`. Date: 2026-06-24. **Authority: lab readiness.
Recommendation, not implementation. No code changes.**

## Verify-first headline (the card's assumption is outdated)

**`zip` already exists in live source** — it does not need designing from scratch. The real readiness
question is therefore *validate + lock semantics*, not *invent*:

- Declared: `lang/igniter-stdlib/stdlib/collections.ig:13` —
  `def zip(a: Collection[A], b: Collection[B]) -> Collection[Pair[A, B]]`.
- Typechecker arm: `lang/igniter-compiler/src/typechecker/stdlib_calls.rs:789` — synthesizes the return type
  `Collection[Pair[A, B]]` from the two input element types.
- VM, **both dispatch paths, byte-for-byte identical** (eval_ast `vm.rs:1817`, bytecode `vm.rs:4920`;
  normalized name at `vm.rs:849`):
  - exactly 2 args, each must be an array (else deterministic error);
  - **unequal lengths → silent truncate to `min(len_a, len_b)`** (`std::cmp::min`);
  - each element is `Value::Record{ first, second }` (a `BTreeMap`, deterministic key order).
- **No test or fixture exists for `zip`** (`rg zip lang/igniter-vm/tests lang/igniter-compiler/tests` →
  none). It is **wired but unproven** end-to-end. `igniter-delta-1.md` still lists `zip` as a 🟡 "would be
  nice" stdlib item — stale.

So `zip` is implemented, parity-clean, deterministic — but (a) untested, (b) its **silent truncation** is a
correctness hazard for paired science, and (c) its `Pair` is synthetic (see below).

## 1. Current collection / HOF capability (live)

| op | typecheck | VM (eval_ast + bytecode) | nested-in-HOF |
| --- | --- | --- | --- |
| `map`, `filter`, `sum`, `count`, `append`, `concat`, `range`, `fold`/`reduce` | yes | yes | yes (P3/P4 recovery) |
| `filter_map`, `reduce` | yes | yes | **no eval_ast arm** → forbidden nested (`OOF-COL-NESTED`) |
| **`zip`** | yes (`:789`) | yes, parity-clean (`:1817`/`:4920`) | wired; **not test-proven nested** |
| record construction in a lambda (`x -> ({a: …})`) | yes | yes (parenthesized; `record_construction_in_lambda_tests.rs`) | yes |

Other live facts that shape the design:
- **User-defined generics do not exist.** A user cannot write `type Pair[A, B] { … }`
  (`parser.rs` `TypeDecl` has no type-params; only *contracts* take `[T: Bound]`). Generics are limited to
  built-in constructors (`Collection[T]`, `Option[T]`, `Result[T,E]`, `Map[K,V]`) plus the **synthetic
  `Pair[A,B]`** that only `zip`'s typecheck arm produces. The runtime `Pair` is just a `Record{first,second}`.
- **Pair field-access typing is unverified.** Whether `p.first` / `p.second` resolves to `A` / `B` (vs falling
  to `Unknown`) on a `zip` result is not test-covered — a validation item, not a known-good.
- Statistics P2 (`mean/variance/stddev`) are pure `.ig` over `Collection[Float]`; its closing report names
  `covariance`/`correlation` as needing exactly this paired iteration.

## 2. Alternatives compared

| # | option | pros | cons | verdict |
| --- | --- | --- | --- | --- |
| 1 | **Adopt existing `zip` → `Collection[Pair[A,B]]` + `map`** | zero code; already wired both paths; general (any element types, not Float-only); records-in-lambda proven | silent min-truncation hazard; Pair typing maybe `Unknown`; untested | **RECOMMENDED** (with §3 length guard + §5 proof) |
| 2 | `zip_with(a, b, (x,y) -> z) -> Collection[Z]` fused HOF | no Pair record allocation; reads cleanly for stats | new builtin; **already expressible** as `map(zip(a,b), p -> f(p.first,p.second))` | defer as ergonomic follow-on |
| 3 | internal paired reduction only (`paired_fold` / bespoke `covariance` builtins; no public pair surface) | can enforce equal length internally; no Pair exposure | hides a reusable primitive; bespoke Rust per stat; duplicates `zip` | reject as primary |
| 4 | change `zip` to **error/`none` on length mismatch** (strict) | safest against silent corruption | **breaks the already-wired contract**; truncate is a legitimate primitive (Python/Elixir parity) | reject — guard at the *consumer*, not the primitive |
| 5 | index-based `range` + element `get` | no new pair type | no clean random-access `get`; more error-prone; `zip` strictly better | reject |

## 3. Recommended v0 surface

**Adopt the existing `zip` as the v0 paired-iteration primitive, unchanged**, and put the safety at the
consumer layer:

- **Primitive contract (lock as-is):** `zip(Collection[A], Collection[B]) -> Collection[Pair[A,B]]`, where
  `Pair` is the synthetic `Record{ first, second }`. Pairing is positional; **unequal lengths truncate to the
  shorter** (documented, Python/Elixir-consistent, deterministic).
- **Paired iteration uses `map` over `zip`:** e.g. `map(zip(xs, ys), p -> (p.first - mx) * (p.second - my))`.
  No `zip_with` primitive is needed for v0 (it's `map`∘`zip`).
- **Science safety = consumer length guard, not a primitive change.** Any paired *statistic* MUST guard equal
  length explicitly before zipping — `if count(xs) != count(ys) { none() } else { … }` — so silent truncation
  can never quietly corrupt a covariance/correlation. The primitive stays permissive; the *statistic* is
  strict. This mirrors stats P2's `Option`-guarded empty handling.

## 4. Unequal-length semantics (decision)

| layer | behavior |
| --- | --- |
| `zip` primitive | **truncate to `min(len_a, len_b)`** (current; keep). Deterministic, total, no error on mismatch. |
| paired statistics (downstream) | **strict**: unequal length → `none()` (never silently truncate a scientific input). |

Rationale: a low-level `zip` that errored on mismatch would be less composable and would break the existing
wiring; a statistic that silently dropped tail observations would be a correctness bug. Splitting the
responsibility keeps both honest. A future `zip_exact`/diagnostic can be added only if a real consumer pulls
it.

## 5. Determinism / performance

- **Deterministic by construction:** integer `min` + positional `clone`, no float math, fixed source order,
  `BTreeMap` (ordered keys) → stable serialization. Cross-arch identical (no libm dependence); same
  determinism story as `map`/`fold`. No `STDLIB_VERSION` bump needed if wiring is unchanged (proof-only).
- **Cost:** O(min(m,n)); one `Record` allocation per pair. The only avoidable cost is Pair materialization —
  the optional `zip_with` fusion (alt #2) removes it, a perf follow-on, not a v0 need.

## 6. Acceptance matrix — first implementation card

Recommended next card: **`LAB-STDLIB-COLLECTION-ZIP-PROOF-P2`** (prove + lock the existing `zip`; no new
primitive). Then the downstream stats card.

| id | card | scope | gate |
| --- | --- | --- | --- |
| ZIP-1 | `LAB-STDLIB-COLLECTION-ZIP-PROOF-P2` | e2e tests through real compiler+VM: truncate-to-min, `Pair{first,second}` shape, determinism/repeatability, top-level **and** nested-in-`map` use; verify `p.first`/`p.second` typing (resolves to `A`/`B` vs `Unknown`) — fix the typecheck arm only if field access is wrongly `Unknown`. | tests green; semantics documented in `collections.ig` + IMPLEMENTED surface |
| ZIP-2 | (same card) | document truncate-to-min as the contract; flag `zip_with` fusion + `zip_exact` as named, deferred follow-ons. | doc only |
| STATS-COV | `LAB-STDLIB-STATISTICS-COVARIANCE-CORRELATION-P3` (downstream **pressure, not implemented here**) | pure `.ig` `covariance`/`correlation : (Collection[Float], Collection[Float]) -> Option[Float]`; **equal-length guard → none()**; population covariance two-pass via `map`∘`zip`+`sum`+P2 `mean`; correlation = `cov/(sx*sy)` guarding zero variance → `none()`. | after ZIP-1 |

## 7. Downstream pressure (named, not implemented)

`covariance`/`correlation` are the immediate consumers (stats P2 closing report), plus: comparing two time
series (`r(t)` vs `Z_i(t)`), transfer-entropy preprocessing / surrogate alignment, vectorized residuals.
None are implemented in this packet.

## Bottom line

`zip` is **already implemented and parity-clean** — the readiness gap is **proof + a documented
unequal-length policy**, not design. Recommended v0 = adopt `zip` as-is (truncate-to-min) + a strict
equal-length guard in paired statistics; first card = `LAB-STDLIB-COLLECTION-ZIP-PROOF-P2`.
