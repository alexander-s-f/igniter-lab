# Card: LAB-STDLIB-STRING-CHAR-AT-VM-P1 — VM string char_at (+ substring)

**Status: READY (not started).** Small VM/runtime string op. Low priority (tail).

## Goal

Implement `stdlib.string.char_at` (and likely `stdlib.string.substring`) in the VM —
the only remaining real stdlib gap. Surfaced by `igniter_parser` (`ParseSource` with
a `source` input) which iterates characters.

## Scope

- `igniter-vm/src/vm.rs` OP_CALL: add `stdlib.string.char_at(s, i) -> String` (single
  char/rune at index) and `stdlib.string.substring(s, start, len)`. Mirror the existing
  `stdlib.text.*` slice handlers (byte/rune semantics — pick rune for v0 consistency
  with `text.rune_slice`).
- Decide alias vs new arm: `char_at` has no bare equivalent → new arm; `substring`
  may route to `text.rune_slice` if signatures align.

## Proof / closed

- Proof: `igniter run igniter-apps/igniter_parser --entry ParseSource -i source="…"`
  → success (depends also on `LAB-APP-DEMO-ENTRY-WAVE-P1` for a zero-input entry).
- Closed: no front-end change; rune-vs-byte policy stays consistent with `text.*`.
