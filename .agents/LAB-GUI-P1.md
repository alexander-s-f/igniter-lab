Card: LAB-GUI-P1
Agent: [Igniter-Lang Research Agent]
Role: research-agent
Track: lab-igniter-lang-to-gui-research-boundary-v0
Route: EXPERIMENTAL / LAB-ONLY / RESEARCH
Status: done

[D] Decisions
- Structured the Igniter Lang to GUI mapping boundary into a formal artifact pipeline.
- Divided GUI components into eight distinct targets: static view tree, component tree, blueprint/canvas graph, contract input forms, output dashboards, debugger/trace panels, live state-slot previews, and the app shell.
- Drafted type-safe mapping rules from contract input ports (String, Integer, Boolean, Collection, Temporal) to HTML form controls and validation boundaries.
- Defined specific output visualization adapters for temporal data, Bi-History models, and uncertain values (carrying confidence and uncertainty bounds).
- Clarified the boundaries between auto-generated UI surfaces (like input forms and dashboards compiled directly from contract JSON schemas) and manually-styled, custom layouts designed using the View DSL.
- Established a Capability Passport Shield design rule where contracts carrying `escape` declarations (side effects) must trigger visual consent boundaries inside the IDE before execution.

[S] Shipped / Signals
- Shipped research boundary document: [lab-igniter-lang-to-gui-research-boundary-v0.md](../lab-docs/lab-igniter-lang-to-gui-research-boundary-v0.md) detailing the pipeline matrix and vocabulary.
- Modeled the compiler-to-view pipeline flow diagram using Mermaid graph nodes showing intermediate artifacts.
- Validated all 10 suggested readiness checklist parameters (GUI-R1 through GUI-R10) outlining playground capabilities and risks.

[T] Tests / Proofs
- Inspected existing AST parser engine: [run_proof.rb](../igniter-view-engine/run_proof.rb) and [run_vsafe_proof.rb](../igniter-view-engine/run_vsafe_proof.rb).
- Audited shared security whitelists and sanitization logic: [safe_renderer_policy.ts](../igniter-ide/src/lib/safe_renderer_policy.ts).
- Checked Svelte component implementations: [ViewInspector.svelte](../igniter-ide/src/lib/components/ViewInspector.svelte) and [ViewNodeRenderer.svelte](../igniter-ide/src/lib/components/ViewNodeRenderer.svelte).
- Examined compiled compiler JSON representations: [manifest.json](../igniter-compiler/out/vendor_lead_pipeline.igapp/manifest.json) and [loop_tester.json](../igniter-compiler/out/loops_and_recursion.igapp/contracts/loop_tester.json).

[R] Risks / Recommendations
- Risk: Framework drift where the experimental View DSL and Svelte sandbox rendering engine are treated as a stable frontend framework. Recommendation: Limit the view engine and IDE canvas to developer-facing diagnostics and testing dashboards only.
- Risk: Styling-based telemetry leaks (unauthorized server calls via dynamic CSS imports or inline background urls). Recommendation: Maintain strict regex filtering of `@import` and `url()` directives across all text children and attributes in `safe_renderer_policy.ts`.
- Recommendation: Keep State-Slots static until a formal design mapping contract execution receipts or VM trace outputs is approved.

[Next] Suggested next slice
- Card: LAB-GUI-P2
- Goal: Implement dynamic contract-to-form generation in the IDE sidebar. Read compiled contract signatures (`contract_id.json`), render corresponding input controls (text, number, checkbox), validate user input, and compile a validated JSON input packet.
