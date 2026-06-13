module SimRules
import SimTypes
import SimTemporal
import stdlib.collection.{ map }

-- ============================================================
-- Simulation Rules (Contract[I→O] Pattern)
-- ============================================================
-- Each rule is a pure contract: Entity × Config → Entity
-- Rules are pluggable and can be composed dynamically.

-- ── Growth Rule ─────────────────────────────────────────────
-- Population grows by growth_rate percent per tick

contract GrowthRule {
  input e : Entity
  input config : SimConfig
  input tick : Integer

  compute growth = (e.population.current * config.growth_rate) / 100
  compute new_pop = e.population.current + growth

  compute result = call_contract("LensUpdatePopulation", e, new_pop, tick, "GrowthRule")

  output result : Entity
}

-- ── Decay Rule ──────────────────────────────────────────────
-- Resources decay by decay_rate percent per tick

contract DecayRule {
  input e : Entity
  input config : SimConfig
  input tick : Integer

  compute decay = (e.resources.current * config.decay_rate) / 100
  compute new_res = e.resources.current - decay

  compute result = call_contract("LensUpdateResources", e, new_res, tick, "DecayRule")

  output result : Entity
}

-- ── Disaster Rule ───────────────────────────────────────────
-- If resources drop below threshold, population takes a hit

contract DisasterRule {
  input e : Entity
  input config : SimConfig
  input tick : Integer

  compute is_disaster = if e.resources.current < config.disaster_threshold { true } else { false }

  compute new_pop = if is_disaster {
    e.population.current - (e.population.current / 4)
  } else {
    e.population.current
  }

  compute result = call_contract("LensUpdatePopulation", e, new_pop, tick, "DisasterRule")

  output result : Entity
}

-- ── Apply Rule Pipeline (Contract[I→O] composition) ─────────
-- Takes a list of rule names and applies them sequentially.
-- This is the Contract[I→O] pattern: contracts as values.

contract ApplyRulePipeline {
  input e : Entity
  input config : SimConfig
  input tick : Integer
  input rules : Collection[String]

  -- Apply rules using dynamic dispatch + map
  -- Each rule transforms the entity
  -- LIMITATION: map cannot thread state (each rule sees original entity)
  -- This demonstrates WHY we need fold — to chain transformations.

  -- Without fold, we manually unroll the pipeline:
  compute after_growth = call_contract("GrowthRule", e, config, tick)
  compute after_decay = call_contract("DecayRule", after_growth, config, tick)
  compute after_disaster = call_contract("DisasterRule", after_decay, config, tick)

  output after_disaster : Entity
}
