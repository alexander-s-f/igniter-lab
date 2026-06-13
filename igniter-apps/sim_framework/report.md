# Simulation Framework Pressure Report

The Simulation Framework is the largest and most complex Igniter application (26 contracts, 7 modules). By building a universal simulation engine with an Ecosystem (Predator-Prey) domain, we stress-tested all 8 proposed novel data structures and discovered **2 entirely new concepts**.

## Structures Validated

### 1. Temporal[T] — ✅ VALIDATED, CRITICAL

We implemented `TemporalInteger` as a sliding window of 4 time steps (`current`, `prev_t1`, `prev_t2`, `prev_t3`).

**What worked brilliantly:**
- `EvolveTemporal`: shifting the window forward is a pure, elegant contract
- `TemporalDelta`: computing change between time steps
- `TemporalTrend`: analyzing trajectory (GROWING/DECLINING/STABLE/RECOVERING/SLOWING)
- `Rewind1`: time travel by shifting the window backward

**What we need from the language:**
- `Temporal[T]` should be a **built-in generic type** with compiler-managed history depth
- The compiler could auto-generate `evolve`, `delta`, `rewind` operations
- A `@temporal` annotation on entity fields would be ideal

### 2. Relation[T] — ✅ VALIDATED, CRITICAL

We used `Collection[Entity]` as a flat relation (table).

**What worked:**
- `SelectByType`, `SelectByRegion`: trivial filter operations (SQL WHERE)
- `SumPopulation`: **fold actually works!** We successfully used `fold(populations, 0, (acc, val) -> acc + val)`

**What's blocked:**
- `GROUP BY`: still impossible. We can't group entities by region and sum per-group.
- `JOIN`: `CrossMatch` simulates a join by nesting filter inside map, but it's O(N²) and lossy.
- `ORDER BY`: no `sort`.

### 3. Proof[T] — ✅ VALIDATED

We generated `ProofEntry` records for every state change via `LensUpdate*` contracts.

**Discovery:** Multi-output contracts (`output entity : Entity` + `output proof : ProofEntry`) cause `call_contract` to return `Unknown` because it only resolves the FIRST output's type. This means **Proof[T] needs to be EMBEDDED inside the returned value**, not as a separate output.

**New pattern emerged:**
```igniter
type ProvenEntity {
  entity : Entity
  proof : ProofEntry
}
```
This wrapping pattern is essentially a **Monad** — the value carries its context (proof) with it.

### 4. Constraint[T] — ✅ VALIDATED

`CheckConstraint` validates entities against `ConstraintDef` bounds.

**Discovery:** Inline record literals inside `if/else` branches resolve to `Unknown` type. We must extract them into helper contracts (`MakeViolation`). This is a **parser/typechecker limitation** that would be solved by proper type inference for record literals in conditional expressions.

### 5. Contract[I→O] — ✅ VALIDATED

Rules (`GrowthRule`, `DecayRule`, `DisasterRule`) are pure contracts with identical signatures. `ApplyRulePipeline` composes them.

**Discovery:** Without `fold`, we CANNOT dynamically chain contracts from a `Collection[String]`. We must manually unroll:
```igniter
compute after_growth = call_contract("GrowthRule", e, config, tick)
compute after_decay = call_contract("DecayRule", after_growth, config, tick)
```
**Fold over contracts** would unlock true dynamic pipeline composition.

### 6. Decision[T] — ✅ VALIDATED

`DecideAction` implements a decision tree that maps constraint violations to corrective actions.

### 7. Lens[S,A] — ✅ VALIDATED

`LensUpdatePopulation` and `LensUpdateResources` demonstrate focused field updates on immutable entities. Each Lens contract takes an entity, updates ONE field's temporal value, and returns a new entity with all other fields preserved.

**Pain point:** Every Lens requires manually copying ALL unchanged fields. With 7 fields per Entity, this is verbose. A `with` syntax would eliminate this:
```igniter
-- Proposed
compute updated = e with { population: evolved_pop }
```

### 8. Tensor[Shape] — ⚠️ PARTIALLY VALIDATED

Not directly implemented as a type, but the Entity × Region matrix is conceptually a 2D tensor. The `CrossMatch` contract performs a tensor-like cross-product. Full tensors still require `reduce`/`sum` for aggregation.

---

## New Concepts Discovered

### NEW: `Snapshot[T]` — Frozen State Slice

During development, we realized that `TakeSnapshot` produces a fundamentally different kind of value: a **read-only, aggregated summary** of the simulation state at a point in time. This is not just a copy — it's a *projection* with computed fields (totals, counts).

```igniter
-- Proposed native type
type Snapshot[T] = frozen {
  source : T
  computed_at : Integer
  aggregates : Map[String, Integer]
}
```

`Snapshot[T]` could be a compiler-managed type that automatically captures and freezes state, preventing mutation and enabling efficient diffing between snapshots.

### NEW: `Trajectory[T]` — Collection of Temporal States

We discovered that `Temporal[T]` tracks a SINGLE entity's history, but simulations need to track the history of an ENTIRE state (all entities together). This is a `Trajectory` — a time-indexed collection of snapshots.

```igniter
type Trajectory[T] {
  snapshots : Collection[Snapshot[T]]
  current_tick : Integer
}

-- Time travel becomes navigation
compute past = seek(trajectory, tick: 5)
compute diff = compare(trajectory, tick_a: 3, tick_b: 7)
```

This is fundamentally different from both `Temporal[T]` (single value history) and `Collection[Snapshot[T]]` (unindexed bag). A `Trajectory` knows its time axis and supports efficient seeking.

---

## Validated fold()!

We successfully compiled `fold(populations, 0, (acc, val) -> acc + val)` — this is the FIRST confirmed use of `fold` in an Igniter application! The syntax is:
```
fold(collection, initial_value, (accumulator, element) -> expression)
```

## Summary Table

| Structure | Validated | Key Finding |
|---|---|---|
| Temporal[T] | ✅ | Sliding window + trend analysis works perfectly |
| Relation[T] | ✅ | SELECT works; GROUP BY / JOIN blocked |
| Proof[T] | ✅ | Must embed in return type (monadic wrapping) |
| Constraint[T] | ✅ | Works, but inline records in if/else → Unknown |
| Contract[I→O] | ✅ | Manual unrolling works; fold over contracts needed |
| Decision[T] | ✅ | Natural fit for Igniter's if/else |
| Lens[S,A] | ✅ | Verbose without `with` syntax |
| Tensor[Shape] | ⚠️ | Conceptual only; needs reduce/sum |
| **Snapshot[T]** | 🆕 | New concept: frozen aggregated state slice |
| **Trajectory[T]** | 🆕 | New concept: time-indexed collection of snapshots |
