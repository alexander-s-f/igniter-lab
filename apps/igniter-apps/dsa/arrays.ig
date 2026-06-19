module DSAArrays
import DSATypes
import stdlib.collection.{ map, filter }

-- ============================================================
-- Arrays (Indexed Collections)
-- ============================================================

contract ArrayGet {
  input arr : ArrayIndexed
  input target_idx : Integer

  -- O(N) lookup because we lack col[i]
  compute matches = filter(arr.elements, e ->
    if e.index == target_idx { true } else { false }
  )

  -- We output a Collection of matches because we lack head()
  output matches : Collection[IndexedElement]
}

contract MakeIndexedElement {
  input index : Integer
  input value : Integer

  compute elem = {
    index: index,
    value: value
  }

  output elem : IndexedElement
}

contract ArraySet {
  input arr : ArrayIndexed
  input target_idx : Integer
  input new_value : Integer

  -- O(N) update because we lack mutability and indexed access
  compute updated_elements = map(arr.elements, e ->
    if e.index == target_idx {
      call_contract("MakeIndexedElement", target_idx, new_value)
    } else {
      e
    }
  )

  compute updated_arr = {
    size: arr.size,
    elements: updated_elements
  }

  output updated_arr : ArrayIndexed
}
