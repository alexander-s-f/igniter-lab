# lab-lang-signature-bound-contract-surface-p2-v0 — pure signature-bound contract surface

**Card:** `LAB-LANG-SIGNATURE-BOUND-CONTRACT-SURFACE-P2` · **Delegation:** `OPUS-LANG-SIGNATURE-BOUND-CONTRACT-SURFACE-P2`
**Status:** CLOSED (lab implementation-proof) — the compact `(in: T) -> (out: U) { name = expr }` contract
surface is implemented as a **pure parser desugar** to canonical `input`/`compute`/`output`. AST-parity
proven (signature body ≡ explicit body). **Only `=` bindings; no `<-`/`?`/comprehensions/`let`; no
typechecker/emitter/VM change; no canon claim.**
**Authority:** Lab tooling. Implements the P1 readiness recommendation (the `=`-only pure slice, Alt B).

## What was implemented (parser only)

A signature-bound contract:
```ig
pure contract Build(req: Request) -> (status: Integer, body: String) {
  prepared : String = Prepare { req: req }
  status = 200
  body = prepared
}
```
**desugars at parse time** to the canonical body — identical AST to:
```ig
pure contract Build {
  input req : Request
  compute prepared : String = Prepare { req: req }
  compute status : Integer = 200
  compute body : String = prepared
  output status : Integer
  output body : String
}
```

Grammar added (`parser.rs`): an optional signature after the contract name/type-params/`implements` and
before `{`:
```
signature := "(" (name ":" Type ("," ...)?)? ")" "->" "(" (name ":" Type ("," ...))? ")"
body      := ( name (":" Type)? "=" expr )*        -- bare bindings, no keyword
```

## Desugar rules

| Surface | Canonical body decl |
|---|---|
| signature input `req: Request` | `BodyDecl::Input { req, Request }` |
| body binding `name [:T] = expr` | `BodyDecl::Compute { name, type?, expr }` (reuses `parse_compute_decl`) |
| signature output `d: Decision` | `BodyDecl::Output { d, Decision, …None }` |
| output binding omitting its type | the compute inherits the **signature output type** |

Body order: inputs, then computes (source order), then outputs — exactly the explicit form. Source order is
readability/diagnostics only; semantics stay DAG dependency order (unchanged from canonical).

**Type rule (Q from card):** a body binding may carry an explicit `: Type` (like canonical `compute x : T`)
or omit it (like canonical `compute x = …`); an **output** binding may omit its type and inherit it from the
signature (so `status = 200` becomes `compute status : Integer`). Intermediates follow the exact canonical
`compute` typing — no new inference was added.

## Why this is safe (the elegant outcome)

The desugar happens **entirely in the parser**, producing the same `Vec<BodyDecl>` the explicit form
produces. Therefore **no typechecker, emitter, or VM change was needed** — everything downstream sees
canonical body decls. Identical post-parse AST ⟹ identical SemanticIR by construction → node identity,
source maps, receipts, time-travel all unaffected.

## SIR / AST parity evidence

`single_signature_desugars_identically_to_explicit` and `intermediate_and_multi_output_desugar_identically`
assert `serde_json::to_value(signature.body) == serde_json::to_value(explicit.body)` — **byte-identical
parsed body** (the AST carries no source positions; spans are a separate sourcemap side-effect). Live CLI
also confirms both forms compile to `status: ok` and a deliberately-undeclared variant yields the **same**
`OOF-KIND2` in both forms (identical downstream path).

## Diagnostics

- **missing output:** signature output with no body binding → `OOF-P1 "signature output \`z\` is not defined
  in the contract body"`. (Proven: `missing_output_binding_is_rejected`.)
- **duplicate body binding:** two bindings with the same name → `OOF-P1 "duplicate body binding \`t\`"`.
  (Proven: `duplicate_body_binding_is_rejected`.)
- a malformed binding recovers via `skip_until_body_boundary` (consistent with the body loop's recovery).

## Files changed

- `lang/igniter-compiler/src/parser.rs` (+151/−3): optional signature in `parse_contract_decl`;
  `parse_contract_signature` + `parse_sig_param_list` + `build_signature_body` helpers.
- `lang/igniter-compiler/tests/signature_contract_surface_tests.rs` (new): 5 tests.
- **No** typechecker/emitter/lexer change (`<-` deliberately not tokenized; `?` already tokenized but
  untouched).

## Tests & commands — exact counts

```text
$ cd lang/igniter-compiler && cargo test --test signature_contract_surface_tests → 5 passed
$ cd lang/igniter-compiler && cargo test                                         → 137 passed; 0 failed
$ cd lang/igniter-compiler && cargo test --test igweb_lowering_tests             → 11 passed (unchanged)
$ cd server/igniter-web    && cargo test                                         → 17 binaries green (relational/ViewArtifact fixtures intact)
$ git diff --check                                                               → clean
```

## Acceptance — mapping

- [x] Parse pure signature contract, single + multiple in/out.
- [x] Desugar signature inputs → `input`; body `name [:T] = expr` → `compute`; signature outputs → `output`.
- [x] Output binding may omit type (inherits signature type).
- [x] Intermediate typing = canonical `compute` rule (explicit `:T` optional, same as today).
- [x] Missing output / duplicate body binding → clear diagnostics.
- [x] Signature contract emits AST-identical (⟹ SIR-identical) form to explicit canonical.
- [x] Existing explicit contracts, IgWeb lowering, relational/ViewArtifact fixtures green (137 / 11 / 17).
- [x] `<-`, `?`, comprehensions, `let`-body not implemented.
- [x] `git diff --check` clean.

## Out of scope (honored)

No semantic `<-` boundary bindings (next: `…-BOUNDARY-BINDINGS-P3`); no `read`/`effect` signature form; no
`?` propagation; no comprehensions; no `let` contract body; no IgWeb syntax change; no runtime/VM change; no
canon claim. (A signature contract using `<-` simply fails to parse — `<-` is not a token — which is an
acceptable "not implemented in P2" outcome.)

## Next

1. `LAB-LANG-SIGNATURE-BOUND-BOUNDARY-BINDINGS-P3` — semantic `<-` (`read`/effect boundary; `pure` rejects
   it), after canonical read/effect node semantics are pinned.
2. `LAB-LANG-FALLIBLE-BINDING-READINESS-P1` — `?` propagation over Result/Option.
3. `LAB-LANG-COLLECTION-COMPREHENSION-READINESS-P1` — list ergonomics over `map`/`filter`.

---

*Lab implementation-proof. Compiled 2026-06-20; igniter-compiler 137 passed / 0 failed (incl. 5 new
signature tests, AST-parity green), igweb lowering 11, igniter-web 17 binaries green, `git diff --check`
clean. The compact `(in)->(out){ binds }` surface is a pure parser desugar to canonical input/compute/output
— zero typechecker/emitter/VM change, byte-identical AST/SIR.*
