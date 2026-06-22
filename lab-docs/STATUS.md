# igniter-lab: Current Status

Last updated: 2026-06-22

`igniter-lab` is the frontier lab repo for Igniter experiments. It contains
working prototypes, proof runners, research reports, and agent handoffs that
help pressure-test future language, runtime, backend, tooling, UI, and server
ideas.

The lab is evidence only. It is not the canonical language specification, not
public runtime support, not a Reference Runtime, and not a release or production
surface.

## Current Shape

The repo is now organized by flat domain umbrellas:

| Domain | Purpose |
| --- | --- |
| `lang/` | Compiler, VM, stdlib, language research. |
| `runtime/` | Machine runtime, temporal backend, storage/runtime adapters. |
| `server/` | `igniter-server`, `igniter-web`, IgWeb runner and server protocol work. |
| `frame-ui/` | Frame/UI kit/console/3D/GUI/view-engine/design-system work. |
| `ide/` | JetBrains plugin and Tauri/Svelte lab IDE. |
| `apps/` | App/product pressure fixtures. |
| `archive/` | Parked stubs and old nested lab material. |

There is still no root Cargo workspace; crates remain package-local.

## Latest Structural Checkpoint

`9bb6508 Rehome lab into domain umbrellas`

Verified after the move:

| Check | Result |
| --- | --- |
| `runtime/igniter-machine cargo test --no-default-features --no-fail-fast` | green |
| `ide/igniter-jetbrains-plugin ./gradlew test --rerun-tasks` | green |
| `ide/igniter-ide/src-tauri cargo check` | green |
| active-code stale-path scan | clean |

Stale known-red claims cleared by targeted recheck on 2026-06-22:

| Surface | Command | Result |
| --- | --- |
| `lang/igniter-compiler` | `cargo test --test loop_conformance_tests` | green: 14 passed, 0 failed |
| `lang/igniter-vm` | `cargo test --test vm_candidate_proof_tests` | green: 9 passed, 0 failed |

This is a targeted recheck only. It clears the stale known-red entries above; it
does not claim whole-repo or whole-workspace green.

## Live Lab Lanes

| Lane | Status | Boundary |
| --- | --- | --- |
| Language / stdlib | Active pressure lane (`lang/`). | Evidence for future language design; no stable grammar claim. |
| Machine / capability IO | Active runtime/substrate lane (`runtime/`). | Lab-only capability and machine evidence; no public runtime authority. |
| Server / IgWeb | Active server/app DX lane (`server/`). | Loopback/lab runner evidence; no public hosting or production claim. |
| Frame / UI / console | Active UI authoring lane (`frame-ui/`). | Machine-free UI evidence unless explicitly bridged by host-side proof. |
| IDE tooling | Active tooling lane (`ide/`). | Editor/tooling assistance only; no language/runtime authority. |
| Apps / product pressure | Active fixture lane (`apps/`). | Product/DX learning only. |

## Operating Rule

Use `.agents/` for dispatch and handoff memory. Use `lab-docs/` for durable
meaning. Use `MAP.md` and this status file as the front door. When answering
"is X implemented?", verify the package-local `IMPLEMENTED_SURFACE.md` and
live source before trusting old proof prose.
