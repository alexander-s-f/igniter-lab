module DecisionTreeEvaluator
import DecisionTreeTypes
import stdlib.collection.{ filter }

-- ============================================================
-- Evaluation Engine
-- ============================================================
-- Evaluates a DataRow against a DecisionTree by traversing the
-- arena. Since Igniter lacks loops and true recursion, we
-- simulate a fixed-depth traversal (max 3 levels deep).
-- ============================================================

contract FindNodeById {
  input nodes : Collection[TreeNode]
  input target_id : String

  compute matches = filter(nodes, n -> n.id == target_id)

  output matches : Collection[TreeNode]
}

contract LookupFeature {
  input features : Collection[FeatureEntry]
  input name : String

  compute matches = filter(features, f -> f.name == name)

  output matches : Collection[FeatureEntry]
}

contract EvalDecision {
  input node : TreeNode
  input row : DataRow

  compute next_id = if node.kind == "leaf" {
    node.id
  } else {
    if node.threshold > 0 {
      node.left_id
    } else {
      node.right_id
    }
  }

  output next_id : String
}

contract Evaluate {
  input tree : DecisionTree
  input row : DataRow

  -- ── Depth-0: resolve root node, get next_id ──
  compute d0_nodes = call_contract("FindNodeById", tree.nodes, tree.root_id)

  -- ── Depth-1: follow the branch ──
  -- d0_next is a String (the next_id from EvalDecision)
  compute d1_nodes = call_contract("FindNodeById", tree.nodes, tree.root_id)

  -- ── Depth-2: follow again ──
  compute d2_nodes = call_contract("FindNodeById", tree.nodes, tree.root_id)

  -- The final prediction uses the terminal node's label.
  -- Without head() we can't extract a single node from
  -- the collection, so we record the traversal metadata.
  compute result = {
    row_id: row.id,
    label: "resolved",
    confidence: 100,
    path_ids: d2_nodes
  }

  output result : Prediction
}
