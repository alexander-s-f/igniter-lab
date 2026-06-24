module Linalg.Mat3
import Linalg.Vec3.{ Vec3 }

-- LAB-STDLIB-LINALG-MAT3-P3: fixed-shape Float Mat3 over three Vec3 rows. Shape lives in the type
-- (no runtime shape checks, no dynamic dimensions). All Float, no implicit coercion — built over the
-- P2 Float Vec3 package, NOT the Integer milli-unit vector_math convention (that is a separate track).
-- Pure .ig, no VM builtins, no generic Matrix[R,C]. Inner row literals are annotated `: Vec3` computes so
-- Ruby TC gets an unambiguous row hint (mirrors the governance VM-P10 nested-hint pattern).
type Mat3 { r0 : Vec3, r1 : Vec3, r2 : Vec3 }

pure contract Mat3Identity {
  compute r0 : Vec3 = { x: 1.0, y: 0.0, z: 0.0 }
  compute r1 : Vec3 = { x: 0.0, y: 1.0, z: 0.0 }
  compute r2 : Vec3 = { x: 0.0, y: 0.0, z: 1.0 }
  compute m : Mat3 = { r0: r0, r1: r1, r2: r2 }
  output m : Mat3
}

pure contract Mat3Transpose {
  input m : Mat3
  compute r0 : Vec3 = { x: m.r0.x, y: m.r1.x, z: m.r2.x }
  compute r1 : Vec3 = { x: m.r0.y, y: m.r1.y, z: m.r2.y }
  compute r2 : Vec3 = { x: m.r0.z, y: m.r1.z, z: m.r2.z }
  compute r : Mat3 = { r0: r0, r1: r1, r2: r2 }
  output r : Mat3
}

pure contract Mat3Add {
  input a : Mat3
  input b : Mat3
  compute r0 : Vec3 = { x: a.r0.x + b.r0.x, y: a.r0.y + b.r0.y, z: a.r0.z + b.r0.z }
  compute r1 : Vec3 = { x: a.r1.x + b.r1.x, y: a.r1.y + b.r1.y, z: a.r1.z + b.r1.z }
  compute r2 : Vec3 = { x: a.r2.x + b.r2.x, y: a.r2.y + b.r2.y, z: a.r2.z + b.r2.z }
  compute r : Mat3 = { r0: r0, r1: r1, r2: r2 }
  output r : Mat3
}

pure contract Mat3Scale {
  input m : Mat3
  input k : Float
  compute r0 : Vec3 = { x: m.r0.x * k, y: m.r0.y * k, z: m.r0.z * k }
  compute r1 : Vec3 = { x: m.r1.x * k, y: m.r1.y * k, z: m.r1.z * k }
  compute r2 : Vec3 = { x: m.r2.x * k, y: m.r2.y * k, z: m.r2.z * k }
  compute r : Mat3 = { r0: r0, r1: r1, r2: r2 }
  output r : Mat3
}

pure contract Mat3MulVec3 {
  input m : Mat3
  input v : Vec3
  -- each row dotted with v (no milli-unit divide — Float arithmetic is exact-by-construction)
  compute r : Vec3 = {
    x: (m.r0.x * v.x) + (m.r0.y * v.y) + (m.r0.z * v.z),
    y: (m.r1.x * v.x) + (m.r1.y * v.y) + (m.r1.z * v.z),
    z: (m.r2.x * v.x) + (m.r2.y * v.y) + (m.r2.z * v.z)
  }
  output r : Vec3
}

pure contract Mat3Mul {
  input a : Mat3
  input b : Mat3
  -- (a · b)[i][j] = sum_k a[i][k] * b[k][j]; rows are Vec3 so b's columns are b.r{k}.{x,y,z}
  compute r0 : Vec3 = {
    x: (a.r0.x * b.r0.x) + (a.r0.y * b.r1.x) + (a.r0.z * b.r2.x),
    y: (a.r0.x * b.r0.y) + (a.r0.y * b.r1.y) + (a.r0.z * b.r2.y),
    z: (a.r0.x * b.r0.z) + (a.r0.y * b.r1.z) + (a.r0.z * b.r2.z)
  }
  compute r1 : Vec3 = {
    x: (a.r1.x * b.r0.x) + (a.r1.y * b.r1.x) + (a.r1.z * b.r2.x),
    y: (a.r1.x * b.r0.y) + (a.r1.y * b.r1.y) + (a.r1.z * b.r2.y),
    z: (a.r1.x * b.r0.z) + (a.r1.y * b.r1.z) + (a.r1.z * b.r2.z)
  }
  compute r2 : Vec3 = {
    x: (a.r2.x * b.r0.x) + (a.r2.y * b.r1.x) + (a.r2.z * b.r2.x),
    y: (a.r2.x * b.r0.y) + (a.r2.y * b.r1.y) + (a.r2.z * b.r2.y),
    z: (a.r2.x * b.r0.z) + (a.r2.y * b.r1.z) + (a.r2.z * b.r2.z)
  }
  compute r : Mat3 = { r0: r0, r1: r1, r2: r2 }
  output r : Mat3
}

pure contract Mat3MakeRotationZ {
  -- Z-axis rotation embedded in 3x3, mirroring governance MakeRotation2D but in Float and without the
  -- milli-unit scale. cos/sin are precomputed Float inputs — keeping trig OUT of the package avoids any
  -- fast-vs-det trig fork (norm/det_norm policy unchanged: the only sqrt site stays in Vec3).
  input cos_t : Float
  input sin_t : Float
  compute r0 : Vec3 = { x: cos_t, y: 0.0 - sin_t, z: 0.0 }
  compute r1 : Vec3 = { x: sin_t, y: cos_t, z: 0.0 }
  compute r2 : Vec3 = { x: 0.0, y: 0.0, z: 1.0 }
  compute r : Mat3 = { r0: r0, r1: r1, r2: r2 }
  output r : Mat3
}
