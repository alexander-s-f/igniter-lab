-- TodoApp view handlers (LAB-TODOAPP-VIEW-MANIFEST-P2; authored, pure, fake/static data).
-- Each view handler builds a typed `View` descriptor and returns it via `RespondView`, so the wire
-- body root is the clean view JSON object (no `{"body": "<escaped-json>"}` double-wrap, no DB).
module TodoViews

import IgWebPrelude

pure contract TodoIndexView {
  input req : Request
  compute items : Collection[ViewItem] = [
    { key: "1", label: "Buy milk" },
    { key: "2", label: "Write the spec" }
  ]
  compute v : View = { kind: "todo_index", title: "Todos", items: items }
  compute d : Decision = RespondView { status: 200, view: v }
  output d : Decision
}

pure contract TodoDetailView {
  input req     : Request
  input todo_id : Option[String]
  compute items : Collection[ViewItem] = [
    { key: or_else(todo_id, "none"), label: "Todo detail" }
  ]
  compute v : View = { kind: "todo_detail", title: "Todo", items: items }
  compute d : Decision = RespondView { status: 200, view: v }
  output d : Decision
}

-- Contrast: a plain JSON data route still uses the older `Respond { body: String }` shape.
pure contract ApiHealth {
  input req : Request
  compute d : Decision = Respond { status: 200, body: "ok" }
  output d : Decision
}

-- LAB-TODOAPP-VIEW-HTML-P17: hand the request-body ViewArtifact JSON through `Render`; igniter-web
-- projects it to escaped HTML (P3 renderer) and ships verbatim text/html bytes (P15 raw seam). `.ig`
-- cannot author a JSON literal, so the descriptor is sourced from `req.body` — JSON-first `RespondView`
-- routes above are untouched.
pure contract TodoHtmlPreview {
  input req : Request
  compute d : Decision = Render { status: 200, artifact_json: req.body }
  output d : Decision
}

-- LAB-IGNITER-WEB-VIEWARTIFACT-AUTHORING-P19: author the ViewArtifact from ordinary typed `.ig` records
-- (NO request-body JSON, NO JSON/HTML string literals, NO concatenation). The captured `todo_id` flows
-- into a leaf field; a `<script>` leaf proves the renderer escapes it. `RenderView` carries the typed
-- value; igniter-web serializes + projects it to text/html.
pure contract TodoAuthoredHtml {
  input req     : Request
  input todo_id : Option[String]
  compute body : Collection[HtmlNode] = [
    { kind: "label",  id: "", label: "", text: or_else(todo_id, "none"), required: false, action: "", options: [] },
    { kind: "label",  id: "", label: "", text: "Buy milk <script>",      required: false, action: "", options: [] },
    { kind: "button", id: "done", label: "Done", text: "", required: false, action: "submit", options: [] }
  ]
  compute view : ViewArtifact = { artifact: "view", layout: "form", title: "Todo Detail", body: body }
  compute d : Decision = RenderView { status: 200, view: view }
  output d : Decision
}

-- Failure proof: an unsupported node `kind` must fail closed to the same JSON 500 the render path uses.
pure contract TodoBadNode {
  input req : Request
  compute body : Collection[HtmlNode] = [
    { kind: "marquee", id: "", label: "", text: "x", required: false, action: "", options: [] }
  ]
  compute view : ViewArtifact = { artifact: "view", layout: "form", title: "Bad", body: body }
  compute d : Decision = RenderView { status: 200, view: view }
  output d : Decision
}

-- LAB-IGNITER-WEB-VIEWARTIFACT-HELPER-CONTRACTS-P20: app-local helper contracts that return the SAME P19
-- flat `HtmlNode`/`ViewArtifact` records, so the verbose defaulted fields are set ONCE in the helper and
-- the caller reads like composition. No new protocol, no node enum, no renderer change — pure `.ig`.
pure contract MakeLabel {
  input text : String
  compute node : HtmlNode = { kind: "label", id: "", label: "", text: text, required: false, action: "", options: [] }
  output node : HtmlNode
}

pure contract MakeButton {
  input id     : String
  input label  : String
  input action : String
  compute node : HtmlNode = { kind: "button", id: id, label: label, text: "", required: false, action: action, options: [] }
  output node : HtmlNode
}

pure contract FormView {
  input title : String
  input body  : Collection[HtmlNode]
  compute view : ViewArtifact = { artifact: "view", layout: "form", title: title, body: body }
  output view : ViewArtifact
}

-- LAB-IGNITER-WEB-VIEWARTIFACT-SELECT-OPTIONS-P23: a select/dropdown node from an authored option
-- collection. `HtmlNode.options : Collection[String]` (the renderer's select schema); options render in
-- authored order, each escaped. App-local helper over the flat record; no new dialect, no client JS.
pure contract MakeSelect {
  input id      : String
  input label   : String
  input options : Collection[String]
  compute node : HtmlNode = { kind: "select", id: id, label: label, text: "", required: false, action: "", options: options }
  output node : HtmlNode
}

pure contract TodoFilterHtml {
  input req : Request
  compute options : Collection[String] = ["all", "pending <script>", "done"]
  compute sel   : HtmlNode = call_contract("MakeSelect", "status", "Status", options)
  compute apply : HtmlNode = call_contract("MakeButton", "apply", "Apply", "/todos")
  compute body  : Collection[HtmlNode] = [sel, apply]
  compute view  : ViewArtifact = call_contract("FormView", "Filter", body)
  compute d : Decision = RenderView { status: 200, view: view }
  output d : Decision
}

-- LAB-IGNITER-WEB-VIEWARTIFACT-LIST-AUTHORING-P21: a domain collection → node collection. `map` over a
-- `Collection[TodoItem]` with a helper-contract callback (the live `map(coll, x -> call_contract(...))`
-- shape, proven in apps/batch_importer + bloom_filter) builds `body : Collection[HtmlNode]` — no manual
-- per-node enumeration. App-local domain type + helper; no DB, no new syntax, no renderer change.
type TodoItem {
  id    : String
  title : String
  done  : Bool
}

pure contract TodoLabel {
  input todo : TodoItem
  compute text : String = todo.title
  compute node : HtmlNode = call_contract("MakeLabel", text)
  output node : HtmlNode
}

pure contract TodoListHtml {
  input req : Request
  compute todos : Collection[TodoItem] = [
    { id: "1", title: "Buy milk <script>", done: false },
    { id: "2", title: "Write the spec",    done: true  }
  ]
  compute body : Collection[HtmlNode] = map(todos, t -> call_contract("TodoLabel", t))
  compute view : ViewArtifact = call_contract("FormView", "Todos", body)
  compute d : Decision = RenderView { status: 200, view: view }
  output d : Decision
}

-- LAB-IGNITER-WEB-VIEWARTIFACT-CONDITIONAL-LISTS-P22: a conditional list — `filter` the domain collection
-- (keep only pending todos) BEFORE mapping to nodes. `filter(coll, x -> predicate)` is the live shape
-- (apps/bookkeeping `filter(tx.postings, p -> p.direction == "Debit")`); `filter` then `map` preserves
-- order. Reuses P21 `TodoItem`/`TodoLabel` + P20 `FormView`; no renderer/prelude change, no new syntax.
pure contract TodoPendingHtml {
  input req : Request
  compute todos : Collection[TodoItem] = [
    { id: "1", title: "Buy milk <script>", done: false },
    { id: "2", title: "Write the spec",    done: true  },
    { id: "3", title: "Pay bills",         done: false }
  ]
  compute pending : Collection[TodoItem] = filter(todos, t -> t.done == false)
  compute body : Collection[HtmlNode] = map(pending, t -> call_contract("TodoLabel", t))
  compute view : ViewArtifact = call_contract("FormView", "Pending", body)
  compute d : Decision = RenderView { status: 200, view: view }
  output d : Decision
}

-- Helper-authored route. SAME inputs/content as the verbose `TodoAuthoredHtml`, so its rendered HTML must
-- be byte-identical — proving helpers are sugar over the proven record model. Named `compute` nodes
-- (call_contract results) compose into the body collection.
pure contract TodoHelperHtml {
  input req     : Request
  input todo_id : Option[String]
  compute n_id   : HtmlNode = call_contract("MakeLabel", or_else(todo_id, "none"))
  compute n_milk : HtmlNode = call_contract("MakeLabel", "Buy milk <script>")
  compute n_done : HtmlNode = call_contract("MakeButton", "done", "Done", "submit")
  compute body : Collection[HtmlNode] = [n_id, n_milk, n_done]
  compute view : ViewArtifact = call_contract("FormView", "Todo Detail", body)
  compute d : Decision = RenderView { status: 200, view: view }
  output d : Decision
}
