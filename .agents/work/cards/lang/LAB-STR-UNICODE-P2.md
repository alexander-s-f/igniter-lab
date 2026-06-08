# Card: LAB-STR-UNICODE-P2

**Status:** ✅ CLOSED — 2026-06-08  
**Lane:** Standard / experimental-lab / implementation  
**Agent:** Igniter-Lab VM Agent  
**Role:** implementation-agent  
**Category:** lang  
**Track:** lab-text-unicode-runtime-ops-implementation-proof-v0  

---

## Task

Implement the missing VM OP_CALL handlers for Unicode-aware Text stdlib
operations in `igniter-lab/igniter-vm`, and prove end-to-end runtime
correctness via `verify_unicode_text_runtime.rb`.

## Depends on

- LAB-STR-UNICODE-P1 (Unicode authority / policy design-lock — closed 2026-06-08)
- LAB-STR-CORE-P3 (value semantics compile-time proof — closed 2026-06-08)
- LAB-RACK-P5 (VM stdlib.text.* alignment — closed 2026-06-08)

## Authorized Writes

- `igniter-lab/igniter-vm/Cargo.toml` — add unicode-segmentation dep
- `igniter-lab/igniter-vm/src/vm.rs` — add new OP_CALL handlers
- `igniter-lab/igniter-compiler/verify_unicode_text_runtime.rb`
- `igniter-lab/lab-docs/lang/lab-text-unicode-runtime-ops-implementation-proof-v0.md`
- `igniter-lab/.agents/work/cards/lang/LAB-STR-UNICODE-P2.md`
- `igniter-lab/.agents/portfolio-index.md` (update after closure)

## Closed

- Canon grammar changes (igniter-lang)
- igniter-org modifications
- Real TCP/socket (TCPSocket, UDPSocket, Socket, Net::HTTP)
- Production/release/runtime-execution gates
- Normalization ops (NFC/NFD/NFKC/NFKD)
- `stdlib.text.length` as canonical op
- Regex, locale folding, tokenizer, TextEngine
- New OOF error codes (v0 reuses OOF-TY0)

---

## What Was Done

### `igniter-vm/Cargo.toml`

```toml
unicode-segmentation = "1.11"
```

### `igniter-vm/src/vm.rs`

Added import:
```rust
use unicode_segmentation::UnicodeSegmentation;
```

Added 13 new OP_CALL handlers (after existing `stdlib.text.byte_length`):
- `stdlib.text.rune_length` — `s.chars().count()`
- `stdlib.text.grapheme_length` — `s.graphemes(true).count()` (UAX #29)
- `stdlib.text.byte_slice` — clamp, `s.get(start..end).unwrap_or("")`
- `stdlib.text.rune_slice` — `chars().skip(start).take(end-start)`
- `stdlib.text.grapheme_slice` — `graphemes(true).collect()[start..end].join("")`
- `stdlib.text.ends_with` — `s.ends_with(suffix)`
- `stdlib.text.replace` — empty pattern → error; `s.replacen(p, r, 1)`
- `stdlib.text.replace_all` — empty pattern → error; `s.replace(p, r)`
- `stdlib.text.concat` — qualified alias
- `stdlib.text.trim` — qualified alias
- `stdlib.text.contains` — qualified alias
- `stdlib.collection.concat` — Vec merge alias

Updated:
- `stdlib.text.split` — added empty-delimiter guard (runtime operational error)

### `verify_unicode_text_runtime.rb` — 43/43 PASS

Sections: UNI-DEP(10) · UNI-LENGTH(8) · UNI-SLICE(9) · UNI-REPLACE(6) ·
UNI-SPLIT(3) · UNI-CLOSED(4) · UNI-REG(3)

Key proofs:
- `rune_length("éx")` = 3 (3 codepoints), `grapheme_length("éx")` = 2 (UAX#29)
- `byte_slice("café", 3, 4)` = `""` (mid-codepoint boundary, fail-closed)
- `replace("banana", "a", "X")` = `"bXnana"` (first-match only)
- `split("hello", "")` → runtime operational error
- NFC "é" (2 bytes) ≠ NFD "é" (3 bytes) — no implicit normalization

---

## Implementation Notes

- Ruby `force_encoding('UTF-8')` required before `JSON.parse` in proof runner
  (backtick output is ASCII-8BIT; VM returns UTF-8 combining chars in results)
- Cleanup order matters: don't delete compiled contract dir between multiple
  run_vm calls using the same contract

---

## Design Doc

`igniter-lab/lab-docs/lang/lab-text-unicode-runtime-ops-implementation-proof-v0.md`

---

## Next Route

| Task | Type | Notes |
|------|------|-------|
| Portfolio update | Doc update | Mark P2 closed in portfolio-index.md |
| Unicode conformance receipt | Design | After runtime gate authorized |
| `split("")` grapheme-split future | Design | Decide before runtime gate opens |
| `length` legacy removal | Migration | Deferred — runtime gate required |
