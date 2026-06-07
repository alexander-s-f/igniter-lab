# LAB-TUTORIAL-P1

Card: LAB-TUTORIAL-P1
Category: tutorial
Agent: [Igniter-Lang Research Agent]
Role: research-agent
Track: lab-tutorial-compiler-first-proof-walkthrough-v0
Route: EXPERIMENTAL / LAB-ONLY
Depends on:
- lab-docs/tutorial/README.md
- lab-docs/tutorial/lab-orientation.md

Goal:
Create the first concrete tutorial lesson for `igniter-lab`: a compact
compiler-first walkthrough that helps a new contributor compile or inspect a
small `.ig` fixture, understand where SemanticIR/diagnostics/result packets
come from, and distinguish proof-local evidence from canonical language
authority.

Scope:
- Read:
  - lab-docs/tutorial/README.md
  - lab-docs/tutorial/lab-orientation.md
  - README.md
  - lab-docs/README.md
  - igniter-compiler/README.md
  - igniter-compiler/verify_compiler.rb
  - igniter-compiler/fixtures/** only as needed
  - igniter-compiler/src/** only as needed to explain the observed artifact
- Write:
  - lab-docs/tutorial/compiler-first-proof.md
  - .agents/work/cards/tutorial/LAB-TUTORIAL-P1.md
- Produce:
  - one beginner-readable lesson;
  - a small read/try/observe/boundary flow;
  - exact commands from inside `igniter-compiler/`;
  - expected outputs or artifact names;
  - explanation of SemanticIR, diagnostics, and proof-local status;
  - a short troubleshooting section for missing toolchains or generated output;
  - D/S/T/R return packet in this card.

Requirements:
- Keep the lesson compact and runnable.
- Use repo-relative links only.
- Do not use absolute local paths or local file URI links.
- Do not add generated outputs to git.
- Do not imply stable grammar, stable API, public runtime support, Reference
  Runtime status, production readiness, release evidence, performance claims,
  certification, portability, or canon authority.
- If a command is stale or unavailable, record that clearly and adjust the
  lesson to inspect existing source/fixtures instead of inventing behavior.

Deliver:
- Tutorial lesson:
  lab-docs/tutorial/compiler-first-proof.md
- Updated card receipt:
  .agents/work/cards/tutorial/LAB-TUTORIAL-P1.md
- D/S/T/R return packet
