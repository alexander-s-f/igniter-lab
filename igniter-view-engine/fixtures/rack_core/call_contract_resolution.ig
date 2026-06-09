module Rack.P11.TypeCheckerResolution

-- ── Base callees ─────────────────────────────────────────────────────────────

-- Double: single-output pure callee (Integer → Integer)
-- Used by CallerDouble to prove Tier 1 literal resolution.
pure contract Double {
  input  n : Integer
  compute result = n + n
  output result : Integer
}

-- IsPositive: single-output pure callee (Bool)
-- Used by CallerBool to prove Bool callee resolution.
pure contract IsPositive {
  input  n : Integer
  compute result = n > 0
  output result : Bool
}

-- Adder: two-input pure callee (Integer)
-- Used by CallerAdder to prove multi-arg literal resolution.
pure contract Adder {
  input  a : Integer
  input  b : Integer
  compute result = a + b
  output result : Integer
}

-- ── Caller contracts (static resolution — Tier 1) ────────────────────────────

-- CallerDouble: calls Double via literal callee — should resolve to Integer.
-- With P11 the TypeChecker resolves call_contract("Double", n) → Integer.
pure contract CallerDouble {
  input  n : Integer
  compute doubled = call_contract("Double", n)
  output doubled : Integer
}

-- CallerBool: calls IsPositive via literal callee — should resolve to Bool.
pure contract CallerBool {
  input  n : Integer
  compute flag = call_contract("IsPositive", n)
  output flag : Bool
}

-- CallerAdder: calls Adder with two positional args — should resolve to Integer.
pure contract CallerAdder {
  input  a : Integer
  input  b : Integer
  compute sum = call_contract("Adder", a, b)
  output sum : Integer
}

-- ── Dynamic caller (Tier 2 — remains Unknown) ────────────────────────────────

-- CallerDynamic: calls via a variable callee name — Unknown; compiles OK.
-- First arg is a ref (not a literal) so Tier 2 path applies.
pure contract CallerDynamic {
  input  n    : Integer
  input  name : String
  compute result = call_contract(name, n)
  output result : Integer
}
