# Igniter Lab Tutorial

Status: tutorial seed

This section is the learning path for `igniter-lab`. It explains how the lab
works by walking through small, bounded examples and existing proof surfaces.

The tutorial is educational and lab-first. Igniter Lab is in active pre-v1
development: APIs, artifact shapes, commands, and examples may change. Lessons
are provided as-is for learning, feedback, and experimentation; formal language
authority lives in the `igniter-lang` source documents and accepted decisions.

## Learning Path

| Step | Lesson | Purpose |
| --- | --- | --- |
| 0 | [Lab Orientation](lab-orientation.md) | Learn the repo shape, evidence vocabulary, and where to start without reading the full history. |
| 1 | [Compiler First Proof](compiler-first-proof.md) | Compile a tiny `.ig` fixture and inspect the generated SemanticIR and diagnostics. |
| 2 | [VM Candidate Proof](vm-candidate-proof.md) | Run a bounded proof runner and learn how result packets describe evidence. |
| 3 | [Forms First Proof](forms-first-proof.md) | Follow `a + b` from syntax pressure to type-directed form resolution and lowering evidence. |
| 4 | [Capability Passport First Proof](capability-passport-first-proof.md) | Inspect an IO capability passport and the fail-closed loader boundary. |
| 5 | [View / GUI / IDE First Proof](view-gui-ide-first-proof.md) | Trace a view artifact through preview, safe rendering, GUI receipts, and IDE inspection. |

## Supporting Resources

- [Tutorial Manifest](tutorial-manifest.md): Catalog of lessons, commands, and site projection statuses.
- [Tutorial Command Matrix](tutorial-command-matrix.md): Command verification matrix.
- [Tutorial Glossary](tutorial-glossary.md): Definition of extensions and concepts (e.g. `.ig`, `.igapp`, SemanticIR).
- [Site Projection Excerpts](site-projection-excerpts.md): Inviting pre-v1 summaries for public website consumption.
- [Expected Output Snippets](expected-output-snippets.md): Concrete success indicators and file schemas.

## Tutorial Writing Rules

- Use repo-relative paths for same-repo links.
- Use `<project>/path/to/file` links for cross-repo references.
- Keep lessons runnable or inspectable with local commands when practical.
- Prefer one concept per lesson.
- Distinguish source code, proof artifact, receipt, and decision evidence.
- Keep lab behavior framed as evidence only.
- Do not write absolute local paths or local file URI links.

## Suggested Format

Each lesson should use this structure:

```text
# Lesson Title

Status: draft | active | verified

Goal:
What the reader will understand or verify.

Read:
Small set of files to inspect.

Try:
One or two commands or UI actions.

Observe:
What output, receipt, or diagnostic to look for.

Boundary:
What this lesson does not claim.
```
