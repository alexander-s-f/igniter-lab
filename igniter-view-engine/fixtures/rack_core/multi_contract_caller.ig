module Rack.P9.UserContractDispatch

-- Base contracts (callees) ──────────────────────────────────────────────────

-- Double: n + n
-- Used to prove happy-path call_contract dispatch (Integer → Integer)
pure contract Double {
  input  n : Integer
  compute result = n + n
  output result : Integer
}

-- IsSmall: n < 100
-- Used to prove Bool-returning callee dispatch
pure contract IsSmall {
  input  n : Integer
  compute result = n < 100
  output result : Bool
}

-- GateCheck: method == "GET" → 1, else 0
-- Uses P6 == operator; two-input callee proving arity check
pure contract GateCheck {
  input  method : String
  input  path   : String
  compute gate =
    if method == "GET" {
      if path == "/" { 200 } else { 404 }
    } else {
      405
    }
  output gate : Integer
}

-- Caller contracts ─────────────────────────────────────────────────────────

-- CallerDoubler: calls Double via call_contract, adds 1 to result.
-- Proves: call_contract happy path (Integer callee)
-- n=10 → doubled=20, result=21
pure contract CallerDoubler {
  input  n : Integer
  compute doubled = call_contract("Double", n)
  compute result  = doubled + 1
  output result : Integer
}

-- CallerSmall: calls IsSmall, returns Bool result unchanged.
-- Proves: Bool-returning callee passthrough
pure contract CallerSmall {
  input  n : Integer
  compute result = call_contract("IsSmall", n)
  output result : Bool
}

-- CallerGate: calls GateCheck with two positional args.
-- Proves: multi-input callee positional mapping
pure contract CallerGate {
  input  method : String
  input  path   : String
  compute status = call_contract("GateCheck", method, path)
  output status : Integer
}

-- SelfRecurse: attempts to call itself (must fail at VM dispatch with cycle error).
-- Proves: self-recursion closed in v0
pure contract SelfRecurse {
  input  n : Integer
  compute result = call_contract("SelfRecurse", n)
  output result : Integer
}
