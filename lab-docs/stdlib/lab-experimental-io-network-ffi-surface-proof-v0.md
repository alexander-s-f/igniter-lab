# Lab: stdlib/io/network — FFI Surface Contract Proof (v0)

> Status: experimental · lab-only · proof-local · no real TCP
> Card: LAB-STDLIB-NET-P3
> Date: 2026-06-07
> Track: lab-experimental-io-network-ffi-surface-proof-v0
> Depends on: LAB-STDLIB-NET-P1 (schema), LAB-STDLIB-NET-P2 (algebra)

---

## Pre-v1 Language Note

Igniter Lang is under active development. All constructs described in this
document — including FFI surface shapes, receipt taxonomy, stub architecture,
and policy enforcement patterns — are drawn from established lab patterns
(IO-P1 through P10, NET-P1, NET-P2) and the proposed stdlib/io/network design
sketch from LAB-STDLIB-NET-P1 §7. They are not stable APIs. This document is
lab-only proof evidence. It does not constitute canon specification, a PROP,
or a production commitment. The source `igniter-lang` documents remain the
reference for all formal decisions. The `stub_mode: true` marker on every
receipt in this proof explicitly distinguishes all receipts from production
evidence.

---

## 1. Purpose

This document records what LAB-STDLIB-NET-P3 proves:

- **FFI surface shape**: six named C ABI functions (`stdlib_io_network_connect`,
  `listen`, `accept`, `send`, `receive`, `close`) exist, accept the expected
  arguments, and return JSON-serialized `ok`/`err` envelopes — the same envelope
  shape established in IO-P1 §4.
- **Receipt taxonomy**: every successful operation returns a typed receipt or
  observation with `stub_mode: true`, `capability_id`, `timestamp`, and the
  operation-specific fields documented in §2.2.
- **Policy enforcement at the FFI boundary**: all six NET safety policies
  (NET-1 through NET-6 from LAB-STDLIB-NET-P1 §3) are checked before any
  registry mutation occurs. Policy violations produce structured `err` envelopes
  with the correct `E-NET-*` error codes.
- **No-real-network guarantee**: the stub contains no TCPSocket, UDPSocket,
  Socket, Net::HTTP, or socket/net-http require calls in non-comment code. All
  state is in-memory only (CONNECTIONS/LISTENERS hashes). Every receipt carries
  `stub_mode: true`.
- **TLS-required caps explicitly refused**: because a stub cannot negotiate TLS,
  capabilities with `tls_required: true` return `StubModeError` rather than
  silently permitting a plaintext connection.
- **Relationship to IO-P1 file FFI pattern**: the network FFI surface follows
  the same `ok`/`err` envelope, the same capability-as-JSON-arg pattern, and
  the same `capability_id` in receipts as the file IO FFI from IO-P1 §3–4.

---

## 2. FFI Surface Contract

### 2.1 C ABI Signatures (documented, not yet in Rust)

All functions accept null-terminated UTF-8 strings and return dynamically
allocated null-terminated JSON strings. Memory is managed by
`stdlib_io_network_free_string` in the Rust implementation (no-op in the Ruby
stub — GC handles memory).

| Function | Params | Return |
|---|---|---|
| `stdlib_io_network_connect` | `host`, `port`, `cap_json` | ConnectReceipt \| NetworkError |
| `stdlib_io_network_listen` | `bind_addr`, `port`, `cap_json` | ListenReceipt \| NetworkError |
| `stdlib_io_network_accept` | `listener_id`, `cap_json` | AcceptReceipt \| NetworkError |
| `stdlib_io_network_send` | `conn_id`, `data`, `cap_json` | SendReceipt \| NetworkError |
| `stdlib_io_network_receive` | `conn_id`, `max_bytes`, `cap_json` | ReceiveObservation \| NetworkError |
| `stdlib_io_network_close` | `conn_id`, `cap_json` | CloseReceipt \| NetworkError |
| `stdlib_io_network_free_string` | `ptr` | void |

### 2.2 Return Taxonomy

| Type | When returned | Key fields |
|---|---|---|
| ConnectReceipt | connect succeeds | `connection_id`, `host`, `port`, `protocol`, `timestamp`, `capability_id`, `stub_mode: true` |
| ListenReceipt | listen succeeds | `listener_id`, `bind_address`, `port`, `protocol`, `timestamp`, `capability_id`, `stub_mode: true` |
| AcceptReceipt | accept succeeds | `connection_id`, `listener_id`, `peer_address`, `peer_port`, `timestamp`, `capability_id`, `stub_mode: true` |
| SendReceipt | send succeeds | `bytes_sent`, `connection_id`, `timestamp`, `capability_id`, `stub_mode: true` |
| ReceiveObservation | receive succeeds | `data`, `bytes_received`, `connection_id`, `timestamp`, `capability_id`, `stub_mode: true` |
| CloseReceipt | close succeeds | `connection_id`, `timestamp`, `capability_id`, `stub_mode: true` |
| NetworkError | any failure | `error_type`, `message`, `code` (E-NET-*), `capability_id` |

All successful receipts use the `{"ok": <receipt>}` envelope.
All failures use the `{"err": <NetworkError>}` envelope.
No other top-level keys are permitted.

### 2.3 Error Taxonomy

| error_type | When triggered | code field |
|---|---|---|
| `CapabilityError` | NET policy violation (NET-1 through NET-6) or schema invalid | `E-NET-LOOPBACK-VIOLATION`, `E-NET-HOST-BLOCKED`, `E-NET-PORT-BLOCKED`, `E-NET-DIRECTION-BLOCKED`, `E-NET-PROTOCOL-MISMATCH`, `E-NET-SCHEMA-INVALID` |
| `ConnectionNotFound` | conn_id not in registry or connection is closed | `E-NET-CONNECTION-NOT-FOUND` |
| `ListenerNotFound` | listener_id not in registry | `E-NET-LISTENER-NOT-FOUND` |
| `InvalidJson` | malformed cap_json argument | `E-INVALID-JSON` |
| `StubModeError` | `tls_required: true` — stub cannot negotiate TLS | `E-STUB-TLS-UNVERIFIABLE` |
| `ProtocolError` | reserved; not yet triggered in stub | — |

---

## 3. Stub Architecture

### 3.1 Module Structure

`lib/network_ffi_stub.rb` contains:

- **Part A**: `NetworkCapabilityValidator`, `NetworkDelegationAlgebra`,
  `PassportValidator` — copied verbatim from P2 proof runner to ensure
  consistent policy enforcement across both proofs.
- **Part B**: C ABI signature documentation as comments — the Rust signatures
  that this stub simulates.
- **Part C**: Return taxonomy type documentation as comments.
- **Part D**: `NetworkFFIStub` module with `CONNECTIONS` and `LISTENERS`
  hashes (thread-unsafe, proof-local) and `reset!` for test isolation.
- **Part E**: Six FFI function implementations as Ruby class methods on
  `NetworkFFIStub`.

### 3.2 In-Memory Registry

`CONNECTIONS` maps `conn_id → { host, port, protocol, capability_id, open }`.
`LISTENERS` maps `listener_id → { bind_address, port, protocol, capability_id, open }`.

IDs are generated with `SecureRandom.hex(8)` prefixed with `conn-` or `lst-`.
`reset!` clears both hashes for test isolation.

### 3.3 No-Real-TCP Guarantee

- No `require 'socket'` or `require 'net/http'` in the stub.
- No `TCPSocket`, `UDPSocket`, or `Socket` usage in non-comment code.
- Every receipt carries `stub_mode: true` — an explicit marker that the
  operation did not create a real OS resource.
- `stdlib_io_network_free_string` is a documented no-op: in Rust this would
  release the C-string allocation; in Ruby the GC handles it.

### 3.4 TLS Stub Mode Handling

Capabilities with `tls_required: true` (e.g. Variant C) are checked before
any host/port/direction policy. The stub returns `StubModeError` with
`E-STUB-TLS-UNVERIFIABLE` — it refuses rather than silently permitting a
plaintext connection that would violate the TLS contract. This is the correct
safe-default behavior: fail closed, not open.

### 3.5 P2 Validator Reuse

`NetworkCapabilityValidator.validate_schema` and all six `check_policy_net*`
methods are called identically to P2. The stub does not re-implement policy
logic — it delegates entirely to the P2 validator, ensuring a single source of
truth for policy enforcement.

---

## 4. What is Proven

| Check group | Count | What it validates |
|---|---|---|
| NET-FFI | 8 | All 6 FFI methods exist; return values are valid JSON with ok/err envelope |
| NET-CONN | 19 | Full connect→send→receive→close lifecycle; receipt fields; registry storage |
| NET-LISTEN | 10 | listen→accept lifecycle; ListenReceipt and AcceptReceipt fields |
| NET-FFI-POLICY | 7 | NET-1 loopback, NET-2 host, NET-3 port, NET-4 direction, StubModeError for tls_required, InvalidJson, wrong resource_type |
| NET-FFI-REGISTRY | 5 | ConnectionNotFound, ListenerNotFound, reset! isolation |
| NET-FFI-GUARD | 3 | No real socket usage in stub; stub_mode:true in all lifecycle receipts; no real socket usage in proof runner |
| NET-FFI-C | 4 | Variant C (tls_required) refuses with StubModeError; port/host blocked on tls=false variant |
| NET-EXTRA | 5 | Registry coherence, post-close state, distinct IDs, envelope shape |
| **Total** | **61** | |

---

## 5. Non-Claims

- No real TCP connections are established. All state is in-memory.
- The Rust implementation does not exist. These are Ruby simulations of the C ABI.
- `stub_mode: true` explicitly marks all receipts as non-production evidence.
- TLS enforcement is not implementable in the stub — `StubModeError` is the
  correct response for `tls_required: true` capabilities.
- This proof establishes the interface contract (shape, taxonomy, policies),
  not runtime behavior (latency, ordering, concurrent access).
- Thread safety is not guaranteed — `CONNECTIONS` and `LISTENERS` are plain
  Ruby hashes. This is a proof-local limitation, not a design claim.
- No `igniter-lang` source files, spec chapters, or covenant text were modified.

---

## 6. Open Questions Surfaced by P3

**Q1 — TLS stub mode tension**: The stub refuses `tls_required: true` caps with
`StubModeError`. This means variant C cannot be exercised end-to-end in stub
mode. The Rust implementation must implement TLS negotiation (e.g. via rustls)
before variant C caps can be used without `StubModeError`. This creates a
two-tier testing gap: stub-mode tests cannot cover TLS paths.

**Q2 — Direction field coherence**: Variant A has `direction: "connect"` but
`listen_allowed: false`, `send_allowed: true`, `receive_allowed: true`. The
`direction` field and the `*_allowed` permission bits are partially redundant.
The P2 open question about which field is authoritative remains: the stub uses
`*_allowed` bits (via NET-4) as the authoritative permission, not `direction`.
A P4 compiler diagnostic proof should clarify whether `direction` is enforced
at compile time or only at runtime.

**Q3 — accept() with receive_allowed=false**: The stub checks both
`listen_allowed` and `receive_allowed` for `accept()`. Variant B has both as
true, so this is not exercised in the failure path. A capability with
`listen_allowed: true` but `receive_allowed: false` would fail accept. Is that
the right behavior? The recv check in accept models "you must be able to receive
data from the accepted connection", but it could be argued that the recv check
belongs on the `receive()` call instead.

**Q4 — Free string no-op documentation**: `stdlib_io_network_free_string` is
a no-op in Ruby. In the Rust implementation, incorrect handling of this function
(e.g. double-free, forgetting to call it) creates memory safety issues. The
FFI contract must specify ownership clearly: the Rust function allocates the
string with `CString::new(...).into_raw()`, and the caller (the Ruby FFI layer)
is responsible for calling `stdlib_io_network_free_string` after use.

---

## 7. Proof Results

```
.............................................................
============================================================================
NetworkFFI Proof — Results Matrix (LAB-STDLIB-NET-P3)
============================================================================
  GROUP                CHECK                    STATUS
----------------------------------------------------------------------------
  NET-FFI              NET-FFI-1                PASS
  NET-FFI              NET-FFI-2                PASS
  NET-FFI              NET-FFI-3                PASS
  NET-FFI              NET-FFI-4                PASS
  NET-FFI              NET-FFI-5                PASS
  NET-FFI              NET-FFI-6                PASS
  NET-FFI              NET-FFI-7                PASS
  NET-FFI              NET-FFI-8                PASS

  NET-CONN             NET-CONN-1a              PASS
  NET-CONN             NET-CONN-1b              PASS
  NET-CONN             NET-CONN-1c              PASS
  NET-CONN             NET-CONN-1d              PASS
  NET-CONN             NET-CONN-1e              PASS
  NET-CONN             NET-CONN-1f              PASS
  NET-CONN             NET-CONN-1g              PASS
  NET-CONN             NET-CONN-2               PASS
  NET-CONN             NET-CONN-3a              PASS
  NET-CONN             NET-CONN-3b              PASS
  NET-CONN             NET-CONN-3c              PASS
  NET-CONN             NET-CONN-4a              PASS
  NET-CONN             NET-CONN-4b              PASS
  NET-CONN             NET-CONN-4c              PASS
  NET-CONN             NET-CONN-4d              PASS
  NET-CONN             NET-CONN-5a              PASS
  NET-CONN             NET-CONN-5b              PASS
  NET-CONN             NET-CONN-5c              PASS
  NET-CONN             NET-CONN-6               PASS

  NET-LISTEN           NET-LISTEN-1a            PASS
  NET-LISTEN           NET-LISTEN-1b            PASS
  NET-LISTEN           NET-LISTEN-1c            PASS
  NET-LISTEN           NET-LISTEN-1d            PASS
  NET-LISTEN           NET-LISTEN-2             PASS
  NET-LISTEN           NET-LISTEN-3a            PASS
  NET-LISTEN           NET-LISTEN-3b            PASS
  NET-LISTEN           NET-LISTEN-3c            PASS
  NET-LISTEN           NET-LISTEN-3d            PASS
  NET-LISTEN           NET-LISTEN-3e            PASS

  NET-FFI-POLICY       NET-FFI-POLICY-1         PASS
  NET-FFI-POLICY       NET-FFI-POLICY-2         PASS
  NET-FFI-POLICY       NET-FFI-POLICY-3         PASS
  NET-FFI-POLICY       NET-FFI-POLICY-4         PASS
  NET-FFI-POLICY       NET-FFI-POLICY-5         PASS
  NET-FFI-POLICY       NET-FFI-POLICY-6         PASS
  NET-FFI-POLICY       NET-FFI-POLICY-7         PASS

  NET-FFI-REGISTRY     NET-FFI-REGISTRY-1       PASS
  NET-FFI-REGISTRY     NET-FFI-REGISTRY-2       PASS
  NET-FFI-REGISTRY     NET-FFI-REGISTRY-3       PASS
  NET-FFI-REGISTRY     NET-FFI-REGISTRY-4       PASS
  NET-FFI-REGISTRY     NET-FFI-REGISTRY-5       PASS

  NET-FFI-GUARD        NET-FFI-GUARD-1          PASS
  NET-FFI-GUARD        NET-FFI-GUARD-2          PASS
  NET-FFI-GUARD        NET-FFI-GUARD-3          PASS

  NET-FFI-C            NET-FFI-C-1              PASS
  NET-FFI-C            NET-FFI-C-2              PASS
  NET-FFI-C            NET-FFI-C-3              PASS
  NET-FFI-C            NET-FFI-C-4              PASS

  NET-EXTRA            NET-EXTRA-1              PASS
  NET-EXTRA            NET-EXTRA-2              PASS
  NET-EXTRA            NET-EXTRA-3              PASS
  NET-EXTRA            NET-EXTRA-4              PASS
  NET-EXTRA            NET-EXTRA-5              PASS
----------------------------------------------------------------------------
Total: 61  |  PASS: 61  |  FAIL: 0
============================================================================
Result: ALL CHECKS PASSED
```

P2 (LAB-STDLIB-NET-P2) also passes without modification: 53 checks, all PASS.

---

## 8. Recommended Next Card

**LAB-STDLIB-NET-P4 — Compiler E-NET-* Diagnostic Proofs**

Prove compiler classification of network nodes as `escape`, plus the full set
of E-NET-AMBIENT-BLOCKED, E-NET-CAP-MISSING, E-NET-CAP-UNKNOWN,
E-NET-EFFECT-UNDECLARED diagnostics. These are the network analogs of the file
IO compiler diagnostic proofs (LAB-STDLIB-IO-P2 §3–4). P3 has established the
runtime capability surface; P4 would establish the compile-time surface,
completing the two-layer coverage (compile + runtime) that the file IO series
achieved across P2 and P3.
