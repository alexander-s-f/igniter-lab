# LAB-RACK-P1

**Card ID:** LAB-RACK-P1
**Category:** lang / web
**Track:** lab-igniter-rack-reimplementation-feasibility-v0
**Route:** LAB / LANG / RESEARCH
**Date:** 2026-06-07
**Status:** DONE

---

## D — Deliverables

- `lab-docs/lang/lab-igniter-rack-reimplementation-feasibility-v0.md`
- `.agents/work/cards/lang/LAB-RACK-P1.md` (this receipt)

---

## S — Summary

Rack's core `call(env) -> [status, headers, body]` interface maps directly to
Igniter's type system: `HttpRequest` and `HttpResponse` as typed `Record{}`
values replace the untyped `env` hash, `ContractRef[HttpRequest, HttpResponse]`
replaces duck-typed middleware chaining, and Igniter's failure taxonomy
(`failed`, `timed_out`, `unknown_external_state`) replaces undifferentiated
exception rescue. Two blocking gaps prevent a full Rack-equivalent today:
network I/O is entirely absent from the stdlib and runtime (no TCP socket, no
`IO.NetworkCapability` — not started), and the service loop (the continuous
accept loop) is Stage 4 deferred under PROP-039+ with no compiler or runtime
support. Streaming response bodies are additionally blocked until Stage 2
(PROP-023). The expressible parts — typed request/response records,
`ContractRef` middleware, idempotency declarations, and structured receipts —
are a genuine accountability dividend over Rack's implicit, untyped design.

---

## T — Tensions / Risks

1. **Network I/O gap is a root blocker** — No `IO.NetworkCapability` type, no
   `stdlib/io/network.ig`, no TCP socket FFI layer. Every server-layer feature
   (accept loop, request parsing, response writing) depends on this. Closing
   this gap requires a new lab card (LAB-STDLIB-NET-P1) and, eventually, extends
   PROP-035 scope. Risk: this gap may not close until Stage 4 governance opens.

2. **Service loop is Stage 4 deferred** — PROP-039+ is a placeholder only.
   Ch13 §13.1 explicitly labels the `service contract` syntax "Design text only:
   source syntax is not implemented." Even if network I/O were available, there
   is no managed loop primitive to accept connections repeatedly. Risk: any
   lab work on a Rack-equivalent server will hit this blocker immediately and
   must stay in research/proof territory.

3. **ContractRef dynamic dispatch is type-system-present but runtime-unproven**
   — Assembling a middleware chain dynamically (the Rack `Builder` pattern)
   requires `ContractRef` as a runtime value in a `Collection`. The type system
   allows this; the lab has no proof. Risk: claiming the middleware composition
   model works without running a proof creates over-confidence. This needs
   LAB-LANG-HTTP-TYPES-P1 before the claim is substantiated.

---

## R — Recommended Next

**LAB-STDLIB-NET-P1 — Network I/O Capability Research** (Option A from §10).

The network I/O gap is the single highest-priority blocker. LAB-STDLIB-NET-P1
should follow the LAB-STDLIB-IO-P1 pattern exactly: research-only, no
implementation, producing a capability schema for `IO.NetworkCapability`
(bind address, port range, protocol constraints) and extending the
LAB-STDLIB-IO-P4 delegation algebra to network grants. This card closes the
root design gap and unblocks both the service loop research and the Effect
Surface (PROP-035) design for HTTP handlers. In parallel, LAB-LANG-HTTP-TYPES-P1
can prove the `ContractRef` dispatch pattern in the existing Ruby lab runner
using the expressible parts of the type system that are available today.

---

## Feasibility Verdict

| Layer | Status |
|---|---|
| Typed `HttpRequest` Record | EXPRESSIBLE TODAY (ch3, Stage 1) |
| Typed `HttpResponse` Record | EXPRESSIBLE TODAY (ch3, Stage 1) |
| Middleware `ContractRef[HttpRequest, HttpResponse]` | EXPRESSIBLE TODAY (type system); runtime dispatch UNPROVEN |
| Idempotency declarations | PLANNED (PROP-035) |
| Effect Surface for HTTP handler | PLANNED (PROP-035) |
| Structured receipts per request | EXPRESSIBLE (Postulate 8); runtime production UNPROVEN in handler |
| Typed failure taxonomy | EXPRESSIBLE TODAY (Result[T,E], ch12 failure classes) |
| Named I/O capabilities (file) | LAB-PROVEN (LAB-STDLIB-IO-P1 through P10) |
| Named I/O capabilities (network) | NOT STARTED |
| Service loop (accept loop) | BLOCKED (PROP-039+, Stage 4 deferred) |
| Streaming body | DEFERRED (Stage 2, PROP-023) |
| Network I/O stdlib | NOT STARTED |
| Dynamic middleware stack assembly | TYPE SYSTEM PRESENT; PROOF NEEDED |
| Capability delegation algebra (network) | NOT STARTED (file I/O algebra: LAB-STDLIB-IO-P4) |
