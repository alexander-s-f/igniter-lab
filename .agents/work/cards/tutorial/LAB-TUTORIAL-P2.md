# LAB-TUTORIAL-P2

Card: LAB-TUTORIAL-P2
Category: tutorial
Agent: [Igniter-Lang Research Agent]
Role: research-agent
Track: lab-tutorial-learning-path-expansion-v0
Route: EXPERIMENTAL / LAB-ONLY
Depends on:
- lab-docs/tutorial/README.md
- lab-docs/tutorial/lab-orientation.md
- lab-docs/tutorial/compiler-first-proof.md

## Goal
Expand the `igniter-lab` tutorial from the current orientation/compiler seed into a coherent beginner learning path, adding the next compact lessons for VM candidate evidence, forms, capability passports, and view/GUI/IDE inspection, without creating canonical language authority, stable grammar/API claims, runtime support claims, or public product promises.

## Scope
- Read:
  - README.md
  - lab-docs/README.md
  - lab-docs/STATUS.md
  - lab-docs/tutorial/README.md
  - lab-docs/tutorial/lab-orientation.md
  - lab-docs/tutorial/compiler-first-proof.md
  - igniter-compiler/README.md
  - igniter-vm/README.md
  - igniter-stdlib/README.md
  - igniter-view-engine/README.md
  - igniter-gui-engine/README.md
  - igniter-ide/README.md
- Write:
  - lab-docs/tutorial/README.md
  - lab-docs/tutorial/vm-candidate-proof.md
  - lab-docs/tutorial/forms-first-proof.md
  - lab-docs/tutorial/capability-passport-first-proof.md
  - lab-docs/tutorial/view-gui-ide-first-proof.md
  - .agents/work/cards/tutorial/LAB-TUTORIAL-P2.md

## Deliverables
- Expanded tutorial README learning path.
- Four new tutorial lessons:
  - `lab-docs/tutorial/vm-candidate-proof.md`
  - `lab-docs/tutorial/forms-first-proof.md`
  - `lab-docs/tutorial/capability-passport-first-proof.md`
  - `lab-docs/tutorial/view-gui-ide-first-proof.md`
- Updated card receipt:
  `.agents/work/cards/tutorial/LAB-TUTORIAL-P2.md`
- Compact D/S/T/R return packet.

---

## D/S/T/R Return Packet

### Decision (D)
- Expanded the learning path into a structured 6-step sequence.
- Kept lessons highly focused, using existing proof runners and compiler commands.
- Maintained strict lab-only disclaimer boundaries on all new files.

### Status (S)
- **Status**: [CLOSED]
- All four lessons successfully integrated and verified.

### Telemetry (T)
- Verified VM candidate proof runner (`ruby igniter-vm/proofs/vm_candidate_proof.rb` -> VMG-1 to VMG-15 PASS).
- Verified VM loader passport integration runner (`ruby igniter-vm/proofs/io_vm_loader_capability_passport_integration.rb` -> IOVM_1 to IOVM_17 PASS).
- Verified Forms compile command (`cargo run -- compile fixtures/forms/positive_forms.ig --out out/forms_test.igapp` -> correctly generates `form_table.json` and `form_resolution_trace.json`).
- Verified View engine proof runner (`ruby igniter-view-engine/run_proof.rb` -> VDSL-1 to VDSL-12 PASS).
- Verified GUI engine proof runner (`ruby igniter-gui-engine/run_proof.rb` -> NGUI-P8-1 to NGUI-P13-14 PASS).
- Verified `git diff --check` passes cleanly.
- Verified no absolute local paths or local file URIs are written.
- Verified generated outputs remain ignored by git.

### Route (R)
- Returning card receipt to the workspace supervisor. All objectives for LAB-TUTORIAL-P2 are complete.
