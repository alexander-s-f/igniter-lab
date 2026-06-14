module BatchImporterExample
import BatchImporterTypes
import BatchImporterValidate

-- ============================================================
-- Example: import a 4-row batch with partial success
-- ============================================================
-- Two good rows, one with a non-positive amount, one with a missing email.
--   total = 4, accepted = 2, rejected = 2.

-- PRESSURE BI-P05: inline records infer to Unknown in the Rust TC → factory.
pure contract MakeRow {
  input row_id : Integer
  input amount : Integer
  input email : String
  compute r = { row_id: row_id, amount: amount, email: email }
  output r : RawRow
}

pure contract DemoRows {
  compute r1 = call_contract("MakeRow", 1, 10000, "a@x.com")
  compute r2 = call_contract("MakeRow", 2, 0,     "b@x.com")   -- bad amount
  compute r3 = call_contract("MakeRow", 3, 5000,  "")          -- missing email
  compute r4 = call_contract("MakeRow", 4, 2500,  "d@x.com")
  compute rows = [r1, r2, r3, r4]
  output rows : Collection[RawRow]
}

contract RunImport {
  compute rows = call_contract("DemoRows")
  compute results = call_contract("ValidateAll", rows)
  compute receipt = call_contract("BuildReceipt", results)
  output receipt : ImportReceipt
}

entrypoint RunImport
