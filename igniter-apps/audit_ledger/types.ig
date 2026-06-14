module AuditLedgerTypes

-- ============================================================
-- audit_ledger — bitemporal audit ledger (pure-data core)
-- ============================================================
-- Pulled from the temporal-audit pressure specimens
-- (financial-audit-time-travel, patient-medical-history). The aspirational
-- specimens want `BiHistory[T]`, `as_of`, `now()`, `Decimal[4]`, `store` —
-- none of which are implemented dual-clean. This app models the PURE-DATA
-- core that LANG-TEMPORAL-STATE-P1 proved is expressible TODAY:
--
--   * an append-only `Collection[LedgerEntry]` (no mutation, no store);
--   * two explicit time axes as Integer ticks (valid_time, transaction_time);
--   * corrections as adjusting entries linking `correction_of`;
--   * "as-of" reconstruction = filter on transaction_time + fold the balance.
--
-- Time-travel question answered: "what was the balance, as known on day T?"
--
-- PURE CORE only. Money is fixed-point Integer cents (no Decimal). Time is
-- injected Integer ticks (no clock / now()). See PRESSURE_REGISTRY.md.

-- ── A single ledger entry (one version of one fact) ─────────
-- A correction is itself an entry: an ADJUSTING delta whose `correction_of`
-- points at the entry it amends. This keeps the ledger append-only and the
-- whole history auditable.
type LedgerEntry {
  id              : Integer
  account         : String
  amount          : Integer   -- cents; correction entries carry the DELTA
  valid_time      : Integer   -- when the fact became true (business time)
  transaction_time: Integer   -- when we recorded it (system time)
  correction_of   : Integer   -- 0 = original entry; else the amended entry id
  reason          : String
}

-- ── A bitemporal "as-of" query ──────────────────────────────
type AsOfQuery {
  account   : String
  as_of_tt  : Integer   -- reconstruct as known on/before this transaction_time
  as_of_vt  : Integer   -- only facts valid on/before this valid_time
}

-- ── Reconstructed balance (the time-travel answer) ──────────
type BalanceReconstruction {
  account   : String
  as_of_tt  : Integer
  balance   : Integer
  entries_used : Integer
}

-- ── Correction receipt (the was/became audit record) ───────
type CorrectionReceipt {
  original_id   : Integer
  correction_id : Integer
  was_amount    : Integer
  became_amount : Integer
  delta         : Integer
  reason        : String
}
