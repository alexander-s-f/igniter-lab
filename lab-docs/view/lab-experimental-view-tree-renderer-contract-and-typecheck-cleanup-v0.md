# Hardening View-Tree Renderer Contract & Typecheck Cleanup (v0)

Status: `experimental · lab-only`
Track: `lab-experimental-view-tree-renderer-contract-and-typecheck-cleanup-v0`
Base: `lab-experimental-view-tree-safe-renderer-and-hot-reload-v0.md`

---

## 1. Safety Policy Contract Hardening

To establish a clearer safety boundary and eliminate copy-paste code in the visual preview, we extracted all whitelists and sanitization logic from component-level code into a single, shared safety policy module: [safe_renderer_policy.ts](../../ide/igniter-ide/src/lib/safe_renderer_policy.ts).

### 1.1 Policy Enhancements (VCON-4, VCON-5, VCON-6)
1.  **Shared Whitelists:** Consolidates `ALLOWED_TAGS` and `ALLOWED_ATTRIBUTES` in one module used by both the root inspector and recursive child node renderers.
2.  **Style Tag Sanitization:** Hardened `<style>` block scanning to handle both raw string children and structured `text` node children (often produced by the HTML AST builder). It replaces `@import` with `/* blocked @import */` and `url(` with `/* blocked url( */` to prevent unauthorized CSS imports or stylesheet-based leaks.
3.  **Inline Style URL Blocking:** Intercepts `style` attributes containing `url(...)` (e.g. background-image styling with remote URLs) and strips them to prevent telemetry/leak vectors.
4.  **Reverse Tabnabbing Prevention:** Links defined with `target="_blank"` are automatically forced to have `rel="noopener noreferrer"`.
5.  **Nested Document-Level Tag Isolation:** Document-level tags (`html`, `head`, `body`, `meta`, `link`) are permitted only at the preview canvas root (`isRoot = true`). If they occur nested inside child elements, they are blocked, stripped, and reported as security warnings.

---

## 2. Dedicated Security Runner: VSAFE Proof

We separated the security validation code from the core layout rendering engine. The core engine runner [run_proof.rb](../../frame-ui/igniter-view-engine/run_proof.rb) now focuses exclusively on VDSL P1 rendering and structural correctness.

All malicious specimens and policy checks have been migrated to a dedicated runner: [run_vsafe_proof.rb](../../frame-ui/igniter-view-engine/run_vsafe_proof.rb).
*   **Input Fixture:** Compiles the updated [malicious_page.rb](../../frame-ui/igniter-view-engine/fixtures/malicious_page.rb) showcasing CSS leaks, stylesheet imports, reverse tabnabbing, inline styles, nested script elements, and nested document tags.
*   **Simulation Assertions:** Re-implements the Svelte TypeScript safety policy in Ruby to verify that the generated AST conforms to all whitelists, blocklists, and mutation criteria.
*   **Result Packet:** Outputs a dedicated safety validation receipt: `igniter-view-engine/out/vsafe_summary.json` mapping all VCON rules to their status.

---

## 3. TypeScript Typecheck and Hot-Reload Fixes

### 3.1 Svelte Check Resolution (VCON-1, VCON-10)
*   **Type Mismatch:** Fixed TypeScript type check errors in `ViewInspector.svelte` where `viewTree` (which can be `ViewNode | null`) was passed directly to tree-walking functions expecting `ViewNode`. We added explicit null checks (`if (viewTree)`) before invoking AST analysis.
*   **Pre-existing Errors:** Ran type check validation. The only remaining type errors are located in `DebuggerPanel.svelte` (`cap` is of type `unknown`), which are pre-existing and completely isolated from our view-tree implementation files.

### 3.2 Hot-Reload Fail-Closed (VCON-8)
*   If the developer modifies code and generates a corrupted or incomplete `view_tree.json` (such as mid-write syntax errors), the hot-reload JSON parser catches the exception and sets the component's `errorMsg` state.
*   The preview panel immediately renders a visible, clear boundary alert containing the parser exception, rather than crashing the Tauri panel or silently preserving a stale, insecure view tree.

---

## 4. Proof Matrix Verification

| Rule ID | Requirement | Result | Verification Notes |
|---------|-------------|--------|---------------------|
| **VCON-1** | TypeScript P3 errors fixed | `PASS` | All type mismatch errors resolved in `ViewInspector.svelte`. |
| **VCON-2** | Shared safety policy exists | `PASS` | [safe_renderer_policy.ts](../../ide/igniter-ide/src/lib/safe_renderer_policy.ts) is imported and utilized reactively. |
| **VCON-3** | VSAFE proof runner exists | `PASS` | [run_vsafe_proof.rb](../../frame-ui/igniter-view-engine/run_vsafe_proof.rb) executes and writes `out/vsafe_summary.json`. |
| **VCON-4** | Style sanitization enforced | `PASS` | `@import` and `url()` inside style tags/attributes are stripped; tabnabbing rel is added. |
| **VCON-5** | Nested root tag isolation | `PASS` | Nested `head` is blocked; root-level tags render only at the canvas entrypoint. |
| **VCON-6** | Unsafe script/iframe/on* blocked | `PASS` | Malicious scripts/events are blocked/stripped and render visual warning banners. |
| **VCON-7** | Diagnostics timeline warning logging | `PASS` | Stripped parameters and policy events are logged to the Timeline panel. |
| **VCON-8** | Hot-reload fail-closed handles JSON error | `PASS` | Corruption is caught in the background watcher, rendering error boundaries. |
| **VCON-9** | Production Vite build compiles | `PASS` | Production build bundles successfully without typecheck or module failures. |
| **VCON-10**| Pre-existing warnings cataloged | `PASS` | Documented pre-existing errors in `DebuggerPanel.svelte`. |
| **VCON-11**| No mainline files edited | `PASS` | All updates confined to playgrounds; `igniter-lang/` untouched. |
| **VCON-12**| Lab-only preview status | `PASS` | Handled entirely within the experimental Tauri playground devtool. |
