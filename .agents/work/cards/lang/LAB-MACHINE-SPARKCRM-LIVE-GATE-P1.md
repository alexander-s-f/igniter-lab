# Card: LAB-MACHINE-SPARKCRM-LIVE-GATE-P1 — SparkCRM live/staging smoke human-decision packet

> **Front door for the substrate:** [`LAB-MACHINE-CAPABILITY-IO-MILESTONE-P1`](LAB-MACHINE-CAPABILITY-IO-MILESTONE-P1.md).
> **This card** prepares the human gate that [`…-HARDENING-CAPSTONE-P25`](LAB-MACHINE-CAPABILITY-IO-HARDENING-CAPSTONE-P25.md)
> and [`LAB-MACHINE-DEPLOYMENT-TOPOLOGY-P1`](LAB-MACHINE-DEPLOYMENT-TOPOLOGY-P1.md) both name as their next step.

**Lane:** formal / readiness / human-gate · **Skill:** idd-agent-protocol
**Status: DECISION PACKET PREPARED — NOT EXECUTED.** 2026-06-16. No code, no live traffic, no
credentials, no SparkCRM mutation, no deployment.

---

> # ⛔ NOT EXECUTABLE BY AGENT
> The deliverable is a document for **Alex** to decide on a future first live/staging SparkCRM smoke.
> An agent MUST NOT execute live traffic, create/fetch credentials, call real SparkCRM, mutate
> staging/prod, or deploy. The smoke is authorized **only** by the verbatim human approval text
> (packet §10) signed by **Alex**. Until then every live surface here is **closed**.

## One truth

```
Correctness model (P1–P15):          DONE   — evidence
In-lab production hardening (P18–P24): DONE  — evidence
Live external runtime:               NOT DONE, NOT AUTHORIZED — human-gated only
```

Authority ≠ evidence. A green local suite is not live readiness. **Decision authority: Alex only.
Agent authority: prepare the decision packet only.**

## Deliverable

- **Packet:** [`lab-docs/lang/lab-machine-sparkcrm-live-gate-p1-v0.md`](../../../lab-docs/lang/lab-machine-sparkcrm-live-gate-p1-v0.md)
  — answers all 10 gate questions, grounded in the live surface (P14/P15/P21/P22/topology):
  1. **Endpoint class** — prod-shadow read-only **first**, then sandbox/staging for a write; never
     prod-write first.
  2. **Credential** — bearer token as a `{{secret:sparkcrm_token}}` reference, env-allowlist / safe-file
     (P22); never raw, never in a fact. Names only, no values.
  3. **Allowlist/TLS/cert** — staging FQDN only, https-only, rustls (`--features tls`), CertInvalid→permanent,
     no redirect-follow (P14/P14-impl).
  4. **Smallest action** — `GET /status` (read-only) first; create→cancel test lead only after re-approval.
  5. **Blast radius/rollback** — read=none; create=one test record on a test tenant, rollback via
     `/cancel` (P12); exactly-one (P18) + replay-no-resend + single-replica-no-fanout.
  6. **Evidence** — EffectReceipt (redacted) + correlation_id + audit fact + transaction_time +
     ObservabilitySnapshot (P23) + `.igm` checkpoint, before & after.
  7. **Operator checks** — before/after checklists (backup, allowlist, scoped secret, signed passport,
     one process/one RocksDB, redaction, rollback reachable).
  8. **Abort conditions** — non-allowlisted/prod host, CertInvalid, redirect, missing secret, untrusted
     passport, mutation>1/fanout, unreconcilable unknown, auth-in-fact, durability error, clock jump.
  9. **Unproven after success** — prod load, multi-process/HA, real vault, PKI/OAuth, ingress threat
     review, runbook, rocksdb durability at scale, cert/cred rotation, multi-tenant.
  10. **Approval text** — verbatim block, Alex-only, naming endpoint/host/action/credential/abort.
- **This card** (route + status).

## Authority

- Evidence: P15 SparkCRM local-TLS capstone, P25 hardening capstone, P17 meta audit, deployment
  topology P1, P14/P21/P22.
- Decision authority: **Alex only.**
- Agent authority: **prepare the decision packet only** — done.

## Acceptance (met)

- [x] "NOT EXECUTABLE BY AGENT" banner (card + packet).
- [x] Required secrets listed **by name, no values** (`sparkcrm_token`).
- [x] Exact preconditions for human approval named (§7 before-checklist + §10 signed block).
- [x] Minimal smoke plan + abort plan defined.
- [x] Evidence packet expected after smoke defined.
- [x] Live/staging execution kept **out of scope**.
- [x] P17/P25 references point at this gate; no P17/P25 content rewritten beyond the pointer.

## Closed surfaces (held)

No code changes · no live network calls · no credential creation · no SparkCRM staging/prod mutation
· no deployment · no claim that live readiness is achieved.

## Anti-drift

- Do NOT open the live smoke as the next card — it is human-gated; only Alex's §10 text authorizes it.
- This packet is **evidence for a decision**, not the decision. Preparing it changed nothing executable.
- The first authorized rung is a read-only `GET /status`; create→cancel is a **separate** gate.

## Next routes (human-owned)

- Alex reviews the packet → signs §10 (or declines / narrows) → operator runs the read-only rung →
  evidence packet → separate gate for the write rung.
- Optional: a gov portfolio pointer if/when this becomes an actioned gate artifact (currently a
  prepared packet, not yet a gate decision — no portfolio entry created by this card).

## Governance

Packet lives in `igniter-lab/lab-docs/lang/`. Card in `igniter-lab/.agents/work/cards/lang/`.
Gov portfolio pointer deferred until the gate is actually exercised (axiom: smallest artifact that
prevents drift — a prepared-but-unsigned packet does not yet warrant a gov gate entry).
