module SimEngine
import SimTypes
import SimTemporal
import SimRelation
import SimConstraints
import SimRules
import stdlib.collection.{ map, filter, count }

-- ============================================================
-- Simulation Engine: The Core Tick Loop
-- ============================================================

-- ── Single Tick: Advance the entire simulation by 1 step ────

contract SimTick {
  input state : SimState
  input config : SimConfig

  compute new_tick = state.tick + 1

  -- Step 1: Apply all rules to all entities
  compute rule_names = ["GrowthRule", "DecayRule", "DisasterRule"]
  compute evolved_entities = map(state.entities, e ->
    call_contract("ApplyRulePipeline", e, config, new_tick, rule_names)
  )

  -- Step 2: Generate interaction events (Cross-Match / JOIN)
  compute predators = filter(evolved_entities, e ->
    if e.entity_type == "predator" { true } else { false }
  )
  compute prey = filter(evolved_entities, e ->
    if e.entity_type == "prey" { true } else { false }
  )
  compute interaction_events = call_contract("CrossMatch", predators, prey, new_tick)

  -- Step 3: Check constraints
  compute pop_constraint = {
    name: "PopulationBounds",
    entity_type: "any",
    field: "population",
    min_val: config.min_population,
    max_val: config.max_population
  }

  compute violations = map(evolved_entities, e ->
    call_contract("CheckConstraint", e, pop_constraint)
  )

  -- Step 4: Build new state
  compute new_state = {
    tick: new_tick,
    entities: evolved_entities,
    events: concat(state.events, interaction_events),
    proofs: state.proofs,
    violations: state.violations
  }

  output new_state : SimState
}

-- ── Multi-Tick: Run N ticks ─────────────────────────────────
-- Without recursion or loops, we manually unroll ticks.

contract RunSim3Ticks {
  input state : SimState
  input config : SimConfig

  compute t1 = call_contract("SimTick", state, config)
  compute t2 = call_contract("SimTick", t1, config)
  compute t3 = call_contract("SimTick", t2, config)

  output t3 : SimState
}

-- ── Time Travel API ─────────────────────────────────────────
-- Rewind all entities' temporal fields by 1 step

contract TimeTravel {
  input state : SimState

  compute rewound_entities = map(state.entities, e ->
    call_contract("RewindEntity", e)
  )

  compute rewound_state = {
    tick: state.tick - 1,
    entities: rewound_entities,
    events: state.events,
    proofs: state.proofs,
    violations: state.violations
  }

  output rewound_state : SimState
}

contract RewindEntity {
  input e : Entity

  compute rewound_pop = call_contract("Rewind1", e.population)
  compute rewound_res = call_contract("Rewind1", e.resources)

  compute rewound = {
    id: e.id,
    entity_type: e.entity_type,
    name: e.name,
    region: e.region,
    population: rewound_pop,
    resources: rewound_res,
    health: e.health
  }

  output rewound : Entity
}

-- ── Trend Analysis API ──────────────────────────────────────
-- Analyze trends across all entities

contract AnalyzeTrends {
  input state : SimState

  compute trends = map(state.entities, e ->
    call_contract("EntityTrend", e)
  )

  output trends : Collection[EntityTrendReport]
}

type EntityTrendReport {
  entity_id : Integer
  name : String
  pop_trend : String
  pop_delta : Integer
  res_trend : String
  res_delta : Integer
}

contract EntityTrend {
  input e : Entity

  compute pop_trend = call_contract("TemporalTrend", e.population)
  compute pop_delta = call_contract("TemporalDelta", e.population)
  compute res_trend = call_contract("TemporalTrend", e.resources)
  compute res_delta = call_contract("TemporalDelta", e.resources)

  compute report = {
    entity_id: e.id,
    name: e.name,
    pop_trend: pop_trend,
    pop_delta: pop_delta,
    res_trend: res_trend,
    res_delta: res_delta
  }

  output report : EntityTrendReport
}
