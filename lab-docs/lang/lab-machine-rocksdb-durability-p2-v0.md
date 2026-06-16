# igniter-machine storage durability — audit / readiness (P2, v0)

**Card:** `LAB-MACHINE-ROCKSDB-DURABILITY-P2` · **Lane:** readiness / proof / storage-hardening
**Scope:** audit + one bounded proof. **No broad storage rewrite, no live/staging, no power-loss claim.**

> **→ HARDENED by P3 (2026-06-16):** the silent-loss + non-atomic + no-fsync findings below are
> **closed** by `LAB-MACHINE-FACTSTORE-DURABILITY-HARDENING-P3`
> (`lab-machine-factstore-durability-hardening-p3-v0.md`): atomic temp→fsync→rename writes, observable
> corruption (`corrupt_files()`/`EngineError::Corruption`), receipt spine on the hardened path, and
> `RocksDBBackend`→`MpkFileBackend` rename. Full cross-platform **power-loss** durability remains
> platform-gated (macOS `F_FULLFSYNC`). This doc stays as the **audit of record**; P3 is the fix.

> **Authority & verify-first.** This doc is anchored on the **live storage code** read on
> 2026-06-16: `igniter-machine/src/backend.rs`, `src/wal.rs`, `src/machine.rs`, `src/write.rs`,
> `src/capability.rs`, `src/recovery.rs`, plus `Cargo.toml`. Where it contradicts a card or an
> older claim, the code wins. Proof: `tests/storage_durability_proof_tests.rs` (3 tests, green).

---

## 0. Headline (read this first)

Two findings change the durability picture from what the topology/P19 lore implies:

1. **"RocksDBBackend" is not RocksDB.** There is **no `rocksdb`/`sled`/`redb` crate dependency**
   (verified in `Cargo.toml`). `RocksDBBackend` is a **pure-Rust `.mpk` file store**: an in-memory
   `ShardedFactLog` plus, per `(store,key)`, a MessagePack file `data_dir/<store>/<key>.mpk` that is
   **rewritten whole on every write** via a **non-atomic, non-fsync'd `std::fs::write`**. The name
   implies guarantees (WAL, fsync, atomic commit) it does **not** provide.

2. **The production receipt spine bypasses the WAL.** The crate *has* a good append-only,
   CRC32, truncation-tolerant WAL (`wal.rs`) — but it is only wired into
   `IgniterMachine::write_fact` (kernel facts). The capability-IO receipts —
   `run_write_effect` / `run_effect` — write directly to the **bare `Arc<dyn TBackend>`**
   (`receipts.write_fact`, verified in `write.rs:207` / `capability.rs:315`), so the
   **most safety-critical store gets the weakest durability path.**

Net: **graceful-restart durability is real** (proven), but **crash-during-write can silently lose
receipts**, and **fsync/power-loss durability is unproven and absent**.

---

## 1. Exact write path

### 1a. Kernel facts — `IgniterMachine::write_fact` (has WAL)
```
machine.write_fact(fact):
  wal.append(&fact)         # append-only: [len u32][rmp body][crc32]; BufWriter::flush() (NOT fsync)
  storage.write_fact(fact)  # then the backend below
# reopen: WALWriter::replay() → re-pushes facts into storage (truncation-tolerant: stops on torn tail)
```

### 1b. Receipts / retry-intents / dead-letters — bare backend (NO WAL)
`run_write_effect`, `run_effect`, `enqueue_retry`, orchestrator `put()` all take
`receipts: &Arc<dyn TBackend>` and call `receipts.write_fact(...)` **directly** — the WAL is not in
this path.

### 1c. `RocksDBBackend::write_fact` (the actual persistence)
```
write_fact(fact):
  log.push(fact)                                   # in-memory ShardedFactLog (fast reads)
  store_dir = data_dir/<fact.store>;  create_dir_all
  file = store_dir/<fact.key>.mpk
  facts = if file.exists { rmp_serde::from_slice(read(file)).unwrap_or_default() } else { [] }
  facts.push(fact)                                 # READ-MODIFY-WRITE the whole version vector
  std::fs::write(file, rmp_serde::to_vec(facts))   # truncate+write, NON-ATOMIC, NO fsync
```
- **store namespace** = subdirectory; **key path** = `<key>.mpk`; one file per `(store,key)`.
- **`.mpk` serialization** = `rmp_serde` MessagePack of `Vec<Fact>` (all versions of that key).
- **append behaviour** = *logical* append, *physical* full-file rewrite (read all, push, rewrite).
- Reopen preload (constructor) is the same shape: `if let Ok(facts) = rmp_serde::from_slice(...)`
  — an undecodable file is **skipped silently** (no error).

---

## 2. What makes a receipt "committed" from the host's POV

`run_write_effect` writes a terminal receipt fact with `state="committed"` after the executor
returns success; the host treats the effect as committed when **`receipts.write_fact(...)` returns
`Ok`**. That `Ok` means: the in-memory log was updated **and** `std::fs::write` returned — i.e. the
bytes reached the **OS page cache**. It does **not** mean the bytes are on stable media (no fsync),
nor that the file is intact if the process dies mid-write (no atomic rename).

---

## 3. Does `write_fact` flush/sync to disk?

| Path | Userspace flush | fsync (`sync_all`/`sync_data`) | Atomic |
|---|---|---|---|
| `RocksDBBackend.write_fact` (receipts) | n/a (`std::fs::write`) | **No** | **No** (truncate+rewrite) |
| `WALWriter.append` (kernel facts) | `BufWriter::flush()` (→ OS) | **No** | append-only (tolerant on replay) |

**No fsync exists anywhere in the fact/receipt write path** (verified: no `sync_all`/`sync_data`/
`fsync` in `src/`). Durability is **OS-page-cache only**. A clean process restart is safe (the OS
still owns the pages); a power loss / kernel panic can lose any not-yet-flushed write that already
returned `Ok`.

---

## 4. Crash-window map

"Survives" below means *the receipt was fully written and the OS flushed the page* (graceful
restart). "Torn" means a crash mid-`std::fs::write` left a half-written `.mpk`.

| Window | If durable bytes survived | If write was torn / not flushed |
|---|---|---|
| **During prepare-receipt write** | n/a (atomic from host view: either prepared exists or not) | torn `.mpk` → on reopen the key's receipts are **silently dropped** (§proof). Effect had **not** run → a re-request re-prepares + re-executes. *Safe* (no double effect), but the in-flight op is invisible. |
| **After prepare, before executor** | P19 boot sees dangling `prepared` → reconciles by read-back → no effect ran → permanent_failure/retry. **Covered.** | prepare lost → P19 has nothing to reconcile → re-request re-prepares. Effect hadn't run → *safe*. |
| **After executor, before terminal receipt** ⚠ | P19 reads the target back (P7) or by correlation (P13) → upgrades dangling `prepared`→`committed`. **Covered — the write-succeeded-but-receipt-failed window.** | **RESIDUAL HOLE:** if the *prepared* receipt was also torn/lost, the effect **landed** but there is **no receipt to reconcile** → invisible → a retry can **double-execute** a non-idempotent external effect. Widened by the receipt store having no fsync/atomicity. |
| **During terminal-receipt write** | committed receipt present → replay bypasses executor. **Covered.** | torn `.mpk` → reopen silently drops the **whole key history incl. the prepared marker** → same residual hole as above. |
| **During retry-intent write** | intent fact present → `drain_due_retries` runs it when due. **Covered.** | torn `__retry_queue__` file → intent **silently lost** on reopen → a due retry never fires (unless the original unknown receipt survives for P19/manual reconcile). |

The single **load-bearing assumption** for P19 to work is: *the `prepared` receipt is durable enough
to be re-read after a crash.* Today that durability is page-cache-only and non-atomic, so the
assumption is weaker than the recovery model presumes.

---

## 5. What P19 covers vs not

**Covers (verified `recovery.rs` + tests):** dangling `prepared`/`unknown_external_state` receipts
that **survived restart** are reconciled by value read-back (P7) or correlation (P13); recovery
**never re-executes** (no executor param); idempotent across reboots; closes the
write-succeeded-but-receipt-failed window **when the prepare receipt is durable**.

**Does NOT cover:** (a) receipts that were never durably flushed (power loss) or were **silently
dropped by `.mpk` corruption** — P19 can only reconcile what it can still read; (b) fsync /
power-loss durability; (c) torn-write atomicity; (d) directory-entry durability (a new `.mpk`'s
dir entry isn't fsync'd). P19 is a **logical** recovery over the fact store; it assumes the fact
store is **physically** sound.

---

## 6. Backup-consistency story

| Method | Consistent? | Notes |
|---|---|---|
| **Copy data dir while running** | **No** | non-atomic full-file rewrites → a copy can catch a half-written `.mpk`; no snapshot isolation across files. |
| **Quiesced backup** | **Yes (file-level)** | topology P1 already mandates **one effect-process per data dir** → stop the process (no in-flight `write_fact`), then copy. Clean-shutdown pages are flushed by the OS. Recommended interim backup. |
| **Checkpoint snapshot** (`IgniterMachine::checkpoint(.igm)` / `checkpoint_bytes`) | **Yes (point-in-time, capsule)** | deterministic, byte-identical MessagePack `SemanticImage{contracts,facts,observations}`; consistent with the process's in-memory view. Better than live file copy — but it is the *capsule* image, taken via the machine; confirm it captures the live receipt stores you need before relying on it for receipt backup. |

---

## 7. Invariants a "committed receipt" must hold across restart

1. **Durable presence** — a `committed` receipt fully written before the crash is readable after
   reopen. *(Today: page-cache only; not guaranteed under power loss.)*
2. **Exactly-once** — the committed receipt + its idempotency key survive so replay bypasses the
   executor. *(Holds under graceful restart; at risk under torn-write loss.)*
3. **No silent loss** — a present-but-corrupt file must **fail loudly**, never be treated as empty.
   **CURRENTLY VIOLATED** (`unwrap_or_default` / `if let Ok` skip) — proven in §8.
4. **Reconstructable ordering** — the `prepared` marker survives so P19 can find dangling ops.
   *(At risk: same torn-write window.)*

---

## 8. Bounded proof added (non-invasive)

`tests/storage_durability_proof_tests.rs` — 3 tests, green, no network/live:

- `durable_across_graceful_reopen` — write 3 versions, drop, reopen → **all survive**, latest
  correct. *(Confirms the durability level P19 relies on: graceful restart.)*
- `truncated_mpk_silently_dropped_on_reopen` — truncate the `.mpk` to half (a torn-write stand-in),
  reopen → **all versions silently gone, no error** (invariant #3 violated).
- `write_after_corruption_drops_prior_history` — after a torn file, the next write persists **only**
  the new fact; history is **not** recovered → one torn write erases prior versions permanently.

> Truncation is a **deterministic stand-in for a torn write**, *not* a power-loss test. It exercises
> the corruption-handling path, which is real code, today.

---

## 9. Recommended code changes (stated, NOT implemented here)

Per the card, recommendations only — each belongs to a future hardening card, **no broad rewrite in
this slice**:

1. **Stop silent loss (highest leverage, smallest change).** On `rmp_serde::from_slice` Err in the
   constructor preload **and** the write read-modify path, **surface/quarantine** instead of
   `unwrap_or_default()`. Silent loss is undetectable; a loud failure lets an operator restore from
   backup.
2. **Atomic writes.** Write `<key>.mpk.tmp` then `rename` (atomic on same fs) — eliminates the torn
   half-file window.
3. **fsync for real crash durability.** `File::sync_all()` on the data file (and fsync the dir on
   create) after the rename — turns page-cache durability into crash durability.
4. **Put the receipt spine on the WAL** (or make the backend durable) — the receipt store is the
   production durability spine and currently uses the weakest path; routing it through the existing
   append-only+CRC WAL (or a real engine) closes most of §4 at once.
5. **Name honestly.** Rename `RocksDBBackend` → `MpkFileBackend`, **or** adopt a real
   `rocksdb`/`redb` engine (built-in WAL + fsync + atomic). The current name asserts guarantees the
   code lacks (anti-drift).

These are a **menu for a deployment/hardening track**, gated like the rest of live readiness.

---

## 10. Explicitly out of scope until deployment

Filesystem-level fsync guarantees on the target OS/FS; **power-loss / pull-the-plug testing**; cloud
volume semantics (EBS/gp3 write barriers, fsync honoring, replicated-volume durability); distributed
lock / CAS / multi-process (one effect-process per dir stands, topology P1); choosing/adopting a real
storage engine. None claimed proven here.

---

## Boundary recap

- Verify-first on live storage code; corrects the "RocksDB" label and the WAL-coverage assumption.
- **Proven** graceful-restart durability ≠ **unproven** fsync/power-loss durability — kept distinct.
- Every crash window mapped to a current mitigation (P19) or an open risk (§4).
- Code changes **recommended and scoped**, not implemented; the one added artifact is a bounded
  no-network proof test.
- P25 live-gate boundary intact: nothing here authorizes live; durability hardening is a gated track.

*Audit/readiness only. Stale docs cannot override live code + the proof test. Compiled 2026-06-16.*
