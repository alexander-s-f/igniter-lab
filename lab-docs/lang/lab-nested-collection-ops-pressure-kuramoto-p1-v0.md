# lab-nested-collection-ops-pressure-kuramoto-p1-v0 — nested collection ops (map-in-map) pressure

**Card:** `LAB-NESTED-COLLECTION-OPS-PRESSURE-KURAMOTO-P1` · **Type:** pressure (evidence, design-only)
**Status:** CLOSED (pressure finding) — the Kuramoto emergence workload, once the stdlib.Math transcendentals
landed, hit the **next** language wall: a `map`/`fold` whose lambda body contains another collection op
(`map`/`fold`/`sum`) fails at VM evaluation. Single-level collection ops work; **nesting does not**. There is
a clean workaround (`call_contract` per element) — but all-to-all / O(N²) models need to know this.
**Authority:** Lab evidence. Workload = private emergence research line; this is the language-side pressure.

## Verify-first: what works vs what doesn't

**Works (single-level collection op, lambda may call stdlib math + access record fields + capture):**
```ig
-- proven: compiles + runs, correct value
compute coupling : Float = sum(map(phases, q -> sin(q - self_phase)))           -- f64
compute coupling : Float = fold(phases, 0.0, (acc, q) -> acc + det_sin(q - self_phase))  -- det_*
```
(The parallel `nbody_coupling.ig` / `nbody_order.ig` rely on exactly this — single map/fold with `det_*`
inside the lambda, record-field access, and outer-variable capture. All fine.)

**Fails (a collection op *inside* another collection op's lambda — the all-N tick):**
```ig
-- compiles OK, but EVALUATION FAILS at runtime
compute new_phases : Collection[Float] =
  map(phases, p -> p + dt * (omega + k_over_n * sum(map(phases, q -> sin(q - p)))))
```
Runtime: `EVALUATION FAILED: Unsupported operator: stdlib.collection.map`. The VM disassembly shows the
**outer** `map` emitted as opcode `0x20 UNKNOWN`, and the outer lambda records `"captures":[]` despite its
body referencing `dt/omega/k_over_n/phases/q`. So: nested collection ops are **typecheck-clean but
unimplemented at the emit/VM layer**, and free-variable capture for the nesting lambda is not wired.

Repro: `igniter-home-lab/apps/emergence/kuramoto/tick_nested_map_REPRO.ig`.

## Why it matters (the workload reason)

The full Kuramoto tick advances **every** oscillator, and each needs a **sum over all others**
(`Σ_j sin(θ_j − θ_i)`). That is inherently a per-i reduction inside a per-oscillator map — a nested
collection op. The same shape appears in N-body forces, pairwise interaction kernels, and most O(N²)
emergence models. Without nested collection ops, none of these can be a single self-contained `.ig` map.

## The workaround (proven, and arguably cleaner)

Extract the inner reduction into a **named contract** and call it from the outer `map` via `call_contract`
(a single call in the lambda body — which DOES work, like a single `sin`):

```ig
pure contract CouplingStep { input phases; input self_phase; … 
  compute coupling = fold(phases, 0.0, (acc,q) -> acc + det_sin(q - self_phase)) … }

pure contract Tick {
  compute new_phases : Collection[Float] =
    map(phases, p -> call_contract("CouplingStep", phases, p, omega, k_over_n, dt))
  output new_phases : Collection[Float]
}
```

Proven end-to-end (live `igc compile` + `igniter-vm run`): full all-N tick of `[0,1,2]` →
`[0.17507684, 1.0, 1.82492316]` (exact). Source: `igniter-home-lab/apps/emergence/kuramoto/kuramoto_full_tick.ig`.

So the per-element call_contract pattern **unblocks O(N²) models today**. It is also arguably better factoring
(the micro-rule is a named, testable, reusable contract). But it is non-obvious, and the nested form fails
only at *runtime* (typecheck passes) — a sharp edge worth fixing.

## Recommendation (prioritized; design-only, no language change here)

1. **Diagnostic, cheap:** reject a nested collection op (a `map`/`fold`/`sum` inside a HOF lambda body) at
   **typecheck/emit** with a clear message + the `call_contract` workaround — instead of a typecheck-clean
   program that dies at VM eval with `Unsupported operator`. Turn a sharp edge into a guided one.
2. **Capability, larger:** implement nested collection ops in the emitter/VM (the outer `0x20 UNKNOWN` path)
   AND wire free-variable capture for the nesting lambda (`captures:[]` is the bug). This is the real fix; it
   makes O(N²) kernels first-class.
3. Until (2): document the `call_contract`-per-element pattern as the canonical way to express all-to-all /
   pairwise interactions in `.ig`.

## Scope / boundaries

- Evidence + recommendation only; no language/stdlib code changed.
- Complements the stdlib.Math pressure (`lab-stdlib-math-pressure-kuramoto-p1-v0.md`, now answered by the
  Tier-1 + det_* surface) and the parallel `nbody_*` proofs (which stay single-level and so never hit this).
- Adjacent tooling note: `igniter-vm run --contract <igapp> [--entry C] --inputs <json>` **does** surface the
  result value (`Resulting Output: …`) — supersedes the earlier "trace shows execution not value" note; use
  `run`, not `trace`, for numeric proofs.

## Next card

`LAB-COLLECTION-NESTED-OPS-DIAGNOSTIC-P2` — recommendation (1): a typecheck/emit diagnostic for nested
collection ops with the `call_contract` workaround in the message. (The full emit/VM implementation,
recommendation (2), is a larger separate card.)

---

*Lab pressure finding. 2026-06-21. With transcendentals landed, the Kuramoto full-N tick exposed the next
wall: nested collection ops (map-in-map) typecheck but fail at VM eval (`0x20 UNKNOWN`, `captures:[]`).
Proven workaround: `call_contract` per element (full tick runs, exact). Recommend a typecheck diagnostic now,
nested-op implementation later.*
