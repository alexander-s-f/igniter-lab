# LAB-STDLIB-NET-P1

**Card ID:** LAB-STDLIB-NET-P1
**Category:** stdlib / io / network
**Track:** lab-experimental-io-network-capability-research-v0
**Route:** EXPERIMENTAL / LAB-ONLY / RESEARCH
**Date:** 2026-06-07
**Status:** DONE

---

## D — Deliverables

- `lab-docs/stdlib/lab-experimental-io-network-capability-research-v0.md`
- `.agents/work/cards/stdlib/LAB-STDLIB-NET-P1.md` (this receipt)

---

## S — Summary

The `IO.NetworkCapability` JSON schema was designed as a direct extension of the
file IO capability schema established in LAB-STDLIB-IO-P1, adding network-specific
scope dimensions: `allowed_hosts`, `allowed_port_ranges`, `loopback_only`, protocol,
direction, bind address, and TLS enforcement. The delegation algebra from
LAB-STDLIB-IO-P4 was extended to a network sub-grant ordering relation (G₂ ⊑_net G₁)
with eight conditions covering type identity, protocol non-escalation, direction
non-escalation, loopback non-escalation, host scope inclusion, port range inclusion,
TLS non-downgrade, and bind address non-escalation — plus a compose operator and
seven delegation violation classes with stable E-NET-DELEGATION-* error codes. Six
safety policies (NET-1 through NET-6) were defined as analogs to the four file IO
policies from P1, with two new network-specific policies (TLS enforcement, protocol
constraint) that have no file IO equivalent. Three named variants (loopback connect,
localhost listen, external HTTPS) provide concrete schemas for the primary network
capability use cases. The primary remaining gap is proof verification: the algebra
and policy claims are design-complete but not yet proof-runner-validated; that work
belongs to LAB-STDLIB-NET-P2.

---

## T — Tensions / Risks

**1. Host allowlist glob semantics are underspecified.**
The schema specifies that `allowed_hosts` may contain glob patterns (e.g.,
`"*.example.com"`), and the delegation algebra says G₂ may refine a glob to specific
subdomains. The exact glob matching semantics (single-level `*` vs recursive `**`,
whether `*` matches the root domain, case sensitivity) are not defined in this
document. This creates ambiguity in Condition 5 (Host Scope Inclusion) that the P2
proof runner will need to resolve with explicit test cases before any implementation.

**2. `direction: "both"` interacts with loopback_only in non-obvious ways.**
A capability with `direction: "both"` and `loopback_only: true` would permit both
connecting to and listening on loopback. The compose operator's behavior when
combining a `direction: "connect"` and `direction: "listen"` grant is not explicitly
defined — the resulting `direction` field is not covered by the compose operator
rules in §4.3. The P2 proof runner should define and verify this interaction.

**3. No analog for the sandbox_dir nesting proof from LAB-STDLIB-IO-P9.**
The file IO hardening card (P9) proved that path-prefix sibling escape (e.g.,
targeting `/sub-sibling` when the sandbox is `/sub`) is blocked by component-based
path matching (IOH-6). The network analog — ensuring that a subdomain glob cannot
escape to a parent domain — requires similar precision in the delegation Condition 5
proof. Without explicit test cases for cases like `"api.example.com"` ⊆ `"*.example.com"`,
the host scope inclusion rule could silently pass invalid delegations.

---

## R — Recommended Next

**LAB-STDLIB-NET-P2** — Network Capability Delegation Algebra Proof

A Ruby proof runner validating the schema, delegation algebra, safety policies,
and passport extension from this document. Follow the LAB-STDLIB-IO-P2 pattern:
- Schema validation for all three variants (Variant A, B, C from §2.3)
- All seven delegation violation classes produce correct E-NET-DELEGATION-* codes
- All eight sub-grant conditions verified for valid delegations
- Compose operator produces correct intersection for selected pairs
- All six NET safety policies produce correct E-NET-* error codes
- Extended passport (§6.1) with mixed file + network grants validates correctly

No actual network IO (no TCP sockets). Schema and algebra validation in memory only.

---

## Capability Schema Summary

| Variant | loopback_only | connect | listen | tls_required | Use case |
|---|---|---|---|---|---|
| Loopback connect (Variant A) | true | true | false | false | Proof-local client; inter-process on same machine |
| Localhost listen (Variant B) | true | false | true | false | Proof-local server; service loop candidate |
| External HTTPS connect (Variant C) | false | true | false | true | Restricted outbound API client |

---

## Delegation Algebra Rules (count)

- **Sub-grant conditions (G₂ ⊑_net G₁):** 8 conditions
- **Compose operator (G₁ ∧ G₂) rules:** 9 field rules
- **Delegation violation classes:** 7 classes with stable E-NET-DELEGATION-* codes
- **Safety policies:** 6 policies (NET-1 through NET-6)
- **Runtime error codes (all NET-* combined):** 10 codes (5 with file IO analog, 5 new)
