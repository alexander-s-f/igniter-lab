# LAB-PROVENANCE-BRIDGE-P6 - wire admitted package artifact digest into experiment provenance

Status: CLOSED - readiness packet
Lane: package trust / experiment runner / hygiene
Type: implementation if small; otherwise readiness with exact blocker
Delegation code: OPUS-PROVENANCE-BRIDGE-P6
Date: 2026-06-22
Skill: idd-agent-protocol

## Context

Gemini drift forensics found a real provenance gap:

```text
lang/igniter-vm/src/experiment.rs currently passes None as artifact_digest in build_provenance_json(...)
```

Package admission now has `.igpkg` / artifact identity work. Experiments should not silently drop that
identity when it exists.

This is not a registry/signing/deploy card. It is only the local bridge from an already admitted package
artifact digest to the experiment runner's `provenance.json`.

## Goal

Determine whether the experiment runner already receives admitted package artifact identity. If yes, wire it
into provenance. If no, produce the smallest exact readiness packet naming the missing seam and the next
implementation card.

## Verify first

From `igniter-lab`:

```text
rg -n "artifact_digest|build_provenance_json|provenance" lang/igniter-vm/src lang/igniter-vm/tests lang/igniter-compiler/src
rg -n "admit|verify_archive|igpkg|manifest.digest|artifact_digest" lang/igniter-compiler/src lang/igniter-compiler/tests
```

Also identify the CLI/runner path that produces experiment outputs today.

## Preferred implementation if the seam is already present

- Thread an optional artifact digest through the existing experiment runner config/args path.
- Preserve current behavior for non-package experiments (`artifact_digest: null`).
- Add one test proving:
  - unpacked/plain source experiment still emits `artifact_digest: null`;
  - package/admitted source experiment emits the expected digest.

## If implementation is not small

Write a proof/readiness doc under `lab-docs/lang/` with:

- exact current runner entrypoint;
- exact package-admission output that should carry digest;
- why the seam is not currently connected;
- smallest next implementation card.

## Closed surfaces

- No registry, signing, networking, remote node admission, or deploy semantics.
- No change to digest algorithm.
- No package trust overclaim: this only copies identity into provenance when the identity is already available.
- No changes outside `lang/igniter-vm` / package helper tests unless verify-first proves a narrower source.

## Acceptance

- [x] Current `None` / null path is verified live.
- [x] Either artifact digest is wired with tests, or an exact blocker packet is written.
- [x] Plain experiments remain backward compatible.
- [x] Package/admitted experiments do not fabricate a digest; digest must come from verified/admitted metadata.
- [x] `git diff --check` clean.

## Closing report

Closed as readiness, not implementation.

Artifact:

- `lab-docs/lang/lab-provenance-bridge-p6-v0.md`

Decision:

- The VM provenance schema already accepts optional `artifact_digest`.
- The package admission receipt already emits `artifact_digest`.
- The current experiment runner does not receive admitted package identity: it
  only accepts plain `--kernel` source plus compiler/out/config/entry paths.
- Wiring a raw digest flag would be fabricable and would violate the package
  trust boundary. The next implementation must add an admitted-package runner
  input that binds the executed kernel to verified/admitted metadata.

Evidence:

```text
rg -n "artifact_digest|build_provenance_json|provenance" lang/igniter-vm/src lang/igniter-vm/tests lang/igniter-compiler/src
rg -n "admit|verify_archive|igpkg|manifest.digest|artifact_digest" lang/igniter-compiler/src lang/igniter-compiler/tests
cargo test provenance_json_shape_is_stable --lib
cargo test --test package_lockfile_cli_tests cli_admit_clean_accepted -- --nocapture
git diff --check
```

Results:

- `cargo test provenance_json_shape_is_stable --lib`: 1 passed.
- `cargo test --test package_lockfile_cli_tests cli_admit_clean_accepted -- --nocapture`: 1 passed.
- `git diff --check`: clean.
