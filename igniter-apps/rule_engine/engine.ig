module RuleEngineCore
import RuleEngineTypes
import stdlib.collection.{ map, filter }

-- ============================================================
-- The Inference Engine
-- ============================================================

contract ExecuteRules {
  input t : Transaction
  input rules : Collection[String]

  -- This is the magic. The compiler allows dynamic strings in `call_contract`.
  -- Tier 2 evaluation means it compiles, sets the output type to `Unknown`,
  -- and delegates validation to the VM at runtime!
  -- Since `map` applies to each item, we execute the rule pipeline in O(N).
  compute raw_decisions = map(rules, r ->
    call_contract(r, t)
  )

  -- Now we filter out the "SKIP" actions so we only return meaningful decisions
  -- Wait, `call_contract` returns `Unknown`. We can't directly read `.action`
  -- on `Unknown` without a type cast. But wait, `Unknown` is permissive!
  -- Does Igniter allow field access on Unknown?
  -- Yes, P9/P11 rules say "Unknown is permissive". Let's test it.
  compute active_decisions = filter(raw_decisions, d ->
    if d.action == "SKIP" { false } else { true }
  )

  output active_decisions : Collection[RuleDecision]
}
