# Safe Policy Edge Cases & State-Slot Preflight Schema (v0)

Status: `experimental · lab-only`
Track: `lab-experimental-view-tree-safe-policy-edgecases-and-state-slot-preflight-v0`
Base: `lab-experimental-view-tree-renderer-contract-and-typecheck-cleanup-v0.md`

---

## 1. Safe Policy Edge Case Hardening

Under this track, we resolved remaining edge cases in our Safe Renderer Policy to block advanced stylesheet telemetry attacks, malicious protocol tricks, and tabnabbing vectors while preserving usability.

### 1.1 Multi-Child Style Blocks (VEDGE-1)
*   **Problem:** Our previous style tag content check sanitized only the first child node. In trees generated with multiple text nodes under a single `<style>` element, remote stylesheets could still be imported in subsequent children.
*   **Resolution:** Modified [safe_renderer_policy.ts](../../igniter-ide/src/lib/safe_renderer_policy.ts) and the Ruby simulation [run_vsafe_proof.rb](../../igniter-view-engine/run_vsafe_proof.rb) to iterate over *all* children. Every child string or text node is now scanned and stripped of `@import` and `url()` directives.

### 1.2 Spaced and Case-Insensitive CSS Injection (VEDGE-2)
*   **Problem:** Attackers can bypass substring checks by injecting spaces (e.g. `url   ( ... )`) or altering casing (e.g. `@ImPoRt` or `UrL(`).
*   **Resolution:** Replaced exact substring matches with tolerant regular expressions:
  - `/@import/gi` and `/url\s*\(/gi` to block spaced/cased CSS url and import declarations in `<style>` blocks.
  - `/@import/i.test(...)` and `/url\s*\(/i.test(...)` for inline `style` attributes.

### 1.3 Suspicious Protocol Schemas (VEDGE-3)
*   **Problem:** Unsafe protocol schemes in `href`, `src`, or `style` attributes (like `javascript:`, `vbscript:`, `file:`, or `data:`) can execute unauthorized code.
*   **Resolution:** Implemented `isSuspiciousUrl` checks:
  - Blocks `javascript:`, `vbscript:`, and `file:` schemes entirely.
  - Blocks `data:` URIs unless it is a safe image data URI (`data:image/`) bound strictly to the `src` attribute of an `<img>` tag.

### 1.4 Target Blank Rel Token Merging (VEDGE-4)
*   **Problem:** Automatically replacing `rel` with `noopener noreferrer` on `target="_blank"` links wipes out other developer-specified attributes (like `rel="nofollow"` or `rel="author"`).
*   **Resolution:** Updated the policy to merge tokens:
  - If a `rel` attribute is already defined, we split it by whitespace into a token set, add `noopener` and `noreferrer`, and join them back to preserve existing tokens.
  - If no `rel` is defined, we fall back to `noopener noreferrer`.

---

## 2. State-Slot Preflight Schema

To prepare for future runtime and VM evidence mapping, we designed a declarative **State-Slot** schema. This schema enables templates to define dynamic placeholder fields in the visual AST, which the IDE can highlight and inspect prior to active VM integration.

### 2.1 State-Slot Schema Definition (VSLOT-1)
State slots are declared as an optional array (`state_slots?: StateSlot[]`) on any `ViewNode` in the JSON tree:

```typescript
export interface StateSlot {
  slot_id: string             // Unique ID inside the layout scope
  contract_output_ref: string // reference path to target compiled igniter contract node
  value_kind: 'string' | 'number' | 'boolean' | 'temporal' | 'array' | 'object'
  render_policy: 'text' | 'attribute' | 'visibility' | 'class_toggle'
  fallback: any               // Fallback display value before VM evaluation
}
```

### 2.2 Visual Representation in the IDE (VSLOT-2)
1.  **Dashed Border Overlay:** Elements containing active slots are rendered in the preview canvas with a dashed temporal border: `border border-dashed border-temporal/30`.
2.  **Telemetry Badge:** A floating badge `⚡ slot: slot_id` appears at the bottom-right of the active boundary.
3.  **Details Inspector:** When selecting a node in the tree walker, the right pane displays a dedicated **State Slots** panel showing the `Ref`, `Policy`, and `Fallback` values.

---

## 3. Pre-existing Type Errors

We ran type validation via `npm run check` and verified that:
*   No TypeScript errors were introduced in the view preview files.
*   The pre-existing errors in `DebuggerPanel.svelte` (`cap` type warning) remain isolated and do not prevent code packaging.

---

## 4. Proof Matrix Verification

| Rule ID | Requirement | Result | Verification Notes |
|---------|-------------|--------|---------------------|
| **VEDGE-1** | All style children sanitized | `PASS` | Multi-child style nodes recursively clean `@import` and `url(` across all children. |
| **VEDGE-2** | Spaced/mixed CSS url variants blocked | `PASS` | Regex blocks `URL   (` and `@ImPoRt` with whitespace or mixed-case. |
| **VEDGE-3** | Suspicious protocol URLs fail closed | `PASS` | Blocks `vbscript:`, `file:`, and html/script `data:` URLs but allows `data:image/` on `<img>`. |
| **VEDGE-4** | Diagnostics timeline records policy events | `PASS` | Timeline updates successfully when warnings are logged. |
| **VEDGE-5** | VSAFE runner covers new fixtures | `PASS` | `run_vsafe_proof.rb` compiles edgecases page and verifies security properties. |
| **VEDGE-6** | VDSL runner remains green | `PASS` | Core layout rendering and VDSL P1 proofs remain fully green. |
| **VEDGE-7** | Build remains green | `PASS` | Svelte Adapter-Static bundles successfully without compiling errors. |
| **VEDGE-8** | Check has no P5-local errors | `PASS` | Verified that typecheck errors are completely confined to `DebuggerPanel.svelte`. |
| **VSLOT-1** | State-slot schema documented | `PASS` | Interface and attributes detailed in Section 2.1. |
| **VSLOT-2** | No live runtime/VM binding implemented | `PASS` | State slots render as static preflight visual mockups only. |
| **VSLOT-3** | Lab-only/non-canon wording preserved | `PASS` | Confined within experimental Tauri view preview boundaries. |
