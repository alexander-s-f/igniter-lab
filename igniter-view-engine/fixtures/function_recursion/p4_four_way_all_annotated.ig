-- LAB-FUNCTION-RECURSION-P4 / Fixture
-- Four-function mutual cycle: a -> b -> c -> d -> a
-- All four carry decreases fuel. Expected: status ok, zero OOF-L4.

module Lab.FunctionRecursion.P4.FourWayAllAnnotated

def a(n: Float) -> Float decreases fuel {
  b(n)
}

def b(n: Float) -> Float decreases fuel {
  c(n)
}

def c(n: Float) -> Float decreases fuel {
  d(n)
}

def d(n: Float) -> Float decreases fuel {
  a(n)
}
