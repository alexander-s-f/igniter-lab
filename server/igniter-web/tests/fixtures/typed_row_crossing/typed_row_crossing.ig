-- LAB-IGNITER-DATA-PROJECTION-TYPED-ROW-CROSSING-P6 fixture — the authored `.ig` typed-row half.
--
-- This is the mainline step after the P1–P5 readiness series: it proves `rows_json : String` is no longer
-- the ONLY read-continuation boundary. The host materializes the fake-Postgres read into a total + typed
-- `Collection[TodoRow]` (records, not a JSON string) plus a `DatasetMeta` sidecar, and the continuation does
-- ordinary typed record work over them — `r.title` (String), `r.done == false` (Bool), `r.rank` arithmetic
-- (Integer), `filter`/`map`/`fold`/`count`, and `call_contract` over a row. No JSON parsing, no
-- `map_get_string`, no decoder contract: rows arrive native and typed.
--
-- App owns the row TYPE (advisory mirror of the host's schema authority); host owns the schema + the
-- reconciliation. No capability id, scope, DSN, raw SQL, or DB handle here — only a logical `source`.
module TypedRowCrossing

import IgWebPrelude

-- ── Relational intent mirror (structured QueryPlan; never SQL) ──────────────────────────────────
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

-- ── The projection target: the app's row type (the SINGLE declaration the host reconciles against) ──
type TodoRow {
  id         : String
  account_id : String
  title      : String
  done       : Bool
  rank       : Integer
}

-- ── Provenance sidecar (fixed, non-generic; crosses beside `rows`) ──────────────────────────────
type DatasetMeta {
  source    : String
  count     : Integer
  truncated : Bool
}

-- A typed summary the harness asserts against directly — every field is a typed read off the crossed
-- `Collection[TodoRow]` + `DatasetMeta`, so a green assertion proves the kind was preserved (e.g. a
-- numeric `rank_sum` could not be produced if `rank` had crossed as a String).
type ProjectionProof {
  total          : Integer
  pending        : Integer
  rank_sum       : Integer
  titles         : String
  meta_source    : String
  meta_count     : Integer
  meta_truncated : Bool
}

pure contract MakeFilter {
  input field : String
  input op    : String
  input value : String
  compute f = { field: field, op: op, value: value }
  output f : QueryFilter
}

-- Query intent: "list this account's todos" → a structural QueryPlan whose projection names the typed
-- columns the continuation will field-access. The host executes it; no SQL here.
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

-- Helper: a typed row → ViewItem (proves `call_contract` over a crossed record + String field access).
pure contract TodoRowItem {
  input r : TodoRow
  compute item : ViewItem = { key: r.id, label: r.title }
  output item : ViewItem
}

-- The PROBE: exhaustively exercises typed access over the crossed rows + meta, returning a custom record so
-- the harness can assert each typed dimension independently. `filter` on a Bool field, `fold` arithmetic on
-- an Integer field, `concat` on a String field, and the `DatasetMeta` reads all run here.
pure contract TypedTodoProbe {
  input req  : Request
  input rows : Collection[TodoRow]
  input meta : DatasetMeta
  compute pending   = filter(rows, r -> r.done == false)
  compute total     : Integer = count(rows)
  compute n_pending : Integer = count(pending)
  compute rank_sum  : Integer = fold(rows, 0, (acc, r) -> acc + r.rank)
  compute titles    : String  = fold(rows, "", (acc, r) -> concat(acc, r.title))
  compute proof : ProjectionProof = {
    total: total,
    pending: n_pending,
    rank_sum: rank_sum,
    titles: titles,
    meta_source: meta.source,
    meta_count: meta.count,
    meta_truncated: meta.truncated
  }
  output proof : ProjectionProof
}

-- The realistic continuation seam: the host re-enters here with the typed rows + meta. The app owns the
-- not-found product decision over the typed collection (empty → 404); a found set maps the PENDING rows to a
-- typed `View` (via `filter` then `map`+`call_contract`) and tags it with the dataset's source. No machine
-- internals; no `rows_json` string.
pure contract TypedTodoIndex {
  input req  : Request
  input rows : Collection[TodoRow]
  input meta : DatasetMeta
  compute total   : Integer = count(rows)
  compute pending = filter(rows, r -> r.done == false)
  compute items : Collection[ViewItem] = map(pending, r -> call_contract("TodoRowItem", r))
  compute v : View = { kind: meta.source, title: "todos", items: items }
  compute d : Decision = if total == 0 {
    Respond { status: 404, body: "no todos" }
  } else {
    RespondView { status: 200, view: v }
  }
  output d : Decision
}
