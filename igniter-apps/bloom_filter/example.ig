module BloomFilterExample
import BloomFilterTypes
import BloomFilterOps
import stdlib.collection.{ map, range }

-- ============================================================
-- Example: URL Visited Cache
-- ============================================================
-- Model a browser's "have I visited this URL?" cache using
-- a Bloom filter. URLs are represented as Integer hashes
-- since Igniter lacks string hashing.
-- ============================================================

contract InitFilter16 {
  -- Create a 16-slot bloom filter (k=3 hash functions)
  -- LAB-BLOOM-FILTER-RANGE-MIGRATION-P1: range(0, 16) replaces
  -- 16 manual slot computes + 14 chained append calls.
  compute slots : Collection[BitSlot] = map(range(0, 16), i -> call_contract("MakeSlot", i))

  compute bf = {
    size: 16,
    num_hashes: 3,
    bits: slots
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
