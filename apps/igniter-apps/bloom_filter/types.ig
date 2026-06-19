module BloomFilterTypes

-- ============================================================
-- Bloom Filter Library — Core Types
-- ============================================================
-- A Bloom filter is a probabilistic set membership structure.
--
-- Key design challenge in Igniter:
--   No array index access (no head(), no col[i]).
--   No modulo operator (%).
--   No bitwise operations.
--
-- Solution:
--   The bit array is modeled as Collection[BitSlot] where
--   each slot has an explicit position Integer. To "set bit N",
--   we map over the collection and flip the slot where pos == N.
--   Modulo is computed manually: a mod b = a - (a / b) * b
-- ============================================================

type BitSlot {
  pos : Integer
  set : Bool
}

type BloomFilter {
  size : Integer
  num_hashes : Integer
  bits : Collection[BitSlot]
}

-- Hash seeds for k independent hash functions
type HashSeed {
  a : Integer
  b : Integer
}

-- Result of a membership query
type QueryResult {
  probably_contains : Bool
}
