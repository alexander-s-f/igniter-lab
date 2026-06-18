# Card: LAB-STDLIB-REGEXP-P3 — register regexp builtins in compiler + VM

**Lane:** standard / canon-adjacent implementation
**Skill:** idd-agent-protocol
**Status:** CLOSED (canon-adjacent implementation)
**Date opened:** 2026-06-18
**Date closed:** 2026-06-18
**Delegation label:** OPUS-STDLIB-REGEXP-C
**Authority:** Lab implementation with canon-adjacent stdlib behavior. This card opens a real runtime dependency on Rust `regex`, but only for the narrow `stdlib.regexp.{matches,capture}` surface proven in P1/P2. No IgWeb lowering, no server changes.

## Why this card exists

P1 decided the regexp shape. P2 proved the semantics in Rust with `regex` as a dev-only dependency.
We now accept `regex` as a real architectural dependency because its benefit outweighs the cost:
text pattern matching unlocks route params, validation, extraction, and classification without Rust
route tables or ugly `split/count/last` patterns.

This card promotes the proven v0 surface into the actual compiler/VM path.

## Architectural decision

`regex` is no longer just a proof dependency. It becomes the narrow, real text-pattern engine for
`stdlib.regexp`.

Guardrails:

- engine = Rust `regex` crate only (linear-time, Unicode default, no lookaround/backrefs);
- surface = `matches` + `capture` only;
- no `captures`, `capture_named`, `split_regex`, `replace_regex`;
- no parser syntax change;
- no IgWeb route DSL/lowering;
- no `igniter-server` changes;
- literal invalid patterns should produce structured compile diagnostics where feasible;
- dynamic invalid patterns produce runtime operational errors, never `false`/`None`.

## Read first (verify-first, live code wins)

- `lab-docs/lang/lab-stdlib-regexp-p1-v0.md`
- `lab-docs/lang/lab-stdlib-regexp-p2-v0.md`
- `.agents/work/cards/lang/LAB-STDLIB-REGEXP-P1.md`
- `.agents/work/cards/lang/LAB-STDLIB-REGEXP-P2.md`
- `igniter-stdlib/tests/regexp_engine_proof_tests.rs`
- `igniter-stdlib/Cargo.toml`
- `igniter-stdlib/stdlib/core/string.ig`
- `igniter-compiler/src/typechecker.rs`
- `igniter-compiler/src/emitter.rs`
- `igniter-vm/src/vm.rs`
- existing stdlib VM tests and compiler builtin tests (`rg -n "stdlib.text|split|starts_with|compiler_builtin|OOF-TY0" igniter-compiler igniter-vm igniter-stdlib tests`)

## Goal

Make these functions available to `.ig` programs through the real compiler + VM path:

```igniter
import stdlib.regexp.{ matches, capture }

matches(text: String, pattern: String) -> Bool
capture(text: String, pattern: String, index: Integer) -> Option[String]
```

The implementation must preserve the exact semantics proven in P2.

## Required implementation

### 1. Stdlib declaration surface

Add a stdlib declaration file in the existing style, likely:

`igniter-stdlib/stdlib/regexp.ig`

with only:

```igniter
def matches(text: String, pattern: String) -> Bool
def capture(text: String, pattern: String, index: Integer) -> Option[String]
```

If the stdlib module path convention requires a different location/name, verify and use that.

### 2. Dependency promotion

Promote `regex = "1"` from proof-only/dev scope into the narrow runtime crate(s) that actually need it.

Expected possibilities:

- `igniter-vm` needs `regex` for runtime dispatch.
- `igniter-compiler` may need `regex` only if literal-pattern validation is implemented in typechecker.
- `igniter-stdlib` may or may not need normal `regex`; avoid adding it there unless actual runtime code uses it.

Keep dependency placement minimal and explain it in the proof doc. It is acceptable for both compiler and VM to depend on `regex` if literal diagnostics require compiler validation.

### 3. Typechecker builtin registration

Register `stdlib.regexp.matches` and `stdlib.regexp.capture` as known builtins with these types:

```text
matches(String, String) -> Bool
capture(String, String, Integer) -> Option[String]
```

Acceptance must include:

- correct arity diagnostics;
- wrong arg type diagnostics;
- unknown `regex_match` remains closed / not silently aliased;
- import path works as `stdlib.regexp.{ matches, capture }` or whichever current import syntax supports.

### 4. Literal-pattern diagnostic

Implement best-effort compile-time validation for literal patterns:

- literal bad pattern in `matches("abc", "(")` / `capture(...)` -> structured diagnostic, preferably `OOF-RE1` or the closest current diagnostic path with a clear rule/message;
- literal lookaround/backref should also be diagnosed as invalid pattern;
- dynamic pattern stays type-valid and is checked at runtime.

If current typechecker architecture makes a new `OOF-RE1` too invasive, implement the smallest structured diagnostic and document the limitation. Do not silently skip literal validation unless truly blocked; if blocked, explain exactly where.

### 5. VM/runtime dispatch

Add native VM dispatch for the qualified stdlib functions.

Semantics must match P2:

- `matches` true iff regex matches anywhere; no hidden anchoring.
- `capture(index=0)` returns whole match.
- `capture(index>=1)` returns capture group.
- no match / out-of-range / optional unmatched -> `Option.None` equivalent currently used by the VM.
- invalid dynamic pattern -> runtime operational error (`Err`), not false/none.
- return substrings, not offsets.
- Unicode capture preserves valid UTF-8.

### 6. Tests

Add targeted tests at the narrowest appropriate layers. Required coverage:

Compiler/typechecker:

- valid `matches` and `capture` compile.
- wrong arity/type fails.
- literal invalid pattern fails with regexp diagnostic.
- dynamic pattern compiles.
- old closed surface (`regex_match` or equivalent) remains unavailable unless explicitly superseded by the new names.

VM/runtime:

- route id: `/todos/42` -> `42`.
- done route: `/todos/42/done` -> `42`.
- nested route: `/accounts/7/todos/42` -> `7` and `42`.
- webhook vendor: `/webhooks/callrail` -> `callrail`.
- unanchored matching behavior.
- `capture(0)` whole match.
- out-of-range/no-match/optional unmatched -> none.
- invalid dynamic pattern -> runtime error.
- lookaround/backref rejected.
- Unicode capture: `/todos/київ` -> `київ`.

Regression:

- existing string/text stdlib tests still pass.
- `igniter-stdlib` proof tests still pass or are migrated cleanly.
- no `igniter-server` changes.

## Required docs

Write:

`lab-docs/lang/lab-stdlib-regexp-p3-v0.md`

Include:

- exact dependency placement and why;
- exact public `.ig` stdlib surface;
- typechecker registration summary;
- literal vs dynamic invalid-pattern behavior;
- VM semantics;
- test commands/pass counts;
- any limitations or postponed surfaces;
- next IgWeb lowering card.

Update closing report in this card.

Optional: update a local implemented-surface/status doc only if this repo has a current one for stdlib/compiler surfaces. Do not create broad status churn.

## Suggested commands

Adjust after verifying crate layout, but run at least:

```bash
cd igniter-stdlib && cargo test
cd igniter-compiler && cargo test --no-fail-fast   # or narrower + documented known failures if full suite has pre-existing reds
cd igniter-vm && cargo test --no-fail-fast         # or narrower + documented known failures
```

If workspace-wide tests are too broad or have known unrelated failures, run targeted tests and document the pre-existing blockers precisely.

## Acceptance

- [ ] `matches` and `capture` are available to `.ig` programs via stdlib import.
- [ ] `regex` is a real dependency only in the crate(s) that need it.
- [ ] Typechecker knows both functions and enforces arity/types.
- [ ] Literal invalid patterns produce structured compile diagnostics or a documented minimal equivalent.
- [ ] Dynamic invalid patterns produce runtime operational error.
- [ ] VM semantics match P2 exactly.
- [ ] `capture(0)` whole match; `capture(1..)` groups; none cases are correct.
- [ ] Lookaround/backrefs rejected.
- [ ] Unicode substring capture proven.
- [ ] Route/nested/webhook/validation pressure tests pass.
- [ ] `captures` remains unavailable/deferred.
- [ ] No parser syntax change.
- [ ] No IgWeb lowering implementation.
- [ ] No `igniter-server` change.
- [ ] Docs and closing report include exact commands/pass counts.

## Closed surfaces

- No `.igweb` DSL/lowering.
- No Todo app implementation.
- No server route table.
- No `captures`, `capture_named`, `split_regex`, `replace_regex`.
- No backtracking regex engine.
- No public listener/live/network/DB/SparkCRM work.
- No broad compiler refactor.
- No release/canon announcement beyond lab implementation evidence.

## Next after success

`LAB-IGNITER-WEB-ROUTING-LOWERING-P4` — implement deterministic `.igweb` route DSL lowering to explicit `Serve(Request)->Decision` `.ig`, using `stdlib.regexp.matches/capture` as the generated substrate for `:params`.

---

## Closing report — 2026-06-18

**Outcome:** `stdlib.regexp.{matches, capture}` are now real `.ig`-callable builtins through the actual
compiler + VM path, preserving the P2 semantics. `regex` promoted to a real dependency of `igniter-vm`
(runtime) + `igniter-compiler` (literal diagnostic). No parser change, no IgWeb lowering, no
`igniter-server` change, no deferred surfaces.

**Deliverable:** `lab-docs/lang/lab-stdlib-regexp-p3-v0.md`.

**Surface:** `import stdlib.regexp.{ matches, capture }`; `matches(String,String)->Bool`,
`capture(String,String,Integer)->Option[String]`. Decl file `igniter-stdlib/stdlib/regexp.ig`
(`module stdlib.regexp`).

**Changes (mirror split/contains):** stdlib decl (new); typechecker `text_stdlib_return_type` matches→
Bool + `stdlib_calls.rs` `matches`/`capture` arms (capture checked in-place for `(Text,Text,Integer)`,
returns Option[String] like `find`) + `check_literal_regexp_pattern` helper (OOF-RE1); emitter bare→
`stdlib.regexp.*` rewrite + resolved_type; VM native arms at BOTH dispatch sites (bytecode OP_CALL +
eval_ast) for parity; `regex="1"` in vm + compiler Cargo.

**Errors:** literal bad pattern → compile-time `OOF-RE1` (implemented via `Expr::Literal` extraction,
mirroring the decimal literal-scale check); dynamic bad pattern → runtime operational `Err` (VM
`Result<_,String>`), never false/None.

**Deferred/closed:** `captures`/`capture_named`/`split_regexp`/`replace_regexp` NOT registered;
`regex_match` closed surface untouched (still OOF-TY0, not aliased); lookaround/backref rejected by the
engine; no parser change; no IgWeb lowering; server/machine untouched.

**Test commands + counts:**
```text
cd igniter-stdlib  && cargo test                               → 11 passed; 0 failed (P2 proof intact)
cd igniter-compiler && cargo test --test regexp_typecheck_tests → 8 passed; 0 failed
cd igniter-vm      && cargo test --test regexp_runtime_tests   → 6 passed; 0 failed
```
Compiler tests: valid compile; matches/capture arity → OOF-TY0; non-Integer index → OOF-TY0; literal
`(` and lookaround → OOF-RE1; dynamic pattern no OOF-RE1; valid literal compiles. VM tests:
matches/capture index semantics, route+nested+webhook pressure, bare-name parity, Unicode
`/todos/київ`→"київ", invalid/lookaround/backref → runtime error.

**Regression (verified via git stash):** my change adds ZERO new failures. Two PRE-EXISTING reds
confirmed identical without my edits and unrelated to regexp: `igniter-compiler`
`loop_conformance_tests` (4, loop-IR shape) and `igniter-vm`
`vm_candidate_proof_tests::test_proof_vmg13_local_loops_and_service_loops` (1, `OP_GET_FIELD` record/
timestamp). `igniter-server`/`igniter-machine` untouched.

**Acceptance:** all boxes met — matches/capture available to `.ig`; regex dep only where needed;
typechecker enforces arity/types; literal invalid → OOF-RE1, dynamic → runtime error; VM semantics
match P2; capture(0) whole / (1..) groups / None correct; lookaround/backref rejected; Unicode
substring proven; route/nested/webhook/validation pressure green; `captures` deferred; no parser/IgWeb/
server change; commands+counts recorded. Next = `LAB-IGNITER-WEB-ROUTING-LOWERING-P4`.
