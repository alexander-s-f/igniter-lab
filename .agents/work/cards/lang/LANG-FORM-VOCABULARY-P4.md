# LANG-FORM-VOCABULARY-P4

Status: CLOSED (contribution-only, 2026-06-27)
Route: standard / canon-facing / form vocabulary / invocation lowering
Skill: idd-agent-protocol
Depends-On: `LANG-TYPED-CONTRACT-REF-P5`, `LANG-FORM-VOCABULARY-P1/P2/P3` as owned by canon

## Goal

Wire the lab ASK2 precedent into the canon form-vocabulary track by specifying
and, if authorized in `igniter-lang`, implementing the narrow invocation-form
lowering slice:

```text
col pad=16 gap=12 { row { leaf "Title" select } }
```

lowers to ordinary typed invocation intent / contract call structure over
`uses` references, without extending cross-module `call_contract`.

## Current Authority

Canon source and canon proposal docs win. Lab evidence is input, not authority.

Read first:

- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/lab-docs/lang/lab-frame-view-form-desugar-and-ask-contribution-p1-v0.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/frame-ui/igniter-frame/src/igv_desugar.rs`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/lab-docs/governance/lab-contract-invocation-forms-in-module-proof-v0.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/lab-docs/governance/lab-form-vocabulary-cross-module-coherence-proof-v0.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lang/lib/igniter_lang/parser.rb`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lang/lib/igniter_lang/typechecker.rb`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lang/lib/igniter_lang/multifile_resolver.rb`

Known live facts to verify:

- `LANG-TYPED-CONTRACT-REF-P5` made cross-module typed `uses` refs work;
- it explicitly did not make `call_contract` cross-module;
- form invocation theory lowers to `InvocationIntent`, not runtime authority;
- lab P1 proves a concrete `col { row { leaf } }` source-to-source lowering
  through real `.ig` compile/run/render.

## Scope

Allowed:

- Produce a canon-facing readiness/implementation packet for P4.
- If working in the canon repo is authorized, add the smallest parser/lowering
  slice for invocation forms using typed refs.
- Add fixtures proving the lab `col/row/leaf/button` example lowers to the same
  explicit call shape.
- Add fail-closed diagnostics for malformed form bodies.
- Preserve resugaring/lowering trace metadata if canon already has a place for
  it.

Closed:

- Do not extend `call_contract` cross-module.
- Do not add runtime dispatch or capability authority to forms.
- Do not add optional/default fields.
- Do not make `.form` a public dialect unless canon owners explicitly choose
  that packaging.
- Do not mutate frame-ui as part of the canon lowering implementation.

## Grammar Constraint From Lab Evidence

Use the lab precedent's ambiguity resolution unless canon owners choose a
different one:

- form body is a sequence of nodes beginning with trigger words;
- attributes use `key=value`, not `key: value`;
- record literals keep `{ key: value }`;
- one-token lookahead should distinguish form-body nodes from record fields.

This keeps form bodies from colliding with record literals.

## Questions To Answer

1. Is P4 implementation authorized in `igniter-lang`, or should this remain a
   canon contribution packet only?
2. What exact AST node represents a form invocation before lowering?
3. Does lowering target an existing typed call/invocation node, or a new
   metadata-only `InvocationIntent` that is erased before runtime?
4. Where does cross-module resolution happen: through existing `uses` ref
   resolution only?
5. What diagnostics distinguish unknown trigger, wrong arity, malformed attrs,
   and ambiguous body?
6. How is the lab desugar output used as a parity reference?

## Acceptance

- [x] Canon live state is verified; no stale lab claim is treated as authority.
- [x] Cross-module `call_contract` remains unchanged and explicitly out of
      scope.
- [x] `col/row/leaf/button` fixture lowers to a normal typed invocation/call
      shape over `uses` refs in the contribution contract; implementation is the
      next canon-owned card.
- [x] Record literal syntax remains unambiguous.
- [x] Malformed forms fail closed with diagnostics in the contribution
      acceptance matrix; implementation is the next canon-owned card.
- [x] Existing typed contract ref tests remain green.
- [x] If implementation is not authorized, a contribution packet is produced
      instead with exact next-card acceptance.
- [x] `git diff --check` passes in whichever repo is touched.

## Suggested Verification

If implementing in canon:

```bash
cd /Users/alex/dev/projects/igniter-workspace/igniter-lang
ruby -I lib test/**/*typed_contract_ref*  # adapt to actual test layout after verify-first
ruby -I lib test/**/*form*                # adapt to actual test layout after verify-first
git diff --check
```

If producing contribution only:

```bash
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab
cargo test --manifest-path frame-ui/igniter-frame/Cargo.toml --test ig_runtime_bridge_tests
git diff --check
```

## Required Packet

Create one of:

```text
lab-docs/lang/lang-form-vocabulary-p4-invocation-lowering-v0.md
```

or, if the canon repo owns docs/cards elsewhere, create the equivalent packet in
that repo and include a lab pointer back to the P1 precedent.

The packet must state whether this was implementation or contribution-only,
what remains for canon owners, and why `call_contract` was not expanded.

## Closing Report

Closed as **contribution-only**, not canon implementation.

Packet:

```text
lab-docs/lang/lang-form-vocabulary-p4-invocation-lowering-v0.md
```

Key decision:

- `LANG-TYPED-CONTRACT-REF-P5` is the cross-module substrate.
- Cross-module `call_contract` remains explicitly out of scope.
- P4 lowering should parse form invocations into a transient
  `form_invocation` node, resolve triggers through explicit vocabulary/typed
  refs, and lower to ordinary typed invocation/call IR with optional
  `lowered_from_form` debug metadata.

Verification:

```text
ruby -I lib experiments/typed_contract_ref_proof/verify_typed_contract_ref_p5.rb
=> LANG-TYPED-CONTRACT-REF-PROP-P5 PASS (71/71)

ruby -I igniter-lang/lib igniter-lab/frame-ui/igniter-view-engine/proofs/verify_lab_form_invocation_p1.rb
=> LAB-FORM-INVOCATION-P1 PASS (66/66)
```

Drift found:

```text
verify_lab_form_vocabulary_p1.rb => 57/61, failing only stale inventory paths
to frame-ui/igniter-compiler/src/form_registry.rs and form_resolver.rs.
```

That proof remains useful design evidence for V-1..V-8, but is not a current
green gate until rehomed.

Next route:

```text
LANG-FORM-VOCABULARY-P4-CANON-IMPL-P1
```

Only run that implementation on a clean canon-owned pass in
`/Users/alex/dev/projects/igniter-workspace/igniter-lang`.
