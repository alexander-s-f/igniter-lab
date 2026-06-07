# Learning Contract 00: Orientation

Status: active development / APIs may change / provided as-is

## Intent

Understand how to learn Igniter without starting from syntax. The learner is
trying to see the shape of the discipline: intent first, contract second,
evidence third, composition later.

## Contract

The smallest idea is: a lesson should name the boundary it is teaching before it
asks the learner to trust an artifact.

## Inputs

You should already know that `igniter-lab` is a frontier workspace and that lab
evidence is not canon. You do not need to know the grammar, runtime candidates,
or package internals.

## Example

Minimal pseudo-source:

```text
intent: understand whether a claim has support
contract: every accepted claim must name its evidence
evidence: inspectable artifact or diagnostic
```

The important part is not syntax. The important part is that the claim cannot
stand alone.

## Run / Inspect

Inspect these documents:

- [Repository README](../../README.md)
- [Tutorial README](README.md)
- [Learning Contracts](igniter-learning-contracts.md)

Look for three boundaries:

- `igniter-lab` provides lab evidence.
- `igniter-lang` owns canon language meaning.
- Tutorial lessons teach a way of reading evidence.

## Expected Evidence

You can point to the sentence or table that says lab behavior is evidence, not
canon. You can also identify the first four learning-contract lessons and the
two paths through them.

## Expected Failure

Broken contract exercise:

```text
claim: "The lab proof makes this language behavior canon."
evidence: "A local lesson mentions it."
```

This should fail because a lab lesson is not an authority route.

## Diagnostic

The diagnostic is conceptual: evidence and authority have been confused. The
lesson can show a current artifact, but the artifact needs an accepted language
route before it can become canon.

## Reflection

The learner's model changes from "documentation tells me what is true" to
"documentation tells me what claim is being made, what evidence supports it,
and which authority surface can accept it."

## Next Composition

You can now move to [First Contract](learning-contract-01-first-contract.md),
where a small intent becomes a checkable contract.
