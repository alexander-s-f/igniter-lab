# Lab Documentation: Experimental IO.NetworkCapability — Compiler Diagnostic Proof (v0)

**Card**: `LAB-STDLIB-NET-P4`
**Track**: `lab-experimental-io-network-compiler-diagnostic-proof-v0`
**Route**: `EXPERIMENTAL / LAB-ONLY`
**Status**: `accept`
**Depends on**: LAB-STDLIB-NET-P1, LAB-STDLIB-NET-P2, LAB-STDLIB-NET-P3
**Pattern**: follows LAB-STDLIB-IO-P2 (compiler E-IO-* diagnostic proofs) exactly, applied to E-NET-* codes

---

## 1. Design Stance and Motivation

LAB-STDLIB-NET-P1 §5.4 defined 10 E-NET-* diagnostic codes for compiler-time network
capability violations, directly analogous to the E-IO-* codes from LAB-STDLIB-IO-P2.
This card completes the proof that:

1. **`stdlib.io.network.*` calls are classified as `escape` nodes** (not `core`), matching
   the LAB-STDLIB-IO-P2 §1 rule that computations calling side-effecting stdlib functions
   must be classified at escape/effect boundaries.

2. **All 10 E-NET-* diagnostic codes fire correctly** on well-chosen fixture Igniter source
   programs, with correct node classification (`blocked`) and informative diagnostic messages.

The proof uses a **proof-local Ruby classifier** (`NetworkIGClassifier`) that parses
illustrative `.ig` source programs and applies all 10 diagnostic rules. No real Igniter
compiler binary is invoked; no real TCP connections are made.

---

## 2. Node Classification Rules

### 2.1 Escape Classification

A contract node calling any `stdlib.io.network.*` function with a properly declared
`IO.NetworkCapability` and a matching `effect...using` binding is classified as **`escape`**
(not `core`). This matches Covenant Postulate 4 and the LAB-STDLIB-IO-P2 rule:

> "Computations calling `stdlib.IO.*` are classified as `'escape'` rather than `'core'`
> nodes, mapping them cleanly to escape/effect boundaries."

The same classification applies to `stdlib.io.network.*`. No network operation can be
`core` because:
- Network I/O depends on external state (other processes, the kernel network stack)
- Network operations carry `unknown_external_state` failure potential (Covenant Postulate 15)
- Network effects must be named and bound (`effect...using`) to be auditable

### 2.2 Classification Matrix

| Condition | `node_class` |
|---|---|
| Valid capability + effect binding + matching network call | `escape` |
| No capability declared, no network calls | `core` |
| Any diagnostic fires (any E-NET-* code) | `blocked` |

---

## 3. Syntax Specifications

All syntax in this document is labeled **"Illustrative only — not canon syntax."**

### 3.1 Capability Declaration

```igniter
-- Illustrative only — not canon syntax
capability net_conn: IO.NetworkCapability { loopback_only: true, connect_allowed: true, listen_allowed: false, protocol: "tcp", allowed_hosts: "127.0.0.1", port_lo: 8000, port_hi: 9000, tls_required: false }
```

### 3.2 Effect Binding

```igniter
-- Illustrative only — not canon syntax
effect connect_to_service using net_conn
```

### 3.3 Network Call

```igniter
-- Illustrative only — not canon syntax
stdlib.io.network.connect(host: "127.0.0.1", port: 8080, cap: net_conn)
stdlib.io.network.connect(host: "api.example.com", port: 443, cap: net_out, tls: true, protocol: "tcp")
```

---

## 4. Diagnostic Codes

All 10 E-NET-* codes from LAB-STDLIB-NET-P1 §5.4, each proved to fire on its fixture:

| Code | Trigger condition | File IO analog |
|---|---|---|
| `E-NET-AMBIENT-BLOCKED` | Network call in pure contract with no `IO.NetworkCapability` declared | `E-IO-AMBIENT-BLOCKED` |
| `E-NET-CAP-MISSING` | `stdlib.io.network.*` call missing `cap:` argument | `E-IO-CAP-MISSING` |
| `E-NET-CAP-UNKNOWN` | `cap:` argument refers to a name not declared in the contract | `E-IO-CAP-UNKNOWN` |
| `E-NET-EFFECT-UNDECLARED` | Capability declared but no `effect...using` binding | `E-IO-EFFECT-UNDECLARED` |
| `E-NET-DIRECTION-BLOCKED` | Op direction (connect/listen) blocked by capability flags | `E-IO-CAP-WRONG-MODE` |
| `E-NET-HOST-BLOCKED` | Target host not in `allowed_hosts` | new — no file IO analog |
| `E-NET-PORT-BLOCKED` | Target port outside `allowed_port_ranges` | new — no file IO analog |
| `E-NET-LOOPBACK-VIOLATION` | Non-loopback host with `loopback_only: true` capability | new — no file IO analog |
| `E-NET-TLS-REQUIRED` | Plaintext connection (`tls: false`) with `tls_required: true` | new — no file IO analog |
| `E-NET-PROTOCOL-MISMATCH` | Call protocol incompatible with capability protocol field | new — no file IO analog |

---

## 5. Fixture Programs

15 fixture `.ig` source programs in `fixtures/network_capability_compiler/`:

| File | Scenario | Expected class | Expected code |
|---|---|---|---|
| `good_connect.ig` | Valid loopback connect contract | `escape` | (none) |
| `good_listen.ig` | Valid loopback listen contract | `escape` | (none) |
| `good_tls_outbound.ig` | Valid TLS outbound (Variant C) | `escape` | (none) |
| `pure_no_network.ig` | Pure contract, no network calls | `core` | (none) |
| `ambient_blocked.ig` | Pure contract calls network | `blocked` | `E-NET-AMBIENT-BLOCKED` |
| `cap_missing.ig` | Call missing `cap:` argument | `blocked` | `E-NET-CAP-MISSING` |
| `cap_unknown.ig` | `cap:` refers to undeclared name | `blocked` | `E-NET-CAP-UNKNOWN` |
| `effect_undeclared.ig` | Capability with no `effect...using` | `blocked` | `E-NET-EFFECT-UNDECLARED` |
| `direction_blocked.ig` | connect-only cap, `listen` call | `blocked` | `E-NET-DIRECTION-BLOCKED` |
| `listen_only_dir_blocked.ig` | listen-only cap, `connect` call | `blocked` | `E-NET-DIRECTION-BLOCKED` |
| `host_blocked.ig` | Host not in `allowed_hosts` | `blocked` | `E-NET-HOST-BLOCKED` |
| `port_blocked.ig` | Port outside `allowed_port_ranges` | `blocked` | `E-NET-PORT-BLOCKED` |
| `loopback_violation.ig` | Non-loopback host, `loopback_only` cap | `blocked` | `E-NET-LOOPBACK-VIOLATION` |
| `tls_required.ig` | Plaintext call, `tls_required: true` | `blocked` | `E-NET-TLS-REQUIRED` |
| `protocol_mismatch.ig` | `udp` call on `tcp`-only cap | `blocked` | `E-NET-PROTOCOL-MISMATCH` |

---

## 6. Verification Results

Running `ruby proofs/network_compiler_diagnostic_proof.rb` verifies all 42 checks:

| Group | Checks | Result |
|---|---|---|
| NET-CLASS (escape/core classification) | 3 | **3/3 PASS** |
| NET-BLOCKED (blocked classification for invalid programs) | 5 | **5/5 PASS** |
| NET-ECODE (all 10 E-NET-* codes fire) | 10 | **10/10 PASS** |
| NET-GOOD (valid contracts — zero diagnostics) | 5 | **5/5 PASS** |
| NET-CAP-PARSE (capability/effect metadata) | 5 | **5/5 PASS** |
| NET-DIRECTION (connect vs listen direction enforcement) | 4 | **4/4 PASS** |
| NET-DETAIL (diagnostic messages carry context) | 5 | **5/5 PASS** |
| NET-STABLE (code constants, closed-surface, no real I/O) | 5 | **5/5 PASS** |
| **Total** | **42** | **42/42 PASS** |

### Key checks

| Check | What is proved |
|---|---|
| NET-CLASS-1,2 | `good_connect.ig`, `good_listen.ig` → `node_class == "escape"` |
| NET-CLASS-3 | `pure_no_network.ig` → `node_class == "core"` (no network calls = core) |
| NET-BLOCKED-1..5 | Every error-bearing fixture → `node_class == "blocked"` |
| NET-ECODE-1..10 | Each of the 10 E-NET-* codes fires on its designated fixture |
| NET-GOOD-1..4 | Valid contracts produce zero diagnostics (no spurious errors) |
| NET-CAP-PARSE-1..5 | Capability params (loopback_only, listen_allowed, tls_required) parsed |
| NET-DIR-1,2 | Both direction-block vectors produce E-NET-DIRECTION-BLOCKED |
| NET-DIR-3,4 | Valid direction → no E-NET-DIRECTION-BLOCKED (no false positives) |
| NET-DETAIL-1..5 | Blocked host/port/host names appear in diagnostic messages |
| NET-STABLE-3 | No TCPSocket / UDPSocket / Socket.new in proof runner |
| NET-STABLE-4 | `igniter-lang` repo untouched (closed-surface scan) |
| NET-STABLE-5 | P4 classifier is independent of P3 FFI stub |

---

## 7. Cumulative Proof Chain

| Card | Checks | Scope |
|---|---|---|
| LAB-STDLIB-NET-P2 | 53/53 | Schema validation, delegation algebra, safety policies NET-1–NET-6 |
| LAB-STDLIB-NET-P3 | 61/61 | FFI surface contract, stub mode, operation sequence |
| LAB-STDLIB-NET-P4 | 42/42 | Compiler escape classification, all 10 E-NET-* diagnostic codes |
| **Total** | **156/156** | |

---

## 8. Non-Claims

This work does **not** claim:

- Mainline `igniter-lang` compiler implements `IO.NetworkCapability` or any E-NET-* codes.
- The `.ig` syntax shown is canon or stable — it is illustrative only.
- The proof-local classifier is a production compiler; it is a lab-only proof tool.
- Any real network I/O is performed at any point in this proof chain.
- The service loop (PROP-039+) or streaming body (PROP-023) work is unblocked by this card.
- Stage 4 governance is opened by this card.

---

## 9. Tensions / Open Questions

**1. Diagnostic rule priority under multiple violations.**
The classifier applies AMBIENT_BLOCKED as a short-circuit (fires and returns immediately when
no capability is declared). For other rules, multiple diagnostics can fire in one classify()
call (e.g., a call with a bad host AND a bad port would fire both E-NET-HOST-BLOCKED and
E-NET-PORT-BLOCKED). Whether the real compiler should short-circuit or report all violations
per call is a design decision deferred to PROP-035.

**2. Effect-undeclared scope.**
The current rule fires E-NET-EFFECT-UNDECLARED for any capability that has no `effect...using`
binding, even if that capability is never used in a network call. Whether an unused declared
capability should produce a warning (vs. error) is deferred.

**3. Direction "both" coverage.**
The `direction: "both"` / `connect_allowed: true, listen_allowed: true` combination is present
in the P2 algebra but not exercised in P4 fixtures. The open question from P2 (compose behavior
for `direction: "both"`) remains unresolved.

---

## 10. Recommended Next

**LAB-STDLIB-NET-P5** — Network Capability Hardening (analog to LAB-STDLIB-IO-P9)

With all four core cards (P1–P4) complete for `IO.NetworkCapability`, the natural next step is
a hardening proof that validates edge cases identified in P1–P4:

- Glob host matching semantics: `*.example.com` vs `api.example.com` vs the root domain
- `direction: "both"` compose behavior when combining connect + listen grants
- Multi-hop delegation chains across 3+ grants (does each hop reduce scope correctly?)
- Bind-address restriction enforcement (a P2 delegation rule not exercised in P4 fixtures)
- Wildcard `allowed_hosts: "*"` + `loopback_only: true` interaction (exercised in
  `loopback_violation.ig` but deserves explicit algebra proof)

Authorized writes would follow the P2 pattern: new fixture JSON + proof runner only.
