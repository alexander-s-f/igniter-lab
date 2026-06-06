# igniter-lab Value Transfer Map

Status: rough value-positive map / frontier only / no physical transfer yet
Date: 2026-06-06

## Principle

This repo should receive the frontier playground that helps the language and
framework discover future directions. It must not become canonical language
authority by accident. Bring working lab source and compact lab docs; leave
generated outputs and dependency/build directories behind.

Path notation:
- source paths are relative to `projects/`
- target paths are relative to `igniter-workspace/`

## Bring First

| Source | Target | Why |
| --- | --- | --- |
| `igniter/playgrounds/igniter-lab/README.md` if present | `igniter-workspace/igniter-lab/README.md` | Lab identity and warning banner. |
| `igniter/playgrounds/igniter-lab/.agents/` | `.agents/` | Lab handoff cards, but prune stale/redundant cards later. |
| `igniter/playgrounds/igniter-lab/lab-docs/` | `lab-docs/` | Frontier docs and proof summaries, compacted as needed. |
| `igniter/playgrounds/igniter-lab/igniter-compiler/src/` | `igniter-compiler/src/` | Lab compiler source. |
| `igniter/playgrounds/igniter-lab/igniter-compiler/fixtures/` | `igniter-compiler/fixtures/` | Source fixtures for proofs. |
| `igniter/playgrounds/igniter-lab/igniter-compiler/proofs/` | `igniter-compiler/proofs/` | Proof runners, not generated outputs. |
| `igniter/playgrounds/igniter-lab/igniter-vm/src/` | `igniter-vm/src/` | VM candidate source. |
| `igniter/playgrounds/igniter-lab/igniter-vm/tests/` | `igniter-vm/tests/` | VM tests. |
| `igniter/playgrounds/igniter-lab/igniter-runtime/lib/` | `igniter-runtime/lib/` | Runtime playground source. |
| `igniter/playgrounds/igniter-lab/igniter-runtime/examples/` | `igniter-runtime/examples/` | Proof/example runners if current. |
| `igniter/playgrounds/igniter-lab/igniter-stdlib/src/`, `stdlib/`, `proofs/` | `igniter-stdlib/` | Experimental stdlib source/proofs. |
| `igniter/playgrounds/igniter-lab/igniter-ide/src/`, `src-tauri/src/`, config files | `igniter-ide/` | IDE source, not build/node_modules. |
| `igniter/playgrounds/igniter-lab/igniter-view-engine/lib/`, `fixtures/`, proof runners | `igniter-view-engine/` | View Framework lab source and fixtures. |
| `igniter/playgrounds/igniter-lab/igniter-gui-engine/lib/`, `fixtures/`, proof runners | `igniter-gui-engine/` | Native GUI lab source and fixtures. |
| `igniter/playgrounds/igniter-lab/igniter-design-system/` | `igniter-design-system/` | Lab design system source/assets. |
| `igniter/playgrounds/igniter-lab/igniter-tbackend/src/`, `docs/`, `data/` | `igniter-tbackend/` | Experimental tbackend lab source. |
| `igniter/playgrounds/igniter-lab/igniter-apps/` | `igniter-apps/` | Only app source, not generated/build output. |

## Bring Selectively

| Source | Target | Rule |
| --- | --- | --- |
| `igniter/playgrounds/igniter-lab/*/Cargo.toml`, lockfiles, package configs | package roots | Bring only if needed to build. |
| `igniter/playgrounds/igniter-lab/igniter-ide/package.json`, lock/config files | `igniter-ide/` | Bring package metadata but not `node_modules` or build output. |
| `igniter/playgrounds/igniter-lab/igniter-jetbrains-plugin/src/`, Gradle config | maybe later | Defer unless plugin remains active. |
| `igniter/playgrounds/igniter-lab/acts-as-tbackend/` | maybe later | Defer unless active. |
| `igniter/playgrounds/igniter-lab/igniter-site/` | maybe later | Defer unless active. |
| `igniter/playgrounds/igniter-lab/igniter-machine/` | maybe later | Defer until ownership clear. |

## Exclude From Living Repo

| Source | Disposition |
| --- | --- |
| any `target/`, `node_modules/`, `.svelte-kit/`, `build/`, `.gradle/`, `.idea/` | exclude. |
| any `out/`, `.igapp`, generated JSON summaries, receipts, logs | archive only if specifically useful; exclude by default. |
| nested `.git/` directories | do not copy into target repo content. |
| accidental local path dirs such as `igniter-ide/Users/` | exclude. |
| stale lab docs/cards no longer tied to active work | archive/quarantine. |

## First Detail Round

Proposed first per-repo card:

```text
Card: LAB-SPLIT-P1
Track: igniter-lab-positive-transfer-detail-v0
Goal: Turn this rough map into a lab copy plan, selecting active packages,
excluding build outputs, and preserving frontier/non-canon wording.
```

## Physical Transfer Readiness

Not ready for physical copy yet.

Required before copy:
- choose active lab packages;
- define `.gitignore` for lab outputs;
- remove `node_modules`, `target`, build dirs, `.idea`, `.DS_Store`, accidental local paths;
- run selected proof/test commands after copy;
- keep lab-only/no-canon wording visible.
