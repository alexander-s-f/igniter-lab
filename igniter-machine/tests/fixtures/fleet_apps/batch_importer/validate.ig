module BatchImporterValidate
import BatchImporterTypes
import stdlib.collection.{ map, filter_map, count }

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

-- ── Partition counts (typed extraction) ─────────────────────
-- BI-P01 RESOLVED: filter_map extracts `Collection[ImportRecord]` from the
-- Valid arm while dropping Invalid rows via none().
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
  compute valid_records : Collection[ImportRecord] = filter_map(results, r -> match r {
    Valid { record } => some(record)
    Invalid { } => none()
  })
  compute n = count(valid_records)
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
