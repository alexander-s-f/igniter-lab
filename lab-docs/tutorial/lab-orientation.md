# Lab Orientation

Status: active

Goal:
Give a new reader enough context to work inside `igniter-lab` while understanding which parts are active experiments and which parts are formal language decisions.

## Read

Start by understanding the repository shape and the key documentation files:

### Start Here

| File | Why It Matters |
| --- | --- |
| [Repository README](../../README.md) | High-level component map and lab evidence policy. |
| [Lab Docs README](../README.md) | Durable documentation index. |
| [Current Status](../STATUS.md) | Current transfer-era package and lane status. |
| [Agent Mapping](../../.agents/agent-mapping.md) | Where new cards and durable docs must be written. |

### Main Components

| Component | What To Expect |
| --- | --- |
| `igniter-compiler/` | Experimental parser, typechecker, SemanticIR, forms, and `.igapp` generation work. |
| `igniter-vm/` | Experimental VM candidate, loader, passport, and execution proof surfaces. |
| `igniter-stdlib/` | Experimental stdlib, IO, capability, and effect surfaces. |
| `igniter-ide/` | Tauri/Svelte IDE for debugging, trace inspection, previews, and viewer experiments. |
| `igniter-view-engine/` | View artifact, safe rendering, and isomorphic view framework pressure. |
| `igniter-gui-engine/` | Headless GUI scene/layout/rendering and receipt proof surface. |

### Evidence Vocabulary

| Term | Meaning |
| --- | --- |
| proof-local evidence | A bounded proof result from a specific fixture, runner, or package. |
| lab-only candidate | A working idea that may be useful and may still change before formal adoption. |
| frontier pressure | A signal that a future spec, proposal, or implementation boundary may need work. |
| result packet | Machine-readable or compact evidence summary from a proof runner. |
| closed surface | A capability or claim that remains explicitly unauthorized. |

## Try

From the package directories inside your checkout, run basic package-local tests:

```bash
cd igniter-vm
cargo test
```

Or run a headless GUI layout resolver proof:

```bash
cd igniter-gui-engine
ruby run_proof.rb
```

## Observe

Observe the terminal output:
- For `cargo test`, you should see passing test units (e.g., `test result: ok.`).
- For the GUI engine, you should see passing layout resolution metrics (e.g., `ALL CHECKS PASS!`).
- Confirm that no background processes, network listeners, or servers are left active.

## What This Proves

Executing these commands proves that:
- Your local compiler, VM, and interpreter toolchains are correctly set up.
- The repository source files compile and execute local proof targets successfully.

Running these tests confirms your local lab checkout can exercise the current
proof targets. Formal language decisions are still made in `igniter-lang`.

## Boundary

Igniter Lab is an active pre-v1 frontier workspace. Its packages and APIs are
provided as-is for exploration and may change quickly. Use the lessons as a
practical guide to the current lab surface, and use `igniter-lang` source docs
when you need formal language authority.

## Troubleshooting

| Symptom | Next Step |
| --- | --- |
| `cargo` is missing | Install Rust/Cargo before running compiler or VM checks. |
| `ruby` is missing | Install Ruby 3.x before running proof runners. |
| Tests fail to build | Verify that your Rust toolchain is up to date and that you run commands from the correct subdirectory. |
