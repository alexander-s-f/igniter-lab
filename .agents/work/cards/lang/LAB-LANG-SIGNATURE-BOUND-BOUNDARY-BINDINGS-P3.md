# LAB-LANG-SIGNATURE-BOUND-BOUNDARY-BINDINGS-P3 - Semantic boundary binding surface

Status: CLOSED
Lane: parallel / language-surface / app-pressure
Type: readiness-design
Delegation code: OPUS-LANG-SIGNATURE-BOUND-BOUNDARY-BINDINGS-P3
Date: 2026-06-21
Skill: idd-agent-protocol

## Context

`LAB-LANG-SIGNATURE-BOUND-CONTRACT-SURFACE-P2` implemented the compact pure surface:

```ig
pure contract RenderPage(req: Request) -> (d: Decision) {
  d = Render { status: 200, artifact_json: req.body }
}
```

as parser-only desugar to canonical `input` / `compute` / `output`.

The design discussion then sharpened the role of `<-`:

- `=` should remain pure derivation / graph definition;
- `<-` should not be a universal binding glyph;
- `<-` is only worth introducing if it marks a real boundary: read/external state/effect continuation;
- `pure contract` must reject `<-` if `<-` means crossing determinism/authority.

Meanwhile TodoApp pressure now has concrete boundaries:

- read query intent (`QueryPlan`) is app-authored but host-executed;
- write intent (`WriteIntent`) is app-authored but host-executed;
- `via` / `guard` remain pure and cannot perform IO;
- `ReadThen`/staged host read is designed but not a general language primitive;
- final `InvokeEffect` is an app decision, not body-side IO.

## Goal

Produce a crisp readiness decision for semantic boundary bindings:

```ig
contract SettleOrder(order_id: String) -> (charge: Money, receipt: Receipt) {
  inventory : Inventory <- read Inventory { key: order_id }
  charge    : Money     = Price { inventory: inventory }
  receipt              <- effect Settle { order_id: order_id, charge: charge }
}
```

The card must decide whether `<-` belongs in core `.ig` now, what it desugars to, and which smallest
implementation slice is safe under current language/runtime facts.

Do not implement syntax in this card unless live code proves the semantics are already pinned tightly
enough for a parser-only proof. Default posture: readiness first.

## Verify First

Read live surfaces before deciding:

- `lang/igniter-compiler/src/{lexer,parser,typechecker,emitter}.rs`
- `lang/igniter-compiler/tests/signature_contract_surface_tests.rs`
- `lang/igniter-compiler/tests/fallible_binding_tests.rs`
- `lang/igniter-compiler/tests/collection_comprehension_tests.rs`
- `server/igniter-web/examples/todo_postgres_app/todo_handlers.ig`
- `server/igniter-web/tests/todo_postgres_api_read_write_e2e_tests.rs`
- `server/igniter-web/src/lib.rs`
- `runtime/igniter-machine/src/postgres_{read,write}.rs`
- `runtime/igniter-machine/IMPLEMENTED_SURFACE.md`
- `lab-docs/lang/lab-lang-signature-bound-contract-surface-p2-v0.md`
- `lab-docs/lang/lab-igniter-web-read-guard-host-readiness-p5-v0.md`
- `lab-docs/lang/lab-igniter-web-read-guard-host-p6-v0.md`
- `lab-docs/lang/lab-igniter-web-effect-host-write-p4-v0.md`

Confirm or correct:

- whether there is already a canonical `read` AST/SIR node;
- whether existing effect surfaces are declarations/intents, final decisions, or body expressions;
- whether `<- read ...` can be parser-desugared to existing canonical constructs;
- whether `<- effect ...` would incorrectly imply body-side IO today;
- whether `<-` should be limited to non-`pure contract`, or whether it needs a new contract qualifier;
- how this interacts with `?`, `guard`, `ReadThen`, and `InvokeEffect`.

Live code wins over this card.

## Questions To Answer

1. What exact semantic property does `<-` mark?
2. Is `<-` about "external value enters graph", "effect leaves graph", both, or neither?
3. Does current `.ig` have canonical read/effect body nodes to desugar into?
4. If no, should P4 first introduce only syntax diagnostics / reserved token?
5. Should `pure contract` reject `<-` parse-time, typecheck-time, or both?
6. Does non-pure `contract` already mean "may contain boundary bindings", or is a new qualifier needed?
7. How does `<-` differ from final `InvokeEffect` decisions in IgWeb?
8. How does `<- read` differ from `QueryPlan` + host `ReadThen`?
9. Can `<-` be expressed without giving `.ig` a DB/file/network handle?
10. What is the smallest TodoApp-motivated example that benefits from `<-`?
11. What are the exact diagnostics for using `<-` in unsupported positions?
12. What would be the P4 implementation slice if readiness says yes?

## Candidate Alternatives

### A. Reserve `<-` only; no behavior yet

Lexer/parser recognize `<-` and emit a crisp "boundary bindings are not implemented" diagnostic.

Pros: prevents accidental syntax drift; cheap.
Cons: no ergonomic gain; can be process noise.

### B. `<- read` lowers to staged read intent

`x <- read Todos { ... }` is sugar for app-authored query + host-staged continuation.

Pros: direct TodoApp pressure.
Cons: likely requires new staged semantics, not parser-only.

### C. `<- effect` lowers to final decision/effect intent

`receipt <- effect Settle { ... }` models a host-executed mutation.

Pros: visually marks authority crossing.
Cons: body expects a value after an effect; current `InvokeEffect` is final and returns no in-body result.

### D. Keep `<-` out of core for now

Use signature-bound `=`, `?`, comprehensions, and IgWeb staged decisions; revisit after real app pressure.

Pros: avoids false monadic/IO semantics.
Cons: leaves read/effect boundaries less visually scannable.

### E. Readiness says "yes, but only after new canonical boundary node"

Define a canonical SIR/body node first; `<-` becomes surface only after that.

Pros: honest semantics.
Cons: bigger language lane.

## Required Acceptance

- [x] Live code inventory completed; stale docs do not decide the answer.
- [x] Exact current canonical constructs for read/effect listed (`BodyDecl::Read` fixed-source decl; `Capability`/`Effect` metadata; `InvokeEffect` terminal decision).
- [x] Decision: `<-` is **deferred** (not parser-only — no canonical node to desugar into).
- [x] `pure contract` invariant: must reject `<-` (parse+typecheck) if/when introduced; moot until then.
- [x] `<- effect` decision: **rejected** (`InvokeEffect` is terminal — returns no in-body value).
- [x] `<- read` vs `ReadThen`: does NOT compose as a body binding (reads are 2-dispatch staged; ReadThen is host-layer, unimplemented).
- [x] Five alternatives compared (A–E).
- [x] Recommended next slice named/scoped: `LAB-IGNITER-WEB-READTHEN-SURFACE-P*` (not a `<-` impl).
- [x] TodoApp example in current (works) and proposed (`<-`, doesn't work under current VM) syntax.
- [x] Authority statement: `.ig` still gets no handle/DSN/passport.
- [x] No implementation (readiness only).
- [x] No canon claim.

---

## Closing Report (2026-06-21)

**Decision: DEFER `<-` from core `.ig` (Alternative D); route the real pressure to a staged-read surface
lane; `<- effect` REJECTED on current semantics.** Deliverable:
`lab-docs/lang/lab-lang-signature-bound-boundary-bindings-p3-v0.md`.

**Why (live-code grounded):**
- `BodyDecl::Read { name, type_annotation, from: String, … }` is a **fixed-source declaration with no RHS
  expression** — the example's app-authored `read Inventory { key: … }` intent cannot desugar into it.
- `<-` is **not tokenized**; `InvokeEffect { target, input, idempotency_key }` is a **terminal Decision**
  returning nothing into the body; `ReadThen` is designed but unimplemented.
- Reads are **staged across two `dispatch()` calls** (app `QueryPlan` → host executes → continuation
  dispatch). A body-level `<- read` implies **mid-dispatch suspend/resume IO the single-`dispatch()` VM does
  not have**. The example's `inventory <- read … ; charge = … ; receipt <- effect …` is **monadic
  do-notation over host IO** — contradicts the pure-graph + staged-host model.
- So `<-` is **not a parser-only desugar**, and `<- effect` would **lie** (effects are terminal).

**Key insight:** the just-landed **`?`** already gives the linear, scannable shape for **pure fallible
chains**; `<-` is only needed for the **IO-staged** case — which belongs in the **ReadThen (host) lane**, not
core `.ig`.

**Authority unchanged:** `.ig` still gets no handle/DSN/passport; reads/writes stay app-authored intents,
host owns execution.

**No code changed** (readiness). **Next (recommended):** `LAB-IGNITER-WEB-READTHEN-SURFACE-P*` — author the
p6-proven two-dispatch staged read as a host-layer decision. Revisit core `<-` only after that yields a
canonical staged-boundary node (Alternative E).

## Required Proof Doc

Create:

```text
lab-docs/lang/lab-lang-signature-bound-boundary-bindings-p3-v0.md
```

It must include:

- live facts with file references;
- the chosen meaning of `<-`;
- accepted/rejected alternatives;
- TodoApp pressure example;
- exact diagnostics for unsupported cases;
- P4 recommendation;
- closed surfaces.

Update this card with a closing report.

## Closed Scope

- No broad effect system.
- No DB/file/network handle inside `.ig`.
- No ORM/SQL syntax.
- No production runner change.
- No VM execution change unless this card explicitly becomes implementation after verify-first.
- No promise that `<-` is canon.

## Suggested Next

If P3 says "yes":

```text
LAB-LANG-SIGNATURE-BOUND-BOUNDARY-BINDINGS-P4
```

If P3 says "not yet":

```text
LAB-IGNITER-WEB-READTHEN-SURFACE-P*
```

or a smaller diagnostic/reservation card for `<-`.
