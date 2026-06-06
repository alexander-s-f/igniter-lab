# Ch8: Stdlib

Source PROP: PROP-013, PROP-013 errata v0.1
Status: ��� PASS (kernel)
Proof: experiments/stdlib_execution_kernel_stage1/ ��� PASS (12 cases):
  integer/float/decimal.add, fold, map, filter, count, or_else (Some + None),
  numeric.add rejected (pre-resolution boundary enforced),
  RuntimeMachine igapp-style evaluate with stdlib.integer.add
Note: stdlib not yet connected to the full RuntimeMachine evaluate path via .igapp/ (pending Slice A)

---

## 8.1 Stdlib Module Structure (PROP-013 ��Stdlib Module Map)

```
stdlib/
  core/
    collection.ig   ��� fold, map, filter, group_by, sort_by, take, first, last
    option.ig       ��� some, none, or_else, map, flat_map, some?
    result.ig       ��� ok, err, ok?, err?, map, flat_map, unwrap_or
    numeric.ig      ��� add, sub, mul, div, neg, compare (generic, pre-resolution)
    integer.ig      ��� stdlib.integer.add, sub, mul, div, neg, compare
    float.ig        ��� stdlib.float.add, ...
    decimal.ig      ��� stdlib.decimal.add (scale-aware), mul
    string.ig       ��� length, concat, trim, split, contains, starts_with
  temporal/
    date.ig         ��� add_days, diff_days, day_of_week, beginning_of, end_of
    datetime.ig     ��� add_duration, diff, as_of (CORE); now() ��� OOF
  stream/           ��� Stage 2: fold_stream, window (deferred)
  temporal_ops/     ��� Stage 2: history_at, rollup (deferred)
  olap/             ��� Stage 2: olap_slice, olap_rollup (deferred)
```

**Tier classification**:
- `stdlib/core/` ��� Tier 1: no TBackend reads, no FFI, no ambient clock ��� CORE
- `stdlib/temporal/` ��� date arithmetic is CORE; TBackend reads are ESCAPE

---

## 8.2 Collection[T] (PROP-013 ��Collection)

```
Collection[T] is always finite and bounded at classification time.
Termination Rule TR-1: if Collection[T].count is statically bounded,
any fold/map/filter terminates unconditionally.

fold(xs: Collection[T], init: A, fn: (A, T) -> A) -> A
map(xs: Collection[T], fn: T -> U) -> Collection[U]
filter(xs: Collection[T], pred: T -> Bool) -> Collection[T]
count(xs: Collection[T]) -> Integer
sum(xs: Collection[T]) -> T           -- requires Numeric[T]
avg(xs: Collection[T]) -> Option[T]   -- None if empty; requires Numeric[T]
min(xs: Collection[T]) -> Option[T]
max(xs: Collection[T]) -> Option[T]
group_by(xs, fn: T -> K) -> Map[K, Collection[T]]
sort_by(xs, fn: T -> K) -> Collection[T]
take(xs, n: Integer) -> Collection[T]
first(xs) -> Option[T]
last(xs) -> Option[T]
```

**avg([]) = None** ��� never OOF; zero-guard is a language invariant.
**Lambda nodes** in SemanticIR: anonymous, non-recursive, bounded.

---

## 8.3 Option[T] (PROP-013 ��Option)

```
some(v: T) -> Option[T]
none() -> Option[T]
some?(opt) -> Bool
or_else(opt: Option[T], fallback: T) -> T
map(opt: Option[T], fn: T -> U) -> Option[U]
flat_map(opt: Option[T], fn: T -> Option[U]) -> Option[U]
```

---

## 8.4 Result[T, E] (PROP-013 ��Result)

```
ok(v: T) -> Result[T, E]
err(e: E) -> Result[T, E]
ok?(r) -> Bool
err?(r) -> Bool
map(r: Result[T,E], fn: T -> U) -> Result[U, E]
unwrap_or(r: Result[T,E], fallback: T) -> T
```

---

## 8.5 Numeric Operations

**Generic pre-resolution names** (resolved by TypeChecker):
```
stdlib.numeric.add(a: T, b: T) -> T    -- T must impl Numeric
stdlib.numeric.sub, mul, div, neg, compare
```

**Monomorphic post-resolution names** (appear in SemanticIR):
```
stdlib.integer.add(a: Integer, b: Integer) -> Integer
stdlib.float.add(a: Float, b: Float) -> Float
stdlib.decimal.add(a: Decimal[N], b: Decimal[N]) -> Decimal[N]  -- scales must match
stdlib.decimal.mul(a: Decimal[A], b: Decimal[B]) -> Decimal[A+B]
```

---

## 8.6 Temporal / Date Primitives (PROP-013 ��Temporal / Date)

```
-- CORE (pure arithmetic)
add_days(d: Date, n: Integer) -> Date
diff_days(a: Date, b: Date) -> Integer
beginning_of(d: Date, grain: Symbol) -> Date
end_of(d: Date, grain: Symbol) -> Date
day_of_week(d: Date) -> Integer

-- now() is OOF (ambient clock, Law 6):
now() -> DateTime    -- OOF-L6: use TemporalCtx.as_of instead
```

`OOF-L6` is the current source-level wording anchor for ambient-clock refusal.
This cross-reference does not mint a new OOF registry code. In managed
loop/service-loop design text, event time must enter through an explicit
TemporalCtx-style input or a materialized event binding such as `tick.time`, not
through `now()`.

---

## 8.7 Aggregate Observations (PROP-013 ��Aggregate Observations)

Every aggregate operation (fold, avg, sum, etc.) must carry `aggregated_from` links
to all source observations. Without them, the aggregate is not CORE-reproducible:

```json
{
  "kind": "aggregate_observation",
  "result": { "avg_score": 87.4 },
  "aggregated_from": ["obs:abc123", "obs:def456", "obs:ghi789"]
}
```

---

## 8.8 SemanticIR Representation (PROP-013 ��SemanticIR Representation)

```json
{
  "kind": "compute_node",
  "name": "total",
  "operator": "stdlib.collection.fold",
  "arg_refs": ["items", "zero", "add_fn"],
  "lambda": {
    "kind": "lambda_node",
    "params": [{"name": "acc", "type": "Integer"}, {"name": "x", "type": "Integer"}],
    "body": { "kind": "call", "operator": "stdlib.integer.add", "arg_refs": ["acc", "x"] },
    "recursive": false
  },
  "type": "Integer"
}
```

---

## 8.9 Stage 2 Stdlib (deferred ��� errata v0.1)

```
fold_stream     ��� PROP-023 (Stage 2)
history_at      ��� PROP-022 (Stage 2)
olap_slice      ��� PROP-024 (Stage 2)
```

Stage 1 compilers must treat these as OOF if encountered.
