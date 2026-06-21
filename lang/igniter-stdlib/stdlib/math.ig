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

-- LAB-STDLIB-MATH-NUMERIC-BASICS-P7: N0 scalar basics. Polymorphic over {Integer, Float} (Decimal deferred),
-- same-type-in/out, NO implicit coercion (mixed numeric types = OOF-MATH3). Deterministic by construction
-- (comparisons / sign flips are bit-identical across targets). Total over finite values: a non-finite Float
-- input, or `clamp` with lo > hi, is a deterministic runtime error. `sign` returns Integer (-1, 0, 1).
def abs(x: T) -> T
def min(a: T, b: T) -> T
def max(a: T, b: T) -> T
def clamp(x: T, lo: T, hi: T) -> T
def sign(x: T) -> Integer

-- LAB-STDLIB-MATH-INTEGER-ROOTS-AND-MOD-P8: N1 integer-only roots/powers/modulo. Integer args + Integer
-- result; NO Float/Decimal overload, NO implicit coercion. Deterministic by construction (pure integer
-- arithmetic, bit-identical cross-arch — no det_* variant needed). Arity → OOF-MATH1, non-Integer →
-- OOF-MATH2. Runtime domain errors (deterministic): isqrt(x<0), ipow(exp<0), ipow overflow, mod(_,0).
-- `isqrt` = floor integer square root. `ipow` = exponentiation by squaring (checked, never wraps).
-- `mod` = Euclidean remainder (non-negative result for a positive modulus).
def isqrt(x: Integer) -> Integer
def ipow(base: Integer, exp: Integer) -> Integer
def mod(a: Integer, b: Integer) -> Integer
