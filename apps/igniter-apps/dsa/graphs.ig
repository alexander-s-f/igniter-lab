module DSAGraphs
import DSATypes
import stdlib.collection.{ filter }

-- ============================================================
-- Graphs
-- ============================================================

contract GetAdjacent {
  input g : Graph
  input node_id : Integer

  -- Find all edges where from_node == node_id
  compute adjacent_edges = filter(g.edges, e ->
    if e.from_node == node_id { true } else { false }
  )

  -- We would typically want to map this to just the to_node Integers,
  -- but returning the edges is fine for demonstrating graph connectivity.
  output adjacent_edges : Collection[Edge]
}

contract HasEdge {
  input g : Graph
  input from_id : Integer
  input to_id : Integer

  compute matches = filter(g.edges, e ->
    if e.from_node == from_id {
      if e.to_node == to_id {
        true
      } else {
        false
      }
    } else {
      false
    }
  )

  -- Returns Collection[Edge]. Non-empty implies true.
  output matches : Collection[Edge]
}
