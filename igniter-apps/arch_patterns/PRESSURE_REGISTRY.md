# Architectural Patterns Pressure Registry

Updated: 2026-06-12

This registry tracks app pressure from `igniter-apps/arch_patterns`. It is evidence, not canon authority.

| ID | Status | Pressure | Evidence | Suggested route |
| --- | --- | --- | --- | --- |
| AP-P01 | ACTIVE | `stdlib.collection` import surface | Rust and Ruby stop at `OOF-IMP2 unknown import path 'stdlib.collection'` in three modules | `LANG-STDLIB-IMPORT-SURFACE-P2/P3` |
| AP-P02 | ACTIVE | `append` collection helper | Rust probe without stdlib imports reaches seven `call_contract: unknown callee 'append'` diagnostics | `LANG-STDLIB-COLLECTION-APPEND-P1` |
| AP-P03 | ACTIVE | Event replay wants fold | `ReplayEvents3` / `ReplayEvents5` are manual unrolls of `ApplyEvent` | fold parity + typed invocation/form follow-up |
| AP-P04 | ACTIVE | Collection emptiness / find-one | `CheckTransition` returns `Collection[Transition]` but cannot enforce non-empty candidate set | `LAB-STDLIB-IS-EMPTY-P1` / `LAB-STDLIB-FIND-ONE-P1` |
| AP-P05 | POSITIVE | Static middleware pipeline | `RunPipeline` chains pure `PipelineContext -> PipelineContext` contracts | preserve as static composition evidence |
| AP-P06 | WATCH | Dynamic middleware registration | Requires function-as-value or conservative form-assisted invocation | typed refs / form vocabulary track |
| AP-P07 | ACTIVE | Text equality | Event kinds, statuses, command kinds use deterministic `==` comparisons | `LANG-STDLIB-TEXT-EQUALITY-P1` |
| AP-P08 | WATCH | Variant/ADT surface | `DomainEvent.kind`, `AccountState.status`, `Command.kind` are string tags | variant/ADT follow-up |

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

- The old full-compile claim is stale on the live toolchain because stdlib imports now gate the app.
- Event sourcing and middleware remain strong positive fit signals.
- State-machine correctness should not rely on optimistic application once collection emptiness/find-one exists.
