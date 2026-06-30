-- Canon-aligned 2026-06-07 (PROP-039 gate 3/4/5)
-- Delta closed: added item variable (canon: loop Name item in source max_steps: N)
-- Delta closed: Array[Integer] → Collection[Integer] (canon: source must be Collection[T])
-- Conformance note: Rust compiler update needed to accept canon syntax
module W1

contract LoopContract {
  input items: Collection[Integer]

  compute total = 0

  loop Accumulate item in items max_steps: 1000 {
    compute total = total + item
  }

  output total: Integer
}
