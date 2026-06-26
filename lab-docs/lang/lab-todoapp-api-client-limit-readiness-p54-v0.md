# lab-todoapp-api-client-limit-readiness-p54-v0

Card: `LAB-TODOAPP-API-CLIENT-LIMIT-READINESS-P54`
Route: standard / product API readiness · Skill: idd-agent-protocol
Status: readiness/design only — **no production code** · no canon claim
Date: 2026-06-26
Builds on: P47 keyset `?after=` · P50 `{items, next}` envelope · P49 pagination-envelope readiness

> **Authority boundary.** Design only. Decides whether/how to expose a client `?limit=`; implements nothing,
> changes no host behavior, makes no API-stability claim. Every concrete claim is checked against live source.

---

## Headline

**Recommend status quo (Alternative A): keep the host-cap-only page size; do NOT add an arbitrary client
`?limit=<n>` yet.** Two independent live-source blockers make arbitrary client limit non-trivial, and the P50
`{items, next}` envelope is already complete and correct without it:

1. **No String→Integer parser in `.ig`** (Q9). `?limit=20` crosses as the **String** `"20"`
   (`req.query : Map[String, Unknown]`, string values, `lib.rs:397-411`), but `QueryPlan.limit` is `Integer`.
   `.ig` has `stdlib.math.to_float` (Integer→Float) and the new `to_text`/`float_to_text`, but **no
   String→Integer** (`grep to_integer|parse_int` = no match). So the app cannot turn `"20"` into a numeric
   plan limit today.
2. **`meta.truncated` is not a faithful "more pages" signal below the cap** (Q7). The host computes
   `requested = plan.limit.unwrap_or(row_limit); effective = requested.clamp(0, row_limit); clamped =
   requested > row_limit` (`postgres_read.rs:518-519`, `533`). So `truncated == (requested > host cap)` — it
   means "your requested page exceeded one host-cap page," **not** "more rows exist beyond this page." A client
   `limit=2` (< cap) yields `effective=2`, `clamped=false` → `truncated=false` even when more rows exist, so
   `next` would be wrongly empty. **Faithful client-limit pagination needs the host to know `available >
   effective` — an N+1 over-fetch or a count — which is new host behavior, out of scope here.**

The only client-tunable option expressible **today** (no new language/host work) is **D (a few named sizes)**,
because it uses string equality (`if size == "small" { 10 } else { 50 }`) instead of integer parsing — but it
still inherits the truncated-faithfulness gap. So even D is only correct once the host reports "more rows."

---

## Verify-first (live source)

| Fact | Evidence |
| --- | --- |
| `?k=v` crosses as `query : Map[String, Unknown]` with **string** values | `build_request_input`: `req.query.iter().map(|(k,v)| (k, Value::String(v)))` → `"query": Value::Object(query)` (`server/igniter-web/src/lib.rs:394-411`). App reads via `map_get_string(req.query, "after")` (`todo_handlers.ig:348`). |
| App sets `QueryPlan.limit : Integer` (a literal today) | `ListTodosByAccount … limit: 50` (`todo_handlers.ig`); the keyset `after` is a **String** (no parse needed) — `limit` is the only numeric query knob. |
| Host clamps the plan limit to `[0, row_limit]` | `requested = plan.limit.unwrap_or(self.policy.row_limit); effective_limit = requested.clamp(0, row_limit)` (`postgres_read.rs:518-519`). |
| `truncated` = requested > cap, NOT "more rows" | `clamped = requested > self.policy.row_limit` → `"row_limit_clamped"` (`postgres_read.rs:533`) → `meta.truncated`. |
| **No String→Integer parser exists** | `grep -n 'to_integer\|parse_int\|to_int\|parse_integer'` over `typechecker/stdlib_calls.rs` + `vm.rs` = **no match**. Only `to_float` (Integer→Float). |
| Host `row_limit` is the operator cap | `host.example.toml [postgres.read] row_limit = "100"`; the hard ceiling, never bypassable. |

---

## Alternatives compared (≥5)

| # | Shape | Expressible today? | Pros | Cons | Verdict |
| --- | --- | --- | --- | --- | --- |
| **A** | **No client limit; host cap only** (status quo) | **yes** | zero code; P50 `{items,next}` already correct; host cap is the only size authority | client can't request a smaller page | **RECOMMENDED v0** |
| **B** | **App parses `req.query.limit` → `QueryPlan.limit`, host clamps** | **NO** | principled; app-owned product semantics; host still caps | **blocked ×2**: (1) no String→Integer parser; (2) `truncated` unfaithful below cap → needs N+1/count host change | defer behind 2 enablers |
| **C** | **Host parses + clamps `limit` before `.ig`** | partial | host has Rust (no parser gap) | mixes authority (host owns *cap*, not product page size); still needs faithful-truncated; app loses the knob | rejected (authority blur) |
| **D** | **A few named sizes** (`?size=small\|large`) | **yes** | uses string equality (no parser); app-owned; no new language | coarse; still needs faithful-truncated for correctness; enum bikeshed | only viable *today*, but gated on truncated fix |
| **E** | **Defer until typed query-param parsing exists** | — | clean; waits for the real enabler | no client limit until then | acceptable framing of A |

---

## Decisions (Q1–Q10)

1. **App-owned or host-owned?** Product page size is **app-owned semantics**; the **host owns only the hard cap**
   (`row_limit`). A client `limit` is a *request for a page ≤ cap* the app validates — but the app can't parse it
   today (B blocked), so v0 = host-cap-only (A).
2. **Accepted syntax (when B/D land):** missing/empty → **default**; non-integer/negative → **400** (app
   `RespondError`); `0` → **400** (a zero-item page is a client error, see Q5); huge (> cap) → **clamp to cap**
   (not an error — clamping is the host's job); repeated `limit` → the query map keeps one value (parser
   collapses duplicates) — **not an error**, document last-wins.
3. **Product default:** the **host cap** (current behavior) — i.e. one full page. A future explicit default
   (e.g. 20) is an app constant ≤ cap, set when B/D land.
4. **Max bound + owner:** the **host `row_limit` cap** is the max and is **host-owned** (operator abuse
   boundary). The app default/requested limit is **app-owned** and always re-clamped by the host — never a
   bypass.
5. **`limit=0`:** **bad request (400)**, app `RespondError`. A client asking for zero items is almost always an
   error; "empty page" is better expressed by an exhausted cursor (`next: ""`), not `limit=0`.
6. **Response metadata:** keep the P50 **`{ items, next }`** — `next` already encodes "more pages" (`""` =
   done). Do **not** add `{page:{limit,truncated}}` (more envelope surface, no consumer) — defer (matches P49's
   rejection of the nested `page`).
7. **Does a smaller client limit affect `truncated`/`next` correctly?** **NO, not today** — `truncated` =
   requested > cap, so a client limit below the cap yields `truncated=false` even with more rows, making `next`
   wrongly empty. **This is the load-bearing technical blocker:** faithful client-limit pagination needs the
   host to report `available > effective` (N+1 over-fetch or count), a new host read behavior.
8. **Bad `limit` → app or host error?** **App `RespondError` 400** (product validation; the host only enforces
   the cap and never validates a client product param). Consistent with the P3/P49 authority split.
9. **New language/stdlib parsing required?** **YES for B** — a `stdlib.string.to_integer(String) -> …` parser
   (Result/Option, fail-closed on non-integer) is required to turn `"20"` into a plan `Integer`; it does not
   exist. **D avoids it** (string equality). This is the minimum language enabler.
10. **Minimum implementation card if proceeding:** see below.

---

## Recommendation + next cards

**Take A (status quo).** The P50 `{items, next}` envelope **remains valid and complete without a client
`limit`** — `next` drives "load more," the host cap is the page size, and no route changes. Do not add an
arbitrary `?limit=` until both enablers exist.

If/when client-tunable page size is wanted, the **minimum path is two narrow enabler cards, then the feature**:

1. **`LAB-LANG-STRING-TO-INTEGER-P-?`** (stdlib enabler) — a total, fail-closed `to_integer(String) ->
   Result[Integer, …]` (or `Option`), mirroring the `to_text`/`to_float` pattern; rejects non-integer/empty/
   overflow deterministically. Independently useful (any numeric query param).
2. **`LAB-TODOAPP-API-FAITHFUL-PAGE-TRUNCATED-P-?`** (host read) — make `truncated`/`next` mean "more rows
   exist beyond the returned page" (N+1 over-fetch or a count), so a sub-cap page size paginates correctly.
3. **`LAB-TODOAPP-API-CLIENT-LIMIT-IMPL-P-?`** (the feature, Alternative B) — app reads `req.query.limit` →
   `to_integer` → validate (default/400 per Q2/Q5) → `QueryPlan.limit` (host still clamps); response stays
   `{items, next}`. Test matrix below.

**Alternative D (named sizes)** is available *today* without enabler #1, but still needs enabler #2 for correct
paging — so it is not meaningfully cheaper than B once #2 lands. Recommend B over D once enabled.

---

## Bad-input taxonomy (for the impl card)

| `?limit=` | Behavior |
| --- | --- |
| absent / empty | product default (= host cap in v0) |
| valid `1..=cap` | page size = that value (host re-clamps to cap) |
| `> cap` | clamp to cap (not an error) |
| `0` | **400** app `RespondError` (`invalid_limit`) |
| negative | **400** |
| non-integer (`abc`, `1.5`) | **400** |
| repeated (`?limit=2&limit=9`) | query map keeps one (last-wins); not an error |

## Test matrix (for the impl card)

DB-free fake adapter, `--features machine`: default (absent → cap-page); valid small (page = n, **with faithful
truncated/next** once enabler #2 lands); `> cap` clamps; `0`/negative/non-integer → 400 app error;
empty page (`next: ""`); missing account (existing 404 path unchanged); denied source (403 before adapter);
the P50 `{items, next}` invariant holds with and without `limit`.

---

## Acceptance self-check

- [x] Packet written under `lab-docs/lang/`.
- [x] Live `Request.query` (`Map[String,Unknown]` strings) + `QueryPlan.limit` clamp (`clamp(0,cap)`,
      `truncated = requested>cap`) verified from code.
- [x] ≥5 alternatives compared (A–E).
- [x] Bad-input taxonomy specified.
- [x] Authority split named: **host owns the cap; app owns the product page-size semantics + 400s**.
- [x] Recommended path named (status quo A now; B behind two enabler cards) with IDs.
- [x] No production code changed; `git diff --check` clean.

## Reporting

- **Recommended `?limit=` contract:** none in v0 — **status quo A (host-cap page size)**; the P50 `{items,
  next}` envelope **remains valid without a client `limit`**.
- **Exact bad-input behavior (when implemented):** absent/empty → default; `>cap` → clamp; `0`/negative/
  non-integer → app `RespondError` 400; repeated → one value, not an error.
- **New language/stdlib parsing required?** **Yes** — a `to_integer(String)` parser (no such builtin exists);
  this is the minimum enabler for arbitrary client limit (Alternative B). Alternative D avoids it via named
  sizes but still needs the faithful-truncated host change.
- **Next card IDs (if proceeding):** `LAB-LANG-STRING-TO-INTEGER` → `LAB-TODOAPP-API-FAITHFUL-PAGE-TRUNCATED`
  → `LAB-TODOAPP-API-CLIENT-LIMIT-IMPL`. Otherwise **defer (E)** until product pressure.
- **P50 statement:** explicitly — the current `{items, next}` pagination is complete and correct **without**
  a client `limit`; adding `limit` is an enhancement, not a fix.
