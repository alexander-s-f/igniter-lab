# Lab Documentation: Experimental IO.NetworkCapability — Hardening Proof (v0)

**Card**: `LAB-STDLIB-NET-P5`
**Track**: `lab-experimental-io-network-hardening-proof-v0`
**Route**: `EXPERIMENTAL / LAB-ONLY`
**Status**: `accept`
**Depends on**: LAB-STDLIB-NET-P1, LAB-STDLIB-NET-P2, LAB-STDLIB-NET-P3, LAB-STDLIB-NET-P4
**Analog to**: LAB-STDLIB-IO-P9 (file I/O hardening)

---

## 1. Design Stance and Motivation

P1 documented five open questions deferred from the initial algebra design. P2–P4 closed
the core proof surface but intentionally left these questions unresolved. This card closes
all five through explicit proof-runner checks.

**Questions closed by P5:**

| # | Question (from P1/P2/P4) | Resolution |
|---|---|---|
| 1 | Glob host matching semantics (`*.example.com`) | **Opaque-literal resolution**: `host_subset?` treats all host strings as opaque identifiers — `*.example.com` ≠ `api.example.com`. Glob expansion is deferred to a future runtime layer. |
| 2 | `direction:"both"` compose behavior | **AND semantics proved**: `compose()` applies `&&` to all permission bits. `compose(connect_only, listen_only)` = both bits false (dead grant). `direction:"both"` parents produce valid single-direction sub-grants. |
| 3 | Multi-hop delegation chains (3+ grants) | **Transitivity proved**: G1→G2→G3 valid implies G1→G3 valid. Compose is associative for key fields. Each hop reduces scope. |
| 4 | Bind-address restriction enforcement | **Condition 8 proved**: fires only when both parent and child have non-null bind_address values that differ. Null parent allows any child bind_address. Non-null parent + null child is valid. |
| 5 | Wildcard `allowed_hosts:"*"` + `loopback_only:true` interaction | **Independent checks proved**: NET-1 (loopback) and NET-2 (host allowlist) are independent. `*` wildcard passes NET-2 for any host, but `loopback_only:true` makes NET-1 fail for non-loopback hosts. Loopback restriction cannot be bypassed by wildcard. |

---

## 2. Resolved Design Decisions

### 2.1 Host Matching: Opaque-Literal Resolution

**Question (P1 §Tensions/1):** What are the glob matching semantics for `allowed_hosts`?
Does `*.example.com` match `api.example.com`?

**Resolution:** The P2 algebra (`NetworkDelegationAlgebra#host_subset?`) treats all host
strings as opaque identifiers. `*.example.com` is a literal string, not a pattern. Therefore:

- `host_subset?(["api.example.com"], ["*.example.com"])` → **false** (NET-GLOB-2)
- `host_subset?(["*.example.com"], ["*.example.com"])` → **true** (same literal; NET-GLOB-3)
- `host_subset?(["api.example.com"], ["*"])` → **true** (full-wildcard sentinel; NET-GLOB-4)

This is a **conservative** resolution: the algebra never falsely permits a host delegation.
Glob expansion, if desired, must be implemented as a separate runtime layer that resolves
patterns before calling `host_subset?`. The compiler-layer algebra is not the right place
for glob expansion.

**Consequence for delegation:** A parent grant with `allowed_hosts: ["*.example.com"]`
can only be delegated to a child with exactly `["*.example.com"]` or a subset of it as
literal strings. A child with `["api.example.com"]` would require `E-NET-DELEGATION-HOST-ESCAPE`
unless the parent also contains `"api.example.com"` literally or uses `"*"` (NET-GLOB-8,9).

### 2.2 direction:"both" Compose: AND Semantics

**Question (P1 §Tensions/2):** What does compose produce when combining a `connect`-only
and `listen`-only grant?

**Resolution (NET-BOTH-2):**

```
compose(connect_only, listen_only):
  connect_allowed = true  && false = false
  listen_allowed  = false && true  = false
  → "dead grant": neither connect nor listen permitted
```

This follows the compose operator's `&&` rule for all permission bits (P2 §4.3). A dead
grant is mathematically valid but operationally useless — any `check_policy_net4` call
on it would return `E-NET-DIRECTION-BLOCKED`.

**Key corollaries proved (NET-BOTH-3..8):**
- `compose(both, connect_only)` = connect-only result ✓
- `compose(both, listen_only)` = listen-only result ✓
- `compose(both, both)` = both still true ✓
- `valid_delegation?(both_parent, connect_child)` = valid ✓
- `valid_delegation?(both_parent, listen_child)` = valid ✓
- `valid_delegation?(connect_parent, listen_child)` = invalid, PERMISSION_ESCALATION ✓

### 2.3 Multi-Hop Chains: Transitivity and Associativity

**Chain structure (G1 → G2 → G3):**

| Grant | Protocol | Hosts | Port range | TLS |
|---|---|---|---|---|
| G1 (root) | `tcp_udp` | `["*"]` | 1–65535 | false |
| G2 (mid) | `tcp` | `["api.example.com"]` | 443–8080 | false |
| G3 (leaf) | `tcp` | `["api.example.com"]` | 443–443 | true |

**Transitivity (NET-CHAIN-3):** G3 ⊑ G1 directly is valid. Every scope restriction
imposed by G2 is a subset of G1's scope, and G3 is a subset of G2's scope — therefore
G3 is necessarily a subset of G1's scope.

**Compose associativity (NET-CHAIN-9):** `compose(G1, compose(G2, G3))` and
`compose(compose(G1, G2), G3)` produce identical `protocol`, `connect_allowed`, and
`allowed_port_ranges` values.

**TLS hardening direction (NET-CHAIN-7,8):**
- G2 (no TLS) → G3 (tls_required) is **valid**: adding TLS enforcement is non-escalating ✓
- G3 (tls_required) → G2 (no TLS) is **invalid** (`E-NET-DELEGATION-TLS-DOWNGRADE`) ✓

### 2.4 Bind-Address Condition 8 Behavior Matrix

| parent.bind_address | child.bind_address | Condition 8 fires? |
|---|---|---|
| `null` | `null` | No |
| `null` | `"127.0.0.1"` | **No** — null parent permits any (NET-BIND-4) |
| `"0.0.0.0"` | `null` | **No** — child null is always valid (NET-BIND-5) |
| `"0.0.0.0"` | `"0.0.0.0"` | No — same value (NET-BIND-2) |
| `"0.0.0.0"` | `"127.0.0.1"` | **Yes** → `E-NET-DELEGATION-BIND-ESCALATION` (NET-BIND-3) |

Condition 8 is a precision rule: it fires **only** when both grants have explicitly
specified (non-null) bind addresses that differ. This allows a root grant (null bind)
to delegate to any specific bind address without triggering escalation.

### 2.5 Wildcard + Loopback: Independent Policy Checks

**The invariant (NET-WILD-3,4):** For a capability with `allowed_hosts: ["*"]` and
`loopback_only: true`:

- `check_policy_net2(cap, "external.example.com")` → `ok: true` (wildcard passes)
- `check_policy_net1(cap, "external.example.com")` → `ok: false, code: "E-NET-LOOPBACK-VIOLATION"`

The wildcard in `allowed_hosts` **cannot** override `loopback_only`. These are independent
policy dimensions. An implementation checking both policies must apply each independently
and reject if either fails. The `loopback_only` field is strictly stronger: it constrains
the universe of permitted hosts to the loopback address space, regardless of what
`allowed_hosts` says.

---

## 3. Verification Results

Running `ruby proofs/network_hardening_proof.rb` verifies all 44 checks:

| Group | Scope | Checks | Result |
|---|---|---|---|
| NET-GLOB | Host matching semantics (opaque-literal resolution) | 9 | **9/9 PASS** |
| NET-BOTH-DIR | direction:both compose and delegation | 8 | **8/8 PASS** |
| NET-CHAIN | Multi-hop G1→G2→G3 chain (transitivity, associativity) | 10 | **10/10 PASS** |
| NET-BIND | Bind-address Condition 8 (4-case matrix) | 6 | **6/6 PASS** |
| NET-WILD | Wildcard + loopback_only independence | 6 | **6/6 PASS** |
| NET-STABLE | Module integrity, all 7 delegation codes producible, closed-surface | 5 | **5/5 PASS** |
| **Total** | | **44** | **44/44 PASS** |

---

## 4. Cumulative Proof Chain

| Card | Checks | Scope |
|---|---|---|
| LAB-STDLIB-NET-P2 | 53/53 | Schema validation, delegation algebra, safety policies NET-1–NET-6 |
| LAB-STDLIB-NET-P3 | 61/61 | FFI surface contract, stub mode, operation sequence |
| LAB-STDLIB-NET-P4 | 42/42 | Compiler escape classification, all 10 E-NET-* diagnostic codes |
| LAB-STDLIB-NET-P5 | 44/44 | Hardening: glob semantics, direction:both, chains, bind-address, wildcard+loopback |
| **Total** | **200/200** | |

---

## 5. Non-Claims

This work does **not** claim:

- That the glob-expansion decision is final — a future card could add a runtime glob
  resolver layer on top of the algebra without changing any P2 algebra rules.
- That "dead grants" (both permission bits false) are rejected at schema validation time;
  they are algebraically valid but operationally useless.
- That compose associativity holds for `bind_address` (the compose operator sets
  `bind_address: nil` in the result — this is a known open question in P2).
- Mainline `igniter-lang` implementation of any of the above.

---

## 6. Remaining Open Questions

**1. Compose does not preserve bind_address.**
The compose operator (P2 §4.3) sets `bind_address: nil` in the result, discarding both
parents' bind addresses. Whether the composed grant should inherit one parent's bind
address (and which) is not defined. This is a known gap.

**2. Dead grant detection.**
A grant where `connect_allowed = listen_allowed = send_allowed = receive_allowed = false`
is a valid schema object but can never authorize any operation. Whether such grants should
be rejected at `validate_schema` time (with a new error code `E-NET-DEAD-GRANT`) is
deferred to a future hardening card.

**3. Multi-level wildcard syntax.**
The `*` sentinel is currently the only recognized wildcard. There is no `**` (recursive)
or `?.example.com` (single-char) syntax. If glob patterns are added in a future layer,
their semantics must be proved explicitly.

---

## 7. Recommended Next

The `IO.NetworkCapability` P1–P5 proof chain is now complete for the core lab scope.
The natural next track depends on which gap matters most:

- **LAB-STDLIB-NET-P6** — Dead grant detection + compose bind_address gap (technical debt from §6)
- **LAB-LANG-HTTP-TYPES-P1** — Prove `ContractRef[HttpRequest, HttpResponse]` dispatch pattern
  (the middleware composition model mentioned in LAB-RACK-P1)
- **Back to LAB-WEB-FRAMEWORK-P4+** — Continue the web framework track (layout primitives,
  i18n) now that the network capability foundation is proved

All three are independent tracks. P6 is the most mechanically obvious; HTTP types and
web framework are higher leverage for the Igniter product direction.
