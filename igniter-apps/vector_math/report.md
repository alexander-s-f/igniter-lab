# Vector Math Pressure Report

Updated: 2026-06-12

This app is currently the strongest positive app fixture in the lab: a six-file mathematical library that compiles all the way to a Rust lab `igapp` artifact. Unlike the blocked app-pressure fixtures, this one should be treated as a baseline success case plus a Ruby parity pressure map.

## Live Check

Source files checked:

- `types.ig`
- `vec2.ig`
- `vec3.ig`
- `mat3.ig`
- `geometry.ig`
- `example.ig`

Rust lab compiler result:

| Field | Value |
| --- | --- |
| status | `ok` |
| stages | `parse -> classify -> typecheck -> emit -> assemble` |
| source units | 6 |
| contracts | 37 |
| `semantic_ir_program.json` | 217,689 bytes |
| `sourcemap.json` | 110,755 bytes |
| `manifest.json` | 14,069 bytes |
| artifact hash | `sha256:289a586aeb172ccc35a55e23f5f400194d14cf8cbb246120881c205bb3ea3d9a` |

Ruby canon compiler result:

| Field | Value |
| --- | --- |
| status | `oof` |
| diagnostics | 82 |
| dominant blocker | `Unknown function: call_contract` (26 occurrences) |
| secondary blocker | `Unsupported operator: <` (8 occurrences) |

Ruby diagnostics are dominated by missing inter-contract invocation support. Record-shape and type-mismatch diagnostics are mostly downstream of `Unknown` values created by failed `call_contract` inference.

## Findings

### VM-P01 - Full Rust multi-file app compilation is proven

The Rust lab compiler successfully compiles all six files and produces a complete `igapp` artifact. This is the first app in the current pressure set that is not merely a blocker map but a working multi-module compilation baseline.

Route: preserve as a regression fixture. Any multi-file/import/typechecker/emitter/assembler change should be checked against this app.

### VM-P02 - Pure contract architecture fits vector math well

Vec2, Vec3, Mat3, AABB, and physics examples map cleanly to pure contracts. The app has no ambient authority, no external IO, no runtime state, and no collection import dependency. This is an existence proof for nontrivial pure computational libraries in Igniter.

Route: use as positive evidence for stdlib/core math design, but do not promote app-local vector operations into stdlib prematurely.

### VM-P03 - Integer milli-units are viable but explicit workaround

The app uses Integer milli-units (`1000 = 1.0`) to avoid Float/Decimal operator gaps. This keeps determinism and full compilation, but it pushes scale discipline into naming/comments rather than type-level representation.

Route: `LAB-STDLIB-FIXED-POINT-P1` or numeric/fixed-scale research after current collection/import work.

### VM-P04 - Unary negative literal pressure remains real

The source uses `0 - N` forms (`0 - 200`, `0 - 9810`) instead of negative literals. This is the safe workaround for parser behavior around unary minus in multi-file contexts.

Route: `LANG-PARSER-UNARY-MINUS-P1` or include in numeric/operator stabilization.

### VM-P05 - Comparison operator ergonomics remain limited

The app avoids `>=` and `<=` by rewriting range checks through `<`, `>`, and nested `if` expressions. This compiles in Rust but creates verbose boolean code.

Route: deterministic numeric comparison parity slice for `<=` / `>=`, keeping Float/Decimal semantics separate.

### VM-P06 - Ruby parity is blocked primarily by `call_contract`

Ruby reports 26 `Unknown function: call_contract` diagnostics. This prevents the Ruby pipeline from observing the same composition structure Rust accepts.

Route: typed contract refs / invocation forms / Ruby `call_contract` parity decision. This is broader than vector math and appears in multiple app-pressure fixtures.

### VM-P07 - Ruby operator parity blocks geometry checks

Ruby reports `Unsupported operator: <` in geometry utilities. Rust accepts the integer comparisons. This makes simple AABB bounds checks unavailable in Ruby despite being deterministic and pure.

Route: `LANG-STDLIB-TEXT-EQUALITY-P1` is not enough here; numeric comparison parity needs its own slice.

### VM-P08 - Ruby record-shape diagnostics are downstream noise here

Ruby emits record-shape errors such as `record literal missing required field: r0` and `unexpected field: x`. Given the upstream `call_contract` failures and Unknown propagation, these should be treated as secondary until invocation parity is resolved.

Route: re-check after Ruby invocation parity before opening a dedicated nested-record bug.

## Current Pressure Ranking

1. Preserve Rust full-compile baseline - this app should become a regression fixture.
2. Ruby `call_contract` / typed invocation parity - dominant blocker.
3. Numeric comparison parity for Ruby `<` and broader `<=` / `>=` ergonomics.
4. Fixed-point / scale-aware numeric model - integer milli-units work but are informal.
5. Unary minus parser support - remove `0 - N` workaround.
6. Re-check Ruby record-shape diagnostics after invocation parity.

## Non-goals

- Do not promote Vec2/Vec3/Mat3 into stdlib just because the app compiles.
- Do not treat milli-units as the final numeric model without a type-level scale story.
- Do not infer runtime/vector engine authority from this pure contract library.
- Do not open Float/Decimal semantics as part of preserving this baseline.

## Recommended Next Cards

- `LAB-VECTOR-MATH-BASELINE-P1` - freeze this app as a Rust full-pipeline regression fixture.
- `LAB-RUBY-CALL-CONTRACT-PARITY-P1` or typed invocation follow-up - unblock Ruby composition parity.
- `LANG-NUMERIC-COMPARISON-PARITY-P1` - deterministic integer comparison parity and `<=` / `>=` ergonomics.
- `LANG-PARSER-UNARY-MINUS-P1` - parse negative integer literals consistently in multi-file contexts.
