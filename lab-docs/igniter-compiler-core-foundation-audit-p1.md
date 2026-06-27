# IGNITER-COMPILER-CORE-FOUNDATION-AUDIT-P1 - fresh verify-first audit of the native Rust compiler

Status: OPEN - findings (no code changed)
Lane: igniter-lab / lang / igniter-compiler / foundation-hardening
Type: audit / fresh verify-first
Date: 2026-06-26
Skill: idd-agent-protocol

> Refresh note 2026-06-27: this remains a 2026-06-26 audit snapshot. Some
> findings below have since closed; route current work through
> `lab-docs/igniter-foundation-hardening-roadmap-p1.md` and
> `lab-docs/lang/lab-audit-foundation-status-refresh-p2-v0.md`, not the
> `Status: OPEN` line alone.

## Onboarding

This is **lab/frontier evidence, not authority**: a code-first audit of the live
`igniter_compiler` (Rust, ~28.8k LOC src). It is not a canon language claim and
not a release gate. Approach (per project lead): go **fresh, code-first,
verify-first** — do NOT lean on PROPs/specs (they pull design back toward what
once seemed right). Read the live code; classify each finding BLOCKER / PROBLEM /
INSIGHT; name the high-leverage opportunities.

Covered (7 parallel subsystem audits, all file:line-verified): `lexer.rs`,
`parser.rs`, `typechecker.rs`, `typechecker/stdlib_calls.rs`, `classifier.rs`,
`liveness.rs`, `monomorphizer.rs`, `emitter.rs`, `assembler.rs`, `project.rs`,
`multifile.rs`, `form_resolver.rs`, `form_registry.rs`, `igweb.rs`.

## Executive Decision

```text
decision=AUDIT - the front end crashes on adversarial input and the type system leaks soundness upstream of the (correct) output boundary; integrity/supply-chain is computed but not enforced
severity=high: 4 reachable input-driven CRASH classes (2 reproduced), 6 UNSOUNDNESS holes, 3 INTEGRITY holes
root_cause=TWO - (1) the type-IR is stringly-typed (serde_json::Value), so every comparison degrades to name-only / Unknown instead of failing; (2) enforcement is THIN and mislocated - several guarantees are declared but not verified (FuelBounded termination, purity, lock-on-build)
good_news=the parts that are right are right: recursive output-boundary assignability (OOF-TY1), no implicit numeric coercion, now() fully forbidden, deterministic resolver core, duplicate/scope/export/cycle all fail-closed
keystone=replace the serde_json::Value type-IR with a real `enum IgType` -> makes the name-only soundness holes UNREPRESENTABLE
next=IGNITER-COMPILER-TYPE-IR-ENUM-P2 (keystone) + IGNITER-COMPILER-INPUT-ROBUSTNESS-P2 (depth-guard/panic-free parse) + IGNITER-COMPILER-LOCK-ON-BUILD-P2 (integrity)
architectural_decision_needed=yes - adopt a typed IgType; make liveness budgets early-return not observe-only
```

## Verify-first premise corrections (the code overturned three assumptions)

1. **The compiler is SINGLE-target, not dual host-codegen.** `emitter.rs` lowers a
   `TypedProgram` into a JSON **Semantic IR** (`semantic_ir_program.json`); there
   is no Ruby/Rust source emission here (no `emit_ruby`/`push_str`-into-source).
   "Dual-clean" = the Ruby `igc` and the Rust `igniter_compiler` emit the **same
   SIR**. → There is no host-codegen injection surface in the emitter (serde_json
   escapes everything); the real exposure is hard-coded lowering choices that must
   match the Ruby compiler + an unchecked emitter↔assembler structural contract.
2. **`igweb.rs` is route-authoring sugar, not the HTML view layer.** It lowers
   `.igweb` route DSL into explicit `.ig` source text (`lower_igweb`,
   `igweb.rs:515`); it emits zero HTML/attributes, no `link`/`safe_url`/escaping.
   The HTML-output-safety surface (the XSS-relevant code) lives in a **different
   crate** (`igniter-web` / `igniter-ui-kit/src/igv.rs`) and must be audited there.
3. **The classifier is a structural GATE, not the termination prover.**
   `classifier.rs` only checks declaration presence (OOF-R2/R4) and extracts the
   variant; the real shrinkage proof is downstream in
   `typechecker.rs::check_recur_in_expr`/`syntactic_decrease` + Tarjan SCC
   (`typechecker.rs:6778`). Auditing termination at the classifier alone would
   wrongly conclude the guarantee is fake. It is real, but thin (see B-U6).

## Root cause (two)

**R1 — the type-IR is stringly-typed.** Igniter types are represented as
`serde_json::Value` and compared via `type_name`/`get_param` string lookups. There
is no Rust-level `enum` for an Igniter type, so every typo, missing param, or
unresolved path **degrades to `Unknown`** (which passes) rather than failing the
build. This is the source of most unsoundness below (B-U1..U4, `==`, match
widening). The one place that does it right — the output boundary
(`structurally_assignable`, recursive over params, `OOF-TY1`) — proves the
architecture *knows* how to be sound; it just isn't applied uniformly upstream.

**R2 — enforcement is thin and mislocated.** Several headline guarantees are
*declared* but not *verified*: FuelBounded termination (literal presence only),
purity/effects (syntactic prefix scan only), the content-lock (computed, not
checked on build). Same shape as the TBackend audit's "audit guarantees are
aspirational, not enforced."

## BLOCKERS

### A. Crashes on input (compiler dies instead of diagnosing)

**B-C1. Parser stack overflow on deep nesting — no depth guard (REPRODUCED,
SIGABRT).** `parse_binary_or`/paren-primary recurse with no bound
(`parser.rs:3293, 3661`); a ~6 KB `.ig` of `((((1))))` / `[[[1]]]` overflows the
native stack (~5-6k depth). The liveness budgets (`liveness.rs`) don't cover the
parser. Headline blocker — arbitrary `.ig` files can take down the compiler.

**B-C2. Float-literal `from_f64().unwrap()` panic (REPRODUCED, exit 101).** A
float literal exceeding f64 parses to `INFINITY`; `Number::from_f64(inf)` is
`None`; `.unwrap()` panics. Two sites: `parser.rs:3630` (FloatLit), `parser.rs:1256`
(assumption strength).

**B-C3. Emitter index-panic on arity-free temporal lowering.** `history_at`/
`bihistory_at` are matched on `fn_name` and index `args[0..2]` with no arity check
(`emitter.rs:1851, 1894`) → index-out-of-bounds on a malformed call. Plus a
one-edit-from-live `unreachable!()` (`emitter.rs:2328`).

**B-C4. Assembler trusts the SIR shape — 2 `.expect()` + ~55 `.unwrap()`.**
`assembler.rs:19, 24` and pervasive `.get(...).unwrap()` (`:506, 511, 687, 1199,
1325, ...`) turn any dropped emitter field or external SIR into a process panic,
not an error. The emitter↔assembler boundary is an *unchecked structural
contract*. Linker-robustness blocker.

*(Related: several recursive passes have no depth guard and the liveness budget is
observe-only — `structurally_assignable`/`type_display` (`typechecker.rs:3225,
3260`), `TarjanScc::visit` (`:6736`), emitter lowering — so deep input can
stack-overflow the compiler in multiple stages. See B-U/liveness below.)*

### B. Unsoundness (ill-typed programs accepted)

**B-U1. User-defined `def` calls are never argument-checked.**
`typechecker.rs:4509-4514` matches by name, takes `f.return_type`, `break`s — no
arity, no arg-type check. Wrong-count/wrong-typed calls to app-local `def`s pass
silently. (stdlib calls *are* checked; user `def`s are not.)

**B-U2. Non-fold lambda params hardcoded to `Integer`; body errors discarded.**
`typechecker.rs:4652-4742` types every lambda param as `Integer` and routes the
body into a throwaway `temp_errors` never merged back → an ill-typed HOF lambda
body emits no diagnostic; param refs mis-type as Integer. Same defect in stdlib
`flat_map` (`stdlib_calls.rs:1541`).

**B-U3. Record-literal & variant-construct field checks compare outer type name
only.** `check_record_literal_shape` (`typechecker.rs:6253`) and
`infer_variant_construct` (`:5651`) compare `type_name` ignoring params → a field
declared `Collection[Integer]` accepts `Collection[Text]`; `Option[Integer]`
accepts `Option[Text]`. The exact "ignores type params" hole, present at field
level (the output boundary does NOT have it).

**B-U4. Named numeric stdlib arms fabricate `Decimal` from anything.**
`add`/`sub`/`div` (`stdlib_calls.rs:174-177`) and `mul` (`:137-172`) accept any
arity/types and return bare `Decimal` — `add("x", true)` typechecks to `Decimal`.
This is a money-safety hole on a parallel surface that bypasses the *sound*
`operator_type` numeric core (which correctly enforces scale equality / `A+B`).

**B-U5. Effect-laundering: a `pure` contract can do I/O via a `def`.** Purity is
decided by `expr_has_io_call` scanning for literal `stdlib.IO.` prefixes inline
(`classifier.rs:2165-2168`); it never resolves `fn_name` to its `def` body. So
`def leak(p) = stdlib.IO.read_text(...)` called from a `pure` node presents as a
plain call → OOF-M1 never fires. Declared-pure, actually-effectful, undetected.

**B-U6. FuelBounded termination has no static bound.** For `decreases fuel` /
`fuel_bounded`, the classifier requires only that a `max_steps` literal *exists*
(`classifier.rs:1573-1593`) and sets `decreases_variant = None`, which makes the
typechecker skip OOF-R3 entirely (`typechecker.rs:2918`). `max_steps: 0` and
`u64::MAX` are equally accepted; `recur()` args need never shrink. Termination for
this whole loop-class reduces to runtime fuel — declared-not-verified. *(The
`decreases` syntactic check itself, `:6595`, accepts only 3 hardcoded forms
`{n-1, n.tail, n.rest}` and proves textual shrink at one site, not well-foundedness
— sound only if the base case is correct, which nothing checks.)*

### C. Integrity / supply-chain (computed, not enforced)

**B-I1. The lockfile is never enforced on the build path.**
`compile`/`run` (`resolve_entry_with_overlays` → `compile_units`, `main.rs:501`)
never reads `igniter.lock`; sha256 verification is a separate, opt-in `igc verify`
(`main.rs:234`). A tampered/drifted dependency compiles and runs cleanly. The
"tamper-evident reproducible build" property does not hold by default (TOCTOU by
design). `project.rs:302-360`.

Update 2026-06-27 (`LAB-IGNITER-COMPILER-LOCK-ON-BUILD-P2`): project compile
now has explicit build-path enforcement:
`igc compile --project-root ROOT --entry MODULE --out OUT --locked` (alias
`--frozen`) reads `igniter.lock`, runs the same `verify_lock`
digest/toolchain-drift check, then runs `check_workspace_integrity` before
project resolve or emit. Default project compile and single-file compile remain
unchanged, so tamper-evident builds are still CI/operator opt-in rather than
default-on.

**B-I2. Symlink escape + no path containment in the dep resolver.** Dependency
paths are normalized *lexically* (`normalize_abs`, `project.rs:1635`, "does NOT
touch the filesystem"); nothing canonicalizes or asserts containment under the
project root. A manifest `path = "/etc"` or `path = "../../.."`, or a symlinked dep
dir, is scanned (`collect_ig_files`, `:1515`) and its bytes folded into the lock
digest (`:894, 770`). Arbitrary file read + digest poisoning at the supply-chain
entry point. (Overlays and archive paths *are* containment-guarded; the dep-path
resolver is not.)

**B-I3. igweb lowering does no token-alphabet validation / escaping** (bounded to
trusted compile-time author input). Contract/method/path-segment tokens are
concatenated raw into generated `.ig` (`igweb.rs:1390, 339-351`); a `"` or
regex-metachar in a route segment can emit `.ig` that means something other than
authored, and an un-escaped literal path segment becomes live regex →
runtime route over-match / authorization-bypass risk (`pattern_to_regex`,
`igweb.rs:339`). "Safe by construction" is only conventionally true here.

## PROBLEMS (condensed by theme)

**Determinism (threatens the content-lock/provenance wave):**
- `canonical_hash` is not canonical — hashes `serde_json::to_string` with no key
  sort; relies on serde_json default ordering; `preserve_order` would make the
  artifact hash non-deterministic (`assembler.rs:1531-1535`).
- Capability/effect manifest aggregation has no dedup/sort (`assembler.rs:126-138`)
  — manifest lists vary with contract iteration order; `requirements_for`
  *does* sort+dedup, so the two surfaces disagree.
- `find_variant_for_arm` resolves same-named arms by `HashMap` order
  (`typechecker.rs:5425-5432`) → nondeterministic typing.

**Numeric / lowering (dual-compiler parity risk):**
- Comparison ops emitted unconditionally as `stdlib.integer.*` regardless of
  operand type (`emitter.rs:1079-1105`); unary `-` hardcoded Integer (`:1063`);
  `numeric.add` defaults `T`→Integer (`:1024-1056`). These are unilateral parity
  decisions vs the Ruby `igc`.
- Decimal `/` has no scale model and no static div-by-zero check
  (`typechecker.rs:5106`); `==` compares outer names only and passes on `Unknown`
  (`:5266`).

**Coverage / robustness:**
- Liveness budgets are observe-only (record-and-continue, never early-return,
  `liveness.rs:114-139`); emitter/parser passes have no budget at all → compiler
  DoS surface.
- Monomorphizer handles only the first type-param / first bound (silent
  truncation) and falls back to a magic `"add"` method name
  (`monomorphizer.rs:18, 29-32`); `substitute_expr` misses `Match`/`Variant`/`Try`
  nodes (un-substituted trait method, `:214-287`). Single-pass (no nested
  generics) — sound-but-incomplete.

**Drift / silent-accept:**
- Two parallel `semantic_expr` lowering passes with hand-maintained duplicate
  allowlists that already differ (`emitter.rs:955` vs `:1424`).
- Hand-rolled TOML manifest parser silently accepts malformed input (inline `#`,
  multiline arrays, quoting) and never errors (`project.rs:1660`) → wrong dep set,
  no diagnostic.
- Lexer silently drops unknown characters (`lexer.rs:514-517`); comparison ops
  parse left-associative so `a < b < c` is accepted (`parser.rs:3315`); array
  literals accept missing commas `[1 2 3]` (`parser.rs:3771`); spans are
  start-only (`end_line/col = 0`) so IDE ranges are zero-width.
- A cluster of stdlib calls silently return `Unknown` with no validation
  (`unwrap`/`try_catch`/`find`/`any`/`all`), `flat_map` swallows lambda-body
  errors, `sum`/`avg` projection falls back to bare `Decimal` on a missing field,
  and app-domain hardcodes (`compute_availability`) are baked into the shared
  stdlib typechecker (`stdlib_calls.rs:2325`).

## INSIGHTS

- **I1. The output boundary is sound; every leak is upstream of it.**
  `structurally_assignable` (`typechecker.rs:3198`) is genuinely recursive with
  correct Unknown asymmetry, and `OOF-TY1` fires structurally. The holes (B-U1..U3,
  `==`, match-widening) are all where the checker falls back to name-only/Unknown.
  The boundary catches many by param-count mismatch — but not when the erased type
  is a bare scalar that name-matches.
- **I2. The good guarantees are genuinely good.** No implicit numeric coercion
  (verified at `operator_type:5099`); Decimal scale equality enforced (`OOF-TC5`);
  `now()` fully forbidden by body-walk in both functions and contracts (`OOF-L2`,
  `typechecker.rs:538`); the resolver core is deterministic (BTreeMap + explicit
  sort) and duplicate/scope/export/cycle detection are fail-closed. The problem is
  *uniformity*, not absence.
- **I3. Termination/effect/integrity guarantees are real but thin & mislocated** —
  FuelBounded is runtime-trusted, purity is a syntactic prefix scan, ServiceLoop
  "bounded-per-step" is enforced nowhere, the lock is computed-not-checked. Same
  "aspirational-at-the-enforcement-layer" pattern as the TBackend audit.
- **I4. "Dual-clean" is testable cheaply via the SIR**, not the VM: both compilers
  emit the same JSON SIR, so `igc(src).sir == igniter_compiler(src).sir` over a
  corpus (after canonicalization) is a strong parity oracle — the hard-coded
  lowering choices (comparison-as-integer, unary-neg-Integer, split→Text) would
  light up first.

## SUPER-COOL (high-leverage opportunities)

- **S1 (keystone). Replace the `serde_json::Value` type-IR with a real
  `enum IgType { Scalar, Collection(Box<IgType>), Record(BTreeMap<..>),
  Variant(..), Option(..), Unknown }`.** This makes the name-only comparison holes
  (B-U3, `==`, match-widening) *unrepresentable* — `structurally_assignable`
  becomes the only path, the compiler forces every arm to handle params, and the
  `Unknown` leakage stops being silent. The single highest-leverage soundness
  change; it fixes R1 at the root.
- **S2. Interprocedural effect-summary pass.** Compute a per-`def` transitive
  effect summary by fixpoint over the call graph **already built for Tarjan SCC**,
  and have purity consult it. Turns purity from a syntactic prefix scan into a real
  effect system — closes B-U5 reusing existing machinery.
- **S3. Differential SIR oracle + one real canonicalizer.** `canonicalize(Value)`
  (recursively sort keys, dedup+sort capability/effect/contract arrays) used by
  both the hash and the per-file writer + a property test "input-order-permutation
  ⇒ identical artifact_hash" — fixes the determinism cluster. Then diff the two
  compilers' canonical SIR over a corpus to operationalize "dual-clean."
- **S4. Make the build tamper-evident by default.** Wire `verify_lock` into
  `compile` (warn/fail on drift, `--frozen` hardens) + a single
  `resolve_within_root(root, candidate)` (canonicalize then assert `starts_with`)
  at the three path entry points — closes B-I1/B-I2 with code already written. A
  content-addressed module store (the digest is already a content address) makes
  location-escape moot.
- **S5. Promote FuelBounded to a static obligation** — require the fuel measure to
  be a declared decreasing numeric expression (reuse the T3 `numeric_measure` path,
  `typechecker.rs:2439`) instead of a present `max_steps` literal. First loop-class
  with statically-witnessed termination.
- **S6 (cheap robustness). One depth-guard RAII at `parse_expr` + make liveness
  early-return.** Reuse the existing `liveness.rs` guard pattern to turn the parser
  SIGABRT (B-C1) and the unguarded-recursion DoS into normal `OOF-*` diagnostics.
  Plus a 2-line `finite-or-diagnostic` float helper kills B-C2. Highest
  safety-per-line in the codebase.

## Keystone recommendation

- **IGNITER-COMPILER-TYPE-IR-ENUM-P2 (keystone).** The `enum IgType` refactor (S1)
  — collapses B-U1..U3 and the `==`/match-widening problems by construction.
- **IGNITER-COMPILER-INPUT-ROBUSTNESS-P2 (parallel).** Parse-depth guard +
  panic-free numeric literals + liveness early-return + emitter arity checks +
  assembler typed-SIR boundary (B-C1..C4).
- **IGNITER-COMPILER-LOCK-ON-BUILD-P2 (parallel).** Lock-on-compile + canonicalize
  + containment guard (B-I1/B-I2) and the single canonicalizer (S3 determinism).

The architecture is sound where it counts (output boundary, numeric core, `now()`,
resolver determinism); the work is **making the soundness uniform and the
enforcement real**, not redesigning.

## Boundary

Lab/frontier evidence only. No code changed by this audit. No canon/authority
claim. Two audit premises (dual host-codegen; igweb=HTML layer) were overturned by
the live code — the HTML-output-safety surface (`igniter-web` /
`igniter-ui-kit/src/igv.rs`) was NOT covered here and needs its own audit.
