# LAB-IGNITER-WEB-LIVE-BIND-GATE-DECISION-READINESS-P35

Date: 2026-06-28
Status: DONE
Route: standard / main-audit / igniter-web / live-bind gate
Implements: audit-control-board row A10 (loopback-to-live gate) — decision step
Depends-On: `LAB-IGNITER-WEB-HOST-LIVE-BIND-CHECKLIST-PARSE-P34`,
`lab-docs/lang/lab-igniter-server-live-bind-tls-checklist-readiness-p33-v0.md`,
`LAB-IGNITER-SERVER-LIVE-BIND-GATE-P31`, `LAB-IGNITER-WEB-LIVE-BIND-GATE-WIRING-P32`

This packet is lab evidence and a gate **decision**, not authority to bind. It does not
create canon language authority, does not open a public/non-loopback listener, does not
implement TLS transport, and does not change `.igweb`, app code, VM, compiler, machine,
home-lab, SparkCRM, or private governance files. **No code changed in this card** — it is a
readiness/decision packet only.

## TL;DR decision

**HOLD public-bind enablement. PROCEED with a defined authority chain.** A complete parsed
`[host.live_bind]` checklist is an operator *assertion of intent*, not bind authority
(IDD axiom 2: authority is not evidence). Before any non-loopback listener may be
demonstrated, the host must (a) convert config → server `LiveBindChecklist` whose booleans
are set from **host-verified runtime state**, not copied from operator claims; (b) wire a
**durable** signed-passport verifier at the inbound request seam; (c) assert a TLS decision
(`terminated_upstream` only for the first proof); and (d) obtain an explicit **human
approval** marker. The next implementation card is a *dry-run verdict* surface that never
binds non-loopback.

## 1. Live surface characterization (verify-first)

Re-verified against live source on 2026-06-28:

| Surface | Live fact | File |
| --- | --- | --- |
| Pre-bind gate | `authorize_bind(addr, checklist)` is **pure** — opens no sockets, reads no config. Loopback ⇒ `Ok(None)`; non-loopback + `None` ⇒ `non_loopback_without_checklist`; non-loopback + complete checklist ⇒ `Ok(LiveBindToken)`. | `server/igniter-server/src/serving_gate.rs` |
| Checklist type | `LiveBindChecklist { signed_passport_path_wired: bool, body_cap_enabled, read_timeout_enabled, fail_closed_auth_enabled, inbound_tls_mode: Option<InboundTlsMode>, operator_signoff }`. All fields `pub` (IgWeb can construct one). `LiveBindToken` is opaque/unforgeable; its `checklist_digest` is proven field-value-free. | `serving_gate.rs` |
| Runner bind | `igweb-serve` calls `authorize_bind(addr, None)` before **every** bind (sync `authorize_runner_bind`; machine-mode line ~224). Nothing converts a parsed config into a checklist. | `server/igniter-web/src/bin/igweb-serve.rs` |
| Parsed checklist | P34 `HostConfig.live_bind: Option<LiveBindConfig>` parses + fails closed, but is **never** read by the bind path. `[host] mode = "public"` still refused. | `server/igniter-web/src/host_config.rs` |
| Inbound auth seam | Inbound authority is a **static shared-bearer-token map**: `req.bearer().and_then(|t| self.tokens.get(t))` over an in-memory `tokens: token→passport`. No cryptographic verification of the inbound credential itself; source notes "a real deployment would resolve credentials". | `runtime/igniter-machine/src/ingress.rs` |
| Signed passport | `sign_passport` / `PassportVerifier` authenticate the **host→hub coordination** passport. `EffectBridgeConfig.effect_passport_verifier` is `Some(..)` on the P34 write path, `None` on the no-op fallback. | `runtime/igniter-machine/src/{capability,ingress}.rs`, `server/igniter-web/src/host_binding.rs` |
| Signing key | `host_process_effect_signing_key()` = `blake3(pid ⧺ nanos)` — **ephemeral, per-process**, trusted only by that process's own verifier. Internally consistent for single-process loopback; not durable / not operator-provided. | `server/igniter-web/src/host_binding.rs` |
| TLS | Metadata only. P34 parses `inbound_tls` mode + file references; `native_tls` carries no transport. No TLS code exists in IgWeb. | P33/P34 packets, `host_config.rs` |

Known facts re-confirmed true:

- Public/non-loopback bind remains closed even with a complete parsed checklist.
- P34 is parse/diagnostic only.
- TLS is metadata-only.
- This card opens no listener.

## 2. Gate decision

**Decision: HOLD enablement; PROCEED with the chain below; require two prerequisites
before any non-loopback proof.**

Rationale (IDD):

- **Authority is not evidence (axiom 2).** The P34 booleans are operator *claims*. If the
  config→`LiveBindChecklist` conversion copied them verbatim, an operator could self-assert
  their way to a `LiveBindToken`. The gate is only as trustworthy as the booleans, so the
  **host** must set each boolean from verified runtime state.
- **Observe before switching authority (axiom 5).** The first implementation slice must be
  a non-binding *dry-run verdict*, not a bind.
- **Smallest artifact that prevents drift (axiom 3).** The conversion + verdict is small and
  fails closed; the risky parts (durable key, inbound verification, TLS, human approval)
  are isolated into later cards.

Two hard prerequisites gate the *real* flip (P39), independent of the dry-run (P36):

1. **Durable, operator-provided signed-passport key + wired inbound verification.** The
   ephemeral pid+nanos key and the static bearer-token map are acceptable for loopback but
   not for a public seam. `signed_passport_path_wired = true` may be asserted only after the
   host confirms a durable trusted key is loaded and the inbound seam rejects a forged
   passport. (This is the IgWeb face of machine audit A07/A08 follow-ups.)
2. **TLS decision in force.** `terminated_upstream` with a proven proxy-header trust policy
   for the first proof; `native_tls` stays blocked until a transport card exists (P33).

## 3. Required authority chain

Each link must hold before the next is trusted; the last link is a human, not code.

1. **Parsed checklist (DONE, P34).** `[host.live_bind]` operator assertions, fail-closed.
2. **Host-verified backing.** For each assertion the host confirms the *mechanism is in
   force* (body-cap configured, read-timeout configured, fail-closed auth wired, inbound
   signed-passport verifier wired with a durable key) — not merely that the operator typed
   `"true"`.
3. **Config → `LiveBindChecklist`.** A conversion that sets each boolean from (2), maps
   `inbound_tls` mode, and carries `operator_signoff`. Produced by the host, auditable.
4. **`authorize_bind(addr, Some(checklist))` verdict.** Pure structural check → opaque
   `LiveBindToken` or a coded refusal naming the missing field.
5. **TLS proof.** `terminated_upstream` proxy/header trust asserted and documented.
6. **Human approval.** An explicit out-of-band approval marker + security-checklist signoff;
   only then may the runner proceed from token → actual non-loopback `TcpListener::bind`.

`authorize_bind` itself never verifies passports or reads TLS (it is pure). Passport
verification lives at the **inbound request seam** (`ingress` handle/handle_effect via
`PassportVerifier`); the `signed_passport_path_wired` boolean is the host's attestation that
that seam is wired, set in link (2).

## 4. Answers to the card questions

1. **What evidence converts operator assertions into server bind authority?** Not the
   operator booleans alone. The carrier is the server `LiveBindChecklist`, but its booleans
   must be set by the **host from verified runtime state** (link 2), plus a TLS-in-force
   proof, plus a **human approval** for the final flip. Operator config = intent; host =
   capability; human = authority.
2. **Is signed-passport verification required before or inside `authorize_bind`?**
   **Before/outside.** `authorize_bind` is pure and only reads `signed_passport_path_wired:
   bool`. Actual verification happens at the inbound request seam with a durable
   `PassportVerifier`; the boolean may be `true` only after the host confirms that wiring
   (and that a forged passport is rejected).
3. **What TLS mode is acceptable for a first human-gated proof?**
   `terminated_upstream` (TLS terminates at a proxy/LB before IgWeb), with a documented
   proxy-header trust policy. `native_tls` remains blocked until a transport implementation
   card exists.
4. **What must be logged/reported without leaking secrets?** Bind class
   (loopback/non-loopback), the opaque `checklist_digest` (proven free of field values), the
   refusal `code()` + `missing_field()` name, the `operator_signoff`/approval marker id, and
   the TLS mode enum. **Never** print: passport material, the contents of
   `signed_passport_path`/`cert_file`/`key_file`, DSNs, or bearer tokens. Reuse the P29
   redaction taxonomy and P34 `CONFIG_PARSE` diagnostics.
5. **What is the smallest future implementation card that still keeps public bind closed
   until human approval?** A **dry-run verdict** surface (P36): convert the parsed config to
   a `LiveBindChecklist`, call `authorize_bind`, and **report** "would-authorize /
   would-refuse: \<reason\>" — but **never** proceed to bind a non-loopback socket. It fails
   closed (loopback is a no-op `Ok(None)`; non-loopback only ever *reports*, never binds) and
   is high-value: an operator can validate their checklist before any real attempt.

## 5. Next implementation / proof cards (with closed surfaces)

```text
LAB-IGNITER-WEB-LIVE-BIND-DRY-RUN-VERDICT-P36
  Goal: config → LiveBindChecklist → authorize_bind verdict, REPORT ONLY (no bind).
  Allowed: conversion fn LiveBindConfig→LiveBindChecklist; an `igweb-serve
    live-bind-check` (or `--check-live-bind`) path that prints would-authorize/would-refuse
    + the opaque digest; unit + subprocess tests.
  Closed: never bind a non-loopback socket; do not change the real bind path; booleans in
    this slice may be a 1:1 readiness mapping ONLY because it never binds — real backing is
    P37; no TLS transport; no human-approval bypass.

LAB-IGNITER-WEB-INBOUND-SIGNED-PASSPORT-DURABLE-KEY-P37
  Goal: durable operator-provided signing key + wired inbound PassportVerifier; prove a
    forged inbound passport is rejected.
  Allowed: operator key-material reference (file/env NAME only); verifier wiring at the
    inbound seam; forged-passport negative tests on loopback.
  Closed: no public bind; no inline key material in fixtures; ephemeral-key path stays the
    loopback default until this lands.

LAB-IGNITER-WEB-LIVE-BIND-TLS-TERMINATED-UPSTREAM-RUNBOOK-P38
  Goal: terminated_upstream operator runbook + proxy-header trust proof.
  Allowed: docs + a parse/trust-policy proof; file/header references only.
  Closed: no native TLS transport; no public bind; no committed cert/key material.

LAB-IGNITER-WEB-LIVE-BIND-HUMAN-GATED-PROOF-P39  (gate decision, human-approved)
  Goal: the actual non-loopback bind proof, terminated_upstream only, behind explicit human
    approval + security-checklist signoff.
  Closed: never run unattended/in CI; native_tls still blocked; revert to loopback default
    after the proof; requires P36+P37+P38 closed first.
```

Ordering: P36 (safe, now) → P37 + P38 (parallelizable prerequisites) → P39 (human-gated
flip, last). Public bind stays closed through P36–P38; only P39 may open one, and only under
human approval.

## 6. Explicit refusal

This card opens **no** public/non-loopback listener, wires **nothing** into the real bind
path, implements **no** TLS, and weakens **no** loopback default. The runner continues to
call `authorize_bind(addr, None)`; non-loopback continues to fail closed with
`non_loopback_without_checklist`.

## Verification run

```text
git diff --check
```
Result: PASS (doc-only card; no source changes).
