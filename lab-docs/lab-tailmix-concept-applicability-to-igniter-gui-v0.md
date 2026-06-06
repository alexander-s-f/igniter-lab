# Tailmix Concept Applicability to Igniter GUI/State-Slot Interaction

Status: `experimental · lab-only · research`
Track: `lab-tailmix-concept-applicability-to-igniter-gui-v0`
Base: [lab-igniter-lang-to-gui-research-boundary-v0.md](../lab-docs/lab-igniter-lang-to-gui-research-boundary-v0.md), [lab-experimental-view-tree-safe-policy-edgecases-and-state-slot-preflight-v0.md](../lab-docs/lab-experimental-view-tree-safe-policy-edgecases-and-state-slot-preflight-v0.md)

---

## 1. Executive Summary & Tailmix Architecture

This document assesses the applicability of **Tailmix** design patterns to the **Igniter Lang** GUI, View DSL, and state-slot boundary. The goal is to determine how Tailmix's approach to declarative component state and serialized event handling can pressure-test and refine Igniter's frontend preview/interaction pipeline without introducing Tailmix dependencies, runtime bloat, or canonical framework drift.

### 1.1 Tailmix Architecture Overview

Tailmix ([README.md](../../tailmix/README.md)) is a declarative, state-driven attributes manager designed for server-rendered and hydrated Ruby components. Its engine relies on a twin-layer compiler/runtime boundary:

1. **Compilation (Ruby AST & JSON):** The DSL in [dsl.rb](../../tailmix/lib/tailmix/dsl.rb) parses components via specialized parsers (like [action_parser.rb](../../tailmix/lib/tailmix/dsl/action_parser.rb)) into structured AST nodes in [nodes.rb](../../tailmix/lib/tailmix/ast/nodes.rb). The [json_generator.rb](../../tailmix/lib/tailmix/compiler/json_generator.rb) compiles the AST into a plain Ruby Hash / JSON-serializable definition dictionary.
2. **Server-Side Render (SSR Facade):** A dynamic Ruby Facade class resolves compile-time variants and applies initial rules during server-side HTML rendering using a Ruby interpreter ([renderer.rb](../../tailmix/lib/tailmix/interpreter/renderer.rb) and [evaluator.rb](../../tailmix/lib/tailmix/interpreter/evaluator.rb)).
3. **Browser Hydration (JS Interpreter):** The client-side runtime ([component.js](../../tailmix/app/javascript/tailmix/runtime/component.js)) mounts onto DOM elements using `data-tailmix-component` attributes. It manages client state, intercepts events, and evaluates compiled JSON rules in the browser to run DOM updates via a mirrored JS evaluator and patcher.

---

## 2. Concept Mapping & Applicability Analysis

### 2.1 State vs. Variant Mapping (TMX-R2)

| Tailmix Concept | Definition | Igniter Analogue | Mapping Status & Translation |
| :--- | :--- | :--- | :--- |
| **`variant`** | Static, compile-time properties passed during SSR rendering (no JS visibility). | **Contract Parameters / Compile-Time Configuration** | **Clean Map.** Igniter uses compile-time parameters to customize view instances. These are evaluated by the View Engine parser during static lowerings and do not change after compilation. |
| **`state`** | Mutable JS runtime properties managed reactively in the client. | **Runtime Result Packets & Local UI Slots** | **Partial Map.** Igniter splits "state" into two: (1) *Immutable execution receipts* (returned by the VM), and (2) *Local UI interaction state* (e.g. open/closed, active tab, loading status). Igniter must separate these to maintain logic/view boundaries. |

### 2.2 Rule & Effect Model (TMX-R3)

Tailmix models conditions via a nested LISP-like instruction format:
* `[:style, condition, consequent_effect, alternate_effect]`
* `[:match, subject, cases_map, default_effect]`

Applying this to Igniter:
* **Recommendation:** **Adopt as static pressure.** Instead of introducing an active runtime VM in the browser for layout styling, Igniter can compile conditional display states (e.g. "show warning border if confidence < 80%") into static metadata fields in `view_tree.json`.
* **Translation:** Svelte-level rendering in the IDE ([ViewNodeRenderer.svelte](../igniter-ide/src/lib/components/ViewNodeRenderer.svelte)) can evaluate these rule structures reactively based on imported static Mock/Receipt files, maintaining safety without embedding a JS engine in the user's application.

### 2.3 Event Instruction Model & Safety (TMX-R4, TMX-R8)

Tailmix serializes action hooks into JSON arrays:
```ruby
on :click do
  set state.active, param.id
  toggle state.open
end
```
Compiles to:
```json
[
  ["on", "click", [
    ["set", ["state", "active"], ["param", "id"]],
    ["toggle", ["state", "open"]]
  ]]
]
```

This serialized representation is highly applicable to **Igniter's Safe Preview Boundaries**:
1. **No Arbitrary Scripting:** The IDE preview must absolutely forbid raw JavaScript execution (`onclick="..."`, inline `<script>`) to prevent security leaks ([safe_renderer_policy.ts](../igniter-ide/src/lib/safe_renderer_policy.ts)).
2. **Declarative Mutation Opcodes:** By adopting a whitelisted list of instruction opcodes (e.g., `set`, `toggle`, `clear`), Igniter can allow developers to declare safe UI updates in their View DSL. The IDE's sandbox renderer interprets these rules safely without exposing DOM access.
3. **Capability Passport Enforcement:** If an event requests an external boundary crossing (like `fetch` or `dispatch`), the IDE intercepts the instruction array, checks it against the contract's Capability Passport, and prompts the user for authorization before performing the operation.

---

## 3. Separation of Concerns & Rejections

### 3.1 Ruby/Rails Framework Baggage (TMX-R7)

Tailmix is deeply coupled to Rails infrastructure (Rails Engines, controllers to serve definitions, and Arbre layout trees). Igniter-Lang **must reject** these features to avoid framework drift:

* **No Rails Engine / Controller mounts:** Igniter's compiler and runtime must remain independent of specific web frameworks. It compiles to static JSON assets (`view_tree.json`, `contract_id.json`) that can be consumed by any client application (Svelte, React, or native IDE panels).
* **No Ruby SSR Facade Classes:** Igniter views do not maintain mutable Ruby object instances at render time. Rendering is either fully compiled static HTML or statically declared Svelte templates.
* **No Tailwind Class Utility API:** While Tailmix provides dedicated class helpers, Igniter-Lang focuses on type-safe CSS token bindings mapped from design systems, preventing Tailwind dependency injection into the compiler.

---

## 4. Architectural Matrices

### 4.1 Concept Applicability Matrix

| Tailmix Concept | Igniter Candidate | Transfer Status | Risk / Consideration |
| :--- | :--- | :--- | :--- |
| **`state` / `variant`** | `StateSlot` / `Parameter` | **Transfer** | Need to separate transient UI state from core contract execution results. |
| **`style` / `otherwise`** | Conditional Class Tokens | **Transfer** | Simple boolean class toggling helps UI styling without full Svelte logic. |
| **`match`** | Switch-Case rendering | **Transfer** | Helps mapping discrete variants (e.g. `size = sm/md/lg`) to specific design tokens. |
| **`on` (event instructions)** | Serializable Action IR | **Lab Prototype** | Must enforce strict whitelisting to prevent runtime escape. |
| **`fetch`** | Capability IO Node | **Reject** | Disallowed inside presentation views. Must lower to explicit capability ports. |
| **`watch`** | Reactive Diagnostics hook | **Lab-Only** | Useful for IDE-level live tracing, but too complex for static view specs. |
| **Persistence** | LocalStorage bindings | **Reject** | State persistence is out of scope for contract presentation layers. |
| **DOM Patching** | Svelte client reactivity | **Reject** | Svelte handles DOM reconciliation; no custom patcher needed. |

### 4.2 Boundary & Route Matrix

| Reusable Pressure | Lab-Only Prototype | Reject (Do Not Import) | Future Spec Input |
| :--- | :--- | :--- | :--- |
| * Declarative styling rules  <br>* Serialized action arrays <br>* State vs. Variant distinction | * Interactive Action IR interpreter in Svelte <br>* Preflight telemetry badges <br>* Visual state-slot toggles in the IDE | * Rails mount points <br>* Arbre-server facade instances <br>* Direct fetch state updates <br>* Browser LocalStorage persistence | * `StateSlot` metadata schemas <br>* Capability-wrapped event declarations <br>* Form input type mappings |

---

## 5. Safety Implications & Capability Shields (TMX-R8)

If Igniter adopts a serializable event/action IR for GUI interaction, it must apply these security shields:

1. **Instruction Sandbox:** The evaluator must only support pure data transformations (e.g. copying an input value into a state slot) and toggle instructions.
2. **Access Control:** The instructions must have zero access to the `window`, `document`, or global Javascript environments.
3. **IO Capability Isolation:** Action blocks must not trigger network requests or filesystem writes directly. Instead of a Tailmix-style `fetch` command, they must emit a contract dispatch request that flows through the compiler's **IO Capability Passport** check, ensuring compile-time permission validation.

---

## 6. Recommendation for Next Slide (TMX-R10)

We recommend proceeding with **LAB-TAILMIX-P2: Static GUI Interaction IR Design & State-Slot Rule Prototype**:

* **Goal:** Design a static, JSON-serializable representation of local UI interaction rules (specifically form input changes and tab toggles) utilizing a simplified Tailmix-style opcode array format.
* **Scope:**
  1. Define a draft schema for `interaction_rules.json` that hooks into Svelte events (e.g. `on:input`).
  2. Implement a safe, zero-dependency interpreter in `safe_renderer_policy.ts` to execute `set` and `toggle` actions on static slots.
  3. Verify interaction by allowing users to toggle tabs in a mock preview dashboard inside the IDE panel, showing reactive class updates without executing raw JavaScript.
