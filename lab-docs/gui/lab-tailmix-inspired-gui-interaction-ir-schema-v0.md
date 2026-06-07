# Tailmix-Inspired GUI Interaction IR Schema & Safe Evaluator

Status: `experimental · lab-only · research`
Track: `lab-tailmix-inspired-gui-interaction-ir-schema-v0`
Card: LAB-TAILMIX-P2
Base: [lab-tailmix-concept-applicability-to-igniter-gui-v0-A.md](lab-tailmix-concept-applicability-to-igniter-gui-v0-A.md), [lab-tailmix-concept-applicability-to-igniter-gui-v0.md](lab-tailmix-concept-applicability-to-igniter-gui-v0.md)

---

## 1. Context & Architectural Design

Under this track, we design and implement a **static GUI Interaction Intermediate Representation (IR)** schema and a safe Svelte/TypeScript evaluation module in the `igniter-ide` playground. The architecture is inspired by Tailmix's isomorphic rule arrays but strictly hardened according to the Igniter Lang Language Covenant.

### 1.1 UIState vs. SlotValue Separation (TMX-P2-1, TMX-P2-2)

Tailmix merges dynamic client variables and data presentation properties under a single, mutable `state` construct. To preserve Igniter's core postulate of immutable contract output receipts (Postulate 5 & 8), we split this into two distinct concepts:

*   **`UIState`**: Transient, locally-owned, UI-only mutable flags (such as `active_tab` or `is_expanded`) that exist only in the IDE viewport/presentation layer.
*   **`SlotValue`**: Read-only value placeholders (`StateSlot` referencing a `contract_output_ref` path) bound directly to compiled contract outputs. **SlotValues are strictly read-only and can never be targeted by UI mutations.**

### 1.2 display_rules vs. interaction_rules (TMX-P2-3, TMX-P2-4)

To prevent interaction triggers from interfering with display layout ordering, we separate layout logic and user triggers into two independent arrays:

1.  **`display_rules`**: Pure, side-effect-free mappings of type `(UIState, SlotValues, NodeParams) => AttributeEffect`. They evaluate display conditions using a restricted expression tree.
2.  **`interaction_rules`**: Declarative event trigger mappings of type `(EventName, Instructions[]) => UIStateMutation`. They only mutate `UIState` keys via a strict whitelist of safe, side-effect-free opcodes.

---

## 2. Implementation Specifications

The module has been implemented in a dedicated file: [gui_interaction_ir.ts](../../igniter-ide/src/lib/gui_interaction_ir.ts).

### 2.1 Whitelisted Opcodes & Covenant Hardening (TMX-P2-6)

The evaluator implements a strict whitelist for interaction instructions:
*   `set_ui_state`: Assigns an expression value to a declared `UIState` key.
*   `toggle_ui_state`: Flips the boolean value of a declared `UIState` key.
*   `clear_ui_state`: Resets a declared `UIState` key to `null`.

**All side-effect opcodes from Tailmix (`fetch`, `dispatch`, `boot`, `watch`, `persistence`) are explicitly rejected by the parser/evaluator.** Unmediated network requests, cross-component event bubbling, lifecycle side effects, and client-side persistence are disallowed under Postulates 4 (named effects) and 7 (explicit effect surfaces).

### 2.2 Node Params / Local Context (TMX-P2-7)

To support rendering collections and parameterized lists, display and interaction evaluations accept a `NodeParams` map. Expression evaluation resolves `['param', 'key']` references, enabling individual elements in a list (e.g. tab items or accordion headers) to pass their respective local identifiers (like `param.id`) during trigger dispatches.

---

## 3. Proof Verification Matrix

We verify the safety boundaries of the interaction engine against the following rules:

| Rule / Check | Requirement | Verification Status | Notes / Proof Evidence |
| :--- | :--- | :--- | :--- |
| **TMX-P2-1** | `UIState` & `SlotValue` are separate | `PASS` | Modeled as distinct types `UIState` and `SlotValues` in [gui_interaction_ir.ts](../../igniter-ide/src/lib/gui_interaction_ir.ts#L20-L24). |
| **TMX-P2-2** | `SlotValue` cannot be mutated | `PASS` | The interaction evaluator blocks any instructions targeting keys outside the declared `UIState` keys. |
| **TMX-P2-3** | `display_rules` are pure | `PASS` | `evaluateDisplayRule` does not perform mutations or write side effects. |
| **TMX-P2-4** | `interaction_rules` mutate only `UIState` | `PASS` | Checked via strict validation: instruction targets must exist in `uiState` parameters. |
| **TMX-P2-5** | Slot value mutation fails closed | `PASS` | Asserted in Security Proof: attempting to mutate `is_locked` (SlotValue) returns `success: false` and logs warning. |
| **TMX-P2-6** | Banned opcodes are rejected | `PASS` | Asserted in Security Proof: opcode `fetch` is explicitly intercepted and fails closed. |
| **TMX-P2-7** | Node parameters are supported | `PASS` | Verified by resolving `['param', 'id']` within display conditions and interaction assignments. |
| **TMX-P2-8** | Tab/Panel fixture produces deterministic transition | `PASS` | Verified in Tab Proof: click triggers `active_tab` transition from `'overview'` to `'profile'`, updating styles. |
| **TMX-P2-9** | Malformed rule payload fails closed | `PASS` | Evaluator checks array structures, unknown opcodes, and domain references, failing immediately. |
| **TMX-P2-10**| TypeScript build compiles | `PASS` | Ran `npm run check` in playground. Zero type errors introduced in view files. |
| **TMX-P2-11**| Canon/projects untouched | `PASS` | All additions confined to `igniter-ide/src/lib/gui_interaction_ir.ts` and `ViewInspector.svelte`. |
| **TMX-P2-12**| Lab-only wording preserved | `PASS` | Documentation maintains strict experimental/research status. |

---

## 4. Verification Proofs Console Log (TMX-P2-8)

We integrated the verification proof runner directly inside the IDE View Inspector page. On mount, Svelte executes the proofs in [gui_interaction_ir.ts](../../igniter-ide/src/lib/gui_interaction_ir.ts#L430) and logs the results inside the **Diagnostics Timeline** for audit transparency:

```
[Diagnostics Timeline Logs]
1. [Security Proof] Event domain display diagnostics: 'Expression Error: Banned domain reference 'event' in display expression'
2. [Security Proof] Event domain in display result success = false
3. [Security Proof] Fetch diagnostics: 'Interaction Security Violation: Banned side-effect opcode 'fetch' is blocked by Covenant Passport'
4. [Security Proof] Banned opcode 'fetch' result success = false
5. [Security Proof] Mutate slot diagnostics: 'Interaction Error: Target UIState key 'is_locked' does not exist. Mutation blocked.'
6. [Security Proof] Mutate read-only slot result success = false
7. [Security Proof] Running vulnerability payload tests...
8. [Panel Proof] Mutated state: is_expanded = true
9. [Panel Proof] Initial visibility: 'hidden', error style: 'border border-oof bg-oof/5'
10. [Panel Proof] Initial state: is_expanded = false
11. [Tab Proof] Post-click display classes: 'border-b-2 border-ignite text-ignite' (selected = true)
12. [Tab Proof] Mutated state: active_tab = 'profile'
13. [Tab Proof] Initial display classes: 'border-transparent text-grey hover:text-warm-3' (selected = false)
14. [Tab Proof] Initial state: active_tab = 'overview'
15. ⚡ Starting Igniter GUI IR Verification Proofs...
```

---

## 5. Tailmix as Concept Pressure Only

Tailmix remains **concept pressure only** because:
1.  **No Native Integration:** We do not import the `tailmix` Ruby gem or bundle its JavaScript runtime. The Svelte preview uses its own safe, zero-dependency typescript evaluator.
2.  **No Server-Side Interop:** Igniter does not evaluate interaction rules in Ruby. All logic lowerings are compiled ahead-of-time to static JSON.
3.  **Strict Security Postulates:** The Covenant requires explicit capability scoping. By stripping browser dependencies (like `window.fetch`), we guarantee that views remain sandboxed displays rather than unmediated execution layers.
