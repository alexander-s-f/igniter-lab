module VectorMathMat3
import VectorMathTypes

-- ============================================================
-- Mat3 Operations (3×3 Matrix)
-- ============================================================
-- Matrix stored as 3 row Vec3s.
-- All arithmetic uses milli-unit Integer convention.
-- ============================================================

contract Mat3Identity {
  -- VM-P10: inner Vec3 row literals extracted as annotated computes to give Ruby TC an
  -- unambiguous Vec3 hint, preventing the nested hint-propagation bug (r0/r1/r2 ← Mat3).
  compute r0 : Vec3 = { x: 1000, y: 0, z: 0 }
  compute r1 : Vec3 = { x: 0, y: 1000, z: 0 }
  compute r2 : Vec3 = { x: 0, y: 0, z: 1000 }
  compute result = { r0: r0, r1: r1, r2: r2 }

  output result : Mat3
}

contract Mat3Transpose {
  input m : Mat3

  compute r0 : Vec3 = { x: m.r0.x, y: m.r1.x, z: m.r2.x }
  compute r1 : Vec3 = { x: m.r0.y, y: m.r1.y, z: m.r2.y }
  compute r2 : Vec3 = { x: m.r0.z, y: m.r1.z, z: m.r2.z }
  compute result = { r0: r0, r1: r1, r2: r2 }

  output result : Mat3
}

contract Mat3MulVec3 {
  input m : Mat3
  input v : Vec3

  -- Matrix × Vector: each row dot v
  compute result = {
    x: (m.r0.x * v.x + m.r0.y * v.y + m.r0.z * v.z) / 1000,
    y: (m.r1.x * v.x + m.r1.y * v.y + m.r1.z * v.z) / 1000,
    z: (m.r2.x * v.x + m.r2.y * v.y + m.r2.z * v.z) / 1000
  }

  output result : Vec3
}

contract Mat3Add {
  input a : Mat3
  input b : Mat3

  compute r0 : Vec3 = { x: a.r0.x + b.r0.x, y: a.r0.y + b.r0.y, z: a.r0.z + b.r0.z }
  compute r1 : Vec3 = { x: a.r1.x + b.r1.x, y: a.r1.y + b.r1.y, z: a.r1.z + b.r1.z }
  compute r2 : Vec3 = { x: a.r2.x + b.r2.x, y: a.r2.y + b.r2.y, z: a.r2.z + b.r2.z }
  compute result = { r0: r0, r1: r1, r2: r2 }

  output result : Mat3
}

contract Mat3Scale {
  input m : Mat3
  input scalar : Integer

  compute r0 : Vec3 = { x: (m.r0.x * scalar) / 1000, y: (m.r0.y * scalar) / 1000, z: (m.r0.z * scalar) / 1000 }
  compute r1 : Vec3 = { x: (m.r1.x * scalar) / 1000, y: (m.r1.y * scalar) / 1000, z: (m.r1.z * scalar) / 1000 }
  compute r2 : Vec3 = { x: (m.r2.x * scalar) / 1000, y: (m.r2.y * scalar) / 1000, z: (m.r2.z * scalar) / 1000 }
  compute result = { r0: r0, r1: r1, r2: r2 }

  output result : Mat3
}

contract Mat3Determinant {
  input m : Mat3

  -- det = r0.x*(r1.y*r2.z - r1.z*r2.y) - r0.y*(r1.x*r2.z - r1.z*r2.x) + r0.z*(r1.x*r2.y - r1.y*r2.x)
  compute cofactor_a = (m.r1.y * m.r2.z - m.r1.z * m.r2.y) / 1000
  compute cofactor_b = (m.r1.x * m.r2.z - m.r1.z * m.r2.x) / 1000
  compute cofactor_c = (m.r1.x * m.r2.y - m.r1.y * m.r2.x) / 1000

  compute value = (m.r0.x * cofactor_a - m.r0.y * cofactor_b + m.r0.z * cofactor_c) / 1000

  output value : Integer
}

contract MakeRotation2D {
  input cos_val : Integer
  input sin_val : Integer

  -- 2D rotation matrix embedded in 3x3 (Z-axis rotation)
  -- cos/sin are in milli-units: cos(45°) ≈ 707, sin(45°) ≈ 707
  compute r0 : Vec3 = { x: cos_val, y: 0 - sin_val, z: 0 }
  compute r1 : Vec3 = { x: sin_val, y: cos_val, z: 0 }
  compute r2 : Vec3 = { x: 0, y: 0, z: 1000 }
  compute result = { r0: r0, r1: r1, r2: r2 }

  output result : Mat3
}

contract MakeScale3D {
  input sx : Integer
  input sy : Integer
  input sz : Integer

  compute r0 : Vec3 = { x: sx, y: 0, z: 0 }
  compute r1 : Vec3 = { x: 0, y: sy, z: 0 }
  compute r2 : Vec3 = { x: 0, y: 0, z: sz }
  compute result = { r0: r0, r1: r1, r2: r2 }

  output result : Mat3
}
