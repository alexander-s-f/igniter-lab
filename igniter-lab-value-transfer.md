# igniter-lab Value Transfer Map

Status: transfer receipt / frontier only / no public authority
Date: 2026-06-06

## Principle

This repo receives the frontier playground that helps the language and framework
discover future directions. It must not become canonical language authority by
accident. Bring working lab source and compact lab docs; leave generated outputs
and dependency/build directories behind.

Path notation:
- source paths are relative to `projects/`
- target paths are relative to `igniter-workspace/`

## Transfer Progress

The first transfer pass is proceeding package by package. Source packages are
committed separately so each slice can be reviewed and rolled back locally if
needed.

Already committed:

```text
igniter-compiler
igniter-vm
igniter-stdlib
igniter-tbackend
igniter-runtime
acts-as-tbackend
igniter-machine
igniter-view-engine
igniter-gui-engine
igniter-design-system
igniter-ide
igniter-jetbrains-plugin
igniter-apps
```

Still open in the current transfer slice:

```text
.agents
lab-docs
igniter-site
this value-transfer receipt
```

## Bring First

| Source | Target | Why |
| --- | --- | --- |
| `igniter/igniter-lab/README.md` if present | `igniter-workspace/igniter-lab/README.md` | Lab identity and warning banner. |
| `igniter/igniter-lab/.agents/` | `.agents/` | Agent handoff cards and return packets; keep operational docs here. |
| `igniter/igniter-lab/lab-docs/` | `lab-docs/` | Frontier reports, proof summaries, pressure packages, maps, status, and roadmap. |
| `igniter/igniter-lab/igniter-compiler/src/` | `igniter-compiler/src/` | Lab compiler source. |
| `igniter/igniter-lab/igniter-compiler/fixtures/` | `igniter-compiler/fixtures/` | Source fixtures for proofs. |
| `igniter/igniter-lab/igniter-compiler/proofs/` | `igniter-compiler/proofs/` | Proof runners, not generated outputs. |
| `igniter/igniter-lab/igniter-vm/src/` | `igniter-vm/src/` | VM candidate source. |
| `igniter/igniter-lab/igniter-vm/tests/` | `igniter-vm/tests/` | VM tests. |
| `igniter/igniter-lab/igniter-runtime/lib/` | `igniter-runtime/lib/` | Runtime playground source. |
| `igniter/igniter-lab/igniter-runtime/examples/` | `igniter-runtime/examples/` | Proof/example runners if current. |
| `igniter/igniter-lab/igniter-stdlib/src/`, `stdlib/`, `proofs/` | `igniter-stdlib/` | Experimental stdlib source/proofs. |
| `igniter/igniter-lab/igniter-ide/src/`, `src-tauri/src/`, config files | `igniter-ide/` | IDE source, not build/node_modules. |
| `igniter/igniter-lab/igniter-view-engine/lib/`, `fixtures/`, proof runners | `igniter-view-engine/` | View Framework lab source and fixtures. |
| `igniter/igniter-lab/igniter-gui-engine/lib/`, `fixtures/`, proof runners | `igniter-gui-engine/` | Native GUI lab source and fixtures. |
| `igniter/igniter-lab/igniter-design-system/` | `igniter-design-system/` | Lab design system source/assets. |
| `igniter/igniter-lab/igniter-tbackend/src/`, `docs/`, `data/` | `igniter-tbackend/` | Experimental tbackend lab source. |
| `igniter/igniter-lab/igniter-apps/` | `igniter-apps/` | Only app source, not generated/build output. |

## Bring Selectively

| Source | Target | Rule |
| --- | --- | --- |
| `igniter/igniter-lab/*/Cargo.toml`, lockfiles, package configs | package roots | Bring only if needed to build. |
| `igniter/igniter-lab/igniter-ide/package.json`, lock/config files | `igniter-ide/` | Bring package metadata but not `node_modules` or build output. |
| `igniter/igniter-lab/igniter-jetbrains-plugin/src/`, Gradle config | maybe later | Defer unless plugin remains active. |
| `igniter/igniter-lab/acts-as-tbackend/` | maybe later | Defer unless active. |
| `igniter/igniter-lab/igniter-site/` | maybe later | Defer unless active. |
| `igniter/igniter-lab/igniter-machine/` | maybe later | Defer until ownership clear. |

## Exclude From Living Repo

| Source | Disposition |
| --- | --- |
| any `target/`, `node_modules/`, `.svelte-kit/`, `build/`, `.gradle/`, `.idea/` | exclude. |
| any `out/`, `.igapp`, generated JSON summaries, receipts, logs | archive only if specifically useful; exclude by default. |
| nested `.git/` directories | do not copy into target repo content. |
| accidental local path directories copied from a developer machine | exclude. |
| stale lab docs/cards no longer tied to active work | archive/quarantine. |

## Docs / Agents Placement

| Surface | Rule |
| --- | --- |
| `.agents/` | Dispatch instructions, return packets, next-agent cards, and current-card scratch pointers. |
| `lab-docs/` | Durable design reports, proof outcomes, architecture notes, pressure packages, status, and roadmap. |
| `igniter-site/` | Later generated documentation/tutorial site stub; do not build the site in this transfer slice. |

## Physical Transfer Readiness

The code package transfer is mostly complete. The remaining readiness work is
documentation closure:

- compact `.agents` index;
- compact `lab-docs` index/status/roadmap;
- keep `igniter-site` as a stub for later generated docs/tutorial work;
- keep lab-only/no-canon wording visible;
- run path and claim hygiene scans before the docs/agents commit.
