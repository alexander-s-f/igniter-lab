module AuditLedgerCorrect
import AuditLedgerTypes

-- ============================================================
-- Corrections — append-only adjusting entries + was/became receipt
-- ============================================================
-- PRESSURE AL-P04: a correction never mutates the original. It appends an
-- ADJUSTING entry (the delta) that links `correction_of`, and emits a receipt
-- recording was/became. The full history stays auditable and reconstructible.

pure contract BuildCorrectionEntry {
  input original : LedgerEntry
  input corrected_amount : Integer
  input new_id : Integer
  input recorded_at : Integer
  input reason : String

  compute delta = corrected_amount - original.amount
  compute entry = {
    id: new_id,
    account: original.account,
    amount: delta,                       -- the adjusting delta
    valid_time: original.valid_time,     -- the fact's business time is unchanged
    transaction_time: recorded_at,       -- but we record the correction NOW
    correction_of: original.id,
    reason: reason
  }
  output entry : LedgerEntry
}

pure contract BuildCorrectionReceipt {
  input original : LedgerEntry
  input corrected_amount : Integer
  input new_id : Integer
  input reason : String

  compute delta = corrected_amount - original.amount
  compute receipt = {
    original_id: original.id,
    correction_id: new_id,
    was_amount: original.amount,
    became_amount: corrected_amount,
    delta: delta,
    reason: reason
  }
  output receipt : CorrectionReceipt
}
