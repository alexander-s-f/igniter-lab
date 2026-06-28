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

-- ── The 3D MESH DESCRIPTOR, authored in Igniter (LAB-FRAME-3D-GAME-IG-MESH-DESCRIPTOR-P7) ──────────
-- `ViewMesh(world) -> Mesh` is the geometry the WebGL host renders. The `.ig` authors the SCENE — one
-- coloured box per body (position FP, half-extents FP, colour 0-255) + a floor box. The host expands
-- each box's fixed cube topology (12 triangles) and rasterizes. So even the render DESCRIPTOR is a
-- deterministic, replayable Igniter artifact; only the projection/raster/light stay on the GPU.
-- (Full triangle-soup emission is blocked today: no flat_map/concat to flatten `Collection[Collection
-- [Vertex]]`, and per-vertex record emission is very verbose — staged to box instances; see the packet.)

type BoxInstance { x : Integer  y : Integer  z : Integer  hx : Integer  hy : Integer  hz : Integer  cr : Integer  cg : Integer  cb : Integer }
type Mesh { floor : BoxInstance  boxes : Collection[BoxInstance] }

-- One body → one coloured cube instance. Colour is a palette over the body id (authored in `.ig`).
contract BodyBox {
  input b : Body
  compute cr = if b.id == 0 { 92 } else { if b.id == 1 { 56 } else { if b.id == 2 { 217 } else { if b.id == 3 { 178 } else { if b.id == 4 { 51 } else { 235 } } } } }
  compute cg = if b.id == 0 { 140 } else { if b.id == 1 { 199 } else { if b.id == 2 { 115 } else { if b.id == 3 { 115 } else { if b.id == 4 { 191 } else { 140 } } } } }
  compute cb = if b.id == 0 { 247 } else { if b.id == 1 { 117 } else { if b.id == 2 { 77 } else { if b.id == 3 { 235 } else { if b.id == 4 { 209 } else { 178 } } } } }
  compute box = { x: b.px, y: b.py, z: b.pz, hx: 2252, hy: 2252, hz: 2252, cr: cr, cg: cg, cb: cb }
  output box : BoxInstance
}

-- VIEW-MESH: (World) -> Mesh. The render geometry, entirely `.ig`. floor: a wide thin box at y=-bound.
contract ViewMesh {
  input world : World
  compute floor = { x: 0, y: 0 - 12288, z: 0, hx: 19660, hy: 80, hz: 19660, cr: 30, cg: 30, cb: 46 }
  compute boxes = map(world.bodies, b -> call_contract("BodyBox", b))
  compute mesh = { floor: floor, boxes: boxes }
  output mesh : Mesh
}
