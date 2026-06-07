Card: LAB-VIEW-DSL-P1
Agent: [Igniter-Lang Research Agent]
Role: research-agent
Track: lab-experimental-igniter-html-view-dsl-arbre-like-boundary-v0
Route: EXPERIMENTAL / LAB-ONLY
Status: done

[D] Decisions
- Designed 3 syntax candidates for HTML views: Block/Tree DSL, Contract-Output (Component) DSL, and Forms-Assisted Component/Tag Invocation DSL.
- Decided that HTML primitive tags should be evaluated via builder functions (`HtmlNode` constructors) rather than full contract invocations to prevent graph explosion.
- Decided that custom components should be modeled as contract invocations that lower to an `HtmlNode` tree.
- Decided that `form:` prefix syntax should be treated as an optional DX sugar / invocation alias that desugars to `ContractInvocation` during compilation (static lowering).
- Prototyped a Ruby-based view engine parser/builder block evaluator supporting nested tags, attribute formatting, dynamic conditions, collection iteration, safe HTML-escaping, raw bypass, and JSON AST serialization.

[S] Shipped / Signals
- All 12 items in the proof matrix successfully passed:
  - VDSL-1: Static view builds a valid view tree.
  - VDSL-2: Data-driven list renders deterministic HTML.
  - VDSL-3: Component invocation is represented as structured nodes (not string concatenation).
  - VDSL-4: Attributes, classes, and styles are serializable and inspectable in JSON.
  - VDSL-5: Text content is HTML-escaped by default to prevent XSS.
  - VDSL-6: Unsafe/raw HTML requires an explicit `raw` marker wrapper.
  - VDSL-7: Conditional rendering is traced in AST trace metadata and diagnostics.
  - VDSL-8: Collection loop items carry loop index trace context metadata.
  - VDSL-9: Forms-assisted invocation is logged and marked as DX candidate only.
  - VDSL-10: Reproducible HTML and view tree output files are written to the workspace.
  - VDSL-11: No mainline files (such as `igniter-lang/`) were edited.
  - VDSL-12: No canonical language claims are introduced; this remains lab-only.

[T] Tests / Proofs
- Prototype code location: [igniter-view-engine/](../../../../igniter-view-engine)
- Core libraries: [igniter_view_engine.rb](../../../../igniter-view-engine/lib/igniter_view_engine.rb), [parser_builder.rb](../../../../igniter-view-engine/lib/parser_builder.rb)
- Fixture files: [static_page.rb](../../../../igniter-view-engine/fixtures/static_page.rb), [data_driven_list.rb](../../../../igniter-view-engine/fixtures/data_driven_list.rb), [componentized_form.rb](../../../../igniter-view-engine/fixtures/componentized_form.rb)
- Proof execution script: [run_proof.rb](../../../../igniter-view-engine/run_proof.rb)
- Output Artifacts:
  - Rendered HTML specimen: [index.html](../../../../igniter-view-engine/out/index.html)
  - Detailed view tree AST: [view_tree.json](../../../../igniter-view-engine/out/view_tree.json)
  - Execution diagnostics trace: [diagnostics.json](../../../../igniter-view-engine/out/diagnostics.json)
  - CSS brand token usage analysis: [token_usage_report.json](../../../../igniter-view-engine/out/token_usage_report.json)
- Lab design/proof doc: [lab-experimental-igniter-html-view-dsl-arbre-like-boundary-v0.md](../../../../lab-docs/view/lab-experimental-igniter-html-view-dsl-arbre-like-boundary-v0.md)

[R] Risks / Recommendations
- Recommendation: **route design-system/IDE integration proof (P2)**.
- The generated `view_tree.json` structure maps extremely well to Svelte component boundaries. Integrating this view-tree artifact directly into the Svelte-based `igniter-ide` workspace will allow live-updating visual preview render panels for contract compositions and receipt outputs.
- The `form:` syntax should remain restricted as a compile-time desugaring alias and not be promoted to a runtime view dispatcher.

[Next] Suggested next slice
- Route Svelte-side integration inside `igniter-lab/igniter-ide/` to consume the generated `view_tree.json` and build a live contract preview inspector tab.
