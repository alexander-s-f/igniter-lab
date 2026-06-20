# lab-lang-signature-bound-contract-surface-readiness-p1-v0 — compact contract surface with graph signatures

**Card:** `LAB-LANG-SIGNATURE-BOUND-CONTRACT-SURFACE-READINESS-P1` · **Delegation:** `OPUS-LANG-SIGNATURE-BOUND-CONTRACT-SURFACE-P1`
**Status:** READINESS / DESIGN (v0) — designs a compact `(inputs) -> (outputs) { binds }` contract surface
that is a deterministic projection to canonical `input/read/compute/output`. **No code; no canon claim.**
P0 discipline: a glyph earns syntax only if it classifies a real, checkable graph property.

## 1. Executive summary

The signature-bound surface is **viable as pure sugar** and is well-grounded in live code: the contract
header today is `[modifier] contract Name [type-params] { body }` with **no parameter list**, so
`(in) -> (out)` is a genuinely new, non-colliding header. The body's bare bindings **desugar directly to
canonical `compute`/`read` body-decls — NOT through the (currently broken) block `let`** — so the pure-`=`
slice is **independent of `MATCH-ARM-BINDINGS-P2`**. The `=`/`<-` split carries real audit information
(`=` pure-derive, `<-` host/world boundary) and is checkable (`pure ⟹ no <-`). Recommendation: **ship the
`=`-only pure surface first (Alternative B), then add semantic `<-` (Alternative D) once canonical read/
effect node semantics are pinned.**

## 2. Verify-first (live findings)

| Question | Finding |
|---|---|
| contract header today | `parse_contract_decl`: `[modifier] contract Name [type-params] { body }` — **no `(params)`** → signature form is new (Q3) |
| canonical body kinds | `input`, **`read`**, **`stream`**, `compute`, `output` are all live body decls (`parser.rs:1722` read; `typechecker.rs:1076` `"input"\|"read"\|"stream"`) — the kernel has ≥5 boundary kinds, not 2 (Q-read) |
| `read` exists as canonical node? | **YES** (not just proposal) |
| modifiers | `"pure" \| "observed" \| "effect" \| "privileged" \| "irreversible"` (`parser.rs:997`), default **`pure`** (`:1558`) |
| `pure` forbids read/effect? | **not strictly enforced today** in the typechecker (modifier is carried; no found "pure⟹no read" check) → the `pure ⟹ no <-` invariant is a **new checkable rule** the surface adds (Q9) |
| multiple outputs | structurally supported — the body loop pushes each `output` decl into a `Vec` (Q10/Q14) |
| `<-` lexical conflict | **none** — lexer has `Arrow ->`, `FatArrow =>`, `Assign =`, `Question ?`; **no `LeftArrow`** → `<-` is a clean new token (Q-conflict) |
| `?` token | already exists in the lexer (from optional-field work) — relevant only to the **deferred** fallible-binding card |
| `let`/`BlockBody` | exist (if/else branches) but `let` **does not bind** (`OOF-P1`, per match-arm readiness) → body bindings must **not** desugar through `let` |
| duplicate node names | no single clear "duplicate body node" rule found → a diagnostic the surface should add/confirm (Q11) |

**Load-bearing consequence:** a body binding `name [:T] = expr` desugars to a **`compute` body-decl**, and
`name [:T] <- read/effect …` to a **`read`/effect body-decl** — the canonical node kinds that already exist
and already lower to SIR. The surface adds **no new node kind**; it is a header + glyph projection.

## 3. Name (Q1)

**"Signature-bound contract surface."** Accurate: the *signature* `(in) -> (out)` binds the contract's
graph boundary; the body provides the interior nodes. ("Compact contract surface" undersells that the
signature *is* the boundary declaration.)

## 4. Grammar (Q3, Q4)

```
contract_decl := modifier? "contract" Name type_params? signature? "{" body_bind* "}"
signature     := "(" param ("," param)* ? ")" "->" "(" param ("," param)* ")"
param         := Name ":" Type
body_bind     := Name (":" Type)? "=" expr        -- pure compute node
               | Name (":" Type)? "<-" boundary    -- host/world boundary node
boundary      := "read" Name record_literal
               | "effect" Name record_literal      -- (effect form gated to non-pure; later slice)
```
- the signature is **optional** — a contract with no signature uses today's explicit `input/.../output` body
  (full backward compatibility);
- with a signature, body decls are bare bindings (no `input`/`compute`/`output` keywords);
- an output named in `-> (...)` is provided by a body binding of the same name.

## 5. Desugar to canonical `.ig` (Q13) — the core

Each surface element maps 1:1 to an existing body decl:

| Surface | Canonical |
|---|---|
| `(req: Request) ->` param | `input req : Request` |
| `name : T = expr` (body) | `compute name : T = expr` |
| `name : T <- read X { … }` | `read name : T = read X { … }` (canonical read node) |
| `name <- effect X { … }` | the canonical effect node (non-pure; later slice) |
| `-> (d: Decision)` + body `d = …` | `compute d` (if needed) + `output d : Decision` |

**`=` (Q6):** a deterministic pure **`compute`** node. **`<-` (Q7):** an explicit **host/world-boundary**
node; **RHS must be a boundary form** (`read …` / `effect …`), *never* an arbitrary expression guessed by
name (Q8) — the glyph promises a boundary, so the RHS must be one. Output names may be assigned by **either**
glyph (Q5): a pure output uses `=`, a boundary output (e.g. `receipt <- effect …`) uses `<-`.

**Independence from `let` (Q15, Q16):** body bindings desugar to `compute`/`read` **directly**, not to block
`let`. So `let` stays reserved for **branch/block-local** names inside `if`/`match` arms (the
`MATCH-ARM-BINDINGS` work); the contract body uses bare graph bindings. The `=`-only slice therefore has
**no dependency** on `MATCH-ARM-BINDINGS-P2` or `RECORD-SPREAD-P2`.

## 6. Invariants & diagnostics (Q9, Q10, Q11, Q12)

- **`pure ⟹ no `<-`** (Q9): a `pure contract` (default modifier) with a `<-` binding → error (new rule,
  `OOF-PURE-BOUNDARY` or reuse). This makes purity *typecheckable from the surface* — a pure contract is
  visibly arrow-free.
- **multi-output** (Q10): every name in `-> (…)` must be assigned **exactly once** in the body; missing →
  `OOF` "output not provided"; assigned-but-not-in-signature non-output bindings are intermediates (allowed).
- **duplicate body node** (Q11) → error; **unused intermediate** → soft diagnostic (warn), not error.
- **source order** (Q12): semantically **order-independent** — the body is a DAG resolved by dependency
  (the emitter already lowers a body to a dependency-ordered chain). Source order is for **readability +
  diagnostics only**; two independent bindings have no order, and the surface must **not** imply sequencing.

## 7. Pressure-test (Q2, five+ examples)

```ig
-- pure single-output
pure contract RenderPage(req: Request) -> (d: Decision) {
  d = Render { status: 200, artifact_json: req.body }
}
-- pure with intermediate node
pure contract RenderPage(req: Request) -> (d: Decision) {
  body : Body = Prepare { req: req }
  d = Render { status: 200, artifact_json: body }
}
-- multi-output
pure contract BuildPage(req: Request) -> (status: Integer, body: String) {
  status = 200
  body   = req.body
}
-- read-heavy + effect (NON-pure; <- carries the boundary; auditor scans the two arrows)
contract SettleOrder(order_id: String) -> (charge: Money, receipt: Receipt) {
  order   : Order <- read Order { id: order_id }   -- external state IN
  charge  : Money  = Price { order: order }         -- pure derive
  receipt         <- effect Settle { order_id: order_id, charge: charge }  -- effect OUT
}
-- relational QueryPlan (pure intent; reads like a node signature)
pure contract ListTodosByAccount(account_id: String) -> (plan: QueryPlan) {
  filters : Collection[QueryFilter] = [ MakeFilter("account_id", "eq", account_id) ]
  plan = { source: "todos", op: "select", projection: ["id","title"], filters: filters, limit: 50 }
}
```
Every one preserves "contract = graph boundary, not function": the signature is the boundary, each binding
is an addressable node, `pure` is arrow-free, the boundary crossings are the two visible `<-` in
`SettleOrder`. **This faithfully keeps the model** (Q2).

## 8. SIR parity & node identity (Q14)

The decisive test: the signature form and its explicit desugaring produce a **byte-identical SemanticIR**
(same node ids, same kinds, same source-map joins). `RenderPage` (signature) ≡ `RenderPage` (explicit) at
the SIR level; `name = expr` ≡ `compute name = expr`; `name <- read …` ≡ `read name = read …`. **No new SIR
node kind.** Node-identity preserved → JetBrains nav / receipts / time-travel unaffected.

## 9. Alternatives (Q-compare)

| # | Form | Verdict |
|---|---|---|
| A | keep only explicit `input/compute/output` | honest but verbose — the status quo this card relieves |
| **B** | signature surface, `=`-only (pure) | **first slice** — covers pure contracts; smallest; no `read`/effect story needed; independent of other lane cards |
| C | universal `<-` binding | **reject** — imports monadic/channel "sequencing/effect" connotation onto pure DAG nodes; glyph carries no info when universal |
| **D** | semantic split `=` pure / `<-` boundary | **recommended target** — the glyph difference is real audit information; stage **after** B, once canonical read/effect node semantics are pinned |
| E | function-like with `let` | reject for the body — `let` is reserved for branch/block-local names; body uses bare graph bindings |

## 10. Implementation test matrix (Q19) → `LAB-LANG-SIGNATURE-BOUND-CONTRACT-SURFACE-P2`

**P2 = the `=`-only pure slice (Alternative B):**
1. parse `pure contract A(x: X) -> (y: Y) { y = F { x: x } }`;
2. desugar = byte-identical SIR to the explicit form (parity test);
3. intermediate bindings (`b : T = …`) become `compute` nodes; node ids/source-map preserved;
4. multi-output: each signature output assigned once; missing/duplicate/extra → correct diagnostics;
5. signature-less contracts unchanged (back-compat);
6. `<-` in a (default-pure) signature contract → `OOF` (forbidden), proving the invariant even before the
   boundary slice ships;
7. existing contract fixtures + IgWeb lowering green; `git diff --check` clean.

**Later slice (`…-P3`):** semantic `<-` for `read`/`effect` boundary bindings, after canonical read/effect
node semantics are fully pinned (it touches the host-boundary surface, higher weight).

## 11. Does it reduce app-authoring pressure? (Q17)

Yes: every `.ig` handler (IgWeb, ViewArtifact helpers, relational intents) drops the `input`/`compute`/
`output` scaffolding for the common pure case. A 3-line `RenderPage` becomes 1 body line. The `=`/`<-` split
additionally makes the **effect surface scannable** (the verify-first/audit win). It does not change
`.igweb`/ViewArtifact schemas — it improves the `.ig` they lower to.

## 12. Non-goals (Q18) & closed scope

**Excluded from this surface (routed to future cards):** `?` fallible propagation
(`LAB-LANG-FALLIBLE-BINDING-READINESS-P1`); collection comprehensions
(`LAB-LANG-COLLECTION-COMPREHENSION-READINESS-P1`) — both deferred so the first signature surface stays the
boundary + `=`/`<-` only. No optional fields/defaults (record-ergonomics card, canon-gated). No effect
execution change. No IgWeb syntax change. No canon claim. **Glyph discipline:** no new glyph beyond `=`/`<-`
unless it classifies a distinct real graph property (`?` would — but it's a separate card).

**Dependencies:** the **B (`=`-only) slice depends on neither** `MATCH-ARM-BINDINGS-P2` nor
`RECORD-SPREAD-P2` (body bindings → `compute` directly). The **D (`<-`) slice** depends on canonical read/
effect node semantics being pinned, not on the other lane cards.

---

*Readiness/design only. Compiled 2026-06-20; grounded in live `parser.rs` (header has no param list; `read`/
`stream`/`compute`/`output` body decls; modifiers incl. `pure`), `typechecker.rs` (no strict pure⟹no-read
enforcement today), and the lexer (`<-` is a clean new token; `?` already tokenized). Recommendation: ship
the `=`-only pure signature surface first (no cross-card deps), add semantic `<-` after read/effect node
semantics are pinned. Surface = boundary + `=`/`<-`; `?` and comprehensions are separate cards.*
