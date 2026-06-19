-- G1 conformance fixture: BudgetedLocalLoop with explicit item variable
-- Canon grammar (PROP-039 gate 3): loop Name item in source max_steps: N
-- Verifies: lab parser accepts canon `loop Name item in source` form
-- Conformance note: closes G1 (item variable in BudgetedLocalLoop)
module W1

contract LoopTester {
  input pending_leads: Collection[Integer]

  compute sum = 0

  loop ProcessLeads lead in pending_leads max_steps: 100 {
    compute sum = sum + lead
  }

  output sum: Integer
}
