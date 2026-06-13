module DecisionTreeBuilder
import DecisionTreeTypes
import stdlib.collection.{ append }

-- ============================================================
-- Tree Construction Contracts
-- ============================================================

contract MakeLeaf {
  input id : String
  input label : String
  input confidence : Integer

  compute node = {
    id: id,
    kind: "leaf",
    feature_name: "",
    threshold: 0,
    left_id: "",
    right_id: "",
    label: label,
    confidence: confidence
  }

  output node : TreeNode
}

contract MakeDecision {
  input id : String
  input feature_name : String
  input threshold : Integer
  input left_id : String
  input right_id : String

  compute node = {
    id: id,
    kind: "decision",
    feature_name: feature_name,
    threshold: threshold,
    left_id: left_id,
    right_id: right_id,
    label: "",
    confidence: 0
  }

  output node : TreeNode
}

contract AddNode {
  input tree : DecisionTree
  input node : TreeNode

  compute new_nodes = append(tree.nodes, node)

  compute updated_tree = {
    root_id: tree.root_id,
    nodes: new_nodes
  }

  output updated_tree : DecisionTree
}
