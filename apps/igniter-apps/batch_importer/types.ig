module BatchImporterTypes

-- ============================================================
-- batch_importer — CSV/webhook batch import (pure core)
-- ============================================================
-- Pulled from the mundane pressure specimens
-- (`igniter-csv-importer-v1.ig`, `igniter-webhook-ingestor-v1.ig`). The
-- specimen wants `Result[ImportRecord, List[Error]]` + `.filter(Ok).map(Ok.value)`
-- — neither dual-clean today (Option/Result not matchable). So validation
-- outcomes are modeled with a USER `variant RowResult`, and the batch produces
-- a partial-success receipt.
--
-- PURE CORE only. Parsing (Bytes/CSV → typed rows) and the DB write are the
-- ESCAPE boundary — injected. Amounts arrive as Integer cents (no String→Int
-- parse in CORE). See PRESSURE_REGISTRY.md.

-- ── A raw, already-tokenised inbound row (parsing is escape) ──
type RawRow {
  row_id  : Integer   -- the source identifier (used as the error key)
  amount  : Integer   -- cents (parsed at the boundary)
  email   : String
}

-- ── A validated domain record ───────────────────────────────
type ImportRecord {
  row_id : Integer
  amount : Integer
  email  : String
}

-- ── Per-row validation outcome (Result modeled as a variant) ──
-- PRESSURE BI-P04: this WANTS to be `Result[ImportRecord, Error]`, but built-in
-- Result is not constructible/matchable dual-clean, so we use a user variant.
-- Regression evidence for LANG-SUMTYPE-CONSTRUCT-MATCH.
variant RowResult {
  Valid   { record : ImportRecord }
  Invalid { row_id : Integer, message : String }
}

-- ── The batch import receipt (partial success) ──────────────
type ImportReceipt {
  total    : Integer
  accepted : Integer
  rejected : Integer
}
