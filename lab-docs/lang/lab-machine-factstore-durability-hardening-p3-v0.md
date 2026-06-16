# igniter-machine fact-store durability — hardening (P3, v0)

**Card:** `LAB-MACHINE-FACTSTORE-DURABILITY-HARDENING-P3` · **Lane:** implementation / storage-hardening
**Scope:** storage code + tests only. **No live/staging, no network, no engine migration, no language changes.**

> **Authority & verify-first.** Anchored on live `igniter-machine` storage code (`src/backend.rs`,
> `src/errors.rs`), the P2 audit (`lab-machine-rocksdb-durability-p2-v0.md`), and P19 recovery. All
> claims below are backed by green tests run 2026-06-16 (`storage_durability_hardening_tests.rs` +
> updated `storage_durability_proof_tests.rs`).

---

## 0. What this closes

P2 found the protocol-level exactly-one/recovery model (P18–P24) sat on a **physically weak** fact
store: the `.mpk` file store used **non-atomic `std::fs::write`**, **no fsync**, and **silently
treated a corrupt file as empty** (`unwrap_or_default`), and the receipt spine wrote through the bare
backend. P3 hardens the backend itself — so everything that writes through it (receipts, retry queue,
dedup, dead-letters, orchestrator) is hardened with **no routing change**.

```
P2 (audit):  silent corruption loss · non-atomic writes · no fsync · misleading "RocksDB" name
P3 (this):   corruption observable+refused · atomic temp→fsync→rename · explicit fsync · MpkFileBackend
Remaining:   full power-loss durability is platform-dependent (macOS F_FULLFSYNC) — gated, not claimed
```

---

## 1. Changes (storage path only)

### 1a. `RocksDBBackend` → `MpkFileBackend` (+ back-compat alias)
`src/backend.rs`: the struct is renamed to **`MpkFileBackend`** with a doc-comment stating it is a
pure-Rust `.mpk` file store, **not** RocksDB. `pub type RocksDBBackend = MpkFileBackend;` keeps every
existing call site (machine.rs `"rocksdb"` mode, recovery tests) compiling. Stops the name implying
LSM/WAL/fsync guarantees it never had (P2 finding #5).

### 1b. Atomic writes (P2 #2)
New `atomic_write(file, tmp, bytes)`: write a **sibling temp** in the same dir → `File::sync_all()`
(**fsync the data file**) → `std::fs::rename` (atomic on same fs) → **best-effort parent-dir fsync**.
On any pre-rename failure the temp is removed and the **prior file is untouched**. A crash mid-write
therefore leaves either the old complete file or the new complete file — never a torn one. The RMW
critical section is guarded by a per-backend write lock so a same-file append is never lost and temp
names never collide.

### 1c. Corruption is observable, never silent (P2 #1)
- **Constructor preload:** a `.mpk` that fails to decode is recorded in **`corrupt_files()`** and
  **left on disk** (forensics) — it is **not** silently skipped into an empty key.
- **Write path:** if the existing file is corrupt, `write_fact` **refuses** with the new
  `EngineError::Corruption(_)` instead of `unwrap_or_default()`-ing it and persisting only the new
  fact (which in P2 permanently erased history). The corrupt bytes are preserved for recovery.
- Persist-then-publish ordering: the file write happens **before** the in-memory `log.push`, so a
  refused write never leaves the in-memory view ahead of disk.

### 1d. Receipt spine uses the hardened path (P2 #4)
The capability-IO receipt spine (`run_write_effect`/`run_effect`), retry queue (`enqueue_retry`),
dedup, dead-letter, and orchestrator writes all go through `Arc<dyn TBackend>::write_fact` =
`MpkFileBackend::write_fact`. Hardening the backend hardens the spine **with no new wrapper and no
routing change**. Proven by `receipt_spine_uses_hardened_factstore_path`.

---

## 2. Durability semantics — what "committed fact on disk" means now (P2 #3)

A `write_fact` returning `Ok` means, in order: bytes written to a sibling temp → **`fsync` (data
file)** → **atomic rename** to the final path → **best-effort `fsync` of the parent dir**. So a
committed fact is **atomic and crash-consistent** (no torn file) and **fsync'd to the OS**.

**Explicit limitation (not claimed):** `File::sync_all()` is `fsync`. On **macOS**, `fsync` does
**not** flush the drive's own write cache — that requires `fcntl(F_FULLFSYNC)`, which Rust `std` does
not expose. So **full power-loss durability is NOT claimed on macOS** (a power cut could still lose an
fsync'd-but-not-F_FULLFSYNC'd write). On Linux/most FSes `fsync` + dir-fsync is the standard durable
path. Power-loss durability remains a **deployment-gated, platform-dependent** property — see §5.

---

## 3. Tests (no network/live)

`tests/storage_durability_hardening_tests.rs` (5, green):
- `corrupt_fact_file_is_not_silently_dropped` — corrupt one key's file; reopen → `corrupt_files()`
  surfaces it AND a healthy sibling key still loads (corruption isolated + observable).
- `atomic_write_preserves_previous_version_on_failed_replace` — a leftover partial temp (crash
  mid-replace) is ignored on reopen; both prior versions survive; the live `.mpk` stays valid.
- `receipt_prepare_torn_write_blocks_or_recovers_without_reexec` — prepared receipt durable + effect
  landed → after reopen, P19 `recover_dangling_writes` resolves it to `committed` **without an
  executor** (no re-exec; substrate unchanged). The P2 dangerous window converted to a safe one.
- `receipt_spine_uses_hardened_factstore_path` — `run_write_effect` committed receipt survives reopen.
- `retry_queue_and_deadletter_survive_reopen` — retry intent + dead-letter facts survive a restart.

`tests/storage_durability_proof_tests.rs` (3, green) — the two P2 tests that **documented** the old
silent-loss bug were rewritten to assert the **hardened** behaviour:
- `durable_across_graceful_reopen` (unchanged) — graceful-restart durability.
- `corrupt_mpk_is_observable_not_silently_dropped` (was `truncated_mpk_silently_dropped_on_reopen`).
- `write_to_corrupt_key_refuses_instead_of_dropping_history` (was `write_after_corruption_drops_prior_history`).

**Suite:** `cargo test --no-default-features` = **264 passed, 0 failed across all targets** (256 P2
baseline + 3 proof + 5 hardening). `--features tls` targets green (http_tls 7, sparkcrm 8).

> **Caveat (not introduced by this card):** the unrelated `tests/frame_projection_tests.rs` currently
> fails to **compile** (`unresolved import igniter_machine::frame`) due to in-progress frame-rehome
> work (`LAB-FRAME-*-REHOME` cards) — `src/frame.rs` is no longer wired into `lib.rs`. Because a
> test-target compile error aborts the whole `cargo test` run, the 264 figure is measured by running
> every target **except** that orphan. The storage suite and the entire capability/coordination suite
> are green. Flagged for cleanup separately; outside this card's storage scope.

---

## 4. P2 crash-window map → P3 status

| Window (P2) | P3 status |
|---|---|
| prepare receipt torn/lost | atomic writes → no torn prepare; either durable (P19 recovers) or never landed (no effect). **Closed.** |
| after prepare, before executor | unchanged-safe (no effect ran); prepare now durable. **Closed.** |
| **after executor, before terminal receipt** (the dangerous one) | prepare is durably present → P19 reconciles by read-back/correlation, no re-exec (`receipt_prepare_torn_write_blocks_or_recovers_without_reexec`). The P2 "torn prepare → invisible → double-exec" sub-case is removed by atomic writes. **Closed (within fsync-to-OS; see §2).** |
| during terminal-receipt write | atomic → old or new complete file, never torn; corruption (external) now refused+observable. **Closed.** |
| retry-intent / dead-letter write | same hardened path; survive reopen (`retry_queue_and_deadletter_survive_reopen`). **Closed.** |

---

## 5. Blocker status (P17/P25/live-gate)

- **Production-hardening blocker (storage physical durability): NARROWED, not fully closed.**
  - **Closed in-lab:** silent corruption loss, write atomicity, fsync-to-OS, receipt-spine path,
    misleading name. All tested.
  - **Remains (deployment-gated):** true power-loss durability is **platform-dependent** — on macOS
    it needs `F_FULLFSYNC` (not exposed by std); on the deployment FS/volume, fsync honoring and
    cloud-volume write-barrier semantics must be validated. This is an **operational** property, not
    an in-lab engineering gap, and stays under the P25 human-gate.
- **No engine migration performed.** If full power-loss durability across platforms is later
  required, the recommendation is to adopt a real `redb`/`rocksdb` engine (built-in WAL + fsync +
  atomic) behind the same `TBackend` — a separate, explicitly-approved card, not done here.

---

## Boundary recap

- No silent data loss on corrupt `.mpk` (observable + refused). Atomic file writes. fsync explicit
  and tested as far as the local platform allows. Receipt/retry/dedup/dead-letter writes go through
  the hardened path. The P2 dangerous window is closed (within fsync-to-OS) and otherwise converted to
  an observable/recoverable state.
- `cargo test --no-default-features` green (264, all targets except the unrelated frame orphan);
  `--features tls` targets green.
- No live/staging/network; no distributed lock/CAS; no multi-process HA; no language/compiler change;
  no broad engine migration; no power-loss claim beyond what §2 proves.

*Implementation + bounded proofs. Stale docs cannot override live code + tests. Compiled 2026-06-16.*
