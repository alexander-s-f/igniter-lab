module BatchImporterValidate
import BatchImporterTypes
import stdlib.collection.{ map, filter, count }

-- ============================================================
-- Validation + batch summary (pure)
-- ============================================================

pure contract MakeRecord {
  input row_id : Integer
  input amount : Integer
  input email : String
  compute r = { row_id: row_id, amount: amount, email: email }
  output r : ImportRecord
}

-- ── Validate one row → RowResult (business rules, pure) ─────
-- Rules: amount must be positive; email must be present. (No String→Int parse
-- in CORE — that is the escape boundary; see BI-P02.)
pure contract ValidateRow {
  input raw : RawRow
  compute result : RowResult = if raw.amount <= 0 {
    Invalid { row_id: raw.row_id, message: "amount must be positive" }
  } else {
    if raw.email == "" {
      Invalid { row_id: raw.row_id, message: "email required" }
    } else {
      Valid { record: call_contract("MakeRecord", raw.row_id, raw.amount, raw.email) }
    }
  }
  output result : RowResult
}

-- ── Validate the whole batch ────────────────────────────────
pure contract ValidateAll {
  input rows : Collection[RawRow]
  compute results = map(rows, r -> call_contract("ValidateRow", r))
  output results : Collection[RowResult]
}

-- ── Partition counts (match-as-predicate) ───────────────────
-- PRESSURE BI-P01: we can COUNT each arm with a match predicate, but we CANNOT
-- cleanly extract `Collection[ImportRecord]` of just the Valid rows — filtering
-- a `Collection[RowResult]` keeps the element type `RowResult`, and changing it
-- to `ImportRecord` needs a partial map / Option-collect (the `.filter(Ok).map(Ok.value)`
-- the specimen wants). That extraction is the sum-type gap.
pure contract IsValid {
  input r : RowResult
  compute ok = match r {
    Valid {}   => true
    Invalid {} => false
  }
  output ok : Bool
}

pure contract CountAccepted {
  input results : Collection[RowResult]
  compute valids = filter(results, r -> call_contract("IsValid", r))
  compute n = count(valids)
  output n : Integer
}

-- ── Build the partial-success receipt ───────────────────────
pure contract BuildReceipt {
  input results : Collection[RowResult]
  compute total = count(results)
  compute accepted = call_contract("CountAccepted", results)
  compute rejected = total - accepted
  compute receipt = { total: total, accepted: accepted, rejected: rejected }
  output receipt : ImportReceipt
}
