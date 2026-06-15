# Card: LAB-MACHINE-BITEMPORAL-AXIS-P1 — bitemporal axis (decided B + IMPLEMENTED)

**Status: DECIDED (route B) + IMPLEMENTED 2026-06-15.** Design below; decision +
implementation summary at the bottom. Follows the time-travel correctness fix in
`LAB-MACHINE-PRESSURE-P1` (cycle 4).

> **Decision (Meta-Architect): route B.** `read_bitemporal(store, key, valid_at, known_at)`
> — both axes explicit. `read_as_of` stays the transaction-time alias (frozen).
> `valid_time = None` → **excluded** under valid-axis queries (no silent inference).
> Implemented this card (the fix was adjacent; not left at design). See closure below.

## Current semantics (FIXED — transaction-time axis only)

`Fact { transaction_time: f64, valid_time: Option<f64>, … }` (igniter-tbackend `fact.rs`).

- **transaction_time** = when the system *recorded / knew* the fact. This is the
  **audit / as-of-knowledge** axis: "what did we know as of T".
- **valid_time** = when the fact is *true in the domain* (the effective axis). It is
  **stored on every fact but never queried** today.

Query surface today (igniter-tbackend `timeline.rs`, used by the machine):
- `read_as_of(store, key, as_of)` → the fact with **max transaction_time ≤ as_of**.
- `facts_for(store, key, since, as_of)` → facts in the **transaction_time** window.

Both are now **order-independent** (linear scan, not `partition_point`) — correct under
out-of-order ingestion (backfills, corrections, replays). `read_as_of` = transaction-time
travel; its audit meaning ("what did we know at T") must NOT be diluted.

## The gap: the second axis is unexercised

`valid_time` is carried but no query filters on it. Real bitemporal use (the SparkCRM
case) needs both: e.g. a correction recorded **today** (`transaction_time = now`) for a
balance that was true **last month** (`valid_time = last month`). "As-of-knowledge"
alone cannot answer "what was actually true on date D, as best we know now".

## Design decision (the point of this card)

**Do NOT overload a single `as_of`.** A single ambiguous parameter is exactly what makes
agents conflate the axes. Make the axis **explicit**. Two candidate shapes:

- **A — two named methods.** Keep `read_as_of` (transaction-time, unchanged) and add
  `read_valid_as_of(store, key, valid_at, known_at: Option<f64>)`.
- **B — one bitemporal query.** `read_bitemporal(store, key, valid_at: Option<f64>,
  known_at: Option<f64>)`: `known_at=None` → latest knowledge; `valid_at=None` →
  transaction-time-only (= current `read_as_of`). One method, both axes explicit.

**Recommendation: B** (one bitemporal query, both axes explicit, optional) — it
generalizes the current behavior as a special case and reads unambiguously, while a thin
`read_as_of` stays as the transaction-time convenience alias.

### v0 semantics to lock

- Facts carry a single `valid_time` **point** (not an interval) in v0.
- Bitemporal query = among facts with `transaction_time ≤ known_at`, pick the one with
  **max `valid_time ≤ valid_at`** (facts lacking `valid_time` are excluded from valid-axis
  queries, or fall back to transaction_time — decide at impl).
- `read_as_of` semantics are FROZEN (audit). The new axis is additive.

## Must-answer before implementation

- [ ] A (two methods) vs B (one bitemporal query) — recommend B.
- [ ] Naming: `valid_at` / `known_at` (explicit) — avoid the bare word `as_of`.
- [ ] Facts with `valid_time = None` under a valid-axis query: exclude, or treat
  `valid_time := transaction_time`?
- [ ] Interval vs point valid_time (v0 = point; interval is a later card).
- [ ] MCP `time_travel` / `query_facts` tool param names must mirror the chosen axes.

## Closed (this card)

- No implementation; no change to `read_as_of` transaction-time meaning; no interval
  model; no valid_time index/perf work; no canon claim.

## Closure — implemented 2026-06-15 (route B)

- `TBackend::read_bitemporal(store, key, valid_at: Option<f64>, known_at: Option<f64>)` —
  a **default trait method** over `facts_for`, so all backends (in-memory, RocksDB,
  remote-TCP) get it for free (`igniter-machine/src/backend.rs`). `IgniterMachine::read_bitemporal`
  delegates (`machine.rs`). `read_as_of`/`read_fact` UNCHANGED (transaction-time).
- Semantics: `known_at` → `transaction_time ≤ known_at`; `valid_at` → among those, facts
  with `valid_time ≤ valid_at` (None excluded), pick **max valid_time, tie-break max
  transaction_time** (latest correction). `valid_at = None` → transaction-time latest.
- Proof `test_machine_bitemporal_valid_axis` (correction scenario): valid@15/known@100→105
  (correction known), valid@15/known@30→100 (pre-correction), valid@25→200, valid@5→None,
  valid_at=None→105. **9/9 machine tests pass.**

### Deferred (later cards)

- Interval valid_time (v0 is a point); `valid_policy: declared_only | fallback_to_tx`.
- MCP `time_travel` / `query_facts` tool params should mirror `valid_at` / `known_at`
  (do when MCP-live is exercised).
