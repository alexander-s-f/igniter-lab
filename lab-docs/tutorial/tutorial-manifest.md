# Igniter Lab Tutorial Manifest

This manifest documents the guided learning path lessons, their corresponding command targets, generated output packages, and their projection readiness status for public/mainline platforms.

## Lesson Manifest

| ID | Lesson | Path | Status | Source Package | Primary Command | Generated Outputs | Site Projection Readiness | Authority Boundary |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **L0** | Lab Orientation | [lab-orientation.md](lab-orientation.md) | `active` | None | `cd igniter-vm && cargo test` | None | **Ready**. High-level workspace structure for general contributor onboarding. | Pre-v1 lab orientation; packages and examples may change. |
| **L1** | Compiler First Proof | [compiler-first-proof.md](compiler-first-proof.md) | `active` | `igniter-compiler` | `cargo run -- compile fixtures/conformance/source/add.ig --out out/tutorial_add.igapp` | `out/tutorial_add.igapp/` | **Ready**. Demonstrates the current basic compilation sequence. | Active lab compiler; grammar and APIs may change before v1. |
| **L2** | VM Candidate Proof | [vm-candidate-proof.md](vm-candidate-proof.md) | `active` | `igniter-vm` | `ruby igniter-vm/proofs/vm_candidate_proof.rb` | `igniter-vm/out/vm_candidate_proof/summary.json` | **Ready**. Demonstrates current VM candidate telemetry. | Runtime candidates are in progress and subject to later decisions. |
| **L3** | Forms First Proof | [forms-first-proof.md](forms-first-proof.md) | `active` | `igniter-compiler` | `cargo run -- compile fixtures/forms/positive_forms.ig --out out/forms_test.igapp` | `out/forms_test.igapp/form_table.json`, `form_resolution_trace.json` | **Ready**. Explains current type-directed form dispatch evidence. | Form syntax and dispatch APIs may change before formal adoption. |
| **L4** | Capability Passport First Proof | [capability-passport-first-proof.md](capability-passport-first-proof.md) | `active` | `igniter-vm` | `ruby igniter-vm/proofs/io_vm_loader_capability_passport_integration.rb` | `igniter-vm/out/io_vm_loader_capability_passport_integration/` | **Ready**. Demonstrates current fail-closed safety evidence. | Capability/passport formats are active lab work and may change. |
| **L5** | View / GUI / IDE First Proof | [view-gui-ide-first-proof.md](view-gui-ide-first-proof.md) | `active` | `igniter-view-engine`, `igniter-gui-engine`, `igniter-ide` | `ruby igniter-view-engine/run_proof.rb` | `igniter-view-engine/out/view_tree.json`, `igniter-gui-engine/out/scene_introspection_receipt.json` | **Ready**. Traces current view/GUI artifacts to the IDE shell. | View, GUI, and IDE surfaces are active frontier tools. |

---

## Site Projection Guidelines

`igniter-org` may consume, copy, or curate tutorial lessons defined here to build user-facing documentation websites. However, the following rules apply:

1. **Frontmatter & Localization**: Frontmatter, translation mappings, and website routing metadata are owned and maintained locally by `igniter-org`. Do not add presentation-specific translation headers to these raw lab files.
2. **Frontier Source**: `igniter-lab` remains the upstream reference for what commands are currently runnable and what outputs they produce.
3. **Policy Wording**: Any projection copied to public sites should preserve the pre-v1/as-is tone: useful for learning and feedback, actively developed, and subject to change before formal adoption.

## See Also
- [Tutorial Glossary](tutorial-glossary.md)
- [Site Projection Excerpts](site-projection-excerpts.md)
- [Expected Output Snippets](expected-output-snippets.md)
