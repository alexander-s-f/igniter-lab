Card: LAB-VIEW-DSL-P5
Agent: [Igniter-Lang Implementation Agent]
Role: implementation-agent
Track: lab-experimental-view-tree-safe-policy-edgecases-and-state-slot-preflight-v0
Route: EXPERIMENTAL / LAB-ONLY
Status: done

[D] Decisions
- Hardened the style check in safe_renderer_policy.ts to map and sanitize all style tag children, not only the first child.
- Switched inline and block style substring checks to case/whitespace-tolerant regular expressions (/url\s*\(/i and /@import/i) to intercept advanced CSS leak payloads.
- Added isSuspiciousUrl to filter javascript:, vbscript:, file:, and unsafe data: schemes (except data:image/ on img elements).
- Implemented rel attribute token merging for target="_blank" links (preserves existing tokens like "nofollow" while appending "noopener" and "noreferrer").
- Designed the preflight StateSlot schema (slot_id, contract_output_ref, value_kind, render_policy, fallback) and integrated visual rendering placeholders (dashed border, ⚡ slot badge, detail rows in inspector pane) without wiring live runtime/VM data.

[S] Shipped / Signals
- All 11 proof matrix items successfully validated:
  - VEDGE-1: Multi-child style blocks are recursively sanitized.
  - VEDGE-2: Spaced and case-insensitive url/import declarations are blocked.
  - VEDGE-3: Unsafe protocol schemas are blocked (safe data:image is allowed).
  - VEDGE-4: Diagnostics timeline continues to log policy events.
  - VEDGE-5: VSAFE runner compiles malicious specimens and verifies all edge cases.
  - VEDGE-6: Core VDSL layout proofs remain green.
  - VEDGE-7: Vite build successfully compiles and packages the static bundle.
  - VEDGE-8: Typecheck errors are restricted to pre-existing warnings in DebuggerPanel.svelte.
  - VSLOT-1: State-slot schema is defined and documented.
  - VSLOT-2: No active runtime VM execution is connected.
  - VSLOT-3: Kept experimental lab-only preview status.

[T] Tests / Proofs
- Safety policy: [safe_renderer_policy.ts](../igniter-ide/src/lib/safe_renderer_policy.ts)
- Svelte view renderer: [ViewNodeRenderer.svelte](../igniter-ide/src/lib/components/ViewNodeRenderer.svelte)
- Security runner: [run_vsafe_proof.rb](../igniter-view-engine/run_vsafe_proof.rb)
- Malicious edge cases: [malicious_page.rb](../igniter-view-engine/fixtures/malicious_page.rb)
- Preflight slots fixture: [static_page.rb](../igniter-view-engine/fixtures/static_page.rb)
- Security validation JSON: [vsafe_summary.json](../igniter-view-engine/out/vsafe_summary.json)
- Lab documentation: [lab-experimental-view-tree-safe-policy-edgecases-and-state-slot-preflight-v0.md](../lab-docs/lab-experimental-view-tree-safe-policy-edgecases-and-state-slot-preflight-v0.md)

[R] Recommendations
- Recommendation: **Maintain state-slots as static preflight mockups**.
- Testing slot visualization under a preflight state validates slot lowerings and metadata formats safely. We recommend keeping these slots static until a design for mapping execution evidence receipts or VM states (e.g. via output node telemetry logs) is approved.

[Next] Suggested next slice
- Lower state-slot schemas into compiled Igniter program IR (SemanticIR or CompiledProgram) as a dedicated view Lowering pass, mapping HTML slots to compile-time contract node types.
