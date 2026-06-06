Card: LAB-VIEW-DSL-P3
Agent: [Igniter-Lang Implementation Agent]
Role: implementation-agent
Track: lab-experimental-view-tree-safe-renderer-and-hot-reload-v0
Route: EXPERIMENTAL / LAB-ONLY
Status: done

[D] Decisions
- Hardened the `ViewNodeRenderer.svelte` preview by establishing a strict Safe Renderer Policy whitelisting allowed HTML elements and safe tag attributes.
- Implemented a parser interceptor that blocks any event attributes (like `onclick`) or non-whitelisted tags (`script`, `iframe`, etc.), converting them to static warning cards.
- Stripped and blocked any URLs with `javascript:` schemes to prevent XSS redirects.
- Added a background interval polling watcher inside `ViewInspector.svelte` that checks for modifications to `view_tree.json` every 1.5 seconds, refreshing the preview canvas dynamically without interrupting selection.
- Fixed the Svelte 5 local state warning in `ViewTreeInspectorNode.svelte` using `$derived` reactive state.

[S] Shipped / Signals
- All 14 matrix points successfully proved and validated:
  - VSAFE-1: Whitelisted HTML tags (div, span, tables) render as normal DOM elements.
  - VSAFE-2: Disallowed `<script>` elements are blocked and replaced with warning cards.
  - VSAFE-3: Disallowed `<iframe>` and other embed tags are intercepted and blocked.
  - VSAFE-4: Event handlers starting with `on*` are stripped from attributes.
  - VSAFE-5: URLs with `javascript:` scheme are blocked and stripped.
  - VSAFE-6: Intercepted tags and attributes appear as warnings in the details panel and diagnostics timeline.
  - VSAFE-7: Forms-assisted component nodes continue to show the DX Candidate warning label.
  - VSAFE-8: Corrupted JSON tree artifacts fail closed and output syntax errors.
  - VSAFE-9: Missing tree files show an empty "Missing Artifact" warning state.
  - VSAFE-10: Polling watcher successfully hot-reloads the preview canvas upon new compilations.
  - VSAFE-11: Vite production Adapter-Static compilation finishes successfully with zero build errors.
  - VSAFE-12: Svelte check results were compiled, resolving local warnings and recording pre-existing warnings in the design document.
  - VSAFE-13: No mainline files in `igniter-lang/` were modified.
  - VSAFE-14: The view renderer is maintained as a playground experiment.

[T] Tests / Proofs
- Hardened safe renderer: [ViewNodeRenderer.svelte](../igniter-ide/src/lib/components/ViewNodeRenderer.svelte)
- Hot reload and diagnostics warning scan: [ViewInspector.svelte](../igniter-ide/src/lib/components/ViewInspector.svelte)
- Svelte 5 warning resolution: [ViewTreeInspectorNode.svelte](../igniter-ide/src/lib/components/ViewTreeInspectorNode.svelte)
- Malicious specimen fixture: [malicious_page.rb](../igniter-view-engine/fixtures/malicious_page.rb)
- Malicious artifacts output: [malicious_view_tree.json](../igniter-view-engine/out/malicious_view_tree.json)
- Lab documentation: [lab-experimental-view-tree-safe-renderer-and-hot-reload-v0.md](../lab-docs/lab-experimental-view-tree-safe-renderer-and-hot-reload-v0.md)

[R] Recommendations
- Recommendation: **continue as view-engine frontier**.
- The safe renderer and hot-reload mechanism successfully harden the visual preview interface. We recommend utilizing this playground to test contract-based view rendering alongside live VM execution trace outputs, providing a zero-risk design arena for developer tools.

[Next] Suggested next slice
- Map dynamic values from the VM execution trace (`OP_CALL` outcomes) onto component placeholders in the preview tree, enabling live visual state verification.
