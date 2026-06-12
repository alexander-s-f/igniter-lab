module RuleEngineRules
import RuleEngineTypes

-- ============================================================
-- The Rules
-- ============================================================
-- Every rule is a pure contract taking a Transaction and
-- returning a RuleDecision.

contract HighValueRule {
  input t : Transaction

  compute decision = if t.amount > 10000 {
    { rule_name: "HighValueRule", action: "FLAG", reason: "Amount > 10000" }
  } else {
    { rule_name: "HighValueRule", action: "SKIP", reason: "Amount OK" }
  }

  output decision : RuleDecision
}

contract ForeignCurrencyRule {
  input t : Transaction

  compute decision = if t.currency == "USD" {
    { rule_name: "ForeignCurrencyRule", action: "SKIP", reason: "Local currency" }
  } else {
    { rule_name: "ForeignCurrencyRule", action: "FLAG", reason: "Foreign currency" }
  }

  output decision : RuleDecision
}

contract FraudScoreRule {
  input t : Transaction

  compute decision = if t.fraud_score > 90 {
    { rule_name: "FraudScoreRule", action: "REJECT", reason: "High fraud score" }
  } else {
    { rule_name: "FraudScoreRule", action: "SKIP", reason: "Score OK" }
  }

  output decision : RuleDecision
}
