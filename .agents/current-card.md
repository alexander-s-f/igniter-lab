# IDD Card: Form System Implementation

Lane: standard
Status: complete
Started: 2026-06-04
Completed: 2026-06-04
Owner: [Architect / Claude]

---

## Contract

Implement the Form System (PROP-Forms-Enhanced-v0) in igniter-compiler (Rust).
Deliver: working form parsing, form resolution pass, `form_table.json` artifact,
and a pressure package return for canonical consideration.

## Authority Surface

| Surface | Status |
|---------|--------|
| `igniter-lab/igniter-compiler/src/` | Open — all changes authorized |
| `igniter-lab/lab-docs/` | Open — lab documentation |
| Main igniter project | Closed — pressure package only, no code changes |
| Agent-C archive | Closed — reference only |

## Closed Surfaces

- Do not modify the main igniter gem (`lib/igniter/`)
- Do not commit to the main igniter repo
- Pressure package return is evidence, not authority

## Spec Reference

`lab-docs/PROP-Forms-Enhanced-v0.md` — §E10 defines the implementation order

---

## Steps

- [x] **P1** Lexer + Parser — form declarations parseable
- [x] **P2** form_registry.rs — FormEntry, trigger index, structural rules F-01/F-02/F-05
- [x] **P3** form_resolver.rs — AST walker, trigger lookup, resolution trace
- [x] **P4** Emitter + Assembler — form_table.json + form_resolution_trace.json output
- [x] **P5** Integration test — forms_test.ig compiles, artifacts verified
- [x] **P6** Pressure package — FORMS-PRESSURE-RETURN-v0.md

## Evidence Paths

- `igniter-compiler/out/*.igapp/form_table.json` — resolution output
- `igniter-compiler/out/*.igapp/diagnostics.json` — trace events
- `lab-docs/tracks/` — step evidence

---

## Next Route

On completion: write `lab-docs/FORMS-PRESSURE-RETURN-v0.md`
Target: mainline igniter review (Architect Supervisor / Codex)
