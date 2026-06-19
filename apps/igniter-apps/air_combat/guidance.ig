module AirCombatGuidance
import AirCombatTypes
import AirCombatVec

-- ============================================================
-- Guidance — pursuit (intercept) and evasion steering
-- ============================================================
-- Pure-pursuit / lead-pursuit approximation in fixed-point. Exact
-- proportional navigation needs a unit vector (sqrt); we approximate
-- with a gain-scaled steering vector clamped to max speed. See AC-P07.

-- Predicted intercept point: where the target will be in `lead` ticks.
pure contract LeadPoint {
  input target : Track
  input lead : Integer

  compute ahead = call_contract("VScale", target.vel, lead * 100)
  compute lead_point = call_contract("VAdd", target.est, ahead)
  output lead_point : Vec2
}

-- Pursue velocity: steer the interceptor toward the lead point.
-- gain is the strategy's intercept_gain (scale 100).
pure contract PursueVelocity {
  input self : Plane
  input target : Track
  input gain : Integer
  input lead : Integer
  input max_speed : Integer

  compute aim = call_contract("LeadPoint", target, lead)
  compute toward = call_contract("VSub", aim, self.pos)
  compute steer = call_contract("VScale", toward, gain)
  compute desired = call_contract("VClampSpeed", steer, max_speed)
  output desired : Vec2
}

-- Evade velocity: steer directly away from the nearest threat point.
pure contract EvadeVelocity {
  input self : Plane
  input threat : Vec2
  input urgency : Integer
  input max_speed : Integer

  compute away = call_contract("VSub", self.pos, threat)
  compute steer = call_contract("VScale", away, urgency)
  compute desired = call_contract("VClampSpeed", steer, max_speed)
  output desired : Vec2
}
