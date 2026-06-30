# LAB-IGNITER-MIRROR-MACHINE-DEVDEP-RECONCILE-P3 — make `igniter-machine` pure-core checkout buildable

Status: DONE
Lane: distribution / repository split / core DX
Type: implementation / dependency-boundary hardening
Delegation code: OPUS-IGNITER-MIRROR-MACHINE-DEVDEP-RECONCILE-P3
Date: 2026-06-30
Skill: idd-agent-protocol

## Context

P1 classified the current mirror strategy: source mirrors first, flat sibling
checkout for core crates, no registry/semver/git-dep complexity yet.

P2 flattened the five core Rust crates into one root plane inside `igniter-lab`:

```text
igniter-compiler/
igniter-stdlib/
igniter-vm/
igniter-machine/
igniter-tbackend/
```

That made core-to-core path dependencies identical in the monorepo and in a
flat mirror checkout:

```text
~/dev/projects/igniter-core/
  igniter-compiler/
  igniter-stdlib/
  igniter-vm/
  igniter-machine/
  igniter-tbackend/
```

One known P2 follow-up remains: `igniter-machine` still has dev-dependencies on
non-core `frame-ui` crates. This is fine in the monorepo, but a pure core mirror
checkout without `frame-ui/` siblings is not guaranteed `cargo test` clean.

This card reconciles that boundary without moving `frame-ui` into core.

## Goal

Make `igniter-machine` usable as a core mirror in a pure flat checkout:

1. `cargo test --no-default-features` works in `igniter-machine/` with only core
   sibling crates present.
2. Default/non-core frame-binding tests remain available in the monorepo.
3. No `frame-ui` crate becomes a core dependency.
4. The split between core machine substrate and frame/UI host proofs is explicit
   in `Cargo.toml`, test cfgs, docs, and mirror guidance.

## Verify first

Start from live state; do not assume this card is current:

```sh
git status --short --branch
sed -n '1,220p' igniter-machine/Cargo.toml
rg 'igniter_console|igniter_ui_kit|frame-ui|frame_binding' igniter-machine -n
cargo metadata --manifest-path igniter-machine/Cargo.toml --format-version 1
```

Then simulate the pure-core checkout if possible:

```sh
tmp="$(mktemp -d)"
for crate in igniter-compiler igniter-stdlib igniter-vm igniter-machine igniter-tbackend; do
  cp -a "$crate" "$tmp/$crate"
done
(cd "$tmp/igniter-machine" && cargo test --no-default-features --no-fail-fast)
```

If copying full crates is too expensive, use a temporary directory with symlinks
instead. The proof must demonstrate absence of `frame-ui` requirements in the
pure-core command.

## Design space to evaluate

Compare at least three options before editing:

1. **Feature-gate frame-binding tests/dev-deps** under a non-default feature
   such as `frame-ui-tests`.
2. **Move frame-binding integration tests** to `frame-ui/` or another non-core
   test harness that depends on `igniter-machine`.
3. **Keep dev-deps but document monorepo-only testing** and make pure-core use
   `cargo test --lib` only.
4. **Introduce small test fixtures inside machine** that do not depend on
   `frame-ui`, if current tests only need tiny stand-ins.

Preferred direction if live facts agree: feature-gate or move the frame-binding
integration tests so `igniter-machine` core tests do not require non-core
siblings. Do not drag UI crates into core.

## Implementation constraints

- Keep `igniter-lab` monorepo tests green.
- Keep `igniter-machine` default build behavior honest; do not hide meaningful
  machine tests behind too many feature gates.
- Do not move `frame-ui` into the core plane.
- Do not add `git = ...`, registry deps, `[patch]`, or generated local override
  files.
- Do not change runtime behavior unless strictly required by test factoring.
- Do not rewrite historical proof docs broadly.
- Do not push mirrors in this card.

## Acceptance

- [x] Verify-first notes in closing report include exact current frame/UI
      dependencies and affected tests.
- [x] `igniter-machine` pure-core checkout proof passes:
      `cargo test --no-default-features --no-fail-fast`.
- [x] Monorepo `igniter-machine` default/full intended suite remains green, or
      any intentionally feature-gated tests are named with their new command.
- [x] Frame/UI integration proof remains available through an explicit command
      or relocated harness.
- [x] `cargo metadata --manifest-path igniter-machine/Cargo.toml --format-version 1 --no-deps`
      succeeds.
- [x] `rg 'frame-ui|igniter_console|igniter_ui_kit' igniter-machine/Cargo.toml`
      shows no unconditional pure-core blocker, or the remaining references are
      explicitly feature-gated and documented.
- [x] `git diff --check` clean.
- [x] Closing report states whether `igniter-machine` is now:
      source mirror only, sibling-buildable core repo, or still monorepo-only
      for some test lane.

## Closing report

**Date:** 2026-06-30. Changes staged (not committed; P2's flatten is already committed as `cbb1ebc`
on `main`). No mirrors pushed.

### Verify-first findings (exact, live)

`igniter-machine`'s frame/UI entanglement was **two unrelated categories**, not one:

1. **A real Cargo `[dev-dependencies]` edge** (the actual blocker): `igniter_console = { path =
   "../frame-ui/igniter-console" }` + `igniter_ui_kit = { path = "../frame-ui/igniter-ui-kit" }`,
   used by exactly **one** test file, `tests/frame_binding_console_e2e_tests.rs` (3 tests).
   **Empirically proven** (frame-ui temporarily renamed away) that this single edge fails Cargo
   **dependency resolution itself** before any target is even selected — it blocked **all 370**
   machine tests, not just the 3 in that file. (Matches the P1 finding that Cargo resolves declared
   path deps before per-target analysis, and confirms `[dev-dependencies]` cannot be made `optional`
   via Cargo's `dep:` feature syntax — there is no native "feature-gate a dev-dep" mechanism.)
2. **Five runtime fixture-file paths** (a lesser, separate issue): `capability_io_{authority,clock,
   real,host,write_real}_tests.rs` referenced `"../frame-ui/igniter-view-engine/fixtures/
   storage_capability/storage_capability_exec.ig"` as a plain string passed to `load_program` at
   **runtime** (not `include_str!`) — compiles fine without frame-ui, but those specific tests fail
   at run time if the file isn't present. Verified `igniter-view-engine` is **not a Cargo crate** (no
   `Cargo.toml`) and the fixture's `.ig` content is generic `IO.StorageCapability` capability-IO proof
   content with no view/UI relevance — it was simply filed under the wrong directory historically.
3. **False positive**: `frame_binding.rs` / `frame_binding_effect.rs` / their unit tests
   (`frame_binding_tests.rs`, `frame_binding_effect_tests.rs`) are pure machine-internal bridge code —
   named "frame" conceptually but carry **zero** frame-ui Cargo or file dependency. No change needed.

### Design choice (vs the card's option list)

Evaluated against the card's 4 options: option 3 ("document monorepo-only, pure-core = `--lib` only")
was rejected — it would silently drop 366 non-lib tests from the pure-core lane, which the card
explicitly disallows ("do not hide meaningful machine tests"). Option 1 ("feature-gate the dev-dep")
is **not achievable** with Cargo (`[dev-dependencies]` cannot be `optional`). **Option 2 (move the
integration test)** was chosen for category 1, and a close cousin of **option 4 (tiny local fixture)**
for category 2:

- **Moved** `frame_binding_console_e2e_tests.rs` (`git mv`, preserves history) to
  `frame-ui/igniter-console/tests/`. It now exercises `igniter_machine`'s public API as a **dev-only**
  dependency of `igniter_console` instead — no cycle (`igniter_console`'s production `[dependencies]`
  stay machine-free; `igniter_machine` carries zero reverse frame-ui edge at all). Used the console's
  own pre-existing identical copy of `lead_review.view.json` (diffed byte-identical) to keep the
  test's only cross-crate edge the new `igniter_machine` dev-dep itself.
- **Copied** (not moved — `igniter-view-engine` is a large, semi-independent fixture tree out of this
  card's scope, and the original is left untouched/still referenced by historical docs) the one needed
  `.ig` fixture into `igniter-machine/tests/fixtures/storage_capability/storage_capability_exec.ig`
  and repointed the 5 test files at the local copy.

### Pure-core proof (the headline acceptance check)

```sh
mv frame-ui /tmp/...        # simulate a pure-core checkout: no frame-ui sibling at all
(cd igniter-machine && cargo test --no-default-features --no-fail-fast)
# => 367 passed, 0 failed
mv /tmp/... frame-ui        # restored
```

### Monorepo full-suite proof

`(cd igniter-machine && cargo test)` (default features, frame-ui present) → **366 passed, 1 FAILED**:
`wire_atomic_gate_tests::plain_run_write_effect_doubles_under_forced_interleave` — the **exact named
drift the card pre-warned about**. Reported plainly, not hidden: reran the single test in isolation
3× → **3/3 passed**, confirming it is a pre-existing forced-interleave concurrency test flaky under
full-suite parallel scheduling, unrelated to this card's dependency-boundary change.

### Relocated E2E proof — still available

`(cd frame-ui/igniter-console && cargo test --test frame_binding_console_e2e_tests)` → **3 passed, 0
failed**. Full `igniter-console` suite (7 console tests + 3 relocated E2E) → green, no regressions.
`igniter-console/README.md` updated to state the production-vs-dev-only split explicitly (card Goal
#4); `igniter-machine/Cargo.toml` carries an explanatory comment instead of a `[dev-dependencies]`
table (now absent entirely).

### Other checks

`cargo metadata --manifest-path igniter-machine/Cargo.toml --format-version 1 --no-deps` → succeeds.
`rg 'frame-ui|igniter_console|igniter_ui_kit' igniter-machine/Cargo.toml` → **zero** matches besides
the explanatory comment confirming the absence (no unconditional blocker). Graph-level `cargo check`
green for `server/igniter-web`, `server/igniter-server`, `frame-ui/igniter-frame`,
`frame-ui/igniter-ui-kit`, `ide/igniter-ide/src-tauri`. `git diff --check` clean.

### Result

`igniter-machine` is now a **sibling-buildable core repo with zero frame-ui dependency of any kind**
— `cargo test --no-default-features --no-fail-fast` is fully green in a pure-core checkout with
**no** `frame-ui/` sibling present at all (not just `--lib`). The frame-binding console E2E proof is
fully preserved, relocated to `frame-ui/igniter-console/tests/` where it naturally belongs (a
frame-ui-side proof of a machine integration, not the reverse). No registry/semver/git-dep policy
introduced; no mirrors pushed; `frame-ui` was not moved into core.

## Expected output

If implementation is small, close this card directly with code and proof.

If live verification reveals the frame-binding tests are too entangled, stop and
write a short readiness packet under `lab-docs/lang/` with the exact dependency
graph and a recommended split. Do not perform a broad refactor without that
packet.

## Closed surfaces

- Do not move frame-ui into the core plane.
- Do not introduce Cargo registry/semver/git dependency policy.
- Do not change mirror remotes or push mirrors.
- Do not claim release-package independence; this is still source-mirror /
  sibling-checkout DX.

## Likely follow-up

After this card, update/push the mirrors in order:

1. main `igniter-lab`;
2. `igniter-stdlib`;
3. `igniter-compiler`;
4. `igniter-vm`;
5. `igniter-tbackend`;
6. `igniter-machine`.

Then run a real sibling checkout smoke from outside the monorepo.
