# LAB-STDLIB-NET-P6

**Card ID:** LAB-STDLIB-NET-P6  
**Category:** stdlib / io / network  
**Track:** lab-experimental-io-network-capability-algebra  
**Route:** EXPERIMENTAL / LAB-ONLY / PROOF  
**Date:** 2026-06-07  
**Status:** DONE

---

## D — Deliverables

- `igniter-view-engine/proofs/network_p6_proof.rb` (NEW — 36-check proof runner)
- `lab-docs/stdlib/lab-experimental-io-network-dead-grant-compose-proof-v0.md` (NEW)
- `.agents/work/cards/stdlib/LAB-STDLIB-NET-P6.md` (this receipt)

No new fixtures were required. All grants used in P6 are built inline from the `base_grant_p6`
lambda. Existing fixtures (`direction_connect_only`, `direction_listen_only`, `direction_both`,
`bind_fixed`, `bind_alt`) are loaded for guard-only use in NET-DEAD-1/2/3.

---

## S — Summary

P6 closes the two open questions deferred from P5 §6:

**1. Dead grant detection**

A dead grant is a network capability where all four permission bits are false. P6 proves:
- `dead_grant?` correctly identifies all-false grants
- `compose(pure_connect_only, pure_listen_only)` produces a dead grant (complementary
  permission bits AND to all-false)
- Dead grant is absorbing for compose (both-sided)
- A dead grant is VALID under `valid_delegation?` (no permission escalation, since all
  bits are false)
- `check_policy_net4(dead_grant, :connect)` fires `E-NET-DIRECTION-BLOCKED`
- A dead grant is schema-valid (booleans may be false; schema does not require any true bit)
- Proposed `E-NET-DEAD-GRANT` WARNING diagnostic fires when `dead_grant_warning?` is true

**2. Compose bind_address semantics**

Current behavior (`compose` sets `bind_address: nil` always) is confirmed as Option C.
Three candidate resolutions are implemented and proved:

| Option | Strategy | bind_address result for (fixed, fixed-same) |
|---|---|---|
| A — inherit-first | `result = g1.bind_address` | "0.0.0.0" |
| B — intersect | nil if either nil; value if equal; :conflict if different | "0.0.0.0" |
| C — nil-always (current) | always nil | nil |

All three variants agree on every field except `bind_address` (NET-COMPOSE-BIND-13).

**3. Compose algebraic properties**

Nine properties proved: idempotence, commutativity of permission bits, TLS monotonicity,
loopback monotonicity, protocol narrowing, protocol conflict, empty intersection, and
empty-ports absorption.

---

## T — Technical

**Authority boundary:** proof-local only. No canon changes. No new stable API surface.

**Inlining:** `NetworkCapabilityValidatorP6` and `NetworkDelegationAlgebraP6` are copied
verbatim from P2 with P6-suffix module names to avoid constant redefinition.

**Dead grant note:** The fixture grants `direction_connect_only` and `direction_listen_only`
both have `receive_allowed: true` (shared flag in the hardening fixture set). Composing them
produces `receive_allowed: true`, which is NOT a dead grant. NET-DEAD-5 uses inline grants
with exact complementary bit assignments (connect=T/F, listen=F/T, send=T/F, receive=F/T).
This is documented behavior, not a bug.

**Option B `:conflict` sentinel:** `compose_bind_intersect` returns a hash with
`bind_address: :conflict` (Ruby Symbol) when two non-nil, different bind addresses collide.
This is a proof-local convention; a production implementation would raise an exception or
return a structured error.

---

## R — Risks and Open Questions

| Item | Status |
|---|---|
| Which bind_address option to adopt in canon | OPEN — P6 proves all three; recommendation is Option B; decision deferred to canonical card |
| `E-NET-DEAD-GRANT` diagnostic code registration | OPEN — proposed as WARNING in proof doc; not yet registered in E-NET-* code table |
| 3+ hop compose with bind_address threading | OPEN — Option B behavior for nested compose not yet proved (suggested P7) |
| Runtime integration of `dead_grant_warning?` | OPEN — proof-local only |

---

## Check Matrix

### NET-DEAD (11/11)

| Check | Description | Result |
|---|---|---|
| NET-DEAD-1 | `dead_grant?` false for connect-only fixture | PASS |
| NET-DEAD-2 | `dead_grant?` false for listen-only fixture | PASS |
| NET-DEAD-3 | `dead_grant?` false for both-direction fixture | PASS |
| NET-DEAD-4 | `dead_grant?` true for explicit all-false grant | PASS |
| NET-DEAD-5 | `compose(pure_connect_only, pure_listen_only)` → dead grant | PASS |
| NET-DEAD-6 | `compose(dead_grant, dir_both)` → dead (absorbing, left) | PASS |
| NET-DEAD-7 | `compose(dir_both, dead_grant)` → dead (absorbing, right) | PASS |
| NET-DEAD-8 | `valid_delegation?(parent, dead_grant)` → VALID | PASS |
| NET-DEAD-9 | `check_policy_net4(dead_grant, :connect)` → E-NET-DIRECTION-BLOCKED | PASS |
| NET-DEAD-10 | `validate_schema(dead_grant)` → valid: true | PASS |
| NET-DEAD-11 | `dead_grant_warning?` true for compose result | PASS |

### NET-COMPOSE-BIND (13/13)

| Check | Description | Result |
|---|---|---|
| NET-COMPOSE-BIND-1 | Current (C): (null, null) → nil | PASS |
| NET-COMPOSE-BIND-2 | Current (C): (fixed, null) → nil (parent bind lost) | PASS |
| NET-COMPOSE-BIND-3 | Current (C): (null, fixed) → nil (child bind lost) | PASS |
| NET-COMPOSE-BIND-4 | Current (C): (fixed, fixed-same) → nil (same value lost) | PASS |
| NET-COMPOSE-BIND-5 | Option A: (null, null) → nil | PASS |
| NET-COMPOSE-BIND-6 | Option A: (fixed, null) → "0.0.0.0" (g1 inherited) | PASS |
| NET-COMPOSE-BIND-7 | Option A: (null, fixed) → nil (g1=nil inherited) | PASS |
| NET-COMPOSE-BIND-8 | Option A: (fixed, fixed-same) → "0.0.0.0" | PASS |
| NET-COMPOSE-BIND-9 | Option B: (null, null) → nil | PASS |
| NET-COMPOSE-BIND-10 | Option B: (fixed, null) → nil (nil wins) | PASS |
| NET-COMPOSE-BIND-11 | Option B: (fixed, fixed-same) → "0.0.0.0" (equal intersection) | PASS |
| NET-COMPOSE-BIND-12 | Option B: (fixed=0.0.0.0, alt=127.0.0.1) → :conflict | PASS |
| NET-COMPOSE-BIND-13 | All three variants agree on core permission fields | PASS |

### NET-COMPOSE-PROPS (9/9)

| Check | Description | Result |
|---|---|---|
| NET-COMPOSE-PROPS-1 | Idempotence: port ranges unchanged | PASS |
| NET-COMPOSE-PROPS-2 | Idempotence: hosts unchanged | PASS |
| NET-COMPOSE-PROPS-3 | Commutativity: permission bits symmetric | PASS |
| NET-COMPOSE-PROPS-4 | TLS monotonicity | PASS |
| NET-COMPOSE-PROPS-5 | loopback monotonicity | PASS |
| NET-COMPOSE-PROPS-6 | Protocol narrowing: tcp_udp ∧ tcp = tcp | PASS |
| NET-COMPOSE-PROPS-7 | Protocol conflict: tcp ∧ udp = none | PASS |
| NET-COMPOSE-PROPS-8 | Empty intersection: non-overlapping ports → [] | PASS |
| NET-COMPOSE-PROPS-9 | Empty ports absorbing: compose(empty, g) → empty | PASS |

### NET-STABLE-P6 (3/3)

| Check | Description | Result |
|---|---|---|
| NET-STABLE-P6-1 | No real socket references (split-string guard) | PASS |
| NET-STABLE-P6-2 | igniter-lang untouched (git status --porcelain) | PASS |
| NET-STABLE-P6-3 | P6 does not require network_ffi_stub | PASS |

### Total: 36/36 PASS

---

## Proof Chain (complete through P6)

| Card | Checks | Cumulative |
|---|---|---|
| LAB-STDLIB-NET-P2 | 53/53 | 53 |
| LAB-STDLIB-NET-P3 | 61/61 | 114 |
| LAB-STDLIB-NET-P4 | 42/42 | 156 |
| LAB-STDLIB-NET-P5 | 44/44 | 200 |
| LAB-STDLIB-NET-P6 | 36/36 | **236** |
