-- LAB-TODOAPP-VIEW-DB-DECIMAL-MONEY-REPORT-P24 fixture — a DB-backed exact-money report in HTML.
--
-- The product payoff of P23 (typed Decimal crossing): a host `numeric` column crosses as an EXACT
-- `.ig Decimal[2]` through the normal `ReadThen` runner path, then renders via the P20 money surface —
-- `to_text(amount)` (exact, trailing zeroes) + `pad_left(..., 8, " ")` (right-aligned column) — AND a real
-- Decimal `fold`-total. No Float, no in-`.ig` decimal parser, no currency/locale, no renderer change. Escaping
-- stays renderer-owned. No capability id / scope / DSN / SQL.
module DbMoneyReport

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

-- App-local HtmlNode/ViewArtifact helpers (the flat records from the IgWebPrelude).
pure contract MakeMoneyLabel {
  input text : String
  compute node : HtmlNode = { kind: "label", id: "", label: "", text: text, required: false, action: "", options: [] }
  output node : HtmlNode
}

pure contract MakeMoneyFormView {
  input title : String
  input body  : Collection[HtmlNode]
  compute view : ViewArtifact = { artifact: "view", layout: "form", title: title, body: body }
  output view : ViewArtifact
}

-- One report row: `to_text(r.amount)` is the EXACT money text (proves `amount` is a real Decimal — a String
-- would be rejected by `to_text`); `pad_left(..., 8, " ")` right-aligns it; `concat` joins the (escaped) label.
pure contract MoneyRowLine {
  input row : LineRow
  compute cell : String = pad_left(to_text(row.amount), 8, " ")
  compute line : String = concat(row.label, cell)
  compute node : HtmlNode = call_contract("MakeMoneyLabel", line)
  output node : HtmlNode
}

-- Query intent: list the money lines (projection names the typed columns the continuation accesses).
pure contract ListMoney {
  input source : String
  compute projection : Collection[String] = ["label", "amount"]
  compute filters : Collection[QueryFilter] = []
  compute plan : QueryPlan = {
    source: source, op: "select",
    projection: projection, filters: filters, limit: 50
  }
  output plan : QueryPlan
}

-- Entry → ReadThen → typed money continuation (the host materializes `amount` as a real `Decimal[2]`).
pure contract FetchMoneyReport {
  input req : Request
  compute plan = call_contract("ListMoney", "lines")
  compute d : Decision = ReadThen { plan: plan, then: "MoneyReportFromRows", carry: "" }
  output d : Decision
}

-- The typed HTML continuation: render each row's money cell, append a real Decimal `fold`-TOTAL, RenderView.
pure contract MoneyReportFromRows {
  input req  : Request
  input rows : Collection[LineRow]
  input meta : DatasetMeta
  compute lines : Collection[HtmlNode] = map(rows, r -> call_contract("MoneyRowLine", r))
  compute total : Decimal[2] = fold(rows, decimal(0, 2), (acc, r) -> acc + r.amount)
  compute total_cell : String = pad_left(to_text(total), 8, " ")
  compute total_line : String = concat("TOTAL", total_cell)
  compute total_node : HtmlNode = call_contract("MakeMoneyLabel", total_line)
  compute body : Collection[HtmlNode] = concat(lines, [total_node])
  compute view : ViewArtifact = call_contract("MakeMoneyFormView", meta.source, body)
  compute d : Decision = RenderView { status: 200, view: view }
  output d : Decision
}
