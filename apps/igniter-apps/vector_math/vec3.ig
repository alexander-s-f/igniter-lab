module VectorMathVec3
import VectorMathTypes

-- ============================================================
-- Vec3 Operations
-- ============================================================

contract Vec3Add {
  input a : Vec3
  input b : Vec3

  compute result = {
    x: a.x + b.x,
    y: a.y + b.y,
    z: a.z + b.z
  }

  output result : Vec3
}

contract Vec3Sub {
  input a : Vec3
  input b : Vec3

  compute result = {
    x: a.x - b.x,
    y: a.y - b.y,
    z: a.z - b.z
  }

  output result : Vec3
}

contract Vec3Scale {
  input v : Vec3
  input scalar : Integer

  compute result = {
    x: (v.x * scalar) / 1000,
    y: (v.y * scalar) / 1000,
    z: (v.z * scalar) / 1000
  }

  output result : Vec3
}

contract Vec3Negate {
  input v : Vec3

  compute result = {
    x: 0 - v.x,
    y: 0 - v.y,
    z: 0 - v.z
  }

  output result : Vec3
}

contract Vec3Dot {
  input a : Vec3
  input b : Vec3

  compute value = (a.x * b.x + a.y * b.y + a.z * b.z) / 1000

  output value : Integer
}

contract Vec3Cross {
  input a : Vec3
  input b : Vec3

  -- Cross product: a × b
  compute result = {
    x: (a.y * b.z - a.z * b.y) / 1000,
    y: (a.z * b.x - a.x * b.z) / 1000,
    z: (a.x * b.y - a.y * b.x) / 1000
  }

  output result : Vec3
}

contract Vec3LengthSq {
  input v : Vec3

  compute value = (v.x * v.x + v.y * v.y + v.z * v.z) / 1000

  output value : Integer
}

contract Vec3Lerp {
  input a : Vec3
  input b : Vec3
  input t : Integer

  compute result = {
    x: a.x + ((b.x - a.x) * t) / 1000,
    y: a.y + ((b.y - a.y) * t) / 1000,
    z: a.z + ((b.z - a.z) * t) / 1000
  }

  output result : Vec3
}

contract Vec3Reflect {
  input incident : Vec3
  input normal : Vec3

  -- reflect = incident - 2 * dot(incident, normal) * normal
  compute d = (incident.x * normal.x + incident.y * normal.y + incident.z * normal.z) / 1000
  compute two_d = 2 * d

  compute result = {
    x: incident.x - (two_d * normal.x) / 1000,
    y: incident.y - (two_d * normal.y) / 1000,
    z: incident.z - (two_d * normal.z) / 1000
  }

  output result : Vec3
}

contract Vec3ComponentMin {
  input a : Vec3
  input b : Vec3

  compute result = {
    x: if a.x < b.x { a.x } else { b.x },
    y: if a.y < b.y { a.y } else { b.y },
    z: if a.z < b.z { a.z } else { b.z }
  }

  output result : Vec3
}

contract Vec3ComponentMax {
  input a : Vec3
  input b : Vec3

  compute result = {
    x: if a.x > b.x { a.x } else { b.x },
    y: if a.y > b.y { a.y } else { b.y },
    z: if a.z > b.z { a.z } else { b.z }
  }

  output result : Vec3
}
