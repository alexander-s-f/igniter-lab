# Igniter Lab Tutorial Manifest

Status: active development / APIs may change / provided as-is

This manifest catalogs the current tutorial path for `igniter-lab`. It links
the learning-contract model, four initial lessons, and existing proof-first
walkthroughs.

The manifest is a lab navigation artifact. It does not create canon authority.
Lab behavior remains evidence for learning and review.

## Learning Model

| Document | Purpose | Boundary |
| --- | --- | --- |
| [Igniter Learning Contracts](igniter-learning-contracts.md) | Defines learning by contract, the lesson structure, two paths, and glossary terms. | Tutorial model only; not canon. |

## Beginner Path

| ID | Lesson | Path | Focus | Evidence Boundary |
| --- | --- | --- | --- | --- |
| LC-00 | Orientation | [learning-contract-00-orientation.md](learning-contract-00-orientation.md) | Separate intent, evidence, and authority. | Lab evidence is not canon. |
| LC-01 | First Contract | [learning-contract-01-first-contract.md](learning-contract-01-first-contract.md) | Turn intent into declared inputs, output, and evidence. | Small contract shape only. |
| LC-02 | Fail Closed | [learning-contract-02-fail-closed.md](learning-contract-02-fail-closed.md) | Treat refusal as boundary preservation. | Current lab refusal shape only. |
| LC-03 | Evidence | [learning-contract-03-evidence.md](learning-contract-03-evidence.md) | Keep claims scoped to artifacts. | Evidence supports bounded claims only. |

## Proof-First Path

| ID | Lesson | Path | Focus | Evidence Boundary |
| --- | --- | --- | --- | --- |
| PF-01 | Compiler First Proof | [compiler-first-proof.md](compiler-first-proof.md) | Inspect a tiny compiler artifact path. | Current lab compiler artifact shape only. |
| PF-02 | Forms First Proof | [forms-first-proof.md](forms-first-proof.md) | Inspect current form-resolution evidence. | Lab form behavior only. |
| PF-03 | Capability Passport First Proof | [capability-passport-first-proof.md](capability-passport-first-proof.md) | Inspect current capability/refusal evidence. | Lab passport and loader candidate behavior only. |
| PF-04 | Expected Output Snippets | [expected-output-snippets.md](expected-output-snippets.md) | Read compact success and refusal snippets. | Snippets are examples, not authority. |

## Existing Orientation Lessons

| ID | Lesson | Path | Use |
| --- | --- | --- | --- |
| S-00 | Lab Orientation | [lab-orientation.md](lab-orientation.md) | Repository shape and evidence vocabulary. |
| S-01 | View / GUI / IDE First Proof | [view-gui-ide-first-proof.md](view-gui-ide-first-proof.md) | Later composition after the first learning contracts. |
| S-02 | VM Candidate Proof | [vm-candidate-proof.md](vm-candidate-proof.md) | Later proof-first runtime-candidate inspection. |

## Path Recommendation

New readers should start with the beginner path, then choose one proof-first
lesson to inspect concrete evidence. Contributors who already understand the
contract/evidence boundary can start with the proof-first path and keep the
same claim discipline.

## Projection Note

The next slice should prepare site-ready excerpts from the first four
learning-contract lessons without editing the site.
