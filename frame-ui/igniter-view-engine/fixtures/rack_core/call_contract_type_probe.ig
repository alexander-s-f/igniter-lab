module Rack.P10.TypeProbe

-- P10 preflight probe fixture — compile and inspect SemanticIR shape only.
-- No runtime execution required; proof is structural inspection only.
-- Proves that SemanticIR carries full output-type metadata per contract,
-- that literal callee names are identifiable from the AST, and that the
-- same-module contract list is available to the TypeChecker at check time.

-- Known pure single-output callee (Integer)
pure contract Adder {
  input a : Integer
  input b : Integer
  compute result = a + b
  output result : Integer
}

-- Known pure single-output callee (Bool)
pure contract IsPositive {
  input n : Integer
  compute result = n > 0
  output result : Bool
}

-- Effect callee (non-pure — dispatch must be blocked)
effect contract SideEffect {
  input n : Integer
  compute result = n + 1
  output result : Integer
}

-- Caller that uses Adder with literal name (literal callee, correct arity)
pure contract CallerAdder {
  input x : Integer
  input y : Integer
  compute sum = call_contract("Adder", x, y)
  output sum : Integer
}

-- Caller that uses IsPositive (literal callee, Bool output)
pure contract CallerBool {
  input n : Integer
  compute flag = call_contract("IsPositive", n)
  output flag : Bool
}

-- Caller with dynamic string (non-literal callee — must remain Unknown at compile time)
pure contract CallerDynamic {
  input name : String
  input n : Integer
  compute result = call_contract(name, n)
  output result : Integer
}
