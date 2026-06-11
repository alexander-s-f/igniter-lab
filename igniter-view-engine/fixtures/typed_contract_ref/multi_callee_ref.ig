module Lab.TypedRef.Multi

-- Normalizer: returns a normalized integer value.
pure contract Normalizer {
  input value : Integer
  compute result = value + 0
  output result : Integer
}

-- Validator: returns a boolean validity signal.
pure contract Validator {
  input amount : Integer
  compute is_valid = amount > 0
  output is_valid : Bool
}

-- Composer: references BOTH Normalizer and Validator.
-- In the typed-ref model this Composer declares two ContractDependency edges,
-- one per callee — both statically resolved, both inspectable.
pure contract Composer {
  input amount : Integer
  compute normalized = call_contract("Normalizer", amount)
  compute valid     = call_contract("Validator", amount)
  output valid : Bool
}
