# Advanced Logistics Pressure Registry

**Date:** 2026-06-12
**App:** `igniter-lab/igniter-apps/advanced_logistics`
**Purpose:** compact registry of language/compiler pressures surfaced by the advanced logistics fixture.

This registry is evidence routing, not implementation authority.

---

## Pressure Entries

| ID | Pressure | Current Evidence | Status | Suggested Route |
|---|---|---|---|---|
| AL-P01 | `stdlib.collection` import surface | Rust and Ruby both emit `OOF-IMP2 unknown import path 'stdlib.collection'`. | active | `LANG-STDLIB-IMPORT-SURFACE-P1` |
| AL-P02 | Bare collection helper probe path | Temporary no-import probe compiles in Rust with `map` and `filter`. | positive / import barrier confirmed | Keep as regression evidence after import-surface decision. |
| AL-P03 | Stringly composition | `api.ig` uses `call_contract("FindFeasibleOrders", t, order_queue)`; Ruby probe reports unknown function. | design pressure | typed-ref/forms migration route |
| AL-P04 | Ruby comparison operator parity | Ruby probe reports `Unsupported operator: <`; Rust probe accepts capacity predicate. | active | `LAB-RUBY-OPERATOR-PARITY-P1` |
| AL-P05 | Inline record literals in HOF contexts | App avoids `{ transport: t, orders: order_queue }` inside `map` lambda after parser ambiguity reports. | historical / needs minimal proof | `LAB-PARSER-RECORD-IN-HOF-P1` |
| AL-P06 | Method-like qualified calls | `stdlib.collection.map(...)` is not a valid call target under current grammar. | design pressure | stdlib import/form vocabulary route, no direct syntax fix yet |
| AL-P07 | Math `sqrt` / spatial helper | `spatial.ig` uses squared distance to avoid `sqrt`. | deferred | `LAB-STDLIB-MATH-P1` after numeric readiness |

---

## Evidence Commands

Rust full multi-file compile:

```bash
cd ../../igniter-compiler
cargo run -- compile ../igniter-apps/advanced_logistics/types.ig ../igniter-apps/advanced_logistics/spatial.ig ../igniter-apps/advanced_logistics/router.ig ../igniter-apps/advanced_logistics/api.ig --out /tmp/advanced-logistics-rust.igapp
```

Ruby full multi-file compile:

```bash
cd ../../../igniter-lang
ruby -Ilib -e 'require "igniter_lang/compiler_orchestrator"; c=IgniterLang::CompilerOrchestrator.new; p c.compile_sources(source_paths: ["../igniter-lab/igniter-apps/advanced_logistics/types.ig", "../igniter-lab/igniter-apps/advanced_logistics/spatial.ig", "../igniter-lab/igniter-apps/advanced_logistics/router.ig", "../igniter-lab/igniter-apps/advanced_logistics/api.ig"], out_path: "/tmp/advanced-logistics-ruby.igapp")'
```

Probe note:

A temporary `/tmp` copy with only `import stdlib.collection.{ map }` and
`import stdlib.collection.{ filter }` removed was used to expose downstream blockers.
Do not treat that probe as an app source change.

Probe results:

- Rust: `status: ok`, zero diagnostics.
- Ruby: `status: oof`, diagnostics: `Unknown function: call_contract`, `Unsupported operator: <`.

---

## Routing Notes

- AL-P01 is the primary blocker in the real app source.
- AL-P02 confirms collection helper implementation is not the first Rust blocker here.
- AL-P03 should route through typed-ref/forms composition, not canonize string dispatch.
- AL-P04 is Integer comparison parity; keep separate from Float/Decimal numeric readiness unless a broader operator card is opened.
- AL-P05 needs a minimal current parser fixture before it becomes an active blocker.
- AL-P06 should be considered alongside stdlib import surface and form vocabulary; avoid a one-off method-call syntax patch.
- AL-P07 is useful future math pressure, but not urgent because squared distance keeps the app deterministic and typeable.
