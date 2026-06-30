# LAB-IGNITER-COMPILER-TYPE-IR-ENUM-P5

Status: CLOSED (2026-06-28)

## Closure Report

Implemented Alternative A from the P4 readiness packet: a narrow internal
`IgType` enum for the typechecker helper boundary, JSON only at the edges, plus
one converted comparison path proving the model fails closed.

- Added `lang/igniter-compiler/src/typechecker/type_ir.rs`
  (`enum IgType { Unknown, Named, Generic }` + `from_json_lossy`/`to_json`/
  `name`/`params`/`decimal_scale`/`display`/`is_unknown_bearing`/
  `structurally_assignable`). Invalid states (non-string `name`, non-array
  `params`, nameless object) are unrepresentable / fail closed to `Unknown`.
- Reimplemented the 7 helper methods (`type_ir`, `get_param`, `type_name`,
  `decimal_scale`, `structurally_assignable`, `unknown_or_unknown_bearing`,
  `type_display`) to delegate to `IgType`. ~270 call sites untouched. Public
  `{name, params}` SIR JSON shape preserved.
- Converted the variant-field construction comparison (was outer-name-only) to a
  structural param check via the typed model, additively — existing outer-name
  `OOF-KIND2` diagnostic left byte-identical.

Proof (before/after, genuine): the `Collection[Integer]` → `Collection[Text]`
variant field compiled `"status": "ok"` at HEAD; now raises
`OOF-KIND2 "Bag::Hold field 'items': expected Collection[Text], got
Collection[Integer]"`.

Acceptance:
- [x] Live type surfaces characterized before editing (verify-first).
- [x] Real typed IR introduced for the variant-field / `structurally_assignable`
      soundness path.
- [x] A test that previously passed by name-only now fails with a clear
      diagnostic (`variant_field_generic_param_tests` + before/after capture).
- [x] Package/workspace, IgWeb lowering (byte-identical), stdlib tests green.
- [x] Proof packet names what moved to typed IR and what stays old-shape.
- [x] `git diff --check` passes.
- [x] Card closed with this report.

Tests: full suite 308 passed / 0 failed (296 baseline + 10 unit + 2
integration). Packet:
`lab-docs/lang/lab-igniter-compiler-type-ir-enum-p5-v0.md`.

Follow-up: `LAB-IGNITER-COMPILER-USER-FN-SIGNATURE-CHECK-P6` (validate
user-`def` call arity/params at `Expr::Call` — readiness risk #1); optional
second slice converts the record-literal non-inline field comparison the same
way (readiness risk #2 remaining half).

---

Status: CLOSED — original card below.
Route: standard / main-audit / compiler / type soundness
Skill: idd-agent-protocol
Depends-On: `lab-docs/lang/lab-igniter-compiler-type-ir-enum-readiness-p4-v0.md`

## Goal

Implement the smallest compiler slice that replaces the most dangerous
stringly/type-name IR surfaces with a real internal `IgType` model, without
changing public `.ig` syntax.

This is an audit-follow-up from `lab-audit-control-board-v1.md` row A19.
The goal is not a broad refactor. It is to make one meaningful class of
name-only type mistakes unrepresentable and prove the migration path.

## Current Authority

Live source wins. Read first:

- `lab-docs/lang/lab-audit-control-board-v1.md`
- `lab-docs/lang/lab-igniter-compiler-type-ir-enum-readiness-p4-v0.md`
- `lang/igniter-compiler/IMPLEMENTED_SURFACE.md` if present
- `lang/igniter-compiler/src/typechecker.rs`
- `lang/igniter-compiler/src/typechecker/stdlib_calls.rs`
- `lang/igniter-compiler/src/project.rs`
- relevant compiler tests under `lang/igniter-compiler/tests/`

Known live facts to re-verify:

- the readiness packet names the current stringly surfaces and the safe first
  migration seam;
- recent form-vocabulary work lives in canon `igniter-lang`, not this Rust lab
  compiler lane;
- route/web/product tests may depend on exact diagnostics, so diagnostics must
  be deliberately updated, not accidentally churned.

## Scope

Allowed:

- Introduce an internal `IgType` enum or equivalent strongly typed model for
  the narrow surface selected by the readiness packet.
- Convert only the first high-leverage comparison/assignment/call path needed
  to prove the model.
- Add tests proving the previous name-only mistake now fails closed.
- Keep serialization/output shape stable unless the implementation slice
  explicitly requires a local test update.
- Update implemented-surface/proof docs if the current truth changes.

Closed:

- No new public language syntax.
- No `.igweb` routing changes.
- No VM/runtime execution changes unless a type-shape fixture needs a compile
  expectation update.
- No broad rewrite of all typechecker internals in one pass.
- No canon `igniter-lang` edits from this lab card.

## Questions To Answer

1. What is the smallest first surface: record fields, collection element
   compatibility, user `def` call arguments, equality, or match widening?
2. Can the new type model be introduced behind conversion helpers first?
3. Which old string names remain as display/diagnostic-only data?
4. What exact diagnostic should prove the old unsoundness is gone?
5. What remains intentionally stringly after this slice, and why?

## Acceptance

- [ ] Live compiler type surfaces are characterized before editing.
- [ ] A real typed internal representation is introduced for one selected
      soundness-critical path.
- [ ] At least one test that would previously pass by name-only/stringly
      comparison now fails with a clear diagnostic.
- [ ] Existing package/workspace, IgWeb lowering, and stdlib compiler tests
      relevant to the touched path remain green.
- [ ] The proof packet names what moved to typed IR and what remains old-shape.
- [ ] `git diff --check` passes.
- [ ] Card is closed with a concise report.

## Suggested Verification

Adapt after verify-first, but start with:

```bash
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab
cargo test --manifest-path lang/igniter-compiler/Cargo.toml
git diff --check
```

If a narrower test family exists after reading the source, run it first and
report both narrow and broader results.

## Required Packet

Create:

```text
lab-docs/lang/lab-igniter-compiler-type-ir-enum-p5-v0.md
```

Packet must include:

- selected first surface and why it was chosen;
- before/after diagnostic evidence;
- untouched surfaces;
- follow-up card name if a second migration slice is needed.

