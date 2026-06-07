# Safe Artifact Renderer & Hot-Reload Watcher (v0)

Status: `experimental · lab-only`
Track: `lab-experimental-view-tree-safe-renderer-and-hot-reload-v0`
Base: `lab-experimental-igniter-ide-view-tree-preview-inspector-v0.md`

---

## 1. Safety Policy Contract

To protect the IDE from malicious or unverified code injection through compiled view tree artifacts, we implemented a strict **Safe Renderer Policy** inside `ViewNodeRenderer.svelte`.

### 1.1 Whitelists
We enforce tag and attribute whitelists at render-time:
*   **Allowed Tags:** `div`, `span`, `p`, `h1`..`h6`, `a`, `button`, `input`, `textarea`, `label`, `table`, `thead`, `tbody`, `tr`, `th`, `td`, `img`, `style`, `meta`, `link`, `head`, `body`, `html`, `header`, `footer`, `section`, `nav`, `ul`, `ol`, `li`, `br`, `hr`, `text`, `component`.
*   **Allowed Attributes:** `class`, `id`, `style`, `href`, `placeholder`, `value`, `type`, `disabled`, `readonly`, `checked`, `src`, `alt`, `lang`, `charset`, `rel`, `for`, `name`, `rows`, `cols`, `target`.

### 1.2 Blacklists and Stripping Rules
*   **Disallowed Tags (`script`, `iframe`, `object`, `embed`):** Any tag not in the whitelist is blocked entirely. The safe element compiler intercepts them and renders a static warning banner: `⚠️ Blocked tag: <tag_name> - Safe policy violation`.
*   **Event Handlers (`on*`):** Any attribute starting with `on` (e.g., `onclick`, `onload`, `onmouseover`) is stripped from the attribute map and added to warning logs.
*   **JavaScript Scheme URLs (`javascript:`):** Any attribute containing a value starting with `javascript:` (e.g. `href="javascript:..."`) is blocked, stripped, and logged.
*   **Raw HTML nodes:** Strings are rendered as Svelte interpolated text nodes, which automatically escape all tags.

---

## 2. Hot-Reload Watcher

To enable rapid developer iteration, `ViewInspector.svelte` sets up a polling file watcher upon mounting:
*   An interval timer runs every **1.5 seconds** in the background.
*   It fetches the current content of `view_tree.json` via Tauri's read API.
*   It compares the raw file content against the last loaded version. If it detects a change, it automatically re-parses and updates the UI preview silently without resetting selected nodes.
*   On every reload, the active tree is scanned for security policy violations, and any stripped tags or attributes are appended directly to the **Diagnostics Timeline**.

---

## 3. Pre-existing Svelte Check Blockers

We ran `npm run check` and identified pre-existing warnings and compilation errors in the codebase:
1.  **TypeScript Destructuring Warning in `DebuggerPanel.svelte`**:
    *   *Error location:* `DebuggerPanel.svelte:532`
    *   *Error details:* `cap` in `Object.entries(...) as [cap_id, cap]` is inferred as type `unknown`. Trying to read `cap.sandbox_dir`, `cap.read_allowed`, or `cap.write_allowed` raises TypeScript errors because the compiler cannot guarantee the structure of the destructured value.
2.  **Svelte 5 Inspector Warning in `ViewTreeInspectorNode.svelte` (Fixed)**:
    *   *Warning details:* `This reference only captures the initial value of node.`
    *   *Resolution:* Fixed by converting the static variable declaration into a reactive Svelte 5 `$derived` state variable:
        ```typescript
        let hasChildren = $derived(node.children && node.children.some(c => typeof c === 'object'))
        ```
    *   *Status:* **Resolved**. The warning no longer appears.

---

## 4. Proof Matrix Verification

| Rule ID | Requirement | Result | Verification Notes |
|---------|-------------|--------|---------------------|
| **VSAFE-1** | Allowed tags render | `PASS` | Standard whitelisted HTML tags (`div`, `h2`, `span`) render correctly. |
| **VSAFE-2** | Disallowed `script` is blocked | `PASS` | `<script>` is blocked, rendering a static alert message. |
| **VSAFE-3** | Disallowed `iframe/object/embed` are blocked | `PASS` | `<iframe>` is blocked, rendering a static alert message. |
| **VSAFE-4** | `on*` event attributes are stripped or blocked | `PASS` | `onclick` attributes are stripped from button tags; a warning indicator appears. |
| **VSAFE-5** | `javascript:` URLs are blocked | `PASS` | `javascript:` scheme URLs are stripped and removed from `href` attributes. |
| **VSAFE-6** | Blocked nodes appear in diagnostics | `PASS` | Blocks and warnings are scanned and injected directly into the diagnostics timeline. |
| **VSAFE-7** | Forms-assisted nodes still show DX Candidate label | `PASS` | Forms-assisted component rendering is successfully identified and labeled. |
| **VSAFE-8** | Malformed JSON still fails closed | `PASS` | Failed parser logs show detailed syntax errors inside the boundary block. |
| **VSAFE-9** | Missing artifact still shows empty state | `PASS` | Renders a "Missing Artifact" explanation showing searched paths. |
| **VSAFE-10**| Hot reload refreshes preview after artifact update | `PASS` | The background interval detects changes to `view_tree.json` and updates immediately. |
| **VSAFE-11**| `npm run build` passes | `PASS` | Vite production adapter static build successfully completes. |
| **VSAFE-12**| `npm run check` result is recorded | `PASS` | Pre-existing type issues in `DebuggerPanel` are documented in Section 3. |
| **VSAFE-13**| No `igniter-lang/**` files are edited | `PASS` | Restricts writes to playground directories. |
| **VSAFE-14**| No canon/stable/public/runtime claims are introduced | `PASS` | Statically validated under a lab-only preview panel. |
