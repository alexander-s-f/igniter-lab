module SimTemporal
import SimTypes
import stdlib.collection.{ map, filter }

-- ============================================================
-- Temporal[T] Operations
-- ============================================================
-- Demonstrates: Temporal[T], Lens[S,A], Proof[T]

-- ── Evolve: Shift the temporal window forward ───────────────
-- Pushes current → prev_t1 → prev_t2 → prev_t3 and sets new current.

contract EvolveTemporal {
  input t : TemporalInteger
  input new_val : Integer

  compute evolved = {
    current: new_val,
    prev_t1: t.current,
    prev_t2: t.prev_t1,
    prev_t3: t.prev_t2
  }

  output evolved : TemporalInteger
}

-- ── Delta: Compute difference between current and previous ──

contract TemporalDelta {
  input t : TemporalInteger

  compute delta = t.current - t.prev_t1
  output delta : Integer
}

-- ── Trend: Is the value growing, stable, or declining? ──────

contract TemporalTrend {
  input t : TemporalInteger

  compute d1 = t.current - t.prev_t1
  compute d2 = t.prev_t1 - t.prev_t2

  -- Trend: "GROWING" if both deltas positive, "DECLINING" if both negative
  compute trend = if d1 > 0 {
    if d2 > 0 { "GROWING" } else { "RECOVERING" }
  } else {
    if d1 == 0 { "STABLE" } else {
      if d2 < 0 { "DECLINING" } else { "SLOWING" }
    }
  }

  output trend : String
}

-- ── Rewind: Time travel — restore state from t-N ────────────

contract Rewind1 {
  input t : TemporalInteger

  compute rewound = {
    current: t.prev_t1,
    prev_t1: t.prev_t2,
    prev_t2: t.prev_t3,
    prev_t3: 0
  }

  output rewound : TemporalInteger
}

-- ── Lens: Update a specific entity's population ─────────────
-- This is the Lens[Entity, TemporalInteger] pattern:
-- We take an entity and a new population value, and return
-- a new entity with evolved population (all other fields intact).

contract LensUpdatePopulation {
  input e : Entity
  input new_pop : Integer
  input tick : Integer
  input rule_name : String

  compute evolved_pop = call_contract("EvolveTemporal", e.population, new_pop)

  compute proof = {
    tick: tick,
    rule_name: rule_name,
    entity_id: e.id,
    field: "population",
    old_val: e.population.current,
    new_val: new_pop,
    reason: concat(concat(rule_name, ": "), concat(concat("pop ", "changed"), ""))
  }

  compute updated_entity = {
    id: e.id,
    entity_type: e.entity_type,
    name: e.name,
    region: e.region,
    population: evolved_pop,
    resources: e.resources,
    health: e.health
  }

  output updated_entity : Entity
}

contract LensUpdateResources {
  input e : Entity
  input new_res : Integer
  input tick : Integer
  input rule_name : String

  compute evolved_res = call_contract("EvolveTemporal", e.resources, new_res)

  compute proof = {
    tick: tick,
    rule_name: rule_name,
    entity_id: e.id,
    field: "resources",
    old_val: e.resources.current,
    new_val: new_res,
    reason: concat(concat(rule_name, ": "), concat("res ", "changed"))
  }

  compute updated_entity = {
    id: e.id,
    entity_type: e.entity_type,
    name: e.name,
    region: e.region,
    population: e.population,
    resources: evolved_res,
    health: e.health
  }

  output updated_entity : Entity
}
