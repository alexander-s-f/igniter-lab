# lab-machine-service-wire-effect-p11-v0 — real loopback HTTP × handle_effect

**Card:** `LAB-MACHINE-SERVICE-WIRE-EFFECT-P11` (front door:
`LAB-MACHINE-AGENT-COORDINATION-META-P1`)
**Status:** CLOSED — implemented + proven. 5 machine tests
(`tests/service_wire_effect_tests.rs`), all over a real `127.0.0.1` socket; full machine suite
green. **MAJOR MILESTONE: wire-to-effect production contour proven in lab.** Local loopback only;
fake effect executor; no live SparkCRM.

## The full wire-to-effect contour (real socket, end-to-end)

```text
real HTTP POST (127.0.0.1)
  → ingress HTTP/1.1 parser        (serve_once_effect)
  → passport (serving authority)
  → duplicate policy (attempt/key) (P7)
  → replica selection (ONE replica) (P9)
  → capsule activation → intent     (coordination, pure)
  → effect executor → receipt       (capability-IO, ONE effect)
  → real HTTP/1.1 response
```

P6 proved the real socket up to capsule activation; P10 proved the logical effect contour; P11
**joins them**: the socket ingress now drives the effect bridge.

## Implementation (`ingress.rs`)

- `serve_once` refactored into `read_one_request` + `write_one_response` (shared HTTP/1.1 I/O).
- `serve_once_effect(listener, router, hub, cfg)` — accept one connection → parse → run
  `handle_effect` (P10) → write the HTTP response. No background worker.
- `status_text` extended for the effect codes (202 / 429 / 500 / 502 / 503).

## Proof (5 tests, real `127.0.0.1` round-trips)

| acceptance | test |
|---|---|
| a real HTTP POST reaches `handle_effect` → committed effect → 200 | `wire_to_effect_committed` |
| `dedup_strict` replay over the wire performs NO second effect | `wire_dedup_strict_no_second_effect` |
| `bounded_fresh` over repeated HTTP requests → attempts 0..n, distinct effects | `wire_bounded_fresh_attempts` |
| status mapping over the wire: unknown → 202, denied → 403 | `wire_status_mapping` |
| bridge audit links correlation / attempt / replica / effect_receipt_id over the wire | `wire_receipt_links` |

Each test binds `127.0.0.1:0`, spawns `serve_once_effect`, and sends a raw HTTP/1.1 POST from a
real `TcpStream` client; the assertions read the parsed HTTP status + the effect facts.

## Decisions

- one connection per `serve_once_effect` (explicit; the host loops — no daemon);
- the wire path is exactly the P10 logic (`handle_effect`) — the socket adds nothing but real
  transport, so all P10 invariants (one-replica-one-effect, dedup_strict, bounded_fresh,
  two authorities, unknown→202) hold over real HTTP;
- shared HTTP I/O helpers so plain serving (`serve_once`) and effect serving (`serve_once_effect`)
  stay one parser/one response writer.

## Closed (held)

Local loopback only (binds `127.0.0.1`). Fake effect executor; no live SparkCRM / external
network. No language/VM change. No background worker / autoscaling. No federation.

## Milestone — wire-to-effect production contour proven in lab

This is the point where igniter-machine stops being "an interesting architecture" and looks like
a server platform: a real HTTP request, through an audited host boundary, deterministically
selects a replica of an immutable content-addressed service image, activates it for a pure
intent, performs exactly one declared effect with a receipt, and returns a real HTTP response —
all reconstructable from facts. Checkpoint card:
`LAB-MACHINE-SERVICE-WIRE-EFFECT-MILESTONE.md`.

## Next route (honest staging gate)

```text
local wire-proven contour (P11)
  → SparkCRM executor over local TLS (neighbour's P15)   ← swap the fake executor only
  → human-approved staging                               ← live is GATED, not a continuation
```

- combine with `serve_once`'s plain path for a serving loop over many connections.
- `invoke_fanout × bridge` diagnostic dry-run only (no commit).
- later: multi-machine federation.
