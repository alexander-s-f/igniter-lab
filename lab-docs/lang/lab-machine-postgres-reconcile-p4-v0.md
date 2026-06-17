# LAB-MACHINE-POSTGRES-RECONCILE-P4: fake-adapter Postgres write reconcile

**Track:** `lab-machine-postgres-reconcile-p4-v0`
**Status:** CLOSED — implementation proof. **Fake adapter/resolver only. No DB, no SQL, no network, no new dependency.**
**Route:** LAB implementation slice, follow-on to `LAB-MACHINE-POSTGRES-WRITE-GATE-P3`.
**Authority:** No canon claim. No language authority. Lab evidence only. Old Ruby framework
surfaces are not authority.

---

## What was proved

The P3 `unknown_external_state` hole is closed: an unknown (or dangling `prepared`) Postgres write
receipt is resolved by an **exact, READ-ONLY lookup** of the fake PG-side
`effect_receipts(idempotency_key)` table — and the reconciler **never re-runs the write executor**.
This is the Postgres-shaped version of P13 correlation reconcile, keyed by the idempotency/effect-
receipt identity (not values), so the P7 same-value false positive is structurally impossible.

```text
unknown_external_state (or dangling `prepared`) write receipt
  → reconcile_postgres_unknown_write(... idempotency_key)        (READ ONLY)
      lookup_effect_receipt(idempotency_key):
        Found        → machine receipt upgraded to `committed`
        NotFound     → machine receipt upgraded to `permanent_failure`
        Unavailable  → stays `unknown_external_state`
  (never calls PostgresWriteAdapter::transact — no second mutation)
```

---

## Verify-first

P3 added the PG-side fake `effect_receipts` table (inside `FakePostgresWriteAdapter`) but **no
reconcile helper**. The live reconcile pattern read for this slice:

- `correlation::reconcile_unknown_by_correlation` (`src/correlation.rs:89`) — the P13 template:
  read the machine receipt, accept only `UnknownExternalState`/`Prepared`, resolve via a read-only
  resolver, and upgrade the receipt with `write_resolved` (clones the original value, changes only
  `state` + adds `reconciled`/`reconciled_by` → **authority & payload digests preserved** so a
  later `run_write_effect` replay still matches).
- `write::run_write_effect` replay semantics (`src/write.rs:239`) — a terminal receipt
  (`Committed`/…) with matching authority + payload digests is replayed; the executor is not
  re-entered.
- `recovery::recover_dangling_by_correlation` (`src/recovery.rs:87`) — the dangling-`prepared`
  reconcile shape (P19).

This card mirrors that template but keys the lookup by **idempotency key against the PG effect-
receipt table** (the card's required primary key), not by `correlation_id`.

---

## Files

| File | Purpose |
|------|---------|
| `igniter-machine/src/postgres_write.rs` | + `PostgresReceiptLookup`, `PostgresWriteReceiptResolver` (impl for `FakePostgresWriteAdapter`), `PostgresReconcileResult`, `reconcile_postgres_unknown_write`, `FakeWriteBehavior::CommitButLost`, `FakePostgresWriteAdapter::set_resolver_down` |
| `igniter-machine/tests/postgres_reconcile_tests.rs` | 7 tests — all acceptance bullets |
| `lab-docs/lang/lab-machine-postgres-reconcile-p4-v0.md` | this doc |
| `.agents/work/cards/lang/LAB-MACHINE-POSTGRES-RECONCILE-P4.md` | card + closing report |

No new `pub mod` (the reconcile lives in `postgres_write`); no change to `run_write_effect`,
`retry`, or `orchestrator`.

---

## Public API (added)

```rust
pub enum PostgresReceiptLookup {
    Found { correlation_id: Option<String>, target: String, key: String },
    NotFound,
    Unavailable(String),
}

#[async_trait]
pub trait PostgresWriteReceiptResolver: Send + Sync {
    async fn lookup_effect_receipt(&self, idempotency_key: &str) -> PostgresReceiptLookup;
}
impl PostgresWriteReceiptResolver for FakePostgresWriteAdapter { … }   // read-only; never mutates

pub enum PostgresReconcileResult {
    ResolvedCommitted, ResolvedPermanentFailure, StillUnknown,
    NotApplicable(WriteState), NoReceipt,
}

pub async fn reconcile_postgres_unknown_write(
    receipts: &Arc<dyn TBackend>,
    resolver: &dyn PostgresWriteReceiptResolver,
    clock: &Arc<dyn ClockProvider>,
    capability_id: &str,
    idempotency_key: &str,
) -> Result<PostgresReconcileResult, EngineError>;

// test-support on the fake: FakeWriteBehavior::CommitButLost (commit lands, ack lost),
// FakePostgresWriteAdapter::set_resolver_down(bool).
```

---

## Design decisions (per card)

1. **Resolver/read-back only.** `reconcile_postgres_unknown_write` takes a
   `&dyn PostgresWriteReceiptResolver`, NOT a `CapabilityExecutor`; it never calls `transact`.
   The fake's resolver impl touches only the `effect_receipts` map — never `attempts`/`business_rows`.
2. **Primary lookup key = idempotency / effect-receipt identity** (exact), not same-value matching.
   The looked-up `correlation_id`/`target`/`key` are recorded as evidence in the terminal receipt.
3. **Terminal mapping:** found→`committed`, not-found→`permanent_failure`, unavailable→stays
   `unknown_external_state`.
4. **Dangling `prepared` supported** — accepted alongside `unknown` (P19 shape).
5. **No business mutation** during reconcile — proven by `attempts`/`business_row_count` unchanged.
6. **No real DB** — fake adapter/resolver only.

---

## Proof results (7/7, `cargo test --no-default-features --test postgres_reconcile_tests`)

| Test | Proves |
|---|---|
| `unknown_with_pg_receipt_found_resolves_committed` | landed-but-unknown (`CommitButLost`) → found → `committed`; attempts/business rows unchanged; evidence (correlation/target/key) preserved |
| `unknown_with_no_pg_receipt_resolves_permanent_failure` | unknown + no effect receipt → `permanent_failure`; no mutation |
| `resolver_unavailable_keeps_unknown` | resolver down → `StillUnknown`; receipt stays `unknown_external_state` |
| `dangling_prepared_reconciled` | a planted `prepared` receipt + present effect receipt → `committed`; no transact |
| `recovered_committed_replays_without_re_executing` | reconciled-committed receipt replays via `run_write_effect` (executor not re-entered) |
| `same_value_different_key_no_false_positive` | identical values, different key → not-found → `permanent_failure`, while the genuinely-landed key → `committed` (identity, not value) |
| `committed_receipt_is_not_applicable_and_missing_is_no_receipt` | terminal receipt → `NotApplicable`; missing → `NoReceipt` |

Full suite green; no regression (postgres_reconcile = +7). Module compiled with no new warnings.

---

## Boundary findings

- **Compositional, not a new mechanism.** The reconcile reuses the P13 `write_resolved` upgrade
  shape (preserve every field, change only `state`), so a reconciled-committed receipt is a
  first-class terminal receipt that `run_write_effect` replays — proven end-to-end.
- **Read-only is structural.** The resolver trait has no mutating method; the fake's impl reads the
  `effect_receipts` map and never increments `attempts`. The "no second mutation" property is not a
  policy, it is the type.
- **Identity beats value.** Keying by idempotency key against the PG effect-receipt table is the
  exact per-request identity P13 introduced for HTTP — it closes the P7 same-value caveat for SQL
  too (`same_value_different_key_no_false_positive`).
- **`Unavailable` is honest.** A down resolver leaves the receipt `unknown` (no guess); a later
  reconcile attempt resolves it once the lookup is available again.

---

## Closed surfaces

| Surface | Status |
|---|---|
| Real Postgres / driver / network | Closed — fake adapter/resolver only |
| SQL execution / migrations / ORM | Closed |
| Re-running the write executor in reconcile | Closed — read-only resolver, no `transact` |
| `run_write_effect` / retry / orchestrator semantics | Unchanged |
| `TBackend` impl for Postgres | Closed — separate deferred track |
| Public / network / live | Closed |

---

## Next routes

- Real local Postgres remains a later **opt-in `postgres` feature + human gate** (`tokio-postgres`
  + pool; the read executor, write gate, and this reconcile are the three behaviours the real
  adapter must satisfy behind the same traits).
- A wire-path atomic gate (serving-loop follow-up) remains separate, before any yielding receipt
  backend.

---

*LAB-ONLY. No canon claim. No language authority. Lab evidence does not by itself create canon.*
