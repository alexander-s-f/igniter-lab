module Rack.P3.ContractRefType

-- Lab-only gap-characterization fixture.
-- CLOSED: lab-only, gap-characterization only, no canon claim, no stable API.
--
-- Attempts to declare an input with type ContractRef[String, Integer].
-- ContractRef is NOT a currently-supported Igniter built-in parameterized type.
-- Supported: Collection[T], Map[K,V].
-- Expected: parse/typecheck gap (unknown parameterized type).
-- A PASS in LAB-RACK-P3 means the gap is precisely confirmed, not that it works.

pure contract ContractRefTest {
  input  handler : ContractRef[String, Integer]
  compute result  = 42
  output result   : Integer
}
