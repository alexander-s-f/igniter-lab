# Learning Contract 01: First Contract

Status: active development / APIs may change / provided as-is

## Intent

Understand how an intent becomes a contract. The learner is trying to see why
Igniter asks for explicit inputs, outputs, and evidence before composition.

## Contract

The smallest idea is: a contract turns a goal into something inspectable. It
names what comes in, what comes out, and what evidence should travel with the
result.

## Inputs

You should understand the orientation lesson's boundary: lab evidence helps you
learn, but it is not canon. You do not need to start with complete syntax.

## Example

Minimal pseudo-source:

```text
intent: add two known quantities
contract Add {
  input a: Integer
  input b: Integer
  output sum: Integer
  evidence [a, b]
}
```

Only after the boundary is clear should syntax details matter. The learner
should first ask: what does this claim depend on?

## Run / Inspect

Inspect the existing proof-first lesson:

- [Compiler First Proof](compiler-first-proof.md)

Then inspect the small source example shown in that lesson. You are not trying
to memorize grammar. You are checking whether the contract shape names inputs,
output, and a result boundary.

## Expected Evidence

The evidence is a readable contract shape and, in the proof-first path, a
compiler artifact that records a successful parse/typecheck/emit path for the
current lab fixture.

The important proof is modest: the current lab compiler can produce inspectable
evidence for a tiny contract in this checkout.

## Expected Failure

Broken contract exercise:

```text
intent: add two known quantities
contract Add {
  input a: Integer
  output sum: Integer
  evidence [a, b]
}
```

This should fail because `b` appears in the evidence claim but is not declared
as an input. A contract cannot depend on an unnamed boundary.

## Diagnostic

Igniter should explain the missing or mismatched boundary rather than silently
accepting the shape. In a lesson, the exact diagnostic text may change with the
lab compiler; the teaching point should not change: unnamed dependencies are
not accepted as if they were declared.

## Reflection

The learner's model changes from "a program is a set of steps" to "a program is
a claim whose dependencies and result boundary must be legible."

## Next Composition

You can now move to [Fail Closed](learning-contract-02-fail-closed.md), where a
bad boundary becomes a useful refusal instead of a mysterious failure.
