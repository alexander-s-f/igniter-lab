# lab-stdlib-regexp-p2-v0 — proof-local Rust regexp engine semantics

**Card:** `LAB-STDLIB-REGEXP-P2` · **Delegation:** `OPUS-STDLIB-REGEXP-B`
**Status:** CLOSED (implementation proof) — the P1 `stdlib.regexp` v0 semantics (`matches` + `capture`)
are locked by a proof-local Rust adapter over the `regex` crate, BEFORE any compiler/VM wiring. **No
canon stdlib surface, no `.ig` availability, no typechecker/VM/parser change, no `igniter-server`/
machine touch. `regex` is a DEV dependency only.**
**Authority:** Lab proof. Grounded in the live crate layout + the P1 readiness decision.

## What this card proves

The candidate v0 engine semantics, as Rust tests over the linear-time `regex` crate:

```text
matches(text, pattern)          -> bool
capture(text, pattern, index)   -> Option<String>     (substring; index 0 = whole match)
captures(text, pattern)         -> Vec<String>        (proven, but recommended DEFERRED — see below)
```

The adapter (`RegexEngine` trait + `RegexCrateEngine` impl + `RegexError`) lives entirely inside the
test file — nothing is reachable from `.ig` programs or the published library.

## Chosen location & dependency scope

- **Location:** `igniter-stdlib/tests/regexp_engine_proof_tests.rs` (a standalone crate; serde-only lib;
  no prior tests dir). The adapter is defined in the test, not in `src/` — zero public API added.
- **Dependency scope:** `regex = "1"` added under **`[dev-dependencies]`** in `igniter-stdlib/Cargo.toml`
  (resolved to `regex 1.12.4` from the local registry cache — offline-clean). **Verified dev-only:**
  `cargo tree -e normal | grep regex` → empty (regex is NOT in the normal dependency tree); the
  published `igniter_stdlib` library builds unchanged. Promotion to a real dependency happens only in
  P3, if the builtin is registered.

## Final proof API & semantics (locked)

| Fn | Semantics (proven) |
|---|---|
| `matches(text, pattern) -> bool` | true iff pattern matches anywhere; the author anchors with `^…$` — **never secretly anchored**. |
| `capture(text, pattern, index) -> Option<String>` | `index 0` = whole match; `index ≥ 1` = that group. Out-of-range / no match / optional-unmatched group → `None`. Returns the matched **substring** (no offsets). |
| `captures(text, pattern) -> Vec<String>` | groups only (`1..n`); unmatched optional group → `""`; no match → `[]`. **Recommended DEFERRED** (see below). |
| invalid pattern (any fn) | `Err(RegexError::InvalidPattern(_))` — **never `false`/`None`**. |

## Pass counts / commands

```text
$ cd igniter-stdlib && cargo test --test regexp_engine_proof_tests
  running 11 tests … test result: ok. 11 passed; 0 failed

$ cd igniter-stdlib && cargo test
  src/lib.rs unittests        0 passed; 0 failed
  regexp_engine_proof_tests  11 passed; 0 failed
  doctests                    0 passed; 0 failed

$ cargo tree -e normal | grep -i regex   →  (empty: regex is dev-only)
$ cargo build                            →  Finished (lib builds without regex)
```

(Adding the dev-dep extends `igniter-stdlib/Cargo.lock` with `regex 1.12.4` + `regex-automata 0.4.14`
+ `regex-syntax 0.8.11` + `aho-corasick 1.1.4` + `memchr` — all proof-only, behind `[dev-dependencies]`.)

## Route + validation pressure results (all green)

| Fixture | Result |
|---|---|
| `/todos/42` → id | `capture(…, "^/todos/([0-9]+)$", 1) == Some("42")` |
| `/todos/42/done` → id | `Some("42")` |
| `/accounts/7/todos/42` → account_id, todo_id | `index 1 == Some("7")`, `index 2 == Some("42")` — **middle-param capture that split+nth cannot do** |
| `/webhooks/callrail` → vendor | `Some("callrail")` |
| route mismatch | `matches == false`, `capture == None` — **no panic** |
| email-ish / UUID / phone-ish validation | `matches` true/false as expected |
| 5-digit extraction from a larger string | `capture("zip is 90210 today", "([0-9]{5})", 1) == Some("90210")` |

## Invalid-pattern behavior (proven)

- lookaround `foo(?=bar)` and backref `(a)\1` → `Err(InvalidPattern)` — Rust `regex` rejects them at
  compile time (a safety feature that keeps search linear-time), so they can never silently mismatch.
- invalid syntax `"("`, `"["`, `"a{2,1}"`, `"*"` → `Err(InvalidPattern)` for both `matches` and
  `capture`. Never `false`/`None`.

## Unicode note

- Captures return matched **substrings**, never byte/rune/grapheme offsets — the API exposes no offset
  at all, staying inside the LOCKED `Text = valid UTF-8` model.
- `capture("/todos/київ", "^/todos/(.+)$", 1) == Some("київ")`, `chars().count() == 4` (rune-correct,
  valid UTF-8). Unicode-mode `.` (the `regex` default) matches scalar values.

## `captures`: keep or drop?

**Recommend DEFERRING `captures` from the v0 `.ig` surface.** It is proven to work, but groups-only
`Vec<String>` cannot represent an optional-unmatched group (rendered `""`, indistinguishable from a
genuine empty match) — a real information loss. Positional `capture(_, _, index) -> Option<String>` is
unambiguous and covers every routing/validation need. So **v0 `.ig` ships `matches` + `capture` only**;
`captures` waits until there's a concrete need and better collection/Option ergonomics.

## Budget note

No heavy benchmark (not needed). Rust `regex` guarantees **linear-time** search (Thompson NFA, no
backtracking), so runtime is bounded by `O(pattern × text)`. An explicit pattern-length / haystack
budget is left as an optional **P3 knob** — P2 found no practical need.

## Relationship recap (unchanged from P1)

Regexp unblocks path-param extraction including nested/middle params (the decisive win over
`split`+`nth`), but `capture`'s `Option[String]` keeps the Option-ergonomics item (`LANG-SUMTYPE-
CONSTRUCT-MATCH`) alive — regexp must not hide it. The IgWeb route DSL uses regexp as the **lowered
substrate** (authors write `:id`; the lowering emits `matches`/`capture`), never the authoring surface.

## Next card

**`LAB-STDLIB-REGEXP-P3`** — register the proven `stdlib.regexp.{matches, capture}` as
`compiler_builtin` entries in the typechecker (T2/T3) + add VM native dispatch arms over `regex`
(promoting it to a real dependency of the VM/compiler runtime, narrowest crate); implement the
**literal-pattern compile diagnostic** (`OOF-RE1`, mirroring `regex_match`→`OOF-TY0`) and the
**dynamic-pattern runtime operational error** (VM `Result<_, String>`). Ship `matches` + `capture`
only; keep `captures` deferred. P3 is the first canon-adjacent step and carries a stricter gate.
(Then `LAB-IGNITER-WEB-ROUTING-LOWERING-P4` consumes it.)

## Closed surfaces (held)

No canon `LANG-*` claim · no `stdlib.regexp` `.ig` signature exposed to real programs · no typechecker
builtin registration · no VM dispatch arms · no parser/compiler semantic change · no web-routing/IgWeb
lowering · no `igniter-server` change · no production/live behavior · no backtracking engine.

---

*Implementation proof only. Compiled 2026-06-18; 11/11 proof tests green; `regex` dev-only (verified
via `cargo tree -e normal`).*
