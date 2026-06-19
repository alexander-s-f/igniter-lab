module AirCombatSwarm
import AirCombatTypes
import AirCombatVec
import AirCombatStrategy
import stdlib.collection.{ map, filter, count }

-- ============================================================
-- Swarm-level behaviour and read-models
-- ============================================================

-- ── Autonomous swarm step ───────────────────────────────────
-- Every plane advances per the shared strategy. The swarm is purely a
-- DERIVATIVE of the strategy — no per-plane player control.
pure contract SwarmStep {
  input planes : Collection[Plane]
  input target : Track
  input threat : Vec2
  input s : Strategy

  compute moved = map(planes, p ->
    call_contract("DoctrineDispatcher", p, target, threat, s)
  )
  output moved : Collection[Plane]
}

-- ── Centroid (fold-to-struct WORKAROUND) ────────────────────
-- PRESSURE AC-P02: the natural form is a single fold into
-- {sum_x, sum_y, count}, but fold cannot accumulate a record today
-- (OOF-COL4), so we run TWO scalar folds plus count and divide.
pure contract SwarmCentroid {
  input planes : Collection[Plane]

  compute sum_x = fold(planes, 0, (acc, p) -> acc + p.pos.x)
  compute sum_y = fold(planes, 0, (acc, p) -> acc + p.pos.y)
  compute n = count(planes)
  compute safe_n = if n > 0 { n } else { 1 }

  compute c = { x: sum_x / safe_n, y: sum_y / safe_n }
  output c : Vec2
}

-- ── Alive count ─────────────────────────────────────────────
pure contract SwarmAlive {
  input planes : Collection[Plane]
  compute living = filter(planes, p -> if p.alive > 0 { true } else { false })
  compute n = count(living)
  output n : Integer
}

-- ── Threat score: living interceptors in the swarm ──────────
pure contract SwarmThreat {
  input planes : Collection[Plane]
  compute hunters = filter(planes, p ->
    if p.role == 0 { if p.alive > 0 { true } else { false } } else { false }
  )
  compute n = count(hunters)
  output n : Integer
}

-- ── Engagement: kill evaders that stray within lethal range ──
-- An evader (role 1) inside range^2 of the enemy threat point is downed.
pure contract MarkKilled {
  input p : Plane
  input threat : Vec2
  input range2 : Integer

  compute d2 = call_contract("VDist2", p.pos, threat)
  compute still = if p.role == 1 {
    if d2 < range2 { 0 } else { p.alive }
  } else {
    p.alive
  }

  compute marked = {
    id: p.id,
    team: p.team,
    role: p.role,
    pos: p.pos,
    vel: p.vel,
    fuel: p.fuel,
    alive: still
  }
  output marked : Plane
}

pure contract EngageSwarm {
  input planes : Collection[Plane]
  input threat : Vec2
  input range2 : Integer

  compute resolved = map(planes, p ->
    call_contract("MarkKilled", p, threat, range2)
  )
  output resolved : Collection[Plane]
}

-- ── Assembled read-model ────────────────────────────────────
pure contract BuildSwarmStats {
  input planes : Collection[Plane]
  input team : Integer

  compute alive = call_contract("SwarmAlive", planes)
  compute centroid = call_contract("SwarmCentroid", planes)
  compute threat = call_contract("SwarmThreat", planes)

  compute stats = {
    team: team,
    alive: alive,
    centroid: centroid,
    threat: threat
  }
  output stats : SwarmStats
}
