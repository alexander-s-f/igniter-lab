module DSAExample
import DSATypes
import DSAArrays
import DSASets
import DSAGraphs
import DSAStrings

-- ============================================================
-- DSA Examples
-- ============================================================

contract RunArrayExample {
  compute e0 = { index: 0, value: 10 }
  compute e1 = { index: 1, value: 20 }
  compute e2 = { index: 2, value: 30 }

  compute c2 = [e0, e1, e2]

  compute arr = { size: 3, elements: c2 }

  -- Get element at index 1
  compute res_get = call_contract("ArrayGet", arr, 1)

  -- Set element at index 1 to 99
  compute res_set = call_contract("ArraySet", arr, 1, 99)

  output res_get : Collection[IndexedElement]
  output res_set : ArrayIndexed
}

contract RunSetExample {
  compute c1 = [100, 200]

  compute s = { size: 2, elements: c1 }

  -- Check contains 200
  compute has_200 = call_contract("SetContains", s, 200)

  -- Check contains 300
  compute has_300 = call_contract("SetContains", s, 300)

  -- Insert 300
  compute s2 = call_contract("SetInsert", s, 300)

  output has_200 : Collection[Integer]
  output has_300 : Collection[Integer]
  output s2 : IntSet
}

contract RunGraphExample {
  -- Nodes 0, 1, 2
  compute edge1 = { from_node: 0, to_node: 1, weight: 5 }
  compute edge2 = { from_node: 0, to_node: 2, weight: 10 }
  compute edge3 = { from_node: 1, to_node: 2, weight: 2 }

  compute c2 = [edge1, edge2, edge3]

  compute g = { num_nodes: 3, edges: c2 }

  -- Get adjacent to 0
  compute adj_0 = call_contract("GetAdjacent", g, 0)

  -- Has edge 1 -> 2
  compute has_1_2 = call_contract("HasEdge", g, 1, 2)

  output adj_0 : Collection[Edge]
  output has_1_2 : Collection[Edge]
}

contract RunStringExample {
  -- Mock string "hi" (104, 105 in ASCII)
  compute c_h = { index: 0, value: 104 }
  compute c_i = { index: 1, value: 105 }

  compute c1 = [c_h, c_i]

  compute s = { length: 2, chars: c1 }

  compute char_1 = call_contract("CharAt", s, 1)

  output char_1 : Collection[IndexedElement]
}
