module DecisionTreeExample
import DecisionTreeTypes
import DecisionTreeBuilder
import DecisionTreeEvaluator
import stdlib.collection.{ append }

-- ============================================================
-- Example: Loan Approval Decision Tree
-- ============================================================
-- A simple credit-scoring tree:
--
--              [income > 50000?]
--              /              \
--      [credit > 700?]      REJECT (conf=95)
--       /          \
--   APPROVE       REJECT
--   (conf=90)     (conf=80)
-- ============================================================

contract BuildLoanTree {
  -- Step 1: Create leaf nodes
  compute leaf_approve = call_contract("MakeLeaf", "leaf-approve", "APPROVE", 90)
  compute leaf_reject_credit = call_contract("MakeLeaf", "leaf-reject-credit", "REJECT", 80)
  compute leaf_reject_income = call_contract("MakeLeaf", "leaf-reject-income", "REJECT", 95)

  -- Step 2: Create decision nodes
  compute decision_credit = call_contract("MakeDecision", "dec-credit", "credit_score", 700, "leaf-approve", "leaf-reject-credit")
  compute decision_income = call_contract("MakeDecision", "dec-income", "income", 50000, "dec-credit", "leaf-reject-income")

  -- Step 3: Assemble the tree arena
  -- Start with a single-node tree, then add remaining nodes
  compute nodes_0 = call_contract("append", decision_income, decision_credit)
  compute tree_init = {
    root_id: "dec-income",
    nodes: nodes_0
  }

  compute tree_1 = call_contract("AddNode", tree_init, leaf_approve)
  compute tree_2 = call_contract("AddNode", tree_1, leaf_reject_credit)
  compute tree_3 = call_contract("AddNode", tree_2, leaf_reject_income)

  output tree_3 : DecisionTree
}

contract RunLoanExample {
  -- Build the tree
  compute loan_tree = call_contract("BuildLoanTree")

  -- Create sample applicants
  compute feat_income_high = { name: "income", value: 75000 }
  compute feat_credit_good = { name: "credit_score", value: 750 }
  compute feat_income_low = { name: "income", value: 30000 }
  compute feat_credit_bad = { name: "credit_score", value: 580 }

  -- Build feature collections by appending
  compute features_good = call_contract("append", feat_income_high, feat_credit_good)
  compute features_bad = call_contract("append", feat_income_low, feat_credit_bad)

  compute applicant_good = {
    id: "applicant-001",
    features: features_good
  }

  compute applicant_bad = {
    id: "applicant-002",
    features: features_bad
  }

  -- Evaluate both applicants against the tree
  compute result_good = call_contract("Evaluate", loan_tree, applicant_good)
  compute result_bad = call_contract("Evaluate", loan_tree, applicant_bad)

  output result_good : Prediction
  output result_bad : Prediction
}
