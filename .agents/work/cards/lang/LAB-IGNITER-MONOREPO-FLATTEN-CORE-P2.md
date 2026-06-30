# LAB-IGNITER-MONOREPO-FLATTEN-CORE-P2 — move core crates to root so mirrors and monorepo share one flat plane

Status: DONE
Lane: distribution / repository split / core DX
Type: implementation / structural migration
Delegation code: OPUS-IGNITER-MONOREPO-FLATTEN-CORE-P2
Date: 2026-06-30
Skill: idd-agent-protocol

## Context

P1 (`LAB-IGNITER-MIRROR-CRATE-LINKING-READINESS-P1`) verified that the current
subtree mirrors are useful but path linking is uneven:

- `igniter-vm -> igniter-stdlib` works in a flat sibling checkout because both
  were siblings under `lang/` and the dep is `../igniter-stdlib`.
- `igniter-machine -> igniter-tbackend` works because both were siblings under
  `runtime/` and the dep is `../igniter-tbackend`.
- `igniter-machine -> igniter-compiler/vm` does **not** work in a flat mirror
  plane because those deps are `../../lang/...`.
- `.cargo/config.toml paths` cannot rescue a missing declared path; Cargo tries
  to load the declared path first.

The clean structural answer is to make core crates flat **inside the monorepo**
too. Then the monorepo source-of-truth and team-facing mirror checkout have the
same relative shape.

Desired root shape:

```text
igniter-lab/
  igniter-stdlib/
  igniter-compiler/
  igniter-vm/
  igniter-machine/
  igniter-tbackend/
  lang/                 # only non-core language/lab material if anything remains
  runtime/              # only non-core runtime/lab material if anything remains
  frame-ui/
  server/
  lab-docs/
  .agents/
```

Core is one flat plane. Lab, experiments, frame-ui, server, home-lab,
emergence, demos, and product apps remain derivative layers.

## Goal

Perform a one-time structural migration:

1. `git mv` the five Rust core crates to the root of `igniter-lab`.
2. Update path dependencies so core-to-core deps are `../<crate>`.
3. Update mirror push helper prefixes.
4. Update docs/readmes/scripts/tests that reference old paths.
5. Prove the whole lab graph still builds/tests enough for this migration.
6. Prove subtree mirrors still split cleanly and the flat core checkout no
   longer needs link/shim machinery for core deps.

No behavior changes. No dependency policy changes. No registry/semver/git-dep
policy. This is purely a directory topology migration.

## Verify first

Read P1 packet first:

- `lab-docs/lang/lab-igniter-mirror-crate-linking-readiness-p1-v0.md`

Then verify live state:

- `git status --short --branch`
- `find lang runtime -maxdepth 2 -name Cargo.toml -print`
- `rg '(lang|runtime)/(igniter-stdlib|igniter-compiler|igniter-vm|igniter-machine|igniter-tbackend)'`
- `rg '../../lang|../../runtime|../igniter-tbackend|../igniter-stdlib' --glob Cargo.toml`
- `ls bin/push-*-mirror`

Live code wins over P1 if it has drifted.

## Move plan

Use `git mv`, not copy/delete:

```sh
git mv lang/igniter-stdlib igniter-stdlib
git mv lang/igniter-compiler igniter-compiler
git mv lang/igniter-vm igniter-vm
git mv runtime/igniter-machine igniter-machine
git mv runtime/igniter-tbackend igniter-tbackend
```

If `lang/` or `runtime/` become empty, remove them only if no non-core files
remain. Do not move `runtime/acts-as-tbackend`; it is a Ruby adapter mirror and
can stay in `runtime/` unless live verification proves moving it is necessary.

## Expected path edits

P1 measured the likely path-dep edits. Re-verify and update the exact current
set before editing.

Expected `Cargo.toml` changes:

### `igniter-vm/Cargo.toml`

Probably unchanged:

```toml
igniter_stdlib = { path = "../igniter-stdlib" }
```

### `igniter-machine/Cargo.toml`

Expected core deps:

```toml
igniter_compiler = { path = "../igniter-compiler" }
igniter_vm = { path = "../igniter-vm" }
igniter_tbackend_playground = { path = "../igniter-tbackend", default-features = false }
```

Expected dev-deps become:

```toml
igniter_console = { path = "../frame-ui/igniter-console" }
igniter_ui_kit = { path = "../frame-ui/igniter-ui-kit" }
```

Note: this does **not** solve the frame-ui dev-dep layering issue for a pure
core checkout. It only keeps the monorepo build working after the move. The
layering issue remains for P3.

### Dependent non-core crates

Update all old core paths in:

- `server/igniter-web/Cargo.toml`
- `server/igniter-server/Cargo.toml`
- `ide/igniter-ide/src-tauri/Cargo.toml`
- `frame-ui/igniter-frame/Cargo.toml`
- any other live `Cargo.toml` found by `rg`

Expected examples:

```toml
../../lang/igniter-compiler      -> ../../igniter-compiler
../../lang/igniter-vm            -> ../../igniter-vm
../../runtime/igniter-machine    -> ../../igniter-machine
../../runtime/igniter-tbackend   -> ../../igniter-tbackend
../../../lang/igniter-compiler   -> ../../../igniter-compiler
../../../lang/igniter-vm         -> ../../../igniter-vm
../../../runtime/igniter-machine -> ../../../igniter-machine
```

## Mirror helper edits

Update helper prefixes:

- `bin/push-igniter-stdlib-mirror`: `lang/igniter-stdlib` -> `igniter-stdlib`
- `bin/push-igniter-compiler-mirror`: `lang/igniter-compiler` -> `igniter-compiler`
- `bin/push-igniter-vm-mirror`: `lang/igniter-vm` -> `igniter-vm`
- `bin/push-igniter-machine-mirror`: `runtime/igniter-machine` -> `igniter-machine`
- `bin/push-tbackend-mirror`: `runtime/igniter-tbackend` -> `igniter-tbackend`

Run each helper with `--help` after editing.

Do **not** push mirrors during this card unless explicitly asked. This card is
about the monorepo topology. The mirror push can happen as a follow-up once the
migration is green.

## Docs / reference edits

Update path references that would mislead agents or users after the move.
At minimum search and update:

```sh
rg 'lang/igniter-(stdlib|compiler|vm)|runtime/igniter-(machine|tbackend)|runtime/igniter-tbackend'
```

Be conservative:

- update current docs, README, helper text, IMPLEMENTED_SURFACE docs, scripts,
  and cards that are operationally relevant;
- avoid churn in old historical proof docs unless they are front-door docs or
  active instructions;
- if a historical doc intentionally references the old path, leave it and note
  it in the closing report.

## Verification matrix

Run a bounded but serious verification. Minimum:

```sh
git diff --check

(cd igniter-stdlib && cargo test)
(cd igniter-compiler && cargo test)
(cd igniter-vm && cargo test)
(cd igniter-tbackend && cargo test)
(cd igniter-machine && cargo test --no-default-features)
```

Also run at least one graph-level check that catches path breakage outside core.
Pick the strongest feasible command from live repo state:

```sh
cargo test --manifest-path server/igniter-web/Cargo.toml
cargo test --manifest-path server/igniter-server/Cargo.toml
cargo test --manifest-path frame-ui/igniter-frame/Cargo.toml
cargo test --manifest-path ide/igniter-ide/src-tauri/Cargo.toml
```

If full `igniter-machine cargo test` still has the known
`wire_atomic_gate_tests::plain_run_write_effect_doubles_under_forced_interleave`
default-feature drift, do not hide it. Re-run and report the exact failure. The
minimum required machine proof for this card is `cargo test --no-default-features`
plus a path-resolution/build proof for default if possible.

Finally verify subtree split viability without pushing:

```sh
git subtree split --prefix=igniter-stdlib -b verify-stdlib-split
git subtree split --prefix=igniter-compiler -b verify-compiler-split
git subtree split --prefix=igniter-vm -b verify-vm-split
git subtree split --prefix=igniter-machine -b verify-machine-split
git subtree split --prefix=igniter-tbackend -b verify-tbackend-split
git branch -D verify-stdlib-split verify-compiler-split verify-vm-split verify-machine-split verify-tbackend-split
```

If this is too slow, run at least two representative splits (`igniter-vm` and
`igniter-machine`) and explain why.

## Acceptance

- [x] Five core crates moved to the monorepo root with `git mv`.
- [x] Core-to-core path deps are flat `../<crate>` paths.
- [x] Non-core dependent path deps updated.
- [x] Mirror helper prefixes updated and `--help` works.
- [x] Operational docs/scripts no longer point agents at old active paths.
- [x] Lab/source-of-truth boundary remains clear.
- [x] No registry/semver/git-dep/release-package policy introduced.
- [x] No behavior changes beyond path relocation.
- [x] `git diff --check` clean.
- [x] Core crate test matrix run and reported.
- [x] At least one graph-level non-core path check run and reported.
- [x] Subtree split viability checked and reported.
- [x] Known unrelated/default-feature test drift, if present, reported plainly (did NOT manifest).
- [x] Closing report names exact files/commands.

## Closing report

**Date:** 2026-06-30. Performed in the working tree on `main`; changes **staged, not committed**
(left for review — see "Commit" below). No mirrors pushed (card boundary).

### Moves (`git mv`)

`lang/igniter-stdlib`, `lang/igniter-compiler`, `lang/igniter-vm` → root; `runtime/igniter-machine`,
`runtime/igniter-tbackend` → root. `lang/` retains `igniter-research`; `runtime/` retains
`acts-as-tbackend` (Ruby, not moved per card) — neither dir removed (non-empty). 641 file renames.

### Path edits (more than P1's "11 lines" — P1 only counted `Cargo.toml`; in-crate relative paths also shift one level)

- **Core→core `Cargo.toml`:** `igniter-machine/Cargo.toml` compiler/vm `../../lang/X`→`../X`; frame-ui
  **dev**-deps `../../frame-ui/X`→`../frame-ui/X`. `vm→stdlib` (`../igniter-stdlib`) and
  `machine→tbackend` (`../igniter-tbackend`) unchanged (already same-parent).
- **Non-core→core `Cargo.toml`:** `ide/.../src-tauri` (×3), `server/igniter-web` (×2),
  `server/igniter-server` (×1), `frame-ui/igniter-frame` (×1) — `../../{lang,runtime}/X` /
  `../../../{lang,runtime}/X` → drop the subdir segment.
- **In-crate source (depth shift, the part P1 missed):**
  - `igniter-compiler/src/{stdlib_surface.rs,multifile.rs}` — canon `include_str!`
    `../../../../igniter-lang/...`→`../../../igniter-lang/...` (the cross-repo canon ref).
  - `igniter-machine/tests/*` — `../../frame-ui/igniter-view-engine/...`→`../frame-ui/...` (5 files,
    CWD-relative consts), `relational_queryplan_bridge_tests.rs` `include_str!`
    `../../../lang/igniter-compiler/...`→`../../igniter-compiler/...`, `frame_binding_console_e2e_tests.rs`
    `include_str!` `../../../frame-ui/...`→`../../frame-ui/...`, `machine_tests.rs`
    `CARGO_MANIFEST_DIR + /../../apps/...`→`/../apps/...`. (`capability_io_secrets_tests.rs`
    `../../etc/passwd` left — adversarial input, not a repo path.)
  - `igniter-vm/tests/reactive_tests.rs` — tbackend daemon path: dropped one `.parent()` and
    `runtime/igniter-tbackend/...`→`igniter-tbackend/...` (this failed first; fixed + verified).
- **Mirror helpers:** 5 `PREFIX` edits (`bin/push-*-mirror`); `--help` verified.
- **Front-door docs:** `README.md`, `server/igniter-web/IMPLEMENTED_SURFACE.md`,
  `igniter-{vm,machine}/IMPLEMENTED_SURFACE.md`, `frame-ui/igniter-frame/README.md` — active
  command/source pointers updated. Historical proof docs + the P1/P2 cards' own prose intentionally
  retain old paths (the verified-state record / the move instructions); left per card guidance.

### Verification (all run, this box)

- `cargo test` per core crate: **stdlib / compiler / vm / tbackend → green**
  (vm's `reactive_tests` needed `igniter-tbackend cargo build --release` for the daemon binary; passes).
- `igniter-machine cargo test --no-default-features` → green; **full default `cargo test` → 370 passed,
  0 failed** (the noted `wire_atomic_gate` drift did NOT manifest); `cargo test --no-run` (default)
  compiles the frame-ui dev-dep graph via the new paths.
- Graph-level: `cargo check` green for `server/igniter-web`, `server/igniter-server`,
  `frame-ui/igniter-frame`, `ide/igniter-ide/src-tauri`; `igniter-web` lib (machine) **127 passed**.
- Subtree-split viability (no push): `igniter-stdlib`, `igniter-vm`, `igniter-machine` split cleanly
  (verified via a temp commit on `main`, then `git reset --soft` — no stray commit; changes preserved).
- `git diff --check` (working + staged) clean.

### Curator addendum

After review, the active front-door layer still had several stale root paths
(`README.md`, `MAP.md`, `SEARCH.md`, `bin/igniter`, `bin/igniter-install`,
mirror helper prose, implemented-surface/status docs, and one VM experiment
compiler lookup). Those were updated to the flat root layout. Targeted active
stale-path scan is now clean; `bash -n` passes for `bin/igniter`,
`bin/igniter-install`, and all five mirror helpers; `cargo metadata --no-deps`
resolves for `igniter-compiler`, `igniter-vm`, `igniter-machine`,
`igniter-tbackend`, `server/igniter-web`, `server/igniter-server`,
`frame-ui/igniter-frame`, and `ide/igniter-ide/src-tauri`; `bin/igniter
toolchain list` and `bin/igniter doctor` now report root-level core crate
paths.

### Result

Core crates are one flat plane at the monorepo root; every core→core dep is `../<crate>`, identical in
the monorepo and in a flat mirror checkout — so mirrors are verbatim subtree copies that build flat with
no shim/overlay/`paths` machinery. Monorepo source-of-truth, atomic cross-crate commits, and whole-graph
CI are unchanged. P3 still stands: `igniter-machine`'s frame-ui **dev**-deps remain a non-core layer
edge, so a *pure-core* checkout (machine without frame-ui siblings) is not yet `cargo test`-clean.

### Commit (not done — review first)

Suggested: `git commit -m "Flatten core crates to monorepo root (LAB-IGNITER-MONOREPO-FLATTEN-CORE-P2)"`.
Mirror pushes (`bin/push-*-mirror`) are a separate, separately-authorized follow-up.

## Closed surfaces

- Do not move frame-ui/server/ide/lab-docs/home-lab/emergence/product apps into
  core.
- Do not convert deps to `git = ...`, registry deps, or `[patch]`.
- Do not publish/push mirrors unless separately authorized.
- Do not fix unrelated warnings.
- Do not rewrite old historical docs broadly just to erase old paths.

## Likely follow-up

`LAB-IGNITER-MIRROR-MACHINE-DEVDEP-RECONCILE-P3` — remove or feature-gate
`igniter-machine`'s frame-ui dev-dep from the pure core checkout path, so
`igniter-machine` becomes fully core-plane buildable without non-core siblings.
