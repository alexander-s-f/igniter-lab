# Igniter IDE Lab Prototype

Igniter IDE is a lab-only SvelteKit/Tauri workbench for exploring Igniter Lang developer tooling.

This package is a frontier prototype inside `igniter-lab`. It is not a public IDE product, frozen editor contract, production application, release artifact, reference-runtime surface, or canonical language authority. It exists to make compiler, VM, view, trace, debugger, and proof artifacts easier to inspect while the language and lab experiments are still moving quickly.

## Current Surface

- SvelteKit/Vite frontend shell for local IDE experiments.
- Tauri wrapper and proof-window experiments for native desktop workflows.
- Monaco-based source editing and syntax theme integration.
- Contract browser, DAG, blueprint, dispatch, timeline, tracer, debugger, docs, and view preview panels.
- Safe view-tree preview and GUI interaction IR experiments.
- Static copies of selected language docs for offline lab inspection.

## Lab Boundaries

- Generated folders such as `.svelte-kit/`, `build/`, `node_modules/`, and `src-tauri/target/` stay out of git.
- Local app state, local IDE settings, local paths, logs, and proof outputs stay out of git.
- The UI may cite lab evidence and snapshots, but it must not present lab behavior as canonical language support.
- Any future public product, package, release, or compatibility wording needs a separate review.

## Useful Commands

```bash
npm run check
npm run build
npm run tauri -- --help
cd src-tauri && cargo check
```

The Tauri command may require the local Rust/Tauri toolchain. For transfer verification, `npm run check`, `npm run build`, and `cargo check` are the expected baseline.
