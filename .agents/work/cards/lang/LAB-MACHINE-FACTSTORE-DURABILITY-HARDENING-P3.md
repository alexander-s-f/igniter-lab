# Card: LAB-MACHINE-FACTSTORE-DURABILITY-HARDENING-P3 — close the P2 storage hole

**Lane:** implementation / storage-hardening / production-safety · **Skill:** idd-agent-protocol
**Status: CLOSED 2026-06-16.** Storage code + tests only. **No live/staging, no engine migration.**

> **Doc:** [`lab-docs/lang/lab-machine-factstore-durability-hardening-p3-v0.md`](../../../../lab-docs/lang/lab-machine-factstore-durability-hardening-p3-v0.md)
> Hardens the `.mpk` fact store so receipt/dedup/retry/recovery/dead-letter facts don't silently
> vanish or corrupt under torn writes — closes the LAB-MACHINE-ROCKSDB-DURABILITY-P2 hole.

## Authority boundary

- **Source of truth:** live `src/backend.rs`, `src/errors.rs`; P2 audit; P19 recovery; P25/P17 boundary.
- **Authorized:** storage code + tests only.
- **Closed (held):** no live/staging, no network, no distributed lock/CAS, no multi-process HA, no
  language/compiler change, no broad engine migration, no power-loss claim beyond what's proven.

## What changed (storage path only)

1. **Stop silent loss** — corrupt `.mpk` is recorded in `corrupt_files()` (observable) + write to a
   corrupt key **refuses** with new `EngineError::Corruption(_)` instead of `unwrap_or_default()`.
2. **Atomic writes** — `atomic_write`: sibling temp → `fsync` data file → atomic `rename` →
   best-effort parent-dir `fsync`; failed replace leaves the prior file intact; RMW under a write lock.
3. **Explicit durability semantics** — "committed fact" = fsync'd-to-OS + atomic rename; **macOS
   power-loss durability NOT claimed** (needs `F_FULLFSYNC`, not in std). Documented.
4. **Receipt spine hardened** — spine writes through `Arc<dyn TBackend>::write_fact` =
   `MpkFileBackend`; hardening the backend hardens the spine, no routing change.
5. **Naming** — `RocksDBBackend` → **`MpkFileBackend`** (+ back-compat alias) to stop the misnomer drift.

## Tests (verify-first, green)

- `tests/storage_durability_hardening_tests.rs` (5): `corrupt_fact_file_is_not_silently_dropped`,
  `atomic_write_preserves_previous_version_on_failed_replace`,
  `receipt_prepare_torn_write_blocks_or_recovers_without_reexec`,
  `receipt_spine_uses_hardened_factstore_path`, `retry_queue_and_deadletter_survive_reopen`.
- `tests/storage_durability_proof_tests.rs` (3): the two P2 silent-loss tests rewritten to assert the
  hardened behaviour; graceful-restart durability retained.
- **`cargo test --no-default-features` = 264 passed / 0 failed** across all targets (256 P2 baseline
  +3 +5). `--features tls` targets green (http_tls 7, sparkcrm 8).
- **Pre-existing, unrelated:** `frame_projection_tests` fails to COMPILE (`unresolved import
  igniter_machine::frame`) from in-progress frame-rehome work (src/frame.rs not in lib.rs). It aborts
  a single `cargo test` run, so 264 is measured per-target excluding it. Flagged separately; not this
  card's storage scope, not introduced here.

## Acceptance (all met, with one honest qualifier)

No silent loss on corrupt `.mpk` ✓ · atomic file writes ✓ · fsync/flush explicit + tested as far as
local platform allows ✓ · receipt/retry/dedup/dead-letter writes don't bypass the hardened path ✓ ·
P2 dangerous window closed/converted to observable-recoverable ✓ · suite green **except** the unrelated
pre-existing frame compile orphan (qualifier, not a storage regression) · no live/network ✓.

## Blocker status

P17/P25 storage-durability blocker **NARROWED**: in-lab physical durability (silent-loss, atomicity,
fsync-to-OS, spine path, naming) **CLOSED**; **full cross-platform power-loss durability remains
deployment-gated** (macOS `F_FULLFSYNC`, cloud-volume fsync honoring) under the P25 human-gate. A real
`redb`/`rocksdb` engine migration is the recommended path if that's later required (separate approved card).

## Next route

- (gated) deployment validation of fsync honoring on the target FS/volume + macOS `F_FULLFSYNC` decision.
- (optional, approved) real storage-engine migration behind the same `TBackend` if power-loss
  durability is required cross-platform.
