module QueryEngineEval
import QueryEngineTypes
import stdlib.collection.{ filter, count }

-- ============================================================
-- Filter evaluation — predicates over rows (pure)
-- ============================================================

-- Integer comparison by stringly op.
-- PRESSURE QE-P01: this if-chain over `op : String` is what a sealed
-- `FilterOp` variant + `match` would replace exhaustively.
pure contract CompareInt {
  input a : Integer
  input op : String
  input b : Integer
  compute r = if op == "eq"  { if a == b { 1 } else { 0 } } else {
    if op == "neq" { if a == b { 0 } else { 1 } } else {
      if op == "gt"  { if a > b  { 1 } else { 0 } } else {
        if op == "gte" { if a >= b { 1 } else { 0 } } else {
          if op == "lt"  { if a < b  { 1 } else { 0 } } else {
            if op == "lte" { if a <= b { 1 } else { 0 } } else { 0 }
          }
        }
      }
    }
  }
  output r : Integer
}

-- Evaluate ONE predicate against a row.
-- PRESSURE QE-P03: field access is a stringly dispatch — there is no
-- dynamic field projection (`row[pred.field]`), so every column is an
-- explicit branch. New columns mean editing this contract.
pure contract MatchPredicate {
  input row : Row
  input p : FilterPredicate
  compute m = if p.field == "age" {
    call_contract("CompareInt", row.age, p.op, p.num)
  } else {
    if p.field == "id" {
      call_contract("CompareInt", row.id, p.op, p.num)
    } else {
      if p.field == "active" {
        call_contract("CompareInt", row.active, p.op, p.num)
      } else {
        if p.field == "city" {
          if p.op == "eq" { if row.city == p.str { 1 } else { 0 } } else {
            if p.op == "neq" { if row.city == p.str { 0 } else { 1 } } else { 0 }
          }
        } else {
          0
        }
      }
    }
  }
  output m : Integer
}

-- AND-compose all predicates over a row (product of 0/1 matches).
-- PRESSURE QE-P04: this is a SCALAR fold (AND via product). A real engine
-- folds predicates AND maps rows — the nested row×predicate iteration is
-- the deeper fold/flat_map pressure.
pure contract MatchAll {
  input row : Row
  input preds : Collection[FilterPredicate]
  compute hits = fold(preds, 1, (acc, p) ->
    acc * call_contract("MatchPredicate", row, p)
  )
  output hits : Integer
}

-- Keep rows where every predicate matches.
pure contract FilterRows {
  input rows : Collection[Row]
  input preds : Collection[FilterPredicate]
  compute kept = filter(rows, row ->
    if call_contract("MatchAll", row, preds) == 1 { true } else { false }
  )
  output kept : Collection[Row]
}

pure contract CountRows {
  input rows : Collection[Row]
  compute n = count(rows)
  output n : Integer
}
