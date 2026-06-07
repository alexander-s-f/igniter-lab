# Tailmix Concept Applicability to Igniter GUI — Variant A

Status: `experimental · lab-only · research`
Track: `lab-tailmix-concept-applicability-to-igniter-gui-v0`
Card: LAB-TAILMIX-P1-A
Agent: [Igniter-Lang Research Agent]
Date: 2026-06-06

Base:
- `language-covenant.md` (Postulates 4, 7, 18, 27, 28)
- `lab-igniter-lang-to-gui-research-boundary-v0.md`
- `lab-experimental-view-tree-renderer-contract-and-typecheck-cleanup-v0.md`
- `lab-experimental-view-tree-safe-policy-edgecases-and-state-slot-preflight-v0.md`
- Tailmix source: `lib/tailmix/**`, `app/javascript/tailmix/**`

Complements: `lab-tailmix-concept-applicability-to-igniter-gui-v0.md` (from LAB-TAILMIX-P1).

This variant goes deeper on: JSON IR structure, scope/param model, dual-interpreter
architecture, watcher reactive model, and hydration data contract. It produces a
finer-grained boundary decision on each concept.

---

## 1. Tailmix Architecture — Precise Summary (TMX-R1)

Tailmix has six distinct layers. Each must be assessed separately:

| Layer | What it is | File |
|---|---|---|
| **DSL** | Ruby `tailmix do` block; component/element/state/variant/event/watcher | `dsl/component_parser.rb`, `element_parser.rb`, `action_parser.rb` |
| **AST** | Typed Ruby Structs: `Component`, `ElementDefinition`, `StyleRule`, `MatchRule`, `EventRule`, `WatchRule`, `Assignment`, `Toggle`, `Fetch`, `Dispatch`, `VariableReference`, `BinaryOp` | `ast/nodes.rb` |
| **Compiler (JSONGenerator)** | AST visitor → plain Ruby Hash (also valid JSON) | `compiler/json_generator.rb` |
| **Definition Hash** | Serialized component contract: states, types, persistence, variants, elements (with rules), boot, watchers | in-memory Hash / JSON over wire |
| **SSR Facade** | Ruby interpreter evaluates rules against variant+state at render time → produces HTML attributes | `runtime/facade_builder.rb`, `interpreter/renderer.rb`, `interpreter/evaluator.rb` |
| **JS Runtime** | Browser: hydrates from `data-tailmix-state` JSON, binds events, renders rules, patches DOM | `runtime/component.js`, `interpreter/action_interpreter.js`, `interpreter/renderer.js`, `interpreter/dom_patcher.js` |

The critical insight is that **the Definition Hash is the contract between all layers**:
compiler → SSR facade → JS runtime all consume identical format. This isomorphic
design is Tailmix's core architectural value proposition.

---

## 2. State vs. Variant — Igniter Mapping (TMX-R2)

### 2.1 Tailmix Definitions

```
state  :open, default: false         # mutable · JS-managed · optionally persisted
variant :size, default: :md          # static · SSR-resolved · invisible to JS
```

`tailmix(size: :lg, open: true)` in the Facade splits kwargs:
- variant keys → `@variants` (frozen at construction)
- remainder → `@state` (initial JS seed)

### 2.2 Igniter Analogues

| Tailmix | Igniter analogue | Mapping quality | Notes |
|---|---|---|---|
| `variant` | **Compile-time contract parameter** (input with no default, resolved once) | **Clean map** | Same semantic: static, compile-resolved, no runtime mutability |
| `variant` (with default) | **Form field pre-fill / static UI configuration** in `form_table.json` | **Clean map** | `size: :lg` ↔ "render this form in compact mode" |
| `state` | **Local UI slot** (tab active state, panel open/closed, loading flag) | **Partial map** | Igniter must separate from immutable execution receipts |
| `state` | **Runtime result packet slot** (`contract_output_ref` in `StateSlot`) | **NOT a map** | Igniter result packets are immutable; `state` is mutable. Conflation is dangerous. |

**Decision:** Igniter must name two distinct concepts that Tailmix unifies under `state`:

```
UIState   — transient, locally-owned, non-canonical, IDE-layer only
            (tab selection, open/close, loading spinner)

SlotValue — injected from immutable contract execution receipt; read-only in UI
            (already modeled in VSLOT-1 schema as StateSlot with contract_output_ref)
```

Mixing these is an accountability violation: a mutable UI state pretending to be an
execution receipt violates Postulate 5 (outputs are immutable values) and Postulate 8
(receipts are proofs). This distinction must be explicit in any future GUI IR schema.

---

## 3. Rule / Effect Model — Mapping (TMX-R3)

### 3.1 Tailmix Rule Structure

The JSONGenerator compiles every rule to a tagged array:

```
[:style, condition_expr, true_effect, false_effect]
[:match, subject_expr, { "val" => effect }, default_effect]
[:on, "click", [instruction, ...]]
[:watch, subject_expr, [instruction, ...]]
```

An effect is a compact hash with shorthand keys:
```
{ "c" => "class string", "d" => { key: expr }, "a" => { key: expr }, "p" => { key: expr } }
```

The Renderer (`renderer.js`) evaluates rules against `(state, param, element)` scope
to produce accumulated `{ classes, data, aria, props }` which the DOMPatcher applies.

### 3.2 Igniter Research Applicability

The **rule array format** is strongly applicable as a research pattern for Igniter
static GUI interaction IR, with important restrictions:

**What maps cleanly:**

| Tailmix rule | Igniter candidate | Notes |
|---|---|---|
| `[:style, condition, true_eff, false_eff]` | **Slot display rule** | Condition references SlotValue; effect is class token or visibility flag |
| `[:match, subject, cases, default]` | **Discrete output renderer** | Maps `enum_output` or `confidence_band` to design token |
| Effect `{ "c" => "classes" }` | **Design token class toggle** | Safe; no DOM escape |
| Effect `{ "a" => { key: expr } }` | **ARIA state from slot value** | E.g. `aria-expanded` driven by SlotValue bool |

**What requires restriction:**

The Tailmix rule format allows `condition_expr` to be any `BinaryOp` / `MethodCall`
tree. In Igniter's IDE preview this must be constrained to:
- Comparisons against `SlotValue` or `UIState` references only
- No `MethodCall` (`.length`, indexing) in display conditions — only literal comparisons and boolean operators
- No `[:event, ...]` domain in display rules (event scope is action-only)

**What must be rejected:**

`[:on, "event", instructions]` must be separated from `[:style, ...]` rules in any
Igniter IR schema. Display rules (style/match) are read-only and can be evaluated
at render time. Action rules (on/watch) require a separate safety envelope.

---

## 4. Event Instruction Model — Mapping and Safety (TMX-R4, TMX-R8)

### 4.1 Tailmix Instruction Opcodes

The `ActionInterpreter` executes five opcodes:

| Opcode | What it does | Safety class |
|---|---|---|
| `set` | Assigns `value_expr` to `[:state, "name"]` → calls `component.update(patch)` | **UI-local · safe if target = UIState** |
| `toggle` | Flips boolean at `[:state, "name"]` | **UI-local · safe** |
| `dispatch` | Creates `CustomEvent`, dispatches on component root element | **Cross-component · requires authority** |
| `log` | `console.log` | **Dev-only · safe** |
| `fetch` | Performs actual HTTP fetch, sets response into state | **I/O · MUST be rejected for Igniter** |

### 4.2 What Igniter Can Use

A restricted opcode set for IDE-layer UI interaction:

```
set     [ui_state_ref, value_expr]          # local UIState mutation only
toggle  [ui_state_ref]                      # boolean flip on UIState
clear   [ui_state_ref]                      # reset to declared default
```

Key restriction: the target domain must always be `[:ui_state, "name"]`, never
`[:slot, ...]` (slot values are immutable receipts). The evaluator must reject
any instruction targeting outside the UIState domain.

### 4.3 What Igniter Must Reject

| Tailmix opcode | Igniter decision | Reason |
|---|---|---|
| `fetch` | **REJECT** | Direct HTTP side effects violate Postulate 4 (named effects) + Postulate 7 (effect surface readable from header). Any data fetch must route through contract execution with a declared `escape` |
| `dispatch` (CustomEvent to DOM) | **REJECT in static view IR** | Cross-component DOM communication outside compiler graph; unauditable. In IDE-tool layer only if explicitly scoped to IDE panel events |
| `log` | **Lab-only / dev surface** | Acceptable in IDE debug mode; strip from any non-dev artifact |
| `watch` | **REJECT for static view IR** | Reactive watchers require a running JS component; incompatible with static view-tree model |

### 4.4 Safety Envelope Requirements

If Igniter defines a GUI interaction opcode evaluator in the IDE:

1. **Opcode whitelist**: Only `set`, `toggle`, `clear` permitted
2. **Target domain restriction**: Target must resolve to UIState (declared in view_tree.json schema, not derived from runtime)
3. **No `window`/`document` access**: Evaluator has no global scope access
4. **No expression side effects**: Expression evaluation is pure read-only; only instruction execution mutates UIState
5. **Capability fence**: Any instruction that reaches outside UIState must be intercepted and converted to a contract dispatch request with compiler-validated Capability Passport

---

## 5. JSON Definition Format vs Igniter Artifacts (TMX-R5)

### 5.1 Tailmix Definition Hash Structure

```ruby
{
  name: "TabsState",
  states:      { "active" => "profile" },         # initial values by key
  types:       { "active" => :string },            # inferred types
  persistence: {},                                  # per-key storage config
  variants:    { "size" => { default: :md } },     # static compile-time props
  elements: [
    {
      name: "tab",
      static: { class: "px-4 py-2 ..." },         # static CSS classes
      rules: [
        [:on, "click", [[:set, [:state, "active"], [:param, "id"]]]],
        [:style, [:eq, [:state, "active"], [:param, "id"]],
          { "c" => "border-b-2 border-blue-600 ...", "a" => { "selected" => true } },
          { "c" => "border-transparent ...", "a" => { "selected" => false } }]
      ]
    }
  ],
  boot: [],
  watchers: []
}
```

### 5.2 Comparison to Igniter Artifacts

| Tailmix definition field | Igniter analogue | Comparable? |
|---|---|---|
| `states` (initial values + types) | `StateSlot` schema in view_tree.json | **Partial** — Igniter's slots reference contract outputs, not arbitrary initial values |
| `variants` | contract input parameters / form defaults | **Yes** — compile-time config with no runtime mutation |
| `elements[].static` | `HtmlNode.attributes` (static classes) | **Yes** — already modeled in view_tree.json |
| `elements[].rules[]` (`style`, `match`) | **Candidate: display rule array** in view_tree.json HtmlNode | **Research candidate** — the array encoding is directly reusable |
| `elements[].rules[]` (`on`) | Separate `interaction_rules` block | **Must be separated** from display rules |
| `boot` | **Reject** — implies component init lifecycle | Not applicable to static view-tree |
| `watchers` | **Reject for static IR** | Reactive; requires JS component runtime |
| `persistence` | **Reject** | LocalStorage/Session out of scope for contract presentation layer |

### 5.3 Candidate Igniter GUI IR Sketch

Based on Tailmix's format, a minimal static interaction IR for Igniter could look like:

```json
{
  "view_node_id": "tab_header",
  "ui_states": {
    "active_tab": { "type": "string", "default": "overview" }
  },
  "slot_refs": {
    "confidence": {
      "contract_output_ref": "risk_model.confidence",
      "value_kind": "number",
      "render_policy": "class_toggle",
      "fallback": 0
    }
  },
  "display_rules": [
    ["style", ["eq", ["ui_state", "active_tab"], ["param", "id"]],
      { "c": "border-b-2 border-brand-600", "a": { "selected": true } },
      { "c": "border-transparent", "a": { "selected": false } }],
    ["match", ["slot", "confidence"],
      { "high": { "c": "badge-green" }, "low": { "c": "badge-red" } },
      { "c": "badge-gray" }]
  ],
  "interaction_rules": [
    ["on", "click", [["set", ["ui_state", "active_tab"], ["param", "id"]]]]
  ]
}
```

Key differences from Tailmix:
- `ui_states` and `slot_refs` are explicitly separated (not unified as `state`)
- `display_rules` and `interaction_rules` are separate arrays with separate evaluators
- `slot_refs` are read-only; cannot appear as assignment targets
- No `boot`, `watchers`, `persistence`

---

## 6. Ruby / JS Mirrored Interpreter Assessment (TMX-R6)

### 6.1 What Tailmix Does

Tailmix maintains two parallel interpreters for the same Definition Hash:
- `lib/tailmix/interpreter/` (Ruby) — used for SSR and RSpec testing
- `app/javascript/tailmix/interpreter/` (JS) — used in browser

Both consume the same rule array format and produce identical HTML attributes.
This enables testing component behavior in pure Ruby without a browser.

### 6.2 Igniter Implications

The mirrored interpreter pattern is valuable as a **testing strategy**, not as an
architecture to adopt:

**Why Igniter should NOT build a mirrored interpreter:**
- Igniter does not do SSR for view trees; the view-tree is compiled static JSON
- The IDE preview runs Svelte; it does not need a Ruby renderer
- The VM (Ruby/Rust) executes contracts; view rendering is IDE-only
- Building a Ruby mirror of a JS evaluator adds maintenance surface with no prod benefit

**What Igniter can learn from the mirror pattern:**
- The test strategy: define a rule array, evaluate it in Ruby tests against fixture state,
  assert expected class output → validates rule schema without a browser
- The Scope model: `(state, param, element, variants)` is a clean separation of concerns
  that Igniter's IDE evaluator should replicate as `(ui_states, slot_refs, node_params)`
- The `Scope#clone` pattern used in watchers (creating isolated scope for each watcher run)
  is the right model for `interaction_rules` evaluator isolation in Igniter

---

## 7. Arbre / Rails / Tailwind Separation (TMX-R7)

Explicit rejection list — must not enter Igniter:

| Tailmix artifact | Rejection reason |
|---|---|
| `Rails::Engine` mount in `engine.rb` | Igniter-Lang is not Rails-bound; compiler outputs static JSON assets |
| `DefinitionsController` (serves `/tailmix/definitions/:name.json`) | Igniter compiles to `.igapp` bundle; no runtime Rails controller needed |
| `view_helpers.rb` (`tailmix_component_tag`) | Igniter IDE is Tauri/Svelte; no Rails view helpers |
| `FacadeBuilder` (builds SSR Ruby class) | Igniter view-tree is static JSON; no SSR Ruby instance needed |
| `PersistenceManager` (LocalStorage/SessionStorage) | No browser persistence for contract presentation layer |
| `BaseComponent` (Arbre parent) | Igniter VDSL compiles to view_tree.json, not Arbre instances |
| Tailwind class string management as product API | Igniter uses design system CSS token bindings, not Tailwind strings |
| `data-tailmix-component` attribute on DOM | Igniter IDE uses Svelte reactivity; no custom hydration attribute needed |
| `window.Tailmix` global JS bundle | Igniter IDE does not adopt the Tailmix JS runtime |

---

## 8. Capability / Effect Safety Implications (TMX-R8)

### 8.1 The `fetch` Problem

Tailmix's `fetch` opcode in `ActionInterpreter` calls `window.fetch` directly:

```javascript
const resp = await fetch(url, { method: options.method || 'GET', ... });
```

This is an unmediated I/O side effect triggered from a serialized instruction array.
In Igniter-Lang terms, this violates:
- **Postulate 4**: Side effects must be named (there is no `escape` declaration for `fetch`)
- **Postulate 7**: Effect surface not readable from header (the fetch target URL is a runtime value)
- **Postulate 27**: The feature hides execution reality from audit

Any Igniter GUI interaction IR that includes a `fetch`-equivalent opcode would require:
1. The fetch to route through a contract with a declared `escape` to the target
2. Capability Passport validation before execution
3. A receipt proving the fetch completed with specific URL, method, and response

Since the IDE preview layer cannot satisfy these requirements (it has no compiler,
no Capability Passport at render time), **`fetch` must be completely excluded** from
the GUI interaction IR.

### 8.2 The `dispatch` Problem

Tailmix's `dispatch` creates a DOM `CustomEvent` that bubbles:

```javascript
const ev = new CustomEvent(eventName, { bubbles: true, cancelable: true, detail });
this.component.element.dispatchEvent(ev);
```

This is cross-component communication outside the compiler's dependency graph.
It creates implicit contracts between components with no declared dependency. In
Igniter terms this is hidden state (Postulate 2: all dependencies must be declared).

For Igniter IDE panels: a restricted `dispatch` to a named IDE panel event bus
(not DOM CustomEvent) may be acceptable as lab tooling — but must not enter any
language-level GUI IR schema.

### 8.3 Capability Shield Pattern

The existing Capability Passport in the IDE (from `lab-experimental-io-capability-passport-schema-generalization-v0.md`)
is the correct mechanism for any GUI-initiated I/O. The pattern should be:

```
GUI Interaction Rule → UIState mutation only (no I/O)
    OR
GUI Interaction Rule → Emit contract dispatch request → Capability Passport check → VM execution → Result → SlotValue update
```

The second path is not GUI interaction IR — it is contract invocation, which already
has a defined pipeline (ContractFormGenerator → DispatchPanel → VM).

---

## 9. GUI / State-Slot Applicability Assessment (TMX-R9)

### 9.1 Where Tailmix Concepts Add Research Value

| Igniter GUI target | Tailmix contribution | Confidence |
|---|---|---|
| **Contract Input Forms** | `variant` model → form field defaults; `param` per-element concept → per-field render context | High |
| **Output Dashboard badges** | `[:match, subject, cases, default]` → discrete output → design token mapping | High |
| **Confidence/uncertainty display** | `[:style, condition, eff, alt]` → threshold-based class toggle | High |
| **Tab navigation in IDE** | Full `state + on :click + style` pattern → UIState-powered tab switching | Medium (lab prototype) |
| **Slot visibility rules** | `[:style, [:eq, [:slot, "x"], nil], hidden_eff, visible_eff]` | Medium |
| **View DSL authoring** | `element` + `static` attributes pattern → already present in view_tree.json | Already applied |
| **Debugger trace panel** | `watch` concept inspires "observe when node state changes" → IDE-only diagnostic | Low (too complex for static IR) |
| **Design system conformance** | `match` on variant value → design token class | High |

### 9.2 Where Tailmix Concepts Do Not Apply

| Tailmix capability | Igniter verdict | Reason |
|---|---|---|
| SSR Facade (Ruby class per component) | No | Igniter view-tree is compiled static JSON; no runtime Ruby rendering |
| Browser hydration (`data-tailmix-component`) | No | Svelte handles reactivity; no custom hydration needed |
| LocalStorage/SessionStorage persistence | No | Contract execution receipts are immutable; no client-side state persistence |
| `watch` reactive triggers | No (except IDE tooling) | Static view-tree has no JS component lifecycle |
| `boot` initialization | No | No component init lifecycle in static view-tree |
| Cross-component `dispatch` | No | Unauditable cross-component coupling outside compiler graph |
| `fetch` data loading | No | Must route through contract execution pipeline with declared escape |
| `window.Tailmix` runtime bundle | No | Not imported; not a dependency |

---

## 10. Concept Matrix — Full (Compact)

| Tailmix Concept | Igniter Candidate | Transfer Status | Risk |
|---|---|---|---|
| `variant` (static prop) | Compile-time contract parameter / form default | **Reusable Pressure** | Low |
| `state` (mutable, JS-managed) | UIState (IDE-layer only, non-canonical) | **Lab-Only Prototype** | Medium: must not conflate with SlotValue |
| `state` (result display) | SlotValue (read-only, from receipt) | **Spec Input candidate** | High: conflation = Postulate 5 violation |
| `style` / `otherwise` | Display rule `[:style, condition, eff, alt]` | **Reusable Pressure** | Low |
| `match` | Discrete output renderer `[:match, subject, cases, default]` | **Reusable Pressure** | Low |
| `element` definition | HtmlNode in view_tree.json (already adopted) | **Already Applied** | None |
| `static` attributes | HtmlNode.attributes (already adopted) | **Already Applied** | None |
| `on` (event instruction array) | Restricted opcode set in `interaction_rules` | **Lab-Only Prototype** | High: requires strict whitelist + domain restriction |
| `set` / `toggle` opcodes | UIState mutation instructions | **Lab-Only Prototype** | Medium: target domain must be UIState only |
| `fetch` opcode | **REJECT** | Reject | Critical: unmediated I/O, no audit trail |
| `dispatch` opcode | **REJECT** (IDE tool: scoped panel event only) | Reject / Lab tool only | High: cross-component coupling, unauditable |
| `watch` (reactive watcher) | IDE diagnostic only | **Lab-Only / IDE tool** | Medium: not for static view IR |
| `boot` block | **REJECT** | Reject | No component lifecycle in static view-tree |
| `persistence` (LocalStorage) | **REJECT** | Reject | No client-side state persistence for contract layer |
| JSON Definition Hash format | Candidate: GUI interaction IR schema | **Future Spec Input** | Low if restricted; see §5.3 sketch |
| Mirrored Ruby/JS interpreter | Testing strategy (not architecture) | **Research Pressure** | Low |
| `param` (per-element context) | Per-node render context in display rules | **Reusable Pressure** | Low: already needed for collection item rendering |
| Scope model `(state, param, variants)` | IDE evaluator scope `(ui_states, slot_refs, node_params)` | **Reusable Pressure** | Low |
| FacadeBuilder (SSR Ruby class) | **REJECT** | Reject | No SSR Ruby rendering in Igniter view-tree path |
| Rails Engine / controller | **REJECT** | Reject | Framework coupling; compiler must remain framework-free |
| Arbre integration | **REJECT** | Reject | Igniter VDSL → static JSON, not Arbre instances |
| Tailwind class API | **REJECT** | Reject | Igniter uses design token bindings |
| Browser hydration attributes | **REJECT** | Reject | Svelte handles DOM reactivity |

---

## 11. Boundary Matrix

| Category | Items |
|---|---|
| **Reusable Research Pressure** | `variant` → param defaults; `style`/`match` rule arrays; `element.static`; `param` per-node context; Scope model; mirrored interpreter as test strategy |
| **Lab-Only Prototype** | UIState concept (local tab/open/close); `on`/`set`/`toggle` interaction opcodes in safe evaluator; `watch` as IDE diagnostic hook |
| **Future Spec Input** | SlotValue / UIState distinction as formal GUI IR schema primitive; interaction_rules JSON schema; per-node `display_rules` + `interaction_rules` separation |
| **Reject (Do Not Import)** | `fetch`; `dispatch` to DOM; `boot`; `persistence`; FacadeBuilder; Rails engine; Arbre; Tailwind class API; browser hydration attributes; `window.Tailmix` bundle |

---

## 12. Readiness Matrix (TMX-R1 through TMX-R10)

| Check | Status | Notes |
|---|---|---|
| **TMX-R1** Tailmix architecture summarized accurately | ✅ | Six-layer breakdown with file references; Definition Hash as isomorphic contract |
| **TMX-R2** State vs. variant mapped to Igniter concepts | ✅ | Explicit UIState / SlotValue split; variant → compile-time param |
| **TMX-R3** Rule/effect model mapped or rejected | ✅ | `style`/`match` mapped; `on`/`watch` conditionally accepted with safety envelope |
| **TMX-R4** Event instruction model mapped with safety caveats | ✅ | Opcode whitelist defined; `fetch`/`dispatch`/`boot` rejected with Covenant citations |
| **TMX-R5** JSON definition format compared to Igniter artifacts | ✅ | Field-by-field comparison; candidate IR sketch with explicit UIState/SlotRef separation |
| **TMX-R6** Ruby/JS mirrored interpreter assessed without adopting runtime | ✅ | Rejected as architecture; accepted as test strategy pattern |
| **TMX-R7** Arbre/Rails/Tailwind baggage explicitly separated | ✅ | Full rejection table with reasons |
| **TMX-R8** Capability/effect safety implications listed | ✅ | `fetch` = Postulate 4+7+27 violation; `dispatch` = Postulate 2 violation; capability shield pattern defined |
| **TMX-R9** Igniter GUI/state-slot applicability assessed | ✅ | Per-target applicability table for forms, dashboard, tabs, debugger |
| **TMX-R10** Exact LAB-TAILMIX-P2 recommendation produced | ✅ | See §13 below |

---

## 13. Recommendation for LAB-TAILMIX-P2 (TMX-R10)

### Recommended Slice: Static GUI Interaction IR — Prototype

**Goal:** Design and prototype a static, safe, JSON-serializable GUI interaction IR
for the IDE preview layer, based on Tailmix's rule array format, with strict domain
separation between UIState and SlotValue.

**Scope (lab-only, no canonical authority):**

1. **Schema draft** — `gui_interaction_ir.json` schema with:
   - `ui_states` block (named, typed, with defaults) — explicitly not SlotValues
   - `slot_refs` block (read-only bindings to contract_output_ref) — already in VSLOT-1
   - `display_rules` array: `[:style, ...]` and `[:match, ...]` only; condition scope = UIState + SlotRef + node param
   - `interaction_rules` array: `[:on, event, [set/toggle/clear ...]]` only; target scope = UIState only

2. **Svelte evaluator** — minimal evaluator in IDE (NOT in `safe_renderer_policy.ts` — separate module):
   - Accepts `(display_rules, ui_states, slot_values, node_params)` → returns class/aria patch
   - Pure function, no DOM access, no fetch, no CustomEvent
   - Whitelist enforced: unknown opcode → throw, no fallthrough

3. **Prototype integration** — one existing IDE panel (ContractFormGenerator or ViewInspector)
   uses the evaluator to drive tab selection or section visibility from UIState

**Hard constraints:**
- Do not implement `fetch`, `watch`, `boot`, `dispatch` opcodes
- Do not conflate UIState with SlotValue in the schema
- Do not claim stable API, portability, canonical language feature, or Reference Runtime support
- All schema and evaluator changes confined to `igniter-lab/`

**Alternative: Hold**
If the priority is forms lowering completion (LAB-FORMS track) or debugger
observability (LAB-IDE-DEBUGGER track), hold LAB-TAILMIX-P2. The research
pressure from this document is sufficient to inform those tracks without a
separate GUI IR prototype.

**Recommendation: Proceed with P2** — the UIState / SlotValue separation is a
foundational decision that will affect both forms and debugger display. Prototyping
it early prevents conflation drift across multiple lab tracks.
