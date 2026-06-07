# Igniter Learning Contracts

Status: active development / APIs may change / provided as-is

This document defines the first Igniter Lab tutorial learning model. It is not
a syntax reference and it is not canon. It teaches Igniter as a way of thinking:
state an intent, draw a boundary, inspect evidence, understand diagnostics, and
compose only when the smaller contract is legible.

Lab evidence is useful because it is concrete. It is still lab evidence. A lab
lesson can show what a current proof, artifact, or diagnostic does in this
checkout, but it does not create language authority. Canonical language meaning
belongs to `igniter-lang` source documents and accepted decisions.

## Learning By Contract

Learning by contract means each lesson asks the learner to make one small
promise explicit before looking at implementation details.

Instead of starting with "write this syntax," a learning contract starts with:

- What are you trying to understand?
- What boundary must be named?
- What evidence would show the idea worked?
- What should refuse to proceed if the boundary is wrong?
- What does the diagnostic teach you?

This makes refusal part of the lesson. A fail-closed result is not a broken
experience when it is expected and explained. It is the system preserving the
boundary the learner is studying.

## Lesson Contract

Every learning-contract lesson uses the same structure:

- Intent: what the learner is trying to understand.
- Contract: the smallest Igniter idea being learned.
- Inputs: what the learner should already know.
- Example: minimal source or pseudo-source.
- Run / Inspect: what artifact, proof, or diagnostic to inspect.
- Expected Evidence: what proves the concept worked.
- Expected Failure: what should fail and why.
- Diagnostic: how Igniter explains the failure.
- Reflection: what changed in the learner's model.
- Next Composition: what the lesson unlocks.

The repeated structure is deliberate. It trains the reader to ask the same
questions Igniter asks of a program.

## Two Paths

### Beginner Path

Use this path when the learner is new to Igniter:

1. [Orientation](learning-contract-00-orientation.md)
2. [First Contract](learning-contract-01-first-contract.md)
3. [Fail Closed](learning-contract-02-fail-closed.md)
4. [Evidence](learning-contract-03-evidence.md)

The beginner path keeps syntax secondary. The reader first learns what intent,
contract, evidence, and diagnostic mean.

### Proof-First Path

Use this path when the learner already understands the idea and wants concrete
lab artifacts:

1. [Compiler First Proof](compiler-first-proof.md)
2. [Forms First Proof](forms-first-proof.md)
3. [Capability Passport First Proof](capability-passport-first-proof.md)
4. [Expected Output Snippets](expected-output-snippets.md)

The proof-first path should still preserve the same boundary: proof artifacts
are evidence, not canon.

## Teaching Rules

- Start with intent and boundary before syntax.
- Introduce syntax only when it helps make the boundary visible.
- Treat diagnostics as explanations, not only error messages.
- Teach fail-closed behavior as useful discipline.
- Keep examples small enough that the evidence can be inspected.
- Say when a behavior is active lab work and may change.
- Avoid turning lab behavior into canon by wording.
- Avoid framework, runtime, package, or tool details until the learner needs
  them to inspect evidence.

## Compact Glossary

| Term | Meaning In The Tutorial |
| --- | --- |
| intent | The learner or program's stated goal: what it is trying to understand or do. |
| contract | The explicit boundary and promise that makes an intent checkable. |
| evidence | The artifact, receipt, proof result, or diagnostic record that supports a claim. |
| diagnostic | The explanation Igniter gives when a contract cannot be accepted as written. |
| capability | A named permission or resource boundary; no ambient access is assumed. |
| profile | A policy shape that restricts what a contract may do. In lessons, treat it as intent unless a proof says it was checked. |
| composition | Connecting contracts after each smaller contract and evidence boundary is clear. |
| frontier | Active lab exploration where APIs, artifact shapes, and examples may change. |
| canon | The accepted language meaning owned by `igniter-lang`, not by lab proof results. |
| fail-closed | Refusing to proceed when a boundary is missing, mismatched, or unsupported. |

## Boundary

This tutorial model is for Igniter Lab learning. It is provided as-is for
orientation, feedback, and iteration. It does not claim canon authority,
finished APIs, runtime support, or site-ready copy. Site excerpts should be
prepared in a later slice without editing the site from this card.
