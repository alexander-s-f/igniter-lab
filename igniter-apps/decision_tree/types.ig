module DecisionTreeTypes

-- ============================================================
-- Decision Tree Library — Arena-Based Tree Model
-- ============================================================
-- Since Igniter has no recursive types or ADTs, we use the
-- flat Arena pattern (proven in the parser app).
-- Every node lives in a Collection[TreeNode] and references
-- children by String ID.
-- ============================================================

-- A single feature value for classification input
type FeatureEntry {
  name : String
  value : Integer
}

-- A row of input data: a collection of named feature values
type DataRow {
  id : String
  features : Collection[FeatureEntry]
}

-- A single node in the decision tree arena
type TreeNode {
  id : String
  kind : String
  -- kind = "decision" | "leaf"

  -- Decision fields (used when kind == "decision")
  feature_name : String?
  threshold : Integer?
  left_id : String?
  right_id : String?

  -- Leaf fields (used when kind == "leaf")
  label : String?
  confidence : Integer?
}

-- The full decision tree: a flat arena + the root pointer
type DecisionTree {
  root_id : String
  nodes : Collection[TreeNode]
}

-- Result of evaluating a single data row against the tree
type Prediction {
  row_id : String
  label : String
  confidence : Integer
  path_ids : Collection[String]
}
