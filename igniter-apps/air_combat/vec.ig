module AirCombatVec
import AirCombatTypes

-- ============================================================
-- Fixed-point 2D vector math (scale 100)
-- ============================================================
-- No sqrt is available, so distances are kept SQUARED (mag2) and
-- compared squared. This is a deliberate workaround; see AC-P07
-- (missing stdlib.math.sqrt) in PRESSURE_REGISTRY.md.

pure contract VAdd {
  input a : Vec2
  input b : Vec2
  compute r = { x: a.x + b.x, y: a.y + b.y }
  output r : Vec2
}

pure contract VSub {
  input a : Vec2
  input b : Vec2
  compute r = { x: a.x - b.x, y: a.y - b.y }
  output r : Vec2
}

-- Scale by a fixed-point factor s (scale 100): r = a * s
pure contract VScale {
  input a : Vec2
  input s : Integer
  compute r = { x: (a.x * s) / 100, y: (a.y * s) / 100 }
  output r : Vec2
}

-- Squared magnitude: |a|^2  (kept squared — no sqrt)
pure contract VMag2 {
  input a : Vec2
  compute m = (a.x * a.x) + (a.y * a.y)
  output m : Integer
}

-- Squared distance between two points
pure contract VDist2 {
  input a : Vec2
  input b : Vec2
  compute d = call_contract("VSub", a, b)
  compute m = call_contract("VMag2", d)
  output m : Integer
}

-- Clamp a velocity vector to a maximum component speed (coarse, no sqrt).
-- Each axis is independently clamped to [-max, max].
pure contract VClampSpeed {
  input v : Vec2
  input max : Integer
  compute cx = if v.x > max { max } else {
    if v.x < (0 - max) { 0 - max } else { v.x }
  }
  compute cy = if v.y > max { max } else {
    if v.y < (0 - max) { 0 - max } else { v.y }
  }
  compute r = { x: cx, y: cy }
  output r : Vec2
}
