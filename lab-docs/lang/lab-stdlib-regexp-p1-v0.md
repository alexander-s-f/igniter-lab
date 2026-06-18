# lab-stdlib-regexp-p1-v0 — regexp stdlib pressure / readiness

**Card:** `LAB-STDLIB-REGEXP-P1` · **Delegation:** `OPUS-STDLIB-REGEXP-A`
**Status:** RESEARCH / READINESS (v0, recommended) — what `stdlib.regexp` v0 should mean before any
canon-ish `LANG-STDLIB-REGEXP-*` implementation. **Design only. No code, no dependency change, no
compiler/parser/VM/stdlib edit, no canon `LANG-*` claim.**
**Authority:** Lab evidence. Grounded in the live string/Unicode policy docs, the stdlib builtin seam
(typechecker + VM), and the IgWeb routing pressure (P1/P2).

---

## Result (the clean call)

```text
LAB-STDLIB-REGEXP-P1 result:
  recommended v0 API = matches(text,pattern)->Bool ; capture(text,pattern,index)->Option[String]
                       (+ captures(...)->Collection[String] as an optional secondary; named/split DEFERRED)
  delegated engine   = Rust `regex` crate (linear-time, Unicode-by-default, NO lookaround/backrefs)
                       behind a host-adapter trait seam (richer engines stay rejected/deferred)
  safety policy      = linear-time by construction (no catastrophic backtracking); pure/deterministic;
                       no fs/net/locale/global state; return SUBSTRINGS not byte offsets; budgets optional
  error policy       = literal invalid pattern → compile-time structured diagnostic (P3, new OOF-RE*);
                       dynamic invalid pattern → runtime operational error (existing VM Result<_,String>)
  next card          = P2 proof-local Rust adapter over `regex` (no compiler wiring, dep only in proof)
  canon promotion    = NOT YET — gated by P2 proof then P3 typechecker+VM registration
```

Regexp **is** the right first move *for routing param extraction* — but it must be the lowered
**substrate** for an IgWeb route DSL, never the app author's surface, and it must not be used to hide
the separate `Option`/collection ergonomics gap (WR-P04).

---

## 1. Current policy baseline (Q1)

The string-value-semantics proof is explicit (`lab-string-value-semantics-bounds-and-unicode-proof-v0.md`):
- "**No regex:** Pattern strings are matched literally … There is no `Regex` type in v0 — any `Text`
  value accepted as a pattern arg is treated as a literal" (l.114-117); "enforced by policy, not by the
  type system" (l.115).
- `regex_match` / `regex_find` / `regex_replace` → "**Regex deferred**" (l.159); `regex_match` resolves
  to the closed-surface diagnostic `OOF-TY0` (STR-VALUE-CLOSED, l.180).
- Standing directive: "**Do not open regex, locale, tokenizer without a separate gate decision**"
  (l.207). The Unicode policy is DESIGN-LOCKED: Text = valid UTF-8 (`Value::String(Arc<str>)`); units
  byte / rune (scalar) / grapheme (UAX #29) are LOCKED.

**Why open it now (not feature growth):** this card *is* the required separate gate decision, triggered
by concrete new pressure — IgWeb routing (`WR-P04`: no path-param parser; `split` doesn't infer
`Collection[String]`; nested/middle params not expressible). The center of gravity is "a deterministic,
host-delegated text-pattern capability narrow enough to be safe", not "web routing wants regex".

## 2. Host delegation model (Q2)

The stdlib builtin seam **already exists** and is exactly where regexp slots:
- a stdlib `def` (e.g. `string.ig`'s `split`/`starts_with`) is type-registered as a
  **`compiler_builtin`** in the typechecker T2/T3 registry (`typechecker.rs:63-100,1811`);
- the VM dispatches the qualified builtin name to a **native Rust** arm
  (`vm.rs:596` `"stdlib.string.concat" => "concat"` → `vm.rs:764+` native impl).

So `stdlib.regexp.{matches,capture}` = a `.ig` signature + a typechecker builtin entry + a VM native
arm. **Engine choice:**

| Engine | Verdict |
|---|---|
| **Rust `regex` crate** | **RECOMMENDED.** Linear-time (Thompson NFA — **no catastrophic backtracking by construction**), Unicode-by-default, well-audited. Its lack of lookaround/backrefs is a **safety feature**, not a gap. |
| `fancy-regex` | **REJECTED/deferred.** Backtracking → re-introduces the catastrophic-backtracking class the safety policy forbids. |
| PCRE / onig (C libs) | **REJECTED/deferred.** Backtracking + C FFI + non-determinism risk. |
| host-provided adapter trait | **YES, as the seam.** Define `stdlib.regexp` against a small host `RegexEngine` trait so a richer engine could be slotted later WITHOUT changing the `.ig` API — but v0 ships only the `regex`-backed impl. |

`regex` is **not yet a dependency** anywhere (verified `rg regex Cargo.toml` = empty), so adding it is a
P2/P3 dependency decision — out of scope for this design card.

## 3. Safety policy (Q3)

v0 guarantees:
- **Deterministic + linear-time:** guaranteed by the `regex` engine (no catastrophic backtracking, no
  lookaround/backrefs). Pure function of `(text, pattern)`.
- **No ambient authority:** no filesystem, network, locale, clock, or global mutable state. A compiled
  pattern is value-local (the engine may cache by pattern string, but observably pure).
- **Budgets:** the linear-time engine bounds runtime by `O(pattern × text)`; an explicit pattern-length
  / haystack-length cap is **optional** (recommend a generous pattern-length cap, e.g. ≤ a few KB, to
  bound compile cost; not required for correctness). Note as a P3 knob.
- **Return substrings, never offsets** (see Q5) — avoids exposing byte vs rune position semantics and
  stays inside the LOCKED Text model.
- **No replacement / mutation in v0** — `replace_regex` is deferred (literal `replace`/`replace_all`
  already exist for non-regex needs).
- **Unicode mode:** default Unicode (the `regex` default) — `\d`/`\w`/`.` are Unicode-aware; matches
  align with the locked "rune"/scalar view. Document that `.` excludes newline by default.

## 4. Function surface (Q4)

Smallest justified v0:

```igniter
module stdlib.regexp

def matches(text: String, pattern: String) -> Bool                       -- v0 ✓ (workhorse)
def capture(text: String, pattern: String, index: Integer) -> Option[String]  -- v0 ✓ (THE WR-P04 unblock)
def captures(text: String, pattern: String) -> Collection[String]        -- v0 optional/secondary
```

- `matches` — route guards + validation; the most-used, simplest, no ergonomics friction.
- `capture(…, index)` — positional capture group → the path-param extraction primitive. `index 0` =
  whole match; `1..` = groups. Returns the **substring** (Q5).
- `captures` — all groups as a collection; **kept but secondary** (collection iteration ergonomics are
  weaker than a single `capture`; for routing you usually want a specific group). Could be deferred if
  P2 finds it unused.
- `capture_named(text, pattern, name) -> Option[String]` — **DEFERRED.** Named groups are nicer but
  positional `capture` covers routing; named adds no power and the routing DSL (Q11) generates the
  pattern anyway. Revisit if a real app needs self-documenting captures.
- `split_regex(text, pattern) -> Collection[String]` — **DEFERRED.** Literal `split` exists; regex-split
  is not needed for routing and widens the surface.
- `replace_regex` — **DEFERRED** (mutation; literal replace exists).

## 5. Return-shape fit (Q5)

- **Return substrings, not positions.** `capture -> Option[String]` (the matched text), `captures ->
  Collection[String]`. This sidesteps the byte-vs-rune offset question entirely and stays inside the
  LOCKED `Text = valid UTF-8` model. No `(start,end)` integer tuples in v0.
- **`Option[String]` is usable TODAY** despite imperfect ergonomics: `or_else(capture(p, re, 1), "")`
  works now (the live `reconciler` uses `or_else(map_get(…), default)`). So `capture` is shippable
  before Option-match ergonomics improve.
- **Map-returning shapes wait.** `capture_named` would ideally return into a `Map`/record, but Map
  construction is a gap (`WR-P03 / LANG-STDLIB-MAP`) and record-literal inference needs annotation
  (`WR-P06`). So named/grouped-into-map captures are deferred until those land — don't ship an API
  that's elegant on paper and painful in `.ig`.

## 6. Error taxonomy (Q6)

| Pattern source | Invalid-pattern behavior (v0 policy) |
|---|---|
| **literal** (string literal in source) | eventually a **compile-time structured diagnostic** (a new `OOF-RE1`-style code) — the pattern is known at compile time, mirroring how `regex_match` already maps to a closed-surface `OOF-TY0`, and the `call_contract` literal-resolution discipline. (Specified here; implemented in P3.) |
| **dynamic** (computed `String`) | **runtime operational error** — surfaced via the VM's existing `Result<_, String>` error path (`vm.rs` already returns `Err(format!(…))` for operational failures like division-by-zero). NOT silently `false`/`None` (which would swallow a real bug). |

`matches` on an invalid pattern must NOT return `false`; `capture` must NOT return `None` — both must
error (compile or runtime per source). A `Result`-like variant return is **rejected for v0** (it would
force every call site through a `match` even on valid patterns — too heavy); the literal/dynamic split
above is the lighter, honest policy.

## 7. Literal vs dynamic pattern (Q7)

**Both allowed, with a diagnostic split.** Recommend the typechecker **validate literal patterns at
compile time** (same spirit as `call_contract`'s literal-name resolution) → a bad literal regex is a
compile diagnostic, never a runtime surprise. **Dynamic patterns compile** (the type is just `String`)
but are validated only at runtime (operational error on bad pattern). The IgWeb lowering (Q11) emits
**literal** patterns, so the common case always gets the compile-time diagnostic. This is the safer
default and matches the existing literal-resolution discipline.

## 8. Route pressure tests (Q8)

```igniter
-- id extraction
compute is_done   = matches(req.path, "^/todos/([0-9]+)/done$")
compute todo_id   = or_else(capture(req.path, "^/todos/([0-9]+)/done$", 1), "")

-- nested (middle param — the case `split`/`last` CANNOT do; regex CAN)
compute account_id = or_else(capture(req.path, "^/accounts/([0-9]+)/todos/([0-9]+)$", 1), "")
compute todo_id2   = or_else(capture(req.path, "^/accounts/([0-9]+)/todos/([0-9]+)$", 2), "")

-- webhook vendor
compute vendor = or_else(capture(req.path, "^/webhooks/([a-z0-9_-]+)$", 1), "")
```

These are **clean enough today** wrapped in `or_else`. The raw `Option[String]` is the friction point —
routed to the Option-ergonomics gap (`LANG-SUMTYPE-CONSTRUCT-MATCH`), NOT papered over. Crucially,
regexp **does** express nested middle-param extraction (`account_id` + `todo_id`), which
`split`+`last`+`nth` could not do cleanly (WR-P04 / DX-SHAPE-P2 fixture 2). That is the decisive win.

## 9. Validation / extraction pressure tests (Q9)

```igniter
compute email_ok  = matches(addr,  "^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$")          -- email-ish (not RFC)
compute uuid_ok   = matches(id,    "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$")
compute phone_ok  = matches(phone, "^\\+?[0-9][0-9 .-]{6,}$")                 -- phone-ish, not locale-aware
compute zip5      = or_else(capture(line, "([0-9]{5})", 1), "")              -- extract a 5-digit run
```
Practical, not regex golf. Note: backslash classes need doubling in `.ig` string literals (`\\d`) — an
escaping ergonomics cost the route DSL (Q11) hides from authors.

## 10. Relationship to WR-P04 (Q10)

Regexp **unblocks** routing param extraction (esp. nested/middle params) — but it does **NOT replace**
the desirability of `split → Collection[String]` typing, `nth`, and `Option`-match ergonomics:
- `capture` still returns `Option[String]`, so the **same** `LANG-SUMTYPE-CONSTRUCT-MATCH` Option
  friction remains (you still need `or_else`/`match` to use the result). Regexp must not be used to
  **hide** this — fix it independently.
- `split`/`nth`/collection work is broadly useful beyond routing (CSV-ish parsing, lists). Regexp does
  not subsume it.
**Precise relationship:** for IgWeb *path-param routing specifically*, the regexp track is the cleaner
substrate and removes the hard blocker; the WR-P04 collection-ergonomics items stay independently
desirable (and `capture`'s Option result keeps the Option-ergonomics item on the table).

## 11. Relationship to the IgWeb route DSL (Q11)

The DX-SHAPE-P2 winner — a `.igweb` DSL lowering to an explicit `Serve` contract — uses regexp as its
**lowered substrate**, never the author's surface:

```text
route POST "/todos/:id/done" -> TodoDone        (author writes this — no regex)
        │  lower_igweb  (each ":id" → a capture group)
        ▼
compute matched = matches(req.path, "^/todos/([0-9]+)/done$")          (generated)
compute id      = or_else(capture(req.path, "^/todos/([0-9]+)/done$", 1), "")   (generated)
→ if matched { call_contract("TodoDone", with_id(req,id)) } else { … }  (static arm)
```

So app authors write `:id`; the lowering emits `matches`/`capture`. Layering: **DSL (author) → regexp
(generated substrate) → static `call_contract` arms → `ServerDecision`.** Regex's escaping/anchoring
complexity stays inside the generator. (A `:id` could default to `([^/]+)` or a typed `([0-9]+)` if the
DSL grows param types — future.)

## 12. Implementation path (Q12)

1. **`LAB-STDLIB-REGEXP-P2`** *(proof-local, Rust)* — a standalone Rust adapter over the `regex` crate
   proving `matches`/`capture`/`captures` semantics + the safety policy (linear-time, invalid-pattern
   handling, Unicode), with the dependency added **only** in the proof scope. **No** compiler/VM/stdlib
   wiring, no `.ig` surface yet. Decides the engine + return shapes against real fixtures (Q8/Q9).
2. **`LAB-STDLIB-REGEXP-P3`** *(if P2 proves the shape)* — register `stdlib.regexp.{matches,capture}` as
   `compiler_builtin` in the typechecker (T2/T3) + add VM native dispatch arms over `regex`; implement
   the literal-pattern compile diagnostic (`OOF-RE1`) + dynamic-pattern operational error. This is the
   first canon-adjacent step → its own gate.
3. **`LAB-IGNITER-WEB-ROUTING-LOWERING-P4`** *(consumes P3)* — the `.igweb`→`Serve` lowering emits
   regexp `matches`/`capture` as substrate (composes with the DX-SHAPE-P2 winner).

Ordering note vs DX-SHAPE-P2 (which named WR-P04 `split`/`nth` as the routing prerequisite): **regexp
supersedes the `nth`-for-routing need** — it handles nested/middle params that `split`+`nth` struggle
with — so for IgWeb routing, this regexp track (P2→P3) is the recommended prerequisite over a `nth`
card. WR-P04's `split` typing + Option ergonomics remain independently desirable (Q10) but are no longer
the hard routing blocker once regexp lands.

**Canon promotion: NOT YET** — lab readiness only; gated by P2 proof then P3 registration.

---

## Closed surfaces (held)

No code change; no new dependency (regex added only in a later proof scope); no compiler/parser/
typechecker/VM/stdlib edit; no regex-based router in `igniter-server`; no backtracking engine (rejected/
deferred); no public listener/DB/SparkCRM/vendor; no canon `LANG-*`/stdlib claim.

---

*Research/readiness only. Compiled 2026-06-18 against the live string/Unicode policy docs, the
typechecker/VM builtin seam, and the IgWeb routing pressure (P1/P2). No implementation; no dep change.*
