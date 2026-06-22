# Igniter Lab Project Map

Status: current lab map
Updated: 2026-06-19
Owner: local lab / status curator

---

## Purpose

This is the compact map for `igniter-lab`.

Igniter Lab collects alternative implementation experiments, runtime and backend
candidates, tooling prototypes, application pressure, and proof packets. It is
useful for rapid exploration and evidence gathering, but it is not canonical
Igniter state unless a mainline Igniter decision explicitly accepts a slice.

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

As of 2026-06-19 the lab is grouped by flat domain umbrellas:

```text
lang/       compiler, VM, stdlib, language research
runtime/    machine runtime, temporal backend, runtime/storage adapters
server/     igniter-server, igniter-web, IgWeb runner
frame-ui/   frame runtime, UI kit, console, 3D/GUI, view-engine, design assets
ide/        JetBrains plugin, Tauri/Svelte lab IDE
apps/       app/product pressure fixtures
archive/    parked stubs kept for explicit later disposition
```

There is still no root Cargo workspace. Rust crates are standalone and use
relative `path` dependencies. Run checks from each crate directory until a later
workspace-root card changes that.

## Domain Table

| Domain | Contents | Status | Primary entry points |
| --- | --- | --- | --- |
| `lang/` | `igniter-compiler`, `igniter-vm`, `igniter-stdlib`, `igniter-research` | Active language/runtime evidence. | `lang/igniter-compiler/src/`, `lang/igniter-vm/src/`, `lang/igniter-stdlib/stdlib/` |
| `runtime/` | `igniter-machine`, `igniter-tbackend`, `acts-as-tbackend` | Active machine/substrate evidence. | `runtime/igniter-machine/src/`, `runtime/igniter-tbackend/src/` |
| `server/` | `igniter-server`, `igniter-web` | Active server/app/IgWeb evidence. | `server/igniter-server/src/`, `server/igniter-web/src/bin/igweb-serve.rs` |
| `frame-ui/` | `igniter-frame`, `igniter-ui-kit`, `igniter-console`, `igniter-3d`, `igniter-gui`, `igniter-view-engine`, GUI/3D/design proofs | Active UI/frame/console/view evidence. | `frame-ui/igniter-frame/src/`, `frame-ui/igniter-ui-kit/src/`, `frame-ui/igniter-console/src/`, `frame-ui/igniter-view-engine/STATUS.md` |
| `ide/` | `igniter-jetbrains-plugin`, `igniter-ide` | Active tooling evidence. | `ide/igniter-jetbrains-plugin/src/main/kotlin/`, `ide/igniter-ide/src-tauri/src/` |
| `apps/` | `igniter-apps` | App/product pressure fixtures. | `apps/igniter-apps/*` |
| `archive/` | old `igniter-site`, nested `igniter-lab` stubs | Parked, not active surface. | explicit disposition only |
| `lab-docs/` | research/proof/status docs | Durable lab meaning. | `lab-docs/STATUS.md`, `lab-docs/ROADMAP.md` |
| `.agents/` | cards, handoffs, operational packets | Dispatch/handoff memory. | `.agents/work/cards/` |

## Verification Snapshot

The 2026-06-19 domain rehome landed in commit `9bb6508`.

Verified after the move:

```text
runtime/igniter-machine cargo test --no-default-features --no-fail-fast  -> green
server/igniter-server cargo test                                         -> green in rehome pass
server/igniter-web cargo test                                            -> green in rehome pass
frame-ui Rust crates                                                     -> green in rehome pass
ide/igniter-jetbrains-plugin ./gradlew test --rerun-tasks                -> green
ide/igniter-ide/src-tauri cargo check                                    -> green
```

All known older red tests have been cleared (all suites compile and run 100% green as of 2026-06-22).

## Relationship Map

```text
apps / .ig fixtures
  -> lang/igniter-compiler
  -> lang/igniter-vm or runtime/igniter-machine
  -> runtime/igniter-tbackend where storage/fact pressure is needed

server/igniter-web
  -> generated .ig via lang/igniter-compiler
  -> runtime/igniter-machine for lab execution proofs
  -> server/igniter-server as transport/process substrate

frame-ui/*
  -> machine-free UI/frame artifacts by default
  -> runtime/igniter-machine only through host-side bridge proofs

ide/*
  -> tooling over compiler/runtime/frame evidence
  -> no language/runtime authority
```

## Status Vocabulary

| Status | Meaning |
| --- | --- |
| active evidence | Useful implementation evidence, not canonical acceptance. |
| proof archive | Historical proof scripts and reports remain useful for comparison. |
| substrate candidate | Backend/runtime capability evidence only, not public runtime authority. |
| app pressure | Product/DX learning only. |
| parked stub | Kept for explicit later disposition; not active surface. |

## Recommended Next Documentation Moves

1. Add a root Cargo workspace only as an explicit structural card, not as a
   side effect of this map.
2. Replace package READMEs opportunistically when a package is actively touched.
3. Keep this map compact; move detailed evidence into dated status reports or
   proof packets.
4. When a lab slice becomes mainline-relevant, route it through a bounded
   Igniter decision/proof card before treating it as canonical.
