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
    { kind: "label",  id: "", label: "", text: or_else(todo_id, "none"), required: false, action: "" },
    { kind: "label",  id: "", label: "", text: "Buy milk <script>",      required: false, action: "" },
    { kind: "button", id: "done", label: "Done", text: "", required: false, action: "submit" }
  ]
  compute view : ViewArtifact = { artifact: "view", layout: "form", title: "Todo Detail", body: body }
  compute d : Decision = RenderView { status: 200, view: view }
  output d : Decision
}

-- Failure proof: an unsupported node `kind` must fail closed to the same JSON 500 the render path uses.
pure contract TodoBadNode {
  input req : Request
  compute body : Collection[HtmlNode] = [
    { kind: "marquee", id: "", label: "", text: "x", required: false, action: "" }
  ]
  compute view : ViewArtifact = { artifact: "view", layout: "form", title: "Bad", body: body }
  compute d : Decision = RenderView { status: 200, view: view }
  output d : Decision
}
