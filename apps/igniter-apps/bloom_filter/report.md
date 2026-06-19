# Bloom Filter: Stdlib & Compiler Pressure Report

Second fully-compiled Igniter application. The Bloom filter pushes the language
into territory requiring index-addressed data, hashing, and modular arithmetic.

## 1. FULL COMPILATION ACHIEVED (Second Time)

```
parse: ok → classify: ok → typecheck: ok → emit: ok → assemble: ok
status: ok — 14 contracts
```

Confirms the vector_math result was not a fluke — Igniter can reliably
fully compile multi-module applications with complex data flow.

## 2. No Array Index Access — BitSlot Pattern

The core Bloom filter challenge: you need to set/check bit at position N.
Igniter has no `col[i]`, no `head()`, no `nth()`.

**Solution**: Model the bit array as `Collection[BitSlot]` where each slot
carries its own `pos: Integer`. Setting bit N is a `map()` over all slots:
```
map(bits, slot -> if slot.pos == target_idx { MakeSlotTrue(slot.pos) } else { slot })
```

**Cost**: O(n) per bit operation instead of O(1). For a 16-bit filter,
every insert does 3 × 16 = 48 comparisons. For a production-size filter
(1024 bits), that's 3 × 1024 = 3072 comparisons per insert.

**Implication**: Igniter desperately needs indexed collection access for
any performance-sensitive data structure work.

## 3. No Modulo Operator (%)

Hash functions universally require modulo to map into a fixed range.
Igniter lacks `%`.

**Solution**: Manual modulo: `a mod b = a - (a / b) * b`

This works perfectly for positive integers and compiled through typecheck
without issues. However, it should be a stdlib function.

## 4. No String Hashing

Bloom filters typically hash strings. Igniter has no string operations
at all. We represented URLs as pre-hashed Integer keys.

**Implication**: Combined with the findings from the parser app, this
confirms that `stdlib.string` is the #1 priority for practical applications.

## 5. Collection Initialization Without range()

Creating a 16-slot bit array required **16 individual compute statements**
and **15 chained append calls**. A `range(0, 16)` function that produces
`Collection[Integer]` followed by a `map()` would reduce this to 2 lines.

**Implication**: `stdlib.collection.range` is a high-priority addition.

## 6. Filter → Boolean Collapse Problem

`CheckBitAtIndex` returns `Collection[BitSlot]` (the filtered matches).
To determine if the bit is actually set, we need to know if this collection
is non-empty. Without `length()`, `is_empty()`, or `head()`, this is
**impossible to determine programmatically**.

The `Query` contract works around this by returning a static
`probably_contains: true` and documenting the limitation. A real
implementation requires `stdlib.collection.is_empty` or `length`.

## Summary Table

| Feature | Status | Impact |
|---|---|---|
| Full compilation | ✅ ok | Second confirmed success |
| Manual modulo (`a - (a/b)*b`) | ✅ Works | Needs stdlib `mod` |
| BitSlot pattern for indexing | ✅ Works | O(n) cost, needs index access |
| Collection initialization | ⚠️ Verbose | Needs `range()` |
| Filter → Boolean | ❌ Blocked | Needs `is_empty()` / `length()` |
| String hashing | ❌ Missing | Needs `stdlib.string` |
