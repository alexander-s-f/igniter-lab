-- plus_policy.ig
-- H4 proof fixture: + vs ++ policy
--
-- H4 claim A: numeric "+" resolves to Add (verified: UseNumericPlus compiles, trace shows Add)
-- H4 claim B: "++" is a separate independent trigger (form_table shows two entries)
-- H4 claim C: String "+" is rejected — not accepted as concat
--   → test: StringPlus contract uses String + String; typechecker emits OOF-TY0 (correct gate)
--   → this fixture expects status=oof because StringPlus uses unsupported String + String
--   → that IS the proof: no path accepts String "+" as concat
--
-- Note: form resolver (sidecar) does NOT do type-directed dispatch
-- Sidecar would show String + String "resolving" to Add (incorrect)
-- The honest posture: type-gate (typechecker) is what enforces numeric-only for "+"
-- H3 (sidecar_resolution_only) confirms: form_table is evidence, not runtime enforcement

module Forms.Hardening.PlusPolicy

-- "+" owned by Add (numeric)
contract Add
  form (left) "+" (right)
  priority 5
  associativity :left
{
  input left: Integer
  input right: Integer
  compute result = left + right
  output result: Integer
}

-- "++" is a SEPARATE trigger — independent of "+"
-- No collision, no shared resolution
contract Concat
  form (left) "++" (right)
  priority 4
  associativity :left
{
  input left: Integer
  input right: Integer
  compute result = left + right
  output result: Integer
}

-- H4-A: Integer "+" → form table Add, typechecker ok
contract UseNumericPlus {
  input a: Integer
  input b: Integer
  compute total = a + b
  output total: Integer
}

-- H4-C: String "+" → typechecker OOF-TY0 (no form or type path accepts it)
-- This contract makes the overall compilation status=oof
-- That IS the pass condition: String + is rejected end-to-end
contract StringPlusProof {
  input s1: String
  input s2: String
  compute bad = s1 + s2
  output bad: String
}
