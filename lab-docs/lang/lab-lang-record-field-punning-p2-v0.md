# lab-lang-record-field-punning-p2-v0 — `{ field }` record punning

**Card:** `LAB-LANG-RECORD-FIELD-PUNNING-P2` · **Delegation:** `OPUS-LANG-RECORD-FIELD-PUNNING-P2`
**Status:** CLOSED (lab implementation-proof) — `{ name }` is **pure parse-time sugar** for `{ name: name }`.
Composes with explicit fields and with record spread (`{ ...base, name }`). **Parser-only** (one branch in
`parse_record_or_block`), no new node kind, no typechecker/emitter/VM change, no canon claim. The scorecard's
top remaining friction (`{ projection: projection, … }`) is removed.
**Authority:** Lab tooling. Implements `LAB-LANG-APP-PRESSURE-ERGONOMICS-SCORECARD-P4`'s recommended card.

## Grammar accepted

```
RecordField := name ':' Expr        -- explicit (unchanged)
             | name                  -- punned  (new)
```

Punned and explicit fields mix freely, in any order, in both record literals and record spreads:

```ig
{ account_id, title, done }                 -- all punned
{ field: "account_id", op: "eq", value }    -- mixed
{ ...ctx, todo_id }                         -- spread + punned
```

## Desugar rule (exact)

In `parse_record_or_block`'s field loop, after reading the field `name`: if the next token is `:`, parse the
value as before; otherwise the field is **punned** and its value is `Expr::Ref { name }`:

```
{ name }              ⇒ { name: name }       (value = Ref(name))
{ name, other: e }    ⇒ { name: name, other: e }
{ ...base, name }     ⇒ { ...base, name: name }
```

The record literal / spread therefore sees the **canonical `{ name: <ref> }`** shape — there is no new AST
variant and nothing downstream (typecheck, spread expansion, emit, VM) changes.

## Before / after (TodoApp pressure)

```ig
-- todo_handlers.ig MakeWriteValues — current
compute v = { account_id: account_id, title: title, done: done }
-- punned
compute v = { account_id, title, done }

-- relational QueryFilter — current
{ field: "account_id", op: "eq", value: account_id }
-- punned (value bound from `value` input)
{ field: "account_id", op: "eq", value }

-- context accumulation — current
{ ...ctx, todo_id: todo_id }
-- punned
{ ...ctx, todo_id }
```

## Interaction with record spread

The punning branch lives in the field loop shared by literals and spreads, so `{ ...base, name }` works with
no extra code: the spread source is parsed first (LAB-LANG-RECORD-SPREAD-P2), then punned/explicit fields,
then the spread's target-driven expansion runs over the canonical `{ name: <ref> }` fields. A punned field
overrides a spread-copied one exactly like an explicit field (same override rule).

## Diagnostics

- **Missing symbol:** `{ account_id }` with no `account_id` in scope → `OOF-P1: Unresolved symbol:
  account_id` (the normal `Ref` unknown-symbol path — punning adds no special case).
- **Unexpected field:** `{ account_id, nope }` against a type lacking `nope` →
  `OOF-TY0: ... unexpected field 'nope' in literal ... (not declared in type)` (existing record-shape check).
- **Dotted punning:** `{ account.id }` → parse error (`Expected name, got Dot`). Closed for v0 (the field
  name would be ambiguous); left as the natural parse error per the card.
- **Duplicate field:** unchanged — `{ account_id, account_id }` → `duplicate field` (the existing literal
  check; punned and explicit share the same key-collision guard).

## Closed forms (and why)

| Form | Status | Why |
|---|---|---|
| `{ account.id }` | rejected (parse error) | dotted/keypath punning — ambiguous field name |
| `{ "name" }` | rejected (parse error) | string-key punning — `name_token` requires an identifier |
| `{ name? }` | not added | optional/pattern sugar — out of scope (canon PROP track) |
| `{ name = expr }` | not added | alternate separator — `:` stays the field separator |

## SIR / runtime parity (proven)

`{ account_id, title, done }` and `{ account_id: account_id, title: title, done: done }` produce a
**byte-identical `record_literal` node** in `semantic_ir_program.json` (test
`punned_record_sir_identical_to_explicit`). Punning is *exactly* the explicit form — zero runtime impact.

## Verification — exact counts

```text
$ cd lang/igniter-compiler && cargo test --test record_field_punning_tests   → 8 passed
    (pure punning; mixed; spread+punning; missing→unresolved; extra→shape; dotted→parse error;
     Todo WriteValues fixture; SIR parity)
$ cd lang/igniter-compiler && cargo test --test record_spread_tests          → 9 passed
$ cd lang/igniter-compiler && cargo test --test app_pressure_scorecard_tests → 3 passed
$ cd lang/igniter-compiler && cargo test --no-fail-fast                      → 183 passed; 0 failed
$ cd server/igniter-web    && cargo test --no-fail-fast                      → 52 passed; 0 failed
$ git diff --check                                                           → clean
```

## Acceptance — mapping

- [x] `{ name }` parses + compiles as `{ name: name }`.
- [x] Mixed explicit + punned fields compile.
- [x] Punned fields work in typed `compute`/`output` contexts.
- [x] Punned fields work inside the spread update `{ ...ctx, todo_id }`.
- [x] Missing symbol fails through the normal unresolved-symbol path.
- [x] Unexpected punned field fails through normal record-shape validation.
- [x] Dotted punning rejected (parse error).
- [x] Existing record spread tests remain green (9/0).
- [x] App-pressure Todo-shaped `WriteValues` fixture with punning compiles.
- [x] No VM/runtime change (parser-only; byte-identical SIR).
- [x] No product example rewrite (fixtures only).
- [x] No canon claim; `git diff --check` clean.

## Deferred / non-goals (honored)

No record defaults, no optional fields, no dotted/keypath punning, no destructuring, no new runtime
representation, no TodoApp rewrite, no canon claim.

## Next

Optional: a tiny example migration applying punning + comprehension to `todo_handlers.ig` / `todo_views.ig`
to showcase the surface (doc/example-only, not a language change). Optional-field defaults — the remaining
`HtmlNode` verbosity — stay on the canon PROP track.

---

*Lab implementation-proof. Compiled 2026-06-21; igniter-compiler 183/0 (incl. 8 new), record_spread 9,
scorecard 3, comprehension 10, igniter-web 52/0; `git diff --check` clean. Punning is parser-only pure sugar
— byte-identical to the explicit record, no new node kind, no authority.*
