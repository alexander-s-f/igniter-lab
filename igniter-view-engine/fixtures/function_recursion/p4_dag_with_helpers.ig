-- LAB-FUNCTION-RECURSION-P4 / Fixture
-- A DAG of non-recursive functions with one recursive root.
-- Only `compute` is self-recursive; `format`, `validate`, `lookup` are helpers.
-- Expected: OOF-L4 on `compute` only. Helpers have no cycle, no OOF-L4.

module Lab.FunctionRecursion.P4.DagWithHelpers

type Item { value: Float }

def lookup(key: Float) -> Item {
  { value: key }
}

def validate(item: Item) -> Float {
  item.value
}

def format(n: Float) -> Text {
  "result"
}

def compute(n: Float) -> Float decreases fuel {
  let item = lookup(n)
  let v = validate(item)
  compute(v)
}
