# lab-lang-surface-ergonomics-readiness-p0-v0 — the application-pressure language-polish lane

**Card:** `LAB-LANG-SURFACE-ERGONOMICS-READINESS-P0` · **Delegation:** `OPUS-LANG-SURFACE-ERGONOMICS-P0`
**Status:** READINESS / PRIORITIZATION (v0) — opens a **parallel surface-ergonomics lane** with the
discipline that **sugar must lower to the existing graph/SIR and add no runtime authority**. **No code, no
parser/compiler/VM edit, no new syntax, no canon claim.**
**Authority:** Lab readiness. Grounded in the P18–P23 app-authoring proofs + the live lexer/parser + the
igniter-lang proposal/meta-proposal corpus.

## 1. Executive summary

App-authoring (IgWeb/Todo/View P16–P23) pushed `.ig` from substrate proofs into real application shapes and
**surfaced concrete, repeated paper cuts** — not a rejection of the graph foundation. The igniter-lang team
already named the same diagnosis (`abstraction-layering-primitive-sugar-pressure`, `external-syntax-monotony-
review-signal`: *"strong semantic kernel, flat surface"*). This packet turns that into a **prioritized,
disciplined lane**:

1. **`LAB-LANG-STRING-ESCAPES-P1`** — lowest risk, highest unblock, **not even tracked in proposals**.
2. **`LAB-LANG-MATCH-ARM-BINDINGS-READINESS-P1`** — removes the one *graph-purity* ceiling (multi-guard /
   accumulation); reconciles with existing `LANG-MATCH-ARM-PARAM-UNIFICATION` + `LANG-TYPED-COMPUTE-BINDING`.
3. **`LAB-LANG-RECORD-ERGONOMICS-READINESS-P1`** — optional fields (proposal exists) + spread (pressure
   only); kills the all-fields-required record noise P19/P23 hit.
4. **pipe / `section` grouping** — defer (readability sugar; wait for a 2nd app to repeat the pain).

The load-bearing governance rule: **a surface-sugar change must desugar to the same canonical AST/SIR a
human could hand-write, produce a byte-identical SemanticIR, and introduce no new semantics, dispatch, IO,
or authority** — exactly the Projection-Dialect discipline (`.igweb`/`.igv` → `.ig`), applied *inside* the
language.

## 2. Pressure table (live evidence, from this lab's own proofs)

| Pressure | Class | Evidence (first-hand) | In proposals? |
|---|---|---|---|
| **String literals have no escapes** → can't author inline JSON/quotes | **paper cut** | P17–P22 routed *5 cards* around it: ViewArtifact JSON had to come from `req.body` (P17) or typed records (P18–P22) because `"{\"a\":1}"` won't lex (`lexer.rs` `read_string` reads to next `"`). | **NO** (string proposals are stdlib fns only) |
| **`match`/result arms can't rebind / no `let`-in-arm** → multi-guard & accumulation verbose | **expressiveness gap** (the one graph-purity ceiling) | P20: multi-`via` chaining shadows `Ok { value }` (no rename, arm body is a single expr) → v0 narrowed to single-`via`. P19-via-chain-readiness §2. | **PARTIAL** — `LANG-MATCH-ARM-PARAM-UNIFICATION-P1/P2`, `LANG-TYPED-COMPUTE-BINDING-P1` |
| **Records require ALL fields; no spread / optional** → noisy literals | **expressiveness gap** | P19 flat `HtmlNode` = 6 fields/node; P23 adding `options` forced `options: []` on every node (`OOF-TY0: required field 'options' is missing`). | **PARTIAL** — `LANG-OPTIONAL-FIELD-PARTIAL-RECORD-P1/P2` (spread = *pressure-only* in `syntax-pressure-registry`) |
| **`filter`→`map` chains read inside-out** | **readability sugar** | P21/P22 work but nest function calls; a pipe would read top-down. | **NO** (method-chain = pressure-only) |
| **Monotone surface (`input/compute/output` flat)** | **readability / scannability** | external review + `abstraction-layering` note; `section`/`phase` grouping is the low-risk relief. | pressure-only |

## 3. Classification (Q2) & proposal crosswalk (Q3, Q4)

- **Paper cuts (small, mechanical):** string escapes.
- **Expressiveness gaps (real ceilings):** match-arm bindings; record spread/optional.
- **Readability sugar (defer):** pipe; `section`/`phase` grouping.

| Need | Tracking status | Lane card |
|---|---|---|
| string escapes | **untracked gap** (Q4) | `LAB-LANG-STRING-ESCAPES-P1` (new) |
| match-arm bindings / let-in-arm | partial: `LANG-MATCH-ARM-PARAM-UNIFICATION` + `LANG-TYPED-COMPUTE-BINDING` | `LAB-LANG-MATCH-ARM-BINDINGS-READINESS-P1` *reconciles* them with lab pressure |
| optional fields / partial records | tracked: `LANG-OPTIONAL-FIELD-PARTIAL-RECORD-P1/P2` | `LAB-LANG-RECORD-ERGONOMICS-READINESS-P1` adopts it |
| record spread `{ ...base, f: v }` | **pressure-only** (Q4) | folded into `…-RECORD-ERGONOMICS-READINESS-P1` |
| pipe `\|>` | untracked | defer (`LANG-PIPE-SYNTAX-READINESS-P*`) |
| `section`/`phase` grouping | pressure-only | defer (separate scannability axis) |

**Two genuine gaps missing from proposal tracking (Q4):** (1) **string escapes** — the single highest-leverage
fix and not carded anywhere; (2) **record spread** — only a registry "pressure" line, no PROP. Everything
else has at least a partial proposal to build on.

## 4. The acceptance rule for this lane (Q5) — load-bearing

A surface-sugar change is admissible **only if all hold**:

1. **Desugars to canonical `.ig`** — there is a hand-writable `.ig` form the sugar is exactly equivalent to.
2. **SIR parity** — the sugar and its desugaring produce a **byte-identical SemanticIR** (the same proof
   shape the `.igweb`/`.igv` dialects already use: lower → compare to hand-written). This is the *evidence*
   the lane isn't adding hidden meaning.
3. **No new runtime authority** — no IO, effect, capability, dispatch, mutation, or nondeterminism; purity,
   determinism, replay, and receipts are untouched because the sugar vanishes before SIR.
4. **No new node types in SIR** — sugar is *typography*, not a new semantic node (string escapes change the
   lexer's string value; record spread/optional change literal construction; match-arm bindings change
   binding scope — none add an executable node kind).
5. **Diagnostics still point at the source** — line-positioned errors on the sugar, not only the desugaring.

If a change can't meet (1)–(4), it is **not** surface sugar — it belongs in the capability/runtime/projection
lane (§5).

## 5. Out of scope for this lane (Q6)

Effects / DB / storage / streaming capability design (capability lane: `LANG-EFFECT-SURFACE-RUNTIME-BRIDGE`,
`LANG-IO-CAPABILITY-EXECUTOR`, `PROP-046`); package manager / workspace resolver; the projection dialects
(`.igweb`/`.igv`/`.ig.html` — those lower to `.ig`, this lane improves `.ig` itself); canon promotion (a
separate `LANG-*` gate); anything that adds a semantic/runtime node. This lane is **pure `.ig` source-surface
sugar that lowers to today's SIR**.

## 6. First slice (Q7) — `LAB-LANG-STRING-ESCAPES-P1`

**Why first:** (a) **highest unblock / lowest risk** — it is a localized `lexer.rs` `read_string` change
(recognize `\"`, `\\`, `\n`, `\t`, `\uXXXX`), no parser/typechecker/VM/SIR change; (b) it removes an entire
*class* of workarounds (the P17–P22 inline-JSON detour); (c) it is **not tracked anywhere**, so the lane
closes a real backlog hole; (d) trivially meets the §4 rule — escapes change only the *string value*, the
SIR string node is unchanged. Acceptance: a `.ig` string literal with `\"`/`\\`/`\n`/`\t`/`\uXXXX` lexes to
the correct runtime string; an unterminated/invalid escape is a line-positioned error; existing
no-escape strings are byte-identical; `OOF`-clean compile + a VM round-trip of an escaped string.

## 7. Second slice (Q8) — `LAB-LANG-MATCH-ARM-BINDINGS-READINESS-P1`

**Why second:** it removes the **only graph-purity-caused ceiling** (P20 multi-`via` `value`-shadowing;
accumulation). It is a *readiness* (not impl) because it must reconcile three live threads —
`LANG-MATCH-ARM-PARAM-UNIFICATION`, `LANG-TYPED-COMPUTE-BINDING`, and the lab's multi-guard pressure — and
decide the minimal shape (arm-local `let` / pattern rebinding `Ok { value: account }` / `where`) that
preserves graph node identity (the registry flags this: *"`let` as contract-body replacement must preserve
graph node identity"*). Higher design weight than escapes → readiness first.

`LAB-LANG-RECORD-ERGONOMICS-READINESS-P1` (optional fields + spread) is the natural **third** — it has a
live proposal to adopt and concrete P19/P23 evidence, but it is record-construction noise (verbose, not
*impossible*), so it ranks below the two ceilings above.

## 8. Evidence the lane is helping, not adding noise (Q9)

- **Workaround retirement:** an app-authoring card that *previously needed a detour* is re-authored directly
  — e.g. after escapes, an inline ViewArtifact/`.view.json` authored without the P18–P22 typed-record
  scaffolding; after match-arm bindings, a multi-`via` chain that P20 had to narrow to single-`via`.
- **SIR parity tests** (the §4 rule) green: sugar ≡ desugaring, byte-identical SemanticIR — proves no hidden
  semantics.
- **No growth in SIR node kinds** across the lane — a measurable "typography not semantics" check.
- **Net-negative source size** on a real fixture (fewer chars, same SIR) without new node types.

## 9. Defer until two apps repeat the pain (Q10)

Pipe `|>`; `section`/`phase` grouping; record spread *beyond* what optional-fields covers; any abstraction-
layer surface (`entity`/`entrypoint` — those are also bigger, and partly canon-proposal territory). Sugar
earns its place when a **second** application repeats the same friction — otherwise it is speculative syntax
(the registry's own [R3]).

## 10. Recommended first implementation card

**`LAB-LANG-STRING-ESCAPES-P1`** — proceed. It is the smallest, safest, highest-leverage slice, fills an
untracked gap, and meets the §4 discipline trivially. Sequence: `STRING-ESCAPES-P1` →
`MATCH-ARM-BINDINGS-READINESS-P1` → `RECORD-ERGONOMICS-READINESS-P1` → (pipe/section, deferred).

## Closed scope (honored)

No code/parser/compiler/VM edit; no new syntax shipped; no canon claim; no DB/effect/storage/streaming
capability design; no `.igweb`/`.igv`/`.ig.html` design beyond marking projections out-of-lane; no package
manager / workspace resolver.

---

*Readiness/prioritization only. Compiled 2026-06-20; grounded in the P18–P23 proofs, live `lexer.rs`
(no-escape `read_string`), and the igniter-lang proposal corpus (string-escapes untracked; match-arm +
optional-field partially tracked; record-spread + pipe pressure-only). The lane's contract: surface sugar
lowers to today's SIR and adds no authority. First card: `LAB-LANG-STRING-ESCAPES-P1`.*
