# Lab: Text Unicode Semantics — Authority and Runtime Policy Design v0

**Track:** lab-text-unicode-semantics-authority-and-runtime-policy-design-v0
**Card:** LAB-STR-UNICODE-P1
**Opened:** 2026-06-08
**Status:** ✅ DESIGN-LOCKED — policy decisions closed; implementation deferred to runtime gate
**Depends on:** LAB-STR-CORE-P3, LAB-STR-CORE-P2, igniter-string-core-units-and-pure-stdlib-boundary-v0
**Route:** EXPERIMENTAL / LAB-ONLY / DESIGN

---

## Purpose

Design-lock the Unicode authority and runtime policy boundary for Igniter Text.
No runtime implementation is done here. No new stdlib ops are added. No canon
grammar changes. No stable API authority claimed.

This document answers the open questions from LAB-STR-CORE-P3 explicitly, so
that the runtime gate can be opened with a clear implementation contract.

---

## Explicit Answers

| Question | Answer | Section |
|----------|--------|---------|
| Does Text require valid UTF-8? | YES — at all runtime boundaries | §1 |
| Are byte/rune/grapheme units authoritative? | YES — all three, distinct | §2 |
| Is UAX #29 the grapheme authority? | YES — Extended Grapheme Clusters | §3 |
| Should Unicode version be pinned? | YES — via Cargo.lock + receipt field | §4 |
| Text equality: normalize or exact codepoint? | Exact codepoint sequence — no implicit normalization | §5 |
| byte_slice on invalid UTF-8 boundary? | Return `""` (fail-closed, empty Text) | §6 |
| split("") empty delimiter? | Undefined for v0 — operational error; no compile-time check | §7 |
| replace("") / replace_all("")? | Undefined for v0 — operational error; same as split("") | §8 |
| Is `unicode-segmentation` acceptable for lab? | YES — for lab runtime proof only | §9 |
| Should canon require Unicode conformance receipt? | YES — design intent for future gate | §10 |
| What is the exact next route? | See §11 | §11 |

---

## §1 — UTF-8 Validity Requirement

**Design lock:** Text values at all runtime boundaries MUST be valid UTF-8.

**Basis:** The VM already enforces this structurally. `Value::String(Arc<str>)` uses
Rust's `str` type, which is guaranteed to contain valid UTF-8 by the Rust type system.
Any non-UTF-8 byte sequence cannot enter the VM as a `Text` value.

**Policy consequences:**

| Boundary | Rule |
|----------|------|
| Contract input port (`input name: Text`) | Caller must supply valid UTF-8; invalid input is a runtime error |
| Contract output port (`output name: Text`) | Guaranteed valid UTF-8 by invariant |
| String literals in source | Parser produces valid UTF-8 string literals only (Rust source parser) |
| `byte_slice` result | Must be valid UTF-8 or `""` (see §6) |

**Not a design decision** — this falls out of the implementation model. The policy
is to make it explicit and treat violation as a runtime contract breach.

---

## §2 — Unit Family Authority

Three unit families are canonical. Each is a distinct conceptual level.
No single universal "length" exists in v0.

| Family | Atom | Rust implementation | Notes |
|--------|------|---------------------|-------|
| Byte | UTF-8 octet | `s.len()` | Fastest; not human-meaningful for multi-byte chars |
| Rune | Unicode scalar value | `s.chars().count()` | Code points U+0000..U+D7FF, U+E000..U+10FFFF; no surrogates |
| Grapheme | Extended grapheme cluster | `s.graphemes(true).count()` via `unicode-segmentation` | User-perceived characters; UAX #29 |

**Invariant for valid UTF-8 text:**
`byte_length(t) >= rune_length(t) >= grapheme_length(t)` — always.

**Canonical example (design-locked, runtime-gated for verification):**

| Text | byte_length | rune_length | grapheme_length |
|------|-------------|-------------|-----------------|
| `"hello"` | 5 | 5 | 5 |
| `"é"` U+00E9 (precomposed) | 2 | 1 | 1 |
| `"é"` U+0065+U+0301 (decomposed) | 3 | 2 | 1 |
| `"\u{1F1FA}\u{1F1F8}"` (🇺🇸 flag, regional indicator sequence) | 8 | 2 | 1 |
| `"👨‍👩‍👧"` (family, ZWJ sequence) | 25 | 8 | 1 |
| `""` (empty) | 0 | 0 | 0 |

---

## §3 — Grapheme Cluster Authority (UAX #29)

**Design lock:** Grapheme clusters are defined by Unicode Standard Annex #29
(Unicode Text Segmentation), §3.1 "Default Grapheme Cluster Boundaries" —
Extended Grapheme Cluster algorithm.

This is the `extended: true` mode in the `unicode-segmentation` Rust crate
(`graphemes(true)`). It handles:
- Base + combining mark sequences
- Regional indicator pairs (flags)
- Zero-width joiner (ZWJ) sequences (emoji families, professions)
- Hangul syllable sequences
- Indic syllable clusters

**Not in scope for v0 grapheme authority:**
- Tailored grapheme clusters (locale-specific segmentation)
- CLDR grapheme break rules
- Application-level grapheme customization

**Conformance target:** A runtime implementation is conformant if it produces the
same grapheme cluster count and boundaries as UAX #29 Extended Grapheme Cluster
algorithm for the pinned Unicode version (§4).

---

## §4 — Unicode Version Pinning Policy

**Design lock:** The Unicode version used for grapheme segmentation MUST be pinned.

**Rationale:** Unicode table updates add new extended grapheme cluster rules (e.g.,
new emoji ZWJ sequences, new regional indicator pairs). Without pinning:
- The same source text compiled at different times on different machines may produce
  different `grapheme_length` values.
- This violates the pure determinism contract for a `pure contract`.

**v0 pinning mechanism:** Pin via Cargo.lock on the `unicode-segmentation` crate version,
which encodes a specific Unicode version in its tables.

**Receipt design (future gate):** When the runtime gate opens, contracts that use
grapheme ops should emit a receipt field:

```json
{
  "unicode_policy": {
    "grapheme_backend": "unicode-segmentation",
    "crate_version": "1.11.0",
    "unicode_version": "15.1.0",
    "algorithm": "uax29-extended"
  }
}
```

This is not a v0 requirement (runtime gate closed), but it is the required design
for canon conformance certification.

**Version update policy:** Upgrading the Unicode version is a breaking change for
`grapheme_*` ops if it alters cluster boundaries for existing text. Requires a
versioned gate decision, not a silent dependency bump.

---

## §5 — Text Equality and Normalization

**Design lock:** Text equality is exact codepoint sequence comparison. No implicit
Unicode normalization is applied anywhere in v0.

**Consequences:**

| Case | v0 result |
|------|-----------|
| `"é"` (U+00E9) == `"é"` (U+0065+U+0301) | **false** — different codepoint sequences |
| `contains("café", "é")` where both use U+00E9 | **true** |
| `contains("café", "é")` where text uses U+00E9 and needle uses U+0065+U+0301 | **false** |
| `split("café", "é")` with mismatched normalization | Splits on exact byte pattern only |

**Rationale:** A `pure contract` must be deterministic. Implicit normalization introduces
a hidden processing step whose behavior depends on Unicode version and normalization form.
Two texts that are canonically equivalent (NFC/NFD) but byte-different are different
`Text` values in v0.

**This is intentional and must be documented in canon.** If callers need normalization-
insensitive comparison, they must normalize explicitly. Normalization ops (`nfc`, `nfd`,
`nfkc`, `nfkd`) are deferred surface items — not part of v0.

**Implementation:** Rust's `==` on `str` is byte-level equality, which equals exact
codepoint sequence equality for valid UTF-8. No extra code required.

---

## §6 — Slice Bounds Policy

All three slice families use half-open range `[start, end)`.

### byte_slice: invalid UTF-8 boundary

**Design lock:** If `start` or `end` falls at a byte offset that is not on a
codepoint boundary (i.e., inside a multi-byte UTF-8 sequence), `byte_slice` returns `""`.

**Rationale:** Returning partial multi-byte sequences would produce invalid UTF-8, which
violates §1. Panicking violates pure determinism. Returning `""` is safe, deterministic,
and fail-closed.

**Implementation note:** Rust's `s.get(start..end)` returns `None` when the range
does not align to char boundaries. Map `None → ""`.

### All slice families: out-of-bounds indices

| Condition | Policy | Result |
|-----------|--------|--------|
| `start < 0` | Clamp to 0 | Same as `slice(t, 0, end)` |
| `end < 0` | Clamp to 0 | Same as `slice(t, start, 0)` |
| `start > length` | Clamp to length | `""` (empty) |
| `end > length` | Clamp to length | Slice to end of text |
| `start > end` (after clamping) | Return `""` | Empty range |
| `start == end` | Return `""` | Degenerate range |
| Empty text `""` with any indices | Return `""` | Trivially empty |

**Rationale:** Fail-closed clamping is the safest choice for a pure contract language.
It avoids runtime errors and produces deterministic results. The tradeoff is that callers
may receive `""` silently on bad index input. This is acceptable for v0 — the type system
cannot enforce index validity at compile time.

**Implementation note for byte_slice:** Apply clamping first (to `[0, s.len()]`), then
check UTF-8 boundary alignment, then return `""` if misaligned or empty if `start >= end`.

---

## §7 — split Empty Delimiter Policy

**Design lock for v0:** `split(t, "")` where the delimiter is the empty string is an
**operational error**. Callers must not pass an empty delimiter. No compile-time check
is possible (the compiler cannot inspect runtime `Text` values).

**Rationale:** Rust's `str::split("")` produces surprising interstitial-boundary behavior
(`"hello".split("") → ["", "h", "e", "l", "l", "o", ""]`). This behavior:
- Is not useful for most Igniter use cases
- Does not correspond to grapheme-level splitting
- Is confusing and implementation-specific

**v0 behavior:** Undefined. The runtime may produce Rust's default behavior
(interstitial split) or may return `[""]` (single-element). Neither is authoritative.

**Future gate option:** When runtime semantics gate opens, one of three policies:
1. **Error / OOF at runtime** — empty delimiter is a contract violation, emit runtime error
2. **Grapheme-split** — `split(t, "")` = `split into individual grapheme clusters` → preferred semantic
3. **Rune-split** — split into individual Unicode scalar values

**Design preference for future:** option 2 (grapheme-split) is the most user-useful
interpretation. `split(t, "")` could become sugar for grapheme cluster enumeration.
This is a separate gate decision.

---

## §8 — replace / replace_all Empty Pattern Policy

**Design lock for v0:** `replace(t, "", r)` and `replace_all(t, "", r)` where the
pattern is the empty string are **operational errors**. Callers must not pass an
empty pattern.

**Rationale:** Rust's `str::replace("", "x")` inserts `x` between every codepoint:
`"hello".replace("", "x")` → `"xhxexlxlxox"`. This is not useful and not semantically
clean for a pure contract language.

**v0 behavior:** Undefined. Runtime may produce Rust's interstitial-insertion behavior.

**Future gate:** Declare `replace(t, "", r)` as `OOF-TY0` at call sites where the
empty literal `""` is statically detectable. Dynamic empty patterns remain runtime-undefined
until a policy is locked.

---

## §9 — Runtime Implementation Options

### Current state (as of 2026-06-08)

VM Cargo.toml has NO Unicode library dependency. Partial stdlib.text.* ops in VM:
- `concat` — Rust string formatting (✓)
- `trim` — Rust `str::trim()` (Unicode White_Space — see note below)
- `split` / `stdlib.text.split` — Rust `str::split()` (byte-level literal pattern — ✓)
- `contains` / `starts_with` — Rust `str::contains()` / `starts_with()` (✓)
- `stdlib.text.byte_length` — Rust `s.len()` (✓)

**Missing:** `rune_length`, `grapheme_length`, `rune_slice`, `grapheme_slice`,
`byte_slice`, `ends_with`, `replace`, `replace_all`.

### trim Unicode whitespace note

Rust's `str::trim()` removes characters with the `Pattern_White_Space` Unicode property.
This includes U+0009 (tab), U+000A (newline), U+000D (CR), U+0020 (space),
U+00A0 (no-break space), U+2028 (line separator), U+2029 (paragraph separator),
and others.

**Design lock:** Igniter `trim` follows Unicode `Pattern_White_Space` — not ASCII
whitespace only. This is the Rust `str::trim()` behavior and is the declared v0 policy.

### Option matrix

| Option | Rune ops | Grapheme ops | Slice ops | Extra dep | Acceptable for lab |
|--------|----------|--------------|-----------|-----------|-------------------|
| **Rust std only** | `str::chars()` ✓ | ✗ no | byte_slice via `s.get()` | None | Partial — no grapheme |
| **+ `unicode-segmentation`** | `str::chars()` ✓ | UAX #29 ✓ | grapheme boundaries ✓ | ~200KB | **YES** ✓ |
| **+ `icu4x`** | ✓ | UAX #29 ✓ | ✓ | ~1–5MB | Overkill for v0 |
| **Custom minimal** | Custom | Partial UAX #29 | Custom | None | Not recommended |
| **Hold/defer** | — | — | — | None | ✓ (current state) |

### Recommendation for lab runtime proof

**Add `unicode-segmentation` to `igniter-vm/Cargo.toml`.**

```toml
unicode-segmentation = "1.11"
```

This gives:
- `grapheme_length(t)` → `t.graphemes(true).count()`
- `grapheme_slice(t, s, e)` → `t.graphemes(true).skip(s).take(e-s).collect::<String>()`
- `rune_length(t)` → `t.chars().count()` (Rust std, no dep needed)
- `rune_slice(t, s, e)` → `t.chars().skip(s).take(e-s).collect::<String>()`
- `byte_length(t)` → `t.len()` (already implemented)
- `byte_slice(t, s, e)` → `t.get(s..e).unwrap_or("")` with clamping

**This dependency addition requires a separate authorization card** before it is
made to vm.rs. This document is design only — no Cargo.toml modifications here.

---

## §10 — Canon Conformance Receipt (Future Gate Design)

When the runtime gate opens, grapheme-using contracts should produce a conformance
receipt field. This is the mechanism by which canon can certify that two runtimes
are equivalent for `grapheme_*` ops.

**Proposed receipt shape (not yet active):**

```json
{
  "contract_name": "MyContract",
  "unicode_policy": {
    "grapheme_backend": "unicode-segmentation",
    "crate_version": "1.11.0",
    "unicode_version": "15.1.0",
    "algorithm": "uax29-extended",
    "normalization": "none"
  }
}
```

**Design intent:** A contract that uses only `byte_*` ops does not need a Unicode receipt
(byte ops are pure UTF-8 octet counting — no Unicode table). A contract that uses
`rune_*` ops needs to declare the Unicode version for codepoint validity. A contract
that uses `grapheme_*` ops needs the full grapheme_backend declaration.

**Canon conformance ladder (design intent for future):**

| Op family | Receipt required | Portability requirement |
|-----------|-----------------|------------------------|
| `byte_*` | None | Same for all valid UTF-8 runtimes |
| `rune_*` | Unicode version | Same for any conformant UTF-8 decoder |
| `grapheme_*` | Unicode version + grapheme_backend | Same for runtimes with same Unicode tables |

This ladder is a future design constraint on the runtime gate, not a v0 requirement.

---

## §11 — Next Route

### Immediate (design-locked, awaiting authorization)

| Task | Card | Notes |
|------|------|-------|
| Add `unicode-segmentation` to VM | New card | Requires explicit authorization before modifying Cargo.toml |
| Implement missing VM text ops | New card | After dep authorized: rune_length, grapheme_length, byte_slice, rune_slice, grapheme_slice, ends_with, replace, replace_all |
| `trim` Unicode whitespace policy documentation | Into canon track doc | Confirm Pattern_White_Space is the declared policy |

### Deferred (runtime gate must open first)

| Task | Notes |
|------|-------|
| Runtime bounds enforcement (clamp/empty) | Needs runtime execution gate |
| `split("")` grapheme-split behavior | Design decision needed before runtime gate |
| `replace("")` / `replace_all("")` policy | Design decision needed before runtime gate |
| Unicode conformance receipt in SemanticIR | After runtime gate + receipt schema gate |
| Normalization ops (`nfc`, `nfd`, etc.) | Separate surface gate; not v0 |

### Explicitly closed

- Regex surface
- Locale-sensitive case folding
- Tokenizer
- TextEngine / streaming text
- `stdlib.text.length` as canonical op (replaced by explicit unit ops)
- Source-level method syntax
- Namespace syntax (`Text.concat(...)`)

---

## Summary Matrix

| Policy | Decision | Status |
|--------|----------|--------|
| Text runtime representation | Valid UTF-8 only (`Value::String(Arc<str>)`) | ✅ LOCKED |
| byte unit | UTF-8 octet, `s.len()` | ✅ LOCKED |
| rune unit | Unicode scalar value, `s.chars()` | ✅ LOCKED |
| grapheme unit | Extended grapheme cluster, UAX #29 | ✅ LOCKED |
| grapheme authority | Unicode Standard Annex #29 (UAX #29) | ✅ LOCKED |
| Unicode version pinning | YES — via Cargo.lock; receipt on runtime gate | ✅ LOCKED |
| Text equality | Exact codepoint sequence — no normalization | ✅ LOCKED |
| Normalization | None implicit in v0 | ✅ LOCKED |
| trim whitespace | Unicode Pattern_White_Space (Rust `str::trim`) | ✅ LOCKED |
| slice range model | `[start, end)` half-open | ✅ LOCKED |
| byte_slice invalid boundary | Return `""` (fail-closed) | ✅ LOCKED |
| slice out-of-bounds | Clamp, then empty if start ≥ end | ✅ LOCKED |
| split("") | Undefined v0 — operational error | ✅ LOCKED |
| replace("") | Undefined v0 — operational error | ✅ LOCKED |
| pattern matching | Literal byte-level, no regex | ✅ LOCKED |
| grapheme library | `unicode-segmentation` for lab — requires auth to add | ✅ LOCKED |
| Canon Unicode receipt | Future gate — receipt names Unicode version + backend | ✅ DESIGN INTENT |
