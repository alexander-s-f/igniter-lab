# lab-lang-record-spread-p2-v0 — pure record spread/update

**Card:** `LAB-LANG-RECORD-SPREAD-P2` · **Delegation:** `OPUS-LANG-RECORD-SPREAD-P2`
**Status:** CLOSED (lab implementation-proof) — record spread/update `{ ...base, field: value }` works as
**pure sugar**: the typechecker expands it to an explicit field-by-field `record_literal` once the target
record type is known, then the existing emitter lowers it. **No optional fields, no defaults, no runtime
reflection, no new SIR node kind, no ViewArtifact/renderer/relational change, no canon claim.**
**Authority:** Lab tooling. Implements the spread half of `LAB-LANG-RECORD-ERGONOMICS-READINESS-P1`
(optional fields stay on the canon PROP track — not smuggled through spread).

## Exact syntax accepted

```ig
compute bumped : Counter = { ...counter, count: counter.count + 1 }   -- same-type update
compute enriched : Ctx2  = { ...ctx, todo_id: todo_id }               -- accumulation (source ⊂ target)
compute r : Counter      = { ...counter, count: 99 }                  -- partial update (rest copied)
```

- `...expr` may appear **once**, as the **first** entry of a record literal, followed by zero or more explicit
  `field: value` entries.
- It is recognized only at the **top level of a typed compute/output** (where the declared record type drives
  expansion). A nested spread is rejected (see narrowing).

## Narrowing (live-code limits, honored + documented)

v0 is **top-level, typed** spread. Two deliberate limits:

1. **Top-level only.** The emitter holds no type definitions and the `annotated_expr` desugar carrier is read
   only at the compute-decl level, so the target type is available only there. A spread nested inside another
   expression (`[ { ...c, … } ]`, `f({ ...c, … })`) has no target type at that point → rejected with
   `OOF-TY0: record spread is only supported at the top level of a typed compute/output (v0)` rather than
   letting an unexpanded `record_spread` reach the emitter. Widening needs a general expected-type-threading
   pass through `infer_expr` (not in this slice).
2. **Copied = target-declared ∧ source-has.** Per the card: copied fields are exactly those the **target type
   declares** and the **source type also has**. Copied-field types are verified directly against the target
   shape (source-vs-target type equality), so accumulation is type-safe. Explicit fields override copied ones.

## Desugaring model

`{ ...src, f: v }` at `compute name : T` expands (typechecker, decl level) to an explicit
`record_literal` whose fields are:

- every **explicit** `f: v` (these override), plus
- for every field `g` that **T declares** and the **source type S has** and is **not explicit**:
  a synthesized `field_access(src, g)`.

Fields in T that are neither explicit nor in S are **left out** → the existing
`check_record_literal_shape` reports them as missing required fields. Extra explicit fields (not in T) are
likewise reported by the shape checker. The expanded `record_literal` is stashed as the decl's
`annotated_expr`; the emitter lowers it via the established `annotated_expr → record_literal` path (one new
line in `lower_annotated_expr`). **No new SIR node kind**; `record_spread` never reaches the SIR.

## Parser / typechecker / emitter changes

| File | Change |
|---|---|
| `lexer.rs` | new `Spread` token for `...` (checked before `DotDot`/`Dot`) |
| `parser.rs` | new `Expr::RecordSpread { spread, fields }`; `parse_record_or_block` parses a leading `...expr`; **duplicate explicit field names are now rejected** (`duplicate field` error) |
| `typechecker.rs` | `infer_expr` types `RecordSpread` source+fields (→ Unknown, like `RecordLiteral`); **decl-level expansion** (target-driven) → `check_record_literal_shape` → `annotated_expr`; nested-spread guard; `expr_kind`/escape-refs/`expr_has_call`/`expr_has_now`/`expr_collect_calls`/`rewrite_concat_calls` mirror `RecordSpread` |
| `classifier.rs` | `expr_kind`, `collect_expr_refs` (spread source is a real dependency edge), `expr_has_write`, `expr_has_io_call`, `check_expr_io` mirror `RecordSpread` |
| `emitter.rs` | `lower_annotated_expr`: `record_literal => semantic_expr(val)` (lowers the expanded literal via the normal path) |
| `form_resolver.rs` | `RecordSpread` added to the ignore group (exhaustiveness) |

## Diagnostics (live output)

```text
{ ...counter, count: 1, count: 2 }   → duplicate field `count` in record literal
{ ...n, count: 1 }  (n : Integer)    → OOF-TY0 record spread source must be a known record type, got `Integer`
{ ...counter, nope: 1 }              → OOF-TY0 unexpected field `nope` (shape checker)
{ ...ctx, user: ctx.user } : Ctx2    → OOF-TY0 `todo_id` ... missing from literal at node 'r'
[ { ...counter, count: 1 } ]         → OOF-TY0 record spread is only supported at the top level (v0)
```

## Serialization parity (proof)

Compiling `{ ...counter, count: counter.count + 1 }` and the hand-written
`{ count: counter.count + 1, label: counter.label }` produces a **byte-identical `record_literal` node** in
`semantic_ir_program.json`, and the spread output contains **no `record_spread`** in the SIR (only the source
span id in `sourcemap.json`). So the spread is *exactly* the explicit literal — same VM serialization, same
evaluation. (Test `spread_serializes_identically_to_explicit_literal` asserts both.)

## Fixture status

A context-accumulation fixture was **mirrored in tests** (`Ctx`/`Ctx2` accumulation, `Counter` same-type
update) rather than rewriting a live `CtxWith*` helper — the lead/router `CtxWith*` contracts remain untouched
this slice; the suggested-next is to simplify one of them with spread now that the surface is proven.

## Tests & commands — exact counts

```text
$ cd lang/igniter-compiler && cargo test --test record_spread_tests → 9 passed
    (same-type update; accumulation; override; duplicate→reject; non-record source→reject;
     extra field→reject; missing field→reject; nested→reject; serialization parity)
$ cd lang/igniter-compiler && cargo test                            → 152 passed; 0 failed
$ cd lang/igniter-compiler && cargo test --test string_escapes_tests    → 10 passed
$ cd lang/igniter-compiler && cargo test --test loop_conformance_tests  → 14 passed
$ cd lang/igniter-compiler && cargo test --test igweb_lowering_tests    → 11 passed
$ cd lang/igniter-compiler && cargo test --test match_arm_bindings_tests → 6 passed
$ cd server/igniter-web    && cargo test                            → 17 binaries green
$ git diff --check                                                  → clean
```

## Acceptance — mapping

- [x] Same-type update: `{ ...counter, count: counter.count + 1 }`.
- [x] Accumulation: source fields + one explicit target field → larger target record (source ⊂ target).
- [x] Explicit field override wins over spread-copied field.
- [x] Explicit duplicate fields rejected (`duplicate field`).
- [x] Unknown/non-record spread source rejected with a clear diagnostic.
- [x] Missing required target field after spread+explicit rejected by existing shape logic.
- [x] Extra explicit field rejected by existing shape logic.
- [x] Emitted value serializes exactly like an explicit record literal (byte-identical SIR record node).
- [x] Existing record literal tests remain green (full suite 152/0).
- [x] No optional fields / default values introduced.
- [x] No ViewArtifact schema changes.
- [x] `lang/igniter-compiler cargo test` green (152/0).
- [x] `git diff --check` clean.

## Out of scope / deferred (honored)

No optional fields, no defaults, no partial-omission semantics; no map/dynamic spread; no variant spread; no
nested/untyped spread (rejected, widening deferred); no renderer/relational/canon change. Optional fields stay
on the `LANG-OPTIONAL-FIELD-PARTIAL-RECORD` canon PROP track.

## Next

Use spread in one live context-accumulation fixture (a `CtxWith*` helper / Todo/IgWeb context) to retire
boilerplate. If nested spread becomes load-bearing, card a general expected-type-threading pass for
`infer_expr` (the only thing blocking widening).

---

*Lab implementation-proof. Compiled 2026-06-20; igniter-compiler 152/0 (incl. 9 new), string_escapes 10,
loop_conformance 14, igweb 11, match_arm 6, igniter-web 17 green; `git diff --check` clean. Record spread is
pure sugar — target-driven expansion to a byte-identical explicit `record_literal`, no new SIR node kind, no
optional-field semantics, no authority.*
