# Lab Experimental — stdlib/io/network: Dead Grant Detection + Compose bind_address Gap

**Card:** LAB-STDLIB-NET-P6  
**Track:** lab-experimental-io-network-capability-algebra  
**Route:** EXPERIMENTAL / LAB-ONLY / PROOF  
**Date:** 2026-06-07  
**Status:** DONE  
**Proof file:** `igniter-view-engine/proofs/network_p6_proof.rb`  
**Checks:** 36/36 PASS

---

## §1 Design Stance

P5 closed all five open questions from the initial P1 design, but left two documented gaps
in §6 of `lab-experimental-io-network-hardening-proof-v0.md`:

1. **compose does not preserve bind_address** — the canonical `compose(g1, g2)` sets
   `bind_address: nil` regardless of both parents' values. This is current behavior but
   operationally lossy.

2. **Dead grant detection** — `compose(connect_only, listen_only)` where the two grants
   have complementary permission bits produces a grant where ALL permission bits are false.
   This is schema-valid but operationally useless; no operation can be authorized through it.

P6 closes both gaps with explicit proofs. The algebra modules are inlined from P2 verbatim
(module names suffixed `P6` to avoid constant redefinition) with two additions:
- `dead_grant?` predicate on `NetworkDelegationAlgebraP6`
- Three compose bind_address variants: `compose_bind_inherit_first`, `compose_bind_intersect`, `compose_bind_nil`

No real TCP sockets. Proof-local algebra only.

---

## §2 Dead Grant Resolution

### Definition

A **dead grant** is a network capability grant in which all four permission bits are false:

```
connect_allowed = false
listen_allowed  = false
send_allowed    = false
receive_allowed = false
```

The predicate:

```ruby
def self.dead_grant?(cap)
  !cap['connect_allowed'] && !cap['listen_allowed'] &&
    !cap['send_allowed']   && !cap['receive_allowed']
end
```

### Key findings

| Finding | Proved by |
|---|---|
| `dead_grant?` returns false for connect-only, listen-only, both-direction grants | NET-DEAD-1,2,3 |
| `dead_grant?` returns true for all-false grant | NET-DEAD-4 |
| `compose(pure_connect_only, pure_listen_only)` produces a dead grant | NET-DEAD-5 |
| Dead grant is absorbing for compose — `compose(dead, any)` and `compose(any, dead)` are both dead | NET-DEAD-6,7 |
| `valid_delegation?(parent, dead_grant)` is VALID — no permission escalation | NET-DEAD-8 |
| `check_policy_net4(dead_grant, :connect)` fires `E-NET-DIRECTION-BLOCKED` | NET-DEAD-9 |
| Dead grant is schema-valid (`validate_schema` returns `valid: true`) | NET-DEAD-10 |
| `dead_grant_warning?` fires on compose result | NET-DEAD-11 |

### Absorption clarification

The "dead grant is absorbing for compose" result (NET-DEAD-6,7) follows directly from AND
semantics on permission bits: if any grant in a compose pair has all bits false, the AND
of each bit with the other grant's bit is guaranteed false.

Note: the fixture grants `direction_connect_only` and `direction_listen_only` both have
`receive_allowed: true`, so they do NOT produce a dead grant when composed. Dead grant
composition requires purely complementary bit assignments (NET-DEAD-5 uses inline grants
with exact complementary bits).

### Proposed diagnostic code

**`E-NET-DEAD-GRANT`** (WARNING, not error) — proposed new diagnostic code.

Firing condition: `dead_grant_warning?(result)` returns true when `dead_grant?(result)` is true.

Severity is WARNING (not error) because:
- A dead grant is schema-valid; rejecting it at compile time would break downstream
  code that constructs grants programmatically via compose and may not yet narrow them.
- The operational consequence of using a dead grant is that `check_policy_net4` blocks
  every operation (`E-NET-DIRECTION-BLOCKED`) — the grant is self-enforcing.
- Emitting a warning at the compose call site gives the developer early signal without
  causing a hard failure in cases where the dead grant is an intermediate result.

---

## §3 Compose bind_address Options (A/B/C)

### The gap

The canonical `compose(g1, g2)` sets `bind_address: nil` in the result unconditionally.
This discards bind_address constraints from both parents. Proved gaps:

| Case | Current behavior (Option C) |
|---|---|
| `compose(null_bind, null_bind)` | nil — correct |
| `compose(fixed_bind, null_bind)` | nil — parent bind lost |
| `compose(null_bind, fixed_bind)` | nil — child bind lost |
| `compose(fixed_bind, fixed_bind_same)` | nil — same value lost |

### Three candidate resolutions

**Option A — inherit-first**

`result.bind_address = g1.bind_address`

| Case | Result |
|---|---|
| (null, null) | nil |
| (fixed=0.0.0.0, null) | "0.0.0.0" |
| (null, fixed=0.0.0.0) | nil (g1 is nil) |
| (fixed=0.0.0.0, fixed=0.0.0.0) | "0.0.0.0" |

Tradeoff: simple to implement, but asymmetric — order of arguments changes the result.
`compose(g_fixed, g_null) != compose(g_null, g_fixed)` for bind_address. Acceptable only
if compose is documented as ordered.

**Option B — intersect**

- Both nil → nil
- One nil → nil (unconstrained side does not restrict)
- Both same non-nil → that value
- Both different non-nil → `:conflict` (caller must handle)

| Case | Result |
|---|---|
| (null, null) | nil |
| (fixed=0.0.0.0, null) | nil |
| (null, fixed=0.0.0.0) | nil |
| (fixed=0.0.0.0, fixed=0.0.0.0) | "0.0.0.0" |
| (fixed=0.0.0.0, alt=127.0.0.1) | :conflict |

Tradeoff: symmetric and principled. Conflict case forces the caller to handle a
disagreement explicitly. Most conservative — nil wins unless both sides agree.

**Option C — nil-always (current behavior)**

`result.bind_address = nil` always.

Tradeoff: simplest, backward-compatible, but lossy. Bind constraints are silently dropped
on compose, which can widen the effective bind_address scope of a composed grant beyond
either parent's intent.

### Invariant across all three options

All three variants agree on every field except `bind_address`. Core permission fields
(`connect_allowed`, `listen_allowed`, `send_allowed`, `receive_allowed`, `loopback_only`,
`tls_required`, `protocol`, `allowed_hosts`, `allowed_port_ranges`) are identical for all
three variants on the same input pair. Proved by NET-COMPOSE-BIND-13.

### Recommendation

Option B (intersect) is the most defensible for a capability security system:
- It is symmetric.
- It preserves bind_address when both sides agree (the common case for same-service compose).
- It surfaces conflicts explicitly rather than silently dropping constraints.
- The nil-wins-over-fixed behavior is conservative: if one grant is unconstrained, the
  composed result is also unconstrained rather than unexpectedly inheriting a restriction.

Adoption of Option B is left to a future canonical card; P6 documents all three and proves
the algebra for each.

---

## §4 Verification Results Table

| Group | Checks | Pass | Fail |
|---|---|---|---|
| NET-DEAD | 11 | 11 | 0 |
| NET-COMPOSE-BIND | 13 | 13 | 0 |
| NET-COMPOSE-PROPS | 9 | 9 | 0 |
| NET-STABLE-P6 | 3 | 3 | 0 |
| **Total** | **36** | **36** | **0** |

### NET-COMPOSE-PROPS summary

| Property | Check | Result |
|---|---|---|
| Idempotence (port ranges) | NET-COMPOSE-PROPS-1 | PASS |
| Idempotence (hosts) | NET-COMPOSE-PROPS-2 | PASS |
| Commutativity of permission bits | NET-COMPOSE-PROPS-3 | PASS |
| TLS monotonicity | NET-COMPOSE-PROPS-4 | PASS |
| loopback monotonicity | NET-COMPOSE-PROPS-5 | PASS |
| Protocol narrowing: `tcp_udp ∧ tcp = tcp` | NET-COMPOSE-PROPS-6 | PASS |
| Protocol conflict: `tcp ∧ udp = none` | NET-COMPOSE-PROPS-7 | PASS |
| Empty intersection (non-overlapping ports) | NET-COMPOSE-PROPS-8 | PASS |
| Empty ports absorbing | NET-COMPOSE-PROPS-9 | PASS |

---

## §5 Cumulative Proof Chain

| Card | Checks | Scope |
|---|---|---|
| LAB-STDLIB-NET-P2 | 53/53 | Schema validation, delegation algebra (8 conditions), 6 safety policies |
| LAB-STDLIB-NET-P3 | 61/61 | FFI stub surface, operation sequence, error codes |
| LAB-STDLIB-NET-P4 | 42/42 | Compiler escape classification, 10 E-NET-* diagnostic codes |
| LAB-STDLIB-NET-P5 | 44/44 | Glob semantics, direction:both, 3-hop chains, bind-address Condition 8, wildcard+loopback |
| LAB-STDLIB-NET-P6 | 36/36 | Dead grant detection, compose bind_address gap (options A/B/C), compose properties |
| **Cumulative** | **236/236** | |

---

## §6 Non-Claims

- This proof does not claim that `E-NET-DEAD-GRANT` is a stable diagnostic code. It is
  proposed here and documented as `warning?` behavior only.
- This proof does not select Option A, B, or C as the canonical `compose` bind_address
  behavior. That decision requires a canonical card outside the lab track.
- This proof does not cover multi-hop compose chains with bind_address threading (e.g.,
  three grants each with a different bind_address — that is left to a future card).
- No real network I/O was performed. All proofs are in-memory algebra.
- The `dead_grant?` predicate is proof-local. No claim is made about its integration into
  the runtime validator or compiler diagnostic pipeline.

---

## §7 Recommended Next

| Item | Rationale |
|---|---|
| Canonical card: adopt `compose` bind_address Option B | Option B is symmetric and principled; the current nil-always behavior silently drops constraints |
| Canonical card: register `E-NET-DEAD-GRANT` as a WARNING code | Compose producing a dead grant is a likely developer error; a warning at compose-time is actionable |
| LAB-STDLIB-NET-P7 (if needed): bind_address threading through 3+ compose hops | Option B behavior for `compose(compose(g1,g2), g3)` is not yet proved |
| Runtime integration: wire `dead_grant_warning?` into the capability validation pipeline | Currently proof-local only |
