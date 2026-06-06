-- polymorphic_add.ig
-- Parser acceptance fixture for bounded polymorphic Add.
-- Still parser-only: no trait coherence, typechecking, or SemanticIR claim.

module Lang.Examples.PolymorphicAdd

trait Additive[T] {
  def add(a: T, b: T) -> T
}

impl Additive[Integer] using stdlib.numeric.add
impl Additive[Float] using stdlib.numeric.add
-- No Additive[String] in this fixture.
-- String concatenation should use ++ / Concat, not numeric add.

contract_shape AddShape[T] {
  input a: T
  input b: T
  output sum: T
}

contract Add[T: Additive] implements AddShape[T] {
  compute sum = add(a, b)
}
