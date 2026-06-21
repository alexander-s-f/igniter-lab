# lab-lang-signature-bound-boundary-bindings-p3-v0 — semantic `<-` boundary bindings

**Card:** `LAB-LANG-SIGNATURE-BOUND-BOUNDARY-BINDINGS-P3` · **Delegation:** `OPUS-LANG-SIGNATURE-BOUND-BOUNDARY-BINDINGS-P3`
**Status:** CLOSED (readiness/design — **no implementation**).
**Decision: DEFER `<-` from core `.ig` (Alternative D), route the real pressure to a staged-read surface
lane; `<- effect` is REJECTED on current semantics.** `<-` is **not** a parser-only desugar — no canonical
node exists to lower into, and the example's sequential effectful bindings contradict the graph + staged-host
model. No canon claim. `.ig` still gets no handle/DSN/passport.
**Authority:** Lab tooling design.

## Live facts (verified against code, not docs)

| Fact | Evidence |
|---|---|
| `read` is a **fixed-source declaration**, not an expression binding | `parser.rs` `BodyDecl::Read { name, type_annotation, from: String, lifecycle, scoped_by, … }` — `from` is a fixed string holder (`read stored : T from "editor.workspace"`). **No RHS expression.** |
| `read` performs **no body IO**; emits no executable node | emitter: `read` → `temporal_input_node` only when temporal, else no SIR node; the value is an input-like binding the body `compute`s over. |
| `capability` / `effect` are **declarations** (metadata), not body statements | `parser.rs` `Capability { name, type }`, `Effect { name, capability_ref }` — they mark the IO surface; they don't execute. |
| `InvokeEffect` is a **final Decision value**, returns nothing into the body | `igweb.rs:68` `InvokeEffect { target: String, input: Unknown, idempotency_key: String }` — produced by `compute d = InvokeEffect {…}`; the host receives it. There is **no in-body result**. |
| `<-` is **not tokenized** | no `LeftArrow`/`<-` in `lexer.rs`. |
| TodoApp read = **pure app-authored `QueryPlan`**, host-executed | `todo_handlers.ig` `ListTodosByAccount` builds `compute plan : QueryPlan = { source:"todos", op:"select", … }`; the `.ig` holds no DB handle. |
| TodoApp write = **pure `InvokeEffect` intent**, host-executed | `todo_handlers.ig` `AccountTodoCreate` → `compute d : Decision = InvokeEffect { target:"todo-create", input: intent, … }`. |
| Reads are **staged across two dispatches** (not mid-body) | `read-guard-host-p6`: query contract `dispatch()` → `PostgresReadExecutor` → rows → **separate** continuation `dispatch()`. The VM does one `dispatch()` per call; there is **no mid-dispatch IO**. `ReadThen { plan, then }` is **designed (p5) but unimplemented**. |
| Writes are **terminal**, proven via host | `effect-host-write-p4`: app returns `InvokeEffect` → `MachineEffectHost::run_invoke_effect` → receipt. The effect does **not** return a value into the same body. |
| Signature surface (P2) body = **`=` only**, parser-only | `signature-bound-contract-surface-p2` desugars `name = expr` → `compute`; `<-`/`?`/`let` explicitly excluded. |
| Authority boundary (host owns IO) | read-guard-host-p6: *"App owns the logical query + not-found Decision; host owns read policy + executor; `.ig` names no capability id, scope, DSN, or SQL."* |

## The chosen meaning of `<-` (if it existed)

The card's example wants `<-` to mean **"an app-authored intent crosses the host boundary and its result
re-enters the body for downstream use"**:

```ig
contract SettleOrder(order_id: String) -> (charge: Money, receipt: Receipt) {
  inventory : Inventory <- read   Inventory { key: order_id }   -- host reads, value returns to body
  charge    : Money     = Price { inventory: inventory }        -- pure
  receipt              <- effect Settle { order_id, charge }    -- host mutates, receipt returns to body
}
```

This is **monadic do-notation over host IO** — sequential bindings where each `<-` suspends the body, the
host performs IO, and the result resumes the body. **Igniter is not that.** It is a pure dependency graph
whose IO is *staged by the host across separate dispatches*. `<-` as written would impose an imperative/
continuation model the VM does not have.

## Can `<-` be a parser-only desugar? **No.**

- **`<- read` ✗→ `read … from "src"`**: the canonical `read` has a **fixed string source and no RHS
  expression**; the example's `read Inventory { key: order_id }` is an **app-authored intent** (like
  `QueryPlan`). Different shape, different authority origin. No desugar target.
- **`<- read` ✗→ staged continuation**: the only honest lowering is the **`ReadThen { plan, then }`** staged
  decision — and it is **unimplemented** and lives at the **IgWeb/host** layer, not as a core `.ig` body
  binding. A body-level `<- read` would require **mid-dispatch IO** (suspend → host read → resume), which the
  single-`dispatch()` VM cannot do. Not parser-only; not even VM-expressible today.
- **`<- effect` ✗**: `InvokeEffect` is a **final decision returning nothing into the body**. `receipt <-
  effect Settle {…}` falsely implies the effect yields a `receipt` for downstream use. Allowing it would
  **lie about semantics**. Effects are terminal today.

## Answers to the 12 questions

1. **What property does `<-` mark?** "An app-authored intent crosses the host boundary and its result
   re-enters the body" — i.e. a *staged IO continuation*. (Not a pure derivation.)
2. **Value-in / effect-out / both?** Both, as written (`<- read` = external value enters; `<- effect` =
   mutation leaves + receipt enters). That duality is exactly why it can't ride one existing node.
3. **Canonical read/effect body nodes to desugar into?** **No.** `read` = fixed-source declaration;
   `effect` = capability metadata; `InvokeEffect` = terminal decision. None accepts an app-authored intent
   RHS that returns a value into the same body.
4. **If no, P4 = syntax-reservation only?** Not worth it now — `<-` isn't tokenized, so there's no drift to
   prevent; reserving it adds process noise without ergonomic gain. (Alternative A rejected.)
5. **Where should `pure contract` reject `<-`?** Both parse-time and typecheck-time **when** `<-` is
   eventually introduced (a boundary crosses determinism/authority). Moot until then.
6. **Does non-pure `contract` already mean "may contain boundary bindings"?** No — non-pure today means
   "may carry `capability`/`effect` declarations and return `InvokeEffect`," not "has mid-body IO bindings."
   A genuine `<-` would need a **new qualifier or a new canonical boundary node**, not just dropping `pure`.
7. **`<-` vs final `InvokeEffect`?** `InvokeEffect` is terminal (contract output, host executes after); `<-`
   implies a *non-terminal* binding whose result continues the body. The model gap is exactly this.
8. **`<- read` vs `QueryPlan` + host `ReadThen`?** `QueryPlan` + staged host re-entry is the **real, working**
   mechanism (two dispatches). `<- read` would be sugar over a *single-body* continuation that doesn't exist.
9. **Can `<-` avoid giving `.ig` a handle?** Yes — intents stay app-authored, host executes; authority is
   unchanged. (Authority is **not** the blocker; the **execution model** is.)
10. **Smallest TodoApp example that benefits?** A read-then-respond handler (below) — but it benefits from a
    **`ReadThen` surface**, not from core `<-`.
11. **Diagnostics for unsupported `<-`?** Until/unless introduced: `<-` is a lexer-unknown → parse error.
    When introduced: `OOF-B1 "<- (boundary binding) is not supported here"`, `OOF-B2 "<- effect does not
    return a value into the body (effects are terminal)"`, `OOF-B3 "<- is not allowed in a pure contract"`.
12. **P4 slice if yes?** Not a `<-` implementation. The justified next slice is the **staged-read surface**
    (`LAB-IGNITER-WEB-READTHEN-SURFACE-P*`) that turns the proven p6 two-dispatch flow into an authored
    `read … as rows -> Handler` decision **at the IgWeb/host layer**. Revisit `<-` only after a canonical
    staged-boundary node exists (Alternative E).

## Alternatives compared

| Alt | Summary | Verdict |
|---|---|---|
| **A. Reserve `<-` only** (diagnostic, no behavior) | tokenize `<-`, emit "not implemented" | **Rejected** — no drift to prevent (not tokenized today), pure process noise. |
| **B. `<- read` → staged read intent** | sugar over app query + host continuation | **Rejected now** — needs mid-dispatch IO / `ReadThen` (unimplemented); not parser-only. |
| **C. `<- effect` → final decision** | model host mutation | **Rejected** — `InvokeEffect` is terminal; `<-` falsely implies an in-body receipt. |
| **D. Keep `<-` out of core for now** | use `=`, `?`, comprehensions, IgWeb staged decisions | **CHOSEN** — honest; avoids false monadic/IO semantics; real pressure handled by the ReadThen lane. |
| **E. Yes, but only after a canonical boundary node** | define SIR/body node first, then `<-` as surface | **Deferred follow-on** — the correct eventual path once staged IO has a canonical in-body form. |

## TodoApp pressure — current vs proposed

**Current (works today, p6-proven):** read is a pure plan + a host-staged continuation (two contracts).

```ig
pure contract ListTodosByAccount {              -- app authors the query (pure data)
  input account_id : String
  compute plan : QueryPlan = { source: "todos", op: "select", filters: [...], limit: 50 }
  output plan : QueryPlan
}
-- host runs the plan, then re-enters:
pure contract ListTodosRespond {                -- continuation receives rows
  input rows_json : String
  compute d : Decision = Respond { status: 200, body: rows_json }
  output d : Decision
}
```

**Proposed `<-` (does NOT work under current VM):**

```ig
contract ListTodos(account_id: String) -> (d: Decision) {
  rows : String <- read Todos { account_id: account_id }   -- needs mid-dispatch host IO (absent)
  d = Respond { status: 200, body: rows }
}
```

The proposed form reads better but requires a suspend/resume the VM does not have. The **ReadThen surface**
(host layer) is the place to recover that ergonomics without imposing monadic `<-` on core `.ig`. Note: for
**pure** fallible chains, the just-landed **`?`** already gives the linear, scannable shape — `<-` is only
needed for the *IO-staged* case, which is precisely the ReadThen lane.

## Diagnostics (for the eventual implementation, not now)

```text
x <- effect E { … }                    → OOF-B2 <- effect does not return a value into the body (effects are terminal)
pure contract … { x <- read … }        → OOF-B3 <- is not allowed in a pure contract (boundary crosses determinism)
x <- read … (outside a boundary-capable contract) → OOF-B1 <- (boundary binding) is not supported here
```

## Authority boundary (unchanged)

`.ig` gets **no** DB/file/network handle, **no** DSN, **no** passport. Reads/writes are **app-authored
intents** (`QueryPlan` / `InvokeEffect`); the **host owns** policy, capability authority, adapter, and
execution. `<-`, if ever added, would not change this — it changes *body control flow*, not authority.

## P4 recommendation

**Do not open `…-BOUNDARY-BINDINGS-P4` (implementation).** Open instead:

```text
LAB-IGNITER-WEB-READTHEN-SURFACE-P*
```

— turn the p6-proven two-dispatch staged read into an authored host-layer decision (`read <plan> as rows ->
<Handler>`), giving the read-ergonomics pressure a home in the layer that already owns staged IO. Revisit a
core `<-` only if/when that produces a canonical staged-boundary node (Alternative E), at which point `<-`
becomes thin surface over it.

## Closed surfaces

No broad effect system; no DB/file/network handle in `.ig`; no ORM/SQL syntax; no production runner change;
no VM execution change; no `<-` tokenization; no canon claim.

---

*Readiness/design only — verified against live lexer/parser/emitter + igweb + TodoApp + host docs
(2026-06-21). `<-` is not a parser-only desugar: no canonical in-body boundary node exists, reads are staged
across two dispatches, and effects are terminal. Decision: defer `<-` (D), route pressure to a staged-read
surface lane (E later). `?` already covers pure fallible chains.*
