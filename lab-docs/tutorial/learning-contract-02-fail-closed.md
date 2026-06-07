# Learning Contract 02: Fail Closed

Status: active development / APIs may change / provided as-is

## Intent

Understand fail-closed behavior as a positive teaching principle. The learner
is trying to see refusal as boundary preservation, not as the system being
unusable.

## Contract

The smallest idea is: when intent, capability, profile, or evidence does not
match the declared boundary, Igniter should refuse to proceed and explain why.

## Inputs

You should understand that a contract names its dependencies and that evidence
does not become authority by existing. You do not need to know loader internals.

## Example

Minimal pseudo-source:

```text
intent: read from an external resource
contract ReadNote {
  input note_id: Text
  output note: Text
  capability: file_read
}

caller_profile: no file capabilities granted
```

The intent is clear, but the capability boundary is not satisfied by the caller
profile.

## Run / Inspect

Inspect these proof-first lessons:

- [Capability Passport First Proof](capability-passport-first-proof.md)
- [Expected Output Snippets](expected-output-snippets.md)

Focus on the refusal shape: mismatched capability, tampered artifact, or
ambient access should stop before the action is treated as acceptable.

## Expected Evidence

Expected evidence is a fail-closed result: the action is not accepted, and the
result names the mismatched boundary. In current lab proofs this may appear as a
summary entry, a passport check, or a diagnostic-oriented result.

## Expected Failure

Broken contract exercise:

```text
claim: "A contract may use a resource because the surrounding process has it."
declared capability: none
```

This should fail because ambient authority is not a declared contract boundary.

## Diagnostic

The diagnostic should point to the missing capability, mismatched profile, or
unsupported authority path. A good diagnostic does not merely say "no"; it says
which boundary stopped the composition.

## Reflection

The learner's model changes from "failure means something went wrong" to
"expected refusal can be evidence that the boundary is working."

## Next Composition

You can now move to [Evidence](learning-contract-03-evidence.md), where the
lesson asks what proof is strong enough for a specific claim.
