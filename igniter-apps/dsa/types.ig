module DSATypes

-- ============================================================
-- Data Structures & Algorithms
-- ============================================================

-- ── Arrays ──────────────────────────────────────────────────
-- Since Igniter has no array indexing, an Array must track
-- the explicit index of every element if we want positional access.

type IndexedElement {
  index : Integer
  value : Integer
}

type ArrayIndexed {
  size : Integer
  elements : Collection[IndexedElement]
}

-- ── Sets ────────────────────────────────────────────────────
-- A Set of integers.

type IntSet {
  size : Integer
  elements : Collection[Integer]
}

-- ── Graphs ──────────────────────────────────────────────────
-- Adjacency list representation.

type Edge {
  from_node : Integer
  to_node : Integer
  weight : Integer
}

type Graph {
  num_nodes : Integer
  edges : Collection[Edge]
}

-- ── Strings ─────────────────────────────────────────────────
-- Since Igniter Strings are opaque and lack operations,
-- we represent a manipulable string as a Collection of Integers
-- (ASCII/Unicode code points).

type CharString {
  length : Integer
  chars : Collection[IndexedElement]
}

-- A result of substring search
type SearchResult {
  found : Bool
  index : Integer
}
