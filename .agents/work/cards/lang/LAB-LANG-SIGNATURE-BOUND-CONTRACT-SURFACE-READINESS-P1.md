# LAB-LANG-SIGNATURE-BOUND-CONTRACT-SURFACE-READINESS-P1 - Compact contract surface with graph signatures

Status: CLOSED
Lane: parallel / surface-ergonomics
Type: readiness / design
Delegation code: OPUS-LANG-SIGNATURE-BOUND-CONTRACT-SURFACE-P1
Date: 2026-06-20
Skill: idd-agent-protocol

## Context

Application pressure is now real enough that the canonical `input` / `compute` / `output` form feels
accurate but verbose for simple app contracts.

Example today:

```ig
pure contract RenderPage {
  input req : Request
  compute d : Decision = Render { status: 200, artifact_json: req.body }
  output d : Decision
}
```

Candidate compact surface:

```ig
pure contract RenderPage(req: Request) -> (d: Decision) {
  d = Render { status: 200, artifact_json: req.body }
}
```

Important design intuition:

- `(inputs...) -> (outputs...)` is not a "function return" in the ordinary language sense;
- it is a compact declaration of the contract graph boundary;
- each body binding is still an addressable graph node, not an imperative assignment;
- canonical `input` / `compute` / `read` / `output` remains the audit / graph-readable form.

During discussion, one stronger idea emerged: use two binding operators with real semantic content:

```ig
name : Type = pure_expr
name : Type <- boundary_expr
```

where `=` lowers to deterministic `compute`, while `<-` is reserved for explicit host/world boundary nodes
such as `read ...` or future effect-producing primitives. `pure contract` should reject `<-`.

This card should pressure-test that surface before implementation.

## Organizing Principle

The body is a graph. A binding glyph earns syntax only if it classifies a real, checkable property of a graph
edge/node binding.

Recommended v0 discipline:

| Glyph | Meaning | Canonical lowering |
|---|---|---|
| `=` | deterministic dataflow / pure derivation | `compute` |
| `<-` | explicit host/world boundary | `read` or future approved effect-boundary node |

Future glyphs must earn their place the same way. Two known candidates are **out of scope for this card**:

- `?` as fallible short-circuit binding / expression sugar over `Result` or `Option`;
- collection comprehensions as sugar over `map` / `filter`.

Both may be valuable, but they should not be smuggled into the first signature-bound surface. This card is
only about boundary signatures and the `=` vs `<-` split.

## Goal

Design the smallest signature-bound contract surface that:

1. stays a deterministic projection to canonical `.ig`;
2. preserves graph node identity, source maps, diagnostics, and SIR parity;
3. supports multi-input and multi-output contracts;
4. makes purity / host-boundary crossings visually and typecheckably explicit;
5. does not imply imperative sequencing or hidden mutation.

## Verify First

Read live surfaces before writing the packet:

- `lang/igniter-compiler/src/parser.rs`
  - contract headers;
  - input / output declarations;
  - compute declarations;
  - read declarations if present;
  - block bodies / `let` parsing;
- `lang/igniter-compiler/src/typechecker.rs`
  - contract boundary typing;
  - compute/read typing;
  - pure-vs-impure validation if any;
  - duplicate names / output resolution;
- `lang/igniter-compiler/src/emitter.rs`
  - how `input`, `compute`, `read`, and `output` become SIR / emitted graph;
- `lang/igniter-compiler/tests/fixtures` for:
  - pure contracts;
  - multi-output contracts;
  - contracts with reads/effects if any;
  - contracts that use `Decision`, `Render`, `InvokeEffect`, `QueryPlan`, `WriteIntent`;
- current cards/docs:
  - `LAB-LANG-MATCH-ARM-BINDINGS-P2.md`;
  - `LAB-LANG-RECORD-SPREAD-P2.md`;
  - `LAB-LANG-SURFACE-ERGONOMICS-READINESS-P0.md`;
  - `lab-docs/lang/lab-lang-match-arm-bindings-readiness-p1-v0.md`;
  - `lab-docs/lang/lab-lang-record-ergonomics-readiness-p1-v0.md`;
  - IgWeb/Todo docs that show authoring pain (`ViewArtifact`, relational/Todo API).

Confirm or correct:

- whether canonical contracts can already have multiple outputs and how they are represented;
- whether `read` exists as a canonical node kind today or only as proposal/pressure;
- whether `pure contract` currently enforces absence of reads/effects;
- whether body declarations are order-independent or merely parsed in source order;
- whether duplicate node names are already rejected;
- whether a body binding can be desugared to `compute` without changing SIR;
- whether `<-` has lexical conflicts with existing `->`, comparison, or other operators.

Live code wins over this card.

## Candidate Surface

### Pure single-output

```ig
pure contract RenderPage(req: Request) -> (d: Decision) {
  d = Render { status: 200, artifact_json: req.body }
}
```

Desugars to:

```ig
pure contract RenderPage {
  input req : Request
  compute d : Decision = Render { status: 200, artifact_json: req.body }
  output d : Decision
}
```

### Pure with intermediate nodes

```ig
pure contract RenderPage(req: Request) -> (d: Decision) {
  body : Body = Prepare { req: req }
  d = Render { status: 200, artifact_json: body }
}
```

Desugars to explicit `input`, `compute body`, `compute d`, `output d`.

### Multi-output

```ig
pure contract BuildPage(req: Request) -> (status: Integer, body: String) {
  status = 200
  body = req.body
}
```

Every output name must be defined exactly once in the body.

### Host-boundary read / effect sketch

```ig
contract SettleOrder(order_id: String) -> (charge: Money, receipt: Receipt) {
  order : Order <- read Order { id: order_id }
  charge : Money = Price { order: order }
  receipt <- effect Settle { order_id: order_id, charge: charge }
}
```

Rules to pressure-test:

- `=` means deterministic compute node;
- `<-` means explicit host/world-boundary node;
- RHS of `<-` must be an explicit boundary form (`read ...`, `effect ...`, or another approved host-bound
  primitive), never an arbitrary expression guessed by name;
- `pure contract` forbids `<-`;
- both forms still create addressable graph nodes.

## Required Questions

Answer directly:

1. Is this best named "signature-bound contract surface", "compact contract surface", or something else?
2. Does the surface faithfully preserve the model "contract = graph boundary, not function"?
3. What exact grammar is proposed for contract signatures?
4. What exact grammar is proposed for body bindings?
5. Should output names be assignable with `=` only, or can boundary outputs use `<-`?
6. What is the precise meaning of `=`?
7. What is the precise meaning of `<-`?
8. What RHS forms are legal after `<-` in v0?
9. How does `pure contract` reject boundary bindings?
10. How are multi-output contracts checked?
11. How are duplicate body bindings / missing outputs / unused body nodes diagnosed?
12. Does source order matter semantically, or only for readability and diagnostics?
13. How does this desugar to canonical `input` / `compute` / `read` / `output`?
14. What SIR-parity tests prove the desugar is not changing semantics?
15. How does this interact with `let` from `MATCH-ARM-BINDINGS-P2`?
16. Should `let` be reserved for branch/block-local names while contract body uses bare graph bindings?
17. Does this reduce pressure on `.igweb`, ViewArtifact authoring, and relational contracts?
18. What future pressure belongs in separate cards (`?` propagation, collection comprehensions), and why is
    it out of scope here?
19. What is the smallest implementation slice after readiness?

## Alternatives To Compare

### A. Keep only canonical explicit form

Most honest for graph/audit, but app authoring remains verbose.

### B. Signature-bound surface with `=`

Compact and likely enough for pure contracts:

```ig
contract A(x: X) -> (y: Y) { y = F { x: x } }
```

But it needs a separate story for `read` / effect boundaries.

### C. Universal `<-` graph binding

```ig
y <- F { x: x }
```

Visually graph-like, but risks importing monadic/channel semantics and falsely suggesting sequencing/effects
for pure DAG nodes.

### D. Semantic split: `=` pure, `<-` boundary

Preferred candidate if live code supports it: the glyph difference carries real audit information.

### E. Function-like surface with `let`

```ig
contract A(x: X) -> (y: Y) { let y = F { x: x } }
```

Readable, but `let` is better reserved for branch/block-local binding unless readiness proves otherwise.

## Required Deliverable

Create:

```text
lab-docs/lang/lab-lang-signature-bound-contract-surface-readiness-p1-v0.md
```

It must include:

- live grammar/typechecker/emitter findings;
- name recommendation for the surface;
- final candidate grammar;
- desugar rules to canonical `.ig`;
- `=` vs `<-` semantics;
- pure-contract invariant;
- multi-output behavior;
- SIR/source-map/node-identity requirements;
- alternative comparison;
- implementation test matrix;
- explicit non-goals.

Update this card with a closing report.

## Required Acceptance

- [x] Verify-first findings are grounded in live files, not stale memory.
- [x] At least five examples are pressure-tested (pure single, pure intermediate, multi-output, read+effect, relational QueryPlan).
- [x] The packet clearly states whether `<-` is semantic or rejected/deferred (semantic; staged after the `=`-only slice).
- [x] The packet clearly states whether `let` belongs in contract body or only nested blocks (only nested blocks; body uses bare graph bindings).
- [x] The packet states the glyph discipline: no new glyph unless it carries a real graph property.
- [x] The packet explicitly excludes `?` propagation and collection comprehensions from this slice.
- [x] The packet defines SIR parity expectations.
- [x] The packet defines diagnostics for missing output, duplicate output, duplicate body node, and illegal `<-` in pure contract.
- [x] The packet names dependencies on `MATCH-ARM-BINDINGS-P2`, `RECORD-SPREAD-P2`, or neither (`=`-only slice: neither).
- [x] No code is changed.
- [x] No canon claim is made.

---

## Closing Report (2026-06-20)

**Deliverable:** `lab-docs/lang/lab-lang-signature-bound-contract-surface-readiness-p1-v0.md` — readiness/
design, **no code**. Answers Q1–Q19, pressure-tests 5 examples, defines grammar + desugar + invariants.

**Decisive live findings:**
- contract header today is `[modifier] contract Name [type-params] { body }` — **no param list** → the
  `(in) -> (out)` signature is a clean new header;
- canonical body kinds are `input/read/stream/compute/output` (so `read` is a real node, not just proposal);
- **`<-` is not a lexer token** (`->`,`=>`,`=`,`?` exist; no `LeftArrow`) → clean to add; `?` already
  tokenized → confirms it belongs to a *separate* fallible-binding card;
- `let`/`BlockBody` exist but `let` doesn't bind (`OOF-P1`) → **body bindings must desugar to `compute`/
  `read` directly, NOT through `let`**;
- `pure` modifier exists (default) but doesn't strictly forbid `read` today → `pure ⟹ no <-` is a **new
  checkable rule** the surface adds.

**Recommendation:** ship the **`=`-only pure signature surface first** (Alternative B) — body binding
`name [:T] = expr` → `compute`; signature params → `input`; signature outputs → `output`; byte-identical
SIR; **no dependency** on match-arm or record-spread (bindings → `compute` directly, sidestepping the broken
`let`). Then add **semantic `<-`** (Alternative D: `=` pure / `<-` host-boundary `read`/`effect`, RHS must be
a boundary form, `pure` forbids `<-`) as a later slice once canonical read/effect node semantics are pinned.

**Glyph discipline reaffirmed:** `=` (pure compute) and `<-` (boundary) each classify a real graph edge;
`?` propagation and comprehensions are **explicitly excluded** (separate cards). `let` stays branch/block-
local; contract body uses bare graph bindings.

**Next:** `LAB-LANG-SIGNATURE-BOUND-CONTRACT-SURFACE-P2` (the `=`-only pure slice — parse + desugar + SIR
parity + multi-output diagnostics + `<-`-in-pure rejection). The `<-` boundary slice and the deferred `?`/
comprehension cards follow.

## Closed Scope

- No implementation.
- No parser changes.
- No typechecker changes.
- No IgWeb syntax changes.
- No effect execution changes.
- No `?` propagation / fallible binding implementation or design beyond routing it to a future card.
- No collection comprehension syntax.
- No live Postgres.
- No ViewArtifact schema changes.
- No optional fields/defaults.
- No canon claim.

## Suggested Next

If readiness confirms the surface, open a narrow implementation proof:

```text
LAB-LANG-SIGNATURE-BOUND-CONTRACT-SURFACE-P2
```

Recommended P2 should likely support pure contracts first:

```ig
pure contract A(x: X) -> (y: Y) { y = F { x: x } }
```

Then a later slice can add semantic `<-` for read/effect boundaries after live canonical read/effect node
semantics are fully pinned down.

Separate future cards, if pressure remains:

```text
LAB-LANG-FALLIBLE-BINDING-READINESS-P1
LAB-LANG-COLLECTION-COMPREHENSION-READINESS-P1
```
