-- unresolved.ig
-- H2 proof fixture: honest classification of unresolved triggers
--
-- primitive_pass_through: "+", "-", "*", ">" — language primitives not in form registry
--   → correct behavior; typechecker handles them; form resolver classifies as primitive_pass_through
--   → NOT "fail-closed" in the security sense; policy says: primitive pass-through is intended
--
-- unresolved_trigger: ".unknown_method" — trigger not in registry, not a language primitive
--   → classified as unresolved_trigger; honest claim about what we don't know
--
-- unresolved_form_error (representable as blocked):
--   → see no_form.ig — a trigger that IS in the registry but all candidates are blocked (no_form)
--   → this is the closest to "intended form error" representable in the lab
--
-- Note: true unresolved_form_error (type mismatch without type-directed dispatch) is DEFERRED
--   → requires type-directed dispatch (TYPE FILTER step) not implemented in this proof

module Forms.Hardening.Unresolved

-- No form declarations in this module
-- All operators below are primitive_pass_through
contract PrimitiveMath {
  input a: Integer
  input b: Integer
  compute sum   = a + b
  compute diff  = a - b
  compute prod  = a * b
  compute check = a > b
  output sum: Integer
}
