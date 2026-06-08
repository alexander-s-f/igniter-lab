# Lab: String Value Semantics — Bounds and Unicode Proof v0

**Track:** lab-string-value-semantics-bounds-and-unicode-proof-v0
**Card:** LAB-STR-CORE-P3
**Opened:** 2026-06-08
**Status:** ✅ CLOSED — verify_str_value_semantics.rb 33/33 PASS
**Depends on:** LAB-STR-CORE-P2, igniter-string-core-units-and-pure-stdlib-boundary-v0
**Route:** EXPERIMENTAL / LAB-ONLY

---

## Purpose

Prove the value-semantics boundary for the existing Text stdlib surface:

- **Proven** (compile-time): type signatures enforced, SemanticIR shapes correct,
  OOF-TY0 fires at the right call sites, closed surface remains closed.
- **Declared** (runtime-gated): bounds behavior, split edge cases, replace first-match
  policy — these are semantic contracts that can only be verified with a running runtime.
  They are declared here as proposed policy for when the runtime gate opens.

This document does not open runtime execution, add new stdlib ops, change canon
grammar, or claim stable API authority.

---

## Value Semantics Matrix

### 1. Length Unit Separation

| Operation | Unit | Return | Signature | v0 Policy |
|-----------|------|--------|-----------|-----------|
| `byte_length(t)` | UTF-8 bytes | Integer | (Text) → Integer | Count of UTF-8 octets in `t` |
| `rune_length(t)` | Unicode scalar values | Integer | (Text) → Integer | Count of Unicode code points (U+0000..U+10FFFF) |
| `grapheme_length(t)` | User-perceived clusters | Integer | (Text) → Integer | Count of grapheme clusters per UAX #29 (impl-defined for v0; grapheme_length("é") = 1) |

**Key invariant:** `byte_length(t) >= rune_length(t) >= grapheme_length(t)` for any valid
UTF-8 text. Operations are distinct — no single `length` op is canonical for v0.

**Example (declared, runtime-gated):**

| Text | byte_length | rune_length | grapheme_length |
|------|-------------|-------------|-----------------|
| `"hello"` | 5 | 5 | 5 |
| `"é"` (U+00E9) | 2 | 1 | 1 |
| `"é"` (U+0065 U+0301) | 3 | 2 | 1 |
| `"👨‍👩‍👧"` (family emoji, ZWJ sequence) | 25 | 8 | 1 |
| `""` (empty) | 0 | 0 | 0 |

---

### 2. Slice Unit Separation

| Operation | Unit | Return | Signature | Range Model |
|-----------|------|--------|-----------|-------------|
| `byte_slice(t, start, end)` | UTF-8 byte positions | Text | (Text, Integer, Integer) → Text | `[start, end)` half-open |
| `rune_slice(t, start, end)` | Unicode scalar positions | Text | (Text, Integer, Integer) → Text | `[start, end)` half-open |
| `grapheme_slice(t, start, end)` | Grapheme cluster positions | Text | (Text, Integer, Integer) → Text | `[start, end)` half-open |

All three use the **half-open range `[start, end)`** model: start-inclusive, end-exclusive.

---

### 3. Bounds Policy (declared v0; runtime-gated)

The compiler enforces only the **type** of indices (must be Integer). No static value
constraint exists — any Integer passes type-check. Runtime behavior is declared below.

| Condition | Declared policy | Notes |
|-----------|-----------------|-------|
| `start < 0` | Treat as 0 (clamp) | Fail-closed; negative index not meaningful |
| `end < start` | Return `""` (empty text) | Empty range is valid |
| `end == start` | Return `""` (empty text) | Degenerate range |
| `end > unit_length(t)` | Clamp to `unit_length(t)` | Fail-closed; no out-of-bounds error |
| `byte_slice` through invalid UTF-8 boundary | Return `""` (fail-closed) | UTF-8 byte-level slicing may produce invalid UTF-8 if start/end do not fall on code point boundaries; v0 policy: return empty rather than panic or produce invalid UTF-8 |
| Empty text `""` with any indices | Return `""` | Trivially valid |

**`byte_slice` UTF-8 boundary note:** This is the most subtle policy. If `start` or `end`
falls in the middle of a multi-byte UTF-8 sequence, the slice would produce invalid UTF-8.
v0 policy: implementation must not return invalid UTF-8. Fail-closed → return `""`.
This is a runtime gate. No compile-time enforcement is possible or required.

---

### 4. Split Edge Cases (declared v0; runtime-gated)

Signature: `split(text, delimiter)` → `Collection[Text]`

| Edge case | Declared behavior |
|-----------|------------------|
| Delimiter found once | Returns `["before", "after"]` (2 elements) |
| Delimiter not found | Returns `["original"]` (1 element — single-element collection) |
| Delimiter at start of text | Returns `["", "rest"]` (first element is empty string) |
| Delimiter at end of text | Returns `["prefix", ""]` (last element is empty string) |
| Delimiter repeated | Returns `["a", "b", "c"]` for `split("a..b..c", "..")` — one element per segment |
| Consecutive delimiters | Returns `["a", "", "c"]` for `split("a..c", ".")` — empty string between each pair |
| Empty text `""`, non-empty delimiter | Returns `[""]` (single-element collection with empty string) |
| Empty delimiter `""` | **Undefined behavior for v0.** Caller must not pass empty delimiter. No compile-time check exists; runtime behavior implementation-defined. |

---

### 5. Replace / replace_all Literal Semantics

| Property | `replace` | `replace_all` |
|----------|-----------|---------------|
| Match scope | First occurrence only | All non-overlapping occurrences |
| Direction | Left-to-right | Left-to-right |
| Pattern type | Literal string (no regex) | Literal string (no regex) |
| Locale sensitivity | None — byte-level match | None — byte-level match |
| Overlapping patterns | Not applicable (first match only) | Non-overlapping: after a match, scan resumes AFTER the end of the matched span |
| Empty pattern `""` | **Undefined for v0** | **Undefined for v0** |
| Pattern not found | Return original text unchanged | Return original text unchanged |

**No regex:** Pattern strings are matched literally. `".*"` matches the four-character
literal string `.*`, not any sequence of characters. This is enforced by policy, not
by the type system. There is no `Regex` type in v0 — any `Text` value accepted as a
pattern arg is treated as a literal.

**Proven:** The compiler accepts `replace(text, ".*", "[x]")` without OOF-TY0, confirming
the type system treats regex-like patterns as ordinary `Text` literals.

---

### 6. concat Semantics (P2 regression, declared complete)

| Call form | Resolved to | Declared behavior |
|-----------|-------------|-------------------|
| `concat(a: Text, b: Text)` | `stdlib.text.concat` | String concatenation; no separator |
| `concat(a: Collection, b: Collection)` | `stdlib.collection.concat` | Collection join |

No separator is inserted. `concat("ab", "cd")` → `"abcd"`.

---

### 7. Text vs String Stance

| Name | Role | v0 rule |
|------|------|---------|
| `Text` | Canonical contract type for text values | Used in `input`/`output`/`compute` type annotations |
| `String` | Parser `type_tag` for string literals | Accepted as `Text` arg without type error (v0 compat) |

**Text is canonical.** No new `String`-typed canonical stdlib ops. `String` is not a
user-facing contract type. Any future Text ops must use `Text`, not `String`.

**`length` status:** Legacy/held. The Rust lab typechecker retains a `"length"` handler
(accepts Text, returns Integer) from the pre-STR-CORE period. It is NOT part of the
canonical 14-op v0 surface. Callers should use the explicit unit ops
(`byte_length` / `rune_length` / `grapheme_length`). The legacy handler will be
removed when the runtime gate opens and the full migration is done.

---

### 8. Closed Surface

The following call sites are explicitly closed and produce `OOF-TY0`:

| Surface | Reason closed |
|---------|---------------|
| `regex_match`, `regex_find`, `regex_replace` | Regex deferred |
| `locale_fold_case`, `fold_case`, `upcase`, `downcase` | Locale-sensitive case folding deferred |
| `tokenize` | Tokenizer framework deferred |
| `TextEngine`, streaming text | TextEngine deferred |
| `text.method()` method syntax | Method syntax deferred |
| Source-level namespace syntax `Text.fn()` | Namespace form deferred |

---

## Proof Evidence

**Proof runner:** `igniter-lab/igniter-compiler/verify_str_value_semantics.rb`

| Section | Checks | What is proven |
|---------|--------|----------------|
| STR-VALUE-UNIT | 6 | byte/rune/grapheme_length: compile, no OOF, SIR fn names, bad-type OOF |
| STR-VALUE-SLICE | 5 | byte/rune/grapheme_slice: compile, no OOF, SIR fn+resolved_type |
| STR-VALUE-BOUNDS | 3 | bad index types → OOF-TY0; Integer accepted; arity error → OOF-TY0 |
| STR-VALUE-SPLIT | 4 | split compiles, SIR fn, Collection[Text] params shape, arity OOF |
| STR-VALUE-REPLACE | 5 | replace/replace_all compile, SIR fn names, regex-literal accepted, arity OOF |
| STR-VALUE-TEXT-STRING | 3 | Text annotation, String literal compat, `length` legacy note |
| STR-VALUE-CLOSED | 3 | regex_match / locale_fold_case / tokenize → OOF-TY0 |
| STR-VALUE-CONCAT | 3 | P2 disambiguation: Text→stdlib.text.concat, Collection→stdlib.collection.concat |
| STR-VALUE-REG | 2 | Integer arithmetic and recur() unaffected |
| **Total** | **33/33 PASS** | 2026-06-08 |

---

## Implementation Gaps (runtime-gated)

These are gaps that cannot be closed without opening the runtime gate:

| Gap | Description | Gate needed |
|-----|-------------|-------------|
| `byte_slice` UTF-8 boundary enforcement | Must return `""` (not panic) on mid-sequence start/end | Runtime |
| Bounds clamping for all slice ops | Negative/overflow index → clamp to 0/length | Runtime |
| `split("")` undefined behavior | Empty delimiter behavior must be specified | Runtime |
| `replace("")` / `replace_all("")` | Empty pattern behavior must be specified | Runtime |
| `grapheme_length` / `grapheme_slice` UAX #29 | Full Unicode grapheme cluster algorithm | Runtime + Unicode library |
| `rune_length` for decomposed forms | NFC/NFD invariant not enforced at compiler | Runtime + normalization policy |
| `length` legacy removal | Remove old `length` handler when unit ops are stable | Runtime migration |

---

## Boundary Constraints (carry-forward)

- **Do not add `stdlib.text.length`** as a canonical op. The canonical ops are
  `byte_length`, `rune_length`, `grapheme_length`.
- **Do not open regex, locale, tokenizer** without a separate gate decision.
- **Do not claim stable API authority** — this proof is experiment-pass compiler surface only.
- **Runtime execution, `igc run`, `.igbin`** remain closed.
- **Value semantics for edge cases** (bounds, empty delimiter, empty pattern) remain
  declared policy only until the runtime gate opens.

---

## Next Route

| Task | Priority | Notes |
|------|----------|-------|
| Runtime gate (bounds, UTF-8, grapheme/UAX #29) | When runtime opens | Depends on runtime execution gate |
| `grapheme_*` UAX #29 library decision | Design | Which Unicode grapheme cluster impl is authoritative? |
| `length` legacy removal | Cleanup | When explicit unit ops are stable and runtime is open |
| Collection[Text] deep param check | Enhancement | v0 compares only top-level type name |
| `split("")` policy decision | Design | Before runtime gate opens |
