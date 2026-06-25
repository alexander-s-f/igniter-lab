-- LAB-IGNITER-DATA-PROJECTION-BOOT-DIAGNOSTIC-P8 fixture — STRUCTURALLY INVALID typed read continuations.
--
-- Each `*Bad*` contract below declares a read-continuation input shape that is invalid INDEPENDENT of any DB
-- source, so the host can reject it at build/check time before binding a listener (the P8 boot subset). The
-- contracts compile and load fine — the defect is in the crossing CONTRACT, not the syntax. A valid `Serve`
-- entry is present so the app builds. No capability id / scope / DSN / SQL.
module InvalidContinuations

import IgWebPrelude

type TodoRow {
  id         : String
  account_id : String
  title      : String
  done       : Bool
  rank       : Integer
}

-- A row type whose `amount : Float` has no v0 projection landing (only String/Text/Integer/Bool/Map/
-- Collection[String] land). Recoverable from metadata, but un-projectable → a boot diagnostic.
type MoneyRow {
  id     : String
  amount : Float
}

-- Valid entry so the app builds (not itself a read continuation).
pure contract Serve {
  input req : Request
  compute d : Decision = Respond { status: 200, body: "ok" }
  output d : Decision
}

-- INVALID: declares BOTH `rows_json : String` and `rows : Collection[TodoRow]` — ambiguous crossing.
pure contract BadBothShapes {
  input req       : Request
  input rows_json : String
  input rows      : Collection[TodoRow]
  compute d : Decision = Respond { status: 200, body: rows_json }
  output d : Decision
}

-- INVALID: `rows` element is a scalar, not a record — not a product-row boundary.
pure contract BadScalarRows {
  input req  : Request
  input rows : Collection[String]
  compute d : Decision = Respond { status: 200, body: "ok" }
  output d : Decision
}

-- INVALID: row type recoverable but carries a field with no v0 projection landing (`amount : Float`).
pure contract BadUnprojectableRow {
  input req  : Request
  input rows : Collection[MoneyRow]
  compute d : Decision = Respond { status: 200, body: "ok" }
  output d : Decision
}
