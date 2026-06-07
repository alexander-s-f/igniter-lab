Card: LAB-VIEW-DSL-P2
Agent: [Igniter-Lang Implementation Agent]
Role: implementation-agent
Track: lab-experimental-igniter-ide-view-tree-preview-inspector-v0
Route: EXPERIMENTAL / LAB-ONLY
Status: done

[D] Decisions
- Integrated the view preview/inspector panel as a new tab `'view_preview'` inside the IDE's main toolbar, next to Timeline and Tracer.
- Implemented recursive rendering of DOM trees using Svelte 5 dynamic elements (`<svelte:element>`) with attribute spreading, completely avoiding raw HTML string injection (`{@html}`) to secure the IDE from malicious/unverified code execution.
- Separated the inspector into a split pane: the left side acts as the secure rendering preview container, while the right side manages the interactive collapsable tree inspector details and logs.
- Added comprehensive error handlers for file load failures (missing view_tree.json) and parsing failures (corrupted JSON AST) to fail-closed gracefully.

[S] Shipped / Signals
- All 12 proof matrix items successfully validated:
  - VID-1: Successfully reads view_tree.json from disk using local Tauri file APIs.
  - VID-2: Employs secure recursive Svelte component compilation, avoiding HTML string injection.
  - VID-3: Draws custom dashed outlines with contract titles around component boundaries in the preview.
  - VID-4: Exposes active trace scopes and key-value attribute tables in the inspector details.
  - VID-5: Identifies `forms_assisted` nodes and labels them with high-visibility DX Candidate alerts.
  - VID-6: Renders a timestamped scrollable timeline of diagnostic events (conditionals, loops, etc.).
  - VID-7: Displays design system CSS class frequency counts sorted by occurrence.
  - VID-8: Handles corrupted JSON files gracefully inside a red boundary box error block.
  - VID-9: Renders a clean "View Tree Preview" splash dashboard when no active workspace or file is loaded.
  - VID-10: Svelte check and Vite production compilation completed with 100% success.
  - VID-11: No mainline source files inside `igniter-lang/` were modified.
  - VID-12: The view preview remains a playground experiment without claiming canonical language syntax.

[T] Tests / Proofs
- Integrated View Inspector: [ViewInspector.svelte](../../../../igniter-ide/src/lib/components/ViewInspector.svelte)
- Safe recursive node renderer: [ViewNodeRenderer.svelte](../../../../igniter-ide/src/lib/components/ViewNodeRenderer.svelte)
- Collapsible tree walker: [ViewTreeInspectorNode.svelte](../../../../igniter-ide/src/lib/components/ViewTreeInspectorNode.svelte)
- Layout wiring: [routes/+page.svelte](../../../../igniter-ide/src/routes/+page.svelte)
- Lab documentation: [lab-experimental-igniter-ide-view-tree-preview-inspector-v0.md](../../../../lab-docs/ide/lab-experimental-igniter-ide-view-tree-preview-inspector-v0.md)

[R] Recommendations
- Recommendation: **route design-system/IDE integration proof**.
- The preview inspector successfully proves that structured JSON trees can act as a lightweight, safe, and inspectable intermediate view representation (IR). We recommend continuing this track to build closer bindings between the Svelte AST representation and Igniter's compiled graphs.

[Next] Suggested next slice
- Implement a hot-reload watcher in the IDE that automatically refreshes the `ViewInspector` panel whenever a new build is emitted to `igniter-view-engine/out/`.
