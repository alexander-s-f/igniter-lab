module BloomFilterHash
import BloomFilterTypes

-- ============================================================
-- Hash Functions
-- ============================================================
-- Igniter has no modulo (%), no bitwise ops, no string hashing.
-- We implement:
--   mod(a, b)   = a - (a / b) * b
--   hash(key, seed) = mod(seed.a * key + seed.b, filter_size)
--
-- For k=3 hash functions, we use 3 fixed seeds.
-- ============================================================

contract Mod {
  input a : Integer
  input b : Integer

  -- Manual modulo: a mod b = a - (a / b) * b
  -- Handles only positive a, b (sufficient for Bloom index)
  compute quot = a / b
  compute value = a - (quot * b)

  output value : Integer
}

contract Hash1 {
  input key : Integer
  input filter_size : Integer

  -- seed: a=31, b=17
  compute raw = 31 * key + 17
  compute abs_raw = if raw < 0 { 0 - raw } else { raw }
  compute quot = abs_raw / filter_size
  compute idx = abs_raw - (quot * filter_size)

  output idx : Integer
}

contract Hash2 {
  input key : Integer
  input filter_size : Integer

  -- seed: a=37, b=53
  compute raw = 37 * key + 53
  compute abs_raw = if raw < 0 { 0 - raw } else { raw }
  compute quot = abs_raw / filter_size
  compute idx = abs_raw - (quot * filter_size)

  output idx : Integer
}

contract Hash3 {
  input key : Integer
  input filter_size : Integer

  -- seed: a=61, b=7
  compute raw = 61 * key + 7
  compute abs_raw = if raw < 0 { 0 - raw } else { raw }
  compute quot = abs_raw / filter_size
  compute idx = abs_raw - (quot * filter_size)

  output idx : Integer
}
