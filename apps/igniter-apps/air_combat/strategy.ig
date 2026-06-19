module AirCombatStrategy
import AirCombatTypes
import AirCombatVec
import AirCombatGuidance

-- ============================================================
-- Doctrine — the autonomous behaviour derived from a Strategy
-- ============================================================
-- The player authors a `Strategy` record. From then on each plane acts
-- AUTONOMOUSLY: its per-tick velocity is a PURE FUNCTION of (plane,
-- strategy, local world view). No live player input at the sim level.
--
-- Doctrines are selected by STATIC dispatch (literal call_contract),
-- exactly the LAB-DYNAMIC-CONTRACT-DISPATCH-P2 discipline: behaviour is
-- chosen by name, never by a runtime string. See AC-P06.

-- Max component speed a plane may command, derived from aggression.
pure contract MaxSpeed {
  input s : Strategy
  compute v = 100 + s.aggression
  output v : Integer
}

-- ── Pursuit doctrine (interceptors) ─────────────────────────
pure contract PursuitDoctrine {
  input self : Plane
  input target : Track
  input s : Strategy

  compute max_v = call_contract("MaxSpeed", s)
  compute new_vel = call_contract("PursueVelocity", self, target, s.intercept_gain, s.lead_time, max_v)
  compute new_pos = call_contract("VAdd", self.pos, new_vel)

  compute moved = {
    id: self.id,
    team: self.team,
    role: self.role,
    pos: new_pos,
    vel: new_vel,
    fuel: self.fuel - 1,
    alive: self.alive
  }
  output moved : Plane
}

-- ── Evasion doctrine (evaders) ──────────────────────────────
pure contract EvasionDoctrine {
  input self : Plane
  input threat : Vec2
  input s : Strategy

  compute max_v = call_contract("MaxSpeed", s)
  -- urgency rises with aggression: a bolder doctrine breaks harder
  compute urgency = 100 + (s.aggression / 2)
  compute new_vel = call_contract("EvadeVelocity", self, threat, urgency, max_v)
  compute new_pos = call_contract("VAdd", self.pos, new_vel)

  compute moved = {
    id: self.id,
    team: self.team,
    role: self.role,
    pos: new_pos,
    vel: new_vel,
    fuel: self.fuel - 1,
    alive: self.alive
  }
  output moved : Plane
}

-- ── Combined doctrine: role-based autonomous step ───────────
-- Same strategy record drives every plane; behaviour forks on role.
-- This is the "swarm as a derivative of the strategy" core.
pure contract CombinedDoctrine {
  input self : Plane
  input target : Track
  input threat : Vec2
  input s : Strategy

  compute stepped = if self.role == 0 {
    call_contract("PursuitDoctrine", self, target, s)
  } else {
    call_contract("EvasionDoctrine", self, threat, s)
  }
  output stepped : Plane
}

-- ── Static dispatcher ───────────────────────────────────────
-- PRESSURE AC-P06: we WANT call_contract(swarm.doctrine, ...) to pick a
-- doctrine by the strategy's name. That returns Unknown (Tier 2), so we
-- hardcode CombinedDoctrine — the trade_robot StrategyDispatcher pattern.
pure contract DoctrineDispatcher {
  input self : Plane
  input target : Track
  input threat : Vec2
  input s : Strategy

  compute stepped = call_contract("CombinedDoctrine", self, target, threat, s)
  output stepped : Plane
}
