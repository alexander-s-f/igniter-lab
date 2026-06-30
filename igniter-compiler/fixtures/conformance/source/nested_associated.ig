-- source/nested_associated.ig
-- Conformance fixture verifying nested option types and associated type structure monomorphization.

module Lang.Examples.NestedAssociated

trait Container[C] {
  type Element
  def wrap(item: Element) -> C
}

impl Container[Option[Integer]] using stdlib.option.wrap {
  type Element = Integer
}

contract_shape WrapShape[T, C] {
  input item: T
  output container: C
}

contract Wrap[C: Container] implements WrapShape[C::Element, C] {
  compute container = wrap(item)
}
