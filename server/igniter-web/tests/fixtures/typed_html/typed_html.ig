-- LAB-TODOAPP-VIEW-TYPED-ROWS-HTML-P18 fixture — host DB-shaped rows → typed app rows → real text/html.
--
-- Joins the two proven halves: P7's typed `ReadThen` crossing (rows : Collection[TodoRow] + meta :
-- DatasetMeta, auto-routed through `dispatch_with_read`) and the TodoView HTML helpers (MakeLabel/MakeLink/
-- FormView + map/filter → Collection[HtmlNode] → RenderView → escaped text/html). NO `rows_json : String`,
-- NO request-body artifact JSON, NO manual node enumeration, NO JSON parser in `.ig`. App owns the row type,
-- the view, and the empty-state; the host owns the read + schema. No capability id / scope / DSN / SQL.
module TypedHtml

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

type TodoRow {
  id         : String
  account_id : String
  title      : String
  done       : Bool
  rank       : Integer
}

type DatasetMeta {
  source    : String
  count     : Integer
  truncated : Bool
}

pure contract MakeFilter {
  input field : String
  input op    : String
  input value : String
  compute f = { field: field, op: op, value: value }
  output f : QueryFilter
}

pure contract ListTypedTodos {
  input account_id : String
  compute projection : Collection[String] = ["id", "account_id", "title", "done", "rank"]
  compute f_acct = call_contract("MakeFilter", "account_id", "eq", account_id)
  compute filters : Collection[QueryFilter] = [f_acct]
  compute plan : QueryPlan = {
    source: "todos", op: "select",
    projection: projection, filters: filters, limit: 50
  }
  output plan : QueryPlan
}

-- ── App-local HTML helpers (same flat HtmlNode/ViewArtifact records as todo_view_app) ───────────
pure contract MakeLabel {
  input text : String
  compute node : HtmlNode = { kind: "label", id: "", label: "", text: text, required: false, action: "", options: [] }
  output node : HtmlNode
}

pure contract MakeLink {
  input text : String
  input href : String
  compute node : HtmlNode = { kind: "link", id: "", label: "", text: text, required: false, action: href, options: [] }
  output node : HtmlNode
}

pure contract FormView {
  input title : String
  input body  : Collection[HtmlNode]
  compute view : ViewArtifact = { artifact: "view", layout: "form", title: title, body: body }
  output view : ViewArtifact
}

-- A typed host row → an HtmlNode label (proves call_contract over a crossed record; the title escapes).
pure contract TodoRowLabel {
  input row : TodoRow
  compute node : HtmlNode = call_contract("MakeLabel", row.title)
  output node : HtmlNode
}

-- ── Entry → ReadThen → typed HTML continuation ──────────────────────────────────────────────────
pure contract FetchTodoHtml {
  input req : Request
  compute account_id : String = req.path
  compute plan = call_contract("ListTypedTodos", account_id)
  compute d : Decision = ReadThen { plan: plan, then: "TodoHtmlFromRows", carry: "" }
  output d : Decision
}

-- The typed HTML continuation: host re-enters with materialized typed rows + meta. `filter` keeps pending
-- todos, `map` turns them into HtmlNode labels, `meta` drives the view title + a "load more" affordance, and
-- an empty set renders an APP-owned empty state (200) — never a host error. RenderView → escaped text/html.
pure contract TodoHtmlFromRows {
  input req  : Request
  input rows : Collection[TodoRow]
  input meta : DatasetMeta
  compute total : Integer = count(rows)
  compute pending : Collection[TodoRow] = filter(rows, t -> t.done == false)
  compute labels : Collection[HtmlNode] = map(pending, t -> call_contract("TodoRowLabel", t))
  compute more_link : HtmlNode = call_contract("MakeLink", "Load more", "/todos")
  compute more : Collection[HtmlNode] = if meta.truncated {
    [more_link]
  } else {
    []
  }
  compute empty_node : HtmlNode = call_contract("MakeLabel", "No todos yet")
  compute body : Collection[HtmlNode] = if total == 0 {
    [empty_node]
  } else {
    concat(labels, more)
  }
  compute view : ViewArtifact = call_contract("FormView", meta.source, body)
  compute d : Decision = RenderView { status: 200, view: view }
  output d : Decision
}

-- ── LAB-TODOAPP-VIEW-TYPED-ROW-LINKS-P19: row DATA drives navigation, not just text ─────────────────
-- A typed host row → an HtmlNode DETAIL LINK: href built from `row.id` (a String field → clean `concat`,
-- no Integer→String coercion), label from `row.title` (escaped by the projector). Same flat `link` node,
-- no new schema.
pure contract TodoRowDetailLink {
  input row : TodoRow
  compute href : String = concat("/todos/", row.id)
  compute node : HtmlNode = call_contract("MakeLink", row.title, href)
  output node : HtmlNode
}

-- P19 entry → ReadThen → typed links continuation (same plan/source as the label flow).
pure contract FetchTodoLinksHtml {
  input req : Request
  compute account_id : String = req.path
  compute plan = call_contract("ListTypedTodos", account_id)
  compute d : Decision = ReadThen { plan: plan, then: "TodoLinksHtmlFromRows", carry: "" }
  output d : Decision
}

-- The typed links continuation: each crossed row → a per-row detail link (`map`); the KEYSET "load more"
-- href is built from the LAST row's id (the next page starts after it). `last` returns `Option[String]`,
-- unwrapped with `or_else`. No `rows_json`, no new primitive, no Integer→String (id is a String field).
pure contract TodoLinksHtmlFromRows {
  input req  : Request
  input rows : Collection[TodoRow]
  input meta : DatasetMeta
  compute total : Integer = count(rows)
  compute links : Collection[HtmlNode] = map(rows, r -> call_contract("TodoRowDetailLink", r))
  compute ids : Collection[String] = map(rows, r -> r.id)
  compute last_id : String = or_else(last(ids), "")
  compute more_href : String = concat("/todos?after=", last_id)
  compute more_link : HtmlNode = call_contract("MakeLink", "Load more", more_href)
  compute more : Collection[HtmlNode] = if meta.truncated {
    [more_link]
  } else {
    []
  }
  compute empty_node : HtmlNode = call_contract("MakeLabel", "No todos yet")
  compute body : Collection[HtmlNode] = if total == 0 {
    [empty_node]
  } else {
    concat(links, more)
  }
  compute view : ViewArtifact = call_contract("FormView", meta.source, body)
  compute d : Decision = RenderView { status: 200, view: view }
  output d : Decision
}

-- ── LAB-TODOAPP-VIEW-MONEY-REPORT-P20: exact money cells from the new formatting surface ─────────────
-- A tiny report view: authored `Decimal[2]` amounts → `to_text` (exact, trailing zeroes preserved) →
-- `pad_left` (right-aligned column) → `concat` with an (escaped) label → an HtmlNode label → RenderView.
-- No Float, no currency/locale/grouping, no local formatter, no renderer change. Money on a host READ would
-- arrive as a String (typed Decimal projection is deferred), so the Decimal values are authored here.
type LineItem {
  label  : String
  amount : Decimal[2]
}

-- Factory: build a `Decimal[2]` from minor units (cents) so the amount is a real Decimal, not a String.
pure contract MakeLineItem {
  input label : String
  input cents : Integer
  compute amt : Decimal[2] = decimal(cents, 2)
  compute item : LineItem = { label: label, amount: amt }
  output item : LineItem
}

-- One report row: `to_text(Decimal)` is the exact money text; `pad_left(..., 8, " ")` right-aligns it into a
-- fixed column; `concat` joins the label. The renderer escapes the whole label (user text included).
pure contract MoneyRow {
  input item : LineItem
  compute cell : String = pad_left(to_text(item.amount), 8, " ")
  compute line : String = concat(item.label, cell)
  compute node : HtmlNode = call_contract("MakeLabel", line)
  output node : HtmlNode
}

pure contract MoneyReportHtml {
  input req : Request
  compute it1 = call_contract("MakeLineItem", "Coffee <script>", 1250)
  compute it2 = call_contract("MakeLineItem", "Books", 12345)
  compute it3 = call_contract("MakeLineItem", "Gift", 500)
  compute items : Collection[LineItem] = [it1, it2, it3]
  compute body : Collection[HtmlNode] = map(items, it -> call_contract("MoneyRow", it))
  compute view : ViewArtifact = call_contract("FormView", "Report", body)
  compute d : Decision = RenderView { status: 200, view: view }
  output d : Decision
}
