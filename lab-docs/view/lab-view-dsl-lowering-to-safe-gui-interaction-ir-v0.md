# View DSL Lowering to Safe GUI Interaction IR

Status: `experimental · lab-only · research`
Track: `lab-view-dsl-lowering-to-safe-gui-interaction-ir-v0`
Card: LAB-VIEW-DSL-P6
Base: [lab-tailmix-inspired-gui-interaction-ir-schema-v0.md](../gui/lab-tailmix-inspired-gui-interaction-ir-schema-v0.md)

---

## 1. Context & Architectural Design

Under this track, we design and prototype the **Ahead-of-Time (AOT) lowering pipeline** translating View DSL event and display declarations into safe, declarative GUI Interaction IR structures embedded inside `view_tree.json`. This implements a compiler-checked rendering and interaction boundary while keeping Tailmix purely as concept pressure.

### 1.1 Stack-Based Builder Scoping

To allow inline layout rules to target the correct DOM element, we redesigned the parser builder scoping using a stack of currently building elements (`@building_nodes`). During DSL evaluation:
*   When a tag block starts (e.g. `button do ... end`), a new `HtmlNode` is pushed onto `@building_nodes`.
*   DSL methods evaluated inside the block (`ui_state`, `display_rule`, `interaction_rule`, `node_param`) modify the tag node at the top of the stack.
*   Once the block completes, the node is popped from `@building_nodes` and appended to the sibling list, preserving correct structural association.

### 1.2 DSL Syntax & Target Lowering Fields

The View DSL now supports the following safe declarations:
1.  **`ui_state(key, default_value)`**: Declares a transient local state property and its default value, compiled to the node's `ui_states` map.
2.  **`display_rule(rule_array)`**: Declares conditional classes and ARIA attributes in a LISP-like format, compiled to the node's `display_rules` list.
3.  **`interaction_rule(event, instructions_array)`**: Declares event trigger instructions (using whitelisted opcodes `set_ui_state`, `toggle_ui_state`, `clear_ui_state`), compiled to the node's `interaction_rules` list.
4.  **`node_param(key, value)`**: Declares contextual variables (e.g., `id: "overview"`), compiled to the node's `node_params` map.

---

## 2. Proof Verification Matrix (VDSL-IR-1 through VDSL-IR-12)

We verify the compilation and security boundaries using a dedicated proof runner: [run_ir_proof.rb](../../frame-ui/igniter-view-engine/run_ir_proof.rb).

| Rule / Check | Requirement | Verification Status | Notes / Proof Evidence |
| :--- | :--- | :--- | :--- |
| **VDSL-IR-1** | DSL compiles `display_rules` | `PASS` | Evaluated on buttons in `interactive_view_tree.json` fixture. |
| **VDSL-IR-2** | DSL compiles `on :click` | `PASS` | Compiles click interactions to whitelisted opcode arrays. |
| **VDSL-IR-3** | UIState defaults are separate | `PASS` | `ui_states` and `state_slots` are separate fields. |
| **VDSL-IR-4** | SlotValue mutation fails closed | `PASS` | Attempting to mutate a slot value raises a compilation error. |
| **VDSL-IR-5** | Banned opcodes are rejected | `PASS` | Opcodes `fetch`, `dispatch`, etc. raise compiler safety exceptions. |
| **VDSL-IR-6** | Node parameters are compiled | `PASS` | Mapped from `node_param` call into `node_params` JSON key. |
| **VDSL-IR-7** | accepted by IDE evaluator | `PASS` | IDE evaluates display/interaction rules successfully. |
| **VDSL-IR-8** | Separate safety policy and evaluator | `PASS` | TypeScript and Ruby evaluators remain structurally separate. |
| **VDSL-IR-9** | Proof runner emits summary JSON | `PASS` | Emits summary JSON at `out/ir_proof_summary.json`. |
| **VDSL-IR-10**| TS build/check recorded | `PASS` | Clean check except for pre-existing errors in `DebuggerPanel`. |
| **VDSL-IR-11**| Main projects untouched | `PASS` | Mainline folders untouched; changes confined to playgrounds. |
| **VDSL-IR-12**| Lab-only wording preserved | `PASS` | Strictly experimental, research status. |

---

## 3. Lowering Proof Summary Output (VDSL-IR-9)

The proof runner output at `out/ir_proof_summary.json` records compile-time successes and safety violations:

```json
{
  "timestamp": "2026-06-06 07:56:52 +0300",
  "overall_status": "SUCCESS",
  "results": {
    "VDSL-IR-1": true,
    "VDSL-IR-2": true,
    "VDSL-IR-3": true,
    "VDSL-IR-4": true,
    "VDSL-IR-5": true,
    "VDSL-IR-6": true,
    "VDSL-IR-7": true,
    "VDSL-IR-8": true
  },
  "diagnostics": [
    {
      "timestamp": "2026-06-06 07:56:52 +0300",
      "kind": "safe_renderer_warning",
      "message": "Interaction Security Violation: Blocked banned side-effect opcode 'fetch'"
    },
    {
      "timestamp": "2026-06-06 07:56:52 +0300",
      "kind": "safe_renderer_warning",
      "message": "Interaction Security Violation: Blocked banned side-effect opcode 'dispatch'"
    },
    {
      "timestamp": "2026-06-06 07:56:52 +0300",
      "kind": "safe_renderer_warning",
      "message": "Interaction Security Violation: Banned/Unknown opcode 'custom_banned_op'"
    },
    {
      "timestamp": "2026-06-06 07:56:52 +0300",
      "kind": "safe_renderer_warning",
      "message": "Interaction Security Violation: Attempted mutation of read-only SlotValue 'is_locked'"
    }
  ]
}
```

---

## 4. UIState-Driven Tab Switching Preview Demo (TMX-P2-8)

When the view engine runs, it compiles the interactive panel fixture into the shared preview artifact. In the IDE viewport, the renderer evaluates these rules dynamically:

1.  **Initial Render**: The container is initialized with `active_tab = "overview"`. The Overview button evaluates to `bg-ignite text-ink-1 font-bold` (display condition is true). The Overview content panel is visible (`block`), and Logs is hidden (`hidden`).
2.  **User Click**: Clicking the "Execution Logs" tab triggers the `interaction_rule`:
    *   `['set_ui_state', 'active_tab', ['param', 'id']]` is evaluated with local param `{ id: "logs" }`.
    *   State transition is processed safely, updating `active_tab = "logs"`.
    *   Svelte reactivity propagates the new state down the tree, showing the Logs panel and highlighting the Logs tab border immediately.
3.  **Audit Trace**: The transition is recorded in the Diagnostics Timeline:
    *   `State Transition: activeUIState -> {"active_tab":"logs"}`

This verifies that View DSL authored layouts compile down to safe declarative interaction IRs that can be run interactively inside sandboxed previews.
