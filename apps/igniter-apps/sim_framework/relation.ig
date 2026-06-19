module SimRelation
import SimTypes
import stdlib.collection.{ map, filter, count }

-- ============================================================
-- Relation[T] Operations
-- ============================================================
-- Demonstrates: Relation[T] (select, project, cross-filter)

-- ── Select: Filter entities by predicate ────────────────────

contract SelectByType {
  input entities : Collection[Entity]
  input target_type : String

  compute selected = filter(entities, e ->
    if e.entity_type == target_type { true } else { false }
  )

  output selected : Collection[Entity]
}

contract SelectByRegion {
  input entities : Collection[Entity]
  input target_region : String

  compute selected = filter(entities, e ->
    if e.region == target_region { true } else { false }
  )

  output selected : Collection[Entity]
}

-- ── Aggregate: Sum populations across entities ──────────────
-- We test the newly discovered `sum` and `fold`!

contract SumPopulation {
  input entities : Collection[Entity]

  compute populations = map(entities, e -> e.population.current)
  compute total = fold(populations, 0, (acc, val) -> acc + val)

  output total : Integer
}

-- ── Relation Join (simulated): Find neighbors ───────────────
-- Given two entity collections (predators and prey in same region),
-- this produces interaction events.

contract CrossMatch {
  input sources : Collection[Entity]
  input targets : Collection[Entity]
  input tick : Integer

  -- For each source, find targets in the same region
  -- This is a Relation JOIN: sources ⋈ targets ON region
  compute interactions = map(sources, s ->
    call_contract("MakeInteraction", s, targets, tick)
  )

  output interactions : Collection[SimEvent]
}

contract MakeInteraction {
  input source : Entity
  input targets : Collection[Entity]
  input tick : Integer

  -- Find first target in same region
  compute same_region = filter(targets, t ->
    if t.region == source.region { true } else { false }
  )

  compute event_count = count(same_region)

  compute event = {
    tick: tick,
    event_type: "INTERACTION",
    source_id: source.id,
    target_id: event_count,
    amount: source.population.current / 10,
    rule_name: "CrossMatch"
  }

  output event : SimEvent
}

-- ── Snapshot: Capture a slice of the simulation ─────────────

contract TakeSnapshot {
  input state : SimState

  compute entity_count = count(state.entities)
  compute event_count = count(state.events)
  compute violation_count = count(state.violations)
  compute total_pop = call_contract("SumPopulation", state.entities)

  compute snapshot = {
    tick: state.tick,
    entity_count: entity_count,
    event_count: event_count,
    violation_count: violation_count,
    total_population: total_pop
  }

  output snapshot : SnapshotSummary
}

type SnapshotSummary {
  tick : Integer
  entity_count : Integer
  event_count : Integer
  violation_count : Integer
  total_population : Integer
}
