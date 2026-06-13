module SimExample
import SimTypes
import SimRelation
import SimEngine

-- ============================================================
-- Ecosystem Simulation: Predator-Prey Model
-- ============================================================

contract RunEcosystemSim {

  -- ── Configuration ─────────────────────────────────────────
  compute config = {
    max_ticks: 10,
    growth_rate: 15,        -- 15% growth per tick
    decay_rate: 5,          -- 5% resource decay per tick
    disaster_threshold: 20, -- below 20 resources triggers disaster
    min_population: 10,
    max_population: 10000,
    min_resources: 0,
    max_resources: 1000
  }

  -- ── Initial Entities (Relation[Entity]) ───────────────────
  compute wolves = {
    id: 1,
    entity_type: "predator",
    name: "Wolves",
    region: "Forest",
    population: { current: 50, prev_t1: 50, prev_t2: 50, prev_t3: 50 },
    resources: { current: 200, prev_t1: 200, prev_t2: 200, prev_t3: 200 },
    health: 80
  }

  compute rabbits = {
    id: 2,
    entity_type: "prey",
    name: "Rabbits",
    region: "Forest",
    population: { current: 500, prev_t1: 500, prev_t2: 500, prev_t3: 500 },
    resources: { current: 300, prev_t1: 300, prev_t2: 300, prev_t3: 300 },
    health: 90
  }

  compute deer = {
    id: 3,
    entity_type: "prey",
    name: "Deer",
    region: "Plains",
    population: { current: 200, prev_t1: 200, prev_t2: 200, prev_t3: 200 },
    resources: { current: 400, prev_t1: 400, prev_t2: 400, prev_t3: 400 },
    health: 85
  }

  compute bears = {
    id: 4,
    entity_type: "predator",
    name: "Bears",
    region: "Plains",
    population: { current: 30, prev_t1: 30, prev_t2: 30, prev_t3: 30 },
    resources: { current: 150, prev_t1: 150, prev_t2: 150, prev_t3: 150 },
    health: 75
  }

  -- ── Initial State ─────────────────────────────────────────
  compute initial_state = {
    tick: 0,
    entities: [wolves, rabbits, deer, bears],
    events: [],
    proofs: [],
    violations: []
  }

  -- ── Run 3 ticks ───────────────────────────────────────────
  compute final_state = call_contract("RunSim3Ticks", initial_state, config)

  -- ── Snapshot at the end ───────────────────────────────────
  compute snapshot = call_contract("TakeSnapshot", final_state)

  -- ── Trend Analysis ────────────────────────────────────────
  compute trends = call_contract("AnalyzeTrends", final_state)

  -- ── Time Travel: Rewind 1 tick ────────────────────────────
  compute rewound = call_contract("TimeTravel", final_state)
  compute rewound_snapshot = call_contract("TakeSnapshot", rewound)

  -- ── Relation Query: Only predators ────────────────────────
  compute predators_only = call_contract("SelectByType", final_state.entities, "predator")

  -- ── Relation Query: Only Forest region ────────────────────
  compute forest_only = call_contract("SelectByRegion", final_state.entities, "Forest")

  output final_state : SimState
  output snapshot : SnapshotSummary
  output trends : Collection[EntityTrendReport]
  output rewound_snapshot : SnapshotSummary
  output predators_only : Collection[Entity]
  output forest_only : Collection[Entity]
}
