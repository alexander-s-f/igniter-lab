# igniter-machine operator console — design / readiness (P1, v0)

**Card:** `LAB-MACHINE-OPERATOR-CONSOLE-P1` · **Lane:** readiness / product-ops / operator UX
**Scope:** **design only.** No code, no UI, no live/staging, no new authority model, no daemon.

> **Authority & verify-first.** Source of truth = live code +
> [`igniter-machine/IMPLEMENTED_SURFACE.md`](../../igniter-machine/IMPLEMENTED_SURFACE.md),
> the P20 orchestrator (`src/orchestrator.rs`), the P23 observability projection
> (`src/observability.rs`), and the P25 hardening capstone. This doc designs an operator surface
> **over what already exists** — it invents no new effect behaviour. Whole-wave context:
> [`lab-machine-io-wave-digest-p1-v0.md`](lab-machine-io-wave-digest-p1-v0.md).

---

## 0. The one principle

**The facts are the console.** Every view is a *read-only projection* of fact stores
(`observe()` already does exactly this). Every operator *action* is a host call into the existing
P20 control loop — never a new mutation path, never a background daemon. The console adds
**presentation + safe triggering**, not capability.

```
Read  = project facts (observe / report / fact reads)  → never mutates
Act   = call an existing host entrypoint (boot / tick)  → writes an audit fact, nothing hidden
Gate  = compensate / reissue / live / credentials       → confirmation or out of scope
```

---

## 1. Minimum operator views (read-only)

All views below are projections of facts already written by the substrate. Backing source in
parentheses is the **real** function/store (verified).

| View | What it shows | Backing source |
|---|---|---|
| **Health summary** | one-line: committed / unknown / prepared(dangling) / dead-letters; retry-queue depth | `EffectOrchestrator::report()` → `OrchestratorStatus` + `observe()` |
| **Receipts by state** | counts: committed, denied, unknown, permanent_failure, retryable, prepared, aborted; + auth_refusals, secret_missing | `observe()` → `EffectMetrics` (from `__receipts__`) |
| **Dead-letter inbox** | total + grouped `by_reason` + entries `{key, kind, reason, correlation}` | `observe()` → `DeadLetterInbox` (from `__dead_letter__`, correlation joined from receipt) |
| **Retry queue** | intents by state: pending, exhausted, done, blocked, abandoned; due-at per intent | `observe()` (`__retry_queue__`); detail = `retry_queue` facts |
| **Unknown / reconcile status** | unknown receipts awaiting read-back / correlation resolution; what `boot()` would reconcile | `report().receipts_unknown` + `__receipts__` state=`unknown_external_state` |
| **Capsule pool / service route status** | pools, visibility (Production?), replica count per recipe, route→pool map, accepted recipes | `__recipes__`, pool/ACL facts (`coordination.rs`), route table |
| **Orchestrator boot/tick/report** | last boot/tick audit (scanned/committed/drained), current `report()` snapshot | `__orchestrator_audit__` + `report()` |

**Drill-downs (read-only):** a single receipt by key/correlation; the audit trail for a
`(route, duplicate_key)` from `__ingress_dedup__`; the coordination audit (`__coord_audit__`,
allowed **and** denied); messenger/escalation threads (`__messenger__`) if an operator is also a
participant.

### Fact stores the console reads (verified constants)
`__receipts__` · `__retry_queue__` · `__dead_letter__` · `__orchestrator_audit__` ·
`__ingress_dedup__` · `__recipes__` · `__coord_audit__` · `__messenger__` · `__transfers__`.

---

## 2. Actions safe from the UI (read or host-loop)

These are either pure reads or calls into the **already-existing** P20 loop. Each mutating one
writes an audit fact (no silent action). None is automatic.

| Action | Kind | Maps to | Note |
|---|---|---|---|
| View receipt / inspect correlation | read | fact read / correlation join | redacted facts only (§7) |
| Export evidence packet | read | bundle facts for a key/correlation/time-window → file | read-only snapshot; redaction enforced on export |
| Health / metrics refresh | read | `observe()` / `report()` | idempotent projection |
| **Boot sweep** | host-loop | `EffectOrchestrator::boot()` | reconciles dangling `prepared`/`unknown` (P19); **never re-executes** an effect; idempotent; dead-letters what stays unresolved; writes `boot` audit |
| **Tick now** | host-loop | `EffectOrchestrator::tick()` | drains **DUE** retry intents (P9); dead-letters exhausted/blocked; writes `tick` audit |
| Operator note / mark | annotate | append an operator note fact (e.g. `__operator_notes__`) | additive only; never edits an existing fact; carries operator subject |

> `boot` and `tick` are **safe** precisely because the substrate makes them safe: boot only reads
> back / reconciles (no executor param → cannot re-perform an effect), and tick only runs intents
> that are already DUE under the existing retry policy. The console exposes the trigger, not a new
> behaviour.

---

## 3. Actions that require confirmation or are OUT of scope

| Action | Disposition | Why |
|---|---|---|
| **Compensate** (reverse a committed effect) | **explicit + confirmation**; out of scope for v0 auto-UI | P12/P20: reversing a committed effect is a host decision, intentionally **not** loop-driven. A console may *surface* a compensation candidate but must require a typed confirmation + authority continuity (compensator digest must match original). |
| **Replay / reissue** an effect | **gated**, not a v0 button | re-issuing crosses the idempotency envelope; must go through the duplicate-policy path with an explicit fresh key, not an operator click. |
| **Live smoke** (real external endpoint) | **out of scope** | human-gated per P25; not a console capability at any tier. |
| **Credential changes** (vault, secret refs) | **out of scope** | secrets are env/file via `SecretProvider`; the console never reads, sets, or displays secret *values* (§7). |

Design rule: anything that **changes external-world state** or **authority** is either confirmation-
gated with full audit, or simply absent from v0.

---

## 4. Facts/projection vs live process state

| Comes from FACTS (durable, source of truth) | Comes from LIVE PROCESS (ephemeral, advisory) |
|---|---|
| receipt states, retry intents, dead-letters, audits, recipes, dedup history | in-flight single-flight locks held *right now* (`single_flight.rs` map) |
| everything `observe()` / `report()` returns | current listener bind / uptime / last-tick wall-clock |
| evidence packets, operator notes | live RocksDB open/health, queue drain currently running |

**Rule:** the console treats **facts as truth**; live process state is *advisory* (a hint that a
restart/recovery may be needed) and must be **labelled as ephemeral**, never persisted as if it
were a fact. After a crash, only the facts survive — the console must reconstruct entirely from
them (which is exactly what `boot()` + `observe()` already do).

---

## 5. First CLI / API shape (before any frontend)

A thin read/act surface over the existing functions. **CLI first** (scriptable, testable, no
frontend dependency); the same calls become a JSON API later. Illustrative shape only — not an
implementation spec.

```
# READ (pure projections)
opcon status                      # report() one-liner + observe() headline
opcon receipts [--state X]        # EffectMetrics; filter by state
opcon deadletters [--reason R]    # DeadLetterInbox grouped + entries
opcon retryqueue                  # intents by state + due-at
opcon receipt <key|correlation>   # single receipt drill-down (redacted)
opcon routes                      # recipes / pools / replica counts / route map
opcon export <key|correlation|--since T>   # evidence packet (redacted) → file

# ACT (host-loop; each writes an audit fact)
opcon boot                        # EffectOrchestrator::boot()
opcon tick                        # EffectOrchestrator::tick()
opcon note <key> "<text>"         # append operator note fact

# GATED (confirmation; not v0 default)
opcon compensate <receipt> --confirm   # explicit, authority-continuity checked
```

**API mapping:** `GET` for every READ verb (returns `observe().to_json()` / `report()` shapes);
`POST /boot`, `POST /tick`, `POST /note` for ACT (idempotent, audited); compensate stays a
separate, confirmation-bearing endpoint. The API is **a host boundary**, not an ingress — it does
not share the vendor-webhook hot path.

---

## 6. What must be visible for SparkCRM-like effects

For a domain executor (P15 `sparkcrm.rs`) the operator needs, per effect:

- **state + outcome** (committed / unknown / permanent_failure / retryable / aborted) and the
  **failure_kind** when present;
- **correlation_id** (first-class receipt field) — the join key for reconcile/lookup and the
  evidence packet;
- **duplicate context** — `(route, duplicate_key, attempt_index, decision)` from `__ingress_dedup__`
  (so an operator can see an auction's bounded-fresh attempts as distinct, intentional effects, not
  bugs — see the auction-policy card);
- **reconcile/compensation linkage** — whether an unknown was resolved by value (P7) or correlation
  (P13), and any `compensation_correlation_id`;
- **retry trail** — intent state + attempt count + due-at.

**Never visible:** the credential. The receipt stores only the secret *reference*
(`{{secret:sparkcrm_token}}`); the `Authorization` header is redacted at the executor before the
fact is written. The console therefore *cannot* leak it — but the export path must re-assert this.

---

## 7. Redaction & secret handling

- **Secrets never enter facts.** Receipts carry secret *references*, not values; HTTP/TLS executors
  redact `Authorization`/secret headers before writing the receipt (verified in `http.rs`/
  `sparkcrm.rs`). The console reads facts → already redacted.
- **The console never reads `SecretProvider` values.** No view, drill-down, or export resolves a
  `{{secret:...}}` reference. Secret *names* may appear (they are references); values must not.
- **Export must re-assert redaction.** An evidence packet is a fact snapshot; the export step
  applies a redaction pass (defence in depth) and records who exported what (operator subject +
  time) as an audit fact.
- **Operator notes are additive and attributed**, never edits to existing facts.

---

## 8. Minimal daily operator checklist

1. `opcon status` — committed up; **`prepared`/dangling = 0** (else a boot is overdue);
   dead-letters not growing.
2. If any dangling `prepared` or stuck `unknown`: `opcon boot` (idempotent recovery sweep),
   re-check `status`.
3. `opcon retryqueue` — pending draining, `due-at` not piling up. `opcon tick` if intents are due
   and the host cadence hasn't run.
4. `opcon deadletters` — triage by reason; for each, `opcon receipt <key>` → decide (note / escalate
   / gated compensate). Dead-letters should trend to zero, not accumulate.
5. Spot-check SparkCRM-like effects: correlation present, no unexpected `unknown`, auction
   attempts (if any) match the configured `bounded_fresh` limit.
6. Anything requiring **compensate / reissue / live / credentials** → stop, it's gated (§3).

---

## Boundary recap

- Read-only views vs mutating actions are **separated** (§1–§2 vs §3).
- Facts/projections are the **source of truth**; live process state is advisory (§4).
- Redaction/secret handling is explicit; the console cannot surface a credential (§6–§7).
- CLI/API surface is defined **before** any UI (§5).
- Compensation / reissue / live / credential actions stay **gated** (§3).
- No code, no UI, no daemon, no new authority. The console is a thin lens over P20 + P23.

*Design/readiness only. Stale docs cannot override live code + `IMPLEMENTED_SURFACE.md`.
Compiled 2026-06-16.*
