# igniter-lab

Experimental playground for Igniter Language frontier work.

`igniter-lab` is a lab-only workspace for prototypes, proof runners, pressure
tests, design-system experiments, IDE work, VM/compiler candidates, GUI
research, and other fast-moving ideas around Igniter.

This repository is not the canonical language specification, not public runtime
support, not a Reference Runtime, and not a production/release surface. Lab
results are evidence and pressure only until a separate Main Line decision
accepts them.

## Workspace Map

| Component | Stack | Role |
| --- | --- | --- |
| [`igniter-compiler`](./igniter-compiler/) | Rust | Experimental compiler and proof fixtures for `.ig` source, SemanticIR, forms, capabilities, and `.igapp` bundle generation. |
| [`igniter-vm`](./igniter-vm/) | Rust | Experimental VM candidate and loader/capability proof surface. |
| [`igniter-stdlib`](./igniter-stdlib/) | Rust | Experimental stdlib and capability/effect proof surface. |
| [`igniter-runtime`](./igniter-runtime/) | Ruby | Runtime playground and proof runners for adapters, capability delegation, and dry-run boundaries. |
| [`igniter-ide`](./igniter-ide/) | Svelte / Tauri | Lab IDE for diagnostics, debugger experiments, view preview, and trace inspection. |
| [`igniter-view-engine`](./igniter-view-engine/) | Ruby / JS | Experimental Igniter view artifact and safe preview work. |
| [`igniter-gui-engine`](./igniter-gui-engine/) | Ruby | Headless GUI scene/layout/rendering proof surface. |
| [`igniter-design-system`](./igniter-design-system/) | HTML/assets | Lab design-system sketches and visual direction. |
| [`igniter-tbackend`](./igniter-tbackend/) | Rust / Ruby | Experimental temporal backend and storage pressure surface. |
| [`igniter-apps`](./igniter-apps/) | Mixed | Small lab applications and product-pressure sketches. |
| [`lab-docs`](./lab-docs/) | Markdown | Frontier notes, proof summaries, status reports, pressure packages, and research packets. |
| [`.agents`](./.agents/) | Markdown | Lab agent handoff cards and return packets. |

## Quick Start

Install the toolchains needed for the package you are working on:

- Rust and Cargo for `igniter-compiler`, `igniter-vm`, `igniter-stdlib`, and
  other Rust experiments.
- Ruby 3.x for proof runners and runtime playgrounds.
- Node.js and npm for `igniter-ide` and browser-facing view experiments.

Common local checks:

```bash
ruby igniter-compiler/verify_compiler.rb
ruby igniter-compiler/verify_loops.rb
ruby igniter-gui-engine/run_proof.rb
ruby igniter-stdlib/proofs/experimental_io_stdlib_candidate_proof.rb
```

IDE development:

```bash
cd igniter-ide
npm install
npm run tauri dev
```

Rust package checks are package-local, for example:

```bash
cd igniter-compiler
cargo test
```

## Evidence Policy

Lab artifacts should be described precisely:

- proof-local evidence;
- lab-only candidate behavior;
- frontier design pressure;
- experimental implementation signal.

Avoid wording that implies:

- canonical language authority;
- stable grammar or public API;
- public runtime support;
- Reference Runtime status;
- production readiness;
- release evidence;
- performance, certification, or portability guarantees.

## Generated Output Policy

Generated outputs are local evidence and should stay out of normal commits
unless a specific proof card requires them:

- `out/`
- `.igapp/`
- `target/`
- `node_modules/`
- `.svelte-kit/`
- `build/`
- `.gradle/`
- logs, WAL/state files, temporary files, and local machine paths

## Relationship To Other Repositories

- `igniter-lang` owns the language specification and Main Line decisions.
- `igniter-ruby` owns the Ruby Framework and package umbrella.
- `igniter-lab` explores frontier ideas and returns evidence back to those
  product repositories through explicit review routes.

## License

License policy should be copied or finalized before public release. Until then, keep lab materials internal/frontier and preserve upstream license requirements.
