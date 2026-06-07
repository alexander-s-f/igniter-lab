# LAB-TUTORIAL-P3

Card: LAB-TUTORIAL-P3
Category: tutorial
Agent: [Igniter-Lang Research Agent]
Role: research-agent
Track: lab-tutorial-command-verification-and-site-projection-readiness-v0
Route: EXPERIMENTAL / LAB-ONLY
Depends on:
- LAB-TUTORIAL-P2
- lab-docs/tutorial/README.md
- lab-docs/tutorial/lab-orientation.md
- lab-docs/tutorial/compiler-first-proof.md
- lab-docs/tutorial/vm-candidate-proof.md
- lab-docs/tutorial/forms-first-proof.md
- lab-docs/tutorial/capability-passport-first-proof.md
- lab-docs/tutorial/view-gui-ide-first-proof.md

## Goal
Harden the `igniter-lab` tutorial learning path so it is command-verified, site-projection-ready, and easy for new contributors to follow, while keeping all tutorial material lab-only evidence and not canonical language authority.

## Scope
- Read:
  - README.md
  - lab-docs/README.md
  - lab-docs/STATUS.md
  - lab-docs/tutorial/**
  - igniter-compiler/README.md
  - igniter-vm/README.md
  - igniter-stdlib/README.md
  - igniter-view-engine/README.md
  - igniter-gui-engine/README.md
  - igniter-ide/README.md
  - selected proof runners referenced by tutorial lessons
- Write:
  - lab-docs/tutorial/README.md
  - lab-docs/tutorial/*.md
  - lab-docs/tutorial/tutorial-manifest.md
  - lab-docs/tutorial/tutorial-command-matrix.md
  - .agents/work/cards/tutorial/LAB-TUTORIAL-P3.md

## Deliverables
- Normalized tutorial learning path files.
- `lab-docs/tutorial/tutorial-manifest.md`
- `lab-docs/tutorial/tutorial-command-matrix.md`
- Updated card receipt:
  `.agents/work/cards/tutorial/LAB-TUTORIAL-P3.md`
- Compact D/S/T/R return packet.

---

## D/S/T/R Return Packet

### Decision (D)
- Reorganized and normalized every lesson to follow the strict 7-section shape.
- Documented all execution details in a central tutorial manifest and command matrix.
- Clarified site projection rules and disclaimers.

### Status (S)
- **Status**: [CLOSED]
- Normalization and command matrices successfully verified and closed.

### Telemetry (T)
- Verified VM candidate proof runner (`ruby igniter-vm/proofs/vm_candidate_proof.rb` -> PASS).
- Verified VM loader capability passport runner (`ruby igniter-vm/proofs/io_vm_loader_capability_passport_integration.rb` -> PASS).
- Verified Forms compiler command (`cargo run -- compile fixtures/forms/positive_forms.ig --out out/forms_test.igapp` -> PASS).
- Verified View engine proof runner (`ruby igniter-view-engine/run_proof.rb` -> PASS).
- Verified GUI engine proof runner (`ruby igniter-gui-engine/run_proof.rb` -> PASS).
- Verified Svelte typechecker check in IDE package (`npm run check` -> PASS).
- Tested `git diff --check` (clean PASS) and confirmed all output directories stay ignored.
- Confirmed no absolute local paths or local file URI link literals are written.

### Route (R)
- Returning card receipt to workspace supervisor. All objectives for LAB-TUTORIAL-P3 are complete.
