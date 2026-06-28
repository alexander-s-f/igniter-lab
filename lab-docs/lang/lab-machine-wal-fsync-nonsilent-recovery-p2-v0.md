# LAB-MACHINE-WAL-FSYNC-NONSILENT-RECOVERY-P2 v0

Status: implementation complete
Date: 2026-06-28
Scope: `igniter-lab` `runtime/igniter-machine` only. No TBackend/home-lab/SparkCRM
edits, no Postgres receipt-CAS change, no server/web change.
Depends-On: `lab-docs/lang/lab-machine-durable-cas-seqid-fsync-owner-split-p1-v0.md`
Closes: audit-control-board row **A21** machine-WAL slice (orthogonal to the
PG exactly-once CAS slice).

## Before-state (verified in live source)

`runtime/igniter-machine/src/wal.rs` — append-only log,
`len(u32 BE) | msgpack(Fact) | crc32(u32 BE)` per record.

- **Durability (Q1):** `append` called `BufWriter::flush()` only — flush to the OS
  page cache, **no `fsync`** (`sync_data`/`sync_all`). Survives a process crash,
  NOT power loss. There was no policy type and no fsync anywhere in `wal.rs`.
- **Recovery (Q3 before):** `replay()` returned `Vec<Fact>` and was **silent** on
  every fault: a short body/crc read → `break`; a CRC mismatch → `break`; a
  decode error → `continue`. No counts, offsets, flags, or error — corruption and
  truncation were indistinguishable from a clean end of log.
- **Callers:** `replay()` is called once, at boot
  (`machine.rs:77`, feeds facts into storage); `WALWriter::new` once
  (`machine.rs:76`); `append` once (`machine.rs:368`). Single producer/consumer,
  so the hardening lands with no call-site churn.
- **Pattern to mirror:** the `.mpk` store (`backend.rs`) already had the explicit
  vocabulary — `sync_all` fsync of the data file + best-effort dir fsync, a
  `corrupt_files()` report, and fail-closed `EngineError::Corruption` — with an
  honest macOS power-loss non-claim. The WAL is brought to the same posture.

## Chosen fsync / group-commit policy (Q2)

Per-record fsync, **policy-selectable**:

```rust
pub enum WalDurability { Flush, Sync }   // default for new(): Sync
```

- `append` flushes the buffer, then (when `Sync`) calls
  `BufWriter::get_ref().sync_data()` — `fdatasync`, not `sync_all`: a pure append
  only changes file length (already updated by the write), so the metadata sync
  `sync_all` adds is unnecessary.
- `WALWriter::new(path)` defaults to `Sync` (durable) for machine receipts;
  `WALWriter::with_durability(path, Flush)` opts into flush-only for tests /
  throughput paths. `durability()` exposes the active policy.
- **Group-commit is intentionally NOT built** this slice. The machine appends one
  fact per write under a `Mutex<BufWriter>`; per-record `fdatasync` is the
  explicit, simplest correct policy. A batched group-commit (amortising fsync over
  N queued appends) is a throughput optimisation deferred to a later card — named
  in "Remaining gaps".

## Recovery failure taxonomy (Q3, Q4)

New non-silent scan `replay_reported() -> Result<WalReplay, EngineError>`:

```rust
struct WalReplay { facts, recovered, truncated_tail: bool, corrupt: Vec<WalCorruption> }
struct WalCorruption { offset: u64, kind: WalCorruptionKind, detail: String }
enum   WalCorruptionKind { CrcMismatch, Deserialize }
```

| Situation | Classification | Scan action | Boot (`replay`) |
|---|---|---|---|
| clean EOF at a record boundary | (normal) | stop | recover all |
| length/body/crc field cut short, or a body claiming more bytes than the file holds | `truncated_tail = true` | stop | **tolerated** — recover healthy prefix |
| stored CRC ≠ `hash(body)` | `corrupt += CrcMismatch` | **stop** (framing past here is untrustworthy) | **fail closed** |
| CRC valid but body does not decode to `Fact` | `corrupt += Deserialize` | **continue** (framing intact) | **fail closed** |
| cannot open / read the file | — | `Err(EngineError::IOError)` | propagate |

Rationale (Q4 — quarantine vs skip vs hard-fail):
- A **torn tail** is the signature of a crash *during* the last append; the
  completed prefix is durable, so recovery keeps it and only **flags** the tail.
  Not fatal.
- **Mid-stream corruption** is an integrity fault. `replay_reported` *reports* it
  (offset + kind, never silent), while the boot-facing `replay()` **fails closed**
  with `EngineError::Corruption` rather than silently dropping or skipping
  receipts — matching the `.mpk` store's "refuse, don't silently lose" posture.
  An operator/test can still inspect the full picture via `replay_reported()`.
- The huge-length guard (`body_len + 4 > remaining` ⇒ `truncated_tail`) is checked
  **before** allocating, so a corrupt length field cannot trigger an OOM
  allocation. (Edge note: a corrupted huge length on a non-final record is
  classified as a torn tail rather than `CrcMismatch`; it is still non-silent.)

`replay()` is unchanged at its single call site — it now fails closed on
corruption automatically (`?` propagates), so boot refuses a corrupt receipt WAL.

## Tests / proofs run

New `tests/wal_fsync_recovery_tests.rs` (5), tempdirs + deterministic on-disk
corruption:

- `default_durability_is_sync_and_is_selectable` — policy is explicit.
- `clean_replay_recovers_all_and_reports_no_corruption` — 3 appended → 3 recovered,
  no flag, no corruption; `replay()` agrees.
- `truncated_tail_recovers_prefix_and_is_flagged_not_fatal` — 2 appended, tail
  cut → 1 recovered, `truncated_tail`, `corrupt` empty, `replay()` Ok.
- `crc_mismatch_is_reported_and_boot_fails_closed` — last record's CRC byte
  flipped → prefix recovered, `CrcMismatch` reported, `replay()` Err(Corruption).
- `deserialize_failure_is_reported_and_scan_continues` — a CRC-valid non-`Fact`
  record followed by a good one → bad one reported as `Deserialize` at offset 0,
  the later good record still recovered (proves continue), `replay()` Err.

```text
cargo test … --test wal_fsync_recovery_tests        → 5 passed; 0 failed
cargo test … --test storage_durability_proof_tests  → 3 passed; 0 failed
cargo test … (full igniter-machine suite)           → 58 suites ok, 362 passed, 0 failed
git diff --check                                     → clean
```

## Durability level + explicit non-claims (Q5: weaker than TBackend daemon)

- **Claimed:** every `Sync` append is flushed and `fdatasync`'d to the OS before
  returning; replay never silently swallows corruption/truncation; boot fails
  closed on mid-stream corruption.
- **NOT claimed:** real power-loss / device-cache durability. `fsync` does not
  flush the drive's own write cache on macOS (needs `F_FULLFSYNC`); on-disk
  truncation/byte-flip in the tests is a deterministic stand-in for a torn write,
  not a power-loss simulation. Same non-claim as the `.mpk` store.
- **Weaker than the TBackend daemon (P1 owner-split):** no batched group-commit
  (per-record fsync only); no multi-process exactly-once CAS (that is the
  orthogonal PG slice, `LAB-MACHINE-DURABLE-CAS-PG-EXACTLY-ONCE-P2`); no
  server-assigned `seq_id` / version-vector admission; no compaction. This slice
  is WAL hygiene only.

## Remaining gaps / next cards

- Group-commit / batched fsync for append throughput (optional perf card).
- Surfacing the boot-time `WalReplay` report through a machine-level
  observability hook (machine.rs has no logger today; the signal is currently the
  fail-closed `Err` + the inspectable `replay_reported()`).
- TBackend daemon receipt adoption (deferred cross-project,
  `LAB-MACHINE-TBACKEND-RECEIPT-ADOPTION-READINESS-P2`).

## Untouched

- TBackend / home-lab / SparkCRM — not edited.
- Postgres receipt CAS — not edited.
- server / web — not edited.
- Public machine API — only additive (`WalDurability`, `WalReplay`,
  `WalCorruption[Kind]`, `with_durability`, `durability`, `replay_reported`);
  `replay()` signature unchanged.
