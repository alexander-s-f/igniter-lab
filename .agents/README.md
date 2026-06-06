# Igniter Lab Agent Handoffs

Status: compact agent handoff index
Updated: 2026-06-06

`.agents` contains operational handoff cards and return packets for lab agents.
It is intentionally separate from [`../lab-docs/`](../lab-docs/), which holds
larger research reports, proof summaries, pressure packages, and status docs.

## Boundary

Agent cards are coordination evidence. They do not create canonical language
authority, implementation authority, public runtime support, Reference Runtime
status, stable API, production readiness, release evidence, performance claims,
certification, or portability guarantees.

## Active Families

| Prefix | Lane |
| --- | --- |
| `LAB-FORMS-*` | Contract invocation forms research and hardening. |
| `LAB-STDLIB-IO-*` | Experimental IO, capabilities, passports, and loader alignment. |
| `LAB-IDE-*` | IDE debugger and design-system application slices. |
| `LAB-VIEW-DSL-*` | View DSL, safe renderer, and preview work. |
| `LAB-IGNITER-VIEW-FRAMEWORK-*` | Igniter View Framework and view artifact research. |
| `LAB-TAURI-IVF-*` | Tauri isomorphic view framework and trace bridge work. |
| `LAB-NATIVE-GUI-*` | Native/headless GUI scene, layout, rendering, and interaction proofs. |
| `LAB-GUI-*` | Igniter Lang to GUI mapping and schema/form research. |
| `LAB-TAILMIX-*` | Tailmix-inspired interaction IR and GUI applicability research. |

## Current Card

[`current-card.md`](current-card.md) is a scratch pointer to the currently active
or most recent agent slice. Keep it small; durable results belong in the
individual `LAB-*.md` card and the corresponding `lab-docs` report.

## Placement Rule

- Put dispatch instructions, return packets, and next-agent cards here.
- Put design reports, proof outcomes, architecture notes, and pressure packages
  in `lab-docs`.
- If a handoff grows into a durable design document, keep the handoff here and
  move the design substance into `lab-docs`.
