# Igniter View — `.igv` DSL to ViewArtifact Compiler Sketch

Status: `experimental · lab-only · no-canon · no-public-api · no-stable-syntax`
Track: `lab-igniter-view-dsl-to-viewartifact-sketch-v0`
Card: `LAB-IGNITER-VIEW-FRAMEWORK-P3`
Date: 2026-06-06
Proof: 42/42 IGV-P3 + 18/18 P2 + 15/15 DOM + 37/37 P1 — **ALL PASS**
tabs.igv digest: `sha256:ed8ab03d35487fa14bca3598402670feae7e2962c39581dcbc942ea16456c404`
(identical to P1/P2 fixture — same content → same digest, confirmed by IGV-P3-2b)

Builds on:
- `lab-igniter-isomorphic-view-artifact-mvp-boundary-v0.md` (P1)
- `lab-igniter-view-live-slot-injection-and-hydration-hardening-v0.md` (P2)

---

## 1. What Was Built

A minimal `.igv` DSL sketch and compiler prototype that lowers view definitions
to the existing `ViewArtifact` JSON shape proven by P1/P2, without adding new
schema fields, without changing the runtime, and without making any canonical
syntax claims.

| Artifact | Path | Role |
|---|---|---|
| `IgvCompiler` | `lib/igv_compiler.rb` | DSL evaluator + compilation pipeline |
| `tabs.igv` | `fixtures/tabs.igv` | Primary proof fixture (matches P1 digest) |
| `static_page.igv` | `fixtures/static_page.igv` | Static elements, no state/slots |
| `unsafe_opcode.igv` | `fixtures/unsafe_opcode.igv` | Banned opcode → compile error |
| `undeclared_slot.igv` | `fixtures/undeclared_slot.igv` | Undeclared slot → warning |
| `malformed.igv` | `fixtures/malformed.igv` | NameError → compile error |
| `run_ivf_proof_p3.rb` | `run_ivf_proof_p3.rb` | 42-check proof runner |

---

## 2. The `.igv` Syntax Sketch

`.igv` files are Ruby DSL files evaluated by `IgvCompiler`. The syntax is intentionally
narrow — only the primitives needed to express a `ViewArtifact`. No general Ruby logic,
no conditionals, no loops.

### Complete example: tabs component

```ruby
view "igniter.lab.tabs_panel" do
  # ── UIState ───────────────────────────────────────────────────────────────
  state :active_tab, type: "string", default: "overview"

  # ── Slots (read-only from contract output) ────────────────────────────────
  slot :has_warnings, type: "boolean", from: "diagnostics.has_warnings"

  # ── Elements ──────────────────────────────────────────────────────────────
  element :tab_btn do
    classes "tab-btn px-4 py-2 text-xs font-mono rounded-t"
    param :id, type: "string"              # declares node_params_schema

    display :style,
            condition: eq(ui_state(:active_tab), param(:id)),
            on_true:   { c: "bg-ignite text-ink-1 font-bold", a: { selected: "true" } },
            on_false:  { c: "text-grey hover:text-grey-2",    a: { selected: "false" } }

    on :click, set_ui_state(:active_tab, param(:id))
  end

  element :tab_panel do
    classes "tab-panel p-4 bg-ink-1 border border-line rounded mt-2"
    param :id, type: "string"

    display :style,
            condition: eq(ui_state(:active_tab), param(:id)),
            on_true:   { c: "block" },
            on_false:  { c: "hidden" }
  end

  element :warning_banner do
    classes "warning-banner text-xs font-mono px-3 py-2 rounded"

    display :style,
            condition: slot(:has_warnings),
            on_true:   { c: "block border border-oof bg-oof-5 text-oof" },
            on_false:  { c: "hidden" }
  end
end
```

### Minimal static example: no state, no slots

```ruby
view "igniter.lab.static_page" do
  element :hero_section do
    classes "hero px-8 py-16 bg-ink-1 text-center"
  end

  element :cta_button do
    classes "btn px-6 py-2 bg-ignite text-ink-1 rounded font-mono text-sm"
  end
end
```

---

## 3. DSL Reference

### Top-level keywords (inside `view "..." do ... end`)

| Keyword | Signature | Effect |
|---|---|---|
| `state` | `state :name, type: "string", default: value` | Declares UIState field |
| `slot` | `slot :name, type: "boolean", from: "contract.path"` | Declares read-only slot |
| `element` | `element :name do ... end` | Defines an element |

### Element-level keywords (inside `element :name do ... end`)

| Keyword | Signature | Effect |
|---|---|---|
| `classes` | `classes "static css classes"` | Sets `static_classes` |
| `param` | `param :key, type: "string"` | Declares node_params_schema key |
| `display` | `display :style, condition:, on_true:, on_false:` | Adds style display rule |
| `display` | `display :match, subject:, cases:, default:` | Adds match display rule |
| `on` | `on :event, instruction, ...` | Adds interaction rule |

### Expression helpers (available inside element blocks)

| Helper | Output |
|---|---|
| `ui_state(:key)` | `["ui_state", "key"]` |
| `param(:key)` | `["param", "key"]` (expression use; no type:) |
| `slot(:key)` | `["slot", "key"]` (read-only reference) |
| `eq(a, b)` | `["eq", a, b]` |
| `neq(a, b)` | `["neq", a, b]` |
| `gt(a, b)` | `["gt", a, b]` |
| `lt(a, b)` | `["lt", a, b]` |
| `gte(a, b)` / `lte(a, b)` | `["gte"/"lte", a, b]` |
| `and_(a, b)` / `or_(a, b)` | `["and"/"or", a, b]` |
| `not_(a)` | `["not", a]` |

### Instruction helpers (for `on` blocks)

| Helper | Output |
|---|---|
| `set_ui_state(:key, value_expr)` | `["set_ui_state", "key", value_expr]` |
| `toggle_ui_state(:key)` | `["toggle_ui_state", "key"]` |
| `clear_ui_state(:key)` | `["clear_ui_state", "key"]` |

---

## 4. Compiler Architecture

```
.igv file (Ruby DSL)
    │
    ↓ IgvCompiler.compile_file(path)     (entry point)
    │   File.read → compile_string
    │
    ↓ wrapper.instance_eval(source)      (top-level: provides `view` keyword)
    │   view("id") { |block|
    │       IgvViewBuilder.new("id")
    │       vb.instance_eval(&block)     (view context: state, slot, element)
    │           element(:name) { |block|
    │               IgvElementBuilder.new("name")
    │               eb.instance_eval(&block)   (element context: classes, param,
    │                                            display, on, expression helpers)
    │           }
    │   }
    │
    ↓ IgvViewBuilder#build_artifact
    │   ├─ collect_slot_ref_warnings!    (compiler diagnostic: undeclared slot refs)
    │   └─ ViewArtifact.new(...)         (P1/P2 validation: overlap, opcodes, slots)
    │           ↓ compute_digest         (SHA-256, same algorithm as P1/P2)
    │
    ↓ IgvCompiler#artifact               → ViewArtifact instance
      IgvCompiler#diagnostics            → [] | [{ type:, message:, ... }]
      IgvCompiler#success?               → true | false
```

---

## 5. Two-Fence Security Model

Banned opcodes are rejected at two independent checkpoints:

**Fence 1 — `IgvElementBuilder#on`:**
```ruby
if IGV_BANNED_OPCODES.include?(op)
  raise IgvCompileError, "Banned opcode '#{op}' rejected..."
end
```
This is the DSL-level fence. It catches banned opcodes before any `ElementDef` is
created — the element builder never accumulates a malformed state.

**Fence 2 — `ViewArtifact#validate!`:**
```ruby
if BANNED_OPCODES.include?(op)
  raise ArgumentError, "banned opcode '#{op}' rejected at build time"
end
```
This is the artifact-level fence. Even if `IgvElementBuilder` were bypassed (e.g. by
constructing `ElementDef` directly), `ViewArtifact.new` would catch it.

Both fences tested by IGV-P3-8a..d.

---

## 6. Diagnostic System

### Error-level diagnostics (artifact is nil, success? → false)

| type | Cause |
|---|---|
| `compile_error` | Banned opcode, slot declared inside element block, missing `view` declaration, missing required keyword arg |
| `validation_error` | `ViewArtifact.new` raised `ArgumentError` (overlap, slot mutation, etc.) |
| `syntax_error` | Ruby `SyntaxError` in .igv source |
| `name_error` | `NameError` in .igv source (undefined method, typo) |
| `unknown_error` | Unexpected exception |
| `file_not_found` | Path does not exist |

### Warning-level diagnostics (artifact produced, success? → true)

| type | Cause |
|---|---|
| `undeclared_slot_reference` | Display rule references `slot(:key)` not in view's `slot` declarations |

### Usage

```ruby
result = IgvCompiler.compile_file("my_view.igv")

if result.success?
  puts result.artifact.to_json
  result.diagnostics.each { |d| puts "[#{d[:type]}] #{d[:message]}" }  # warnings
else
  result.diagnostics.each { |d| puts "[ERROR:#{d[:type]}] #{d[:message]}" }
end
```

---

## 7. Key Design Decisions

**D1 — `.igv` files are Ruby DSL files, not a new file format.**
Rationale: the lab has no parser infrastructure, and the ViewArtifact expression language
is small enough to express cleanly as Ruby method calls. The `instance_eval` boundary
provides DSL isolation without a grammar. If a canonical `.igv` specification is desired
in a later phase, this prototype validates the intended semantics before a parser is built.

**D2 — `param(:key)` is overloaded: declaration with `type:`, expression without.**
```ruby
param :id, type: "string"  # → adds "id" → "string" to node_params_schema
param(:id)                 # → ["param", "id"] expression for display/interaction rules
```
Same keyword, context-sensitive. Reduces cognitive overhead. Works because the declaration
form always has `type:` as a named parameter, while the expression form never does.

**D3 — `slot(:key)` overloaded at view level (declaration) vs element level (expression).**
View level: `slot :has_warnings, type: "boolean", from: "..."` → schema declaration.
Element level: `slot(:has_warnings)` → expression reference `["slot", "has_warnings"]`.
Attempting `slot :name, type: ...` inside an element block raises `IgvCompileError`.

**D4 — Undeclared slot references are warnings, not errors.**
The artifact is still produced. The runtime's P2 `filterSlotValues` guard ensures the
undeclared reference evaluates nil at runtime. The warning flags a likely developer mistake.
This mirrors the P2 digest-mismatch stance: the content is usable, the diagnostic is for
the developer to fix.

**D5 — `non_claims` is not in the digest computation.**
`ViewArtifact#compute_digest` covers `{view_id, ui_states, slots, elements}` only.
Same content = same digest regardless of non_claims. This is intentional:
non_claims is metadata/governance annotation, not semantic content.
Proved by IGV-P3-2b: `tabs.igv` produces the same digest as `tabs_artifact.rb` (P1).

**D6 — The compiler emits no new artifact schema fields.**
`IgvCompiler.build_artifact` calls `ViewArtifact.new` with the same kwargs as P1.
No new keys in `ui_states`, `slots`, `elements`, or `safety_policy`. The compiler is
purely a frontend; the artifact backend is unchanged.

---

## 8. Proof Evidence

### Cumulative proof chain

| Level | Runner | Checks | Status |
|---|---|---|---|
| P1 — ViewArtifact + SSR + JS runtime | `run_ivf_proof.rb` | 37/37 | ✅ PASS |
| P2 — updateSlots + hydration hardening | `run_ivf_proof_p2.rb` | 18/18 | ✅ PASS |
| P2 DOM — dynamic Node.js proof | `run_ivf_dom_proof.js` | 15/15 | ✅ PASS |
| P3 — .igv DSL compiler | `run_ivf_proof_p3.rb` | 42/42 | ✅ PASS |

### P3 proof matrix

| Check | Result | What it verifies |
|---|---|---|
| IGV-P3-1a..c | ✅ (3) | .igv parser accepts valid views; zero error diagnostics |
| IGV-P3-2a..k | ✅ (11) | Emitted artifact structure, digest, elements, rules |
| IGV-P3-2b | ✅ | **tabs.igv digest == P1 digest** (identical content) |
| IGV-P3-3a..d | ✅ (4) | Artifact renders via SSRRenderer; deterministic; static page |
| IGV-P3-4a..c | ✅ (3) | Artifact JSON structure correct for JS runtime hydration |
| IGV-P3-5 | ✅ | P1 37/37 still pass |
| IGV-P3-6 | ✅ | P2 18/18 still pass |
| IGV-P3-7 | ✅ | P2 DOM 15/15 still pass |
| IGV-P3-8a..d | ✅ (4) | Banned opcode caught at DSL level; no artifact; two-fence |
| IGV-P3-9a..c | ✅ (3) | Undeclared slot: warning produced; P2 filter fence intact |
| IGV-P3-10a..e | ✅ (5) | NameError, undeclared slot warning, inline compile, error capture |
| IGV-P3-11a..e | ✅ (5) | No eval/innerHTML/fetch/contract in compiler source |
| IGV-P3-12 | ✅ | igniter-lang/** untouched |
| **Total** | **42/42** | |

---

## 9. What This Is Not (Non-Claims)

| Claim | Status |
|---|---|
| Canonical `.igv` syntax for Igniter-Lang | **No** — sketch only, may change entirely |
| Stable public compiler API | **No** — `IgvCompiler` is lab-internal |
| Production frontend DSL | **No** |
| Grammar-based parser | **No** — uses Ruby `instance_eval`; grammar TBD if needed |
| Portability to non-Ruby compiler host | **No** — Ruby-only prototype |
| Igniter-Lang spec proposal | **No** — lab-to-canon pressure path via Supervisor review |

---

## 10. Lab-to-Canon Pressure Findings

These findings may apply upstream pressure on the Igniter-Lang spec (via Supervisor review):

**Finding 1 — The ViewArtifact format is a sound compilation target.**
The `tabs.igv` DSL and its compiled artifact have identical semantics to the hand-authored
P1 fixture, producing bit-identical digests. The artifact shape has enough expressive power
for the current UI primitives without requiring parser-level changes.

**Finding 2 — The param/slot duality is clean but may need a clearer grammar.**
Using `param(:id)` for both declaration (with type:) and expression (without type:) is
ergonomic in Ruby DSL form but would be ambiguous in a grammar-based parser without
explicit context rules. A canonical `.igv` grammar would need to distinguish:
- `param id: string` (declaration, in element header) vs
- `param(id)` (expression, in condition/rule body)

**Finding 3 — The `:style` vs `:match` display rule shape is minimal but sufficient.**
All current display patterns fit `:style` (binary condition). `:match` adds N-way dispatch.
These two cover the same surface as Tailmix's `if/when` pattern without importing Tailmix.

**Finding 4 — Undeclared slot warnings suggest a need for a "slot contract" linkage.**
The warning is produced when a `.igv` file references a slot not declared at view level.
A future compiler phase could validate slot declarations against a contract output schema
(from the Igniter Lang type system). This would close the loop from contract type to view
type at compile time, not just at runtime.

---

## 11. Next Slice Recommendations

### Option A — IVF-P4: `.igv` Grammar Sketch (text format)
Write a formal grammar (EBNF or PEG) for `.igv` syntax as a language-agnostic spec.
The Ruby DSL prototype proves the semantics; a grammar would separate syntax from
Ruby embedding. Enables non-Ruby tooling (IDE completion, linting) in the future.

### Option B — IVF-P4: Collection Rendering
Extend ViewArtifact with `collections` — a named list of element instances each carrying
their own `node_params`. Add `collection` DSL keyword to `.igv`. Test `match` display rule
with multiple param values. SSR renders all items; JS re-renders on UIState change.

### Option C — IVF-P4: Slot-Contract Type Linkage
Validate that declared `.igv` slot types match the Igniter contract's declared output types.
Requires a contract schema introspection API. Closes the static type gap found in Finding 4.

**Recommended: Option A** — grammar formalisation separates "what .igv means" from "how it
is parsed in Ruby", enabling the spec to evolve independently of the Ruby prototype.
