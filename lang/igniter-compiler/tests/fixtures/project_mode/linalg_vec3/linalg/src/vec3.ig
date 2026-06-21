module Linalg.Vec3

-- LAB-STDLIB-LINALG-VEC3-PACKAGE-P2: fixed-shape Float Vec3 + pure helper contracts. Shape lives in the
-- type (no runtime shape checks). All Float, no implicit coercion. norm uses fast sqrt; det_norm uses the
-- replay-safe det_sqrt. Pure .ig, no VM builtins.
type Vec3 { x : Float, y : Float, z : Float }

pure contract Vec3Make {
  input x : Float
  input y : Float
  input z : Float
  compute v : Vec3 = { x: x, y: y, z: z }
  output v : Vec3
}

pure contract Add {
  input a : Vec3
  input b : Vec3
  compute r : Vec3 = { x: a.x + b.x, y: a.y + b.y, z: a.z + b.z }
  output r : Vec3
}

pure contract Sub {
  input a : Vec3
  input b : Vec3
  compute r : Vec3 = { x: a.x - b.x, y: a.y - b.y, z: a.z - b.z }
  output r : Vec3
}

pure contract Scale {
  input v : Vec3
  input k : Float
  compute r : Vec3 = { x: v.x * k, y: v.y * k, z: v.z * k }
  output r : Vec3
}

pure contract Dot {
  input a : Vec3
  input b : Vec3
  compute d : Float = (a.x * b.x) + (a.y * b.y) + (a.z * b.z)
  output d : Float
}

pure contract Cross {
  input a : Vec3
  input b : Vec3
  compute r : Vec3 = {
    x: (a.y * b.z) - (a.z * b.y),
    y: (a.z * b.x) - (a.x * b.z),
    z: (a.x * b.y) - (a.y * b.x)
  }
  output r : Vec3
}

pure contract Norm {
  input v : Vec3
  compute d2 : Float = (v.x * v.x) + (v.y * v.y) + (v.z * v.z)
  compute n : Float = sqrt(d2)
  output n : Float
}

pure contract DetNorm {
  input v : Vec3
  compute d2 : Float = (v.x * v.x) + (v.y * v.y) + (v.z * v.z)
  compute n : Float = det_sqrt(d2)
  output n : Float
}

pure contract Distance {
  input a : Vec3
  input b : Vec3
  compute dx : Float = a.x - b.x
  compute dy : Float = a.y - b.y
  compute dz : Float = a.z - b.z
  compute d2 : Float = (dx * dx) + (dy * dy) + (dz * dz)
  compute n : Float = sqrt(d2)
  output n : Float
}
