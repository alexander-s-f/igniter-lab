# LANG-FORM-VOCABULARY-P4 invocation lowering

Status: CONTRIBUTION-ONLY DONE
Date: 2026-06-27
Lane: canon-facing / form vocabulary / invocation lowering
Authority: lab contribution packet for `igniter-lang` owners. No canon compiler
code changed by this packet.

## Decision

Do not implement P4 directly from the lab worktree in this pass. Treat this as
a canon-facing contribution packet that gives the owners a precise, verified
lowering contract and the next narrow implementation slice.

Reason:

- `LANG-FORM-VOCABULARY-P4` changes the language surface: parser, lowering,
  diagnostics, and typed-ref integration.
- `igniter-lang` is the authority repo and was clean during this pass.
- `igniter-lab` was concurrently dirty with unrelated agent work, so mixing a
  canon implementation into this harvest would blur ownership.
- The lab ASK2 precedent is strong enough to contribute a target shape without
  front-running canon.

## Live Canon Facts Verified

### Typed `uses` refs are the cross-module substrate

Command:

```text
cd /Users/alex/dev/projects/igniter-workspace/igniter-lang
ruby -I lib experiments/typed_contract_ref_proof/verify_typed_contract_ref_p5.rb
```

Result:

```text
LANG-TYPED-CONTRACT-REF-PROP-P5 PASS (71/71)
```

Relevant live code:

- `lib/igniter_lang/parser.rb` parses `uses ContractName` and
  `uses Mod.Contract`.
- `lib/igniter_lang/typechecker.rb` resolves typed refs as:
  `local`, `qualified`, or `imported`.
- P5 SIR/manifest evidence carries module attribution and
  `execution_dependency: false`.

This means form invocation lowering should target the typed-ref substrate, not
stringly dynamic dispatch.

### `call_contract` remains same-module and stringly

Live code:

- `lib/igniter_lang/typechecker.rb::build_call_contract_registry` builds a
  registry from contracts in the classified program.
- `infer_call_contract` looks up literal string callees in that separate
  registry.
- Unknown callees fail with:

```text
call_contract: unknown callee '<name>' — not found in this module
```

P5 also proves:

```text
J-03 call_contract unaffected: compute node still present in single-file case
```

Therefore P4 must **not** extend cross-module `call_contract`. Cross-module
reuse belongs to typed `uses` refs.

### Record literal ambiguity is real

Live parser:

```text
parse_record_or_block
  { key: value, ... }
```

The parser consumes `{`, then expects an identifier/key and `:`. A form body
whose children are arbitrary expressions would collide with record/block parsing.

Lab P1 gives the clean disambiguation:

- form bodies are sequences of nodes beginning with trigger words;
- attributes use `key=value`, not `key: value`;
- record literals keep `{ key: value }`;
- one-token lookahead distinguishes a form node from a record field.

## Live Lab Facts Verified

### In-module form invocation model remains green

Command:

```text
ruby -I /Users/alex/dev/projects/igniter-workspace/igniter-lang/lib \
  /Users/alex/dev/projects/igniter-workspace/igniter-lab/frame-ui/igniter-view-engine/proofs/verify_lab_form_invocation_p1.rb
```

Result:

```text
LAB-FORM-INVOCATION-P1 PASS (66/66)
```

This proves the core model:

- resolved form -> `InvocationIntent`;
- no `execute`, `runtime_dispatch`, or `capability_grant`;
- explicit invocation intent and form-lowered intent have identical authority;
- conservativity receipt is present and conservative.

### Cross-module vocabulary proof is useful but stale as a gate

Command:

```text
ruby -I /Users/alex/dev/projects/igniter-workspace/igniter-lang/lib \
  /Users/alex/dev/projects/igniter-workspace/igniter-lab/frame-ui/igniter-view-engine/proofs/verify_lab_form_vocabulary_p1.rb
```

Result:

```text
LAB-FORM-VOCABULARY-P1 FAIL (57/61)
```

The four failures are inventory path drift:

```text
frame-ui/igniter-compiler/src/form_registry.rs missing
frame-ui/igniter-compiler/src/form_resolver.rs missing
```

The model sections still pass: V-1 through V-8 are mechanized in the proof-local
model. So P1 remains design evidence, but it is **not** a current green gate
until the stale inventory checks are rehomed or removed.

### ASK2 lab precedent is working implementation evidence

Packet:

```text
lab-docs/lang/lab-frame-view-form-desugar-and-ask-contribution-p1-v0.md
```

Commit:

```text
aabdee1 frame-ui: ASK2 invocation-form lab precedent (terse col{row{}} -> .ig, e2e)
```

It proves:

```text
.form -> source-to-source desugar -> .ig -> igc -> igniter-vm -> Element -> frame render
```

No canon compiler, VM, or `call_contract` semantics changed.

## Recommended P4 Lowering Contract

### Surface sketch

```text
uses Elements.Col
uses Elements.Row
uses Elements.Leaf
uses Elements.Button

compute view =
  col pad=16 gap=12 {
    row flex=1 gap=12 {
      leaf "Review Ada's lead" select fixed=40
      button "+ add item" add fixed=40
    }
  }
```

Exact vocabulary/import syntax remains canon-owned. The important lowering
rules are independent of spelling.

### Parser node

Add a transient AST node:

```text
form_invocation
  trigger      : String
  attrs        : [{ name, value }]
  text_args    : [literal]        # for leaf/button-like nodes
  word_args    : [identifier]     # e.g. intent word
  children     : [form_invocation]
  source_span  : span
```

This node is pre-runtime. It is erased before VM/runtime output.

### Resolution target

Resolve a form trigger through an explicit vocabulary to a typed contract ref:

```text
trigger col -> resolved typed ref Elements.Col
trigger row -> resolved typed ref Elements.Row
```

Refusal rules:

- unknown trigger: `E-FORM-UNKNOWN`
- trigger not imported by vocabulary/scope: `E-FORM-NO-IMPORT`
- ambiguous trigger across imported vocabularies: `E-FORM-VOCAB-AMBIG`
- unresolved typed ref: reuse `OOF-REF1` / `OOF-REF2` where appropriate
- wrong arity/shape: `E-FORM-ARITY` or `E-FORM-SHAPE`
- malformed attrs: `E-FORM-ATTR`

### Lowering target

Lower to an existing typed invocation/call representation over the resolved
typed ref, not to stringly `call_contract`.

Conceptually:

```text
col attrs children
  -> InvocationIntent(target_ref: Elements.Col, args: [attrs, children])
  -> existing typed call node after resolution
```

The final runtime authority must be identical to writing the explicit invocation.

### Resugaring trace

Carry debug metadata if canon has a location for it:

```text
lowered_from_form:
  trigger: "col"
  vocabulary: "Elements.Forms"
  target_contract: "Elements.Col"
  source_span: ...
```

This is diagnostic/debug metadata only. It must not affect artifact authority.

## Why `call_contract` Is Explicitly Out Of Scope

The lab view pressure originally looked like "we need cross-module
`call_contract`". Verify-first changed that:

- cross-module typed refs are already live and attributed;
- `call_contract` is deliberately stringly and same-module;
- extending it would make the weaker surface do what the stronger typed-ref
  surface already owns;
- form lowering can solve nesting and cross-module reuse through typed refs.

So P4 should preserve:

```text
call_contract("Leaf", ...) across modules -> still not supported
```

and add:

```text
leaf "Title" select -> typed ref invocation of Elements.Leaf
```

## Minimal Next Implementation Card

Recommended next card:

```text
LANG-FORM-VOCABULARY-P4-CANON-IMPL-P1
```

Goal:

Implement the smallest canon slice in `/Users/alex/dev/projects/igniter-workspace/igniter-lang`:

1. Parse one explicit vocabulary/import shape chosen by canon owners.
2. Parse invocation-form bodies with trigger words + `key=value` attrs.
3. Resolve triggers through typed `uses` refs.
4. Lower to an existing typed invocation/call IR with `lowered_from_form`
   metadata.
5. Prove the lab `col/row/leaf/button` fixture lowers to the same explicit
   invocation shape.

Acceptance:

- typed-ref P5 proof remains `71/71`;
- record literals still parse unchanged;
- unknown trigger fails closed;
- ambiguous imported trigger fails closed;
- `call_contract` cross-module behavior unchanged;
- one lab `col { row { leaf } }` specimen compiles through canon and emits the
  expected typed call/lowering shape;
- no runtime/VM/capability authority is added.

## Current P4 Closure

This packet closes the current lab card as contribution-only. It does not claim
canon implementation. It gives the next implementation owner a verified boundary
and a small acceptance matrix.
