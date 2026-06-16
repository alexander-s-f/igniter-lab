# Card: LAB-MACHINE-SERVICE-WIRE-EFFECT-P11 — real loopback HTTP × handle_effect

> **Front door:** [`LAB-MACHINE-AGENT-COORDINATION-META-P1`](LAB-MACHINE-AGENT-COORDINATION-META-P1.md). Milestone: [`LAB-MACHINE-SERVICE-WIRE-EFFECT-MILESTONE`](LAB-MACHINE-SERVICE-WIRE-EFFECT-MILESTONE.md) — "wire-to-effect production contour proven in lab".

**Status: CLOSED 2026-06-16 — implemented + proven over a real socket.** 5 machine tests
(`igniter-machine/tests/service_wire_effect_tests.rs`, real `127.0.0.1` round-trips); full suite
green. Code: `ingress.rs` (`serve_once_effect`, `read_one_request`/`write_one_response`,
`status_text` extended). Design doc: `lab-docs/lang/lab-machine-service-wire-effect-p11-v0.md`.
**MAJOR MILESTONE.** Fake effect executor; no live SparkCRM.

## Goal (met)

Join the real socket (P6) to the effect bridge (P10): a real HTTP POST drives the full contour.

```text
HTTP POST → parser → duplicate policy → replica selection → capsule intent → effect → receipt → HTTP response
```

## Implementation

`serve_once_effect(listener, router, hub, cfg)` = accept → `read_one_request` → `handle_effect`
(P10) → `write_one_response`. Shared HTTP/1.1 I/O helpers with `serve_once`. `status_text`
extended (202/429/500/502/503).

## Proof (5 tests, real 127.0.0.1)

`wire_to_effect_committed` (200), `wire_dedup_strict_no_second_effect`,
`wire_bounded_fresh_attempts` (0..n distinct effects), `wire_status_mapping` (unknown→202,
denied→403), `wire_receipt_links` (correlation/attempt/replica/effect_receipt_id).

## Decisions

- one connection per call (explicit; host loops, no daemon);
- the wire adds only transport — all P10 invariants hold over real HTTP;
- shared HTTP I/O for plain + effect serving.

## Closed

Local loopback only (`127.0.0.1`). Fake executor; no live SparkCRM / external network. No
language/VM change. No daemon / federation.

## Next (honest staging gate)

`local wire-proven contour → SparkCRM executor over local TLS (neighbour P15) → human-approved
staging` (live is GATED, not a continuation). Plain serving loop over many connections;
`invoke_fanout × bridge` diagnostic only; later federation.
