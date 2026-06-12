module DSASets
import DSATypes
import stdlib.collection.{ filter }

-- ============================================================
-- Sets
-- ============================================================

contract SetContains {
  input s : IntSet
  input target : Integer

  -- Filter to find the element
  compute matches = filter(s.elements, e ->
    if e == target { true } else { false }
  )

  -- We return the matches collection because we lack is_empty()
  output matches : Collection[Integer]
}

contract SetInsert {
  input s : IntSet
  input new_elem : Integer

  -- In a real language we check contains first, but because
  -- SetContains returns a Collection and we lack is_empty(),
  -- we can't conditionally branch on the result.
  -- We'll just append it, meaning this is technically a Multiset
  -- due to language limitations!
  --
  -- Real implementation WOULD be:
  -- compute already_exists = call_contract("SetContains", s, new_elem)
  -- compute new_elements = if already_exists { s.elements } else { concat(s.elements, [new_elem]) }

  compute new_elements = concat(s.elements, [new_elem])

  compute new_set = {
    size: s.size + 1,
    elements: new_elements
  }

  output new_set : IntSet
}
