# Architectural Patterns for Igniter

A comprehensive demonstration of three architectural patterns implemented in Igniter, integrated into a single banking domain application. Achieves **full compilation** with **15 contracts**.

## Patterns

### 1. Event Sourcing
State is never stored — it is always derived by replaying events.

```
genesis(pending, bal=0)
  → AccountOpened  → (active, bal=0)
  → Deposited(5000) → (active, bal=5000)
  → Withdrawn(1500) → (active, bal=3500)
  → Deposited(2000) → (active, bal=5500)
  → Frozen         → (frozen, bal=5500)
```

Contracts: `ApplyEvent`, `ReplayEvents3`, `ReplayEvents5`

### 2. State Machine
Explicit transition table with guard conditions.

```
pending  →[AccountOpened]→  active
active   →[Deposited]→      active
active   →[Withdrawn]→      active  (guard: balance ≥ 0)
active   →[Frozen]→         frozen
frozen   →[Unfrozen]→       active
active   →[Closed]→         closed
```

Contracts: `CheckTransition`, `GuardCheck`, `TryTransition`

### 3. Middleware Pipeline
Sequential chain of validation/enrichment stages with short-circuit on rejection.

```
Command → [MwValidateAmount] → [MwCheckFrozen] → [MwCheckBalance] → Result
```

Contracts: `MwValidateAmount`, `MwCheckFrozen`, `MwCheckBalance`, `RunPipeline`

## Compilation

```bash
cargo run -- compile types.ig event_sourcing.ig state_machine.ig pipeline.ig example.ig --out arch_patterns.igapp
```

**Result**: Full compilation — 15 contracts emitted.
