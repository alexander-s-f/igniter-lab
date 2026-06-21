-- stdlib/math.ig
-- Declarative signatures for standard financial and arithmetic operations

module stdlib.Math

-- Fixed-point Decimal operations with explicit scale constraints
def add(a: Decimal[S], b: Decimal[S]) -> Decimal[S]
def sub(a: Decimal[S], b: Decimal[S]) -> Decimal[S]
def mul(a: Decimal[S1], b: Decimal[S2]) -> Decimal[S1 + S2]
def div(a: Decimal[S1], b: Decimal[S2]) -> Decimal[S1 - S2]

-- LAB-STDLIB-MATH-TRANSCENDENTALS-P2: Tier-1 Float transcendentals (fast, platform f64 — NOT a
-- cross-architecture determinism claim). No implicit Integer/Decimal coercion.
def sin(x: Float) -> Float
def cos(x: Float) -> Float
def sqrt(x: Float) -> Float
def pi() -> Float

-- LAB-STDLIB-MATH-DET-TIER1-P5: DETERMINISTIC, replay-safe Float transcendentals (flat `det_*` spelling —
-- a dotted `det.sin` is a parse error). det_sin/det_cos via vendored pure-Rust libm with local golden-bit
-- lock; cross-arch confirmation is a qemu-CI follow-up. det_sqrt uses IEEE-correct std f64::sqrt. Never
-- NaN/Inf: a non-finite input or a negative det_sqrt is a deterministic runtime error. Governed by
-- STDLIB_VERSION.
def det_sin(x: Float) -> Float
def det_cos(x: Float) -> Float
def det_sqrt(x: Float) -> Float
