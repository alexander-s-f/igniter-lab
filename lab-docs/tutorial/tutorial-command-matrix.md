# Igniter Lab Tutorial Command Verification Matrix

This matrix lists all commands referenced inside the tutorial lessons, specifying the environment requirements, expected outputs, git tracking status, and verification history.

## Verification Command Matrix

| Lesson | Command | Working Directory | Expected Success Signal | Generated Output Path | Staged/Tracked? | Verified in P3? | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| **L0** | `cargo test` | `igniter-vm/` | Test runner outputs passing unit and doc tests (exit 0) | None (target/ ignored) | No (ignored) | Yes | Bounded crate tests |
| **L0** | `ruby run_proof.rb` | `igniter-gui-engine/` | Solves scene layout metrics, logs success (exit 0) | `igniter-gui-engine/out/` | No (ignored) | Yes | Bounded headless UI proof |
| **L1** | `cargo run -- compile fixtures/conformance/source/add.ig --out out/tutorial_add.igapp` | `igniter-compiler/` | Outputs compilation report JSON showing `"status": "ok"` | `igniter-compiler/out/tutorial_add.igapp/` | No (ignored) | Yes | Compiles `Add` fixture |
| **L2** | `ruby igniter-vm/proofs/vm_candidate_proof.rb` | Repository root | Writes result packet with all target checks passing | `igniter-vm/out/vm_candidate_proof/summary.json` | No (ignored) | Yes | Bounded VM candidate run |
| **L3** | `cargo run -- compile fixtures/forms/positive_forms.ig --out out/forms_test.igapp` | `igniter-compiler/` | Generates type-directed form tables and resolution traces | `igniter-compiler/out/forms_test.igapp/` | No (ignored) | Yes | Compiles `Forms` fixture |
| **L4** | `ruby igniter-vm/proofs/io_vm_loader_capability_passport_integration.rb` | Repository root | Logs 17 safety validation targets passing (exit 0) | `igniter-vm/out/io_vm_loader_capability_passport_integration/` | No (ignored) | Yes | Fail-closed delegation check |
| **L5** | `ruby igniter-view-engine/run_proof.rb` | Repository root | Compiles `.igv` files and writes SSR HTML files | `igniter-view-engine/out/` | No (ignored) | Yes | Bounded SSR view proof |
| **L5** | `ruby igniter-gui-engine/run_proof.rb` | Repository root | Resolves scene constraints and writes SVG frames | `igniter-gui-engine/out/` | No (ignored) | Yes | Headless scene resolution |
| **L5** | `npm run check` | `igniter-ide/` | Svelte check passes cleanly with exit code 0 | None (build/ and node_modules/ ignored) | No (ignored) | Yes | Static Svelte checker |

---

## Skipped Commands

All cheap local commands listed above have been executed successfully during this round. No commands were skipped.
If local compilers (Rust/Ruby/Node) are missing on your workstation, please consult the troubleshooting table inside the corresponding tutorial lesson.
