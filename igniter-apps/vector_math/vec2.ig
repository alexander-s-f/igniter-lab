module VectorMathVec2
import VectorMathTypes

-- ============================================================
-- Vec2 Operations
-- ============================================================

contract Vec2Add {
  input a : Vec2
  input b : Vec2

  compute result = {
    x: a.x + b.x,
    y: a.y + b.y
  }

  output result : Vec2
}

contract Vec2Sub {
  input a : Vec2
  input b : Vec2

  compute result = {
    x: a.x - b.x,
    y: a.y - b.y
  }

  output result : Vec2
}

contract Vec2Scale {
  input v : Vec2
  input scalar : Integer

  -- scalar is in milli-units: 2000 = 2.0×
  -- To keep precision: (v.x * scalar) / 1000
  compute result = {
    x: (v.x * scalar) / 1000,
    y: (v.y * scalar) / 1000
  }

  output result : Vec2
}

contract Vec2Negate {
  input v : Vec2

  compute result = {
    x: 0 - v.x,
    y: 0 - v.y
  }

  output result : Vec2
}

contract Vec2Dot {
  input a : Vec2
  input b : Vec2

  -- Dot product: a.x*b.x + a.y*b.y
  -- Result is in milli²-units, divide by 1000 to get milli-units
  compute value = (a.x * b.x + a.y * b.y) / 1000

  output value : Integer
}

contract Vec2LengthSq {
  input v : Vec2

  -- Squared magnitude avoids sqrt
  compute value = (v.x * v.x + v.y * v.y) / 1000

  output value : Integer
}

contract Vec2Perp {
  input v : Vec2

  -- Perpendicular vector (90° CCW rotation)
  compute result = {
    x: 0 - v.y,
    y: v.x
  }

  output result : Vec2
}

contract Vec2Cross {
  input a : Vec2
  input b : Vec2

  -- 2D cross product (scalar): a.x*b.y - a.y*b.x
  compute value = (a.x * b.y - a.y * b.x) / 1000

  output value : Integer
}

contract Vec2Lerp {
  input a : Vec2
  input b : Vec2
  input t : Integer

  -- Linear interpolation: a + t * (b - a)
  -- t is in milli-units: 500 = 0.5, 1000 = 1.0
  compute result = {
    x: a.x + ((b.x - a.x) * t) / 1000,
    y: a.y + ((b.y - a.y) * t) / 1000
  }

  output result : Vec2
}
