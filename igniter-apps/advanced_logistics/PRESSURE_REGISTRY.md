# Advanced Logistics Pressure Registry

**Date:** 2026-06-13 (APP-RECHECK-WAVE-P8 — DUAL-CLEAN)
**App:** `igniter-lab/igniter-apps/advanced_logistics`
**Purpose:** compact registry of language/compiler pressures surfaced by the advanced logistics fixture.

This registry is evidence routing, not implementation authority.

---

## Pressure Entries

| ID | Pressure | Current Evidence | Status | Suggested Route |
|---|---|---|---|---|
| AL-P01 | `stdlib.collection` import surface | Wave P1/P2: both Rust and Ruby emitted `OOF-IMP2 unknown import path 'stdlib.collection'`. Wave P3: RESOLVED — both toolchains CLEAN (0 diagnostics). LANG-STDLIB-COLLECTION-APPEND-PROP-P3/P4 + LANG-STDLIB-IS-EMPTY-PROP-P3/P4 landed; stdlib.collection recognized by inventory | RESOLVED — `LANG-STDLIB-COLLECTION-APPEND-PROP-P3/P4` CLOSED |
| AL-P02 | Bare collection helper probe path | Temporary no-import probe compiles in Rust with `map` and `filter`. Wave P3: moot — real app source compiles CLEAN without probing | Positive / superseded by AL-P01 resolution |
| AL-P03 | Stringly composition | `api.ig` uses `call_contract("FindFeasibleOrders", t, order_queue)`; Wave P3: Rust CLEAN (call_contract Tier 1 literal same-module callee lookup works in Rust via LAB-RACK-P11); Ruby CLEAN (LAB-RUBY-CALL-CONTRACT-PARITY-P3 now handles Tier 1 literal callee); both toolchains resolve this call cleanly | Design pressure remains for long-term; no active diagnostic |
| AL-P04 | Ruby comparison operator parity | Wave P1/P2: Ruby probe reported `Unsupported operator: <`. Wave P3: RESOLVED — LANG-STDLIB-NUMERIC-COMPARISON-P3 CLOSED; `<` works in Ruby TC; both toolchains CLEAN | RESOLVED — `LANG-STDLIB-NUMERIC-COMPARISON-P3` CLOSED |
| AL-P05 | Inline record literals in HOF contexts | App avoids `{ transport: t, orders: order_queue }` inside `map` lambda after parser ambiguity reports | Historical / needs minimal proof — `LAB-PARSER-RECORD-IN-HOF-P1` |
| AL-P06 | Method-like qualified calls | `stdlib.collection.map(...)` is not a valid call target under current grammar | Design pressure — stdlib import/form vocabulary route; no direct syntax fix yet |
| AL-P07 | Math `sqrt` / spatial helper | `spatial.ig` uses squared distance to avoid `sqrt` | Deferred — `LAB-STDLIB-MATH-P1` after numeric readiness |

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

Probe results (Wave P1/P2 — pre-resolution):

- Rust: `status: ok`, zero diagnostics.
- Ruby: `status: oof`, diagnostics: `Unknown function: call_contract`, `Unsupported operator: <`.

---

## Wave P2 Recheck Summary (2026-06-12)

Rust: oof (OOF-IMP2 import surface). Ruby: oof (OOF-IMP2 + call_contract + comparison operator). AL-P01 (import surface) and AL-P04 (comparison) still blocking both toolchains.

## Wave P6 Recheck Summary (2026-06-13)

Rust: ok / 0 diagnostics — STILL CLEAN. Ruby: ok / 0 diagnostics — STILL CLEAN. LANG-RUBY-RECORD-LITERAL-INFERENCE-P3 had zero effect: no unannotated intermediate record literal computes in this app. advanced_logistics retains dual-toolchain CLEAN status. No new pressures. No regressions.

## Wave P5 Recheck Summary (2026-06-13)

Rust: ok / 0 diagnostics — STILL CLEAN. Ruby: ok / 0 diagnostics — STILL CLEAN. LANG-RUBY-RECORD-LITERAL-INFERENCE-P2 had zero effect: no annotated compute record literals in this app. advanced_logistics retains dual-toolchain CLEAN status. No new pressures.

## Wave P4 Recheck Summary (2026-06-13)

**BOTH TOOLCHAINS STILL CLEAN — 0 diagnostics in Rust and Ruby.** LANG-TYPED-COMPUTE-BINDING-P2 had no visible effect (no annotated computes in this app). No new pressures. advanced_logistics retains dual-toolchain CLEAN status.

## Wave P3 Recheck Summary (2026-06-13)

**BOTH TOOLCHAINS CLEAN — 0 diagnostics in Rust and Ruby.**

Resolutions since Wave P2: AL-P01 RESOLVED — stdlib.collection import surface now recognized (LANG-STDLIB-COLLECTION-APPEND-PROP-P3/P4 + LANG-STDLIB-IS-EMPTY-PROP-P3/P4 CLOSED); no OOF-IMP2. AL-P04 RESOLVED — LANG-STDLIB-NUMERIC-COMPARISON-P3 CLOSED; `<` operator works in Ruby TC. AL-P03 stringly composition also CLEAN — LAB-RUBY-CALL-CONTRACT-PARITY-P3 CLOSED; `call_contract("FindFeasibleOrders", t, order_queue)` Tier 1 literal callee now dispatches in Ruby. Remaining pressures: AL-P05 (HOF record literals — historical), AL-P06 (method-like calls — design), AL-P07 (sqrt — deferred). No active blockers.

---

## Routing Notes

- AL-P01 and AL-P04 are RESOLVED — no active import or operator blockers.
- AL-P03 stringly composition is now clean in both toolchains; long-term typed-ref/forms route remains the recommended direction.
- AL-P05 needs a minimal current parser fixture before it becomes an active blocker.
- AL-P06 should be considered alongside stdlib import surface and form vocabulary; avoid a one-off method-call syntax patch.
- AL-P07 is useful future math pressure, but not urgent because squared distance keeps the app deterministic and typeable.
- **advanced_logistics is the first app to achieve dual-toolchain CLEAN status (Wave P3).**

## Wave P7 Recheck Summary (2026-06-13)

Rust: ok / 0 diagnostics — unchanged. Ruby: ok / 0 diagnostics — unchanged. DUAL-TOOLCHAIN CLEAN. No pressure ID changes this wave. No new pressures. (LANG-RUBY-RECORD-LITERAL-INFERENCE-P3 had no effect — all computes in this app were already annotated or resolved before Wave P6.)

## Wave P8 Recheck Summary (2026-06-13)

Rust: ok / 0 diagnostics — unchanged. Ruby: ok / 0 diagnostics — unchanged. DUAL-TOOLCHAIN CLEAN. LANG-STRING-TEXT-ALIAS-P2, LANG-RUBY-RECORD-LITERAL-INFERENCE-P5, LANG-STDLIB-STRING-SUBSTRING-P2, and LAB-BLOOM-FILTER-RANGE-MIGRATION-P1 had no effect on this app. No new pressures. No regressions.

## Wave P9 Recheck Summary (2026-06-13)

Rust: ok / 0 diagnostics — unchanged. Ruby: ok / 0 diagnostics — unchanged. DUAL-TOOLCHAIN CLEAN. LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P4, LAB-VE-NEW-OBJ-INFERENCE-P1, LAB-VECTOR-MATH-FIELD-ALIGNMENT-P1, LAB-HOF-LAMBDA-ERROR-PROPAGATION-P2, and LAB-PARSER-RECORD-IN-HOF-P1 had no effect on this app. No new pressures. No regressions.