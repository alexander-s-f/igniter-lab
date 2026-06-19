-- stdlib/math.ig
-- Declarative signatures for standard financial and arithmetic operations

module stdlib.Math

-- Fixed-point Decimal operations with explicit scale constraints
def add(a: Decimal[S], b: Decimal[S]) -> Decimal[S]
def sub(a: Decimal[S], b: Decimal[S]) -> Decimal[S]
def mul(a: Decimal[S1], b: Decimal[S2]) -> Decimal[S1 + S2]
def div(a: Decimal[S1], b: Decimal[S2]) -> Decimal[S1 - S2]
