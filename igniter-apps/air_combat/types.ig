module AirCombatTypes

-- ============================================================
-- Air Combat: a multiplayer, strategy-driven swarm simulation
-- ============================================================
-- Theme: each PLAYER owns a SWARM (fleet) of aircraft and authors a
-- STRATEGY. The swarm then operates AUTONOMOUSLY as a pure derivative
-- of that strategy — no per-frame player control at the sim level.
--
-- All arithmetic is fixed-point Integer at scale 100 (1.00 == 100).
-- There is NO float, NO sqrt, NO clock, NO RNG, NO IO at this stage.
-- Those are recorded as language/runtime pressure in PRESSURE_REGISTRY.md.

-- ── Geometry ────────────────────────────────────────────────
-- 2D battlespace coordinate / vector. Scale 100 (centimetres-ish).

type Vec2 {
  x : Integer
  y : Integer
}

-- ── Aircraft ────────────────────────────────────────────────
-- role: 0 = INTERCEPTOR (hunts), 1 = EVADER (flees)
-- team: which player owns this plane
-- alive: 1 = flying, 0 = downed

type Plane {
  id : Integer
  team : Integer
  role : Integer
  pos : Vec2
  vel : Vec2
  fuel : Integer
  alive : Integer
}

-- ── Track: a Kalman / alpha-beta state estimate ─────────────
-- The estimate of an opponent's kinematics, accumulated from noisy
-- measurements. `p` is a scalar covariance proxy (uncertainty):
-- it GROWS on predict and SHRINKS on update.
--
-- PRESSURE: refining a Track over a sequence of measurements is the
-- canonical fold-to-struct case — fold(measurements, track0,
-- (track, meas) -> updated_track). Today that fails (OOF-COL4), so
-- `engine.ig` manually unrolls the steps. See AC-P01.

type Track {
  est : Vec2
  vel : Vec2
  p : Integer
}

-- ── Strategy: the player-authored doctrine ──────────────────
-- This record IS the player's "program". The swarm reads it and acts.
-- intercept_gain : proportional-navigation steering gain (scale 100)
-- lead_time      : how far ahead to aim (ticks)
-- evade_threshold: distance^2 at which an evader breaks away
-- aggression     : 0..100, bias toward closing vs. conserving
-- formation_spread: desired separation for the swarm

type Strategy {
  aggression : Integer
  intercept_gain : Integer
  lead_time : Integer
  evade_threshold : Integer
  formation_spread : Integer
}

-- ── Swarm: one player's fleet + its doctrine ────────────────

type Swarm {
  team : Integer
  doctrine : String
  strategy : Strategy
  planes : Collection[Plane]
}

-- ── Player: the entity that owns a swarm and a score ────────
-- PRESSURE: Player is the config(strategy) + state(swarm,score) +
-- behavior(doctrine contracts) triad that a future `entity` would
-- bind. Today every contract threads the whole Player in and out by
-- hand. See AC-P05.

type Player {
  id : Integer
  name : String
  swarm : Swarm
  score : Integer
}

-- ── World: the multiplayer battlespace ──────────────────────
-- Two players, symmetric. The engine ticks the world forward.

type World {
  tick : Integer
  player_a : Player
  player_b : Player
}

-- ── Aggregate read-models (pure projections) ────────────────

type SwarmStats {
  team : Integer
  alive : Integer
  centroid : Vec2
  threat : Integer
}

type Measurement {
  pos : Vec2
}
