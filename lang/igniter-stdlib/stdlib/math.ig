-- stdlib/math.ig
-- Declarative signatures for standard financial and arithmetic operations

module stdlib.Math

-- Fixed-point Decimal operations with explicit scale constraints
def add(a: Decimal[S], b: Decimal[S]) -> Decimal[S]
def sub(a: Decimal[S], b: Decimal[S]) -> Decimal[S]
def mul(a: Decimal[S1], b: Decimal[S2]) -> Decimal[S1 + S2]
def div(a: Decimal[S1], b: Decimal[S2]) -> Decimal[S1 - S2]

-- LAB-STDLIB-MATH-TRANSCENDENTALS-P2: Tier-1 Float transcendentals (fast f64 path).
-- No implicit Integer/Decimal coercion; deterministic cross-arch variants are a separate card.
def sin(x: Float) -> Float
def cos(x: Float) -> Float
def sqrt(x: Float) -> Float
def pi() -> Float
