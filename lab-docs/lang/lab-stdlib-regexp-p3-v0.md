# lab-stdlib-regexp-p3-v0 — regexp builtins in compiler + VM

**Card:** `LAB-STDLIB-REGEXP-P3` · **Delegation:** `OPUS-STDLIB-REGEXP-C`
**Status:** CLOSED (canon-adjacent implementation) — `stdlib.regexp.{matches, capture}` are now real
compiler + VM builtins available to `.ig` programs, with the P2 semantics. **`regex` is a real
dependency only in `igniter-vm` (runtime) + `igniter-compiler` (literal diagnostic). No parser change,
no IgWeb lowering, no `igniter-server` change, no `captures`/`capture_named`/`split_regexp`/
`replace_regexp`.**
**Authority:** Lab implementation. Grounded in the live builtin seam; mirrors `split`/`contains`.

## Public `.ig` surface

```igniter
import stdlib.regexp.{ matches, capture }

matches(text: String, pattern: String) -> Bool
capture(text: String, pattern: String, index: Integer) -> Option[String]
```

Declaration file: `igniter-stdlib/stdlib/regexp.ig` (`module stdlib.regexp`). Semantics are exactly the
P2 proof: linear-time `regex` engine; `matches` anchors only if the author writes `^…$`; `capture`
`index 0` = whole match, `≥1` = group; no-match / out-of-range / unmatched-optional → `Option.None`
(VM `Value::Nil`); invalid pattern → error (compile for literals, runtime for dynamic); returns
matched **substrings**, never offsets; Unicode-mode by default.

## Dependency placement (and why)

| Crate | `regex` scope | Why |
|---|---|---|
| `igniter-vm` | **real dependency** | runtime dispatch of `matches`/`capture` over `regex::Regex`. |
| `igniter-compiler` | **real dependency** | compile-time validation of LITERAL patterns (`OOF-RE1`) — same engine as the VM, so a literal that compiles behaves identically at runtime. |
| `igniter-stdlib` | dev-only (unchanged from P2) | the `.ig` declaration carries no Rust code; the P2 proof test keeps its dev-dep. |

`igniter-server` and `igniter-machine` are untouched.

## What changed (minimal, mirrors `split`/`contains`)

| File | Change |
|---|---|
| `igniter-stdlib/stdlib/regexp.ig` | **new** — `module stdlib.regexp` + the two `def`s |
| `igniter-compiler/src/typechecker.rs` | `text_stdlib_return_type`: `matches` → `Bool` |
| `igniter-compiler/src/typechecker/stdlib_calls.rs` | `matches` arm (arity/type via `check_text_stdlib_call`); `capture` arm (in-place check — heterogeneous `(Text,Text,Integer)` — returns `Option[String]`); new `check_literal_regexp_pattern` helper (literal → `OOF-RE1`) |
| `igniter-compiler/src/emitter.rs` | bare `matches`/`capture` → `stdlib.regexp.*` + `resolved_type` (Bool / Option[String]), mirroring the `TEXT_STDLIB_OPS` rewrite |
| `igniter-vm/src/vm.rs` | native arms at BOTH dispatch sites — the bytecode OP_CALL path (`"matches" \| "stdlib.regexp.matches"`, `"capture" \| "stdlib.regexp.capture"`) and the `eval_ast` tree-walker — for parity |
| `igniter-vm/Cargo.toml`, `igniter-compiler/Cargo.toml` | `regex = "1"` |

## Typechecker registration

`infer_stdlib_call` recognizes the bare names (the dispatch is by short name, same as `split`):
- `matches` → arity 2, both `Text`, return `Bool`. Wrong arity/type → `OOF-TY0`.
- `capture` → arity 3, args 1–2 `Text`, arg 3 `Integer`, return `Option[String]` (built in-place like
  `find`). Wrong arity / non-Integer index → `OOF-TY0`.
The emitter then rewrites bare → `stdlib.regexp.*` with the resolved type, so the IR is fully
annotated; the VM dispatches the qualified name.

## Literal vs dynamic invalid-pattern behavior

- **Literal pattern** (a string literal arg): validated at compile time by `check_literal_regexp_pattern`
  → `OOF-RE1` on failure (bad syntax, or a rejected feature like lookaround/backref). Implemented (not
  skipped) — extraction mirrors the existing `decimal` literal-scale check (`Expr::Literal { value,
  type_tag == "String" }`).
- **Dynamic pattern** (a computed `String`): compiles cleanly; validated at runtime → an operational
  `Err` from the VM (`Result<_, String>`), never `false`/`None`.

## VM semantics (both backends)

Native arms added at the bytecode OP_CALL path AND the `eval_ast` tree-walker (parity, per the live
dual-path design). `matches` → `Value::Bool`; `capture` → `Value::String` (Some) or `Value::Nil`
(None); invalid pattern → `Err`. Substrings only; Unicode preserved.

## Deferred / closed (held)

`captures`, `capture_named`, `split_regexp`, `replace_regexp` are **not registered** — calling them is
not recognized as a regexp builtin (deferred per P2). The old closed `regex_match` surface is
untouched (still `OOF-TY0`); it is NOT aliased to the new names. No lookaround/backref (rejected by the
engine). No parser syntax change. No IgWeb lowering. No `igniter-server` change.

## Test commands / pass counts

```text
$ cd igniter-stdlib && cargo test                              → 11 passed; 0 failed   (P2 proof, intact)
$ cd igniter-compiler && cargo test --test regexp_typecheck_tests → 8 passed; 0 failed
$ cd igniter-vm && cargo test --test regexp_runtime_tests      → 6 passed; 0 failed
```

**Compiler tests (8):** valid matches+capture compile clean; `matches`/`capture` wrong arity → OOF-TY0;
`capture` non-Integer index → OOF-TY0; literal `(` → OOF-RE1; literal lookaround `foo(?=bar)` →
OOF-RE1; dynamic pattern → no OOF-RE1; valid literal compiles.

**VM tests (6):** matches anchored/unanchored; capture index 0/1/out-of-range/no-match/optional; route
pressure (`/todos/42`→42, `/todos/42/done`→42, nested `/accounts/7/todos/42`→(7,42), webhook
`callrail`, mismatch→false); bare-name dispatch parity; Unicode `/todos/київ`→"київ"; invalid pattern +
lookaround + backref → runtime error.

## Regression (verified)

- `igniter-stdlib`: 11/11 (P2 proof unchanged).
- `igniter-compiler` full suite: all green EXCEPT `loop_conformance_tests` (4 failures) — **PRE-EXISTING**
  (loop-IR shape; confirmed identical with my compiler edits stashed). Unrelated to regexp.
- `igniter-vm` full suite: all green EXCEPT `vm_candidate_proof_tests::test_proof_vmg13_local_loops_and_
  service_loops` — **PRE-EXISTING** (`OP_GET_FIELD: expected Record, got Integer`; confirmed identical
  with my `vm.rs` change stashed). Unrelated to regexp.
- `igniter-server`, `igniter-machine`: not touched.

My change introduces **zero new test failures**; the two pre-existing reds were confirmed via
`git stash` of my edits.

## Next card

`LAB-IGNITER-WEB-ROUTING-LOWERING-P4` — implement deterministic `.igweb` route DSL lowering to an
explicit `Serve(Request) -> Decision` `.ig` contract, using `stdlib.regexp.matches`/`capture` as the
generated substrate for `:params` (authors write `:id`; lowering emits regexp). Builds on this P3
surface; no server-core route table.

---

*Canon-adjacent lab implementation. Compiled 2026-06-18; 11 + 8 + 6 = 25 regexp tests green; two
pre-existing unrelated reds documented.*
