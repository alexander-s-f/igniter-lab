# Architectural Patterns for Igniter

A demonstration of three architectural patterns implemented in Igniter and integrated into a single banking-domain application: event sourcing, state machine transitions, and middleware pipelines.

## Patterns

### 1. Event Sourcing

State is derived by replaying events.

```text
genesis(pending, bal=0)
  -> AccountOpened   -> (active, bal=0)
  -> Deposited(5000) -> (active, bal=5000)
  -> Withdrawn(1500) -> (active, bal=3500)
  -> Deposited(2000) -> (active, bal=5500)
  -> Frozen          -> (frozen, bal=5500)
```

Contracts: `ApplyEvent`, `ReplayEvents3`, `ReplayEvents5`.

### 2. State Machine

Explicit transition table with guard conditions.

```text
pending -> [AccountOpened] -> active
active  -> [Deposited]     -> active
active  -> [Withdrawn]     -> active
active  -> [Frozen]        -> frozen
frozen  -> [Unfrozen]      -> active
active  -> [Closed]        -> closed
```

Contracts: `CheckTransition`, `GuardCheck`, `TryTransition`.

### 3. Middleware Pipeline

Sequential validation/enrichment stages with short-circuit through a `rejected` flag.

```text
Command -> [MwValidateAmount] -> [MwCheckFrozen] -> [MwCheckBalance] -> Result
```

Contracts: `MwValidateAmount`, `MwCheckFrozen`, `MwCheckBalance`, `RunPipeline`.

## Pressure Docs

- [`report.md`](report.md) - live compiler findings and pressure analysis.
- [`PRESSURE_REGISTRY.md`](PRESSURE_REGISTRY.md) - concise pressure IDs and suggested routes.

## Current Compile Status

Real multi-file compile currently stops in both toolchains on the same first blocker:

```text
OOF-IMP2 unknown import path 'stdlib.collection'
```

A temporary probe that removes only the stdlib collection imports exposes downstream `append` pressure in transition table construction and audit-trail accumulation.

## Testing

Rust lab compiler:

```bash
cargo run -- compile ../igniter-apps/arch_patterns/types.ig ../igniter-apps/arch_patterns/event_sourcing.ig ../igniter-apps/arch_patterns/state_machine.ig ../igniter-apps/arch_patterns/pipeline.ig ../igniter-apps/arch_patterns/example.ig --out /tmp/arch-patterns-rust.igapp
```

Ruby canon compiler:

```bash
ruby -Ilib -e 'require "igniter_lang/compiler_orchestrator"; paths = %w[types.ig event_sourcing.ig state_machine.ig pipeline.ig example.ig].map { |f| File.expand_path("../igniter-lab/igniter-apps/arch_patterns/#{f}", __dir__) }; result = IgniterLang::CompilerOrchestrator.new.compile_sources(source_paths: paths, out_path: "/tmp/arch-patterns-ruby.igapp"); puts JSON.pretty_generate(result)'
```
