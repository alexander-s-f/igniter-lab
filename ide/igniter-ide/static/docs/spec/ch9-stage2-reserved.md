# Ch9: Stage 2 Reserved Primitives

Status: deferred ��� do not implement until Stage 1 closes
Source PROPs: PROP-022, PROP-023, PROP-024, PROP-025 (all authored)

> These PROPs are fully written specifications. They are NOT speculative.
> Implementation begins after Stage 1 pipeline is proven end-to-end.

---

## 9.1 History[T] and BiHistory[T] (PROP-022)

```
History[T]      ��� time-indexed sequence of T (single axis: valid time)
BiHistory[T]    ��� two axes: valid time �� transaction time

Subtyping:  T  ���  History[T]  ���  BiHistory[T]
Unification: History[T]  ���  OLAPPoint[T, {time: DateTime}]
```

Key operations: `.at(t)`, `.avg[period]`, `.rollup(:grain)`, `.changes`

BiHistory four canonical queries:

| Query | Use case |
|-------|---------|
| `h[vt: now, tt: now]` | Current live value |
| `h[vt: created_at, tt: created_at]` | Frozen legal value |
| `h[vt: created_at, tt: now]` | Retroactive audit |
| `h[vt: past, tt: report_date]` | Regulatory report |

**Stage 1 OOF**: `History[T]` or `BiHistory[T]` in type annotations ��� OOF-reserved.

---

## 9.2 stream T and fold_stream (PROP-023)

```
stream name: Type          ��� ESCAPE input (unbounded external source)
window "key" { kind, size, on_close }  ��� required per stream
fold_stream(s, init, fn) @window_bounded  ���  A  (CORE result)
```

Theoretical grounding: ��-transducer / Kahn Process Network.
Window boundary = synchronous clock tick. Inside window = CORE DAG.

**Stage 1 OOF**: `stream` declaration ��� OOF-S2 (no window); `fold_stream` without bound ��� OOF-S1.

---

## 9.3 OLAPPoint[T, Dims] (PROP-024)

```
olap_point Name {
  dimensions: { time: DateTime, region: Region, ... }
  measure:    T
  source:     fn(...) -> T
  indexed:    [:time, :region]
}

Type: OLAPPoint[T, Dims]
Slice: OLAPPoint[T, D][d: v]  ���  OLAPPoint[T, D - {d}]
Resolved: OLAPPoint[T, {}]    ���  T
```

Cluster: `rollup` over `indexed:` dimension ��� automatic scatter-gather.

---

## 9.4 Invariant Severity Levels (PROP-025)

```
invariant "predicate"
  severity: :error | :warn | :soft | :metric
  label:    "REQ-ID"
  message:  "..."
  overridable_with: :justification?
```

| Severity | Predicate false | Output |
|----------|-----------------|--------|
| `:error` (default) | raises InvariantViolation | none |
| `:warn` | continues | T + warnings |
| `:soft` | continues | ~T (uncertain) |
| `:metric` | continues | T (unaffected) |

---

## 9.5 Stage 3+ (Queued, not yet authored)

| PROP | Topic |
|------|-------|
| PROP-026 | ~T probabilistic types (ProbLog subset) |
| PROP-027 | Deadline contracts + WCET analysis |
| PROP-028 | Full unit algebra (dimensional type checking) |
| PROP-029 | Plastic Runtime Cells (ownership + migration) |
| PROP-030 | Rule synthesis via LP (goal-directed) |

Reference: `META-EXPERT-006` for design decisions on all Stage 2/3 primitives.
