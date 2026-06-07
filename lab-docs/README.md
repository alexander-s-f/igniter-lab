# Igniter Lab Docs

Status: compact lab documentation index
Updated: 2026-06-06

`lab-docs` is the place for larger lab meaning: research notes, proof reports,
pressure packages, status snapshots, and roadmap-level synthesis.

Agent handoff cards and per-round operating packets belong in
[`../.agents/`](../.agents). If a document is mainly "what the next agent did
or should do", keep it in `.agents`. If it explains a concept, proof result,
architecture boundary, or pressure package, keep it here.

## Start Here

| Document | Purpose |
| --- | --- |
| [Project Map](igniter-lab-project-map.md) | Compact map of lab packages, status vocabulary, and authority boundaries. |
| [Current Status](STATUS.md) | Short transfer-era status snapshot and live lanes. |
| [Roadmap](ROADMAP.md) | Next useful lab directions without treating lab behavior as canon. |
| [Tutorial](tutorial/README.md) | Learning path for understanding lab packages, proof evidence, and safe boundaries. |
| [2026-06-04 Status Report](status-report-2026-06-04.md) | Historical detailed snapshot from the pre-split lab state. |

## Major Meaning Areas

| Area | Representative docs |
| --- | --- |
| Contract invocation forms | [PROP Forms Enhanced](core/PROP-Forms-Enhanced-v0.md), [Forms pressure return](core/FORMS-PRESSURE-RETURN-v0.md), forms proof/hardening/lowering reports. |
| Loops and recursion | [Pressure package](core/loops-and-recursion-pressure-package.md), [pressure return](core/loops-and-recursion-pressure-package-return.md). |
| IO and capabilities | `lab-experimental-io-*` capability, passport, stdlib, compiler bridge, and VM loader reports. |
| View / GUI / IDE | View DSL, Igniter View Framework, Tauri IVF, Native GUI, Tailmix-inspired Interaction IR, and debugger/IDE reports. |
| Runtime/backend research | [Igniter Machine Notes](core/igniter-machine.md), [SparkCRM Shadow](core/igniter-sparkcrm-shadow.md), runtime/backend proof reports. |
| Tutorial | [Lab Orientation](tutorial/lab-orientation.md), compiler/VM/forms/capability/view walkthroughs as they are added. |

## Documentation Boundary

These docs are lab-local evidence and frontier working memory. They do not
create canonical Igniter semantics, runtime support, Reference Runtime status,
stable API, production readiness, public claims, release evidence, performance
guarantees, certification, or portability guarantees.
