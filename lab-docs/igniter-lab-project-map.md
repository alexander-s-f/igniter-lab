# Igniter Lab Project Map

Status: current lab map
Updated: 2026-06-04
Owner: local lab / status curator

---

## Purpose

This is the main map for `igniter-lab`.

Igniter Lab collects alternative implementation experiments, runtime and
backend candidates, tooling prototypes, and pressure packets. It is useful for
rapid exploration and evidence gathering, but it is not canonical Igniter state
unless a mainline Igniter decision explicitly accepts a slice.

## Authority Boundary

Lab evidence may inform canonical work. It does not by itself authorize:

```text
public runtime support
Reference Runtime support
stable API
production readiness
release evidence
Spark integration
public demo claims
public performance claims
portability guarantees
compiler/runtime/API/CLI widening
```

Generated outputs under `out/`, build products under `target/`, WAL/log files,
and local app state are inspection evidence only.

## Repository Shape

As observed on 2026-06-04:

```text
igniter-lab is one nested git repository.
Subprojects are directories inside that repository.
No deeper .git directories were found under the lab root.
```

Current local git hygiene note:

```text
pre-existing working-tree state:
  AD igniter-vm/scratch_inputs.json
```

That file is not interpreted by this map and was not touched by the docs pass.

## Project Status Table

| Project | Kind | Status | Main role | Primary entry points |
| --- | --- | --- | --- | --- |
| `igniter-compiler/` | Rust compiler candidate | active lab compiler / pressure input | Parses, classifies, typechecks, emits `.igapp`-style artifacts and compilation reports for lab fixtures. | `src/lexer.rs`, `src/parser.rs`, `src/classifier.rs`, `src/typechecker.rs`, `src/emitter.rs`, `src/assembler.rs`, `verify_compiler.rb`, `verify_loops.rb` |
| `igniter-vm/` | Rust VM candidate | active delegated runtime candidate | Executes local VM instructions and supports VM candidate proof work. Carries current capability gaps as lab evidence unless accepted by mainline. | `src/vm.rs`, `src/instructions.rs`, `src/compiler.rs`, `src/tbackend.rs`, `proofs/vm_candidate_proof.rb`, `tests/` |
| `igniter-runtime/` | Ruby IVM proof playground | proof archive / delegated runtime research | Earlier Ruby IVM and adapter proof scripts for compiler-to-IVM, branch coverage, AOT loading, FFI/native acceleration, and resident supervisor research. | `README.md`, `lib/ivm/`, `examples/`, `docs/`, `fixtures/` |
| `igniter-stdlib/` | Rust stdlib candidate | proof candidate / expansion needed | Decimal, collection, and temporal stdlib sketches plus candidate proof outputs. | `src/`, `stdlib/`, `proofs/stdlib_candidate_proof.rb`, `verify_stdlib.rb` |
| `igniter-tbackend/` | Rust bitemporal backend playground | backend/substrate candidate | Local bitemporal ledger, query, pack, WAL, analytics, snapshot, mesh, diagnostics, and pipeline experiments. Treat as backend evidence, not runtime authority. | `src/`, `src/packs/`, `test_suite.rb`, `verify_*.rb`, `docs/` |
| `acts-as-tbackend/` | Ruby/ActiveRecord adapter sketch | shadow adapter sketch | Demonstrates model lifecycle fact capture into the local TBackend playground. | `README.md`, `lib/acts_as_tbackend/`, `demo.rb`, `verify_shadow.rb` |
| `igniter-machine/` | unified kernel / machine prototype | experimental architecture prototype | Explores an in-process machine combining compiler, VM, fact memory, bridge, WAL, registry, FFI, REPL, and MCP binaries. | `Cargo.toml`, `src/machine.rs`, `src/backend.rs`, `src/bridge.rs`, `src/bin/repl.rs`, `src/bin/mcp.rs`, `PROP-042.md`, `TUI.md` |
| `igniter-ide/` | Tauri/Svelte IDE prototype | UI prototype / stale template docs | Local IDE shell with contract DAG, fact explorer, temporal timeline, workspace panels, Monaco editor, and Tauri wrapper. README is still template-level and should be replaced later. | `src/lib/components/`, `src-tauri/`, `package.json` |
| `igniter-jetbrains-plugin/` | JetBrains plugin prototype | early IDE plugin prototype | Kotlin plugin skeleton for language, syntax, references, completion, compiler action, and tool window work. README is minimal. | `src/main/kotlin/com/igniter/plugin/`, `build.gradle.kts`, `plugin.xml` |
| `igniter-apps/` | tiny app experiments | local app sketches | Product/application experiments, currently including a temporal todo CLI and benchmark app. | `README.md`, `todolist/`, `benchmark-app/` |
| `lab-docs/` | lab documentation | active map/status/pressure docs | Holds this map, status reports, and pressure/design notes used to route lab evidence back into mainline decisions. | `README.md`, `igniter-lab-project-map.md`, `status-report-2026-06-04.md` |

## Relationship Map

```text
source fixtures / .ig
  -> igniter-compiler
  -> .igapp-style artifacts and reports
  -> igniter-vm or igniter-runtime proof scripts
  -> optional backend reads/writes through igniter-tbackend
  -> future igniter-machine unifies compiler + VM + fact memory in-process

tooling surfaces:
  igniter-ide and igniter-jetbrains-plugin inspect or assist the language
  but do not create language/runtime authority.

application pressure:
  igniter-apps and acts-as-tbackend create local app/shadow evidence only.
```

## Current Main Threads

### Compiler / VM / Runtime Candidate

`igniter-compiler` and `igniter-vm` are the active lab pair. They are useful for
testing how far alternative Rust implementation can go before canonical spec
boundaries need to be resolved.

Current known pressure areas:

```text
loops / recursion / service loops
now() prohibition and tick.time binding
progression fragment-class decision
OOF code registry alignment
integer capability and stdlib parity
backend reads from VM execution
```

### Runtime And Backend Split

`igniter-runtime` records Ruby IVM and delegated runtime proof history.
`igniter-tbackend` is a backend/substrate candidate, not runtime authority.
`igniter-machine` explores the unified in-process direction where compiler,
runtime, and fact memory are one machine.

### Product And Tooling Pressure

`acts-as-tbackend`, `igniter-apps`, `igniter-ide`, and
`igniter-jetbrains-plugin` are applied pressure surfaces. They are valuable for
DX and product understanding, but they do not open production, public docs, or
release claims.

## Status Vocabulary

| Status | Meaning |
| --- | --- |
| active lab compiler / pressure input | Useful implementation evidence, not canonical acceptance. |
| active delegated runtime candidate | Runtime candidate evidence exists, but public/runtime authority remains closed. |
| proof archive / delegated runtime research | Historical proof scripts and reports remain useful for comparison. |
| backend/substrate candidate | Backend capability evidence only, not Igniter runtime authority. |
| experimental architecture prototype | Architecture implementation exists locally but needs mainline route before authority. |
| UI prototype / early plugin prototype | Tooling experiments only. |
| local app sketch | Product pressure and demo-local learning only. |

## Recommended Next Documentation Moves

1. Replace empty or template-level subproject READMEs for:
   `igniter-compiler`, `igniter-vm`, `igniter-machine`,
   `igniter-ide`, and `igniter-jetbrains-plugin`.
2. Add a rotating `status-report-YYYY-MM-DD.md` when lab state changes
   materially.
3. Keep this map compact; move detailed evidence into dated status reports or
   pressure packets.
4. When a lab slice becomes mainline-relevant, route it through a bounded
   Igniter decision/proof card before treating it as canonical.
