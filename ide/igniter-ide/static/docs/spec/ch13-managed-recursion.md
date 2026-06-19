# Chapter 13: Managed Recursion and Service Loops

Status: proposed
Stage: 4 (deferred)
Source PROP: PROP-039+ placeholder for managed local recursion / loop-class
extensions; PROP-037 owns external progression and service liveness
Governance: META-EXPERT-013
Last updated: 2026-06-04

> **Proposed ��� Stage 4 deferred.** This chapter describes the managed recursion
> and service loop extension. It is not in scope for Stage 3.
> Status advances when Stage 4 governance opens and an assigned managed-recursion
> PROP passes. Managed local recursion / loop-class extensions route to PROP-039+
> or later. Service-loop liveness maps through PROP-037 progression descriptors.
> PROP-036 is reserved for `compiler_profile_id` manifest identity.

---

## �� 13.1 Overview

Every repetition in Igniter-Lang is *managed*: it belongs to one of five loop
classes, each with a compiler-verified termination or liveness contract. There is
no general recursion and no unbounded loop.

```igniter
-- Finite loop: bounded by collection size
for ClaimLoop item in claims {
  FactCheckClaim(item, as_of)
}

-- Structural recursion: variant decreases at every recur() call
recursive contract SumList(items: Collection[Integer], acc: Integer) -> total: Integer
  decreases items.remaining
{
  match items.head {
    none    => output acc
    some(x) => recur(items: items.tail, acc: acc + x)
  }
}

-- Fuel-bounded: explicit step budget
fuel_bounded contract SearchOptimal(state: SearchState) -> best: Route
  max_steps 10_000
  on_exhaustion :suspend
{
  ...
}

-- Convergent: metric converges toward threshold
loop contract Optimize(params: Params) -> result: Params
  variant loss_function(params)
  convergence epsilon: 0.001
  max_steps 100_000
  on_exhaustion :return_partial
{
  ...
}

-- Service loop: continuous, stoppable, observable
-- Design text only: source syntax is not implemented.
service contract LiveNewsClarityService()
  heartbeat every 10.seconds
  checkpoint every 1.minute
  cancellation required
  max_step_latency 2.seconds
  via audited_truth_mesh
{
  loop TickLoop tick in clock.every(10.seconds) {
    as_of = tick.time
    receipt = RunArticlePipeline(tick.payload.article, as_of)
    write clarity_reports <- receipt.report evidence [receipt]
  }
}
```

---

## �� 13.2 The Five Loop Classes

| Class | Termination contract | Compiler verification |
|-------|---------------------|----------------------|
| `FiniteLoop` | Terminates when collection is exhausted | Collection size is finite; proven by type |
| `StructuralRecursion` | Terminates because structural variant strictly decreases | Compiler checks variant at every `recur()` site |
| `FuelBoundedRecursion` | Terminates when fuel counter reaches zero | `max_steps` is a static literal |
| `ConvergentLoop` | Terminates when metric reaches threshold or fuel exhausts | Convergence criterion and `max_steps` required |
| `ServiceLoop` | Does not terminate by design; must be stoppable, observable, and bounded per step | Heartbeat, checkpoint, cancellation, and `max_step_latency` verified |

The first four classes are managed local repetition territory and require a
future PROP-039+ proposal/proof before parser, TypeChecker, SemanticIR, runtime,
or fixture authority. `ServiceLoop` is a service-liveness surface whose source
binding and descriptor obligations are governed by PROP-037 companion wording.

---

## �� 13.3 `recur()` Combinator

`recur()` is not a self-call. It is a compiler primitive for structural and
fuel-bounded recursion:

```igniter
recursive contract SumList(items: Collection[Integer], acc: Integer) -> total: Integer
  decreases items.remaining
{
  match items.head {
    none    => output acc
    some(x) => recur(items: items.tail, acc: acc + x)
  }
}
```

The compiler checks that the `decreases` expression is strictly smaller at every
`recur()` call site. A `recur()` outside a `recursive` or `fuel_bounded` context
is OOF-R1.

For fuel-bounded recursion, `decreases fuel` is the design shorthand for a
compiler-visible static budget that decreases on every recursive step. The exact
syntax, metric model, and diagnostic ownership remain PROP-039+ design work; no
current parser or TypeChecker enforcement is claimed by this chapter.

---

## �� 13.4 Service Loop Obligations

A service loop must satisfy three compiler-checked obligations:

1. **Stoppable**: `cancellation required` ��� the loop handles a cancellation signal
   and terminates gracefully.

2. **Observable**: `heartbeat every N.duration` ��� the loop emits a heartbeat signal
   within each heartbeat window. A step that blocks the heartbeat is OOF-R2.

3. **Bounded per step**: `max_step_latency N.duration` ��� each iteration must
   complete within the latency budget. A step that provably exceeds the budget
   is OOF-R3 (warn).

Service loops do not have a termination proof. Instead, they are governed by
liveness theory: the loop is alive as long as heartbeat signals arrive.

---

## �� 13.5 Timer-Driven Progression Source Binding

A service loop may bind a timer source through a PROP-037 progression descriptor:

```igniter
loop TickLoop tick in clock.every(250.ms)
  max_steps 1_000_000
  on_exhaustion :suspend
{
  as_of = tick.time
  ...
}
```

`clock.every(N.duration)` is a progression `source_kind` / source binding for
service liveness. It is not semantically equivalent to `Stream[DateTime]`, and
it does not weaken PROP-023 `fold_stream` / window OOF rules.

`tick.time` is explicit event-time binding from the materialized progression
event. It is not ambient time. Source-level `now()` remains prohibited; use an
explicit TemporalCtx-style input or event-time binding such as `tick.time`.

---

## �� 13.6 `write store <- value evidence [refs]`

Inside a service loop body, a contract may append a value to a temporal store:

```igniter
write clarity_reports <- receipt.report
  evidence [receipt]
```

This is an effect statement, not an output declaration. The `evidence` clause is
mandatory and names the receipts or observations that justify the write. The
append is `lifecycle: :audit` by default.

---

## �� 13.7 OOF Rules

The following codes are deferred design vocabulary for managed recursion and
service-loop wording. They are not a newly accepted OOF registry namespace.
Source-level `now()` prohibition cross-references Ch8 `OOF-L6`; this chapter
does not mint a replacement OOF code.

| Code | Condition | Severity |
|------|-----------|----------|
| OOF-R1 | `recur()` outside recursive or fuel_bounded context | error |
| OOF-R2 | Service loop step blocks heartbeat window | error |
| OOF-R3 | Service loop step provably exceeds `max_step_latency` | warn |
| OOF-R4 | `on_exhaustion: :suspend` without a suspension point | error |
| OOF-R5 | Unbounded loop (no `max_steps`, no structural proof) | error |

Future proof fixtures must include unnamed-loop robustness for Postulate 28
(the R246/R247 `OOF-L3` pressure item), but this chapter does not claim that
enforcement is proven. Source-level `break` remains deferred.

---

## �� 13.8 Relationship to Other Chapters

- **Ch11 (Profile System):** the `loop`, `heartbeat`, `checkpoint`, `cancellation`,
  and `max_step_latency` profile properties bind to the service loop obligations
  defined here.
- **Ch10 (Contract Modifiers):** service loops are declared with the `service`
  keyword, not a modifier. The `service contract` form is syntactically distinct.
- **Ch9 (Stage 2 Reserved):** `fold_stream @window_bounded` and `fold_stream
  @count_bounded(n)` are stream/window bounded folds, not arbitrary managed
  local loops. They remain separate from PROP-039+ local loop/recursion work.
- **PROP-037:** service-loop source binding maps to progression descriptors,
  including `clock.every` source kind, materialization, receipts, cancellation,
  checkpoint, and backpressure obligations. PROP-037 does not authorize parser,
  runtime, scheduler, or a `PROGRESSION` fragment class.
