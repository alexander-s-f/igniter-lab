# LAB-STDLIB-DECIMAL-MONEY-CONTRACT-READINESS-P1

Status: READY
Date: 2026-06-27
Lane: igniter-lab / stdlib+VM / foundation-hardening
Type: readiness / numeric contract

## Authority Boundary

This packet is lab readiness evidence only. It does not change canon language
authority in `igniter-lang`, and it does not implement Decimal runtime changes.
Live Rust source and tests are the authority for current lab behavior.

## Live Current Behavior

Current source paths:

- `lang/igniter-stdlib/src/decimal.rs`
- `lang/igniter-stdlib/src/lib.rs`
- `lang/igniter-vm/src/value.rs`
- `lang/igniter-vm/src/vm.rs`
- `lang/igniter-vm/tests/vm_tests.rs`
- `lang/igniter-vm/tests/stdlib_to_text_tests.rs`
- `server/igniter-web/tests/decimal_crossing_tests.rs`

Observed behavior:

- `Decimal` is stored as `value: i64` plus `scale: u32` and derives raw
  `PartialEq`, `Eq`, `PartialOrd`, and `Ord`.
- `Value::Decimal` uses the public JSON/SIR shape `{ "value": i64, "scale": u32 }`.
- `Decimal::add` and `Decimal::sub` reject mismatched scales with `OOF-TC5`,
  but perform unchecked `i64` arithmetic.
- `Decimal::mul` performs unchecked `i64` multiplication, unchecked scale
  addition, and returns `Decimal` rather than `Result`.
- `Decimal::div` rejects zero with `OOF-DM2`, rejects `lhs.scale < rhs.scale`,
  then truncates integer division and subtracts scales.
- VM equality currently uses structural `Value` equality, so `1.5` and `1.50`
  are not equal.
- VM Decimal order comparisons use `Decimal::to_f64()`, losing exactness for
  large values and crossing money/report determinism boundaries.
- `to_text(Integer|Decimal)` is already exact for `Value::Decimal`, preserves
  trailing zeroes, and does not use `f64`.
- Web Decimal crossing expects the public `{ value, scale }` shape and exact
  Decimal behavior, including refusing Float for Decimal fields and failing
  closed on scale drift.

## Alternatives

| Option | Summary | Correctness | Compatibility | Risk | Determinism | App pressure fit |
| --- | --- | --- | --- | --- | --- | --- |
| A | Minimal `i64 checked_*` arithmetic plus scale-normalized compare. | Medium: fixes wraps, not wider intermediates. | High: no shape change. | Low. | High if compare avoids `f64`. | Good emergency patch, weak for multiply and rescale headroom. |
| B | Use checked `i128` intermediates/helpers while keeping public VM/SIR JSON `{ value: i64, scale: u32 }`. | High for v0 fixed scale money values. | High: public shape stays stable. | Medium. | High. | Best fit for current Todo/report money and web crossing pressure. |
| C | Full arbitrary-precision Decimal. | Highest. | Medium/low: new dependency and broader representation work. | High. | High if implemented carefully. | Too broad for foundation-hardening P1/P2 closure. |
| D | Split stdlib checked arithmetic first, VM compare second, division later. | Medium during split: visible wrong equality/order can remain. | High. | Low per slice. | Incomplete until VM work lands. | Acceptable only if schedule forces staged rollout. |
| E | Hold all Decimal division until explicit rounding syntax exists. | High for avoiding silent money bugs. | Medium: breaks current exact-div tests/use. | Low/medium. | High. | Too strict alone; exact divisible division is useful and safe. |

Chosen v0: **B with exact-only division from E and a single implementation card
that includes VM equality/order**. This keeps the public representation stable,
uses checked wider intermediates for safety, and removes the user-visible `f64`
comparison bug in the same slice as arithmetic.

## V0 Contract

### Representation

- Public VM/SIR/JSON representation remains:

```text
Value::Decimal { value: i64, scale: u32 }
JSON/SIR: { "value": <i64>, "scale": <u32> }
```

- V0 does not require changing `Value::Decimal` to store `i128`.
- Arithmetic and comparison must use checked `i128` intermediates internally.
- Every produced public Decimal result must fit back into `i64`; otherwise the
  operation fails with `OOF-DM1`.
- The exact `to_text(Decimal)` surface stays compatible and remains separate
  from Float formatting work.

### Scale Bound

- Define `MAX_DECIMAL_SCALE = 18` for v0 Decimal operations and construction.
- Compute powers with checked `10_i128.checked_pow(scale)`.
- Reject any operation input or result requiring `scale > MAX_DECIMAL_SCALE`
  with `OOF-DM4`.
- Reject checked scale addition overflow with `OOF-DM5`.
- Existing stored/test Decimal values outside the bound should not be minted by
  new constructors or arithmetic. Existing `to_text` can continue to render a
  stored `Value::Decimal` as a compatibility reflection path.

### Add/Sub

- `add` and `sub` continue to require equal scales in v0.
- Mismatched scales remain `OOF-TC5`.
- Compute `lhs.value +/- rhs.value` in checked `i128`.
- Result scale is the shared input scale.
- Result value must fit `i64`; overflow is `OOF-DM1`.

### Mul

- Compute value product in checked `i128`.
- Result scale is `lhs.scale + rhs.scale`.
- Checked scale addition overflow is `OOF-DM5`.
- Result scale above `MAX_DECIMAL_SCALE` is `OOF-DM4`.
- Result value must fit `i64`; overflow is `OOF-DM1`.
- `stdlib_decimal_mul` must stop being a silent void-returning overflow path;
  it needs a fallible/error-code surface before it is money-safe.

### Div

- V0 division is exact-only until explicit rounding syntax/policy exists.
- Division by zero remains `OOF-DM2`.
- Result scale preserves lhs scale.
- Formula:

```text
numerator = lhs.value * 10^rhs.scale
quotient = numerator / rhs.value
remainder = numerator % rhs.value
result = Decimal { value: quotient, scale: lhs.scale }
```

- If `remainder != 0`, reject with `OOF-DM3`:

```text
OOF-DM3: Decimal division is inexact; explicit rounding mode required
```

- Intermediate overflow or public result overflow is `OOF-DM1`.
- Scale out of range is `OOF-DM4`.

Example change:

```text
Decimal { value: 2625, scale: 2 } / Decimal { value: 25, scale: 1 }
old: Decimal { value: 105, scale: 1 }
v0:  Decimal { value: 1050, scale: 2 }
```

### Equality And Order

- Decimal equality is numeric, not structural.
- `Decimal { value: 15, scale: 1 } == Decimal { value: 150, scale: 2 }`.
- Decimal order is numeric and exact.
- Comparisons must not call `to_f64()`.
- Normalize for comparison by checked rescaling to the larger scale within
  `MAX_DECIMAL_SCALE`, using `i128` intermediates.
- Comparison helpers return `Result<Ordering, String>` so scale/overflow errors
  can fail closed rather than returning a wrong Bool.
- Required large-value guard:

```text
Decimal { value: 9007199254740993, scale: 0 }
  > Decimal { value: 9007199254740992, scale: 0 }
```

### From Float

- No implicit Float-to-Decimal path is money-safe.
- `from_f64` should be removed from money paths or replaced with an explicit
  fallible helper such as `try_from_f64(value, scale)`.
- If retained as a helper, it must be finite-only, require `scale <= 18`, check
  the rounded scaled result fits `i64`, and fail with `OOF-DM6`.
- VM/compiler Decimal construction should not use Float as a Decimal source.

## Diagnostics

- `OOF-TC5`: Decimal add/sub scale mismatch.
- `OOF-DM1`: Decimal overflow.
- `OOF-DM2`: Decimal division by zero.
- `OOF-DM3`: Decimal division is inexact; explicit rounding mode required.
- `OOF-DM4`: Decimal scale out of range.
- `OOF-DM5`: Decimal scale overflow.
- `OOF-DM6`: Float to Decimal conversion is not permitted or is fallible.

## Old Tests To Change

- `lang/igniter-vm/tests/vm_tests.rs::test_decimal_division_scale_subtraction`
  encodes old truncating scale-subtraction behavior. Replace expected
  `Decimal { value: 105, scale: 1 }` with exact lhs-scale-preserving
  `Decimal { value: 1050, scale: 2 }`.
- Add a VM/runtime division test for inexact division, for example
  `Decimal { value: 1000, scale: 2 } / Decimal { value: 300, scale: 2 }`
  returning `OOF-DM3`.
- Add stdlib/VM checked overflow tests for add, sub, and mul returning
  `OOF-DM1`.
- Add scale-bound tests for constructor/ops with `scale > 18` and multiplication
  scale sum above 18 returning `OOF-DM4` or `OOF-DM5`.
- Add normalized equality tests:
  `Decimal { value: 15, scale: 1 } == Decimal { value: 150, scale: 2 }`.
- Add exact order tests:
  `Decimal { value: 10, scale: 1 } < Decimal { value: 5, scale: 0 }` and the
  `9007199254740993 > 9007199254740992` no-`f64` guard.
- Keep `lang/igniter-vm/tests/stdlib_to_text_tests.rs` green unchanged; it is
  the exact text boundary, not a Float/rounding surface.
- Keep `server/igniter-web/tests/decimal_crossing_tests.rs` public shape
  expectations green: Postgres numeric string crossing remains `{ value, scale }`.

## Implementation Order

### 1. `LAB-STDLIB-DECIMAL-MONEY-SAFE-P2`

Use the existing card as the first implementation slice, with VM equality/order
included in scope. Splitting VM comparison later would leave a known money bug
visible after arithmetic is fixed.

Acceptance tests:

- checked `add/sub/mul` overflow returns `OOF-DM1`;
- scale over bound and multiplication scale overflow return `OOF-DM4`/`OOF-DM5`;
- exact division preserves lhs scale;
- inexact division returns `OOF-DM3`;
- `1.5 == 1.50`;
- `1.0 < 5.0`;
- `9007199254740993 > 9007199254740992` without `to_f64`;
- existing Decimal construction, `to_text`, and web crossing tests remain green.

### 2. `LAB-IGNITER-COMPILER-DECIMAL-CONTRACT-TYPING-P2`

Follow-up after runtime safety lands. Scope: compiler/typechecker alignment for
Decimal scale bounds, named `add/sub/mul/div` result scale typing, and clearer
diagnostics around exact-only division. This should not precede runtime safety.

Acceptance tests:

- `decimal(value, scale)` rejects literal scale above 18 with `OOF-DM4`;
- Decimal multiplication type carries bounded scale sum or rejects overflow;
- named stdlib calls preserve the same result-scale policy as operators;
- no implicit Float-to-Decimal typing path appears.

## Close

No Decimal runtime code is changed by this packet. The chosen v0 contract keeps
public representation compatible, fixes arithmetic through checked `i128`
intermediates, makes equality/order exact, and allows only exact division until
an explicit rounding contract exists.
