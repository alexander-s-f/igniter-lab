-- LAB-FUNCTION-RECURSION-P4 / Fixture
-- Four-function mutual cycle: a -> b -> c -> d -> a
-- No decreases annotations. All four must receive OOF-L4.
-- Tests SCC detection for cycles longer than 3 nodes.

module Lab.FunctionRecursion.P4.FourWayCycle

def a(n: Float) -> Float {
  b(n)
}

def b(n: Float) -> Float {
  c(n)
}

def c(n: Float) -> Float {
  d(n)
}

def d(n: Float) -> Float {
  a(n)
}
