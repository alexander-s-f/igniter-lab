module AirCombatEngine
import AirCombatTypes
import AirCombatVec
import AirCombatSwarm

-- ============================================================
-- The simulation engine — multiplayer world tick
-- ============================================================
-- One authoritative step advances BOTH players' swarms, resolves
-- engagements, and updates scores. Everything is pure: the entire
-- World is threaded in and out by hand.
--
-- PRESSURE AC-P05: WorldTick is the config+state+behavior triad a
-- future `entity` would bind — note how much of the body is just
-- re-threading Player/Swarm records field by field.

pure contract WorldTick {
  input world : World

  -- doctrines (the players' authored strategies)
  compute strat_a = world.player_a.swarm.strategy
  compute strat_b = world.player_b.swarm.strategy

  -- enemy centroids = each side's shared target / threat point
  compute centroid_a = call_contract("SwarmCentroid", world.player_a.swarm.planes)
  compute centroid_b = call_contract("SwarmCentroid", world.player_b.swarm.planes)

  -- coarse enemy track (vel unknown at world level; refined Kalman
  -- tracking is demonstrated in example.ig via TrackFold3)
  compute target_a = { est: centroid_b, vel: { x: 0, y: 0 }, p: 0 }
  compute target_b = { est: centroid_a, vel: { x: 0, y: 0 }, p: 0 }

  -- autonomous swarm advance
  compute stepped_a = call_contract("SwarmStep", world.player_a.swarm.planes, target_a, centroid_b, strat_a)
  compute stepped_b = call_contract("SwarmStep", world.player_b.swarm.planes, target_b, centroid_a, strat_b)

  -- engagement: evaders within lethal range^2 (150^2 = 22500) are downed
  compute engaged_a = call_contract("EngageSwarm", stepped_a, centroid_b, 22500)
  compute engaged_b = call_contract("EngageSwarm", stepped_b, centroid_a, 22500)

  -- score = enemy evaders downed this tick
  compute alive_b_before = call_contract("SwarmAlive", world.player_b.swarm.planes)
  compute alive_b_after = call_contract("SwarmAlive", engaged_b)
  compute kills_by_a = alive_b_before - alive_b_after

  compute alive_a_before = call_contract("SwarmAlive", world.player_a.swarm.planes)
  compute alive_a_after = call_contract("SwarmAlive", engaged_a)
  compute kills_by_b = alive_a_before - alive_a_after

  -- rebuild swarms (manual record threading)
  compute swarm_a2 = {
    team: world.player_a.swarm.team,
    doctrine: world.player_a.swarm.doctrine,
    strategy: strat_a,
    planes: engaged_a
  }
  compute swarm_b2 = {
    team: world.player_b.swarm.team,
    doctrine: world.player_b.swarm.doctrine,
    strategy: strat_b,
    planes: engaged_b
  }

  compute player_a2 = {
    id: world.player_a.id,
    name: world.player_a.name,
    swarm: swarm_a2,
    score: world.player_a.score + kills_by_a
  }
  compute player_b2 = {
    id: world.player_b.id,
    name: world.player_b.name,
    swarm: swarm_b2,
    score: world.player_b.score + kills_by_b
  }

  compute next_world = {
    tick: world.tick + 1,
    player_a: player_a2,
    player_b: player_b2
  }
  output next_world : World
}

-- ── Manual multi-tick run (fold-over-state WORKAROUND) ───────
-- PRESSURE AC-P03: this wants to be
--   fold(range(0, N), world0, (w, _) -> WorldTick(w))
-- but folding state through a record accumulator is unavailable today,
-- so the battle is unrolled by hand (trade_robot RunBacktest pattern).
pure contract RunBattle3 {
  input world0 : World
  compute w1 = call_contract("WorldTick", world0)
  compute w2 = call_contract("WorldTick", w1)
  compute w3 = call_contract("WorldTick", w2)
  output w3 : World
}
