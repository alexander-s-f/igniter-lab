module VectorMathTypes

-- ============================================================
-- Vector Math Library — Core Types
-- ============================================================
-- All components use Integer (milli-units) since Igniter's
-- typechecker does not support Float binary operators.
-- Convention: 1000 = 1.0, 500 = 0.5, etc.
-- ============================================================

type Vec2 {
  x : Integer
  y : Integer
}

type Vec3 {
  x : Integer
  y : Integer
  z : Integer
}

type Vec4 {
  x : Integer
  y : Integer
  z : Integer
  w : Integer
}

-- 3x3 matrix stored as three row vectors
type Mat3 {
  r0 : Vec3
  r1 : Vec3
  r2 : Vec3
}

-- Result of a scalar operation (dot product, magnitude², etc.)
type ScalarResult {
  value : Integer
}

-- Ray for intersection tests
type Ray {
  origin : Vec3
  direction : Vec3
}

-- Axis-aligned bounding box
type AABB {
  min_pt : Vec3
  max_pt : Vec3
}
