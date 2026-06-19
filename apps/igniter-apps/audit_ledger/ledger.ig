module AuditLedgerCore
import AuditLedgerTypes
import stdlib.collection.{ filter, count }

-- ============================================================
-- Bitemporal reconstruction + correction trail (pure)
-- ============================================================

-- ── As-of visibility filter ─────────────────────────────────
-- An entry is VISIBLE in an as-of view when it belongs to the account, was
-- recorded on/before as_of_tt, and is valid on/before as_of_vt. Corrections
-- are ordinary entries, so an adjusting delta becomes visible exactly once
-- its own transaction_time has passed — that is what makes time-travel honest.
pure contract VisibleAsOf {
  input entries : Collection[LedgerEntry]
  input q : AsOfQuery
  compute visible = filter(entries, e ->
    if e.account == q.account {
      if e.transaction_time <= q.as_of_tt {
        if e.valid_time <= q.as_of_vt { true } else { false }
      } else { false }
    } else { false }
  )
  output visible : Collection[LedgerEntry]
}

-- ── Balance = scalar fold over the visible entries ──────────
-- PRESSURE AL-P03: a single running balance is a scalar fold (works). A
-- running-balance TRAJECTORY ({tick, balance} per step) would want fold-to-struct.
pure contract SumVisible {
  input visible : Collection[LedgerEntry]
  compute balance = fold(visible, 0, (acc, e) -> acc + e.amount)
  output balance : Integer
}

pure contract ReconstructBalance {
  input entries : Collection[LedgerEntry]
  input q : AsOfQuery
  compute visible = call_contract("VisibleAsOf", entries, q)
  compute balance = call_contract("SumVisible", visible)
  compute n = count(visible)
  compute recon = {
    account: q.account,
    as_of_tt: q.as_of_tt,
    balance: balance,
    entries_used: n
  }
  output recon : BalanceReconstruction
}

-- ── Correction trail for one original fact ──────────────────
-- PRESSURE AL-P07: the trail is the set of adjusting entries linking back to
-- an original. Provenance is by explicit `correction_of` id — a future
-- History[T] / typed temporal read would carry this natively.
pure contract CorrectionTrail {
  input entries : Collection[LedgerEntry]
  input original_id : Integer
  compute trail = filter(entries, e ->
    if e.correction_of == original_id { true } else { false }
  )
  output trail : Collection[LedgerEntry]
}

pure contract CorrectionCount {
  input entries : Collection[LedgerEntry]
  input original_id : Integer
  compute trail = call_contract("CorrectionTrail", entries, original_id)
  compute n = count(trail)
  output n : Integer
}
