# LAB-TUTORIAL-P4

Card: LAB-TUTORIAL-P4
Category: tutorial
Agent: [Igniter-Lang Research Agent]
Role: research-agent
Track: lab-tutorial-public-projection-excerpts-and-learning-glossary-v0
Route: EXPERIMENTAL / LAB-ONLY
Depends on:
- LAB-TUTORIAL-P3
- lab-docs/tutorial/README.md
- lab-docs/tutorial/tutorial-manifest.md
- lab-docs/tutorial/tutorial-command-matrix.md

## Goal
Create a compact public-projection support layer for the `igniter-lab` tutorial: short lesson summaries, glossary terms, expected-output snippets, and site-copy excerpts that `igniter-org` can consume without copying the full lab history or weakening the pre-v1/as-is positioning.

## Scope
- Read:
  - README.md
  - lab-docs/README.md
  - lab-docs/STATUS.md
  - lab-docs/tutorial/**
  - selected package README files referenced by tutorial lessons
- Write:
  - lab-docs/tutorial/tutorial-glossary.md
  - lab-docs/tutorial/site-projection-excerpts.md
  - lab-docs/tutorial/expected-output-snippets.md
  - lab-docs/tutorial/README.md
  - lab-docs/tutorial/tutorial-manifest.md
  - .agents/work/cards/tutorial/LAB-TUTORIAL-P4.md

## Deliverables
- `lab-docs/tutorial/tutorial-glossary.md`
- `lab-docs/tutorial/site-projection-excerpts.md`
- `lab-docs/tutorial/expected-output-snippets.md`
- Updated tutorial README/index.
- Updated card receipt:
  `.agents/work/cards/tutorial/LAB-TUTORIAL-P4.md`
- Compact D/S/T/R return packet.

---

## D/S/T/R Return Packet

### Decision (D)
- Drafted beginner-readable glossary definitions for core lab concepts: [tutorial-glossary.md](lab-docs/tutorial/tutorial-glossary.md).
- Created site-ready copy excerpts and concrete expected-output snippets: [site-projection-excerpts.md](lab-docs/tutorial/site-projection-excerpts.md) & [expected-output-snippets.md](lab-docs/tutorial/expected-output-snippets.md).
- Integrated the new files in the main index [README.md](lab-docs/tutorial/README.md) and linked in [tutorial-manifest.md](lab-docs/tutorial/tutorial-manifest.md).

### Status (S)
- **Status**: [CLOSED]
- Public projection support files successfully created, linked, and verified.

### Telemetry (T)
- Tested `git diff --check` (clean PASS) and confirmed all output files stay ignored.
- Confirmed no absolute local paths or local file URI link literals exist in the tutorial files or cards.

### Route (R)
- Returning card receipt to workspace supervisor. All objectives for LAB-TUTORIAL-P4 are complete.
