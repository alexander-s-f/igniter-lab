# lab-igniter-package-remote-trust-p23-v0 — local node-admission proof

**Card:** `LAB-IGNITER-PACKAGE-REMOTE-TRUST-P23` · **Delegation:** `OPUS-IGNITER-PACKAGE-REMOTE-TRUST-P23`
**Status:** CLOSED (lab implementation-proof) — `igc package admit` answers, locally and deterministically,
**"would this node accept this `.igpkg` for execution?"** — reusing the `verify_archive` digest + integrity
primitives, adding optional **lock parity** and **toolchain match**, and emitting a receipt-like result with a
structured `refusals` list. **`project.rs` + `main.rs` + tests — no networking, no registry, no signing, no
deploy, no execution of the package.**

## CLI / API chosen — `igc package admit` (not `verify --admission`)

`igc package admit FILE.igpkg [--require-lock] [--match-toolchain]`, backed by
`pub fn admit_archive(path, require_lock, match_toolchain) -> Result<Value, ProjectError>`. Chosen over
`verify --admission` because it **names the future node-runtime use case** without changing plain
`package verify` semantics (which stay exactly as P22). Exit 0 if `accepted`, exit 1 if refused/malformed.

## Manifest delta

- **`lock_digest`** — `sha256` of the packed `igniter.lock` when present, else `null` (explicit provenance for
  receipts/lineage; the lock is also inside the tree digest).
- **`entry_contract`** — `null`, **documented**: the entry *package* is known, but an entry *contract* (e.g.
  `NodeTick`) needs an app model the compiler does not track at pack time — not invented.
- `signature` stays `null` (reserved, unimplemented).

## Admission flow (reuses verify primitives)

`unpack_archive` (extracted, shared with `verify_archive` — behavior-preserving refactor; now uses an atomic
per-call temp dir, fixing a latent parallel-test race) → digest check → `check_workspace_integrity` → then:
- **lock parity** (`--require-lock`): packed lock must exist (else `missing_lock`); recompute `workspace_lock`
  on the unpacked tree and `verify_lock` against the packed lock — any **content** drift (Changed/New/Missing;
  toolchain drift excluded — that is a separate refusal) → `stale_lock`.
- **toolchain match** (`--match-toolchain`): `manifest.compiler_version`/`stdlib_version` must equal this
  node's `env!("CARGO_PKG_VERSION")` / `crate::STDLIB_VERSION` → else `toolchain_drift`.

`accepted = refusals.is_empty()`.

## Admission result (live)

```json
{
  "kind": "igniter_package_admission",
  "accepted": true,
  "artifact_digest": "sha256:d753a3a7…",
  "lock_digest": "sha256:4c23ea9f…",
  "compiler_version": "0.1.0",
  "stdlib_version": "0.1.x",
  "entry": "app",
  "entry_contract": null,
  "refusals": []
}
```

## Refusal taxonomy

| reason | trigger | detail |
|---|---|---|
| `digest_mismatch` | recomputed per-file/tree digest ≠ manifest | — |
| `integrity` | `check_workspace_integrity` fault on the unpacked tree | `diagnostic` (the `OOF-IMP4/6/7/8/9` to_value, incl. P19 `details`) |
| `missing_lock` | `--require-lock` and the archive has no (readable) lock | — |
| `stale_lock` | packed lock ≠ packed sources (content drift) | `packages: [names]` |
| `toolchain_drift` | `--match-toolchain` and manifest compiler/stdlib ≠ node's | `expected` / `actual` |

**Honest boundary:** `compiler_version`/`stdlib_version` live in the manifest header, which is **not** inside
the tree digest — so `toolchain_drift` is a *compatibility* check, not a security gate. The security guarantee
is the **tree digest + integrity + local compilation by the node's own toolchain**; a lied toolchain field
cannot grant code execution (the node compiles the verified source itself).

## Live behavior (smoke)

| Action | Result |
|---|---|
| `admit` clean (locked) `--require-lock --match-toolchain` | `accepted:true`, full receipt, exit 0 |
| flip one byte → `admit` | `refusals:[digest_mismatch]`, exit 1 |
| `admit` phantom archive | `refusals:[integrity{diagnostic.rule:OOF-IMP6}]`, exit 1 |
| edit source after lock, pack, `admit --require-lock` | `refusals:[stale_lock{packages:[…]}]`, exit 1 |
| no lock, `admit --require-lock` | `refusals:[missing_lock]`, exit 1 (accepted without the flag) |
| manifest compiler lied, `admit --match-toolchain` | `refusals:[toolchain_drift{actual,expected}]`, exit 1 (digest still ok) |

## Connects to (P22-remote design)

The deterministic `{accepted, artifact_digest, lock_digest, compiler/stdlib_version, entry, refusals}` is the
receipt a future node runtime records as lineage. Distributed Kuramoto: every node `admit`s the **same**
`.igpkg` for `NodeTick` (same `artifact_digest`); topology/seed = separate runtime config; the run is
attributable to an exact admitted artifact. Transport / identity / authorization / admission policy stay
host + control-plane — `admit` only answers *should this code be trusted*, not *who sent it*.

## Tests & commands — exact counts

```text
$ cd lang/igniter-compiler && cargo test --test package_lockfile_cli_tests   → 44 passed (37 + 7 NEW P23)
$ cd lang/igniter-compiler && cargo test                                     → full suite green (0 failed)
$ git diff --check                                                           → clean
```

New P23 tests (7): `cli_admit_clean_accepted`, `cli_admit_is_deterministic`,
`cli_admit_tampered_digest_mismatch`, `cli_admit_integrity_refused` (OOF-IMP6),
`cli_admit_stale_lock_refused`, `cli_admit_missing_lock_refused` (accepted without the flag),
`cli_admit_toolchain_drift_refused`. The P22 `verify` tests stay green (the `unpack_archive` extraction is
behavior-preserving).

## Acceptance — mapping

- [x] Clean archive → `accepted: true`.
- [x] Result carries `artifact_digest`, `compiler_version`, `stdlib_version`, and lock identity (`lock_digest`).
- [x] Same archive → deterministic admission result.
- [x] Tampered archive refused (`digest_mismatch`) before execution.
- [x] Integrity fault refused (`integrity`) with the underlying `OOF-IMP*` visible.
- [x] Stale lock refused (`stale_lock`).
- [x] Missing lock under `--require-lock` refused (`missing_lock`).
- [x] Toolchain drift under `--match-toolchain` refused (`toolchain_drift`).
- [x] `igc package verify` unchanged; no network/registry/semver/signing/deploy; full suite green; `git diff --check` clean.

## Files changed

- `lang/igniter-compiler/src/project.rs` (`pack_archive` manifest +`lock_digest`/`entry_contract`;
  `unpack_archive`/`unpacked_integrity` extraction; `verify_archive` routed through them; `admit_archive`).
- `lang/igniter-compiler/src/main.rs` (`package admit` dispatch + handler).
- `lang/igniter-compiler/tests/package_lockfile_cli_tests.rs` (+7 P23 tests).

## Deferred / future

Signatures + key management (manifest `signature` slot reserved); registry / semver / remote transport;
real node identity + authorization + admission policy (control-plane); execution receipts in the runtime
(igniter-machine effect); folding the manifest into the digest if toolchain fields ever need tamper-evidence.

## Next

`LAB-IGNITER-REMOTE-NODE-MOCK-TRANSPORT-P*` (transport/admission, no real network) or
`LAB-IGNITER-EMERGENCE-LOCAL-MULTINODE-SIM-P*` (every simulated node admits + runs the same `NodeTick`
artifact); later signed-package / registry waves.

---

*Lab implementation-proof. Compiled 2026-06-21; `package_lockfile_cli_tests` 44 green, full `igniter-compiler`
suite green, `git diff --check` clean. `igc package admit` is the local node-admission gate — content digest +
integrity + optional lock-parity + toolchain-match → a deterministic `{accepted, artifact_digest, refusals}`
receipt; tampered/stale/drifted input refused before execution; transport/identity/admission stay control-plane.*
