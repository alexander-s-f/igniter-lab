# TBackend — Team Onboarding (read this first)

You are not being asked to adopt a new database. You are onboarding to TBackend as **two things**:

1. **A reference fact-contract** — the shape our Hub-style ledgers should be *designed toward* from
   day one, even while they run on Postgres. Design to this contract now and the eventual substrate
   swap is an adapter change, not a rewrite.
2. **The future engine** for the Hub's fact-log — introduced later, as a *shadow*, and promoted to
   authority only after convergence evidence.

So the goal of this onboarding is not "learn to operate a new DB." It is: **internalize the fact
contract, so every ledger/receipt/projection we design minimizes the delta to TBackend.**

---

## The 30-minute path

1. **Run it (10 min).** [`tbackend-team-quickstart.md`](tbackend-team-quickstart.md) — start the daemon,
   write a fact, do a point-in-time read, list by `seq`, follow lineage. Touch it before you theorize.
2. **Internalize the fact contract (10 min).** The section below, backed by
   [`technical_architecture.md`](technical_architecture.md). This is the part you carry into every
   design review.
3. **See it work on a domain (10 min).** [`example-usecase.md`](example-usecase.md) +
   `examples/availability_ledger.py` — a bitemporal availability ledger, end to end.

By role, go deeper:

| Role | Then read |
| --- | --- |
| Hub / backend | `technical_architecture.md` (fact contract, `seq_id`, group-commit, compaction) + the foundation audit (honest gaps) |
| Infra / devops | `deployment.md` + `docker.md` (systemd, loopback, durability knobs) |
| Anyone evaluating fit | README **Current fit** + **Promotion path** |

---

## The fact contract — the design target

Every durable thing we write should be expressible as a **fact** with these fields. Carry this into
every Hub table you design — if your row can't map to this, ask why.

| Field | Meaning | Why it matters |
| --- | --- | --- |
| `id` | **deterministic / derived** from the domain event (e.g. `store:record:event:source_version`) | idempotency — a retry re-sends the same id and collapses to a replay, never a duplicate. **Never put wall-clock in the id.** |
| `store` | the partition / stream (≈ one of our ledger or receipt tables) | isolates one fact family |
| `key` | the entity the fact is about | point lookups |
| `value` + `value_hash` | the payload + its canonical hash | integrity; content-dedup; parity checks |
| `transaction_time` | when we **recorded** it (evidence time) | audit: "what did we know, and when" |
| `valid_time` | when it is **true in the domain** | correct history under backfills/corrections — bitemporal |
| `seq_id` | server-assigned monotonic **ordering authority** | clock-free ordered replay — correct even under skew/backfill |
| `causation` / `correlation` | what caused this fact | lineage / explainability |
| `schema_version`, `producer` | evolution + provenance | safe change over time |

Write path: **`write_fact_once`** → `Inserted` | `Replay` (same id+content) | `Conflict` (same id,
different content). Durability: `accepted` (survives process crash) or `durable` (survives power loss).

Read path: **`facts_by_seq`** (clock-free ordered — use this for replay/audit, *not* `ORDER BY
timestamp`) and **`latest_for(as_of:)`** (time-travel to any past coordinate).

---

## Why a ledger (the 60-second case)

A mutable `UPDATE`-in-place row answers only *"what is true now."* A fact ledger answers four
questions a coordinator/audit system actually needs — and can't fake after the fact:

- **What is true now** — the latest fact per key (same as a normal read).
- **What was true at time T** — `as_of` time-travel, no snapshot tables.
- **In what order did it happen** — `seq_id`, independent of clock skew.
- **Why did it happen** — causation/lineage, and content-hash integrity that a mutable row destroys on
  every overwrite.

For a Hub whose top requirement is **auditability**, that's the whole point: the log *is* the audit,
projections are disposable working copies rebuilt from it.

---

## Honest maturity (don't oversell it to yourself)

- **Shadow-ready candidate, not production authority.** The primitives (idempotent durable write,
  `seq` ordering, group-commit ack, safe compaction, recovery) are built and tested; some foundation-
  audit items remain. See the audit before you lean on it.
- **Do not put money-truth on it.** Lago stays the source of money. TBackend's first job is the
  **coordination fact-log** (events / decisions / receipts) — audit, not balances.
- The "not-production / frontier" language is deliberate caution, **not** a verdict that it's a toy.
  The path is lab → shadow → convergence gate → promotion. We walk it on evidence, per store.

---

## Where this goes next

The adoption arc is **Reference → Mirror → Shadow → Converge → Swap**:

- **Reference / Mirror** — design Hub facts to the contract above (this doc).
- **Shadow → Converge → Swap** — run TBackend beside Postgres, prove parity, flip the substrate per
  store behind a convergence gate. That trajectory + the `LedgerStore` seam + the convergence
  checklist live in the Hub-side doc: **`Hub ledger: design-to-TBackend + shadow→swap`**.

You don't adopt TBackend. You design as if you already had, run it in the shadow, and let the evidence
decide when to flip.
