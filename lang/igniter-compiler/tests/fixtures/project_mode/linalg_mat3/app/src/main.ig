module App.Main
import Linalg.Vec3.{ Vec3 }
import Linalg.Mat3.{ Mat3 }

-- Consumer proof: imports the Vec3 and Mat3 types from the linalg package and exercises the Mat3 op
-- contracts via call_contract through the real workspace resolver. One entry contract per proof.

pure contract IdentityProof {
  compute m : Mat3 = call_contract("Mat3Identity")
  output m : Mat3
}

-- identity * v = v
pure contract IdentityMulVecProof {
  input v : Vec3
  compute id : Mat3 = call_contract("Mat3Identity")
  compute r : Vec3 = call_contract("Mat3MulVec3", id, v)
  output r : Vec3
}

-- transpose(transpose(m)) = m
pure contract TransposeTwiceProof {
  input m : Mat3
  compute t1 : Mat3 = call_contract("Mat3Transpose", m)
  compute t2 : Mat3 = call_contract("Mat3Transpose", t1)
  output t2 : Mat3
}

-- single transpose, known value
pure contract TransposeProof {
  input m : Mat3
  compute r : Mat3 = call_contract("Mat3Transpose", m)
  output r : Mat3
}

pure contract AddProof {
  input a : Mat3
  input b : Mat3
  compute r : Mat3 = call_contract("Mat3Add", a, b)
  output r : Mat3
}

pure contract ScaleProof {
  input m : Mat3
  input k : Float
  compute r : Mat3 = call_contract("Mat3Scale", m, k)
  output r : Mat3
}

-- known matrix-vector multiplication
pure contract MatVecProof {
  input m : Mat3
  input v : Vec3
  compute r : Vec3 = call_contract("Mat3MulVec3", m, v)
  output r : Vec3
}

-- known matrix-matrix product
pure contract MatMulProof {
  input a : Mat3
  input b : Mat3
  compute r : Mat3 = call_contract("Mat3Mul", a, b)
  output r : Mat3
}

-- rotation helper, then apply to a vector: rot(90deg) applied to (1,0,0) = (0,1,0)
pure contract RotationApplyProof {
  input cos_t : Float
  input sin_t : Float
  input v : Vec3
  compute rot : Mat3 = call_contract("Mat3MakeRotationZ", cos_t, sin_t)
  compute r : Vec3 = call_contract("Mat3MulVec3", rot, v)
  output r : Vec3
}
