# lab-vector-math-field-alignment-p1-v0

**Track:** lab / governance / vector_math source hygiene  
**Card:** LAB-VECTOR-MATH-FIELD-ALIGNMENT-P1  
**Status:** PROVED 49/49  
**Date:** 2026-06-13  
**Predecessor:** APP-RECHECK-WAVE-P8 (VM-P10 ACTIVE)

---

## Goal

Classify and resolve VM-P10: Ruby TC emits 36 `OOF-TY0` diagnostics
("missing required field: r0/r1/r2" + "unexpected field: x/y/z") on the
`vector_math` app. Rust TC: ok/0 throughout.

---

## Questions and Answers

### Q1: Which contracts produce the 36 diagnostics?

**Source**: 6 contracts in `mat3.ig` that construct `Mat3` from inner `Vec3` row
literals: `Mat3Identity`, `Mat3Transpose`, `Mat3Add`, `Mat3Scale`,
`MakeRotation2D`, `MakeScale3D`.

**Attribution bug**: `CompilationReport.enrich` (line 58,
`compilation_report.rb`) uses `parsed.fetch("contracts")[0].fetch("name")`
as the attribution contract for ALL diagnostics. `MultifileResolver` puts
`SimulateFrame` first in the multifile merge order, so all 36 errors appeared
attributed to `SimulateFrame/node:result` rather than the mat3 contracts. With
the mat3-only compilation (types.ig + mat3.ig), the first contract is
`Mat3Identity`, so errors appeared at `Mat3Identity/node:result`.

**Diagnostic count**: Each affected contract contributes 3 inner Vec3 row
literals × 6 errors each = 18 raw errors; `dedupe_errors` collapses to 6
unique (same rule/message/node/line). 6 contracts × 6 = 36 total.

### Q2: Are the offending record literals intended to be Vec3?

**Yes.** The inner row literals `{x:..., y:..., z:...}` in the Mat3-constructing
contracts ARE correctly shaped `Vec3` records. The app source is correct. The
type mismatch is a TC inference artefact, not an app field name error.

### Q3: Is Ruby selecting the wrong candidate type, or is app source misaligned?

**Neither exactly.** The P3 structural candidate matching was never reached for
these literals — they were caught by the hint-path validation (the P2 path in
`infer_record_literal`), which incorrectly applied the outer node's type hint
to inner field value literals.

**Root cause** (`typechecker.rb` lines 3023–3065):

```
infer_record_literal(outer_literal, ..., node_name="result")
  hint_type = @output_type_hints["result"] = Mat3   ← from output result : Mat3
  typed_fields = fields.transform_values do |val_expr|
    infer_expr(val_expr, ..., node_name)             ← node_name="result" propagated in!
  end
  # For field r0, val_expr = {x:1000, y:0, z:0}:
  infer_record_literal({x:1000,y:0,z:0}, ..., "result")
    hint_type = @output_type_hints["result"] = Mat3  ← WRONG: inner literal gets Mat3 hint
    → "missing required field: r0/r1/r2, unexpected field: x/y/z"
```

The hint installed by `output result : Mat3` is keyed on "result". Because
all field-value expressions inside the outer record literal are inferred with
the same `node_name = "result"`, inner `{x,y,z}` literals also look up the
same Mat3 hint and are validated against Mat3 — the wrong type.

This is a **compiler inference gap**: nested record literals share the outer
node's type hint, which is only valid for the named compute, not for its field
values.

### Q4: Does adding compute annotations disambiguate?

**Yes.** By extracting each inner Vec3 row as an annotated compute:

```
compute r0 : Vec3 = { x: ..., y: ..., z: ... }
```

The annotated compute path (lines 411–423 of `typechecker.rb`) installs a
TEMPORARY hint `@output_type_hints["r0"] = Vec3` scoped to this compute's
inference only (deleted via `ensure` after `infer_expr` completes). The inner
record literal is now inferred with `node_name = "r0"`, finds hint `Vec3`, and
validates correctly. The temporary hint is removed before any other compute is
processed.

The outer Mat3 assembly:

```
compute result = { r0: r0, r1: r1, r2: r2 }
```

uses symbol references (not nested literals). The hint path runs with
`@output_type_hints["result"] = Mat3`, validates r0/r1/r2 fields whose values
are `Vec3` symbols → match expected `Vec3` → clean.

### Q5: Does the same source edit preserve Rust ok/0?

**Yes.** The Rust TC supports annotated compute declarations (line 1196 of
`typechecker.rs`). After the edit, `cargo run -- compile ...` → `"status":"ok"`,
0 diagnostics. Verified by proof H-checks.

### Q6: Is there any need for compiler work?

**The compiler has a real gap.** Nested record literal type hint propagation is
incorrect: the outer named node's type hint should not apply to inner field
value literals. This is a separate language-level issue that warrants a
follow-up card (`LAB-NESTED-RECORD-LITERAL-TYPING-P1` as listed in the P3 Out
of Scope section).

For THIS card, the app source fix is sufficient: annotated row computes provide
the TC an unambiguous Vec3 type hint for each inner literal, working within
the current TC's P2 annotated-compute path.

---

## App Source Change

**File**: `igniter-lab/igniter-apps/vector_math/mat3.ig`  
**Contracts changed**: 6 (Mat3Identity, Mat3Transpose, Mat3Add, Mat3Scale,
MakeRotation2D, MakeScale3D)  
**Pattern** (identical in all 6):

```
-- Before
compute result = {
  r0: { x: ..., y: ..., z: ... },
  r1: { x: ..., y: ..., z: ... },
  r2: { x: ..., y: ..., z: ... }
}
output result : Mat3

-- After
compute r0 : Vec3 = { x: ..., y: ..., z: ... }
compute r1 : Vec3 = { x: ..., y: ..., z: ... }
compute r2 : Vec3 = { x: ..., y: ..., z: ... }
compute result = { r0: r0, r1: r1, r2: r2 }
output result : Mat3
```

**Unchanged**: `Mat3MulVec3` (outputs Vec3 via scalar products, not nested
Mat3 rows), `Mat3Determinant` (outputs Integer).

---

## Diagnostic Attribution Side Note

The `CompilationReport.enrich` attribution bug (all errors attributed to
`contracts[0]` name from the merged multifile program) means that the Wave P3
registry note "errors in vec2.ig/vec3.ig" was inaccurate. The actual error
source was always mat3.ig contracts. The attribution changed between waves
because `MultifileResolver` contract ordering changed (SimulateFrame rose to
position 0). This attribution gap is out of scope for this card but is
documented here for awareness.

---

## Proof Matrix (49 checks / 8 sections)

| Section | Checks | Focus |
|---------|--------|-------|
| A — Source guard | 6 | mat3.ig annotated row computes in place |
| B — Ruby TC outcome | 8 | 36 → 0 diagnostics; mat3-only also clean |
| C — Rust TC baseline | 5 | Still ok/0 after source edit |
| D — Root cause evidence | 5 | Nested hint propagation in typechecker.rb |
| E — Attribution mechanism | 5 | CompilationReport.enrich + flat_map |
| F — Fix mechanism | 5 | Annotated computes give Vec3 hint |
| G — Regression | 7 | vec2/vec3/geometry/example still clean |
| H — Contract isolation | 8 | Each affected mat3 contract clean individually |

**Result: 49/49 PASS**

---

## Open Routes

| Card | Scope |
|------|-------|
| `LAB-NESTED-RECORD-LITERAL-TYPING-P1` | Compiler fix: do not propagate outer record node_name into field value literal inference |
| `APP-RECHECK-WAVE-P9` | Re-freeze vector_math baseline now that VM-P10 is resolved |
