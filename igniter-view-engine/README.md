# Igniter View Engine Lab Prototype

`igniter-view-engine` is a lab-only prototype for Igniter view artifacts,
`.igv` view sketches, safe rendering, slot injection, collection rendering,
contract-schema linkage, and diagnostic reports.

It explores whether Igniter can describe GUI/view structure as inspectable
artifacts without depending on React, Svelte, Vue, HTMX, or Tailmix at runtime.
The package is frontier evidence only; it is not a released framework, stable
grammar, public API, or Igniter Lang authority.

## Current Map

| Path | Purpose |
| --- | --- |
| [`lib/view_artifact.rb`](lib/view_artifact.rb) | Lab ViewArtifact model with UIState, read-only SlotValues, elements, rules, and collection metadata. |
| [`lib/ssr_renderer.rb`](lib/ssr_renderer.rb) | Ruby SSR renderer for ViewArtifact fixtures. |
| [`lib/igv_compiler.rb`](lib/igv_compiler.rb) | Experimental `.igv` DSL compiler into ViewArtifact JSON. |
| [`lib/contract_schema.rb`](lib/contract_schema.rb) | Contract output schema model used by view-slot linkage proofs. |
| [`lib/compiled_contract_extractor.rb`](lib/compiled_contract_extractor.rb) | Extracts schema facts from compiled contract JSON fixtures without executing contracts. |
| [`lib/contract_schema_supplement.rb`](lib/contract_schema_supplement.rb) | Lab supplement overlay for missing collection item-field metadata. |
| [`lib/slot_type_linker.rb`](lib/slot_type_linker.rb) | Validates slot-to-contract output references and collection item params. |
| [`lib/linkage_report.rb`](lib/linkage_report.rb) | Unified diagnostic report for extractor, overlay, and linker diagnostics. |
| [`igniter_view_runtime.js`](igniter_view_runtime.js) | Vanilla JS micro-runtime proof surface for safe slot updates and interaction rules. |
| [`docs/igv-grammar-sketch-v0.ebnf`](docs/igv-grammar-sketch-v0.ebnf) | Grammar sketch only; no canonical syntax claim. |
| [`fixtures/`](fixtures/) | Lab fixtures for view, contract-schema, malicious-input, trace, and supplement proofs. |
| [`run_*`](.) | Proof runners that regenerate ignored local outputs under `out/`. |

## Boundary

- Lab-only research and proof evidence.
- No stable grammar, stable schema, public API, package, or release authority.
- No production framework, runtime support, Reference Runtime support, public
  demo, performance, compatibility, certification, or portability claims.
- No contract execution inside the view runtime.
- No Igniter Lang canon unless a future Main Line route explicitly accepts a
  narrowed design.

## Local Checks

From this directory:

```bash
ruby run_proof.rb
ruby run_ir_proof.rb
ruby run_vsafe_proof.rb
ruby run_ivf_proof_p9.rb
node run_ivf_dom_proof.js
node run_ivf_dom_proof_p5.js
```

The proof runners write local artifacts into `out/`; that directory is ignored.
