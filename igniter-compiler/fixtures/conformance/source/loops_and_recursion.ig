-- Canon-aligned conformance fixture (PROP-039 gates 3/4/5, updated 2026-06-07)
-- Canon grammar sources:
--   gate 3 (parser):     loop Name item in source max_steps: N
--                        recursive contract { ... decreases variant }
--                        fuel_bounded contract { ... max_steps N }
--   gate 4 (typechecker): OOF-L1 (source not Collection[T]), OOF-R2/R4
--   gate 5 (semanticir):  loop_node termination evidence
--
-- Delta closed:
--   [D1] loop item variable added (was: loop Name in source, now: loop Name item in source)
--   [D2] Array[Integer] → Collection[Integer] (canon source type for FiniteLoop/BudgetedLocalLoop)
--   [D3] def factorial(...) -> Integer [LAB form] replaced with recursive contract [CANON form]
--
-- Remaining conformance gaps (Rust compiler update required):
--   [G1] Rust compiler does not yet accept canon loop item-variable syntax
--   [G2] Rust compiler does not yet accept recursive/fuel_bounded contract modifier
--   [G3] Service loop (clock.every) moved to PROP-037 section below (boundary separation)

module Lang.Examples.LoopsAndRecursion

-- ── PROP-039: BudgetedLocalLoop ───────────────────────────────────────────────
-- Canon: loop Name item in source max_steps: N { body }
-- item variable is explicit; inside the body, use `lead` to reference the current element.
-- verify_loops.rb note: sum of [10,20,30,40] = 100 (Rust runtime update needed for canon syntax)

contract LoopTester {
  input pending_leads: Collection[Integer]

  compute sum = 0

  loop ProcessLeads lead in pending_leads max_steps: 100 {
    compute sum = sum + lead
  }

  output sum: Integer
}

-- ── PROP-039: FuelBoundedRecursion ────────────────────────────────────────────
-- Canon: fuel_bounded contract Name { ... max_steps N }
-- Previous lab form: def factorial(n: Integer, acc: Integer) -> Integer decreases fuel { ... }
-- Canon replaces direct self-call with recur() primitive; function-style def is not canon.
-- Body (recur() call) is body-semantics work — deferred beyond gate 5.

fuel_bounded contract Factorial {
  input n: Integer
  input acc: Integer
  compute result = acc
  output result: Integer
  max_steps 100
}

-- ── PROP-039: StructuralRecursion ─────────────────────────────────────────────
-- Canon: recursive contract Name { ... decreases variant }

recursive contract SumList {
  input items: Collection[Integer]
  input acc: Integer
  compute total = acc
  output total: Integer
  decreases items.remaining
}

-- ── PROP-037 territory: ServiceLoop ──────────────────────────────────────────
-- clock.every is a ProgressionSource (PROP-037), not a PROP-039 local loop source.
-- This form does NOT belong in a PROP-039 conformance fixture.
-- Kept here as a boundary marker; to be moved to a separate PROP-037 fixture
-- when PROP-037 conformance work begins.
--
-- LAB FORM (non-canon, PROP-037 territory):
--   loop tick in clock.every(5.seconds) { compute tick_time = tick.time }
-- Canon boundary: clock.every → ProgressionSource; tick.time → PROP-037 event-time binding.
-- See: PROP-037, igniter-lab/.agents/two-track-model.md §Current Delta
