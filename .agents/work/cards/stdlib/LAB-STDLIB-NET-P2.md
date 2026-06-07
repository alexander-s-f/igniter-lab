# LAB-STDLIB-NET-P2

**Card ID:** LAB-STDLIB-NET-P2
**Category:** stdlib / io / network
**Track:** lab-experimental-io-network-capability-algebra-proof-v0
**Route:** EXPERIMENTAL / LAB-ONLY / PROOF-LOCAL
**Date:** 2026-06-07
**Status:** DONE

---

## D — Deliverables

- `igniter-view-engine/fixtures/network_capability/variant_a_loopback_connect.json`
- `igniter-view-engine/fixtures/network_capability/variant_b_localhost_listen.json`
- `igniter-view-engine/fixtures/network_capability/variant_c_https_outbound.json`
- `igniter-view-engine/fixtures/network_capability/mixed_passport.json`
- `igniter-view-engine/proofs/network_capability_proof.rb`
- `lab-docs/stdlib/lab-experimental-io-network-capability-algebra-proof-v0.md`
- `.agents/work/cards/stdlib/LAB-STDLIB-NET-P2.md` (this receipt)

---

## S — Summary

LAB-STDLIB-NET-P2 proves the IO.NetworkCapability delegation algebra defined
in the P1 research document (LAB-STDLIB-NET-P1) by implementing it as a
self-contained Ruby proof runner (no gems, no real sockets) and executing 53
checks covering all defined properties. The proof confirms that all six
safety policies (NET-1 through NET-6) produce correct E-NET-* error codes on
both PASS and FAIL inputs, that all eight conditions of the sub-grant ordering
relation G₂ ⊑_net G₁ are correctly enforced with the seven E-NET-DELEGATION-*
violation codes, and that the nine-rule compose operator produces the correct
most-restrictive intersection for all tested input pairs. The mixed
file+network passport validator correctly dispatches each capability to its
appropriate policy set by `resource_type`. All 53 checks pass; the proof
runner exits 0.

The proof also surfaced five open questions not fully resolved in P1: glob
subdomain matching semantics, compose result `direction` field inconsistency,
the `null` parent bind_address privilege boundary, the `"none"` protocol
sentinel from incompatible compose, and the unexercised `direction: "both"`
value. These are documented in the proof doc §5 and should inform P3+.

---

## T — Tensions / Risks

**T1: Glob host matching is unspecified.**
P1 §4.2 Condition 5 mentions "glob pattern" for `allowed_hosts` but does not
define the glob language. This proof implements only `"*"` (any-host wildcard)
and exact match. Any production host matching will require a formal glob
semantics decision before the host_subset? condition can be fully proven.
Subdomain glob (`"*.example.com"`) behavior is a real-world requirement for
any outbound API capability and cannot remain unspecified at P3+.

**T2: Compose result leaves `direction` field inconsistent with permission bits.**
After composing a connect-only and a listen-only grant, the result has
`direction: "connect"` but `connect_allowed: false, listen_allowed: false`.
The permission bits are authoritative for policy enforcement, but the `direction`
string misrepresents the composed grant to any reader. This is a schema
coherence issue that grows worse when compose results are further composed or
delegated. P3 should decide whether `direction` is synthesized from bits or
dropped from composed grants.

**T3: `null` parent bind_address admits wide-interface child delegation.**
Condition 8 (Bind Address Non-Escalation) treats `null` parent bind_address
as unrestricted: any child bind_address is permitted. This means
`null → "0.0.0.0"` is currently a valid delegation even though binding to all
interfaces is potentially more privileged than binding to loopback. Whether
this requires a separate "bind_address wildcard" concept or a stronger null
interpretation (null means loopback-only unless explicitly otherwise) should
be decided before any runtime enforcement is written.

---

## R — Recommended Next

**LAB-STDLIB-NET-P3** — FFI Surface Proof

Define the `stdlib/io/network.ig` operation signatures (connect, listen,
accept, send, receive, close), write a Rust stub (no real connections), and
a Ruby runner that validates the calling convention and the compiler-facing
error codes (E-NET-CAP-MISSING, E-NET-CAP-UNKNOWN, E-NET-AMBIENT-BLOCKED)
that P2 could not reach. Follows the LAB-STDLIB-IO-P3 FFI surface proof
pattern.

---

## Proof Matrix

```
.....................................................
========================================================================
NetworkCapability Proof — Results Matrix
========================================================================
  GROUP        CHECK                    STATUS
------------------------------------------------------------------------
  schema       NET-SCHEMA-1             PASS
  schema       NET-SCHEMA-2             PASS
  schema       NET-SCHEMA-3             PASS

  policy       NET-POLICY-A1            PASS
  policy       NET-POLICY-A2            PASS
  policy       NET-POLICY-A3            PASS
  policy       NET-POLICY-A4            PASS
  policy       NET-POLICY-A5            PASS
  policy       NET-POLICY-A6            PASS
  policy       NET-POLICY-A7            PASS
  policy       NET-POLICY-A8            PASS
  policy       NET-POLICY-A9            PASS
  policy       NET-POLICY-A10           PASS
  policy       NET-POLICY-A11           PASS
  policy       NET-POLICY-C1            PASS
  policy       NET-POLICY-C2            PASS
  policy       NET-POLICY-C3            PASS
  policy       NET-POLICY-C4            PASS
  policy       NET-POLICY-C5            PASS
  policy       NET-POLICY-C6            PASS

  delegation   NET-DELEG-1              PASS
  delegation   NET-DELEG-2              PASS
  delegation   NET-DELEG-3              PASS
  delegation   NET-DELEG-4              PASS
  delegation   NET-DELEG-5              PASS
  delegation   NET-DELEG-6              PASS
  delegation   NET-DELEG-7              PASS
  delegation   NET-DELEG-8              PASS
  delegation   NET-DELEG-9              PASS
  delegation   NET-DELEG-10             PASS
  delegation   NET-DELEG-11             PASS
  delegation   NET-DELEG-12             PASS
  delegation   NET-DELEG-13             PASS
  delegation   NET-DELEG-14             PASS
  delegation   NET-DELEG-15             PASS

  compose      NET-COMPOSE-1            PASS
  compose      NET-COMPOSE-2            PASS
  compose      NET-COMPOSE-3            PASS
  compose      NET-COMPOSE-4            PASS
  compose      NET-COMPOSE-5            PASS
  compose      NET-COMPOSE-6            PASS
  compose      NET-COMPOSE-7            PASS

  passport     NET-PASSPORT-1           PASS
  passport     NET-PASSPORT-2           PASS
  passport     NET-PASSPORT-3           PASS
  passport     NET-PASSPORT-4           PASS

  edge         NET-EDGE-1               PASS
  edge         NET-EDGE-2               PASS
  edge         NET-EDGE-3               PASS
  edge         NET-EDGE-4               PASS
  edge         NET-EDGE-5               PASS
  edge         NET-EDGE-6               PASS
  edge         NET-EDGE-7               PASS
------------------------------------------------------------------------
Total: 53  |  PASS: 53  |  FAIL: 0
========================================================================
Result: ALL CHECKS PASSED
```
