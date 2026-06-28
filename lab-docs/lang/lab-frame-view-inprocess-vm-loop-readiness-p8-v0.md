# LAB-FRAME-VIEW-INPROCESS-VM-LOOP-READINESS-P8

Date: 2026-06-28
Status: DONE (readiness/design)
Route: standard / igniter-lab / frame-ui / igniter-frame / VM-loop / readiness
Depends-On: `LAB-FRAME-VIEW-EQ-WORKAROUND-REMOVAL-P7`

Readiness/design only. **No production code changed.** No `.ig`/form/`.igv`/`.ig.html`/bridge
semantics change; no dependency added; `Cargo.lock` untouched. Public claim is scoped to frame-ui
DX — this is not a canonical app runner.

## Current boundary (what we have after P7) and what it buys

```text
authored .ig View/Reduce  --(igc compile, offline)-->  .igapp
  --(subprocess `igniter-vm run --entry … --inputs … --json`)-->  Element / State JSON
  --(checked-in, latency-normalized runtime fixtures)-->  frame-ui bridge/runtime tests
```

What it buys (keep regardless of any adapter):
- **frame-ui library stays machine-free and wasm-safe.** No VM/compiler/IO in the core.
- **Deterministic, reviewable proofs.** The `vm_loop_*.runtime.json` fixtures are command-produced
  (P7 documents the exact command; `latency_us` normalized to 0 → byte-reproducible) and reviewed
  in-tree.
- **Honest engine boundary.** The bridge is engine-agnostic about how the Element JSON was made.

What it costs (the DX pain this card scopes):
- The live loop (`examples/vm_loop.rs`) needs the `igniter-vm` binary on a path and spawns a
  process per `View`/`Reduce` call, threading temp JSON files. Fine for fixture-gen and a demo,
  clunky as an interactive in-process loop.

## Live dependency map (verify-first, file:line)

| Crate | Exposes | tokio? | Compiler? | Backend/IO? | wasm-safe? |
| --- | --- | --- | --- | --- | --- |
| `igniter_frame` core | layout/solve/bridge/runtime ports; `project_ig_element`, `render_ig_view` | no | no | no | **yes** (lib builds `--no-default-features` and `--features wasm`) |
| `igniter_vm` | `vm`, `compiler` (bytecode), `value`, `pipeline`, … as a **library** | **yes (full)** | no (bytecode only; front-end is in `igniter-compiler`) | no | **no** today (tokio-full) |
| `igniter_machine` | `load_contract_source` (`.ig` source → register), `dispatch`, backend/IO, capability data-plane | **yes (full)** | **yes** (pulls `igniter_compiler`) | **yes** | **no** |

Two load/run facts that shape the options:
- The `.igapp` **load + entry-run** logic currently lives in `igniter-vm`'s **binary**
  (`src/main.rs`: reads `<igapp>/semantic_ir_program.json`, builds the VM, runs an entry) — it is
  **not** a clean library function yet. An in-process `igniter_vm` adapter must first lift that into
  the `igniter_vm` library.
- `igniter_machine::load_contract_source(src, name)` + `dispatch(name, inputs)` already does
  **source → in-memory run** in one call — but it pulls the compiler front-end and the whole
  machine IO/tokio surface.

frame-ui features today: `default = ["machine"]`; `machine = ["dep:igniter_machine"]` (TBackend
frame facts); `wasm = ["dep:wasm-bindgen"]` (independent of `machine`).

## Option comparison

| # | Option | Dep pulled into frame-ui | Compile model | wasm | Machine-free core | Verdict |
| --- | --- | --- | --- | --- | --- | --- |
| A | **Subprocess stays** | none | external `igc` + external `igniter-vm` binary | safe (no dep) | yes | **Keep** as the fixture/CI/demo boundary regardless |
| B | **Optional `igniter_vm` adapter** (`vm-loop` feature) | `igniter_vm` (vm+bytecode; no compiler, no backend/IO) | external `igc` → load a built `.igapp` in-process; `render`/`reduce` run on the VM library | native-only today (tokio-full); off for wasm | yes (opt-in, off by default & off for wasm) | **Recommended** |
| C | Optional `igniter_machine` adapter | `igniter_machine` (+`igniter_compiler`, tokio-full, backend/IO) | `.ig` source → in-process compile+run | no | **breaks intent** — pulls compiler + host IO into frame core | Rejected for the view loop (the existing `machine` feature is for TBackend frame facts, a different purpose) |

Option B is the minimal correct dependency: it adds only the VM (the thing that runs the authored
view/reduce), not the compiler or the host IO/data-plane. Compilation stays a separate, prior `igc`
step (the adapter consumes a built `.igapp`) — keeping the "compile is offline, run is in-process"
split. Option C would re-import everything the machine-free core was designed to exclude.

## Recommended feature boundary + dependency proof

A **new `vm-loop` feature**, separate from `machine`, off by default, **never** implied by `wasm`:

```toml
# (proposed — NOT applied in this readiness card)
[features]
default  = ["machine"]
machine  = ["dep:igniter_machine"]   # TBackend frame facts (unchanged)
wasm     = ["dep:wasm-bindgen"]      # machine-free + vm-free (unchanged)
vm-loop  = ["dep:igniter_vm"]        # NEW: native-only in-process View/Reduce runner
```

Dependency proof:
- `vm-loop → igniter_vm` only. `igniter_vm` carries no compiler and no backend/IO, so the view loop
  gains exactly the run engine and nothing else.
- It is **native-only** because `igniter_vm` currently depends on `tokio = full` (wasm-hostile). So
  `vm-loop` must NOT be combined into the wasm build. Making an in-process loop wasm-capable later
  is a separate upstream enabler (gate `igniter_vm`'s tokio behind a feature so the sync VM core
  compiles to `wasm32`); noted, not required for this slice.
- It is **not** folded under `machine`: `machine` means TBackend frame facts; `vm-loop` means "run
  an authored view/reduce program." Different axes, independently selectable.

## Minimal API shape (Q3)

```rust
// frame-ui, behind `--features vm-loop` (native). Pure-ish: IO only at load(); render/reduce are
// deterministic VM runs of a loaded program.
pub struct ViewReduceLoop { /* loaded VM program + resolved view/reduce entries */ }

impl ViewReduceLoop {
    pub fn load(igapp_dir: &Path, view_entry: &str, reduce_entry: &str) -> Result<Self, VmLoopError>;
    pub fn render(&self, state: &serde_json::Value) -> Result<serde_json::Value, VmLoopError>; // Element JSON
    pub fn reduce(&self, state: &serde_json::Value, key: &serde_json::Value)
        -> Result<serde_json::Value, VmLoopError>;                                            // State JSON
}
```

`render` returns the Element JSON the existing `project_ig_element`/`render_ig_view` already consume,
so the bridge is unchanged. No `igc run`/passport flow (Q5): compilation is the prior `igc` step and
view/reduce are pure compute — passports are a machine data-plane concern, not a view loop.

## Failure taxonomy (Q6)

One `VmLoopError` enum, all non-panicking `Result`s:

| Variant | Trigger |
| --- | --- |
| `Load(String)` | `.igapp` dir / `semantic_ir_program.json` missing or unreadable; malformed program JSON |
| `EntryNotFound(String)` | `view_entry` or `reduce_entry` absent from the loaded program |
| `BadInput(String)` | `state`/`key` JSON not the shape the entry expects (e.g. missing field) |
| `VmRuntime(String)` | VM execution error (OOF budget, bad op, type error at run) |

(Mirrors the `igniter-vm run` envelope's `status:"error"`/`"oof"` distinction; `BadInput` vs
`VmRuntime` split keeps an operator's "my input was wrong" separate from "the program faulted".)

## wasm / no-default build status (Q4) — do NOT break the machine-free core

Verified this card (no code changed, so this is the live baseline):

```text
cargo build --manifest-path frame-ui/igniter-frame/Cargo.toml --no-default-features --lib                 # OK (machine-free core)
cargo build --manifest-path frame-ui/igniter-frame/Cargo.toml --no-default-features --features wasm --lib  # OK (wasm core, machine-free)
cargo test  --manifest-path frame-ui/igniter-frame/Cargo.toml                                              # 79/0 (default = machine)
git diff --check                                                                                           # PASS
```

**Caveat (pre-existing, documented per the card):** the suggested `cargo test --no-default-features`
(and `… --features wasm`) commands do **not** currently pass, because two *test* targets
(`tests/frame_projection_tests.rs`, `tests/frame_input_loop_tests.rs`) import `igniter_machine`
unconditionally (no `#![cfg(feature = "machine")]`). The **library** core is machine-free/wasm-safe
(builds above); only those two test binaries are un-gated. This is unrelated to P7/P8 and would be a
tiny separate hygiene fix (add the `cfg` gate). The `vm-loop` adapter must be gated the same way so
it never leaks into the `--no-default-features`/`wasm` builds.

**Invariant restatement:** `--no-default-features` and `--features wasm` MUST remain machine-free AND
vm-free. `vm-loop` is additive, native-only, off by default; the core ports/bridge/runtime never gain
a VM/machine/IO dependency.

## Recommended next slice (Q7) — one implementation card

```text
LAB-FRAME-VIEW-INPROCESS-VM-LOOP-ADAPTER-P9
  Goal: an optional, native-only in-process View/Reduce runner for frame-ui, behind a new `vm-loop`
        feature, without touching the machine-free / wasm core.
  Steps:
    1. Lift `.igapp` load + entry-run from `igniter-vm` `main.rs` into the `igniter_vm` LIBRARY
       (a `pub fn` load + run-entry returning the result Value or a typed error) — a small refactor
       with the binary delegating to it (no behavior change; existing vm tests stay green).
    2. frame-ui: add `vm-loop = ["dep:igniter_vm"]`; implement `ViewReduceLoop` over that library API
       with the `VmLoopError` taxonomy above.
    3. Add a `#[cfg(feature = "vm-loop")]` test driving the SAME `vm_loop_app.ig` loop in-process
       (load → render(sel="") → derive_intent → reduce → render(sel="lead:1") → assert authored
       per-row `selected`), proving parity with the subprocess fixtures.
  Allowed: the lib lift; the `vm-loop` feature + adapter; native-only tests.
  Closed: do NOT enable `vm-loop` by default or under `wasm`; do NOT add the compiler or any
    backend/IO to frame core; do NOT delete the command-produced fixture tests (they stay as the
    machine-free + CI proof); no `.ig`/bridge semantics change; no passport/`igc run` flow.
  Prereq note: in-process loop is native-only until `igniter_vm` gates its tokio dep behind a feature
    (separate upstream enabler for a future wasm in-the-loop).
```

### Acceptance matrix for P9

| Acceptance | Check |
| --- | --- |
| `igniter_vm` lib exposes load + run-entry; binary delegates | existing `igniter-vm` suite + fleet stay green |
| `vm-loop` feature compiles native; `ViewReduceLoop` API as specced | `cargo build --features vm-loop` |
| In-process loop matches subprocess fixtures (authored `selected`) | new `#[cfg(feature="vm-loop")]` test |
| Failure taxonomy returned, never panics | unit tests for Load/EntryNotFound/BadInput/VmRuntime |
| Core unchanged | `--no-default-features --lib` + `--features wasm --lib` still build; default `cargo test` green |
| No dep creep / `Cargo.lock` only gains `igniter_vm` under the opt-in feature | review `git diff` |

## Do-not-break statement

The frame-ui core (ports, `Frame`, layout/solve, `ig_bridge`, `runtime`) MUST keep building with
`--no-default-features` and `--features wasm` with **zero** VM/machine/compiler/IO dependency. The
`vm-loop` adapter is strictly additive, opt-in, native-only, and must never be reachable from the
default-off, wasm, or no-default builds. The command-produced fixture tests remain the canonical
machine-free proof and are not collapsed.
