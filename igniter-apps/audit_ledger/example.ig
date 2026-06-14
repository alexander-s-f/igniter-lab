module AuditLedgerExample
import AuditLedgerTypes
import AuditLedgerCore
import AuditLedgerCorrect

-- ============================================================
-- Example: a correction and the time-travel it enables
-- ============================================================
-- Account "ACC-1" gets three entries, then entry #2 (5000) is corrected to
-- 4000 — recorded later (transaction_time 5) as an adjusting -1000 delta.
--
--   balance as known on day 3  → 17000  (before the correction existed)
--   balance as known on day 5  → 16000  (after the correction was recorded)
--
-- Same valid history, two transaction-time views — that is the audit point.

-- PRESSURE AL-P06: inline records infer to Unknown in the Rust TC, so the
-- ledger entries and the query are built through typed factories.
pure contract MakeEntry {
  input id : Integer
  input account : String
  input amount : Integer
  input valid_time : Integer
  input transaction_time : Integer
  input correction_of : Integer
  input reason : String
  compute e = {
    id: id, account: account, amount: amount,
    valid_time: valid_time, transaction_time: transaction_time,
    correction_of: correction_of, reason: reason
  }
  output e : LedgerEntry
}

pure contract MakeQuery {
  input account : String
  input as_of_tt : Integer
  input as_of_vt : Integer
  compute q = { account: account, as_of_tt: as_of_tt, as_of_vt: as_of_vt }
  output q : AsOfQuery
}

-- ── Build the append-only ledger (with one correction) ──────
pure contract DemoLedger {
  compute e1 = call_contract("MakeEntry", 1, "ACC-1", 10000, 1, 1, 0, "opening")
  compute e2 = call_contract("MakeEntry", 2, "ACC-1", 5000,  2, 2, 0, "invoice-42")
  compute e3 = call_contract("MakeEntry", 3, "ACC-1", 2000,  3, 3, 0, "fee")
  -- correction of e2: should have been 4000, recorded at tt=5
  compute c1 = call_contract("BuildCorrectionEntry", e2, 4000, 4, 5, "overcharge fix")
  compute ledger = [e1, e2, e3, c1]
  output ledger : Collection[LedgerEntry]
}

-- ── Time-travel: balance as known on day 3 (pre-correction) ──
contract BalanceAsOfDay3 {
  compute ledger = call_contract("DemoLedger")
  compute q = call_contract("MakeQuery", "ACC-1", 3, 3)
  compute recon = call_contract("ReconstructBalance", ledger, q)
  output recon : BalanceReconstruction
}

-- ── Time-travel: balance as known on day 5 (post-correction) ──
contract BalanceAsOfDay5 {
  compute ledger = call_contract("DemoLedger")
  compute q = call_contract("MakeQuery", "ACC-1", 5, 5)
  compute recon = call_contract("ReconstructBalance", ledger, q)
  output recon : BalanceReconstruction
}

-- ── The correction receipt (was/became) ─────────────────────
contract ShowCorrection {
  compute e2 = call_contract("MakeEntry", 2, "ACC-1", 5000, 2, 2, 0, "invoice-42")
  compute receipt = call_contract("BuildCorrectionReceipt", e2, 4000, 4, "overcharge fix")
  output receipt : CorrectionReceipt
}

entrypoint BalanceAsOfDay5
