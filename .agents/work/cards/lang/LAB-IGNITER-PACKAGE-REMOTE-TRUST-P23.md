# LAB-IGNITER-PACKAGE-REMOTE-TRUST-P23 — local node-admission proof

Status: OPEN
Lane: package / remote substrate / trust
Type: implementation proof
Delegation code: OPUS-IGNITER-PACKAGE-REMOTE-TRUST-P23
Date: 2026-06-21
Skill: idd-agent-protocol

## Context

Depends on:

- `LAB-IGNITER-PACKAGE-ARCHIVE-PACK-VERIFY-P22` (**P22-archive**) — `.igpkg` source archive pack/verify is live.
- `LAB-IGNITER-PACKAGE-REMOTE-TRUST-READINESS-P22` (**P22-remote**) — trust seam design is closed.
- `LAB-IGNITER-PACKAGE-TRANSITIVE-GRAPH-CI-P15` and earlier package waves — lock, strict integrity, exports,
  transitive graph, compiler/stdlib provenance.
- home-lab remote-node substrate readiness — remote execution is substrate/control-plane/host capability, not
  language syntax or VM magic.

P22-remote decided:

- source `.igpkg` is enough for v0 trust;
- node verifies source locally, then compiles locally;
- node never trusts a foreign `.igapp`;
- transport, node identity, authorization, and admission policy are host/control-plane concerns;
- package layer proves "what code is this" via content + lock + integrity + provenance.

This card implements the smallest local proof of that admission gate. **No networking. No registry. No deploy.**

## Goal

Add a local "node admission" proof for `.igpkg`:

```text
candidate .igpkg
  -> verify content digest
  -> verify assembly integrity
  -> verify lock parity when required
  -> verify compiler/stdlib match when required
  -> emit deterministic receipt-like admission result
```

The result should answer: **would this node accept this package artifact for execution?**

## Verify first

Read live code and docs before editing:

- `lab-docs/lang/lab-igniter-package-archive-pack-verify-p22-v0.md`
- `lab-docs/lang/lab-igniter-package-remote-trust-readiness-p22-v0.md`
- `lang/igniter-compiler/src/project.rs`
- `lang/igniter-compiler/src/main.rs`
- package archive tests and lock/verify tests:
  - `tests/package_lockfile_cli_tests.rs`
  - `tests/package_workspace_tests.rs`
  - any archive pack/verify tests
- `lang/igniter-compiler/src/lib.rs` for compiler version / `STDLIB_VERSION`
- package fixtures used by archive tests

Confirm or correct:

- exact current `pack_archive` manifest fields;
- exact current `verify_archive` JSON shape;
- whether archive manifest already includes `lockfile`, compiler version, stdlib version, digest, closed surfaces;
- whether `verify_archive` can cheaply recompute lock parity on the unpacked temp tree;
- whether toolchain match should be a new CLI flag, a new command, or a field in `verify`.

Live code wins over this card.

## Recommended shape

Prefer a new project-layer function rather than overloading existing behavior:

```rust
admit_archive(path, options) -> Result<Value, ProjectError>
```

where the returned JSON is receipt-like:

```json
{
  "accepted": true,
  "artifact_digest": "sha256:...",
  "lock_digest": "sha256:...",
  "compiler_version": "...",
  "stdlib_version": "...",
  "entry": "...",
  "entry_contract": null,
  "refusals": []
}
```

CLI may be one of:

```text
igc package admit FILE.igpkg --require-lock --match-toolchain
igc package verify FILE.igpkg --admission --require-lock --match-toolchain
```

Choose the smaller live fit. If both are equally easy, prefer `package admit`: it names the future node-runtime
use case without changing plain `verify` semantics.

## Required implementation

### 1. Manifest additions

Add to pack manifest if absent:

- `lock_digest` — digest of packed `igniter.lock` when lockfile exists, else `null`;
- optional `entry_contract` / `entrypoints` only if live pack surface has enough information without inventing a
  new app model. If not feasible, keep it `null` and document why.

Do not add signatures. Keep `signature: null` reserved if it already exists.

### 2. Admission verification

Admission must reuse existing `verify_archive` primitives where possible:

- digest recomputation;
- unpack temp tree;
- `check_workspace_integrity`;
- parse packed manifest.

Then add:

- **lock parity** when `--require-lock` is enabled:
  - packed lock must exist;
  - recomputed lock for unpacked tree must match packed `igniter.lock`;
  - mismatch -> refuse with `stale_lock`;
- **toolchain match** when `--match-toolchain` is enabled:
  - manifest compiler version must equal local compiler package version;
  - manifest stdlib version must equal local `STDLIB_VERSION`;
  - mismatch -> refuse with `toolchain_drift`.

### 3. Refusal taxonomy

At minimum:

- `digest_mismatch`
- `integrity`
- `missing_lock`
- `stale_lock`
- `toolchain_drift`

Each refusal should be structured enough for tests to assert the reason without string scraping. If existing
archive errors exit before JSON can be emitted, either normalize them in `admit_archive` or document why one
class stays as an error.

### 4. Tests

Add focused tests in the compiler crate. Prefer tempdir-based fixtures; do not dirty committed fixtures with
generated locks unless the fixture is meant to include them.

Required cases:

- clean archive admitted;
- same artifact admitted deterministically with same digest/receipt fields;
- tampered byte refused as `digest_mismatch`;
- integrity fault refused as `integrity` with the underlying `OOF-IMP*` visible;
- stale lock refused as `stale_lock`;
- missing lock refused under `--require-lock`;
- toolchain drift refused under `--match-toolchain`;
- plain package verify behavior remains unchanged.

## Acceptance

- [ ] Clean archive -> `accepted: true`.
- [ ] Admission result carries `artifact_digest`, `compiler_version`, `stdlib_version`, and lock identity when present.
- [ ] Same archive yields deterministic admission result.
- [ ] Tampered archive refuses before execution (`digest_mismatch`).
- [ ] Integrity fault refuses with structured `integrity` reason and visible `OOF-IMP*`.
- [ ] Stale lock refuses with `stale_lock`.
- [ ] Missing lock under `--require-lock` refuses with `missing_lock`.
- [ ] Toolchain drift under `--match-toolchain` refuses with `toolchain_drift`.
- [ ] Existing `igc package verify` behavior remains compatible.
- [ ] No network, registry, semver, signing, deploy, Docker, systemd, or home-lab host changes.
- [ ] Proof doc written: `lab-docs/lang/lab-igniter-package-remote-trust-p23-v0.md`.
- [ ] Targeted package tests pass.
- [ ] Full compiler suite or a justified package-focused suite passes.
- [ ] `git diff --check` clean.

## Proof doc requirements

The proof doc must include:

- exact CLI/API chosen (`admit` vs `verify --admission`) and why;
- final manifest delta (`lock_digest`, `entry_contract` decision);
- admission result JSON shape;
- refusal taxonomy table;
- exact tests and counts;
- what remains future: signatures, registry, semver, remote transport, node identity, real execution receipts.

## Closed scope

- No remote network calls.
- No registry or semver solver.
- No signatures or key management.
- No compiled `.igapp` trust path.
- No deployment or home-lab node changes.
- No new language or VM semantics.
- No execution of the admitted package.

## Next

After this proof, the package layer can hand a deterministic `{accepted, artifact_digest, ...}` result to:

- `LAB-IGNITER-REMOTE-NODE-MOCK-TRANSPORT-P*` — transport/admission without real network;
- `LAB-IGNITER-EMERGENCE-LOCAL-MULTINODE-SIM-P*` — every simulated node runs the same admitted `NodeTick`
  artifact;
- later signed-package / registry waves.
