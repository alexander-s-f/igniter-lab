# Architectural Patterns: Pressure Report

This application is a breakthrough — the first to test **architectural composition**
rather than data structure manipulation. It demonstrates that Igniter's contract
model naturally supports several major software architecture patterns.

## 1. Event Sourcing — PERFECT FIT ✅

Igniter's immutable contracts are a **natural home for Event Sourcing**.
Each `ApplyEvent` call is a pure function: `(State, Event) → State`.
The pattern requires zero workarounds.

**Critical Gap: `fold` / `reduce`**

The elegance breaks down at replay. Without `fold(events, initial, ApplyEvent)`,
we must manually unroll: `ReplayEvents3`, `ReplayEvents5`, etc. Each variant
is a separate contract with hardcoded depth.

A single `fold` combinator would make Event Sourcing a first-class pattern:
```
compute final = fold(event_log.events, genesis, ApplyEvent)
```

**Priority**: `stdlib.collection.fold` is arguably the single highest-impact
addition for Igniter's architectural expressiveness.

## 2. State Machine — GOOD FIT ⚠️

The transition table pattern works well: transitions are data (records),
matching is done via `filter()`, and state updates use `ApplyEvent`.

**Gap: Collection-to-Boolean conversion**

`CheckTransition` returns `Collection[Transition]` (the matching transitions).
To truly validate a transition, we need to know if this collection is
non-empty. Without `is_empty()`, the state machine must be **optimistic**
— it always applies the event and trusts that the transition table was
consulted upstream.

This is the same `head()` / `is_empty()` gap identified in the Decision
Tree and Bloom Filter reports.

## 3. Middleware Pipeline — EXCELLENT FIT ✅

The pipeline pattern maps beautifully to Igniter's contract chaining:
```
step_1 = MwValidateAmount(ctx)
step_2 = MwCheckFrozen(step_1)
step_3 = MwCheckBalance(step_2)
```

The `PipelineContext` record carries both the command payload AND the
pipeline metadata (rejected, reject_reason, audit_trail). Each middleware
receives the full context and returns a modified version.

**Short-circuit via `rejected` flag** works perfectly — each middleware
checks `if ctx.rejected { ctx }` first.

**Gap: Dynamic middleware registration**

Middlewares are statically chained in `RunPipeline`. There's no way to
dynamically compose a pipeline from a `Collection[Middleware]` because:
- Igniter has no function-as-value / first-class functions
- `call_contract` requires a string literal, not a variable
- There's no `fold` to iterate over a middleware list

## 4. Cross-Pattern Integration

The example (`RunFullScenario`) chains all three patterns in a single contract:
1. Event Sourcing replays 5 events to derive state
2. State Machine validates and applies a transition (unfreeze)
3. Middleware Pipeline validates commands against the derived state

This works because all patterns operate on the same domain types
(`AccountState`, `DomainEvent`, `Command`). The shared type system
provides natural integration points.

## 5. Architectural Patterns That Are BLOCKED in Igniter

| Pattern | Blocker |
|---|---|
| **Observer / PUB-SUB** | No callbacks, no function-as-value |
| **Strategy** | No polymorphism, no function-as-value |
| **Decorator** | No higher-order contracts |
| **Repository** | No IO / storage primitives |
| **Actor Model** | No concurrency, no message queues |

## Summary Table

| Pattern | Fit | Key Gap |
|---|---|---|
| Event Sourcing | ✅ Perfect | `fold` / `reduce` |
| State Machine | ⚠️ Good | `is_empty()` for guard validation |
| Middleware Pipeline | ✅ Excellent | Dynamic middleware registration |
| Observer/PUB-SUB | ❌ Blocked | No function-as-value |
| Strategy | ❌ Blocked | No polymorphism |
