# Card: LAB-STR-UNICODE-P3

**Status:** ✅ CLOSED — 2026-06-08  
**Lane:** Standard / experimental-lab / implementation  
**Agent:** Igniter-Lab VM Agent  
**Role:** implementation-agent  
**Category:** lang  
**Track:** lab-text-unicode-runtime-receipt-and-handler-hygiene-v0  

---

## Task

Harden the LAB-STR-UNICODE-P2 runtime proof by:
1. Aligning the bare `"split"` VM handler with the empty-delimiter fail-closed policy
2. Emitting a machine-readable Unicode runtime receipt
3. Verifying handler-policy consistency across bare and qualified handler names

## Depends on

- LAB-STR-UNICODE-P2 (Unicode VM runtime ops — closed 2026-06-08)
- LAB-STR-UNICODE-P1 (Unicode policy design-lock — closed 2026-06-08)

## Authorized Writes

- `igniter-lab/igniter-vm/src/vm.rs` — bare `"split"` handler guard only
- `igniter-lab/igniter-compiler/verify_unicode_text_runtime.rb`
- `igniter-lab/igniter-compiler/out/unicode_runtime_receipt.json` (generated)
- `igniter-lab/lab-docs/lang/lab-text-unicode-runtime-receipt-and-handler-hygiene-v0.md`
- `igniter-lab/.agents/work/cards/lang/LAB-STR-UNICODE-P3.md`
- `igniter-lab/.agents/portfolio-index.md` (update after closure)

## Closed

- Canon grammar changes (igniter-lang)
- igniter-org modifications
- New Text/String APIs
- Normalization ops (NFC/NFD/NFKC/NFKD)
- `stdlib.text.length` as canonical op
- Production/release/stable-API gates

---

## What Was Done

### `igniter-vm/src/vm.rs` — bare split guard

Added to bare `"split"` handler:
```rust
// LAB-STR-UNICODE-P3: align bare handler with stdlib.text.split policy
if sep.is_empty() {
    return Err("split: empty delimiter is an operational error (v0 policy)".to_string());
}
```

**Before:** bare `split("")` would use Rust's `str::split("")` behavior
(splits at every char boundary → empty strings everywhere) — a silent policy bypass.
**After:** bare `split` and `stdlib.text.split` are both fail-closed on empty delimiter.

### `verify_unicode_text_runtime.rb` — updated with P3 sections

Added: UNI-DEP · UNI-RCP · UNI-HYG · UNI-ERR · UNI-LENGTH · UNI-SLICE · UNI-REPLACE · UNI-SPLIT · UNI-ALIAS · UNI-AUTH · UNI-PATH

**41/41 PASS**

### `out/unicode_runtime_receipt.json` — receipt

Key fields:
- `status: "lab-only-evidence"` — no stable/public/production claim
- `cargo_lock_resolved: "1.13.3"` — actual resolved dependency version
- `grapheme_algorithm: "uax29-extended-grapheme-cluster"`
- `applies_to_bare_handler: true` — empty-input policy covers bare and qualified handlers
- `handler_consistency: { bare_split_guarded: true, ... }` — all 4 guards confirmed

---

## Implementation Notes

### UTF-8 encoding in proof runner

Ruby string literals with non-ASCII chars get NFC-normalized by file-editing tools.
NFD test strings must use explicit `\u` escapes in source. For grapheme_slice result
comparison, use `.bytes ==` rather than string equality to avoid NFC/NFD mismatch.

### Cargo version note

`Cargo.toml` spec: `= "1.11"` (semver compatible minimum).
`Cargo.lock` resolved: `1.13.3` (latest 1.x at lock time).
Receipt records both.

---

## Explicit Answers

| Question | Answer |
|----------|--------|
| Receipt accepted as lab-only evidence? | YES |
| Handler-policy consistency proven? | YES — both bare and qualified split guarded |
| Can bare `split` bypass canonical policy? | NO — P3 closes the gap |
| New Text API introduced? | NO |
| Canon grammar changed? | NO |
| Public/stable/release claims closed? | YES |

---

## Design Doc

`igniter-lab/lab-docs/lang/lab-text-unicode-runtime-receipt-and-handler-hygiene-v0.md`

---

## Next Route

| Task | Notes |
|------|-------|
| `split("")` grapheme-split future | Decide behavior before runtime gate opens |
| Unicode conformance receipt for runtime gate | Extend schema when gate authorized |
| `length` legacy removal | Runtime gate required |
| Canon conformance receipt | After runtime gate — `unicode_version`, `grapheme_backend` |
