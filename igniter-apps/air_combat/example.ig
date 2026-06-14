module AirCombatExample
import AirCombatTypes
import AirCombatEngine
import AirCombatKalman

-- Program entry point — the duel is the default run target.
-- PRESSURE AC-P10: only ONE bare `entrypoint` is allowed today; RunDuel and
-- TrackBogey each want to be a named PROP-029 run-profile (panel preset).
entrypoint RunDuel

-- ============================================================
-- Example: a 3-tick duel between two strategy-authored swarms
-- ============================================================
-- Player A ("Falcons") flies an aggressive intercept doctrine.
-- Player B ("Ravens") flies a cautious evasive doctrine.
-- Each owns a swarm; the swarms then fight autonomously.

-- ── Factories ───────────────────────────────────────────────
-- PRESSURE AC-P04: MakePlane / MakeStrategy exist only to build typed
-- records (inline branch records infer to Unknown). A future record
-- literal / entity surface would remove these.

pure contract MakePlane {
  input id : Integer
  input team : Integer
  input role : Integer
  input px : Integer
  input py : Integer
  input vx : Integer
  input vy : Integer

  compute p = {
    id: id,
    team: team,
    role: role,
    pos: { x: px, y: py },
    vel: { x: vx, y: vy },
    fuel: 1000,
    alive: 1
  }
  output p : Plane
}

pure contract MakeStrategy {
  input aggression : Integer
  input intercept_gain : Integer
  input lead_time : Integer
  input evade_threshold : Integer
  input formation_spread : Integer

  compute s = {
    aggression: aggression,
    intercept_gain: intercept_gain,
    lead_time: lead_time,
    evade_threshold: evade_threshold,
    formation_spread: formation_spread
  }
  output s : Strategy
}

-- ── The duel ────────────────────────────────────────────────
contract RunDuel {

  -- Player A: aggressive interceptors (team 0, role 0)
  compute strat_a = call_contract("MakeStrategy", 80, 60, 3, 40000, 200)
  compute a1 = call_contract("MakePlane", 1, 0, 0, 0,    0,   120, 80)
  compute a2 = call_contract("MakePlane", 2, 0, 0, 0,    300, 120, 60)
  compute a3 = call_contract("MakePlane", 3, 0, 0, 0,    600, 120, 40)

  compute swarm_a = {
    team: 0,
    doctrine: "CombinedDoctrine",
    strategy: strat_a,
    planes: [a1, a2, a3]
  }
  compute player_a = { id: 1, name: "Falcons", swarm: swarm_a, score: 0 }

  -- Player B: cautious evaders (team 1, role 1)
  compute strat_b = call_contract("MakeStrategy", 30, 20, 2, 90000, 300)
  compute b1 = call_contract("MakePlane", 11, 1, 1, 2000, 100, 0 - 40, 30)
  compute b2 = call_contract("MakePlane", 12, 1, 1, 2000, 400, 0 - 40, 10)
  compute b3 = call_contract("MakePlane", 13, 1, 1, 2000, 700, 0 - 40, 0 - 20)

  compute swarm_b = {
    team: 1,
    doctrine: "CombinedDoctrine",
    strategy: strat_b,
    planes: [b1, b2, b3]
  }
  compute player_b = { id: 2, name: "Ravens", swarm: swarm_b, score: 0 }

  compute world0 = { tick: 0, player_a: player_a, player_b: player_b }

  -- Run the autonomous battle for 3 ticks
  compute final = call_contract("RunBattle3", world0)
  output final : World
}

-- ── Kalman tracking demo ────────────────────────────────────
-- Track a moving bogey from 3 noisy measurements. This is the
-- fold-to-struct shape (AC-P01): refine a Track record over a sequence.
contract TrackBogey {
  compute t0 = { est: { x: 1000, y: 1000 }, vel: { x: 0, y: 0 }, p: 1000 }
  compute m1 = { pos: { x: 1110, y: 1040 } }
  compute m2 = { pos: { x: 1225, y: 1085 } }
  compute m3 = { pos: { x: 1335, y: 1130 } }

  compute estimate = call_contract("TrackFold3", t0, m1, m2, m3)
  output estimate : Track
}
