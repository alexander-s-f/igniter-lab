# lab-igniter-web-html-expression-model-readiness-p24-v0

Card: `LAB-IGNITER-WEB-HTML-EXPRESSION-MODEL-READINESS-P24`
Route: standard / architecture readiness (background) · Skill: idd-agent-protocol
Status: readiness packet (no code changed; no renderer/dialect/Todo change; no canon claim)
Date: 2026-06-25
Builds on: Data Projection wave P1-P5. Keystone for the HTML wave P25 (template dialect) · P26 (ViewArtifact
evolution) · P27 (SSR descriptor boundary).

> **Authority boundary.** Design only. No code, no renderer change, no dialect implementation, no TodoApp
> route/view, no claim any HTML dialect is canon or implemented. Every concrete claim is cited against live
> source or a green test.

---

## Headline

**The HTML expression model is *View Descriptor Projection* — the outbound mirror of the Data Projection
Boundary.** The app projects domain data → a **typed view descriptor** (`ViewArtifact`); a **host projector**
renders that descriptor → bytes. The app never emits HTML strings or bytes; the descriptor is the contract;
optional dialects (`.igv`, a future `.ig.html`) are *authoring sugar that lowers to the descriptor*, never a
hidden runtime; the projector (host) owns rendering, escaping, and surface choice.

This is not a new proposal — it is the model the live code **already implements**. `igniter_render_html`
declares itself *"a projector / render target, not a language feature and not server authority… the HTML
analogue of the frame `RenderHost` impls (SVG/wireframe/GUI)"* (`frame-ui/igniter-render-html/src/lib.rs:3-6`).
So `ViewArtifact` is already a **multi-surface** descriptor; HTML is one `RenderHost` among several. `.igv`
already proves the *projection-dialect* pattern: *"a tiny lab-only text authoring syntax that LOWERS to the
proven ViewArtifact JSON… SUGAR over the artifact, nothing more… does not touch `.ig`"*
(`frame-ui/igniter-ui-kit/src/igv.rs:1-12`). **P24's job is to name this as the model and gate the wave on
it** — not to invent anything.

---

## 1. Projection symmetry — the unifying frame

The whole Igniter web stack is *projection at both ends, typed in the middle*:

```text
INBOUND   (Data Projection, P1-P5)   external source ──[ host projector ]──► typed data  Collection[<Record>]
COMPUTE   (Transform, P4)            typed data       ──[ app transform  ]──► view model / view descriptor
OUTBOUND  (View Projection, P24)     ViewArtifact     ──[ host projector ]──► bytes  (HTML | SVG | GUI | 3D)
```

The app lives **entirely in the typed middle** — it never touches SQL, JSON strings, HTML strings, or bytes.
Both ends are **host-owned projectors**: the data side decodes per `PostgresReadValueKind`
(`runtime/igniter-machine/src/postgres_read.rs:299`); the view side renders per `igniter_render_html` (and the
sibling frame `RenderHost`s). This symmetry is the "good form" the wave is searching for, and it is *already
real on both ends* — not aspirational.

Consequence: **HTML authoring is not HTML-locked.** Because the descriptor renders to SVG/GUI/3D too
(`igniter-frame` RenderHosts — see `project-gui-3d-exploration`), effort spent on the `ViewArtifact` descriptor
pays off across surfaces. A template dialect bound to HTML strings would forfeit this.

---

## 2. Live current surface (verified)

`cargo test --test todo_view_app_tests` → **14 passed, 0 failed** (run 2026-06-25). The surface:

**Authoring (in `.ig`) — Q1.** All structured; no HTML strings authored in `.ig`:
| Surface | What it is | Where |
| --- | --- | --- |
| typed `.ig` records | `HtmlNode` / `ViewArtifact` records built with literals | `igweb.rs:53-68`; `todo_views.ig:54-61` |
| helper contracts | `MakeLabel`/`MakeButton`/`MakeSelect`/`FormView`/`<Row>ToNode` hide the flat record's defaulted fields | `todo_views.ig:78-148` (P20-P23) |
| `RenderView { status, view : ViewArtifact }` | typed-record source → HTML | `lib.rs:415-427`; `igweb.rs:86` |
| `Render { status, artifact_json : String }` | request-body JSON source → HTML (`.ig` cannot author a JSON literal, so sourced from `req.body`) | `lib.rs:414`; `todo_views.ig:41-45` |
| `RespondView { status, view : View }` | JSON-first 2-level page→items descriptor (the body root) | `lib.rs:375-380`; `igweb.rs:43-47` |

**Intermediate representation (the descriptor) — Q2.** Two shallow, closed shapes (`.ig` has no recursive
types, `igweb.rs:36-37`):
- `ViewArtifact { artifact, layout, title, body : Collection[HtmlNode] }` (`igweb.rs:63-68`).
- `HtmlNode { kind, id, label, text, required, action, options }` — **flat, single record, kind-dispatched,
  all fields required (no defaults)** (`igweb.rs:53-61`).
- `View { kind, title, items : Collection[ViewItem] }` — 2-level JSON descriptor for `RespondView`
  (`igweb.rs:43-47`).

**Host projector (Rust, outside `.ig`).** `igniter_render_html::render_html(artifact_json)` → escaped HTML
document/fragment (`render-html/src/lib.rs:45-54`); `igniter-web` calls it from `render_to_decision`
(`lib.rs:441-453`), `igniter-server` stays renderer-free. Bounded vocabulary:
- layouts: `form`, `workbench` (`render-html:115-121`);
- `form` components: `label`→`<p>`, `button`→`<button>`, `text`/`select`/`checkbox`→inputs
  (`render-html:240-255`);
- **escaping/XSS is wholly projector-owned**: structured input → user data only lands in escaped leaves →
  *"there is no markup-injection surface"* (`render-html:9-13,58`); URLs via `safe_url` fail-closed on
  non-`http(s)` (`:77-102`); **no raw-HTML node; unknown shapes fail closed** (`:13,252,301`).

**Honest bound (feeds P26):** the descriptor is **flat and non-recursive** — `body` is a flat component list;
no containers/nesting, no semantic list primitive (the only list is the hardcoded `workbench` `data.leads`),
no links/anchors (`safe_url` exists but **unused** today, `:76`), node kinds limited to
label/button/text/select/checkbox. Enough for a Todo *form/list*; **not** enough for arbitrarily nested UI.
That bound is P26's subject, not P24's — the *model* holds regardless of vocabulary breadth.

---

## 3. Layer ownership map (Q3)

| Concern | Owner | Evidence |
| --- | --- | --- |
| domain data | host projector (in) / app decoder (untrusted) | P1-P5 |
| view model | **app** `.ig` transform | P4 (`todo_views.ig`) |
| view descriptor (`ViewArtifact`/`HtmlNode`) | **app** returns structured record | `lib.rs:415-427` |
| layout selection | descriptor `layout` field → host projector interprets (`form`/`workbench`) | `render-html:115` |
| **escaping / XSS** | **host projector** (structured → escaped leaves; no injection surface) | `render-html:9-13,58` |
| URL safety | **host projector** (`safe_url`, fail-closed) | `render-html:77` |
| surface choice (HTML / SVG / GUI / 3D) | **host projector** selection | frame `RenderHost`s |
| assets (css/js) | host (out of v0) | — |
| actions / forms | descriptor (`action`/`id` fields) → host maps to `<form>`/`<button>` | `render-html:245` |
| HTTP response bytes | **host** (`render_to_decision` raw `text/html` seam) | `lib.rs:441` |

The invariant: **`.ig` owns the descriptor; the host owns the bytes and the escaping.** Nothing in `.ig`
concatenates markup or decides safety — which is *why* injection is structurally impossible (§2).

---

## 4. Alternatives compared (Q / ≥7)

| # | Alternative | Verdict | Why |
| --- | --- | --- | --- |
| 1 | Typed `.ig` `HtmlNode`/`ViewArtifact` records + helpers | **Recommended substrate** | Proven (14/14); bias-aligned (no strings, host escaping); multi-surface; composes with P6. |
| 2 | App-local UI helper conventions (`MakeLabel`/`FormView`/`<Row>ToNode`) | **Recommended convention** | The P4 view-contract naming; hides the flat record's defaults; legible in code + graph. |
| 3 | `.igv` ViewArtifact dialect | **Keep as the dialect precedent** | Already lowers deterministically to ViewArtifact JSON, no runtime (`igv.rs:1-12`). The model for any dialect. Good for static/declarative views. |
| 4 | `.ig.html` template dialect | **Defer → P25** | Acceptable *only* as a projection dialect (lowers to ViewArtifact); **not** the v0 default (design bias). P25 decides its shape. |
| 5 | Host-side template engine / middleware | **Reject** | Hidden runtime; view logic leaves `.ig`; breaks "app returns structured descriptors"; loses multi-surface. |
| 6 | Direct HTML string return from `.ig` | **Reject** | Design bias; reintroduces the injection surface the structured descriptor *eliminates* (`render-html:9-13`). |
| 7 | Hybrid: `.ig` data→ViewModel, dialect renders ViewModel→ViewArtifact | **The target architecture = View Descriptor Projection** | #1+#2 instantiate it in v0; #3/#4 are optional dialect sugar on top. This *is* the recommendation. |
| 8 | ViewArtifact as a **multi-surface** descriptor (not HTML-specific) | **Recommended framing** | The renderer is one of several `RenderHost`s (`render-html:3-6`); staying on the descriptor keeps HTML/SVG/GUI/3D unified. A strength, not an alternative to discard. |

**Recommendation: #7 (the model) instantiated by #1+#2 for v0, with #3 as the proven dialect precedent and #4
deferred to P25.** Reject #5/#6 outright.

---

## 5. What TodoApp HTML should use first after Data Projection P6 (Q4)

**Idiom A from P4, unchanged, on the existing `form` layout** — no dialect, no vocab change:

```text
input rows : Collection[TodoRow]                                   -- from typed projection (P6)
compute body : Collection[HtmlNode] = map(rows, r -> call_contract("TodoRowToNode", r))
compute view : ViewArtifact         = call_contract("FormView", "Todos", body)
compute d    : Decision             = RenderView { status: 200, view: view }
```

Every line is already green (`todo_view_app_tests`); `TodoRowToNode` builds a `label` node via `MakeLabel`.
This is the implementation slice named in P1-P4 (typed-row crossing → HTML join). It needs **nothing** from
P25/P26/P27.

---

## 6. What stays out of v0 (Q5)

- `.ig.html` dialect **implementation** (P25 produces readiness only).
- ViewArtifact **vocabulary expansion** beyond the Todo list/form need (P26 decides scope; do not grow the
  node set speculatively).
- **Host template engine** (rejected, §4 #5).
- **Raw-HTML nodes** (security — the closed vocabulary is what removes the injection surface).
- **Arbitrary nesting / recursive trees** (until P26 proves the need *and* a bounded shape — `.ig` has no
  recursive types, so any nesting is a deliberate descriptor change).
- **Assets pipeline, client-side JS / interactivity** (SSR-only; the descriptor→bytes seam is P27).

---

## 7. How it composes with Data Projection P6 (and why it doesn't block it)

P6 (typed row crossing) produces `Collection[TodoRow]`. This model **consumes** that via the already-green
`transform → ViewArtifact → RenderView` path (§5). The HTML model is strictly **downstream and additive**:
P6 depends on nothing here, and TodoApp's first HTML uses the descriptor substrate as-is. The two waves are
**orthogonal and composing** — projection makes the data typed; this model makes its presentation a typed
descriptor. So this background card cannot block P6.

---

## 8. Next cards after P24

| Card | Type | Scope |
| --- | --- | --- |
| `LAB-IGNITER-WEB-TEMPLATE-DIALECT-READINESS-P25` | readiness (queued) | `.ig.html` **strictly as a projection dialect** (lowers to ViewArtifact, no hidden runtime — the `.igv` pattern). Decide if/why a second dialect beyond `.igv` is warranted. |
| `LAB-IGNITER-WEB-VIEWARTIFACT-EVOLUTION-READINESS-P26` | readiness (queued) | Is the flat/bounded `HtmlNode`/`ViewArtifact` vocab (§2 bound) enough for TodoApp UI, or does it need a *small, bounded* evolution (nesting? list primitive? link node via the ready-but-unused `safe_url`)? |
| `LAB-IGNITER-WEB-SSR-DESCRIPTOR-BOUNDARY-READINESS-P27` | readiness (queued) | The `descriptor → host projector → bytes` boundary + its tie to the file/export seam (the outbound projector, sibling of the inbound data projector). |
| TodoApp HTML list (impl) | implementation | §5, after Data Projection P6. Idiom A; DB-free harness; reuses the green renderer. |

---

## Verification

```bash
rg -n "RenderView|Render \{|RespondView|ViewArtifact|HtmlNode|MakeLabel|FormView|TodoLabel|html-preview|text/html" \
  server/igniter-web server/igniter-render-html lab-docs/lang .agents/work/cards/lang \
  > /tmp/igniter-html-expression-grep.txt        # 1210 hits

cargo test --test todo_view_app_tests             # 14 passed, 0 failed (from server/igniter-web, 2026-06-25)
git diff --check                                  # clean
```

(Renderer crate is at `frame-ui/igniter-render-html`, not `server/igniter-render-html`; the grep path is
harmless — the live read used the real path.)

---

## Reporting

- **Recommended HTML expression model:** **View Descriptor Projection** — app projects domain data → a typed
  `ViewArtifact` descriptor; host projector renders it → bytes (HTML/SVG/GUI/3D). Descriptor is the contract;
  dialects (`.igv` today, `.ig.html` later) are *projection sugar that lowers to it*, never a runtime; host
  owns rendering + escaping. v0 = the proven typed-record substrate (#1) + helper conventions (#2). It is the
  outbound mirror of the Data Projection Boundary — the same projection symmetry, already live on both ends.
- **Why it doesn't block Data Projection P6:** the model consumes `Collection[TodoRow]` via the already-green
  `transform → ViewArtifact → RenderView` path; it is downstream/additive and depends on nothing P6 produces.
- **Next cards:** P25 (template dialect — strictly a projection dialect), P26 (bounded ViewArtifact vocab
  evolution), P27 (SSR descriptor→bytes boundary + file/export seam); plus the TodoApp HTML list impl after P6.
