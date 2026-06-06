-- unresolved_check.ig
-- Proof fixture: P8 — unresolved operator/form fails closed
-- An operator used in a body that has NO form registered
-- Should produce "miss" trace events (fail-silent for primitives)
-- No crash, no invalid state — language primitives pass through

module Forms.UnresolvedCheck

-- No form declared for any operator in this module
contract NoForms {
  input a: Integer
  input b: Integer
  -- These operators have no form registration:
  -- "+" → miss (not in form registry)
  -- "-" → miss
  -- "*" → miss
  -- ">" → miss
  compute sum   = a + b
  compute diff  = a - b
  compute prod  = a * b
  compute check = a > b
  output sum: Integer
}

-- P8 proof: all operators produce "miss" trace events
-- Compilation succeeds (miss = not a form trigger, not an error)
-- No diagnostic produced for language primitives (correct behavior)
-- "Fail closed" = no crash, deterministic miss output, no silent wrong resolution
