module Lab.TypedRef.Basic

-- Validator: a pure callee with a well-defined signature.
-- In typed-ref model this is the named target of a ContractRef.
pure contract Validator {
  input amount : Integer
  compute is_valid = amount > 0
  output is_valid : Bool
}

-- Processor: references Validator via the current stringly call_contract pattern.
-- The typed-ref model would express this as an explicit, static dependency edge:
--   uses Validator  =>  ContractRef { module: "Lab.TypedRef.Basic", name: "Validator" }
-- The SemanticIR already carries the data needed to build that ref.
pure contract Processor {
  input amount : Integer
  compute valid = call_contract("Validator", amount)
  output valid : Bool
}
