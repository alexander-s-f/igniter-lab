# LAB-TUTORIAL-P5

Card: LAB-TUTORIAL-P5
Category: tutorial
Agent: [Igniter-Lang Tutorial Agent]
Role: tutorial-agent
Track: lab-igniter-learning-contracts-tutorial-blueprint-v0
Route: LAB / TUTORIAL / IMPLEMENTATION
Depends on:
- lab-docs/tutorial/README.md
- lab-docs/tutorial/tutorial-manifest.md
- lab-docs/tutorial/lab-orientation.md
- lab-docs/tutorial/compiler-first-proof.md
- lab-docs/tutorial/forms-first-proof.md
- lab-docs/tutorial/capability-passport-first-proof.md
- <igniter-lang>/README.md
- <igniter-lang>/docs/language-covenant.md

## Goal

Design and implement the first version of the Igniter tutorial learning model:
lessons teach intent, contract, evidence, diagnostics, capability, composition,
and fail-closed learning before syntax-first detail.

## Files Changed

- `lab-docs/tutorial/igniter-learning-contracts.md`
- `lab-docs/tutorial/learning-contract-00-orientation.md`
- `lab-docs/tutorial/learning-contract-01-first-contract.md`
- `lab-docs/tutorial/learning-contract-02-fail-closed.md`
- `lab-docs/tutorial/learning-contract-03-evidence.md`
- `lab-docs/tutorial/tutorial-manifest.md`
- `.agents/work/cards/tutorial/LAB-TUTORIAL-P5.md`

## Structure Checklist

- [x] Learning model overview doc created.
- [x] Four initial lessons created.
- [x] Tutorial manifest links the learning model and all four new lessons.
- [x] Each lesson uses the required sections:
  Intent, Contract, Inputs, Example, Run / Inspect, Expected Evidence,
  Expected Failure, Diagnostic, Reflection, Next Composition.
- [x] Beginner path included.
- [x] Proof-first path included.
- [x] At least one broken contract exercise included.
- [x] Compact glossary included.

## Claim-Boundary Checklist

- [x] No absolute local paths in written files.
- [x] No local file URI links in written files.
- [x] No maturity, deployment, shipment, or speed claims.
- [x] No claim that lab behavior is canon.
- [x] Lab evidence is explicitly framed as evidence only.
- [x] Syntax appears only after intent and boundary framing.
- [x] No sibling-framework drift introduced.
- [x] Tone uses active development / APIs may change / provided as-is wording
      without overusing warnings.

## D/S/T/R Return Packet

### Decision (D)

Implemented the learning-contract tutorial model as a lab-local teaching layer.
The model treats fail-closed behavior as useful evidence, separates lab evidence
from canon authority, and gives learners both a beginner path and a proof-first
path.

### Status (S)

Status: CLOSED for LAB-TUTORIAL-P5.

### Telemetry (T)

Verification performed:

- local-path and local-URI hygiene scan
- maturity/deployment/shipment/speed claim scan
- sibling-framework drift scan
- lesson-section coverage check for all four learning-contract lessons
- markdown whitespace check

### Route (R)

Return to tutorial supervisor. Recommended next slice:

LAB-TUTORIAL-P6:
Convert the first four lessons into site-ready excerpts for `igniter-org-jekyll`
without editing the site yet.
