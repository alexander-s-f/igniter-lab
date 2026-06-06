-- Type-directed dispatch proof fixture.
-- Trait/generic filtering status: the existing lab monomorphizer specializes
-- Add[T: Additive] to Add[Integer] only because no Additive[String] impl exists.

module Forms.TypeDispatch.GenericAdditive

trait Additive[T] {
  def add(a: T, b: T) -> T
}

impl Additive[Integer] using stdlib.numeric.add

contract_shape AddShape[T]
  form (left) "+" (right)
  priority 5
  associativity :left
{
  input left: T
  input right: T
  output result: T
}

contract Add[T: Additive] implements AddShape[T] {
  compute result = add(left, right)
}

contract UseGenericAdd {
  input a: Integer
  input b: Integer
  compute total = a + b
  output total: Integer
}
