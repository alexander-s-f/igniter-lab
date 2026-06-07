# LAB-STDLIB-NET-P4

**Card ID:** LAB-STDLIB-NET-P4
**Category:** stdlib / io / network
**Track:** lab-experimental-io-network-compiler-diagnostic-proof-v0
**Route:** EXPERIMENTAL / LAB-ONLY / PROOF
**Date:** 2026-06-07
**Status:** DONE

---

## D — Deliverables

- `igniter-view-engine/fixtures/network_capability_compiler/` (15 fixture `.ig` programs)
- `igniter-view-engine/proofs/network_compiler_diagnostic_proof.rb` (proof runner)
- `lab-docs/stdlib/lab-experimental-io-network-compiler-diagnostic-proof-v0.md`
- `.agents/work/cards/stdlib/LAB-STDLIB-NET-P4.md` (this receipt)

---

## S — Summary

All 10 E-NET-* diagnostic codes from LAB-STDLIB-NET-P1 §5.4 were proved to fire correctly
on well-chosen fixture Igniter source programs, and `stdlib.io.network.*` call sites were
proved to classify as `escape` nodes (not `core`). The proof follows the LAB-STDLIB-IO-P2
pattern exactly: a proof-local Ruby classifier (`NetworkIGClassifier`) parses 15 illustrative
`.ig` source programs and applies 10 diagnostic rules. 42/42 checks pass.

**Node classification proved:**
- Valid contract (cap + effect + network call) → `escape`
- Pure contract (no caps, no network calls) → `core`
- Any diagnostic fires → `blocked`

**All 10 E-NET-* codes exercised:**
`E-NET-AMBIENT-BLOCKED`, `E-NET-CAP-MISSING`, `E-NET-CAP-UNKNOWN`,
`E-NET-EFFECT-UNDECLARED`, `E-NET-DIRECTION-BLOCKED`, `E-NET-HOST-BLOCKED`,
`E-NET-PORT-BLOCKED`, `E-NET-LOOPBACK-VIOLATION`, `E-NET-TLS-REQUIRED`,
`E-NET-PROTOCOL-MISMATCH`

**Closed-surface maintained:**
No real TCP sockets. No igniter-lang modifications. P4 classifier independent of P3 FFI stub.
Guard scan (NET-STABLE-3) uses split-string technique to avoid self-triggering (same
pattern as P3).

---

## Proof Chain

| Card | Checks | Scope |
|---|---|---|
| LAB-STDLIB-NET-P2 | 53/53 | Schema, delegation algebra, safety policies NET-1–NET-6 |
| LAB-STDLIB-NET-P3 | 61/61 | FFI surface contract, stub mode, operation sequence |
| LAB-STDLIB-NET-P4 | 42/42 | Compiler escape classification, all 10 E-NET-* codes |
| **Total** | **156/156** | |

---

## T — Tensions / Risks

**1. Diagnostic rule priority under multiple violations.**
The proof-local classifier can fire multiple codes per call (e.g., E-NET-HOST-BLOCKED +
E-NET-PORT-BLOCKED simultaneously). Whether the real compiler short-circuits or reports
all violations is a design decision deferred to PROP-035.

**2. `direction: "both"` cap coverage missing.**
The `connect_allowed: true, listen_allowed: true` combination is present in the P2 algebra
but not exercised in P4 fixtures. Open from P1–P2. Non-blocking for P4.

**3. Multi-hop delegation not exercised in P4.**
The delegation algebra (P2) proved 3-grant chain reduction but P4 fixtures test single-cap
contracts only. Hardening card (P5) is the right place for chained grant proofs.

---

## R — Recommended Next

**LAB-STDLIB-NET-P5** — Network Capability Hardening (analog to LAB-STDLIB-IO-P9)

Edge cases identified across P1–P4 but deferred:
- Glob host matching semantics (`*.example.com` multi-level, root-domain behavior)
- `direction: "both"` compose behavior under combined connect+listen grants
- Multi-hop delegation chains (3+ grants) with scope-reduction verification
- Bind-address restriction enforcement
- Wildcard `allowed_hosts: "*"` + `loopback_only: true` interaction algebra proof

Authorized writes: new fixture JSON files + new proof runner only. Pattern: LAB-STDLIB-IO-P9.

---

## Check Matrix

| Check ID | Group | Description | Status |
|---|---|---|---|
| NET-CLASS-1 | NET-CLASS | good_connect.ig → escape | PASS |
| NET-CLASS-2 | NET-CLASS | good_listen.ig → escape | PASS |
| NET-CLASS-3 | NET-CLASS | pure_no_network.ig → core | PASS |
| NET-BLOCKED-1 | NET-BLOCKED | ambient_blocked.ig → blocked | PASS |
| NET-BLOCKED-2 | NET-BLOCKED | cap_missing.ig → blocked | PASS |
| NET-BLOCKED-3 | NET-BLOCKED | cap_unknown.ig → blocked | PASS |
| NET-BLOCKED-4 | NET-BLOCKED | effect_undeclared.ig → blocked | PASS |
| NET-BLOCKED-5 | NET-BLOCKED | direction_blocked.ig → blocked | PASS |
| NET-ECODE-1 | NET-ECODE | E-NET-AMBIENT-BLOCKED fires | PASS |
| NET-ECODE-2 | NET-ECODE | E-NET-CAP-MISSING fires | PASS |
| NET-ECODE-3 | NET-ECODE | E-NET-CAP-UNKNOWN fires | PASS |
| NET-ECODE-4 | NET-ECODE | E-NET-EFFECT-UNDECLARED fires | PASS |
| NET-ECODE-5 | NET-ECODE | E-NET-DIRECTION-BLOCKED fires | PASS |
| NET-ECODE-6 | NET-ECODE | E-NET-HOST-BLOCKED fires | PASS |
| NET-ECODE-7 | NET-ECODE | E-NET-PORT-BLOCKED fires | PASS |
| NET-ECODE-8 | NET-ECODE | E-NET-LOOPBACK-VIOLATION fires | PASS |
| NET-ECODE-9 | NET-ECODE | E-NET-TLS-REQUIRED fires | PASS |
| NET-ECODE-10 | NET-ECODE | E-NET-PROTOCOL-MISMATCH fires | PASS |
| NET-GOOD-1 | NET-GOOD | good_connect.ig → zero diagnostics | PASS |
| NET-GOOD-2 | NET-GOOD | good_listen.ig → zero diagnostics | PASS |
| NET-GOOD-3 | NET-GOOD | good_tls_outbound.ig → zero diags, escape | PASS |
| NET-GOOD-4 | NET-GOOD | pure_no_network.ig → zero diagnostics | PASS |
| NET-GOOD-5 | NET-GOOD | good_connect.ig → network_call detected | PASS |
| NET-CAP-PARSE-1 | NET-CAP-PARSE | capability net_conn parsed | PASS |
| NET-CAP-PARSE-2 | NET-CAP-PARSE | loopback_only:true parsed | PASS |
| NET-CAP-PARSE-3 | NET-CAP-PARSE | effect binding net_conn parsed | PASS |
| NET-CAP-PARSE-4 | NET-CAP-PARSE | tls_required:true parsed | PASS |
| NET-CAP-PARSE-5 | NET-CAP-PARSE | listen_allowed:true parsed | PASS |
| NET-DIR-1 | NET-DIRECTION | connect-only+listen → DIRECTION_BLOCKED | PASS |
| NET-DIR-2 | NET-DIRECTION | listen-only+connect → DIRECTION_BLOCKED | PASS |
| NET-DIR-3 | NET-DIRECTION | good_connect → no DIRECTION_BLOCKED | PASS |
| NET-DIR-4 | NET-DIRECTION | good_listen → no DIRECTION_BLOCKED | PASS |
| NET-DETAIL-1 | NET-DETAIL | HOST_BLOCKED msg includes host name | PASS |
| NET-DETAIL-2 | NET-DETAIL | PORT_BLOCKED msg includes port number | PASS |
| NET-DETAIL-3 | NET-DETAIL | LOOPBACK_VIOLATION msg includes host | PASS |
| NET-DETAIL-4 | NET-DETAIL | PROTOCOL_MISMATCH msg includes protocol | PASS |
| NET-DETAIL-5 | NET-DETAIL | AMBIENT_BLOCKED msg mentions "pure contract" | PASS |
| NET-STABLE-1 | NET-STABLE | 10 CODES constants defined | PASS |
| NET-STABLE-2 | NET-STABLE | All codes start with E-NET- | PASS |
| NET-STABLE-3 | NET-STABLE | No real socket refs in proof runner | PASS |
| NET-STABLE-4 | NET-STABLE | igniter-lang repo untouched | PASS |
| NET-STABLE-5 | NET-STABLE | P4 independent of P3 FFI stub | PASS |
