-- LAB-FUNCTION-RECURSION-P3 / Reference Fixture
-- Three-way mutual recursion: A → B → C → A
-- Under per-SCC rule: all three members must have `decreases fuel`.
-- Under current self-only rule: NONE are flagged (none call themselves).
-- This is the Case 5 / three-node SCC case.
--
-- Per-SCC REJECT cases (proof-local):
--   No annotations     → three OOF-L4 diagnostics
--   Only A annotated   → two OOF-L4 diagnostics (B, C missing)
--   A and B annotated  → one OOF-L4 diagnostic (C missing)
-- Per-SCC ACCEPT case:
--   All three annotated → accepted

module Lab.FunctionRecursion.P3.ThreeWayMutual

-- Reference: no annotations (should be rejected under per-SCC)
def step_a(n: Float) -> Float {
  step_b(n)
}

def step_b(n: Float) -> Float {
  step_c(n)
}

def step_c(n: Float) -> Float {
  step_a(n)
}
