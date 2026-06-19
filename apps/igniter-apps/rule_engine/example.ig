module RuleEngineExample
import RuleEngineTypes
import RuleEngineRules
import RuleEngineCore

contract RunRuleEngine {
  -- We define our Rule Pipeline
  compute rule_pipeline = [
    "HighValueRule",
    "ForeignCurrencyRule",
    "FraudScoreRule"
  ]

  -- Clean transaction
  compute tx1 = {
    id: 1,
    amount: 5000,
    currency: "USD",
    status: "NEW",
    fraud_score: 10
  }

  -- Suspicious transaction (High value + Foreign currency)
  compute tx2 = {
    id: 2,
    amount: 15000,
    currency: "EUR",
    status: "NEW",
    fraud_score: 50
  }

  -- Fraudulent transaction
  compute tx3 = {
    id: 3,
    amount: 100,
    currency: "USD",
    status: "NEW",
    fraud_score: 95
  }

  compute res1 = call_contract("ExecuteRules", tx1, rule_pipeline)
  compute res2 = call_contract("ExecuteRules", tx2, rule_pipeline)
  compute res3 = call_contract("ExecuteRules", tx3, rule_pipeline)

  output res1 : Collection[RuleDecision]
  output res2 : Collection[RuleDecision]
  output res3 : Collection[RuleDecision]
}
