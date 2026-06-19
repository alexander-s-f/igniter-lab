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
