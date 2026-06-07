# Igniter Lab Tutorial Manifest

This manifest documents the guided learning path lessons, their corresponding command targets, generated output packages, and their projection readiness status for public/mainline platforms.

## Lesson Manifest

| ID | Lesson | Path | Status | Source Package | Primary Command | Generated Outputs | Site Projection Readiness | Authority Boundary |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **L0** | Lab Orientation | [lab-orientation.md](lab-orientation.md) | `active` | None | `cd igniter-vm && cargo test` | None | **Ready**. High-level workspace structure. Safe for general contributor onboarding documentation. | Bounded strictly to local checkouts; no public package publication authority. |
| **L1** | Compiler First Proof | [compiler-first-proof.md](compiler-first-proof.md) | `active` | `igniter-compiler` | `cargo run -- compile fixtures/conformance/source/add.ig --out out/tutorial_add.igapp` | `out/tutorial_add.igapp/` | **Ready**. Demonstrates basic compilation sequence. Safe for mainline tooling docs projection. | Lab-only compiler; no stable grammar or public API guarantee. |
| **L2** | VM Candidate Proof | [vm-candidate-proof.md](vm-candidate-proof.md) | `active` | `igniter-vm` | `ruby igniter-vm/proofs/vm_candidate_proof.rb` | `igniter-vm/out/vm_candidate_proof/summary.json` | **Ready**. Demonstrates linear instruction execution. Safe to project as developer test telemetry overview. | Candidate execution engine only; no Reference Runtime or official CLI status. |
| **L3** | Forms First Proof | [forms-first-proof.md](forms-first-proof.md) | `active` | `igniter-compiler` | `cargo run -- compile fixtures/forms/positive_forms.ig --out out/forms_test.igapp` | `out/forms_test.igapp/form_table.json`, `form_resolution_trace.json` | **Ready**. Explains type-directed dispatch. Safe to project as custom operator design evidence. | Experimental type-dispatch resolver; no stable parser triggers. |
| **L4** | Capability Passport First Proof | [capability-passport-first-proof.md](capability-passport-first-proof.md) | `active` | `igniter-vm` | `ruby igniter-vm/proofs/io_vm_loader_capability_passport_integration.rb` | `igniter-vm/out/io_vm_loader_capability_passport_integration/` | **Ready**. Demonstrates fail-closed safety. Safe to project as security architecture reference. | Lab-only sandbox validation; no public runtime security guarantee. |
| **L5** | View / GUI / IDE First Proof | [view-gui-ide-first-proof.md](view-gui-ide-first-proof.md) | `active` | `igniter-view-engine`, `igniter-gui-engine`, `igniter-ide` | `ruby igniter-view-engine/run_proof.rb` | `igniter-view-engine/out/view_tree.json`, `igniter-gui-engine/out/scene_introspection_receipt.json` | **Ready**. Traces view/GUI artifacts to Tauri shell. Safe to project as IDE developer tool preview. | Experimental solver and wrapper shell; no public framework promise. |

---

## Site Projection Guidelines

`igniter-org` may consume, copy, or curate tutorial lessons defined here to build user-facing documentation websites. However, the following rules apply:

1. **Frontmatter & Localization**: Frontmatter, translation mappings, and website routing metadata are owned and maintained locally by `igniter-org`. Do not add presentation-specific translation headers to these raw lab files.
2. **Frontier Source**: `igniter-lab` remains the upstream authority for what commands are currently runnable and what outputs they produce.
3. **Policy Wording**: Any projection copied to public sites must preserve the baseline disclaimers (e.g., that VM/compiler behaviors are lab-only candidate evidence, not canonical mainline specifications).
