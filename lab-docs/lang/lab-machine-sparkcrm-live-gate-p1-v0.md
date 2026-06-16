# lab-machine-sparkcrm-live-gate-p1-v0 — SparkCRM live/staging smoke: HUMAN-DECISION PACKET

**Card:** `LAB-MACHINE-SPARKCRM-LIVE-GATE-P1`
**Lane:** formal / readiness / human-gate
**Status:** DECISION PACKET — prepared for a human gate. **NOT a continuation of any engineering
wave.** No code, no live traffic, no credentials, no SparkCRM mutation were produced by preparing
this document.

---

> # ⛔ NOT EXECUTABLE BY AGENT
>
> This packet exists so a **human (Alex)** can decide whether a future first live/staging SparkCRM
> smoke may run. An agent reading this MUST NOT treat it as a runnable plan. An agent may not:
> execute live traffic, create or fetch credentials, call any real SparkCRM endpoint, mutate any
> production/staging system, or deploy. The only action a future live smoke is authorized by is the
> **verbatim human approval text in §10**, pasted/signed by Alex. Until that exists, every action
> below is **closed**.

---

## 0. Why this packet exists (provenance, not authority)

The capability-IO substrate is proven **in the glass box** across two stopped waves:

- **Correctness model P1–P15** — front door [`LAB-MACHINE-CAPABILITY-IO-MILESTONE-P1`](../../.agents/work/cards/lang/LAB-MACHINE-CAPABILITY-IO-MILESTONE-P1.md);
  capstone [`…-CAPSTONE-P15-CHECKPOINT`](../../.agents/work/cards/lang/LAB-MACHINE-CAPABILITY-IO-CAPSTONE-P15-CHECKPOINT.md).
  P15 is the SparkCRM-shaped domain executor proven against a **local fake** SparkCRM TLS upstream
  ([`lab-machine-capability-sparkcrm-executor-p15-v0`](lab-machine-capability-sparkcrm-executor-p15-v0.md)).
- **In-lab production hardening P18–P24** — capstone [`…-HARDENING-CAPSTONE-P25`](../../.agents/work/cards/lang/LAB-MACHINE-CAPABILITY-IO-HARDENING-CAPSTONE-P25.md)
  (atomic gate / durable recovery / orchestrator / signed authority / secrets / observability / load).
- **Deployment topology (design only)** — [`lab-machine-deployment-topology-p1-v0`](lab-machine-deployment-topology-p1-v0.md),
  which explicitly names *"a live-gate packet (gathers this + the P25 deltas for a human decision —
  NOT agent-executed)"* as its next step. **This is that packet.**

Per the IDD axiom *Authority ≠ evidence*: every artifact above is **evidence**, not authorization.
A green local suite does not make a live smoke safe. **Live/staging readiness is explicitly NOT
inferred.** Decision authority is **Alex only**.

The honest state carried forward from P25:

```
Correctness model:           DONE  (P1–P15)
In-lab production hardening:  DONE  (P18–P24)
Live external runtime:        NOT DONE, NOT AUTHORIZED — human-gated only
```

---

## 1. Q1 — Endpoint class for the first smoke

**Recommendation: start prod-shadow READ-ONLY, then sandbox/staging for a write — never prod-write
first.** Two rungs, gated separately:

| rung | endpoint class | why |
|---|---|---|
| **1 (recommended first)** | **prod-shadow or sandbox `GET /status`** (read-only) | Exercises only the `CorrelationResolver`/`lookup` path. Maps to the P14 **read-only external profile** (allowlist + https-only + **mutations forbidden before send**). Zero records created. Lowest possible blast radius. |
| **2 (only after rung 1 passes + re-approval)** | **dedicated SANDBOX or STAGING tenant**, full forward+compensate (`POST /leads`, `POST /leads/{id}/cancel`) | A write requires the mutations-allowed SparkCRM profile — must NOT touch a production tenant. A sandbox/test tenant bounds the blast radius to disposable test records. |

**Explicitly rejected for the first smoke:** production-write. A first live mutation against a real
customer tenant is out of scope at this gate regardless of approval text — escalate as a separate
decision if ever needed. *(Grounding: P14 external profile is read-only by design; P15's
mutation-allowed path was only ever run against a local fake.)*

---

## 2. Q2 — Credential shape and where it lives

**Shape:** a single SparkCRM API bearer token / API key, scoped **least-privilege** to the chosen
tenant (read-only for rung 1; create+cancel test-lead only for rung 2).

**Mechanism (already built, P22):** the token is a **secret REFERENCE** in the contract input —
`{{secret:sparkcrm_token}}` — resolved at the host boundary by a `SecretProvider`. It is **never**
a raw token in a contract, and is **redacted from every receipt / audit / result / error fact**
(proven end-to-end in P22, P10/P11).

**Where it lives (operator-provisioned, one of):**

- `EnvSecretProvider` — process env var, **allowlist only** (`allow("sparkcrm_token", "SPARKCRM_TOKEN")`).
  A name not on the allowlist resolves to `None`.
- `FileSecretProvider` — `root/sparkcrm_token`, **path-traversal-safe** root.
- `LayeredSecretProvider` — env over file; a real external vault plugs in as another layer (future,
  not built).

**Required secrets (NAMES ONLY — no values appear in this packet or any fact):**

| logical name | provider key / path | scope required |
|---|---|---|
| `sparkcrm_token` | env `SPARKCRM_TOKEN` **or** file `<secret_root>/sparkcrm_token` | rung 1: read `/status` only · rung 2: create + cancel test lead on the test tenant only |

The operator provisions this **outside the glass box** (env var / mounted secret dir). Issuer keys
and the token are operator host-config, never committed, never in a contract. **A missing secret
refuses before send** (no transport call) — proven in P22.

---

## 3. Q3 — Allowlist / TLS / cert assumptions

All must be satisfied **before** any connect (grounding: P14 external policy + P14-impl real TLS):

- **Host allowlist** must contain the **exact** staging/sandbox FQDN and nothing else for this
  smoke. A non-allowlisted host is **refused before DNS/connect/send** → `permanent_failure`. The
  production host must NOT be on the allowlist for a rung-1/rung-2 smoke.
- **Scheme: https only.** Plain `http` → permanent before send.
- **TLS transport:** the real rustls transport (`--features tls`, P14-impl), offline-cached crates.
- **Cert validation:** a bad/untrusted certificate → `HttpTransportError::CertInvalid` →
  `permanent_failure` (a **security refusal, never retried**). Confirm the staging cert chains to a
  root in the rustls root store, OR pin the staging CA explicitly.
- **Redirects:** 3xx is **not** auto-followed → `permanent_failure` (prevents allowlist escape /
  credential leak).
- **Transient TLS/DNS/connect** → `retryable` (request never reached the server → no mutation).
- **DNS:** the staging FQDN must resolve from the smoke host.

**Must be confirmed by the operator before approval:** exact FQDN, port 443, trusted-root or pinned
CA, and that no production host is reachable through the configured allowlist.

---

## 4. Q4 — Smallest live action

Ranked smallest-first; **the smoke starts at the top and escalates only on success + re-approval:**

1. **`GET /status?correlation_id=<test-id>`** (RECOMMENDED FIRST) — read-only `lookup`. Resolves
   `Landed (200)` / `NotFound (404)` / `Unavailable`. **Zero mutation.** Proves the real wire,
   real TLS handshake, allowlist, secret resolution, redaction, and receipt — with no record
   created.
2. **Create one test lead** — `POST /leads` on a sandbox/test tenant → one `run_write_effect_atomic`
   → one receipt. Bounded to a single disposable record.
3. **Compensate** — `POST /leads/{id}/cancel` (id read from the forward receipt body) → `aborted`
   receipt. **Host-decided, NOT automatic.** Run immediately after step 2 to clean up.

A **dry-run** (the executor refusing a non-allowlisted host / plain-http / mutation-in-read-profile
**before send**) is already proven locally and requires **no live action** — it is a precondition
check, not a smoke step.

**Recommendation: the first authorized smoke is action 1 only.** Treat 2→3 as a separate gate.

---

## 5. Q5 — Blast radius and rollback path

| action | blast radius | rollback |
|---|---|---|
| `GET /status` | one read request + one receipt fact; no external state changed | none needed |
| create test lead | **one** test record on the **test/sandbox** tenant | compensating `POST /leads/{id}/cancel` (P12), host-driven; id from the forward receipt |
| compensation | turns the created lead to cancelled; writes an `aborted` receipt | terminal |

**Multiplication guards (already enforced):**

- **Exactly-one effect** under concurrency — per-key in-process `SingleFlight` (P18); a 2000-way
  same-key storm held exactly-one (P24).
- **Replay never re-sends** (P1/P6) — a retried request reads the prior receipt.
- **Single replica → never fanout** — a served effect funnels through ONE replica → ONE effect
  (coordination guardrail). Pool/activation scaling never multiplies downstream effects.
- **One effect-process / one RocksDB** (topology §1) — the deployment unit for the smoke.

**Before the smoke:** snapshot the RocksDB `data_dir` and take a `checkpoint(.igm)` (topology §6) so
the receipt spine has a clean point-in-time restore.

---

## 6. Q6 — Receipts, correlation IDs, audit facts to capture

For **every** smoke action, capture (all are existing first-class facts):

- the **`EffectReceipt`** (bitemporal fact in `__receipts__`): capability + idempotency key, the
  **status-taxonomy outcome** (200→committed / 4xx→permanent / 5xx-on-POST→unknown / 429→retryable),
  and **redacted** auth (`Authorization`/`Cookie` never present);
- the **`correlation_id`** (recorded first-class, P11/P13) — the join key across forward / lookup /
  compensate;
- the **`transaction_time`** from the injected host clock (P4);
- the **audit fact** for the ingress/serve path (passport subject, route, dedup decision);
- for a create→cancel: the forward receipt **and** the `aborted` compensation receipt;
- an **`ObservabilitySnapshot`** (P23) before and after: effects-by-state, retries, dead-letters,
  unknowns, secret-missing count;
- a `checkpoint(.igm)` before and after (portable, byte-identical point-in-time image).

This bundle **is** the evidence packet expected after the smoke (§ Evidence packet below).

---

## 7. Q7 — Operator checks before and after

**Before (all must pass, else do not approve):**

- [ ] RocksDB `data_dir` backed up; `checkpoint(.igm)` taken.
- [ ] Allowlist contains **only** the staging/sandbox FQDN; production host **not** reachable.
- [ ] Secret `sparkcrm_token` provisioned via env-allowlist or safe file root; **scoped** to the
      smoke action + test tenant; value never echoed.
- [ ] Passport **signed** by a trusted issuer key (P21); verifier loaded with that key; scope
      bound to the smoke capability; not expired/revoked.
- [ ] Redaction confirmed (a dry local effect shows no auth value in any fact).
- [ ] **One** effect-process / one RocksDB / one listener (topology §1); no second process on the
      same data dir.
- [ ] Host clock NTP-synced (audit window sanity; idempotency is identity-keyed regardless).
- [ ] Ingress duplicate policy set deliberately (default = safe dedup).
- [ ] Rollback endpoint (`/leads/{id}/cancel`) reachable on the same allowlisted host (rung 2 only).

**After:**

- [ ] Read receipt + correlation_id + audit fact; confirm outcome matches the expected taxonomy.
- [ ] Confirm **no** auth value in any receipt/audit/result/error.
- [ ] Confirm **exactly-one** (server-side request count if observable; else receipt count == 1).
- [ ] `observe()` snapshot reviewed (no unexpected dead-letters/unknowns).
- [ ] rung 2: confirm the cancel landed (`aborted` receipt) and the test lead is gone.
- [ ] `checkpoint(.igm)` taken; both snapshots archived with the evidence packet.

---

## 8. Q8 — Conditions that abort the smoke immediately

Abort = **stop the serve loop, do NOT `tick()`/retry, triage the dead-letter inbox, hand to human.**

- any attempt to reach a **non-allowlisted host**, or the **production host**;
- `CertInvalid` / any cert-validation failure;
- a **3xx redirect** observed;
- a **missing secret**, or a secret resolving from a non-allowlisted source;
- an **untrusted / expired / revoked / wrong-scope passport** refusal;
- an observed mutation count **> 1**, or any **fanout** of a served effect;
- an **`unknown_external_state`** that `GET /status` cannot reconcile;
- any **auth value appearing in a fact**;
- a RocksDB write / durability error, or a detected second effect-process on the data dir;
- a large backward **clock jump** during the window.

---

## 9. Q9 — What remains UNPROVEN after a successful smoke

One green smoke proves the wire to **one** real endpoint **once**. It does **NOT** prove:

- sustained **production load** against the real API (real rate limits, latency tails, throttling);
- **multi-process / HA** — P18 exactly-one is **in-process**; the constraint is **one
  effect-process per RocksDB**. Horizontal effect scale needs a distributed lock / backend-CAS
  slice (not built);
- a **real vault** — secrets are still env/file (no external secret service integrated);
- **PKI / OAuth / JWT** authority — passport is still a local blake3 keyed-hash MAC (no asymmetric);
- a **public-ingress threat review** — auth surface, rate/cost abuse, DoS, input validation at
  scale (never done);
- an **operational runbook** — on-call, dead-letter triage at scale, rollback rehearsal;
- **RocksDB durability** (`.mpk` log) fsync/consistency semantics under real failure + backup
  cadence on real data;
- **cert pinning / rotation** and credential rotation procedures;
- **multi-tenant partitioning** (one RocksDB + key space per tenant — designed, not exercised live).

A successful smoke advances exactly one bit: *"the proven substrate wired to one real SparkCRM
endpoint and behaved as the glass-box model predicted, once."* Nothing more is inferred.

---

## 10. Q10 — Required human approval text (verbatim, Alex only)

No live action is authorized until **Alex** records the following, filled in, in this card or the
gov gate artifact. An agent may **not** fill, paste, or act on this on Alex's behalf.

```
LIVE-SMOKE AUTHORIZATION — LAB-MACHINE-SPARKCRM-LIVE-GATE-P1

I, Alex, authorize a single SparkCRM smoke with these exact bounds:
  Endpoint class : <prod-shadow read-only | sandbox | staging>   (NOT production-write)
  Exact host     : <FQDN>            (allowlist = this host only)
  Action         : <GET /status only | create+cancel one test lead on tenant <id>>
  Credential     : secret name `sparkcrm_token`, source <env SPARKCRM_TOKEN | file <root>/sparkcrm_token>,
                   scoped least-privilege to the action above
  Abort authority: any condition in §8 aborts immediately; I accept the §9 unproven list.
  Operator       : <name>      Window: <UTC start–end>      Date: <YYYY-MM-DD>

Signed: Alex
```

Absent this exact, filled block signed by Alex, the smoke is **closed**.

---

## Minimal smoke plan (for the human to evaluate — not an agent runbook)

1. Operator completes the §7 *before* checklist; backs up RocksDB + `.igm`.
2. Alex signs §10 (rung 1: `GET /status` only).
3. Operator runs **one** `GET /status?correlation_id=<test-id>` against the allowlisted staging host.
4. Operator captures the §6 evidence bundle; runs the §7 *after* checklist.
5. **Stop.** rung 2 (create→cancel) is a **separate** §10 approval after rung 1 evidence review.

## Abort plan

On any §8 trigger: stop the serve loop, do **not** `tick()`/retry, capture the receipt + audit +
`observe()` snapshot of the failure, dead-letter the item, restore from the pre-smoke `.igm` if any
dangling `prepared` remains (boot's recovery sweep reconciles read-back-able effects), and hand the
evidence to Alex. No automatic compensation; no blind retry.

## Evidence packet expected after a smoke

A single archived bundle: pre/post `ObservabilitySnapshot` JSON · the `EffectReceipt`(s) (redacted)
· the `correlation_id`(s) · the ingress/serve audit fact(s) · pre/post `checkpoint(.igm)` · the
filled §10 authorization · operator before/after checklists · a one-line outcome vs. the predicted
taxonomy. This bundle is **evidence for the next gate decision**, not authority to widen scope.

---

## Closed surfaces (held by this packet)

No code changes · no live network calls · no credential creation · no SparkCRM staging/prod mutation
· no deployment · **no claim that live readiness is achieved.** Preparing this packet changed nothing
executable.

## References (evidence only — not authority)

- Front door: [`LAB-MACHINE-CAPABILITY-IO-MILESTONE-P1`](../../.agents/work/cards/lang/LAB-MACHINE-CAPABILITY-IO-MILESTONE-P1.md)
- Correctness capstone: [`…-CAPSTONE-P15-CHECKPOINT`](../../.agents/work/cards/lang/LAB-MACHINE-CAPABILITY-IO-CAPSTONE-P15-CHECKPOINT.md)
  · domain executor [`lab-machine-capability-sparkcrm-executor-p15-v0`](lab-machine-capability-sparkcrm-executor-p15-v0.md)
- Hardening audit/order: [`…-PRODUCTION-HARDENING-P17`](../../.agents/work/cards/lang/LAB-MACHINE-CAPABILITY-IO-PRODUCTION-HARDENING-P17.md)
- Hardening capstone / gate: [`…-HARDENING-CAPSTONE-P25`](../../.agents/work/cards/lang/LAB-MACHINE-CAPABILITY-IO-HARDENING-CAPSTONE-P25.md)
- Operational shape: [`lab-machine-deployment-topology-p1-v0`](lab-machine-deployment-topology-p1-v0.md)
- Security: [`…-SIGNED-PASSPORT-P21`](lab-machine-capability-io-signed-passport-p21-v0.md) ·
  [`…-SECRET-PROVIDER-P22`](lab-machine-capability-io-secret-provider-p22-v0.md)
- External/TLS policy: [`…-HTTP-EXTERNAL-P14`](lab-machine-capability-http-external-p14-v0.md) ·
  [`…-HTTP-TLS-P14-IMPL`](lab-machine-capability-http-tls-p14-impl-v0.md)
