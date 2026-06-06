# Lab Experimental Igniter IDE View Tree Preview & Inspector (v0)

Status: `experimental · lab-only`
Track: `lab-experimental-igniter-ide-view-tree-preview-inspector-v0`
Base: `lab-experimental-igniter-html-view-dsl-arbre-like-boundary-v0.md`

---

## 1. Context & Goals

Following the implementation of the experimental Arbre-like view engine parser and builder under `igniter-view-engine`, this card integrates the resulting output artifacts into the Svelte-based SvelteKit/Tauri `igniter-ide` shell.

Our objective is to provide a **safe visual preview and inspector panel** in the IDE that loads the compiled view tree, traces component nesting, exposes diagnostics logs, and evaluates brand design system token usage class counts. Crucially, all operations are **sandboxed and statically rendered**, with zero raw HTML execution or runtime dispatch.

---

## 2. Component Architecture

We created three new Svelte 5 components under `igniter-lab/igniter-ide/src/lib/components/`:

1.  **`ViewInspector.svelte`**: The main panel layout, coordinating file input, loading states, the preview canvas, diagnostics tabs, and token reports.
2.  **`ViewNodeRenderer.svelte`**: A recursive node compiler that safely translates JSON tree nodes to Svelte elements (`<svelte:element>`) with spread attributes, eliminating arbitrary HTML string injection (`{@html}`). It visually distinguishes components and flags forms-assisted syntactic sugar.
3.  **`ViewTreeInspectorNode.svelte`**: A collapsible tree explorer that walks the AST hierarchy in the sidebar, allowing operators to traverse, expand, and select individual nodes.

### Tab Integration

The inspector is registered as a new tab in the IDE's main toolbar:
*   Added `'view_preview'` to `ViewTabId` and `VIEW_TABS` in `src/routes/+page.svelte`.
*   Wired the panel to display inside the main area when the tab is selected.

---

## 3. Sandboxing & Safe Rendering

To comply with **VID-2**, the structured preview renders nodes directly without any raw HTML injection.
*   **Text content** is interpolated directly via Svelte's curly braces (`{node.children[0]}`), which automatically handles browser HTML escaping.
*   **Tags and attributes** are checked and compiled dynamically: Svelte’s `<svelte:element this={node.tag} {...node.attributes}>` applies properties (like class name, styles) securely.
*   **Arbitrary Javascript** from the artifact files is unreachable since the preview never parses or executes `<script>` tags or raw HTML strings.

---

## 4. Empty & Error States

To satisfy **VID-8** and **VID-9**, the inspector implements robust error boundaries:
*   **Missing file state**: If the `view_tree.json` path cannot be read (e.g. before compilation or wrong path), it catches the Tauri error and displays a clear "Missing Artifact" warning showing the exact path searched.
*   **Malformed JSON state**: If the JSON tree is corrupted or malformed, it catches the parsing exception and displays a "Malformed JSON" error trace.
*   **Sub-artifact resilience**: If secondary files (`diagnostics.json` or `token_usage_report.json`) are missing, it logs warnings but allows the main structured tree preview to load, preventing cascading failures.

---

## 5. Proof Matrix Verification

| Rule ID | Requirement | Result | Verification Notes |
|---------|-------------|--------|---------------------|
| **VID-1** | IDE loads `view_tree.json` | `PASS` | Reads view_tree.json via Tauri API file system call and parses it. |
| **VID-2** | Structured preview renders without raw HTML injection by default | `PASS` | Uses recursive Svelte component tree rendering; no `{@html}` blocks. |
| **VID-3** | Component nodes are visually distinguishable | `PASS` | Renders a custom dashed border with the contract component name. |
| **VID-4** | Inspector exposes attributes and trace metadata | `PASS` | Exposes key-value attribute tables and active trace contexts. |
| **VID-5** | Forms-assisted nodes are labeled DX candidate only | `PASS` | Detects `forms_assisted: true` and displays a high-visibility warning label. |
| **VID-6** | Diagnostics timeline renders component/loop/conditional events | `PASS` | Renders timestamped events for conditionals, loops, and completions. |
| **VID-7** | Token usage panel renders design-system class counts | `PASS` | Renders a table of CSS classes and counts, sorted by frequency. |
| **VID-8** | Malformed artifact fails closed with readable error | `PASS` | Catches parsing exceptions and renders a readable error boundary box. |
| **VID-9** | Missing artifact shows empty state | `PASS` | Shows an empty layout state if workspace is closed or path is not found. |
| **VID-10**| Build/check command passes or known blockers are recorded | `PASS` | Vite production build compiles successfully. |
| **VID-11**| No `igniter-lang/**` files are edited | `PASS` | Restricts writes to `igniter-ide/` and `lab-docs/`. |
| **VID-12**| No canon/stable/public/runtime claims are introduced | `PASS` | Preserved as a lab-only experimental preview inspector tool. |
