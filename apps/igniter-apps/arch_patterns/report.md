# Architectural Patterns Pressure Report

Updated: 2026-06-12

This app demonstrates event sourcing, state machines, and middleware pipelines over a banking account domain. It is architecturally valuable because it stresses composition patterns rather than only data structures or numeric operations.

## Live Check

Source files checked:

- `types.ig`
- `event_sourcing.ig`
- `state_machine.ig`
- `pipeline.ig`
- `example.ig`

Real multi-file compile currently stops before typechecking in both toolchains:

| Toolchain | Result | First blocking diagnostic |
| --- | --- | --- |
| Rust lab compiler | `status: oof` | `OOF-IMP2 unknown import path 'stdlib.collection'` in `ArchPatternsExample`, `ArchPatternsPipeline`, and `ArchPatternsStateMachine` |
| Ruby canon compiler | `status: oof` | same `OOF-IMP2` diagnostics |

Probe method: a temporary copy removed only the `import stdlib.collection.{ ... }` lines to expose downstream pressure without editing the app.

| Toolchain | Probe result | Downstream signal |
| --- | --- | --- |
| Rust lab compiler | `status: oof` | seven `OOF-TY0 call_contract: unknown callee 'append'` diagnostics |

The previous “full compilation achieved” claim is stale on the current toolchain. The app remains valuable, but its current role is architectural pressure rather than compile-success baseline.

## Findings

### AP-P01 - `stdlib.collection` import surface blocks both toolchains

`state_machine.ig`, `pipeline.ig`, and `example.ig` import `stdlib.collection`. Both Rust and Ruby reject this with `OOF-IMP2` before typechecking. This is the same first blocker observed in multiple app-pressure fixtures.

Route: `LANG-STDLIB-IMPORT-SURFACE-P2/P3`.

### AP-P02 - `append` is central to architectural patterns

After removing stdlib imports in a probe, Rust reaches seven `append` call sites. Append is needed for transition table construction, event/pipeline setup, and audit-trail accumulation.

Route: `LANG-STDLIB-COLLECTION-APPEND-P1`.

### AP-P03 - Event sourcing fits pure contracts, but replay wants fold

`ApplyEvent` is an excellent pure contract shape: `(AccountState, DomainEvent) -> AccountState`. The manual `ReplayEvents3` and `ReplayEvents5` contracts show the missing abstraction: replay should be a fold over an event log.

Route: fold follow-up after implementation parity, plus typed invocation/form design for using a contract as the fold step.

### AP-P04 - State machine guards need collection emptiness or find-one

`CheckTransition` can filter transitions, but the app cannot check whether the candidate collection is empty or extract the single matching transition. The current design is optimistic: it applies the event after consulting candidates, but cannot enforce candidate existence directly.

Route: `LAB-STDLIB-IS-EMPTY-P1` and/or `LAB-STDLIB-FIND-ONE-P1`.

### AP-P05 - Middleware pipeline fits static contract chaining

`RunPipeline` shows a strong fit for static middleware composition: each middleware transforms a `PipelineContext`, and rejection short-circuits through a `rejected` flag. This is pure and inspectable.

Route: preserve as positive evidence for static pipeline composition.

### AP-P06 - Dynamic middleware registration is intentionally blocked today

Dynamic middleware lists would require function-as-value, contract-as-value, or form-assisted invocation over a collection. The app should not push Igniter toward ambient callbacks or untyped runtime dispatch.

Route: typed contract refs / form vocabulary / conservative invocation forms, not arbitrary callbacks.

### AP-P07 - Text equality pressure appears throughout patterns

Event kinds, statuses, and command kinds are represented as strings and compared via `==`. This is ordinary deterministic classification logic and appears across event sourcing, state machines, and pipelines.

Route: `LANG-STDLIB-TEXT-EQUALITY-P1` or a scoped deterministic equality/operator parity card.

### AP-P08 - Pattern-level vocabulary wants variants eventually

`DomainEvent.kind`, `AccountState.status`, and `Command.kind` are all string tags. This works as pressure evidence but lacks exhaustiveness and invalid-state prevention.

Route: variant/ADT surface follow-up after stdlib collection and invocation basics stabilize.

## Current Pressure Ranking

1. `stdlib.collection` import surface - blocks both toolchains before typechecking.
2. Collection `append` - required for table construction and audit-trail accumulation.
3. Collection emptiness / find-one - required for state-machine guards.
4. Fold plus typed invocation - required for scalable event replay.
5. Text equality - required for event/status/command classification.
6. Form-assisted static pipeline composition - future ergonomics, not runtime callbacks.
7. Variant/ADT surface - eventual replacement for string tags.

## Non-goals

- Do not claim this app currently fully compiles on the live toolchain.
- Do not introduce dynamic callbacks or function-as-value from this app alone.
- Do not treat optimistic transition application as final state-machine semantics.
- Do not solve `append` through stringly `call_contract` dispatch.
- Do not promote event/status/command strings as canonical ADT substitutes.

## Recommended Next Cards

- `LANG-STDLIB-IMPORT-SURFACE-P2/P3` - clear the first blocker.
- `LANG-STDLIB-COLLECTION-APPEND-P1` - support construction of transition tables and audit trails.
- `LAB-STDLIB-IS-EMPTY-P1` - prove non-empty checks for state-machine validation.
- `LAB-STDLIB-FIND-ONE-P1` - prove single matching transition extraction semantics.
- Invocation forms / typed contract refs follow-up for contract-as-fold-step ergonomics.
