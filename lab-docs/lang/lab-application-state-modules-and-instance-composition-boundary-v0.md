# LAB-APP-STATE-P1: Application State, Modules, and Instance-Composition Boundary

**Track:** `lab-application-state-modules-and-instance-composition-boundary-v0`
**Status:** OPEN → CLOSED (research report complete)
**Route:** RESEARCH / DESIGN BOUNDARY / NO IMPLEMENTATION
**Recommendation status:** **research-only → proof candidate** (NOT design-ready; no keyword adopted)
**Authority:** No implementation authority. No canon claim. No stable API. No runtime state-holder authorization. No public framework claim.

---

## 0. Reading frame

This is a **derive-from-pain** analysis, not a solution proposal. It deliberately does
**not** assume the answer is a `state` keyword, a `service`, an actor, module visibility,
or host-owned state. It compares five routes and recommends the cheapest one that buys
real clarity, plus an exact next card. The purpose of P1 is to **prevent premature
design lock**.

Six terms are kept distinct throughout (acceptance bar):

| Term | Definition | Where it lives **today** |
|------|-----------|--------------------------|
| **State value** | An immutable typed snapshot of a fact at one instant (the document text at T). | First-class — `type` records (PROP-015 §2.5). |
| **State instance** | Identity of a fact over time ("editor doc #42"), distinct from other instances of the same shape. | **Nowhere in source.** Types are structural; modules are not instantiable. |
| **State holder** | The thing that owns the current value and applies transitions across invocations. | **Outside the language** — a store/host reached via `read … from "store"` + lifecycle. |
| **Transition** | `value_{t+1} = f(value_t, event)`. | Expressible as a contract (`f`), but the *application of f to a held value over time* is not in-language. |
| **Module boundary** | Namespace + purity/fragment-class authority. | First-class (PROP-015) — but **not** a holder, **not** visibility, **not** an instance. |
| **External capability** | Injected authority to touch an external/durable holder. | First-class (PROP-035/046) — `capability x: IO.StorageCapability`. |

The single sentence the rest of the report defends:

> **Igniter already has a state-*lifetime* vocabulary but no state-*holder*. It pushes
> holding outside the language and treats contracts as pure transforms over snapshots.
> The "flat application" pain is not missing state — it is that the *composition* of
> (stateful facts + their lifetimes + their holders + the public operations that
> transition them) is invisible in source.**

---

## 1. Problem statement

### 1.1 The flat-application surface problem

At the contract scale Igniter is strong: a contract is a typed, classified, provable
transform with an explicit effect character (Ch10) and an explicit consequence surface
(Ch12). At the **application** scale a real program is still just a *flat list of
contracts plus a host that wires them*. Nothing in source tells a reader (human or
agent):

- which contracts are **public operations** vs **internal helpers**;
- which typed records are **long-lived application state** vs transient compute values;
- **who holds** the current document/cursor/undo-history between events;
- how a **UI/session event** routes to the operation that transitions that state;
- where the **durable boundary** is and which capability crosses it.

A code-editor application makes this vivid: `current_document_text`, `cursor_position`,
`selection`, `clipboard`, `diagnostics`, `undo/redo history`, `open buffers`,
`session preferences`, `background analysis state` — every one of these is a *stateful
fact with identity and a lifetime*, and Igniter today can describe the **value** of each
(a typed record) but not its **instance**, its **holder**, or its **place in the app**.

### 1.2 Local contract semantics vs application architecture semantics

These are different layers and must not be conflated:

- **Local contract semantics** answer: *given these inputs, what output, with what
  effects and what proof?* Fully served today.
- **Application architecture semantics** answer: *what are the app's stateful facts,
  who owns each, how long does each live, which operations move them, and what is
  public?* Served today only **implicitly, in the host wiring** — i.e. not in `.ig`
  source at all.

### 1.3 Why solving the symptom too fast creates debt

The fastest "fix" — a `state { … }` declaration or a `service` object that holds mutable
fields — would import the exact thing the Covenant and the debugger feasibility work
spent their honesty budget to avoid: **hidden mutable identity**. The moment a language
construct *holds and mutates* a value across invocations, three guarantees erode at once:

1. **Honesty / no hidden mutation** — a held mutable field is a side channel the type
   system and the observation stream no longer fully describe.
2. **Debuggability** — the debugger feasibility report's whole model is *node-anchored,
   record-only, post-mortem replay over a value trace*. A mutable holder has no clean
   value to anchor; "what changed and why" stops being reconstructible from the trace.
3. **Proofability** — pure transforms are provable; a stateful object's method is not,
   without dragging in the held state as hidden input.

Ch2 already encodes this caution for syntax (`entrypoint`/`section` are explicitly *not*
reserved early, precisely to avoid locking a meaning before an AST shape is proven). The
same discipline applies to app-state: **name the model before reserving a keyword.**

---

## 2. Existing language inventory

### 2.1 What modules mean (PROP-015)

A `module` is a **compile-time scope + fragment-class authority boundary**. One file =
one module; `module.fragment_class = max(declaration fragment_classes)`; a `:core` module
may not contain or import `:escape` without an explicit `escape` wrapper. Imports are
explicit, acyclic (DAG), no wildcards, no re-export. `module_map` in the compiled program
is **metadata only**.

Modules explicitly do **not** provide: visibility/access modifiers, encapsulation,
instances, state, lifecycle, runtime presence, or any multi-module application
composition. *(Quoted non-goals: "Mutable variables … All bindings are immutable";
multi-file/multi-module composition deferred to PROP-016.)*

→ **Modules are not the holder and are not the composition unit for state.** They are a
namespace + a purity boundary.

### 2.2 What contract modifiers mean (PROP-031 / Ch10)

`pure | observed | effect | privileged | irreversible`, default `pure`. The modifier
declares a contract's **relationship to the outside world** and sets a *minimum*
fragment class. This is the language's existing way of saying "this operation touches
something real" — directly relevant to separating public **effecting** operations from
pure **helpers**.

### 2.3 What the effect surface adds (PROP-035 / Ch12)

For `effect/privileged/irreversible` contracts, seven declared fields — `affects`,
`authority`, `reversibility`, `idempotency`, `receipt`, `failure`, `compensation` — plus
`via <profile>`. The surface **separates the declaration of consequence from the body**:
a reader understands full external impact from the surface alone. The `failure` taxonomy
already includes `unknown_external_state` (reconcile, don't retry) — the epistemic-outcome
vocabulary. **This is the existing model of an external/durable boundary.**

### 2.4 What intent adds (PROP-045)

`intent "…"` at module and contract sites — **metadata-only, queryable purpose**,
preserved into SemanticIR as `intent_text`, semantically inert (not in the behavior
digest, not capability, not proof). Convention-only today (parser impl not yet
authorized). **This is the existing model for making a contract's *role* inspectable to
agents/tools without changing behavior** — a direct precedent for "make the app model
inspectable without making it active."

### 2.5 What lifecycle vocabulary exists (Ch2 grammar)

The most under-appreciated existing surface. `read`, `snapshot`, and `output`
declarations accept a `LifecycleAnn`:

```
LifecycleClass := :local | :session | :window | :durable | :audit
ReadDecl       := "read" Name ":" TypeRef "from" StrLiteral LifecycleAnn?
WindowDecl     := "window" StrLiteral "{" kind | unit | on_close ... "}"
```

So the language **already names state lifetimes** (`:session`, `:window`, `:durable`)
and **already names where external data enters** (`read … from "<store>"`) and **already
names time-bounded scopes** (`window`). What it does *not* do is bind a *named app fact*
to a lifecycle scope and a holder; the annotation today describes the *provenance/retention
of a value read into one contract*, not the *ownership of a fact across the app*.

### 2.6 What capability surfaces add (PROP-035 / PROP-046)

Capability-as-value: `capability c: IO.StorageCapability`, injected, used by `effect …
using c`, with **denial-as-data** (LAB-STORAGE-CAPABILITY-P2: gates → `denied`/`query_error`,
receipts are evidence-only, not authority). **This is the existing model for crossing the
durable boundary under explicit, inspectable authority.**

### 2.7 What is missing

| Capability needed for app architecture | Present? |
|----------------------------------------|----------|
| Typed state **value** | ✅ `type` records |
| State **lifetime** vocabulary | ✅ lifecycle annotations (§2.5) |
| External/durable **boundary** | ✅ effect surface + capabilities |
| Contract **effect character** (public-effecting vs pure-helper signal) | ✅ modifiers |
| Queryable **role/purpose** metadata | ✅ intent (convention) |
| State **instance identity** in source | ❌ |
| Named **stateful fact** bound to a holder + lifetime, app-wide | ❌ |
| **Transition** as a first-class app concept (event → operation → next state) | ❌ (expressible as a contract; not assembled in source) |
| **Public-vs-internal** composition boundary | ❌ (no visibility; intent hints only) |
| **App composition / assembly** artifact | ❌ (`module_map` is metadata, not an app graph) |

The gap is **the middle three rows**: identity, named-fact-with-holder, and assembly.
Everything else already exists and should be *reused*, not re-invented.

---

## 3. Application pressure model

### 3.1 Primary pressure case — the code editor

Mapping the motivating facts onto the six-term model:

| App fact | State value (type) | Instance identity | Natural holder | Lifetime | Transition trigger | Boundary |
|----------|-------------------|-------------------|----------------|----------|--------------------|----------|
| document text | `Document{text,…}` | which open doc | host buffer | `:session`/`:window` | edit/insert/delete event | durable on save |
| cursor position | `Cursor{line,col}` | per editor view | host (hot) | `:local`/`:window` | move/click event | none |
| selection | `Selection{…}` | per view | host (hot) | `:local` | select event | none |
| clipboard | `Snippet{text}` | per session | host/OS | `:session` | copy/cut | OS boundary |
| diagnostics | `Collection[Diagnostic]` | per doc | host (derived) | `:window` | analysis completes | none (derived) |
| undo/redo history | `History{stack…}` | per doc | host | `:session` | any edit | none |
| open tabs/buffers | `Collection[Buffer]` | per workspace | host | `:session` | open/close | durable (workspace) |
| preferences | `Prefs{…}` | per user | store | `:durable` | settings change | durable |
| background analysis | `AnalysisState{…}` | per doc | host (async) | `:window` | analysis tick | observed |
| filesystem/persistence | files | per path | external store | `:durable` | save/load | **capability** |
| UI event routing | events | — | host | transient | — | host responsibility |

Two structural observations fall out immediately:

1. **Holders cluster into a small set of lifetime-scoped classes** — *hot per-view*
   (`:local`), *session* (`:session`/`:window`), *durable/store* (`:durable`). These
   line up almost exactly with the **existing lifecycle vocabulary** (§2.5). The editor
   does not demand a new holder taxonomy; it demands that named facts be *bound* to the
   existing one.
2. **"UI event routing" and the hot holder are host responsibilities, not language
   responsibilities.** Cursor-move at keystroke rate must never become an `effect`
   contract round-trip. This is a hard boundary: the language should *describe* these
   facts and *type their transitions*, but must not try to *hold or pump* them.

### 3.2 Non-editor pressure case — Query/Storage (LAB-QUERY / LAB-STORAGE)

The query track already demonstrates the recommended split **without any state holder**:

- **State value:** `QueryPlan` (nested typed records, `Collection[FilterPredicate]`) —
  pure data, fully constructible in source (closed by LAB-TC-ARRAY-P1/P2).
- **Transition / operation:** `ExecuteQuery` (Stage 2+) is an `effect` contract whose
  effect surface declares the storage boundary; the *plan* is pure, the *execution* is
  the only thing that crosses the boundary.
- **Holder:** the database — strictly external, reached via `IO.StorageCapability`.
- **Outcome:** `QueryResult` KDR (`rows|empty|denied|query_error|system_error`),
  **denial-as-data**, receipts evidence-only.

This is the proof that **"pure plan/value in source + effecting transition at an explicit
capability boundary + result-as-data"** is a viable, already-validated app shape. The
editor's `save` is structurally identical to `ExecuteQuery`.

### 3.3 Secondary pressure case — Epistemic Outcome (LAB-EPISTEMIC-OUTCOME)

Reinforces that **transitions across an external boundary can fail in non-binary ways**:
`unknown_external_state` (lost commit-ack) is a first-class outcome requiring
reconciliation, not retry. Any app-state model whose transitions touch durable holders
**must** preserve this outcome vocabulary rather than collapsing to success/failure.
A held-mutable-object model tends to lose it (the object "just has" the new value); a
value-transition-with-receipt model keeps it.

### 3.4 Recurring entities (normalized)

| Entity | Editor example | Query/Storage example | Today's home |
|--------|----------------|------------------------|--------------|
| app operation (public) | `ApplyEdit`, `Save` | `ExecuteQuery` | contract (modifier signals effecting) |
| helper (internal) | `clampCursor`, `diffText` | `BuildFilterPredicate` | `pure contract` / `def` |
| stateful fact | document, cursor, history | (query is stateless; result is) | typed record + **(no app binding)** |
| event/command | keystroke, paste | run-query request | input to a contract; **routing is host** |
| external boundary | OS clipboard, analysis | DB | effect surface / capability |
| durable boundary | save file, prefs | DB commit | `:durable` + capability |
| UI/session boundary | view, tabs | — | **host** (out of language scope) |
| observation/debugging boundary | diagnostics, trace | receipt/observation stream | observation sink + receipts |

---

## 4. Design alternatives

Five routes, ordered from least to most language change. All five keep the **holder
external** (no runtime state holder is authorized, and the honesty analysis in §1.3 argues
it should stay that way). They differ on **how much of the app model is in source** and
**how state is modeled**.

### Route A — Host-Owned State + Pure Reducers (status-quo discipline)

**Source shape:**
```igniter
-- state values are plain typed records; transitions are pure contracts
pure contract ApplyEdit {
  input  doc   : Document
  input  edit  : EditEvent
  compute next = ...            -- next document value
  output next  : Document
}
```
The host holds `Document`, feeds `(doc, edit)` in, stores the returned `next`.

- **Owns state:** host/store, entirely. **Instance:** host key. **Transition:** pure
  reducer contract. **Public/internal:** modifier + intent convention. **Capability:**
  existing effect surface for `Save`. **Debugger:** trivially honest — every state is a
  value in a trace.
- **Risks:** the app architecture stays *invisible in source* — the flat-surface problem
  is **not** solved, only kept clean. **Makes harder:** agent/human comprehension of "what
  is this app's state model" from `.ig` files alone.

### Route B — Descriptive State Vocabulary (inspectable, non-holding)

**Source shape (candidate future surface — framed as candidate only, not proposed):**
```igniter
-- a DESCRIPTIVE block: names app facts, binds each to lifetime + holder-class.
-- compiles to metadata (like module_map / intent_text). Holds nothing.
app_state EditorSession {
  fact document   : Document            lifecycle :session holder :host
  fact cursor     : Cursor              lifecycle :local   holder :host
  fact prefs      : Prefs               lifecycle :durable holder :store
  fact history    : History             lifecycle :session holder :host
}
```
Transition contracts reference facts by name in `intent`/metadata; the host still holds.

- **Owns state:** host/store (unchanged). **Instance:** still external key; the *schema*
  is named in source. **Transition:** pure/effect contracts as in A. **Public/internal:**
  facts + which operations declare they transition them. **Capability:** `holder :store`
  facts route through capabilities. **Debugger:** can render the declared state shape and
  join it to the value trace by fact-name.
- **Risks:** descriptive-only invites the expectation that it *holds* state; must
  fail-closed on that (it is metadata, like intent). **Makes harder:** nothing — purely
  additive description.

### Route C — Capability-Carried State Handles (state as a capability)

**Source shape:** model a long-lived fact as a capability to its holder, reusing PROP-035/046:
```igniter
observed contract ReadDocument  { capability d: IO.DocumentState  ... output doc: Document }
effect   contract WriteDocument { capability d: IO.DocumentState
  affects internal DocumentHolder  reversibility :reversible
  idempotency natural  receipt EditReceipt  failure EditFailure  ... }
```
- **Owns state:** the capability *provider* (host) — but every touch is an explicit
  observed-read / effect-write with a receipt. **Instance:** *which capability value is
  injected*. **Transition:** effect contract with full effect surface. **Public/internal:**
  effect contracts public, pure helpers internal. **Capability:** native — this *is* the
  capability model. **Debugger:** every read/write is an observation/receipt — maximally
  honest and already in the trace.
- **Risks:** turns *every* state touch into ESCAPE/effect — fatal for hot editor state
  (cursor at keystroke rate); capability proliferation; **drift risk:** if a handle
  accumulates operations it becomes an object/actor by the back door. **Makes harder:**
  cheap in-memory transitions; pure-fragment composition.

### Route D — Composition Manifest / App Assembly (`.igapp`)

**Source shape:** contracts/modules unchanged; add a *separate* declarative assembly that
wires facts ↔ events ↔ public operations ↔ capability boundaries, compiled to a
`CompiledApp` descriptor (analogous to `module_map`):
```
app Editor {
  state  document : Document  lifecycle :session  holder host
  on     EditEvent     -> ApplyEdit(document) -> document
  on     SaveCommand   -> Save(document) via storage_profile
  expose ApplyEdit, Save           -- public operations
  internal diffText, clampCursor   -- helpers
}
```
- **Owns state:** holders named in the manifest (host/store). **Instance:** manifest
  instantiation keyed by host. **Transition:** explicit `on event -> operation -> fact`
  edges. **Public/internal:** `expose`/`internal` — the missing visibility boundary, at
  app scope rather than module scope. **Capability:** manifest binds profiles to
  operations. **Debugger:** the manifest *is* the app graph the `ContractDAG`/source-map
  renders.
- **Risks:** a *second language*; framework-drift risk; manifest can rot into config-soup;
  must avoid re-inventing module composition (PROP-016 territory). **Makes harder:** keeping
  the language small; one-file mental model.

### Route E — Lifecycle-Scope Promotion (lean entirely on existing vocabulary)

**Source shape:** introduce *no new construct*; instead **promote the existing lifecycle
annotations into the load-bearing state model** by defining precisely what each class
means as a *holder-scope*, and standardizing `read … from "<scope>" lifecycle :session`
as the canonical way a fact attaches to a scope:
```igniter
contract ApplyEdit {
  read    document : Document from "editor.session" lifecycle :session
  input   edit     : EditEvent
  compute next     = ...
  output  next     : Document lifecycle :session
}
```
- **Owns state:** the scope's holder, defined by the runtime/host contract per lifecycle
  class; the *binding of fact → scope* is in source. **Instance:** the `from "<scope>"`
  string identifies the scope; instance identity still host-keyed. **Transition:**
  read-current → compute-next → output-to-scope. **Public/internal:** unchanged (modifier/
  intent). **Capability:** `:durable` scopes route through capabilities. **Debugger:**
  reads/outputs already observable; lifecycle class already in IR.
- **Risks:** **conflation** — lifecycle was designed for *provenance/retention of a read
  value*, not *holder identity/ownership*; overloading it risks muddying both meanings.
  **Makes harder:** future divergence of "how long is this kept" from "who owns it" if the
  two are ever needed apart.

---

## 5. Evaluation matrix

Scale: ✅ strong / ◑ partial / ⚠ weak-or-risky. "Drift" rows: ✅ = low drift risk.

| Criterion | A: Host+Reducer | B: Descriptive vocab | C: Capability handle | D: Manifest | E: Lifecycle promote |
|-----------|:---:|:---:|:---:|:---:|:---:|
| Honesty / inspectability | ◑ (clean but invisible) | ✅ | ✅ | ✅ | ✅ |
| No hidden mutation | ✅ | ✅ | ✅ | ✅ | ✅ |
| Agent readability | ⚠ (not in source) | ✅ | ✅ | ✅ | ◑ |
| App ergonomics | ◑ | ✅ | ⚠ (hot-state cost) | ✅ | ◑ |
| Module composability | ✅ | ✅ | ✅ | ◑ (new layer) | ✅ |
| Runtime feasibility | ✅ | ✅ (metadata) | ◑ | ◑ | ✅ |
| VM implications | ✅ none | ✅ none | ⚠ (effect per touch) | ◑ (assembly exec) | ✅ none |
| Proofability | ✅ | ✅ | ✅ | ◑ | ✅ |
| Compat w/ existing contracts | ✅ | ✅ | ✅ | ◑ | ✅ |
| Compat w/ future IDE/textbook | ◑ | ✅ | ✅ | ✅ | ✅ |
| Risk of OOP/actor/framework drift | ✅ low | ✅ low | ⚠ medium | ⚠ medium-high | ✅ low |
| Risk of overfitting to editor | ✅ low | ✅ low | ◑ | ⚠ (manifest shaped by one app) | ✅ low |

**Reading:** A is the honest floor but doesn't solve the stated pain. C and D solve the
most but carry the most drift/VM risk and would lock design early. **B and E are the two
low-risk, additive, no-VM-change routes that make the app model inspectable** — and they
are complementary: E supplies the lifetime/holder *binding mechanism that already exists*,
B supplies the *named, app-wide vocabulary* over it. Neither holds state; both are metadata
in the same spirit as `intent` and `module_map`.

---

## 6. Recommended route

**Recommendation: a staged sequence, anchored on A as the discipline and B⊕E as the next
proof — explicitly NOT adopting a `state` keyword, Route C, or Route D yet.**

- **Stage 0 (now — design-ready as convention, no authority needed):** adopt **Route A**
  discipline as the baseline truth: app state is host/store-held; contracts are pure
  reducers and effecting operations; nothing in the language holds state. This is already
  how Query/Storage works and should be stated as the canonical app shape.
- **Stage 1 (next card — proof candidate):** prototype a **B⊕E hybrid** *proof-locally,
  with zero compiler/parser/VM/keyword changes*: express a code-editor fixture as
  (i) typed state-value records, (ii) pure reducer + effect transition contracts, (iii)
  the state vocabulary captured as **descriptive sidecar metadata** (intent-style /
  fixture metadata) bound to the **existing lifecycle classes**, and show that an agent /
  the feasibility-report debugger model can read the app's state shape and join it to a
  value trace by fact-name. The proof's job is to discover *what is actually missing*
  before any surface is proposed.
- **Defer** Route C (capability-carried handles) and Route D (manifest) until the Stage 1
  proof shows concrete, repeated need that B⊕E cannot express. C is the right model **only
  for the durable boundary** (where it already exists); D is a real candidate **only if**
  the proof shows the wiring genuinely cannot live as sidecar metadata.

**Status of this recommendation:** **research-only → proof candidate.** It is *not*
design-ready (no surface is proven), *not* a keyword adoption, and carries *no*
implementation authority.

**Exact next card:** **`LAB-APP-STATE-P2`** — *proof-local code-editor app-state model*:
build an editor fixture expressing host-owned state values + pure/effect transition
contracts + a descriptive state vocabulary over existing lifecycle classes; validate
inspectability and the six-term separation under real editor pressure; **no compiler,
parser, VM, keyword, or canon changes**. Deliver a gap packet stating exactly which of
{instance identity, fact-holder binding, app assembly, public/internal visibility} the
proof proves *insufficient* as metadata — that gap packet is the gate to any future
proposal-authoring card.

---

## 7. Non-recommendations (tempting, do not adopt yet)

| Tempting design | Why not yet |
|-----------------|-------------|
| A `state { … }` **declaration keyword** | Premature keyword lock. Ch2 explicitly refuses to reserve `entrypoint`/`section` before a proven AST shape; the same caution applies. Name the model (Stage 1 proof) first. |
| **Service object / actor** holding mutable fields | Imports hidden mutable identity → breaks the §1.3 honesty/debuggability/proofability triad. The Covenant + debugger model are built on value-anchored, record-only observation. |
| **Module-as-instance / module-level mutable state** | PROP-015 explicitly rejects mutable bindings and module instances/lifecycle. Modules are scope+purity, not holders. |
| **Host-owned-opaque state with no source vocabulary** (pure Route A, full stop) | Honest but leaves the flat-surface problem unsolved; the app's state model stays unreadable to agents. |
| **Capability-handle for *all* state** (Route C everywhere) | Correct for the durable boundary, fatal for hot in-memory state (keystroke-rate cursor as an effect contract). Use C only at the external/durable edge. |
| **Capability/handle that accumulates operations** | Becomes an object/actor by the back door — OOP drift. Keep capabilities as authority-to-touch, not method bags. |
| **An `.igapp` manifest now** (Route D) | Real candidate, but adopting it before the Stage 1 proof risks a second language shaped by one app (editor) — overfitting + framework drift. |

---

## 8. Open questions

### Blocking (require Stage 1 prototype pressure before any proposal)

1. **Instance identity:** does the editor fixture genuinely need state-*instance* identity
   *in source* (many open documents, many views), or is host-keyed identity sufficient
   with only the *schema* named in source?
2. **Hot-state cost / VM implication:** can keystroke-rate transitions (cursor, selection)
   tolerate the pure-reducer-over-snapshot model, or do they force a host-only path that
   the language should explicitly decline to model?
3. **Lifecycle overload:** can the existing `:session/:window/:durable` vocabulary carry
   *holder-scope* meaning without conflating it with *retention/provenance*, or do the two
   meanings need to split?
4. **Sufficiency of metadata:** can the public-vs-internal boundary and the event→operation
   →fact wiring live as sidecar/intent-style metadata, or do they demand an active surface
   (Route D)? — This is the gate question for P2's gap packet.

### Non-blocking (can be decided later or left to host)

5. Exact descriptor schema for the state vocabulary (field names, JSON shape).
6. Whether the app assembly, if ever needed, is a sidecar file or in-source.
7. UI event routing representation — provisionally **out of language scope** (host).
8. Multi-instance editor (workspace of buffers) representation — likely a `Collection` of
   facts; confirm under proof.

---

## 9. Boundary statement

- **No implementation authority.** No compiler, parser, or VM change is proposed or made.
- **No canon claim.** Spec chapters (Ch10, Ch12) are cited as *proposed*; lab tracks as
  *evidence*, not authority.
- **No stable API.** No public or stable surface is claimed.
- **No runtime state-holder authorization.** The recommendation explicitly keeps the
  holder external and declines to authorize any in-language holder.
- **No public framework claim.** This is lab research, not a framework.
- **No new keyword is adopted.** Route B's `app_state` / Route D's `app` sketches are
  illustrative *candidates only*, framed for comparison; nothing here reserves them.

---

## Inputs reviewed

| Source | Used for |
|--------|----------|
| `igniter-lang/docs/spec/ch2-source-surface.md` | grammar kernel, lifecycle vocabulary, keyword-reservation caution |
| `igniter-lang/.agents/work/proposals/accepted/PROP-015-grammar-module-system-v0.md` | module semantics & non-goals |
| `igniter-lang/docs/spec/ch10-contract-modifiers.md` (PROP-031) | effect-character vocabulary |
| `igniter-lang/docs/spec/ch12-effect-surface.md` (PROP-035) | external/durable boundary, outcome taxonomy |
| `igniter-lang/.agents/work/proposals/PROP-045-…intent…-v0.md` | inspectable-but-inert metadata precedent |
| `igniter-lab/lab-docs/ide/igniter-debugger-and-source-mapping-feasibility-report-v0.md` | inspectability constraints, node-anchored value-trace model, no-hidden-mutation |
| LAB-QUERY-P3 / LAB-STORAGE-CAPABILITY-P2 (pressure) | non-editor pressure case: pure plan + capability boundary + KDR |
| LAB-EPISTEMIC-OUTCOME-P2 (pressure) | `unknown_external_state` outcome preservation |

---

*LAB-ONLY. Research / design boundary. No implementation authority. No canon claim. No stable API.*
