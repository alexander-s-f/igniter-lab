module BloomFilterExample
import BloomFilterTypes
import BloomFilterOps
import stdlib.collection.{ append }

-- ============================================================
-- Example: URL Visited Cache
-- ============================================================
-- Model a browser's "have I visited this URL?" cache using
-- a Bloom filter. URLs are represented as Integer hashes
-- since Igniter lacks string hashing.
-- ============================================================

contract InitFilter16 {
  -- Create a 16-slot bloom filter (k=3 hash functions)
  -- Build slots manually since there's no range() function
  compute s0 = { pos: 0, set: false }
  compute s1 = { pos: 1, set: false }
  compute s2 = { pos: 2, set: false }
  compute s3 = { pos: 3, set: false }
  compute s4 = { pos: 4, set: false }
  compute s5 = { pos: 5, set: false }
  compute s6 = { pos: 6, set: false }
  compute s7 = { pos: 7, set: false }
  compute s8 = { pos: 8, set: false }
  compute s9 = { pos: 9, set: false }
  compute s10 = { pos: 10, set: false }
  compute s11 = { pos: 11, set: false }
  compute s12 = { pos: 12, set: false }
  compute s13 = { pos: 13, set: false }
  compute s14 = { pos: 14, set: false }
  compute s15 = { pos: 15, set: false }

  -- Build the collection by chaining appends
  compute b0 = call_contract("append", s0, s1)
  compute b1 = call_contract("append", b0, s2)
  compute b2 = call_contract("append", b1, s3)
  compute b3 = call_contract("append", b2, s4)
  compute b4 = call_contract("append", b3, s5)
  compute b5 = call_contract("append", b4, s6)
  compute b6 = call_contract("append", b5, s7)
  compute b7 = call_contract("append", b6, s8)
  compute b8 = call_contract("append", b7, s9)
  compute b9 = call_contract("append", b8, s10)
  compute b10 = call_contract("append", b9, s11)
  compute b11 = call_contract("append", b10, s12)
  compute b12 = call_contract("append", b11, s13)
  compute b13 = call_contract("append", b12, s14)
  compute b14 = call_contract("append", b13, s15)

  compute bf = {
    size: 16,
    num_hashes: 3,
    bits: b14
  }

  output bf : BloomFilter
}

contract RunBloomExample {
  -- Initialize a 16-bit filter
  compute empty_filter = call_contract("InitFilter16")

  -- Insert some "URL hashes"
  -- url_a = hash("https://example.com") → 42
  -- url_b = hash("https://igniter.dev") → 99
  -- url_c = hash("https://docs.igniter.dev") → 157

  compute bf_1 = call_contract("Insert", empty_filter, 42)
  compute bf_2 = call_contract("Insert", bf_1, 99)
  compute bf_3 = call_contract("Insert", bf_2, 157)

  -- Query: was "example.com" visited? (key=42, inserted → should match)
  compute query_hit = call_contract("Query", bf_3, 42)

  -- Query: was "unknown.com" visited? (key=999, NOT inserted → maybe false positive)
  compute query_miss = call_contract("Query", bf_3, 999)

  -- Query: was "igniter.dev" visited? (key=99, inserted → should match)
  compute query_hit_2 = call_contract("Query", bf_3, 99)

  output query_hit : QueryResult
  output query_miss : QueryResult
  output query_hit_2 : QueryResult
}
