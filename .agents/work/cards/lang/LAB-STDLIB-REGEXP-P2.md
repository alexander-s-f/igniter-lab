# Card: LAB-STDLIB-REGEXP-P2 — proof-local Rust regexp engine semantics

**Lane:** standard / implementation-proof
**Skill:** idd-agent-protocol
**Status:** CLOSED (implementation proof)
**Date opened:** 2026-06-18
**Date closed:** 2026-06-18
**Delegation label:** OPUS-STDLIB-REGEXP-B
**Authority:** Lab proof only. No canon stdlib surface. No compiler/typechecker/VM registration.

## Why this card exists

P1 chose the shape of `stdlib.regexp` before opening a canon-ish language surface:
`matches` + `capture` (and maybe `captures`) over Rust's linear-time `regex` engine,
with invalid literal patterns later becoming compile diagnostics and dynamic invalid
patterns becoming runtime operational errors.

Before wiring anything into `igniter-compiler`/`igniter-vm`, prove the actual engine
semantics in a tiny Rust proof. This is the last cheap place to discover API mistakes.

## Read first (verify-first, live code wins)

- `lab-docs/lang/lab-stdlib-regexp-p1-v0.md`
- `.agents/work/cards/lang/LAB-STDLIB-REGEXP-P1.md`
- `lab-docs/lang/lab-igniter-web-routing-dx-shape-p2-v0.md`
- `igniter-apps/web_router/PRESSURE_REGISTRY.md`
- `lab-docs/lang/lab-string-value-semantics-bounds-and-unicode-proof-v0.md`
- `lab-docs/lang/lab-text-unicode-semantics-authority-and-runtime-policy-design-v0.md`
- `igniter-stdlib/Cargo.toml`
- `igniter-stdlib/src/`
- `igniter-stdlib/stdlib/core/string.ig`
- current workspace manifests (`rg -n "regex|fancy-regex|pcre|onig" Cargo.toml **/Cargo.toml`)

## Goal

Implement a **proof-local** Rust regexp adapter over the `regex` crate and tests that
lock the candidate v0 semantics:

```text
matches(text, pattern) -> Bool
capture(text, pattern, index) -> Option[String]
captures(text, pattern) -> Collection[String]   (optional; prove or explicitly drop)
```

This card proves semantics only. It must not make regexp available to `.ig` programs.

## Allowed implementation shape

Pick the smallest clean proof route after verifying the crate layout.

Preferred shape:

- add `regex` as a **dev-dependency or proof-only dependency** in the narrowest crate
  that can host the proof, likely `igniter-stdlib`;
- add a proof-only Rust module/test helper, e.g. `tests/regexp_engine_proof_tests.rs`
  or `tests/support/regexp_engine.rs`;
- expose no public stdlib API unless the crate's test layout forces a tiny internal
  helper;
- keep the proof adapter pure Rust, independent of compiler/typechecker/VM.

If `igniter-stdlib` cannot host dev-dep tests cleanly, create the smallest lab proof
crate/tool and explain why. Do not contaminate `igniter-server`, `igniter-machine`, or
compiler crates.

## Candidate proof API

The proof adapter may be a tiny trait + implementation:

```rust
trait RegexEngine {
    fn matches(&self, text: &str, pattern: &str) -> Result<bool, RegexError>;
    fn capture(&self, text: &str, pattern: &str, index: usize) -> Result<Option<String>, RegexError>;
    fn captures(&self, text: &str, pattern: &str) -> Result<Vec<String>, RegexError>;
}
```

Recommended semantics:

- `matches`: true iff pattern matches anywhere unless pattern is anchored by author
  (`^...$`). Do not secretly anchor.
- `capture(index=0)`: whole match.
- `capture(index>=1)`: capture group at that position.
- out-of-range or unmatched optional group -> `Ok(None)`.
- invalid pattern -> `Err(RegexError::InvalidPattern{...})`, never `false`/`None`.
- `captures`: decide and document whether it returns capture groups only or includes
  group 0. Prefer: **groups only** (`1..n`) because `capture(...,0)` covers whole match.
  If a test proves another shape is better, explain it.

## Required proof cases

### Core behavior

- `matches("/todos/42", "^/todos/([0-9]+)$") == true`
- `matches("/todos/x", "^/todos/([0-9]+)$") == false`
- unanchored pattern behavior is explicit (`matches("abc123", "[0-9]+") == true`).
- `capture("/todos/42", "^/todos/([0-9]+)$", 0) == Some("/todos/42")`
- `capture(..., 1) == Some("42")`
- out-of-range capture -> `None`.
- optional unmatched capture -> `None`.

### IgWeb route pressure

Prove exact values for:

- `/todos/42` -> `id=42`
- `/todos/42/done` -> `id=42`
- `/accounts/7/todos/42` -> `account_id=7`, `todo_id=42`
- `/webhooks/callrail` -> `vendor=callrail`
- route mismatch returns `matches=false`, not a capture panic.

### Validation/extraction pressure

- email-ish validation from P1 packet.
- UUID-ish validation.
- phone-ish validation.
- extract a 5-digit token from a larger string.

### Unicode / text policy

- return matched **substrings**, not offsets.
- prove a non-ASCII capture remains valid UTF-8 (e.g. `"/todos/київ"` with a Unicode-safe pattern).
- document that no byte/rune/grapheme offsets are exposed.

### Safety / rejected engine features

- lookaround/backrefs are unsupported by Rust `regex` and produce `InvalidPattern`.
- invalid syntax (`"("`, bad character class, etc.) returns `Err`, not false/None.
- no filesystem/network/global state; pure function tests should be deterministic.

### Budget note

Do not perform a heavy benchmark unless trivial. Add a proof note explaining that
Rust `regex` provides linear-time search, and leave explicit pattern-length/haystack
budget as a P3 knob unless P2 discovers a practical need.

## Required docs

Write:

`lab-docs/lang/lab-stdlib-regexp-p2-v0.md`

Include:

- chosen implementation location and why;
- exact dependency scope (`dev-dependency`, proof crate, etc.);
- final proof API and semantics;
- pass counts / commands;
- route + validation pressure results;
- invalid pattern behavior;
- Unicode note;
- whether `captures` stays in v0 or should be dropped/deferred;
- next P3 card wording.

Then close this card with a compact report.

## Commands / verification

Run the narrow tests and any relevant crate tests. Suggested, adjust after verifying layout:

```bash
cd igniter-stdlib && cargo test
# or the exact proof crate command if a separate proof crate is used
```

If adding a dev-dependency changes lockfiles, include that in the report and explain
why it is proof-only. If there is a workspace lockfile, update intentionally.

## Acceptance

- [ ] `regex` engine semantics are proven by Rust tests.
- [ ] Dependency is proof-local / dev-scope / narrowest possible.
- [ ] No compiler/typechecker/parser/VM registration.
- [ ] No `.ig` stdlib availability yet.
- [ ] `matches` and `capture` semantics are locked.
- [ ] `captures` is either proven and kept or explicitly deferred with rationale.
- [ ] Invalid patterns return structured error, never false/None.
- [ ] Lookaround/backrefs are rejected by the chosen engine and tested.
- [ ] Route, nested-route, webhook, validation, and Unicode pressure fixtures pass.
- [ ] Documentation records exact commands/pass counts.
- [ ] Next P3 card is named and bounded.

## Closed surfaces

- No canon `LANG-*` claim.
- No `stdlib.regexp` `.ig` signatures exposed to real programs unless only in a
  proof-only fixture.
- No typechecker builtin registration.
- No VM dispatch arms.
- No parser/compiler semantic change.
- No web routing implementation.
- No IgWeb lowering implementation.
- No `igniter-server` changes.
- No production/live behavior.
- No backtracking regex engine.

## Suggested next card after success

`LAB-STDLIB-REGEXP-P3` — register proven regexp primitives as `compiler_builtin`
entries and VM native dispatch, add literal-pattern diagnostics (`OOF-RE1`) and
dynamic-pattern operational errors. P3 is the first canon-adjacent implementation
and must carry a stricter gate.

---

## Closing report — 2026-06-18

**Outcome:** P1's `stdlib.regexp` v0 semantics proven by a proof-local Rust adapter over the `regex`
crate — `matches` + `capture` locked, `captures` proven-but-deferred. No `.ig` surface, no compiler/VM
wiring, no canon claim. `regex` is dev-only.

**Deliverable:** `lab-docs/lang/lab-stdlib-regexp-p2-v0.md`.

**Location / dep scope:** `igniter-stdlib/tests/regexp_engine_proof_tests.rs` (adapter defined in the
test — zero public API). `regex = "1"` under `[dev-dependencies]` (resolved 1.12.4 from cache, offline).
**Verified dev-only:** `cargo tree -e normal | grep regex` → empty; the published lib builds unchanged.

**Locked semantics:** `matches` (anchors only if author writes `^…$`, never secretly); `capture(index)`
→ `Option<String>` substring (0=whole, ≥1=group, out-of-range/no-match/optional-unmatched → None,
never offsets); invalid pattern → `Err(InvalidPattern)` (never false/None). `captures` (groups-only
`Vec<String>`) **recommended DEFERRED** — can't represent an optional-unmatched group (renders `""`,
ambiguous); positional `capture` is unambiguous and covers routing.

**Commands / counts:**
```text
cd igniter-stdlib && cargo test --test regexp_engine_proof_tests → 11 passed; 0 failed
cd igniter-stdlib && cargo test                                  → 11 passed; 0 failed (+0 lib +0 doc)
cargo tree -e normal | grep regex → empty (dev-only) ; cargo build → Finished
```

**Pressure (all green):** route id `/todos/42`→42; `/todos/42/done`→42; **nested middle-param**
`/accounts/7/todos/42`→(7,42) — the decisive win split+nth can't do; webhook `callrail`; mismatch→
false/None no panic; email/UUID/phone validation; 5-digit extraction; Unicode `/todos/київ`→"київ"
(rune-correct, substring not offset). Safety: lookaround/backref + invalid syntax → InvalidPattern.

**Next:** `LAB-STDLIB-REGEXP-P3` (typechecker `compiler_builtin` + VM dispatch + literal `OOF-RE1`
diagnostic + dynamic operational error; ship `matches`+`capture`, keep `captures` deferred) → then
`LAB-IGNITER-WEB-ROUTING-LOWERING-P4`. **Canon = NOT YET, gated by P3.**

**Acceptance:** all boxes met — engine semantics proven by Rust tests; dep proof-local/dev-scope; no
compiler/typechecker/parser/VM registration; no `.ig` availability; `matches`/`capture` locked;
`captures` deferred with rationale; invalid patterns structured-error; lookaround/backrefs rejected +
tested; route/nested/webhook/validation/Unicode fixtures pass; commands+counts recorded; P3 named+bounded.
