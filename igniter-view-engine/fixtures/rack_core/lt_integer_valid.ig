module Rack.P6.LtIntegerValid

-- LAB-RACK-P6: proves TypeChecker accepts < for Integer.
-- Proves: Integer < Integer compiles and executes on VM.
-- Closed: lab-only, no canon claim, no stable-API surface.

pure contract LtIntegerValid {
  input n : Integer

  compute is_small = n < 100

  output is_small : Bool
}
