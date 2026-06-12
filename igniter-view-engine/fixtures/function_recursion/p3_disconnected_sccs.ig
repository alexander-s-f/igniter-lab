-- LAB-FUNCTION-RECURSION-P3 / Reference Fixture
-- Two disconnected mutual SCCs in the same module.
-- SCC1: {alpha, beta}  — alpha ↔ beta
-- SCC2: {gamma, delta} — gamma ↔ delta
-- Helper: epsilon — called by both SCCs but not recursive
--
-- Under per-SCC rule:
--   All four SCC members need `decreases fuel`
--   epsilon needs nothing (SCC = {epsilon}, kind :none)

module Lab.FunctionRecursion.P3.DisconnectedSCCs

def alpha(n: Float) -> Float {
  beta(n)
}

def beta(n: Float) -> Float {
  alpha(n)
}

def gamma(n: Float) -> Float {
  delta(n)
}

def delta(n: Float) -> Float {
  gamma(n)
}

-- Non-recursive helper called by both cycles.
-- Should NOT require decreases fuel under per-SCC rule.
def epsilon(n: Float) -> Float {
  n
}
