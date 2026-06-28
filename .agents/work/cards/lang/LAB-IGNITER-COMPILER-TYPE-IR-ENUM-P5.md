# LAB-IGNITER-COMPILER-TYPE-IR-ENUM-P5

Status: OPEN
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

