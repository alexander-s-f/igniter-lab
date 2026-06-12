module RuleEngineTypes

-- ============================================================
-- Rule Engine Core Types
-- ============================================================

-- The base fact that rules will operate on.
type Transaction {
  id : Integer
  amount : Integer
  currency : String
  status : String
  fraud_score : Integer
}

-- The outcome of a rule execution.
type RuleDecision {
  rule_name : String
  action : String -- "APPROVE", "REJECT", "FLAG", "SKIP"
  reason : String
}
