module VectorMathExample
import VectorMathTypes
import VectorMathVec2
import VectorMathVec3
import VectorMathMat3
import VectorMathGeometry

-- ============================================================
-- Example: Physics Simulation Frame
-- ============================================================

contract SimulateFrame {
  compute position = { x: 5000, y: 10000, z: 3000 }
  compute velocity = { x: 100, y: 0, z: 0 - 200 }
  compute gravity = { x: 0, y: 0 - 9810, z: 0 }

  compute gravity_impulse = call_contract("Vec3Scale", gravity, 16)
  compute new_velocity = call_contract("Vec3Add", velocity, gravity_impulse)

  compute displacement = call_contract("Vec3Scale", new_velocity, 16)
  compute new_position = call_contract("Vec3Add", position, displacement)

  compute surface_normal = { x: 0, y: 1000, z: 0 }
  compute reflected_vel = call_contract("Vec3Reflect", new_velocity, surface_normal)

  compute world_min = { x: 0, y: 0, z: 0 }
  compute world_max = { x: 20000, y: 20000, z: 20000 }
  compute world_bounds = call_contract("MakeAABB", world_min, world_max)
  compute in_bounds = call_contract("AABBContains", world_bounds, new_position)

  output new_position : Vec3
  output new_velocity : Vec3
  output reflected_vel : Vec3
  output in_bounds : Bool
}

-- ============================================================
-- Example: Matrix Transform Pipeline
-- ============================================================

contract TransformExample {
  compute point = { x: 1000, y: 0, z: 0 }

  compute rot_45 = call_contract("MakeRotation2D", 707, 707)
  compute rotated = call_contract("Mat3MulVec3", rot_45, point)

  compute scale_2x = call_contract("MakeScale3D", 2000, 2000, 2000)
  compute scaled = call_contract("Mat3MulVec3", scale_2x, rotated)

  compute det = call_contract("Mat3Determinant", rot_45)

  output rotated : Vec3
  output scaled : Vec3
  output det : Integer
}

-- ============================================================
-- Example: Vec2 Triangle Geometry
-- ============================================================

contract Vec2Example {
  compute a = { x: 0, y: 0 }
  compute b = { x: 3000, y: 0 }
  compute c = { x: 1500, y: 2000 }

  compute ab = call_contract("Vec2Sub", b, a)
  compute ac = call_contract("Vec2Sub", c, a)
  compute cross_val = call_contract("Vec2Cross", ab, ac)

  compute triangle_area = if cross_val > 0 {
    cross_val / 2
  } else {
    (0 - cross_val) / 2
  }

  compute mid_ab = call_contract("Vec2Lerp", a, b, 500)
  compute perp_ab = call_contract("Vec2Perp", ab)
  compute ortho_check = call_contract("Vec2Dot", ab, perp_ab)

  output triangle_area : Integer
  output mid_ab : Vec2
  output perp_ab : Vec2
  output ortho_check : Integer
}

-- ============================================================
-- Example: AABB Collision Detection
-- ============================================================

contract CollisionExample {
  compute a_min = { x: 0, y: 0, z: 0 }
  compute a_max = { x: 5000, y: 5000, z: 5000 }
  compute b_min = { x: 3000, y: 3000, z: 3000 }
  compute b_max = { x: 8000, y: 8000, z: 8000 }
  compute c_min = { x: 6000, y: 6000, z: 6000 }
  compute c_max = { x: 9000, y: 9000, z: 9000 }

  compute box_a = call_contract("MakeAABB", a_min, a_max)
  compute box_b = call_contract("MakeAABB", b_min, b_max)
  compute box_c = call_contract("MakeAABB", c_min, c_max)

  compute ab_overlap = call_contract("AABBOverlaps", box_a, box_b)
  compute ac_overlap = call_contract("AABBOverlaps", box_a, box_c)

  compute center_a = call_contract("MidPoint", a_min, a_max)
  compute center_b = call_contract("MidPoint", b_min, b_max)
  compute dist_sq = call_contract("DistanceSq", center_a, center_b)

  output ab_overlap : Bool
  output ac_overlap : Bool
  output dist_sq : Integer
}
