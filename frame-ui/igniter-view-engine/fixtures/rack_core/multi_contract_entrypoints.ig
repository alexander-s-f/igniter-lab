module Rack.P7.MultiContractEntrypoints

-- Contract 1 (position 0 / default): Double
-- Input: n : Integer  →  Output: result = n + n
-- Used to prove: (a) default contracts[0] selection unchanged,
--                (b) explicit --entry Double selection
pure contract Double {
  input  n : Integer
  compute result = n + n
  output result : Integer
}

-- Contract 2: IsSmall
-- Input: n : Integer  →  Output: result = n < 100
-- Uses the P6 < operator; proves second-position --entry selection
pure contract IsSmall {
  input  n : Integer
  compute result = n < 100
  output result : Bool
}

-- Contract 3: RouteGate
-- Input: method : String, path : String  →  Output: status_code : Integer
-- Uses the P6 == operator; proves third-position --entry selection
pure contract RouteGate {
  input  method : String
  input  path   : String
  compute status_code =
    if path == "/" {
      200
    } else {
      if method == "GET" { 404 } else { 405 }
    }
  output status_code : Integer
}
