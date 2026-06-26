-- LAB-IGNITER-DATA-PROJECTION-DECIMAL-CROSSING-P23 fixture — exact typed Decimal[N] row crossing.
--
-- A host `numeric(p,s)` column crosses as an EXACT `.ig Decimal[2]` (not a String): the adapter reads the
-- lossless decimal digits as a String, the host materializer parses them against the declared scale into the
-- `{value, scale}` shape the VM's `from_json` turns into `Value::Decimal`. The continuation then does REAL
-- Decimal work — `to_text(r.amount)` (exact, trailing zeroes) and a `fold`-sum — proving the values are real
-- Decimals, not Strings. No Float, no in-`.ig` decimal parsing. No capability id / scope / DSN / SQL.
module DecimalCrossing

import IgWebPrelude

type QueryFilter {
  field : String
  op    : String
  value : String
}

type QueryPlan {
  source     : String
  op         : String
  projection : Collection[String]
  filters    : Collection[QueryFilter]
  limit      : Integer
}

-- The app row type: `amount` is an EXACT `Decimal[2]` (scale must match the host policy's `Decimal{scale:2}`).
type LineRow {
  label  : String
  amount : Decimal[2]
}

type DatasetMeta {
  source    : String
  count     : Integer
  truncated : Bool
}

-- A custom proof record so the harness can assert each typed dimension directly.
type DecimalProof {
  n          : Integer
  total_text : String
  joined     : String
}

-- Query intent: list the lines (projection names the typed columns the continuation will access).
pure contract ListLines {
  input source : String
  compute projection : Collection[String] = ["label", "amount"]
  compute filters : Collection[QueryFilter] = []
  compute plan : QueryPlan = {
    source: source, op: "select",
    projection: projection, filters: filters, limit: 50
  }
  output plan : QueryPlan
}

-- The typed continuation: REAL Decimal arithmetic + rendering over the crossed rows.
--   - `to_text(r.amount)` only TYPECHECKS if `amount` is a Decimal/Integer (a String would be rejected) —
--     so the fact this compiles + renders "12.50" proves the value crossed as a real Decimal.
--   - the `fold`-sum (`acc + r.amount`, seeded `decimal(0,2)`) sums EXACTLY — a String could not be added.
pure contract DecimalProbe {
  input req  : Request
  input rows : Collection[LineRow]
  input meta : DatasetMeta
  compute n : Integer = count(rows)
  compute total : Decimal[2] = fold(rows, decimal(0, 2), (acc, r) -> acc + r.amount)
  compute total_text : String = to_text(total)
  compute joined : String = fold(rows, "", (acc, r) -> concat(acc, concat(to_text(r.amount), "|")))
  compute proof : DecimalProof = { n: n, total_text: total_text, joined: joined }
  output proof : DecimalProof
}
