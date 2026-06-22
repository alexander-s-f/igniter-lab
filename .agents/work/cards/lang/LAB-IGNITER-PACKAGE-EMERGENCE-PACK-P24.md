# LAB-IGNITER-PACKAGE-EMERGENCE-PACK-P24 - package-admit a Kuramoto kernel

Status: CLOSED
Lane: package / emergence / remote trust
Type: implementation proof
Delegation code: OPUS-IGNITER-PACKAGE-EMERGENCE-PACK-P24
Date: 2026-06-22
Skill: idd-agent-protocol

## Context

Depends on:

- `LAB-IGNITER-PACKAGE-REMOTE-TRUST-P23` - local node admission is closed.
- `LAB-IGNITER-PACKAGE-ARCHIVE-PACK-VERIFY-P22` - `.igpkg` pack/verify is live.
- `EMERGENCE-KURAMOTO-PUBLIC-SEED-P1` - public Kuramoto kernels now live in `igniter-emergence`.

The remote-node story needs one concrete science artifact that can be packed, verified, and admitted before execution. Kuramoto is the right first artifact because it already pressures deterministic math and future distributed execution.

## Goal

Prove the smallest package trust loop for an emergence kernel:

```text
Kuramoto source package
  -> pack .igpkg
  -> verify archive
  -> admit archive as a node would
  -> receipt-like output includes artifact digest, lock digest, compiler version, stdlib version
```

No networking. No registry. No signing. No deployment.

## Verify first

Read live code/docs:

- `lab-docs/lang/lab-igniter-package-remote-trust-readiness-p22-v0.md`
- `lab-docs/lang/lab-igniter-package-archive-pack-verify-p22-v0.md`
- `lang/igniter-compiler/src/project.rs`
- `lang/igniter-compiler/src/main.rs`
- package archive/admission tests
- `/Users/alex/dev/projects/igniter-workspace/igniter-emergence/kernels/*.ig`

Confirm whether the public `igniter-emergence` repo already has enough package metadata. If not, create a test-only fixture in `igniter-lab`; do not mutate `igniter-emergence` unless the card genuinely needs it.

## Recommended shape

Prefer a lab fixture that mirrors the public kernel package:

```text
lang/igniter-compiler/tests/fixtures/package_emergence_kuramoto/
  igniter.toml
  src/kuramoto_per_omega_tick.ig
  src/local_multinode_node_tick.ig
```

Then add CLI/API tests that pack and admit the fixture.

## Acceptance

- [x] A Kuramoto package fixture packs into `.igpkg`.
- [x] `verify_archive` succeeds.
- [x] node admission succeeds and emits deterministic receipt-like identity.
- [x] Artifact digest and lock digest are stable across repeat pack/admit.
- [x] Tampered archive is refused.
- [x] Stale lock or missing required lock is refused if the P23 policy supports it.
- [x] Toolchain drift refusal remains covered or explicitly reused from P23.
- [x] No registry, network, signing, remote host, or deployment.
- [x] Existing package suite remains green.
- [x] `git diff --check` clean.

## Closed scope

No package registry, no semver resolver, no remote node runtime, no public repo release automation, no scientific result changes.

## Next

Use the admitted artifact identity in experiment-runner provenance so a Kuramoto result can say exactly which verified package produced it.

## Closing report

Implemented a lab-local Kuramoto package fixture and proved the trust loop:

```text
Kuramoto fixture -> pack .igpkg -> verify -> admit -> deterministic receipt-like identity
```

Changed surfaces:

- `tests/fixtures/package_emergence_kuramoto/` fixture with `kuramoto_per_omega_tick.ig` and `local_multinode_node_tick.ig`.
- `package_lockfile_cli_tests.rs` adds 6 Kuramoto CLI tests.
- `project.rs` allows archive entry path `"."` in safe-entry validation.

Verification:

```text
cargo test --test package_lockfile_cli_tests kuramoto -- --test-threads=1 -> 6 passed
git diff --check -> clean
```

Covered pack, verify, admit, repeat stability, tamper refusal, missing-lock refusal, locked success, and
toolchain-drift refusal. No registry/network/signing/deployment. Proof doc:
`lab-docs/lang/lab-igniter-package-emergence-pack-p24-v0.md`.
