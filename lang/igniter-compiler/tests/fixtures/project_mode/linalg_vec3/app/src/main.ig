module App.Main
import Linalg.Vec3.{ Vec3 }

-- Consumer proof: imports the Vec3 type from the linalg package and calls its op contracts via
-- call_contract through the real workspace resolver. One entry contract per operation.
pure contract AddProof {
  input a : Vec3
  input b : Vec3
  compute r : Vec3 = call_contract("Add", a, b)
  output r : Vec3
}
pure contract SubProof {
  input a : Vec3
  input b : Vec3
  compute r : Vec3 = call_contract("Sub", a, b)
  output r : Vec3
}
pure contract ScaleProof {
  input v : Vec3
  input k : Float
  compute r : Vec3 = call_contract("Scale", v, k)
  output r : Vec3
}
pure contract DotProof {
  input a : Vec3
  input b : Vec3
  compute d : Float = call_contract("Dot", a, b)
  output d : Float
}
pure contract CrossProof {
  input a : Vec3
  input b : Vec3
  compute r : Vec3 = call_contract("Cross", a, b)
  output r : Vec3
}
pure contract NormProof {
  input v : Vec3
  compute n : Float = call_contract("Norm", v)
  output n : Float
}
pure contract DetNormProof {
  input v : Vec3
  compute n : Float = call_contract("DetNorm", v)
  output n : Float
}
pure contract DistanceProof {
  input a : Vec3
  input b : Vec3
  compute n : Float = call_contract("Distance", a, b)
  output n : Float
}
