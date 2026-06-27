# LAB-FRAME-VIEW-LANGUAGE-PRESSURE-P1 — view authoring as pure igniter (element-contracts)

Status: PRESSURE (ask to canon) — feasibility + trap recon done; direction SAFE; two asks, one HELD.
Lane: igniter-lab / frame-ui → igniter-lang (canon) / DX
Date: 2026-06-27
Reads with: `lab-frame-dx-view-language-design-p1-v0.md` (design + Candidate D),
`lab-frame-dx-authoring-surface-recon-p1-v0.md` (surface recon). Specimens:
`lab-docs/lang/specimens/dx-view-d/{elements,list_view_inline,list_view_dynamic}.ig`.

## What this pressures, in one line

We can author a real, dynamic, nested, data-bound VIEW as PURE igniter — element-CONTRACTS building a
recursive `Element` tree, populated by `map(coll, x -> call_contract("Leaf", …))`. It compiles on the
live `igc` today. Two bounded, canon-aligned gaps stand between today's authoring and a clean
`col { row { leaf } }` surface. Both ride canon's OWN tracks; neither needs new semantics.

## Grounded evidence (compiled on `igniter-lang/bin/igc compile`)

- `elements.ig` — element-contracts + **recursive `Element { children: Collection[Element] }`** →
  `status: ok` standalone.
- `list_view_inline.ig` — full list screen, static, same module → `ok` (5 contracts).
- `list_view_dynamic.ig` — **data-bound dynamic nested screen** (`map(lead_labels, l ->
  call_contract("Leaf", a_row, l))` + `append` + nested children) → `ok`.
- The feared blocker ("no fold/map ⇒ no dynamic lists") was FALSE: `map`/`filter`/`fold`/`filter_map`/
  `append` all exist with lambdas. Dynamic lists compile.

## Load-bearing dependency — and why it's safe

The whole approach rests on **data-shape recursion** (`Element` referencing its own type). Recon
verdict: this is **distinct from the managed computation-recursion LAW** (`recur`/`decreases`,
OOF-R1..R7, which governs CONTROL flow) — the type system permits self-referential records, and the
specimen constructs/nests them cleanly. Crucially, **we only CONSTRUCT the tree in `.ig`; the host
(frame-ui `WidgetRenderHost`) TRAVERSES it** — so even the known weak spot (`.ig` self-traversal) is
out of our path. Load-bearing risk: **LOW**. This was the make-or-break unknown; it is closed.

## The asks (risk-classified)

### ASK 1 — cross-module contract references (the real blocker) — PUSH
`call_contract` is module-local today: a reusable `elements.ig` library OOFs from a view module
(`OOF-TY0: call_contract: unknown callee 'Leaf' — not found in this module`). Without this, the
element library must be inlined into every screen.
- Track: **LANG-TYPED-CONTRACT-REF** (design P1 closed; impl P2 deferred; Rust ahead of Ruby).
- Feasibility: needs implementation, not new design — the `uses ContractName` typed-ref algebra exists.
- Trap risk: **MEDIUM** — must preserve module isolation; mitigated because `uses` is EXPLICIT (no
  implicit visibility). Ask: land cross-module contract-ref resolution so an element library is reusable.

### ASK 2 — invocation-form with nested brace-body children (the `col { row { leaf } }` sugar) — PUSH
Today each node is a named `compute`; nesting is manual child-threading. The sugar that closes the gap:
let an invocation-form's `{ … }` body carry nested child-forms as the `children` argument.
- Track: **LANG-FORM-VOCABULARY** (forms = "conservative elaboration → InvocationIntent"; P4 invocation
  deferred). The lowering algebra is sound; this is syntactic sugar over a working construction path.
- Trap risk: **LOW-MEDIUM** — parse must disambiguate a child-form body from a record literal (canon
  already disambiguates lambda block-vs-record by lookahead). Ask P4 to specify the nesting model and
  **prefer EXPLICIT `map(coll, x -> form)` over implicit child-collection** (keeps determinism obvious).

### HELD — optional/default fields, record spread, shape-with-data — DO NOT PUSH (this is the trap)
Tempting for terse attributes, but recon flags **HIGH risk**: omittable/default fields break the
**totality + determinism + explicit-first** invariants (a field might not exist at runtime; construction
becomes ambiguous). A canon readiness proof (optional-field/partial-record) explicitly says **HOLD —
route a full PROP before any compiler change**; record spread has no proposal; `contract_shape`
(PROP-016) shares PORTS not DATA. **Stay with the safe pattern: explicit attr-presets** (named `a_row`/
`a_col`/… records, as the specimen does). Verbose, but it does not fight the language. Revisit only with
a concrete, totality-preserving design.

### DEFER — lambda body as a record literal (`x -> { field: … }`) — minor
Incidental parser lookahead gap (`Expected rbracket, got rbrace`); the clean workaround (`x ->
call_contract("Leaf", …)`) is exactly what element-contracts use, so it does not block us. Low priority.

## Net

Direction is **SAFE to pursue**: the load-bearing recursive-data dependency is blessed/stable and only
used for construction; the two real gaps (ASK 1, ASK 2) ride active canon tracks and need implementation
not invention; the one genuine trap (optional/default fields) is identified and **deliberately not
pursued**. This turns the frame-ui view work into precedent-setting pressure that advances canon, with no
language-breaking move.

## Smallest proof that de-risks the rest

A **host bridge**: render the compiled `Element` tree (the `.ig`-authored view's output) through the
frame-ui `WidgetRenderHost`, so an `.ig`-authored screen runs LIVE in the browser. If that closes the
loop cleanly (it should — the descriptor IR is exactly what the host already renders), the direction is
proven end-to-end and ASK 1/ASK 2 become the only remaining work. If it exposes a deeper gap, reconsider
(fall back to the side-dialect B/C from the design doc).

## Anchors

- design + candidates: `lab-frame-dx-view-language-design-p1-v0.md`
- specimens (compiled `ok`): `lab-docs/lang/specimens/dx-view-d/`
- ASK 1 track: `LANG-TYPED-CONTRACT-REF-typed-contract-reference-declaration-v0` (igniter-lang proposals)
- ASK 2 track: `LANG-FORM-VOCABULARY-explicit-dictionary-and-resolution-v0` (igniter-lang proposals)
- HELD evidence: optional-field / partial-record readiness proof (canon, verdict = HOLD)
- recursion axes: managed computation-recursion (Ch13, OOF-R1..R7) vs data-shape recursion (Ch3 records)
