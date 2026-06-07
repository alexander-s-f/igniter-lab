# Lab Orientation

Status: active seed

Goal: give a new reader enough context to work inside `igniter-lab` without
confusing frontier experiments with canonical Igniter language authority.

## What This Repo Is

`igniter-lab` is a frontier workspace. It contains prototypes, proof runners,
research reports, IDE experiments, GUI experiments, design-system work, and
pressure packages that may later inform `igniter-lang` or `igniter-ruby`.

Lab output is useful evidence, not authority. A proof can show that an idea is
promising, but it does not by itself create stable language grammar, runtime
support, public API, Reference Runtime status, release readiness, or production
claims.

## Start Here

| File | Why It Matters |
| --- | --- |
| [Repository README](../../README.md) | High-level component map and lab evidence policy. |
| [Lab Docs README](../README.md) | Durable documentation index. |
| [Current Status](../STATUS.md) | Current transfer-era package and lane status. |
| [Agent Mapping](../../.agents/agent-mapping.md) | Where new cards and durable docs must be written. |

## Main Components

| Component | What To Expect |
| --- | --- |
| `igniter-compiler/` | Experimental parser, typechecker, SemanticIR, forms, and `.igapp` generation work. |
| `igniter-vm/` | Experimental VM candidate, loader, passport, and execution proof surfaces. |
| `igniter-stdlib/` | Experimental stdlib, IO, capability, and effect surfaces. |
| `igniter-ide/` | Tauri/Svelte IDE for debugging, trace inspection, previews, and viewer experiments. |
| `igniter-view-engine/` | View artifact, safe rendering, and isomorphic view framework pressure. |
| `igniter-gui-engine/` | Headless GUI scene/layout/rendering and receipt proof surface. |
| `lab-docs/` | Durable research, proof summaries, pressure packages, roadmap, status, and tutorial. |
| `.agents/` | Agent cards, handoff receipts, mapping rules, and work queues. |

## Evidence Vocabulary

| Term | Meaning |
| --- | --- |
| proof-local evidence | A bounded proof result from a specific fixture, runner, or package. |
| lab-only candidate | A working idea that may be useful but is not canon. |
| frontier pressure | A signal that a future spec, proposal, or implementation boundary may need work. |
| result packet | Machine-readable or compact evidence summary from a proof runner. |
| closed surface | A capability or claim that remains explicitly unauthorized. |

## Safe First Commands

Run commands from the package that owns the proof:

```bash
cd igniter-gui-engine
ruby run_proof.rb
```

```bash
cd igniter-ide
npm run check
```

```bash
cd igniter-vm
cargo test
```

These commands validate local lab packages. Passing checks do not promote the
feature to canon.

## Boundary

This tutorial does not authorize migration, package publication, public runtime
support, stable grammar, stable API, Reference Runtime status, performance
claims, certification, or portability guarantees.
