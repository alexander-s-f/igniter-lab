# LAB-NESTED-COLLECTION-OPS-PRESSURE-KURAMOTO-P1 — nested collection ops (map-in-map) pressure

Status: CLOSED
Lane: standard / lab pressure-finding
Type: pressure (evidence, design-only)
Delegation code: OPUS-NESTED-COLLECTION-OPS-PRESSURE-KURAMOTO-P1
Date: 2026-06-21
Skill: idd-agent-protocol

## Context

After the stdlib.Math transcendentals landed (Tier-1 `sin/cos/sqrt/pi` + deterministic `det_*`), the Kuramoto
emergence workload progressed to the **full all-N tick** and hit the next wall: nested collection ops.

## Finding (verify-first, live)

- **Single-level** collection ops work: `sum(map(phases, q -> sin(q - self_phase)))` /
  `fold(phases, 0.0, (acc,q) -> acc + det_sin(q - self_phase))` — lambda may call stdlib math, access record
  fields, and capture outer vars. (Proven by my `CouplingStep` and the parallel `nbody_coupling`/`nbody_order`.)
- **Nested** collection ops fail: a `map` whose lambda body contains `sum(map(...))` **typechecks** but at VM
  eval gives `EVALUATION FAILED: Unsupported operator: stdlib.collection.map`. Disassembly: outer `map` →
  opcode `0x20 UNKNOWN`; outer lambda `"captures":[]` (free-var capture for the nesting lambda not wired).
  Repro: `igniter-home-lab/apps/emergence/kuramoto/tick_nested_map_REPRO.ig`.
- This blocks all-to-all / O(N²) models (Kuramoto coupling, N-body forces) as a single `.ig` map.

## Proven workaround

`call_contract` per element: extract the inner reduction to a named contract, call it from the outer `map`.
Full all-N Kuramoto tick `[0,1,2]` → `[0.17507684, 1.0, 1.82492316]` (exact), deterministic `det_*` surface.
Source: `igniter-home-lab/apps/emergence/kuramoto/kuramoto_full_tick.ig` (compiles + runs live).

## Recommendation

1. **(cheap, do first)** typecheck/emit **diagnostic** for a nested collection op, with the `call_contract`
   workaround in the message — turn a runtime `Unsupported operator` death into a guided compile error.
2. **(larger)** implement nested collection ops in emitter/VM (the `0x20 UNKNOWN` path) + wire capture for the
   nesting lambda (`captures:[]` bug). Makes O(N²) kernels first-class.
3. Until (2): document `call_contract`-per-element as the canonical all-to-all pattern.

## Acceptance

- [x] Verify-first: single-level collection ops work; nested (map-in-map) typechecks but fails at VM eval.
- [x] Root cause captured: outer op `0x20 UNKNOWN` + nesting-lambda `captures:[]`.
- [x] Workaround proven live (`call_contract` per element; full N tick runs, exact values).
- [x] Prioritized recommendation (diagnostic now, implementation later).
- [x] No language/stdlib code changed; complements stdlib.Math pressure + parallel nbody proofs.

## Proof doc

`lab-docs/lang/lab-nested-collection-ops-pressure-kuramoto-p1-v0.md`.

## Next card

`LAB-COLLECTION-NESTED-OPS-DIAGNOSTIC-P2` — implement recommendation (1): the typecheck/emit diagnostic with
the `call_contract` workaround in the message.

## Adjacent tooling note

`igniter-vm run --contract <igapp> [--entry C] --inputs <json>` surfaces the result value
(`Resulting Output: …`) — supersedes the earlier "trace shows execution not value" note in the stdlib.Math
pressure packet. Use `run` for numeric proofs.
