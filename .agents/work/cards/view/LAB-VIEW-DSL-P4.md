Card: LAB-VIEW-DSL-P4
Agent: [Igniter-Lang Implementation Agent]
Role: implementation-agent
Track: lab-experimental-view-tree-renderer-contract-and-typecheck-cleanup-v0
Route: EXPERIMENTAL / LAB-ONLY
Status: done

[D] Decisions
- Extracted all safety whitelists and sanitization procedures into a single, shared module: [safe_renderer_policy.ts](../../../../igniter-ide/src/lib/safe_renderer_policy.ts).
- Hardened style tag content processing to recursively parse either raw string children or structured text node children, replacing CSS import (`@import`) and telemetry/leak directives (`url(`) with blocked comment placeholders.
- Hardened inline style attributes to block `url(` patterns.
- Forced `rel="noopener noreferrer"` for any anchor links utilizing `target="_blank"` to eliminate reverse tabnabbing.
- Isolated document-level elements (`html`, `head`, `body`, `meta`, `link`) to the preview root only; child elements attempting to render these tags are blocked.
- Isolated the security test suite into a dedicated proof runner: [run_vsafe_proof.rb](../../../../igniter-view-engine/run_vsafe_proof.rb) compiling malicious spec fixtures and validating compliance, outputting [vsafe_summary.json](../../../../igniter-view-engine/out/vsafe_summary.json).
- Hardened hot-reload behavior in the inspector panel to show clear syntax error boundaries if JSON payload files are corrupted, failing closed safely.
- Resolved TypeScript compiler type mismatches in [ViewInspector.svelte](../../../../igniter-ide/src/lib/components/ViewInspector.svelte) by introducing type guards.

[S] Shipped / Signals
- All 12 proof matrix points verified:
  - VCON-1: TS type mismatch errors resolved in `ViewInspector.svelte`.
  - VCON-2: Shared safety policy module exists and is imported.
  - VCON-3: Dedicated VSAFE proof runner and `vsafe_summary.json` exist.
  - VCON-4: Style sanitization (import/url block, tabnabbing rel) enforced.
  - VCON-5: Nested document-level root tags blocked.
  - VCON-6: Unsafe script/iframe/on* blocked and logged.
  - VCON-7: Diagnostics timeline logs safety warning events.
  - VCON-8: Hot-reload fail-closed handles JSON errors gracefully.
  - VCON-9: Production Vite build bundles successfully.
  - VCON-10: Pre-existing errors documented (limited to DebuggerPanel.svelte).
  - VCON-11: Restrained to playground folders; `igniter-lang/` untouched.
  - VCON-12: Preserved lab-only preview status.

[T] Tests / Proofs
- Safety policy: [safe_renderer_policy.ts](../../../../igniter-ide/src/lib/safe_renderer_policy.ts)
- Svelte preview: [ViewNodeRenderer.svelte](../../../../igniter-ide/src/lib/components/ViewNodeRenderer.svelte)
- Security runner: [run_vsafe_proof.rb](../../../../igniter-view-engine/run_vsafe_proof.rb)
- Malicious specimen: [malicious_page.rb](../../../../igniter-view-engine/fixtures/malicious_page.rb)
- Core layouts proof: [run_proof.rb](../../../../igniter-view-engine/run_proof.rb)
- Safety receipt: [vsafe_summary.json](../../../../igniter-view-engine/out/vsafe_summary.json)
- Lab documentation: [lab-experimental-view-tree-renderer-contract-and-typecheck-cleanup-v0.md](../../../../lab-docs/view/lab-experimental-view-tree-renderer-contract-and-typecheck-cleanup-v0.md)

[R] Recommendations
- Recommendation: **keep view-tree renderer lab-only**.
- The extracted safe renderer policy provides a robust and reusable baseline for sandboxing view trees. Keeping this implementation lab-only maintains agility and prevents bloating the core compiler/grammar library.

[Next] Suggested next slice
- Map dynamic values from runtime VM executions directly into component slots on the preview tree, allowing live visual representation of state changes during debugging.
