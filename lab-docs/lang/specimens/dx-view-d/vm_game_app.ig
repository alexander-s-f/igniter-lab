module VmGameApp

-- LAB-FRAME-3D-GAME-IG-P2 — the GAME LOGIC authored in Igniter and run on igniter-vm.
-- `Step(world, boom) -> world` is one deterministic fixed timestep of integer physics (the same
-- math as the Rust `game_loop` demo: impulse + gravity + integrate + wall bounce with damping). The
-- host re-runs this `.ig` reducer to advance / replay / time-travel — so lockstep + replay are proven
-- THROUGH the language. Constants match the Rust demo (FP=4096): grav=FP/220=18, impulse_xz=FP/14=292,
-- impulse_up=FP/7=585, bound=3*FP=12288, 2*bound=24576, damp=244/256.

type Body { px : Integer  py : Integer  pz : Integer  vx : Integer  vy : Integer  vz : Integer  id : Integer }
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

  compute b2 = { px: pxr, py: pyr, pz: pzr, vx: vxr, vy: vyr, vz: vzr, id: b.id }
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

-- ── The VIEW, also authored in Igniter: project the 3D bodies → a 2D scene on the VM ───────────────
-- Perspective projection matches the Rust `game_loop` camera: cx=320, cy=240, focal=600, dist=FP*11=45056,
-- body half-size BODY=FP*55/100=2252 → projected half-size = 2252*600/d = 1351200/d.

type Marker { x : Integer  y : Integer  w : Integer  h : Integer  id : Integer }
type Scene  { markers : Collection[Marker] }

-- Project one body's centre to a depth-sized screen marker (carrying its domain `key` so a click maps
-- back to a body for the reducer).
contract ProjectBody {
  input b : Body
  compute d  = b.pz + 45056
  compute sx = 320 + b.px * 600 / d
  compute sy = 240 - b.py * 600 / d
  compute sz = 1351200 / d
  compute m = { x: sx - sz, y: sy - sz, w: sz + sz, h: sz + sz, id: b.id }
  output m : Marker
}

-- VIEW: (World) -> Scene. The whole projection is `.ig`, run on the VM.
contract View {
  input world : World
  compute markers = map(world.bodies, b -> call_contract("ProjectBody", b))
  compute scene = { markers: markers }
  output scene : Scene
}

-- ── INTERACTION, also `.ig`: a click on a body's marker → kick THAT body, on the VM ────────────────
-- The host hit-tests the clicked marker → its `id`, and runs `Reduce(world, target)`; the matched body
-- (real `==` equality, even inside a `map`-called contract) gets a strong up + radial-out impulse.
-- (Written `target == b.id` — RHS a field access, not a bare ident — so the comparand before `{` does
-- not mis-parse as a record construct.)

contract KickBody {
  input b      : Body
  input target : Integer
  compute kx = if target == b.id { if b.px > 0 { 700 } else { if b.px < 0 { 0 - 700 } else { 0 } } } else { 0 }
  compute kz = if target == b.id { if b.pz > 0 { 700 } else { if b.pz < 0 { 0 - 700 } else { 0 } } } else { 0 }
  compute ky = if target == b.id { 1400 } else { 0 }
  compute b2 = { px: b.px, py: b.py, pz: b.pz, vx: b.vx + kx, vy: b.vy + ky, vz: b.vz + kz, id: b.id }
  output b2 : Body
}

-- REDUCER: (World, target) -> World. Kicks the clicked body (by id). Runs on igniter-vm.
contract Reduce {
  input world  : World
  input target : Integer
  compute next_bodies = map(world.bodies, b -> call_contract("KickBody", b, target))
  compute w2 = { bodies: next_bodies }
  output w2 : World
}
