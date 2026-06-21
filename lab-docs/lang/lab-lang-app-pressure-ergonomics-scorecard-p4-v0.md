# lab-lang-app-pressure-ergonomics-scorecard-p4-v0 — TodoApp ergonomics after the surface wave

**Card:** `LAB-LANG-APP-PRESSURE-ERGONOMICS-SCORECARD-P4` · **Delegation:** `OPUS-LANG-APP-PRESSURE-ERGONOMICS-SCORECARD-P4`
**Status:** CLOSED (research-scorecard). Ergonomics axis only — **no performance claims, no product changes,
no canon claim.** Improved forms are backed by a real compile fixture
(`tests/app_pressure_scorecard_tests.rs`, 3/3 green).
**Authority:** Lab measurement.

## Sources scored (live files)

- `server/igniter-web/examples/todo_postgres_app/todo_handlers.ig` (242 lines — relational intent, guards,
  handlers)
- `server/igniter-web/examples/todo_postgres_app/routes.igweb` (route-level `via` guards)
- `server/igniter-web/examples/todo_view_app/todo_views.ig` (ViewArtifact lists, helper contracts)
- shipped surfaces: signature-bound `(in)->(out){…}` (P2), fallible `?` over `Result` (P2), comprehensions
  (P2) — all CLOSED, with proof docs + tests.

## Snippet scorecard (current vs improved)

### 1. Conditional list rendering — `TodoPendingHtml` (comprehension)

**Current** (`todo_views.ig:161-162`):
```ig
compute pending : Collection[TodoItem] = filter(todos, t -> t.done == false)
compute body    : Collection[HtmlNode] = map(pending, t -> call_contract("TodoLabel", t))
```
**Improved** (comprehension):
```ig
compute body : Collection[HtmlNode] = [ call_contract("TodoLabel", t) for t in todos if t.done == false ]
```
2 authored compute nodes → **1**; named intermediate `pending` eliminated; inside-out `map(filter(…))`
(2-deep) → left-to-right read. Same SIR (comprehension desugars to the identical `map`/`filter`).

### 2. Plain list rendering — `TodoListHtml` (comprehension)

**Current** (`todo_views.ig:144`): `compute body = map(todos, t -> call_contract("TodoLabel", t))`
**Improved**: `compute body = [ call_contract("TodoLabel", t) for t in todos ]`
Smaller win (1 line → 1 line) but removes the `map(…, λ)` wrapper and reads in declaration order.

### 3. Contract ceremony — `Health` / every handler (signature-bound)

**Current** (`todo_handlers.ig:148-152`):
```ig
pure contract Health {
  input req : Request
  compute d : Decision = Respond { status: 200, body: "ok" }
  output d : Decision
}
```
**Improved**:
```ig
pure contract Health(req: Request) -> (d: Decision) {
  d = Respond { status: 200, body: "ok" }
}
```
3 body decls (`input`/`compute`/`output`) → **1 binding**; the `input`/`output` keywords and the duplicate
`d : Decision` disappear. The win scales with I+O arity (every contract pays this tax today).

### 4. Read-intent construction — `ListTodosByAccount` (signature; punning pressure remains)

**Current** (`todo_handlers.ig:74-84`) keeps `input`/`output` + a record with `projection: projection,
filters: filters`. **Improved** (signature header) removes the ceremony, but the record still repeats field
names:
```ig
plan = { source: "todos", op: "select", projection: projection, filters: filters, limit: 50 }
```
→ **Remaining pain: field punning** `{ projection, filters, … }` (not yet a feature). This is the strongest
next-card signal (below).

### 5. Failure path / guard — `LoadTodoContext` → handler (fallible `?`)

**Current** (`todo_handlers.ig:192-201`) — Bool flags + an `if` staircase, then `via` routing unwraps the
`Result`:
```ig
compute r : Result[TodoCtx, Decision] = if account_ok {
  if todo_ok { ok(ctx) } else { err(Respond { status: 404, body: "todo not found" }) }
} else { err(Respond { status: 404, body: "account not found" }) }
```
**Improved** (a handler that inlines a `Result`-returning guard, `E == O == Decision`):
```ig
compute d : Decision = {
  let ctx = call_contract("LoadTodoContext", req, account_id, todo_id)?
  Respond { status: 200, body: or_else(ctx.todo_id, "none") }
}
```
`?` collapses the `match`/`if`-staircase to a straight line. **But see finding 3** — the current app sidesteps
`Result` (Bool + `via`), so `?`'s benefit is latent, not currently exercised.

## Numeric friction metrics

| Metric | Current | Improved | Δ |
|---|---|---|---|
| `TodoPendingHtml` authored compute nodes (list path) | 2 | 1 | −1 (−50%) |
| `TodoPendingHtml` collection-expr nesting depth | 2 (`map(filter(…))`) | 1 (linear) | reads in order |
| body keywords per contract (`Health`: input+compute+output) | 3 | 0 (bare bindings) | −3 |
| repeated names in `Health` body (`req`,`d`) | `d`×2 | `d`×1 binding | −1 |
| `account_id` repetition across `routes.igweb` (scope + 4 `via`) | 5× | 5× (unchanged) | route-level, not a `.ig` surface |
| `HtmlNode` literal fields (5 of 7 defaulted) | 7 | 7 (unchanged) | helpers still hide it |
| helper contracts in `todo_views.ig` | 4 (`MakeLabel/Button/Select/FormView`) | 4 (still needed) | comprehensions don't reduce these |

## Qualitative notes

- **Human readability:** comprehension + signature are clear wins — list code reads in declaration order; the
  contract boundary (its I/O) is now a one-line signature instead of scattered `input`/`output` lines.
- **Agent readability:** signature surface is *more* machine-legible (the boundary is one structured header);
  comprehension keeps the `for x in C if P` shape an agent can template. `?` reduces branch-tree depth an
  agent must track. All three desugar 1:1 to canonical nodes, so the SIR an agent reasons over is unchanged.
- **Diagnostic locality:** good — comprehension errors surface as the underlying `map`/`filter` diagnostics
  at the same node; `?` errors point at the binding; signature bindings carry the compute node's diagnostics.
  No new error obscurity introduced (all are parser-desugars to existing nodes).
- **Authority-boundary visibility:** **preserved.** `InvokeEffect { target, input, idempotency_key }`,
  `Respond`/`RespondView`/`Render`, `requires idempotency`, and the `pure` modifier all stay explicit nodes.
  None of the three surfaces touch the effect/decision boundary — `?`'s `Err` arm is still a visible
  `Decision`. The authority boundary reads exactly as before.

## Questions answered

1. **Largest real reduction?** Two winners by different measures: **signature-bound** has the broadest reach
   (every contract sheds input/compute/output ceremony); **comprehensions** give the deepest per-site cut on
   list/conditional-list rendering (the ViewArtifact hot path).
2. **Does signature hide node structure?** No — it desugars 1:1 to the same compute nodes; it makes the
   contract boundary *more* visible. Mild note: without `compute` keywords the DAG is slightly less
   visually flagged, but order was never semantic.
3. **Does `?` cut guard/Result boilerplate here?** It *can* (proven to compile), but the current app avoids
   `Result` via Bool flags + `via` routing, so the benefit is **latent**. `?` is the right tool the moment a
   handler inlines a `Result`-returning guard (`E == O`).
4. **Do comprehensions solve ViewArtifact list pressure?** **Yes** — the `map`/`filter`→nodes pattern
   (snippets 1–2) collapses and reads in order.
5. **Are helper contracts still needed?** **Yes** — for the default-heavy `HtmlNode` records (7 fields, 5
   defaulted). Comprehensions handle the *collection* shape, not per-element field verbosity.
6. **Where is it still too graph-ceremonial?** (a) field punning `{ projection: projection, … }`; (b)
   defaulted `HtmlNode` fields; (c) `or_else(ctx.x, "none")` Option-unwrap everywhere; (d) route-arg
   repetition in `.igweb` (igweb-dialect, not core `.ig`).
7. **Where is explicitness worth keeping?** The authority boundary — `InvokeEffect`, the `Respond*`/`Render*`
   decisions, `requires idempotency`, `pure`. These name effects/authority and must stay explicit.
8. **Do-not-add sugar:** **an effectful/`await`-style operator (or implicit Decision short-circuit) that
   hides `InvokeEffect`/capability behind a glyph.** Any sugar that lets a write run or a Decision return
   without a visible node would erase the authority boundary — the one thing the whole model exists to keep
   legible. (Implicit Option auto-unwrap that hides None-handling is a milder version of the same hazard.)
9. **Next card to prioritize:** **field-punning shorthand** `{ projection, filters, source: "todos" }` —
   high-frequency in QueryPlan/WriteIntent/View construction, a cheap parser-only desugar (same class as
   comprehension), and it composes with record-spread P2. (Optional-field *defaults* would help the
   `HtmlNode` case more but are canon-gated by `LANG-OPTIONAL-FIELD-PARTIAL-RECORD` — not lab-doable.)
10. **Doc/example-migration only (not language):** migrating `todo_views.ig` (TodoListHtml/TodoPendingHtml →
    comprehensions) and `todo_handlers.ig` (→ signature form). Pure example migrations; the language already
    supports them.

## Compile evidence

`tests/app_pressure_scorecard_tests.rs` (3/3 green) proves the improved forms compile **and compose**:
- `signature_bound_handler_compiles` — signature surface.
- `signature_plus_comprehension_list_compiles` — signature + comprehension + filter + record element in one
  contract.
- `signature_plus_fallible_handler_compiles` — signature + `?` over a `call_contract` `Result` (`E == O`).

```text
$ cd lang/igniter-compiler && cargo test --test app_pressure_scorecard_tests → 3 passed
$ git diff --check → clean
```

## Recommendation (one next card)

Open **`LAB-LANG-RECORD-FIELD-PUNNING-P2`**: parser-only `{ name }` ⇒ `{ name: name }` shorthand (with mixed
explicit fields), composing with record spread. Highest-frequency remaining friction in real handler code
(QueryPlan/WriteIntent/View records), cheapest to ship, no authority impact. Keep optional-field defaults on
the canon PROP track.

---

*Research-scorecard, ergonomics axis only. Scored against live TodoApp files (2026-06-21); improved forms
compile via `app_pressure_scorecard_tests` (3/3). No performance claims, no product changes, no canon claim.*
