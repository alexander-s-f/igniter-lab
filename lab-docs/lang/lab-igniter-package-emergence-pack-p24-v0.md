# lab-igniter-package-emergence-pack-p24-v0

**Card:** `LAB-IGNITER-PACKAGE-EMERGENCE-PACK-P24`  
**Status:** CLOSED (implementation proof)  
**Date:** 2026-06-22

## Summary

Added a test-only Kuramoto package fixture and proved the local package trust loop:

```text
Kuramoto source fixture
  -> package pack .igpkg
  -> package verify
  -> package admit
  -> receipt-like identity with artifact digest / lock digest / toolchain provenance
```

No registry, network, signing, remote host, deployment, or public `igniter-emergence` mutation.

## Implementation

- `lang/igniter-compiler/tests/fixtures/package_emergence_kuramoto/`
  - `igniter.toml`
  - `src/kuramoto_per_omega_tick.ig`
  - `src/local_multinode_node_tick.ig`
- `lang/igniter-compiler/tests/package_lockfile_cli_tests.rs`
  - 6 Kuramoto pack/verify/admit CLI tests
- `lang/igniter-compiler/src/project.rs`
  - archive entry path safety accepts `"."`, needed for this package archive shape

The fixture mirrors the public emergence reference shape while staying lab-local. The per-omega tick keeps
`Collection[Float]` output so the external driver owns re-pairing `{theta, omega}` between ticks.

## Verification

```text
cd lang/igniter-compiler
cargo test --test package_lockfile_cli_tests kuramoto -- --test-threads=1
=> 6 passed

git diff --check
=> clean
```

Covered:

- pack `.igpkg`;
- verify archive success;
- admit success with deterministic receipt-like identity;
- repeated admission stability;
- tampered archive refusal (`digest_mismatch`);
- `--require-lock` missing-lock refusal and locked success;
- toolchain drift refusal.

## Closed Scope

No package registry, semver resolver, remote node runtime, public repo release automation, networking, signing,
or scientific result changes.

## Next

Use the admitted artifact identity in experiment-runner provenance, once `LAB-IGNITER-EXPERIMENT-RUNNER-PROVENANCE-P9`
is closed cleanly.
