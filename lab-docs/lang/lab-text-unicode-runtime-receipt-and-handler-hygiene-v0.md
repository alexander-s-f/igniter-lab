# Lab Text Unicode Runtime Receipt and Handler Hygiene (v0)

**Card:** LAB-STR-UNICODE-P3  
**Status:** ✅ CLOSED — 2026-06-08  
**Proof:** `verify_unicode_text_runtime.rb` — 41/41 PASS  
**Depends on:**
- LAB-STR-UNICODE-P2 (Unicode VM runtime ops — closed 2026-06-08)
- LAB-STR-UNICODE-P1 (Unicode authority / policy design-lock — closed 2026-06-08)

---

## Scope

Two goals:

1. **Handler hygiene**: Align the bare `"split"` VM handler with the same
   empty-delimiter fail-closed policy that `"stdlib.text.split"` enforces.
   Prevents policy bypass via the legacy handler name.

2. **Runtime receipt**: Emit a machine-readable `unicode_runtime_receipt.json`
   recording the Unicode policy surface for review: dependency, grapheme
   backend, unit policy ids, slice policy, empty-input policy, normalization
   policy, and handler consistency status.

**Closed:** canon grammar, igniter-org, real TCP/socket, normalization ops,
`length` as canonical op, regex, locale folding, tokenizer, production/release/
stable-API gates.

---

## Changes

### `igniter-vm/src/vm.rs` — bare `"split"` handler guard

Added empty-delimiter guard to the bare `"split"` handler (P3 hygiene):

```rust
"split" => {
    ...
    // LAB-STR-UNICODE-P3: align bare handler with stdlib.text.split policy
    // empty delimiter is an operational error (v0 policy); no bypass via legacy name
    if sep.is_empty() {
        return Err("split: empty delimiter is an operational error (v0 policy)".to_string());
    }
    ...
}
```

**Before P3:** bare `"split"` would fall through to Rust's `str::split("")`
(which in Rust splits between every char, producing `n+1` empty strings around
every character — undefined/misleading behavior, not the v0 policy intent).

**After P3:** bare `"split"` and `"stdlib.text.split"` are both fail-closed.
No handler path can bypass the empty-delimiter operational error.

### `igniter-compiler/out/unicode_runtime_receipt.json` — receipt

Emitted by the proof runner on each run. Content:

```json
{
  "receipt_kind": "unicode_runtime_policy",
  "track_id": "lab-text-unicode-runtime-receipt-and-handler-hygiene-v0",
  "runtime_surface_id": "igniter-vm/stdlib.text.*",
  "card": "LAB-STR-UNICODE-P3",
  "status": "lab-only-evidence",
  "unicode_dep": {
    "crate": "unicode-segmentation",
    "cargo_toml_spec": "1.11",
    "cargo_lock_resolved": "1.13.3",
    "grapheme_algorithm": "uax29-extended-grapheme-cluster"
  },
  "unit_policies": {
    "byte":     { "id": "byte-utf8-octet",     "impl": "s.len()" },
    "rune":     { "id": "rune-unicode-scalar",  "impl": "s.chars().count()" },
    "grapheme": { "id": "grapheme-uax29-egc",   "impl": "s.graphemes(true).count()" }
  },
  "slice_policy": {
    "kind": "half-open", "notation": "[start, end)",
    "bounds": "clamp-negatives-to-0-over-end-to-length",
    "byte_invalid_boundary": "return-empty-string"
  },
  "empty_input_policy": {
    "split_empty_delimiter": "runtime-operational-error-v0",
    "replace_empty_pattern": "runtime-operational-error-v0",
    "applies_to_bare_handler": true
  },
  "normalization_policy": {
    "implicit_normalization": "none",
    "equality_basis": "exact-codepoint-sequence"
  },
  "handler_consistency": {
    "bare_split_guarded":          true,
    "qualified_split_guarded":     true,
    "replace_pattern_guarded":     true,
    "replace_all_pattern_guarded": true
  }
}
```

Receipt status is `"lab-only-evidence"` — no stable/public/production claim.

---

## Proof Results (41/41 PASS)

### UNI-DEP (3) — dependency presence
- Cargo.toml dep present
- Cargo.lock resolved: `unicode-segmentation = 1.13.3`
- UnicodeSegmentation import in vm.rs

### UNI-RCP (5) — receipt shape and content
| Check | Description |
|-------|-------------|
| UNI-RCP-01 | Receipt written to `out/unicode_runtime_receipt.json` |
| UNI-RCP-02 | Receipt is valid JSON |
| UNI-RCP-03 | All required top-level fields present |
| UNI-RCP-04 | `cargo_lock_resolved` matches Cargo.lock (1.13.3) |
| UNI-RCP-05 | `status = "lab-only-evidence"` — no authority overclaim |

### UNI-HYG (4) — handler policy consistency
| Check | Description |
|-------|-------------|
| UNI-HYG-01 | Bare `"split"` handler contains empty-delimiter guard (P3 hygiene) |
| UNI-HYG-02 | Qualified `"stdlib.text.split"` has empty-delimiter guard |
| UNI-HYG-03 | `replace` and `replace_all` have empty-pattern guard |
| UNI-HYG-04 | `"stdlib.text.length"` not present — legacy `length` not re-canonicalized |

### UNI-ERR (3) — operational error enforcement
| Check | Description |
|-------|-------------|
| UNI-ERR-01 | `split(s, "")` → runtime operational error |
| UNI-ERR-02 | `replace(s, "", "X")` → runtime operational error |
| UNI-ERR-03 | `replace_all(s, "", "X")` → runtime operational error |

### UNI-LENGTH (6) — P2 value regression
- `byte_length("café")` = 5 (UTF-8 bytes)
- `rune_length("café")` = 4 (Unicode scalar values)
- `grapheme_length("café")` = 4 (UAX#29 grapheme clusters)
- `rune_length("éx")` = 3 (3 codepoints)
- `grapheme_length("éx")` = 2 (2 grapheme clusters)
- No normalization: NFC `é` = 2 bytes, NFD `é` = 3 bytes (distinct)

### UNI-SLICE (6) — P2 slice regression
- `byte_slice("hello", 1, 4)` = `"ell"`
- `byte_slice("café", 3, 4)` = `""` (mid-codepoint, fail-closed)
- `byte_slice("hello", -5, 100)` = `"hello"` (clamp)
- `rune_slice("café", 0, 3)` = `"caf"`
- `grapheme_slice("éx", 0, 1)` = `e+U+0301` (first cluster, NFD preserved)
- `grapheme_slice("éx", 1, 2)` = `"x"`

### UNI-REPLACE (2), UNI-SPLIT (2) — P2 value regression

`replace` = first-match only; `replace_all` = all occurrences; both error on empty pattern.
`split` normal case and empty-delimiter error both confirmed.

### UNI-ALIAS (4) — alias correctness

`ends_with`, `trim`, `contains` all return correct values.
`"stdlib.text.concat"` qualified alias present in vm.rs.

### UNI-AUTH (4) — authority surface closed

Receipt status, keys, and vm.rs all free of canon/stable/public/production
authority markers. No igc-run or RuntimeSmoke in vm.rs.

### UNI-PATH (2) — receipt portability

No `file://` URIs or absolute filesystem paths in receipt.

---

## Implementation Notes

### Unicode escape encoding in test strings

Ruby string literals in proof runners are susceptible to Unicode normalization
when written by file-editing tools. NFD test strings (e.g. `e + U+0301 + x`)
must be constructed with explicit `\u` escape sequences in the Ruby source
(e.g. `"éx"`) to guarantee they remain NFD at parse time.

For the grapheme_slice result comparison, the VM returns the NFD form via JSON
`́` escape. Ruby's JSON.parse produces the NFD string. Compare using
`.bytes ==` against an explicitly constructed NFD string rather than a raw
string literal, to avoid NFC/NFD mismatch from file encoding.

### Cargo.lock vs Cargo.toml spec version

`Cargo.toml` specifies `unicode-segmentation = "1.11"` (minimum compatible).
`Cargo.lock` resolved to `1.13.3` (latest 1.x at time of lock).
The receipt captures both for traceability. The runtime uses 1.13.3.

### bare `split` prior behavior (pre-P3)

In Rust, `"hello".split("")` produces `["", "h", "e", "l", "l", "o", ""]` —
splitting between every character, yielding empty strings around boundaries.
This is not the v0 policy intent (operational error) and would be a silent
policy bypass. The P3 guard closes this.

---

## Explicit Answers (per card specification)

| Question | Answer |
|----------|--------|
| Unicode runtime receipt accepted as lab-only evidence? | YES — `status: "lab-only-evidence"` |
| Handler-policy consistency proven? | YES — bare and qualified `split` both guarded |
| Can bare `split` bypass canonical `stdlib.text.split` policy? | NO — P3 guard closes the bypass |
| New Text API introduced? | NO |
| Canon grammar/typechecker/SemanticIR changed? | NO |
| Public/stable/runtime/release claims remain closed? | YES — confirmed in UNI-AUTH |

---

## Next Route

| Task | Notes |
|------|-------|
| `split("")` grapheme-split future | Decide behavior before runtime gate opens |
| Unicode conformance receipt for runtime gate | Extend receipt schema when runtime gate authorized |
| `length` legacy removal | Runtime gate required; bare `length` still present as legacy |
| Canon conformance receipt schema | After runtime gate — `unicode_version`, `grapheme_backend` fields |
