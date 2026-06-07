# igniter-lab: Current Status

Last updated: 2026-06-06

`igniter-lab` is the frontier lab repo for Igniter experiments. It contains
working prototypes, proof runners, research reports, and agent handoffs that
help pressure-test future language, runtime, backend, tooling, and GUI ideas.

The lab is evidence only. It is not the canonical language specification, not
public runtime support, not a Reference Runtime, and not a release or
production surface.

## Transfer Snapshot

The initial positive transfer is being committed package by package. Generated
outputs, build directories, logs, WAL/state files, and local machine paths are
excluded by default.

Committed source packages so far:

| Package | Status |
| --- | --- |
| `igniter-compiler/` | Imported as lab compiler baseline. |
| `igniter-vm/` | Imported as lab VM baseline. |
| `igniter-stdlib/` | Imported as lab stdlib baseline. |
| `igniter-tbackend/` | Imported as lab temporal backend baseline. |
| `igniter-runtime/` | Imported as Ruby IVM/runtime research baseline. |
| `acts-as-tbackend/` | Imported as ActiveRecord adapter sketch. |
| `igniter-machine/` | Imported as machine/kernel prototype. |
| `igniter-view-engine/` | Imported as view artifact prototype. |
| `igniter-gui-engine/` | Imported as headless GUI prototype. |
| `igniter-design-system/` | Imported as design-system prototype. |
| `igniter-ide/` | Imported as IDE prototype. |
| `igniter-jetbrains-plugin/` | Imported as JetBrains plugin prototype. |
| `igniter-apps/` | Imported as small app prototypes. |

Still open in this transfer slice:

| Surface | Intended treatment |
| --- | --- |
| `.agents/` | Agent handoff index plus living cards. |
| `lab-docs/` | Meaningful reports, proofs, pressure packages, status, roadmap. |
| `igniter-site/` | Keep as stub for later generated docs/tutorial site work. |
| `igniter-lab-value-transfer.md` | Final transfer receipt and policy summary. |

## Live Lab Lanes

| Lane | Status | Boundary |
| --- | --- | --- |
| Forms | Active pressure lane. | Evidence for future language design; no stable grammar claim. |
| IO / capability passports | Active security/capability lane. NET-P2..P6 (300+ checks). PROP-035 grammar landed in igniter-lang 2026-06-07. | Lab-only capability and passport evidence; no public runtime authority. |
| View / GUI / IDE | Active frontier lane. | Prototypes for authoring, preview, trace, and GUI ideas; no framework or product promise. |
| Tauri IVF | Active frontier lane. | Isomorphic view and trace shell experiments; no public app platform claim. |
| Native GUI | Active frontier lane. | Headless scene/layout/rendering proofs; no production renderer claim. |
| Loops / recursion | Mainline-pressure lane. | Lab behavior remains evidence until accepted by explicit mainline decisions. |
| Backend / machine | Research lane. | Backend and unified-machine ideas remain substrate research, not runtime authority. |

## Operating Rule

Use `.agents/` for dispatch and handoff memory. Use `lab-docs/` for durable
meaning. When in doubt, keep the living source package small and put large
explanations in `lab-docs`.
