# Lab: IO.NetworkCapability — Delegation Algebra Proof (v0)

> Status: experimental · lab-only · proof-local
> Card: LAB-STDLIB-NET-P2
> Date: 2026-06-07
> Track: lab-experimental-io-network-capability-algebra-proof-v0
> Depends on: lab-experimental-io-network-capability-research-v0.md (LAB-STDLIB-NET-P1)

---

## Pre-v1 Language Note

Igniter Lang is under active development. All constructs described in this
document — including capability schemas, delegation algebra, compose operators,
and safety policy implementations — are drawn from proposed or accepted spec
chapters and the established IO capability lab pattern (P1–P10). They are not
stable APIs. This document is lab-only proof evidence. It does not constitute
canon specification, a PROP, or a production commitment. The source
`igniter-lang` documents remain the reference for all formal decisions.

Network I/O is **not currently implemented** in Igniter Lang or igniter-lab.
The proof runner validates the algebraic properties of the capability schema
in memory only. No TCP sockets are opened. No compiler integration is tested.

---

## 1. Purpose

This document records the proof that the `IO.NetworkCapability` delegation
algebra defined in LAB-STDLIB-NET-P1 behaves correctly according to its
specification. The P1 research document defined:

- A 14-field JSON schema for network capability grants (§2)
- Six safety policies NET-1 through NET-6 with corresponding E-NET-* error codes (§3)
- An 8-condition sub-grant ordering relation G₂ ⊑_net G₁ (§4.2)
- Seven delegation violation classes with E-NET-DELEGATION-* error codes (§4.4)
- A compose operator (G₁ ∧ G₂) defined by nine rules (§4.3)
- A mixed file+network passport schema (§6)

P2 translates those definitions into executable Ruby proof code (following the
LAB-STDLIB-IO-P2 pattern established for file IO) and demonstrates that all
defined properties hold under the three canonical variant fixtures and a
comprehensive suite of targeted test cases. The proof is purely algebraic:
no network I/O occurs, no OS calls are made, and no compiler integration is
exercised.

This follows the same pattern as LAB-STDLIB-IO-P2 (file IO delegation algebra
proof), which validated the file capability schema, four file safety policies,
and the file sub-grant ordering relation. Network capability proof extends that
pattern to the topological scope model (host/port/protocol) in place of the
spatial scope model (sandbox directory / path allowlist).

---

## 2. What is Proven

| Group | Count | What is validated | Proof method |
|---|---|---|---|
| Schema | 3 | All three canonical variants (A: loopback connect, B: localhost listen, C: HTTPS outbound) have valid JSON schema — all required fields present and correctly typed | In-memory field presence and type checks against `NetworkCapabilityValidator.validate_schema` |
| Safety policies | 17 | NET-1 through NET-6 pass/fail behavior — each policy checked for PASS (allowed) and FAIL (correct E-NET-* error code) using Variants A and C | Direct policy method invocation; result code checked against expected constant |
| Delegation algebra | 15 | 7 valid delegation pairs (identity, subset scope, protocol narrowing, loopback strengthening, TLS strengthening) and 8 violation cases each producing the correct E-NET-DELEGATION-* code | `NetworkDelegationAlgebra.valid_delegation?` invoked with hand-constructed parent/child pairs |
| Compose operator | 7 | 9-rule compose operator: identity, loopback OR, TLS OR, permission AND, port intersection, host intersection, protocol meet | `NetworkDelegationAlgebra.compose` output inspected field-by-field |
| Passport | 4 | Mixed file+network passport validates; bindings match caps keys; resource_type dispatches correctly; invalid passport rejected | `PassportValidator.validate_passport` against the mixed_passport fixture and a mutated invalid copy |
| Edge cases | 7 | Empty allowed_hosts fail-closed; empty allowed_port_ranges fail-closed; wildcard `"*"` matches any host; port boundary conditions (min, max, min-1); resource_type mismatch rejected | Direct policy invocation with edge-case inputs |
| **Total** | **53** | | |

---

## 3. What is NOT Proven (Non-Claims)

- **No real TCP sockets opened.** The proof runner contains no `TCPSocket`,
  `Socket`, `Net::HTTP`, or any other network I/O call. All checks operate
  on in-memory Ruby objects.
- **No compiler integration tested.** No Igniter compiler, VM, or IR node
  classification is exercised. The E-NET-AMBIENT-BLOCKED, E-NET-CAP-MISSING,
  and E-NET-CAP-UNKNOWN codes are not tested here (they require compiler
  presence — see LAB-STDLIB-NET-P4).
- **Glob subdomain matching not proven.** The P1 research doc noted "glob
  semantics" as a dimension of `allowed_hosts` matching. This proof implements
  only exact match and the `"*"` wildcard (any host). The behavior of patterns
  like `"*.example.com"` is not specified here and is flagged as an open
  question.
- **`direction: "both"` compose behavior not fully specified.** The proof
  validates identity compose (A ∧ A) and cross-direction cases (connect-only ∧
  listen-only → neither), but the compose result's `direction` field is not
  independently asserted; compose operates on the four permission bits
  (`connect_allowed`, `listen_allowed`, `send_allowed`, `receive_allowed`) only.
  The `direction` field in composed grants is not updated (it carries g1's value).
  This is flagged for P3+ resolution.
- **This is proof-local algebra only.** Runtime enforcement — the actual
  application of these policies at a call boundary in the Igniter VM — requires
  LAB-STDLIB-NET-P3 (FFI surface proof) and beyond.
- **No production commitment.** This proof does not constitute a PROP, an
  accepted spec chapter, or a commitment to implement network I/O in any
  timeline.

---

## 4. Key Design Decisions Confirmed

The following decisions emerged from writing the proof code and were not
fully visible in the P1 research text:

**1. Fail-closed defaults require no special-case logic.**
Empty `allowed_hosts` and empty `allowed_port_ranges` both fall through the
same general-case check (no range covers the input) without needing special
sentinel values. The data structure itself enforces fail-closed behavior when
the lists are empty — confirmed by NET-EDGE-1 and NET-EDGE-2.

**2. The `"*"` wildcard in `allowed_hosts` must be treated as a set-level
escape, not an element.**
`intersect_hosts` must return `h2` when `h1` contains `"*"` (not `["*"] ∩ h2`),
and `host_subset?` must return `true` unconditionally when the parent set
contains `"*"`. The wildcard is a permission level, not a literal string to
be intersected. This distinction only became concrete when writing the compose
and delegation algebra methods.

**3. The `bind_address` non-escalation rule admits `null` children.**
Condition 8 (Bind Address Non-Escalation) must explicitly allow a `null`
child bind_address as a valid narrowing of any parent — even a parent with a
specific address. `null` means "OS chooses within parent's constraint", which
is a restriction (the child has less control over binding), not an escalation.
This asymmetry required an explicit `child['bind_address'].nil?` guard in the
delegation check.

**4. Most-restrictive protocol in compose requires a "none" sentinel for
incompatible pairs.**
When composing `"tcp"` and `"udp"` (neither is `"tcp_udp"`), there is no
meaningful common protocol. The compose operator returns `"none"` in this
case. This sentinel propagates downstream: any policy NET-6 check against a
`"none"` protocol will always fail, which is the correct fail-closed behavior
for an incompatible compose.

**5. The passport's `resource_type` discriminator is necessary and sufficient
for policy dispatch.**
PassportValidator dispatches each capability to the appropriate validator
based solely on the `resource_type` field. No other field is needed for
routing. A file capability passed to `NetworkCapabilityValidator` fails
immediately on the `resource_type != "network"` check (NET-EDGE-7), which
confirms that the discriminator is robust without additional type tags.

---

## 5. Open Questions Surfaced

**Q1: Glob semantics for `allowed_hosts` remain unspecified.**
P1 §4.2 Condition 5 mentions "glob pattern" matching for allowed_hosts but
does not define the glob language. This proof implements only `"*"` (any host)
and exact string match. The behavior of `"*.example.com"` as a wildcard for
subdomains is not defined. A decision is needed before any runtime
implementation: does `"*.example.com"` match only direct subdomains
(`api.example.com`) or recursive subdomains (`v2.api.example.com`)? Does it
match the apex domain (`example.com`)? The proof deliberately excludes this
case and marks it unresolved.

**Q2: Compose result `direction` field is not updated.**
The compose operator merges the four boolean permission bits but leaves the
`direction` field (e.g., `"connect"`, `"listen"`, `"both"`) as `g1`'s value.
After composing a `"connect"` grant with a `"listen"` grant the composed
result has `direction: "connect"` but `connect_allowed: false, listen_allowed: false`.
This inconsistency between the `direction` string and the boolean bits should
be resolved: either the compose result should synthesize a new `direction`
value from the bits, or the `direction` field should be dropped from composed
grants and the bits treated as authoritative.

**Q3: `direction: "both"` in the source schema is not exercised.**
None of the three canonical variants uses `direction: "both"`. The spec allows
it, but no delegation or compose test uses it. Its interaction with the
permission bits (should `direction: "both"` imply
`connect_allowed: true, listen_allowed: true`?) is not validated.

**Q4: Protocol `"none"` sentinel in compose output.**
When composing two incompatible protocols (e.g., `"tcp"` and `"udp"`), the
compose operator produces `protocol: "none"`. This sentinel is not part of
the declared protocol vocabulary (`tcp`, `udp`, `tcp_udp`). Should an
incompatible compose produce an error rather than a sentinel value? The
current behavior (fail-closed via sentinel) is safe but may be surprising.

**Q5: Condition 8 (Bind Address) and `null` parent.**
The delegation algebra allows any child bind_address when the parent
bind_address is `null` (OS chooses). This means a parent with `null`
bind_address can delegate to a child with `bind_address: "0.0.0.0"`,
which binds all interfaces. Whether this constitutes a privilege escalation
depends on context. NET-DELEG-7 treats `null → "127.0.0.1"` as valid
(narrowing), but `null → "0.0.0.0"` is also currently valid under the same
rule. This asymmetry may need a policy refinement.

---

## 6. Proof Results

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

---

## 7. Recommended Next Card

**LAB-STDLIB-NET-P3** — FFI Surface Proof

Prove the `stdlib/io/network.ig` operation signatures by writing a Rust stub
(no real network calls) and a Ruby runner that validates the calling convention.
Follows the LAB-STDLIB-IO-P3 FFI surface proof pattern. The P3 proof will
exercise the E-NET-CAP-MISSING, E-NET-CAP-UNKNOWN, and E-NET-AMBIENT-BLOCKED
error codes that P2 could not reach (they require compiler classification
context).
