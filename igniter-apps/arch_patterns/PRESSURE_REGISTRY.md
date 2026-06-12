# Architectural Patterns Pressure Registry

Updated: 2026-06-12 (APP-RECHECK-WAVE-P2)

This registry tracks app pressure from `igniter-apps/arch_patterns`. It is evidence, not canon authority.

| ID | Status | Pressure | Evidence | Suggested route |
| --- | --- | --- | --- | --- |
| AP-P01 | RESOLVED | `stdlib.collection` import surface | Wave recheck: no OOF-IMP2 in Ruby or Rust; app reaches emitter (Ruby) / TC (Rust); `stdlib.collection` recognized in inventory | `LANG-STDLIB-COLLECTION-APPEND-PROP-P3` inventory |
| AP-P02 | ACTIVE | `append` via call_contract | Rust wave recheck: 7 `call_contract: unknown callee 'append'` diags (pipeline.ig ×3 + example.ig ×4); apps use `call_contract("append", ...)` form; stdlib dispatch doesn't cover stringly form | call_contract parity follow-up |
| AP-P03 | ACTIVE | Event replay wants fold | `ReplayEvents3` / `ReplayEvents5` are manual unrolls of `ApplyEvent` | fold parity + typed invocation/form follow-up |
| AP-P04 | READY | Collection emptiness / find-one | `is_empty`/`non_empty` now available; `CheckTransition` can now be updated to enforce non-empty candidate check; state_machine.ig comment `-- candidates is non-empty, but we lack is_empty()` is stale | App can use `filter + is_empty`; `LAB-STDLIB-FIND-ONE-P1` for scalar |
| AP-P05 | POSITIVE | Static middleware pipeline | `RunPipeline` chains pure `PipelineContext -> PipelineContext` contracts | preserve as static composition evidence |
| AP-P06 | WATCH | Dynamic middleware registration | Requires function-as-value or conservative form-assisted invocation | typed refs / form vocabulary track |
| AP-P07 | RESOLVED | Text equality | UTF-8-stripped Ruby recheck: 0 `Unsupported operator: ==` in 41 diagnostics; `==` now in `operator_type` via LANG-STDLIB-TEXT-EQUALITY-P3 | `LANG-STDLIB-TEXT-EQUALITY-P3` CLOSED |
| AP-P08 | WATCH | Variant/ADT surface | `DomainEvent.kind`, `AccountState.status`, `Command.kind` are string tags | variant/ADT follow-up |
| AP-P09 | RESOLVED | `<` operator gap (Ruby TC) | LANG-STDLIB-NUMERIC-COMPARISON-P3 CLOSED — `<`, `<=`, `>=` added to Ruby TC `operator_type` + emitter `operator_for`; Wave P2 unstripped Ruby recheck: 0 `Unsupported operator: <` (39 total diags vs 41 in P1, 2 fewer = the two `<` errors) | `LANG-STDLIB-NUMERIC-COMPARISON-P3` CLOSED |
| AP-P10 | RESOLVED | Ruby emitter UTF-8 encoding | LANG-EMITTER-ENCODING-P2 CLOSED — 6 encoding sites fixed; Wave P2 unstripped Ruby recheck: no JSON crash; 39 actual diagnostics surface (was crashing before strip workaround); types.ig box-drawing chars are tolerated | `LANG-EMITTER-ENCODING-P2` CLOSED |

## Live Commands Used

Rust real compile:

```bash
cargo run -- compile ../igniter-apps/arch_patterns/types.ig ../igniter-apps/arch_patterns/event_sourcing.ig ../igniter-apps/arch_patterns/state_machine.ig ../igniter-apps/arch_patterns/pipeline.ig ../igniter-apps/arch_patterns/example.ig --out /tmp/arch-patterns-rust.igapp
```

Ruby real compile:

```bash
ruby -Ilib -e 'require "igniter_lang/compiler_orchestrator"; paths = %w[types.ig event_sourcing.ig state_machine.ig pipeline.ig example.ig].map { |f| File.expand_path("../igniter-lab/igniter-apps/arch_patterns/#{f}", __dir__) }; result = IgniterLang::CompilerOrchestrator.new.compile_sources(source_paths: paths, out_path: "/tmp/arch-patterns-ruby.igapp"); puts JSON.pretty_generate(result)'
```

Probe: temporary copy in `/tmp/arch_patterns_probe` with only `stdlib.collection` imports removed.

## Wave P2 Recheck Summary (2026-06-12)

Rust: oof (7 diagnostics — all `call_contract: unknown callee 'append'`). Ruby: oof (39 diagnostics — call_contract dominant, no `<` errors, no JSON crash). AP-P09 RESOLVED (`<` operator added via LANG-STDLIB-NUMERIC-COMPARISON-P3). AP-P10 RESOLVED (UTF-8 crash fixed via LANG-EMITTER-ENCODING-P2). Dominant remaining blocker: call_contract parity (AP-P02) — 7 Rust + many Ruby calls.

## Notes

- Import surface (AP-P01), equality (AP-P07), `<` operator (AP-P09), UTF-8 encoding (AP-P10) all resolved.
- call_contract parity (AP-P02) is the dominant Rust blocker: 7 `call_contract("append",...)` calls.
- is_empty available (AP-P04 READY); state_machine.ig stale comment about missing is_empty() can be updated.
- Event sourcing and middleware remain strong positive fit signals.
