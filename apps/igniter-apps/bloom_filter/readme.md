# Bloom Filter Library for Igniter

A probabilistic set membership data structure written in Igniter. Achieves **full compilation** through all stages (`parse → classify → typecheck → emit → assemble → ok`), producing a complete `igapp` artifact with 14 contracts.

## Architecture

```
types.ig    → BitSlot, BloomFilter, HashSeed, QueryResult
hash.ig     → Mod, Hash1, Hash2, Hash3 (3 independent hash functions)
ops.ig      → SetBitAtIndex, CheckBitAtIndex, MakeSlotTrue, Insert, Query
example.ig  → InitFilter16 (16-bit filter), RunBloomExample (URL cache)
```

### How It Works

1. **Bit Array**: Modeled as `Collection[BitSlot]` where each `BitSlot { pos: Integer, set: Bool }` represents one bit. Since Igniter has no array index access, setting bit N uses `map()` to scan all slots and flip the matching one.

2. **Hash Functions**: Three independent hash functions using `h(key) = (a * key + b) mod size`. Modulo is computed manually as `a - (a / b) * b` since Igniter has no `%` operator.

3. **Insert**: Computes 3 hash indices, then chains 3 `SetBitAtIndex` calls.

4. **Query**: Computes 3 hash indices, then chains 3 `CheckBitAtIndex` calls. Returns `QueryResult.probably_contains`.

### Example: URL Visited Cache

```
Insert: hash("example.com")=42, hash("igniter.dev")=99, hash("docs.igniter.dev")=157
Query:  42 → HIT, 999 → MISS (probably), 99 → HIT
```

## Compilation

```bash
cargo run -- compile types.ig hash.ig ops.ig example.ig --out bloom_filter.igapp
```

**Result**: Full compilation — 14 contracts emitted.
