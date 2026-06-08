# Lab Text Unicode Runtime Ops — Implementation Proof (v0)

**Card:** LAB-STR-UNICODE-P2  
**Status:** ✅ CLOSED — 2026-06-08  
**Proof:** `verify_unicode_text_runtime.rb` — 43/43 PASS  
**Depends on:**
- LAB-STR-UNICODE-P1 (Unicode authority / policy design-lock)
- LAB-STR-CORE-P3 (value semantics compile-time proof)
- LAB-RACK-P5 (VM stdlib.text.* alignment: starts_with, split, byte_length)

---

## Scope

This document records the design, implementation, and runtime proof for the
missing VM OP_CALL handlers for Unicode-aware Text stdlib operations.

The P1 design-lock established the Unicode policy surface. P2 implements
that policy in the VM and proves it end-to-end (compile → VM execute → result).

**Closed:** canon grammar, igniter-org, real TCP/socket, normalization,
`length` legacy, regex, locale folding, tokenizer, production/release gates.

---

## Changes (LAB-STR-UNICODE-P2)

### `igniter-vm/Cargo.toml`

```toml
# LAB-STR-UNICODE-P2: UAX #29 extended grapheme clusters for stdlib.text.grapheme_*
unicode-segmentation = "1.11"
```

### `igniter-vm/src/vm.rs`

Import added at top of file:

```rust
// LAB-STR-UNICODE-P2: UAX #29 extended grapheme cluster segmentation
use unicode_segmentation::UnicodeSegmentation;
```

New and updated OP_CALL handlers:

| Handler | Implementation | Policy |
|---------|---------------|--------|
| `stdlib.text.rune_length` | `s.chars().count()` | Unicode scalar value count |
| `stdlib.text.grapheme_length` | `s.graphemes(true).count()` | UAX #29 Extended Grapheme Cluster |
| `stdlib.text.byte_slice` | clamp → `s.get(start..end).unwrap_or("")` | `[start,end)` half-open; invalid boundary → `""` |
| `stdlib.text.rune_slice` | `s.chars().skip(start).take(end-start).collect()` | clamp bounds |
| `stdlib.text.grapheme_slice` | `graphemes(true).collect()[start..end].join("")` | clamp bounds |
| `stdlib.text.ends_with` | `s.ends_with(suffix)` | — |
| `stdlib.text.replace` | `s.replacen(pattern, repl, 1)` | empty pattern → operational error |
| `stdlib.text.replace_all` | `s.replace(pattern, repl)` | empty pattern → operational error |
| `stdlib.text.split` (guard) | existing handler + empty check | empty delimiter → operational error |
| `stdlib.text.concat` | `format!("{}{}", a, b)` | alias for text concat |
| `stdlib.text.trim` | `s.trim()` | alias with arity check |
| `stdlib.text.contains` | `s.contains(sub)` | alias with arity check |
| `stdlib.collection.concat` | Vec merge | alias for collection concat |

---

## Policy Anchors (from LAB-STR-UNICODE-P1)

| Policy | Decision | Status |
|--------|----------|--------|
| Text = valid UTF-8 | `Value::String(Arc<str>)` structural enforcement | LOCKED |
| byte unit | UTF-8 octet, `s.len()` | LOCKED |
| rune unit | Unicode scalar value, `s.chars().count()` | LOCKED |
| grapheme unit | UAX #29 Extended Grapheme Cluster, `s.graphemes(true)` | LOCKED |
| No implicit normalization | NFC "é" (2 bytes) ≠ NFD "é" (3 bytes) | LOCKED |
| trim whitespace | Unicode Pattern_White_Space, `str::trim()` | LOCKED |
| byte_slice invalid boundary | Return `""` — fail-closed | LOCKED |
| split("") | Runtime operational error — no fallback | LOCKED |
| replace("") / replace_all("") | Runtime operational error — no fallback | LOCKED |
| unicode-segmentation | Acceptable for lab proof | LOCKED |

---

## Proof Results (43/43 PASS)

### UNI-DEP (10 checks) — Dependency and source presence

| Check | Description |
|-------|-------------|
| UNI-DEP-01 | Cargo.toml contains unicode-segmentation dep |
| UNI-DEP-02 | vm.rs contains UnicodeSegmentation import |
| UNI-DEP-03 | vm.rs contains stdlib.text.rune_length handler |
| UNI-DEP-04 | vm.rs contains stdlib.text.grapheme_length handler |
| UNI-DEP-05 | vm.rs contains stdlib.text.grapheme_slice handler |
| UNI-DEP-06 | vm.rs contains stdlib.text.replace handler |
| UNI-DEP-07 | vm.rs contains stdlib.text.replace_all handler |
| UNI-DEP-08 | vm.rs contains stdlib.text.ends_with handler |
| UNI-DEP-09 | vm.rs split handler contains empty-delimiter guard |
| UNI-DEP-10 | vm.rs replace handler contains empty-pattern guard |

### UNI-LENGTH (8 checks) — byte / rune / grapheme length distinction

| Check | Input | Expected | Proof |
|-------|-------|----------|-------|
| UNI-LENGTH-04 | `byte_length("café")` | 5 | UTF-8: c(1)+a(1)+f(1)+é(2) |
| UNI-LENGTH-05 | `rune_length("café")` | 4 | 4 Unicode scalar values |
| UNI-LENGTH-06 | `grapheme_length("café")` | 4 | 4 UAX#29 grapheme clusters |
| UNI-LENGTH-07 | `rune_length("éx")` | 3 | 3 codepoints: e + U+0301 + x |
| UNI-LENGTH-08 | `grapheme_length("éx")` | 2 | 2 graphemes: (e+U+0301), x |

Key distinction proven: `rune_length("éx")` = 3 but `grapheme_length("éx")` = 2.
This is the core UAX #29 Extended Grapheme Cluster property.

### UNI-SLICE (9 checks) — byte_slice / rune_slice / grapheme_slice

| Check | Input | Expected | Policy |
|-------|-------|----------|--------|
| UNI-SLICE-04 | `byte_slice("hello", 1, 4)` | `"ell"` | `[1,4)` half-open |
| UNI-SLICE-05 | `byte_slice("café", 3, 4)` | `""` | mid-codepoint → fail-closed |
| UNI-SLICE-06 | `byte_slice("hello", -5, 100)` | `"hello"` | clamp negative/over-end |
| UNI-SLICE-07 | `rune_slice("café", 0, 3)` | `"caf"` | first 3 runes |
| UNI-SLICE-08 | `grapheme_slice("éx", 0, 1)` | `"é"` | first grapheme cluster (NFD) |
| UNI-SLICE-09 | `grapheme_slice("éx", 1, 2)` | `"x"` | second grapheme |

### UNI-REPLACE (6 checks) — replace / replace_all / empty-pattern error

| Check | Input | Expected | Policy |
|-------|-------|----------|--------|
| UNI-REPLACE-03 | `replace("banana", "a", "X")` | `"bXnana"` | first-match only (`replacen(..., 1)`) |
| UNI-REPLACE-04 | `replace_all("banana", "a", "X")` | `"bXnXnX"` | all occurrences |
| UNI-REPLACE-05 | `replace("hello", "", "X")` | runtime error | empty pattern → operational error |
| UNI-REPLACE-06 | `replace_all("hello", "", "X")` | runtime error | empty pattern → operational error |

### UNI-SPLIT (3 checks) — empty delimiter runtime error

| Check | Input | Expected |
|-------|-------|----------|
| UNI-SPLIT-02 | `split("a,b,c", ",")` | `["a","b","c"]` |
| UNI-SPLIT-03 | `split("hello", "")` | runtime operational error |

### UNI-CLOSED (4 checks) — ends_with + no normalization

| Check | Description |
|-------|-------------|
| UNI-CLOSED-02 | `ends_with("hello world", "world")` = true |
| UNI-CLOSED-03 | `ends_with("hello", "world")` = false |
| UNI-CLOSED-04 | NFC "é" (2 bytes) ≠ NFD "é" (3 bytes) — no implicit normalization |

### UNI-REG (3 checks) — regression

All three existing ops (byte_length, starts_with, trim) return correct results
after the new handler block is inserted.

---

## Implementation Notes

### UTF-8 output encoding in Ruby proof runner

Ruby's backtick command output is ASCII-8BIT. The VM returns UTF-8 bytes for
Unicode result values (e.g., combining character sequences). The proof runner
calls `.force_encoding('UTF-8')` before `JSON.parse` to handle this correctly.
This is a Ruby tooling detail — the VM output is correct UTF-8.

### grapheme_slice return type

The VM's `grapheme_slice` handler collects grapheme cluster `&str` slices via
`graphemes(true).collect::<Vec<&str>>()` and joins with `[start..end].join("")`.
This preserves the original UTF-8 byte sequences exactly — no normalization occurs.

### replace vs replace_all distinction

`replace` uses Rust `str::replacen(pattern, repl, 1)` — first occurrence only.
`replace_all` uses Rust `str::replace(pattern, repl)` — all occurrences.
The distinction is proven by `replace("banana", "a", "X")` = `"bXnana"` (not `"bXnXnX"`).

---

## Deferred (runtime-gate required)

- `split("")` grapheme-split future design (before runtime gate opens)
- Unicode conformance receipt schema (`grapheme_backend`, `unicode_version`, `crate_version`)
- `length` legacy op migration (removal deferred)
- Normalization operations (NFC/NFD/NFKC/NFKD) — not in v0

---

## Next Route

| Task | Notes |
|------|-------|
| Portfolio update | Mark LAB-STR-UNICODE-P2 closed in portfolio-index.md |
| Runtime gate planning | Unicode conformance receipt design after gate opens |
| `split("")` future | Decide grapheme-split behavior before runtime gate |
