module VectorMathGeometry
import VectorMathTypes

-- ============================================================
-- Geometric Utilities: AABB, Ray, Distance
-- ============================================================

contract MakeAABB {
  input a : Vec3
  input b : Vec3

  -- Build an axis-aligned bounding box from two corner points
  compute min_pt = {
    x: if a.x < b.x { a.x } else { b.x },
    y: if a.y < b.y { a.y } else { b.y },
    z: if a.z < b.z { a.z } else { b.z }
  }

  compute max_pt = {
    x: if a.x > b.x { a.x } else { b.x },
    y: if a.y > b.y { a.y } else { b.y },
    z: if a.z > b.z { a.z } else { b.z }
  }

  compute result = {
    min_pt: min_pt,
    max_pt: max_pt
  }

  output result : AABB
}

contract AABBContains {
  input box : AABB
  input pt : Vec3

  -- Check if point is inside the AABB
  -- Using NOT-less-than instead of >= (unsupported operator)
  compute inside_x = if pt.x < box.min_pt.x { false } else { if pt.x > box.max_pt.x { false } else { true } }
  compute inside_y = if pt.y < box.min_pt.y { false } else { if pt.y > box.max_pt.y { false } else { true } }
  compute inside_z = if pt.z < box.min_pt.z { false } else { if pt.z > box.max_pt.z { false } else { true } }

  compute contained = if inside_x { if inside_y { if inside_z { true } else { false } } else { false } } else { false }

  output contained : Bool
}

contract AABBOverlaps {
  input a : AABB
  input b : AABB

  -- Two AABBs overlap iff they overlap on all three axes
  compute sep_x = if a.max_pt.x < b.min_pt.x { true } else { if b.max_pt.x < a.min_pt.x { true } else { false } }
  compute sep_y = if a.max_pt.y < b.min_pt.y { true } else { if b.max_pt.y < a.min_pt.y { true } else { false } }
  compute sep_z = if a.max_pt.z < b.min_pt.z { true } else { if b.max_pt.z < a.min_pt.z { true } else { false } }

  -- Overlaps = NOT separated on ANY axis
  compute no_sep_x = if sep_x { false } else { true }
  compute no_sep_y = if sep_y { false } else { true }
  compute no_sep_z = if sep_z { false } else { true }

  compute overlaps = if no_sep_x { if no_sep_y { if no_sep_z { true } else { false } } else { false } } else { false }

  output overlaps : Bool
}

contract DistanceSq {
  input a : Vec3
  input b : Vec3

  -- Squared distance between two points
  compute dx = a.x - b.x
  compute dy = a.y - b.y
  compute dz = a.z - b.z

  compute value = (dx * dx + dy * dy + dz * dz) / 1000

  output value : Integer
}

contract MidPoint {
  input a : Vec3
  input b : Vec3

  compute result = {
    x: (a.x + b.x) / 2,
    y: (a.y + b.y) / 2,
    z: (a.z + b.z) / 2
  }

  output result : Vec3
}
