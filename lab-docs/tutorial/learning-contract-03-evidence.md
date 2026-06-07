# Learning Contract 03: Evidence

Status: active development / APIs may change / provided as-is

## Intent

Understand what evidence can and cannot prove. The learner is trying to separate
an inspectable lab artifact from a broader claim about language meaning.

## Contract

The smallest idea is: every claim needs evidence with a named scope. Evidence
should support exactly the claim it can support, and no more.

## Inputs

You should understand orientation, first contract, and fail-closed behavior. You
should also know that current lab proof shapes may change.

## Example

Minimal pseudo-source:

```text
claim: "This fixture produced a compiler artifact in the current lab checkout."
evidence: compilation report for the fixture
scope: one fixture, one lab package, one current artifact shape
```

The evidence is useful because it is bounded.

## Run / Inspect

Inspect one proof-first lesson and one support file:

- [Compiler First Proof](compiler-first-proof.md)
- [Expected Output Snippets](expected-output-snippets.md)

Look for the difference between:

- an artifact that proves a local command or fixture path worked;
- a claim that would require an accepted language route.

## Expected Evidence

Good evidence includes a named artifact, a bounded command or inspection path,
and a claim that does not exceed the artifact. For example: "this current lab
fixture emitted an inspectable bundle" is appropriately bounded.

## Expected Failure

Broken contract exercise:

```text
artifact: current lab compilation report
claim: "All future syntax and APIs will keep this shape."
```

This should fail because the artifact does not prove future shape, policy, or
canon acceptance.

## Diagnostic

The diagnostic is a claim-boundary mismatch. The evidence may be valid, but the
claim is too large. The correction is to narrow the claim or route it through a
canon decision.

## Reflection

The learner's model changes from "evidence means proof" to "evidence proves a
bounded claim, and the boundary must travel with it."

## Next Composition

You can now compose into proof-first lessons: compiler evidence, forms
evidence, capability evidence, and later site-ready excerpts. Keep the claim
boundary attached as the lessons move.
