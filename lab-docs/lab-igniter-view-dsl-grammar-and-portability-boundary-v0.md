# Igniter View — `.igv` Grammar Sketch and Portability Boundary

Status: `experimental · lab-only · no-canon · no-public-api · no-stable-syntax`
Track: `lab-igniter-view-dsl-grammar-and-portability-boundary-v0`
Card: `LAB-IGNITER-VIEW-FRAMEWORK-P4`
Date: 2026-06-06
Type: research / design — no code implementation
Grammar: `igniter-view-engine/docs/igv-grammar-sketch-v0.ebnf`
Proof matrix: IGV-G1 through IGV-G9 — all verified by analysis

Depends on:
- LAB-IGNITER-VIEW-FRAMEWORK-P3 (42/42 PASS) — the `.igv` Ruby DSL prototype

---

## 1. Motivation

P3 proved that a `.igv` Ruby DSL can compile to `ViewArtifact` JSON with the exact same
digest as a hand-authored fixture. The digest identity confirmed that the Ruby DSL is a
faithful frontend for the artifact format.

But **the Ruby `instance_eval` prototype has a portability boundary**: the `.igv` syntax is
implicitly Ruby, and any tooling (IDE completion, linting, type checking, cross-language
analysis) must know this. P4 separates "what `.igv` means" from "how it is currently
expressed in Ruby" by sketching a portable grammar.

**Goal:** Produce a grammar sketch that:
1. Covers all P3 constructs (IGV-G1, IGV-G2)
2. Resolves the `param`/`slot` ambiguity (IGV-G3)
3. Maps cleanly to the existing ViewArtifact JSON target (IGV-G4)
4. Encodes the banned opcode policy (IGV-G5)
5. Aligns with the P3 diagnostics model (IGV-G6)
6. Requires no runtime or schema changes (IGV-G7)
7. Makes no canonical syntax claim (IGV-G8)
8. Produces an explicit next-route recommendation (IGV-G9)

---

## 2. Grammar Overview

The full EBNF grammar is in `igniter-view-engine/docs/igv-grammar-sketch-v0.ebnf`.
Below is an annotated walkthrough with design rationale.

### 2.1 File structure

```ebnf
igv_file  = view_decl ;
view_decl = 'view' , view_id , 'do' , view_body , 'end' ;
view_body = { state_decl | slot_decl | element_def } ;
```

One `view` per file. Multiple views per file are reserved but not specified here —
the artifact model is one-to-one between `.igv` and `ViewArtifact`. A multi-view
syntax would require a collection wrapper not present in the current schema.

### 2.2 Declarations

```ebnf
state_decl = 'state' , symbol , ',' , 'type:' , type_lit
           , [ ',' , 'default:' , literal ] ;

slot_decl  = 'slot' , symbol , ',' , 'type:' , type_lit
           , ',' , 'from:' , quoted_string ;
```

`state` declares a mutable UIState field. `slot` declares a read-only injected value.
`from:` is required for `slot` (WF-7) — the grammar enforces the contract reference
path that the Ruby DSL also enforces (IgvCompileError if absent).

### 2.3 Elements

```ebnf
element_def  = 'element' , symbol , 'do' , element_body , 'end' ;
element_body = { classes_stmt | param_decl | display_stmt | on_stmt } ;
```

Element bodies are ordered sequences of statements. The grammar does not require a
specific ordering (declarations before rules), but a SHOULD rule recommends placing
`param_decl` before any `display_stmt` or `on_stmt` that references `param_expr`.

### 2.4 Display rules

Two kinds: `:style` (binary condition) and `:match` (N-way dispatch).

```
display :style,
        condition: eq(ui_state(:active_tab), param(:id)),
        on_true:   { c: "bg-ignite", a: { selected: "true" } },
        on_false:  { c: "text-grey" }
```

Maps to ViewArtifact JSON:
```json
["style",
  ["eq", ["ui_state", "active_tab"], ["param", "id"]],
  {"c": "bg-ignite", "a": {"selected": "true"}},
  {"c": "text-grey"}]
```

The mapping is direct and mechanical — no semantic transformation needed.

### 2.5 Interaction rules

```ebnf
on_stmt     = 'on' , symbol , ',' , instruction , { ',' , instruction } ;
instruction = set_instr | toggle_instr | clear_instr ;
set_instr   = 'set_ui_state' , '(' , symbol , ',' , expr , ')' ;
```

The instruction production is **closed**: any identifier at instruction position that
is not `set_ui_state`, `toggle_ui_state`, or `clear_ui_state` is a MUST-error. Banned
opcodes get a named error message.

### 2.6 Expression grammar

```ebnf
expr        = atom_expr | binary_expr | unary_expr ;
atom_expr   = ui_state_expr | param_expr | slot_expr | literal ;
binary_expr = bin_op , '(' , expr , ',' , expr , ')' ;
unary_expr  = 'not_' , '(' , expr , ')' ;
```

Expressions are a pure, closed language. They can reference UIState, params, slots, and
literals; they cannot call functions, access globals, or produce side effects.
The expression grammar is exactly the set of operators supported by the JS runtime's
`evaluate()` and the Ruby `SSRRenderer`'s `evaluate_expr()`. No new operators are added.

---

## 3. Key Design Decisions

### D1 — `param` and `slot` disambiguation: context-based, not keyword-split

**The problem:** In the Ruby DSL, `param` and `slot` are overloaded:
- `param :id, type: "string"` → declaration (statement position)
- `param(:id)` → expression (inside condition/instruction)

This is clean in Ruby (kwarg presence distinguishes) but ambiguous in a grammar without
additional context.

**Grammar solution: production context distinguishes, not separate keywords.**

| Position | Production | Example |
|---|---|---|
| element_body statement | `param_decl` | `param :id, type: "string"` |
| expression position | `param_expr` | `param(:id)` |
| view_body statement | `slot_decl` | `slot :has_warnings, type: "boolean", from: "..."` |
| expression position | `slot_expr` | `slot(:has_warnings)` |

A grammar-based parser resolves this structurally: at statement position in `element_body`,
a `param` followed by `,` and `type:` matches `param_decl`; inside `expr`, `param` followed
by `(` matches `param_expr`. No ambiguity given a single-token lookahead after `param`.

**Decision: keep the same surface keywords; split at grammar level by production context.**
Rationale: the overloading is ergonomic and the disambiguation is unambiguous. Splitting to
`declare_param` / `ref_param` would improve readability at the cost of a different surface
from the P3 prototype.

**Concrete grammar rule (simplified LL(2) lookahead):**
```
at statement position:
  'param' ':' identifier ',' 'type:' …  → param_decl
  otherwise (should not occur at statement level) → error

at expression position:
  'param' '(' ':' identifier ')' → param_expr
```

### D2 — Undeclared slot reference: dual policy (grammar vs Ruby DSL route)

**Grammar-based parser route:** WF-6 — MUST-error. The parser has full view context at
parse time; failing hard on an undeclared slot reference is cheap and correct. The artifact
is not produced.

**Ruby DSL route (existing P3 prototype):** warning-only. The artifact is produced with a
diagnostic. The P2 runtime's `filterSlotValues` guard handles the undeclared key safely at
runtime (evaluates nil → falsy branch).

**These two policies are compatible:** both produce the same *valid* artifact for valid
`.igv` files. They differ only in how they handle invalid inputs. The Ruby DSL's
warning-only stance is appropriate for a development prototype; the grammar-based parser's
hard-error stance is appropriate for a linter/CI tool. The P2 runtime safety guarantee
holds in both cases.

**Decision: dual policy, explicitly documented. Not a contradiction.**

### D3 — Ruby DSL remains acceptable as lab authoring frontend

The P3 Ruby `instance_eval` prototype is a valid first implementation of the grammar
semantics. No grammar-based parser is required before:
- Conducting P5 (collection rendering) experiments
- Running further lab iterations
- Returning findings to the Igniter-Lang canon track

A grammar-based parser would be required before:
- Any public syntax claim for `.igv`
- IDE completion/linting tooling
- Cross-language compiler frontends (TypeScript, Rust, etc.)

**Decision: grammar is a design artifact; Ruby DSL is the authoring frontend for now.**

### D4 — No new ViewArtifact schema fields required by the grammar

The grammar covers all P1–P3 constructs with zero new JSON artifact fields. The grammar
is purely a specification of the *source language*; the *target* (ViewArtifact JSON) is
unchanged. This confirms the P3 finding that the artifact format is a sound compilation
target for a grammar-based compiler.

### D5 — Banned opcode extension: `ajax`, `xhr` added

The grammar explicitly names `ajax` and `xhr` as banned at instruction position. These
were implicit in the P1–P3 runtime (subsumed by `fetch`) but unnamed. The grammar is a
natural place to make the banned set complete and unambiguous.

Runtime-side `BANNED_OPCODES` array in `igniter_view_runtime.js` and `ViewArtifact::BANNED_OPCODES`
SHOULD be extended in a future pass to include `ajax` and `xhr`. This is a
recommendation, not a requirement — the lab runtime already blocks anything not in
`ALLOWED_OPCODES`, so `ajax` would fail on the unknown-opcode gate regardless.

### D6 — Source map trace hooks are desirable but not required yet

The grammar sketch includes a source map annotation model (file + line + col per node).
This is aspirational — the P3 Ruby prototype does not emit source maps. A grammar-based
parser should emit source maps from the start. The value is IDE tooling (go-to-definition,
inline error highlighting at the correct `.igv` line).

---

## 4. Grammar → ViewArtifact Mapping

The following table shows the mechanical correspondence between grammar productions and
ViewArtifact JSON fields. This mapping is the basis for IGV-G4.

| Grammar production | ViewArtifact JSON path |
|---|---|
| `view_decl.view_id` | `artifact.view_id` |
| `state_decl` | `artifact.ui_states["key"]` |
| `slot_decl` | `artifact.slots["key"]` |
| `element_def` | `artifact.elements[i]` |
| `classes_stmt` | `artifact.elements[i].static_classes` |
| `param_decl` | `artifact.elements[i].node_params_schema["key"]` |
| `display_stmt` (style) | `artifact.elements[i].display_rules[j]` = `["style", cond, t, f]` |
| `display_stmt` (match) | `artifact.elements[i].display_rules[j]` = `["match", subj, cases, def]` |
| `on_stmt` | `artifact.elements[i].interaction_rules[j]` = `["on", ev, [instructions]]` |
| `set_instr` | `["set_ui_state", key, value_expr]` |
| `toggle_instr` | `["toggle_ui_state", key]` |
| `clear_instr` | `["clear_ui_state", key]` |
| `ui_state_expr` | `["ui_state", "key"]` |
| `param_expr` | `["param", "key"]` |
| `slot_expr` | `["slot", "key"]` |
| `binary_expr(eq, a, b)` | `["eq", a_json, b_json]` |
| `effect_map {c: "...", a: {}}` | `{"c": "...", "a": {}}` |

The mapping is lossless and invertible (except `non_claims` and `safety_policy` which are
generated by the compiler, not derived from `.igv` source). This means:
- A conforming compiler MUST produce exactly this JSON from a conforming `.igv` file.
- The ViewArtifact digest algorithm (SHA-256 of canonical JSON minus non_claims/safety_policy)
  is deterministic given the grammar — same source → same digest.

---

## 5. Diagnostics Model

Grammar-level diagnostics map to the P3 `IgvCompiler` diagnostic system:

| Grammar constraint | Severity | Diagnostic `type` | Artifact emitted? |
|---|---|---|---|
| WF-1: empty view_id | MUST-error | `compile_error` | No |
| WF-2: state/slot key overlap | MUST-error | `validation_error` | No |
| WF-3: slot mutation in instruction | MUST-error | `validation_error` | No |
| WF-4: unknown opcode | MUST-error | `compile_error` | No |
| WF-5: banned opcode | MUST-error | `compile_error` | No |
| WF-6: undeclared slot_expr (grammar route) | MUST-error | `compile_error` | No |
| WF-6: undeclared slot_expr (Ruby route) | warning | `undeclared_slot_reference` | Yes |
| WF-7: slot without from: | MUST-error | `compile_error` | No |
| WF-8: no view_decl | MUST-error | `compile_error` | No |
| WW-1: undeclared param_expr | SHOULD-warning | `undeclared_param_reference` | Yes |
| WW-2: undeclared ui_state_expr | SHOULD-warning | `undeclared_state_reference` | Yes |
| WW-3: no classes_stmt | SHOULD-warning | `missing_static_classes` | Yes |
| SyntaxError (Ruby eval) | MUST-error | `syntax_error` | No |
| NameError (Ruby eval) | MUST-error | `name_error` | No |

New diagnostics added by grammar analysis (not in P3):
- `undeclared_param_reference` — param_expr symbol not in element's param_decl set
- `undeclared_state_reference` — ui_state_expr symbol not in view's state_decl set
- `missing_static_classes` — element has no `classes` statement (cosmetic, SHOULD-warn)

---

## 6. Portability Analysis

### What "portable" means here

A portable grammar means: a parser implementation in any language can read a `.igv` file
and produce the same `ViewArtifact` JSON (or equivalent AST), without depending on Ruby or
the `IgvCompiler` prototype.

### What the Ruby DSL is and is not

**Is:** A valid implementation of the grammar's semantics using Ruby `instance_eval`. Safe
for trusted developer-authored files in a lab setting.

**Is not:** A grammar. A grammar-based parser. A cross-language format. A sandbox.

**Security note:** The Ruby `instance_eval` approach gives `.igv` source code access to
all Ruby methods in scope. A `.igv` file from an untrusted source could execute arbitrary
Ruby. This is acceptable for the lab (developer-authored, trusted) but would need
sandboxing for any CI/IDE integration reading files from third-party sources.

### Grammar-based parser portability tiers

| Tier | Description | What's needed |
|---|---|---|
| **Tier 0** (current) | Ruby DSL, `instance_eval` | Nothing — P3 prototype |
| **Tier 1** | Ruby PEG parser (e.g. `parslet`, `treetop`) | Grammar → Ruby parser generator |
| **Tier 2** | TypeScript/Node.js parser | Grammar → TS parser (Peggy, Chevrotain, Nearley) |
| **Tier 3** | Rust/WASM parser | Grammar → Rust (pest, lalrpop) → WASM |
| **Tier 4** | Language server (LSP) | Tier 2/3 parser + LSP protocol |

Tier 0 is sufficient for P5. Tier 1 is the natural next step if grammar-based error
messages or IDE linting are required. Tier 4 enables full IDE integration.

### Grammar size

The grammar sketch contains ~25 non-terminal productions. This is small — a typical
handwritten recursive-descent parser for this grammar would be ~300–500 lines in any
language. The grammar is well within PEG parser generator input limits.

### Tokenization notes

A grammar-based lexer needs to distinguish:
- Keywords: `view`, `do`, `end`, `state`, `slot`, `element`, `classes`, `param`,
  `display`, `on`, `true`, `false`, `nil`, `eq`, `neq`, `gt`, `lt`, `gte`, `lte`,
  `and_`, `or_`, `not_`, `set_ui_state`, `toggle_ui_state`, `clear_ui_state`,
  `ui_state`, `slot` (expression use)
- Symbol literals: `:identifier`
- Keyword arguments: `type:`, `default:`, `from:`, `condition:`, `on_true:`, `on_false:`,
  `subject:`, `cases:`, `default:`, `c:`, `a:`, `d:`
- Operators: `,`, `=>`, `(`, `)`, `{`, `}`
- String literals: `"..."` (double-quoted)
- Display kinds: `:style`, `:match`

The tokenizer is unambiguous — no overlapping token classes. Total token types: ~35.

---

## 7. Evaluation of P3 Findings

P3 identified four findings. P4 evaluates each:

### Finding 1 — ViewArtifact is a sound compilation target ✓ Confirmed

The grammar produces the same artifact structure (IGV-G4). No new artifact fields are
needed for the grammar constructs. The artifact format is stable enough for a grammar to
target.

**P4 verdict:** No changes to ViewArtifact schema required. Grammar route confirmed.

### Finding 2 — param/slot overloading is grammar-unfriendly but resolvable ✓ Resolved

P4 shows the overloading IS resolvable by production context without changing the surface
syntax. The grammar distinguishes `param_decl` from `param_expr` using an LL(2) lookahead.
This does not require splitting into separate keywords.

**P4 verdict:** Keep same surface keywords. Grammar resolves via context. Decision D1 above.

### Finding 3 — style/match display rules are minimal but sufficient ✓ Confirmed

The grammar covers `:style` and `:match`. No new display rule kinds are needed for P5
(collection rendering can use existing `:style` rules on per-item elements). A future
`:repeat` or `:each` rule kind could be added in P6.

**P4 verdict:** No new display rule kinds needed for P5.

### Finding 4 — Slot-contract type linkage gap identified, not yet resolved

The grammar includes `from: "contract.path"` in `slot_decl` but does not validate that
the referenced path exists or that the type matches the contract's output schema. This
gap is structural — it requires the Igniter contract type system to be queryable at
`.igv` compile time.

**P4 verdict:** Slot-contract type linkage remains an open gap. It belongs in a future
research phase (P5 or P6). The P4 grammar leaves `from:` as an opaque string — a
"contract reference" — without validating the reference. A future "contract schema
reader" extension to `IgvCompiler` would close this.

---

## 8. Proof Matrix

*Verified by analysis and cross-reference to P1/P2/P3 artifacts.*

### IGV-G1: Grammar covers all P3 tabs.igv constructs

Analysis: Walk `fixtures/tabs.igv`:
- `view "igniter.lab.tabs_panel" do ... end` → `view_decl` ✓
- `state :active_tab, type: "string", default: "overview"` → `state_decl` ✓
- `slot :has_warnings, type: "boolean", from: "diagnostics.has_warnings"` → `slot_decl` ✓
- `element :tab_btn do ... end` → `element_def` ✓
- `classes "tab-btn ..."` → `classes_stmt` ✓
- `param :id, type: "string"` → `param_decl` ✓
- `display :style, condition: eq(ui_state(:active_tab), param(:id)), on_true: {...}, on_false: {...}` → `display_stmt` (style) ✓
- `eq(ui_state(:active_tab), param(:id))` → `binary_expr(eq, ui_state_expr, param_expr)` ✓
- `on :click, set_ui_state(:active_tab, param(:id))` → `on_stmt` + `set_instr` ✓
- `slot(:has_warnings)` in condition → `slot_expr` ✓

**IGV-G1: VERIFIED** — all constructs have grammar productions.

### IGV-G2: Grammar covers static page construct

Analysis: Walk `fixtures/static_page.igv`:
- `view "igniter.lab.static_page" do ... end` → `view_decl` (no state, no slot) ✓
- Empty `view_body` with only `element_def`s ✓
- `element :hero_section do classes "..." end` → `element_def` with only `classes_stmt` ✓
- No `param_decl`, no `display_stmt`, no `on_stmt` → all optional in `element_body` ✓

**IGV-G2: VERIFIED** — static page (no state/slots/rules) is valid.

### IGV-G3: Grammar distinguishes declaration vs expression forms

Analysis: See Section 3 (D1) and grammar productions:
- `param_decl` (statement position, has `type:`) ≠ `param_expr` (expression position, no `type:`)
- `slot_decl` (view body, has `type:` and `from:`) ≠ `slot_expr` (expression position, symbol only)
- LL(2) lookahead resolves both without ambiguity

**IGV-G3: VERIFIED** — grammar is unambiguous for both `param` and `slot`.

### IGV-G4: Grammar preserves existing ViewArtifact JSON target

Analysis: See Section 4 (Grammar → ViewArtifact Mapping table). Every grammar production
maps mechanically to a ViewArtifact JSON field. No new schema fields are added. The P3
compiler (`IgvCompiler`) implements this mapping in Ruby and produces bit-identical digests
to hand-authored artifacts (IGV-P3-2b confirmed).

**IGV-G4: VERIFIED** — grammar target is ViewArtifact JSON, unchanged.

### IGV-G5: Grammar rejects or reserves banned opcodes

Analysis: Grammar defines `instruction` as exactly `set_instr | toggle_instr | clear_instr`.
Any other identifier at instruction position is an error. The grammar additionally names the
explicitly banned opcode set in a non-production annotation comment. A conforming parser must
produce a named error for banned opcodes.

This is the grammar formalization of:
- P1/P2: `ViewArtifact::BANNED_OPCODES` + `validate!`
- P3: `IGV_BANNED_OPCODES` + `IgvElementBuilder#on` fence

Two independent fences remain; the grammar documents both.

**IGV-G5: VERIFIED** — banned opcodes are rejected by closed instruction production.

### IGV-G6: Diagnostics model maps to P3 diagnostics

Analysis: See Section 5 (Diagnostics Model table). All P3 diagnostic `type` values appear
in the grammar constraint table. Three new warning types (`undeclared_param_reference`,
`undeclared_state_reference`, `missing_static_classes`) are added by the grammar analysis.
These are SHOULD-warnings in the grammar route — they extend the P3 model without
contradicting it.

**IGV-G6: VERIFIED** — P3 diagnostics are covered; grammar adds three new SHOULD-warnings.

### IGV-G7: No runtime or schema change required

Analysis:
- `igniter_view_runtime.js` — not read, not modified, not referenced in the grammar
- `ViewArtifact` class — not modified; grammar targets its existing schema
- `SSRRenderer` — not modified; consumes existing ViewArtifact
- No new artifact JSON keys introduced

**IGV-G7: VERIFIED** — grammar is purely a source-language design document.

### IGV-G8: No canonical syntax or public API claim created

This document and the grammar file `igv-grammar-sketch-v0.ebnf` both carry:
```
Status: DESIGN SKETCH — experimental · lab-only · no-canon · no-public-api
```

The grammar is a lab artifact in `igniter-lab/`. No changes were made to
`igniter-lang/` or any external documentation. The `non_claims` in the compiled
ViewArtifact explicitly include `"no-stable-syntax"` and `"no-canon"`.

**IGV-G8: VERIFIED** — no canonical claim made.

### IGV-G9: Next route recommendation is explicit

See Section 9 below.

**IGV-G9: VERIFIED** — recommendation provided with rationale.

---

## 9. Recommendation for P5

### Options

**Option A — Collection Rendering**
Extend `.igv` DSL with a `collection` keyword for repeated element instances, each with
their own `node_params`. SSR renders all items; JS re-renders on UIState change. Tests
the `:match` display rule with per-item params. Adds `collections` key to `ViewArtifact`
schema (first schema extension since P1).

**Option B — Slot-Contract Type Linkage**
Validate `.igv` slot declarations against the Igniter contract's declared output types.
Requires contract schema introspection at compile time. Would close Finding 4 from P3.
Potentially feeds canon pressure on the Igniter-Lang type system.

**Option C — Grammar-Based Parser Prototype (Tier 1)**
Implement a Ruby PEG parser for the P4 grammar. Produces the same ViewArtifact output
as the `IgvCompiler` Ruby DSL prototype. Validates the grammar as a working spec.
Enables grammar-route hard errors (including WF-6 for undeclared slot_expr).

**Option D — Hold**
No P5 for now. Consolidate P1–P4 findings into a structured lab report for the
Portfolio Architect Supervisor. Feed canon pressure upstream.

### Evaluation

| Option | Benefit | Blocker |
|---|---|---|
| A — Collection rendering | Proves DSL ergonomics for lists; feeds back grammar pressure | Requires `ViewArtifact` schema extension (first) |
| B — Slot-contract linkage | Closes important static type gap | Requires contract introspection API (not yet defined) |
| C — Grammar-based parser | Validates grammar spec; enables hard errors | Significant implementation effort with low incremental semantic value |
| D — Hold | Conserves effort | May lose lab momentum |

### Recommendation: **Option A — Collection Rendering**

**Rationale:**
1. Collection rendering is the most natural next step after tabs — it tests whether
   the artifact can handle repeated elements (lists, tables, grids) without `forEach`
   or dynamic HTML construction.
2. It does not require contract introspection (unlike B) or a new parser (unlike C).
3. The `collections` schema extension is small and localized — it doesn't touch
   `ui_states`, `slots`, or the expression language.
4. It feeds back grammar pressure: a `collection` keyword in the DSL would reveal
   whether the current grammar is expressive enough, or whether a `:repeat` display
   rule kind is needed.
5. It keeps the lab momentum while the canon track continues its disciplined pace.

**If collection rendering is approved for P5:** the following new grammar productions
would need to be drafted:

```ebnf
(* Candidate additions for P5 — NOT part of v0 grammar *)
view_stmt    += collection_def ;

collection_def = 'collection' , symbol , 'do' , collection_body , 'end' ;

collection_body = { classes_stmt | item_element_def | display_stmt } ;

item_element_def = 'each' , symbol , 'do' , element_body , 'end' ;
```

And the ViewArtifact schema would add:
```json
"collections": {
  "name": {
    "item_element_id": "element_name",
    "item_params_schema": { "id": "string" }
  }
}
```

This remains a sketch — no implementation authorized.

---

## 10. What This Is Not (Non-Claims)

| Claim | Status |
|---|---|
| Canonical `.igv` syntax for Igniter-Lang | **No** — design sketch only |
| Stable public grammar | **No** — may change entirely |
| Parser implementation | **No** — EBNF sketch only |
| Production frontend DSL | **No** |
| Certified by Igniter-Lang governance | **No** — lab track |
| Justification for Igniter-Lang spec change | **Potential pressure only** — requires Supervisor review |
