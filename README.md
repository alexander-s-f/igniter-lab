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

The lab is grouped by flat domain umbrellas. Crates remain standalone unless a
later workspace-root card changes that; run checks from each package directory.

| Umbrella | Stack | Role |
| --- | --- | --- |
| [`lang/`](./lang/) | Rust / docs | Experimental compiler, VM, stdlib, and language research. |
| [`runtime/`](./runtime/) | Rust / Ruby | Machine runtime, temporal backend, and runtime/storage adapters. |
| [`server/`](./server/) | Rust | `igniter-server`, `igniter-web`, IgWeb runner, and server/app protocol work. |
| [`frame-ui/`](./frame-ui/) | Rust / JS / Ruby / assets | Frame runtime, UI kit, console, 3D/GUI proofs, design-system sketches, and live view-engine IDE backend. |
| [`ide/`](./ide/) | Kotlin / Svelte / Tauri | JetBrains plugin and lab IDE. |
| [`apps/`](./apps/) | Mixed | Small lab applications and product-pressure sketches. |
| [`archive/`](./archive/) | Mixed | Stale or parked lab stubs kept for explicit later disposition. |
| [`lab-docs`](./lab-docs/) | Markdown | Frontier notes, proof summaries, status reports, pressure packages, and research packets. |
| [`lab-docs/tutorial`](./lab-docs/tutorial/) | Markdown | Guided learning path for understanding lab packages, proof evidence, and safety boundaries. |
| [`.agents`](./.agents/) | Markdown | Lab agent handoff cards and return packets. |

## Quick Start

Install the toolchains needed for the package you are working on:

- Rust and Cargo for `lang/*`, `runtime/*`, `server/*`, and `frame-ui/*` Rust
  packages.
- Ruby 3.x for proof runners and runtime playgrounds.
- Node.js and npm for `ide/igniter-ide` and browser-facing view experiments.

Common local checks:

```bash
ruby lang/igniter-compiler/verify_compiler.rb
ruby lang/igniter-compiler/verify_loops.rb
ruby frame-ui/igniter-gui-engine/run_proof.rb
ruby lang/igniter-stdlib/proofs/experimental_io_stdlib_candidate_proof.rb
```

IDE development:

```bash
cd ide/igniter-ide
npm install
npm run tauri dev
```

Rust package checks are package-local, for example:

```bash
cd lang/igniter-compiler
cargo test
```

New readers should start with the [Lab Tutorial](./lab-docs/tutorial/README.md)
before following older proof reports.

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
