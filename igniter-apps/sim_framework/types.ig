module SimTypes

-- ============================================================
-- Universal Simulation Framework: Core Types
-- ============================================================
-- This framework demonstrates pressure on all 8 proposed
-- Igniter structures: Temporal[T], Relation[T], Proof[T],
-- Constraint[T], Contract[I→O], Decision[T], Lens[S,A],
-- Tensor[Shape].

-- ── Temporal[T]: Value with History ─────────────────────────
-- Every entity in the simulation carries its full history.

type TemporalInteger {
  current : Integer
  prev_t1 : Integer    -- t-1
  prev_t2 : Integer    -- t-2
  prev_t3 : Integer    -- t-3
}

-- ── Proof[T]: Value with Audit Trail ────────────────────────
-- Every state change is traceable to the rule that caused it.

type ProofEntry {
  tick : Integer
  rule_name : String
  entity_id : Integer
  field : String
  old_val : Integer
  new_val : Integer
  reason : String
}

-- ── Constraint[T]: Validation Rule ──────────────────────────

type ConstraintDef {
  name : String
  entity_type : String
  field : String
  min_val : Integer
  max_val : Integer
}

type ConstraintViolation {
  constraint_name : String
  entity_id : Integer
  field : String
  actual_val : Integer
  message : String
}

-- ── Relation[T]: Entity Table ───────────────────────────────
-- Entities are stored as a Collection (flat table).
-- Each entity row has an id, a type tag, and named fields.

type Entity {
  id : Integer
  entity_type : String
  name : String
  region : String
  population : TemporalInteger
  resources : TemporalInteger
  health : Integer
}

-- ── Decision[T]: What happens when entities interact ────────

type SimEvent {
  tick : Integer
  event_type : String   -- "GROWTH", "DECLINE", "MIGRATION", "TRADE", "DISASTER"
  source_id : Integer
  target_id : Integer
  amount : Integer
  rule_name : String
}

-- ── Simulation State ────────────────────────────────────────

type SimState {
  tick : Integer
  entities : Collection[Entity]
  events : Collection[SimEvent]
  proofs : Collection[ProofEntry]
  violations : Collection[ConstraintViolation]
}

type SimConfig {
  max_ticks : Integer
  growth_rate : Integer      -- percent (e.g. 10 = 10%)
  decay_rate : Integer       -- percent
  disaster_threshold : Integer
  min_population : Integer
  max_population : Integer
  min_resources : Integer
  max_resources : Integer
}
