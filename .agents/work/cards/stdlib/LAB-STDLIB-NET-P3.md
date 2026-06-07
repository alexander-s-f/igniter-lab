# LAB-STDLIB-NET-P3

**Card ID:** LAB-STDLIB-NET-P3
**Category:** stdlib / io / network
**Track:** lab-experimental-io-network-ffi-surface-proof-v0
**Route:** EXPERIMENTAL / LAB-ONLY / PROOF-LOCAL
**Date:** 2026-06-07
**Status:** DONE

---

## D — Deliverables

| File | Type | Status |
|---|---|---|
| `igniter-lab/igniter-view-engine/lib/network_ffi_stub.rb` | Ruby FFI stub (new) | Created |
| `igniter-lab/igniter-view-engine/fixtures/network_capability/ffi_operations_sequence.json` | Fixture (new) | Created |
| `igniter-lab/igniter-view-engine/proofs/network_ffi_proof.rb` | Proof runner (new) | Created |
| `igniter-lab/lab-docs/stdlib/lab-experimental-io-network-ffi-surface-proof-v0.md` | Proof doc (new) | Created |
| `igniter-lab/.agents/work/cards/stdlib/LAB-STDLIB-NET-P3.md` | Card receipt (this file) | Created |

No existing files were modified. P2 proof runner (`network_capability_proof.rb`) still passes at 53/53.

---

## S — Summary

LAB-STDLIB-NET-P3 writes a pure-Ruby FFI stub (`NetworkFFIStub`) that simulates
the six C ABI network functions a Rust stdlib implementation would export. The
stub enforces all six NET safety policies (loopback, host allowlist, port range,
direction, TLS, protocol) by delegating to the P2 `NetworkCapabilityValidator`
modules verbatim — no policy logic is re-implemented. A 61-check proof runner
(`network_ffi_proof.rb`) exercises the full connect/send/receive/close and
listen/accept lifecycles, all seven policy violation cases, registry isolation,
no-real-network source scans, and Variant C TLS behavior. All 61 checks pass.
The stub carries `stub_mode: true` on every receipt and refuses `tls_required: true`
capabilities with `StubModeError` rather than silently permitting plaintext.

---

## T — Tensions / Risks

**T1 — TLS stub mode gap**: Capabilities with `tls_required: true` (Variant C)
cannot be exercised beyond the StubModeError boundary. The Rust implementation
must integrate a TLS library (e.g. rustls) before end-to-end Variant C flows
can be proven without the StubModeError escape hatch. This creates a testing
blind spot: the stub proves the shape of TLS-required caps but cannot prove
their happy-path behavior.

**T2 — Direction field vs. *_allowed bits coherence**: The `direction` field
(`"connect"`, `"listen"`, `"both"`) and the four `*_allowed` permission bits are
partially redundant. P3 uses the `*_allowed` bits (via NET-4) as authoritative.
If a future cap is constructed with `direction: "connect"` but
`connect_allowed: false`, the bits win. A P4 compiler diagnostic proof should
establish whether `direction` is enforced at compile time (as a type annotation)
or purely as documentation.

**T3 — accept() receive_allowed pre-check**: The stub checks `receive_allowed`
at `accept()` time, not only at `receive()` time. This is a defensible design
(you should not accept a connection you cannot read from) but it differs from
the file IO pattern where permission checks happen per-operation. If a capability
designer wants `listen_allowed: true, receive_allowed: false` (accept but never
read — unusual but conceivable for a fire-and-forget scenario), the current
stub would reject the accept call. This tension should be resolved in the Rust
implementation specification.

---

## R — Recommended Next

**LAB-STDLIB-NET-P4 — Compiler E-NET-* Diagnostic Proofs**

Prove compiler classification of network nodes as `escape` (not `core`), and
prove all compile-time E-NET-* diagnostics: `E-NET-AMBIENT-BLOCKED` (network
call in pure contract), `E-NET-CAP-MISSING` (call without capability arg),
`E-NET-CAP-UNKNOWN` (undeclared capability), `E-NET-EFFECT-UNDECLARED`
(capability declared but no `effect ... using` binding). These are the network
analogs of the file IO compiler proofs in LAB-STDLIB-IO-P2. P3 covers the
runtime surface; P4 would complete the compile+runtime two-layer coverage.

---

## Proof Matrix

```
Total: 61  |  PASS: 61  |  FAIL: 0
Result: ALL CHECKS PASSED
```

Full output in doc `lab-experimental-io-network-ffi-surface-proof-v0.md §7`.

---

## FFI Surface Summary

| Function | Params | Returns | Policy checks |
|---|---|---|---|
| `stdlib_io_network_connect` | host, port, cap | ConnectReceipt \| NetworkError | tls_required→StubModeError, NET-1, NET-2, NET-4(connect), NET-3, NET-6 |
| `stdlib_io_network_listen` | bind_addr, port, cap | ListenReceipt \| NetworkError | NET-4(listen), NET-3, NET-1(bind_addr), NET-6 |
| `stdlib_io_network_accept` | listener_id, cap | AcceptReceipt \| NetworkError | ListenerNotFound, NET-4(listen), NET-4(receive) |
| `stdlib_io_network_send` | conn_id, data, cap | SendReceipt \| NetworkError | ConnectionNotFound, NET-4(send), NET-6 |
| `stdlib_io_network_receive` | conn_id, max_bytes, cap | ReceiveObservation \| NetworkError | ConnectionNotFound, NET-4(receive), NET-6 |
| `stdlib_io_network_close` | conn_id, cap | CloseReceipt \| NetworkError | ConnectionNotFound, schema only |

All functions parse cap_json first (→ InvalidJson on failure), then validate
schema (→ CapabilityError on failure), then run operation-specific checks in
order.
