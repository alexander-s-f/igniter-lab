module VmGameApp

-- LAB-FRAME-3D-GAME-IG-P2 — the GAME LOGIC authored in Igniter and run on igniter-vm.
-- `Step(world, boom) -> world` is one deterministic fixed timestep of integer physics (the same
-- math as the Rust `game_loop` demo: impulse + gravity + integrate + wall bounce with damping). The
-- host re-runs this `.ig` reducer to advance / replay / time-travel — so lockstep + replay are proven
-- THROUGH the language. Constants match the Rust demo (FP=4096): grav=FP/220=18, impulse_xz=FP/14=292,
-- impulse_up=FP/7=585, bound=3*FP=12288, 2*bound=24576, damp=244/256.

type Body { px : Integer  py : Integer  pz : Integer  vx : Integer  vy : Integer  vz : Integer }
type World { bodies : Collection[Body] }

-- One body, one timestep.
contract StepBody {
  input b    : Body
  input boom : Integer

  -- boom impulse: radial-out on x/z (by sign of position), up on y
  compute bx = if boom > 0 { if b.px > 0 { 292 } else { if b.px < 0 { 0 - 292 } else { 0 } } } else { 0 }
  compute bz = if boom > 0 { if b.pz > 0 { 292 } else { if b.pz < 0 { 0 - 292 } else { 0 } } } else { 0 }
  compute by = if boom > 0 { 585 } else { 0 }

  compute vx1 = b.vx + bx
  compute vy1 = b.vy + by - 18
  compute vz1 = b.vz + bz

  compute px1 = b.px + vx1
  compute py1 = b.py + vy1
  compute pz1 = b.pz + vz1

  -- wall bounce per axis (reflect position, reverse + damp velocity)
  compute pxr = if px1 > 12288 { 24576 - px1 } else { if px1 < 0 - 12288 { 0 - 24576 - px1 } else { px1 } }
  compute vxr = if px1 > 12288 { (0 - vx1) * 244 / 256 } else { if px1 < 0 - 12288 { (0 - vx1) * 244 / 256 } else { vx1 } }
  compute pyr = if py1 > 12288 { 24576 - py1 } else { if py1 < 0 - 12288 { 0 - 24576 - py1 } else { py1 } }
  compute vyr = if py1 > 12288 { (0 - vy1) * 244 / 256 } else { if py1 < 0 - 12288 { (0 - vy1) * 244 / 256 } else { vy1 } }
  compute pzr = if pz1 > 12288 { 24576 - pz1 } else { if pz1 < 0 - 12288 { 0 - 24576 - pz1 } else { pz1 } }
  compute vzr = if pz1 > 12288 { (0 - vz1) * 244 / 256 } else { if pz1 < 0 - 12288 { (0 - vz1) * 244 / 256 } else { vz1 } }

  compute b2 = { px: pxr, py: pyr, pz: pzr, vx: vxr, vy: vyr, vz: vzr }
  output b2 : Body
}

-- The whole world, one timestep: map the per-body step over the collection.
contract Step {
  input world : World
  input boom  : Integer
  compute next_bodies = map(world.bodies, b -> call_contract("StepBody", b, boom))
  compute w2 = { bodies: next_bodies }
  output w2 : World
}
