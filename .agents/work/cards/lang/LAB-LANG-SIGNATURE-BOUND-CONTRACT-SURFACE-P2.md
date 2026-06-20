# LAB-LANG-SIGNATURE-BOUND-CONTRACT-SURFACE-P2 - Pure signature-bound contract surface

Status: CLOSED
Lane: parallel / surface-ergonomics
Type: implementation-proof
Delegation code: OPUS-LANG-SIGNATURE-BOUND-CONTRACT-SURFACE-P2
Date: 2026-06-20
Skill: idd-agent-protocol

## Context

`LAB-LANG-SIGNATURE-BOUND-CONTRACT-SURFACE-READINESS-P1` concluded that the safest first slice is the
`=`-only pure signature-bound surface:

```ig
pure contract RenderPage(req: Request) -> (d: Decision) {
  d = Render { status: 200, artifact_json: req.body }
}
```

This must desugar to canonical `input` / `compute` / `output` and produce byte-identical SemanticIR to the
explicit form. It deliberately does **not** implement semantic `<-`; that belongs to a later boundary slice.

Key readiness finding: this slice does **not** depend on `MATCH-ARM-BINDINGS-P2`, because contract body
bindings lower directly to `compute` declarations, not through block-local `let`.

## Goal

Implement the pure signature-bound contract surface:

```ig
pure contract A(x: X) -> (y: Y) {
  tmp : T = F { x: x }
  y = G { tmp: tmp }
}
```

Equivalent canonical form:

```ig
pure contract A {
  input x : X
  compute tmp : T = F { x: x }
  compute y : Y = G { tmp: tmp }
  output y : Y
}
```

## Verify First

Read live code before editing:

- `lang/igniter-compiler/src/lexer.rs`
  - `->`, `=>`, `=`, `?`, and possible token conflicts;
- `lang/igniter-compiler/src/parser.rs`
  - `parse_contract_decl`;
  - `BodyDecl`;
  - `parse_input_decl`;
  - `parse_compute_decl`;
  - `parse_output_decl`;
  - diagnostics for duplicate/missing body declarations;
- `lang/igniter-compiler/src/typechecker.rs`
  - contract input/output validation;
  - compute type validation;
  - duplicate name handling;
- `lang/igniter-compiler/src/emitter.rs`
  - SemanticIR / body declaration emission;
- existing tests:
  - pure contracts;
  - multi-output contracts;
  - IgWeb generated contracts;
  - relational and ViewArtifact fixtures;
- readiness packet:
  - `lab-docs/lang/lab-lang-signature-bound-contract-surface-readiness-p1-v0.md`.

Confirm or correct:

- whether best implementation is true parser desugar into existing `BodyDecl`s;
- whether SIR parity can be tested byte-for-byte or needs normalized comparison;
- whether type annotations on body bindings are optional only when output signature provides a type;
- whether intermediate body bindings require explicit types in v0;
- whether signature form should be rejected for non-`pure` contracts in P2 or accepted with only `=`;
- whether canonical explicit contracts remain untouched.

Live code wins over this card.

## Recommended Scope

P2 should support only:

```ig
pure contract Name(input1: T1, input2: T2) -> (output1: U1, output2: U2) {
  intermediate : I = Expr
  output1 = Expr
  output2 : U2 = Expr
}
```

Rules:

- signature inputs become canonical `input` decls;
- each body binding with `=` becomes canonical `compute`;
- output names in the signature become canonical `output` decls;
- every output must be defined exactly once in the body;
- every body binding name must be unique;
- intermediate bindings are allowed;
- source order is for readability/diagnostics; semantics remain DAG dependency order;
- no `<-` accepted in P2, except optionally as a crisp "boundary bindings are not implemented in P2" diagnostic;
- no `?` propagation, no comprehensions, no `let` contract body.

If intermediate type inference is not already reliable, require explicit type annotations for non-output
intermediate bindings in v0. Output bindings can use the output signature type.

## Required Acceptance

- [x] Parse pure signature-bound contract with one input / one output.
- [x] Parse multiple inputs / multiple outputs.
- [x] Desugar signature inputs to canonical `input` body declarations.
- [x] Desugar body `name [:T] = expr` to canonical `compute`.
- [x] Desugar signature outputs to canonical `output` declarations.
- [x] Output binding may omit type when output signature supplies it.
- [x] Intermediate binding typing specified+tested (explicit `:T` optional, same as canonical `compute`).
- [x] Missing output binding is rejected with a clear diagnostic.
- [x] Duplicate output/body binding is rejected with a clear diagnostic.
- [x] Signature-bound pure contract emits AST-identical (⟹ SIR-identical) form to explicit canonical
      (serde body-parity test).
- [x] Existing explicit canonical contracts remain green.
- [x] IgWeb lowering tests remain green (11).
- [x] Relational / ViewArtifact app fixtures remain green (igniter-web 17 binaries).
- [x] `<-`, `?`, and comprehensions are not implemented.
- [x] `lang/igniter-compiler cargo test` green (137 passed; 0 failed).
- [x] `git diff --check` clean.

---

## Closing Report (2026-06-20)

**Outcome:** the compact `(in: T) -> (out: U) { name = expr }` surface is implemented as a **pure parser
desugar** to canonical `input`/`compute`/`output` — **zero typechecker/emitter/VM change.** Proof doc:
`lab-docs/lang/lab-lang-signature-bound-contract-surface-p2-v0.md`.

**Implementation (parser only):** an optional signature after the contract name (`parse_contract_signature`
+ `parse_sig_param_list`); `build_signature_body` synthesizes `Input` from params, `Compute` from bare
`name [:T] = expr` bindings (reusing `parse_compute_decl`), `Output` from the signature; output computes
inherit the signature type when their binding omits one. Files: `parser.rs` (+151/−3) + new test file. No
lexer change (`<-` deliberately not tokenized → a `<-` binding simply fails to parse, an acceptable
"not-in-P2" outcome).

**Parity (the key proof):** signature-form parsed `body` is **serde-byte-identical** to the explicit form's
(`single_signature_desugars_identically_to_explicit`, `intermediate_and_multi_output_desugar_identically`).
Identical post-parse AST ⟹ identical SemanticIR by construction → node identity / source maps / receipts
untouched. CLI: both forms compile to `status: ok`; the same undeclared-variant input yields the same
`OOF-KIND2` in both.

**Diagnostics:** missing output (`signature output \`z\` is not defined…`) and duplicate body binding both
proven (`OOF-P1`, line-positioned).

**Proof — all green:** igniter-compiler **137 passed / 0 failed** (incl. 5 new); igweb lowering 11;
igniter-web 17 binaries (relational/ViewArtifact intact); `git diff --check` clean.

**Next:** `…-BOUNDARY-BINDINGS-P3` (semantic `<-` for read/effect, `pure` rejects); then
`FALLIBLE-BINDING-READINESS` (`?`) and `COLLECTION-COMPREHENSION-READINESS`.

## Required Proof Doc

Create:

```text
lab-docs/lang/lab-lang-signature-bound-contract-surface-p2-v0.md
```

It must include:

- exact grammar implemented;
- exact desugar path;
- parser/typechecker/emitter files changed;
- SIR parity evidence;
- diagnostics for missing/duplicate outputs;
- type annotation/inference rule for body bindings;
- explicit statement that `<-`, `?`, comprehensions, and block-local `let` are out of scope;
- exact test commands and counts.

Update this card with a closing report.

## Closed Scope

- No semantic `<-` boundary binding.
- No `read` / `effect` signature-bound implementation.
- No `?` propagation.
- No collection comprehensions.
- No `let` contract body.
- No IgWeb syntax changes.
- No runtime / VM behavior changes except what naturally follows from existing canonical lowering.
- No canon claim.

## Suggested Next

If P2 lands cleanly:

1. `LAB-LANG-SIGNATURE-BOUND-BOUNDARY-BINDINGS-P3` — semantic `<-` for `read` / approved effect-boundary
   forms, with `pure` rejection.
2. `LAB-LANG-FALLIBLE-BINDING-READINESS-P1` — `?` propagation over Result/Option.
3. `LAB-LANG-COLLECTION-COMPREHENSION-READINESS-P1` — list rendering ergonomics over `map`/`filter`.
