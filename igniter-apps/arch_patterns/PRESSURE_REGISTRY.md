# Architectural Patterns Pressure Registry

Updated: 2026-06-12 (APP-RECHECK-WAVE-P1)

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
| AP-P09 | ACTIVE | `<` operator gap (Ruby TC) | UTF-8-stripped Ruby recheck: 2 `Unsupported operator: <` from pipeline.ig (lines 30, 108): `ctx.command.amount < 1` and `ctx.account.balance < ctx.command.amount`; Ruby TC has `>` but not `<` in `operator_type` | `LANG-STDLIB-NUMERIC-COMPARISON-P1` |
| AP-P10 | ACTIVE | Ruby emitter UTF-8 encoding | `types.ig` contains box-drawing chars (U+2500 `──`) in comments; Ruby JSON serializer crashes with `JSON::GeneratorError`; masks TC diagnostics in unstripped runs; newly surfaced now that TC-level errors are resolved | `LANG-EMITTER-ENCODING-P1` |

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

## Notes

- Import surface (AP-P01) and equality (AP-P07) are resolved; is_empty available (AP-P04 READY).
- The `<` operator gap (AP-P09) affects pipeline.ig balance and amount comparisons — route LANG-STDLIB-NUMERIC-COMPARISON-P1.
- call_contract parity (AP-P02) is the dominant Rust blocker: 7 `call_contract("append",...)` calls.
- UTF-8 encoding issue (AP-P10) masks TC diagnostics in unstripped Ruby runs.
- Event sourcing and middleware remain strong positive fit signals.
- State-machine `CheckTransition` can now branch on `is_empty` result — AP-P04 stale comment in state_machine.ig.
