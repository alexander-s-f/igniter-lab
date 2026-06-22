# LAB-HYGIENE-STATUS-CLEAN-P2 - refresh stale lab STATUS known-red section

Status: CLOSED - 2026-06-22
Lane: workspace hygiene / status
Type: documentation cleanup with live test evidence
Delegation code: OPUS-HYGIENE-STATUS-CLEAN-P2
Date: 2026-06-22
Skill: idd-agent-protocol

## Context

Gemini drift forensics found `lab-docs/STATUS.md` still claiming old known-red tests:

- 4 `loop_conformance_tests` failures in `lang/igniter-compiler`
- 1 `vm_candidate_proof_tests` failure in `lang/igniter-vm`

Codex spot-check after the report showed:

```text
lang/igniter-compiler cargo test --test loop_conformance_tests -> 14 passed
lang/igniter-vm       cargo test --test vm_candidate_proof_tests -> 9 passed
```

## Goal

Update `lab-docs/STATUS.md` so the front door no longer teaches stale red-test mythology.

## Verify first

Re-run the targeted commands yourself:

```text
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab/lang/igniter-compiler
cargo test --test loop_conformance_tests

cd /Users/alex/dev/projects/igniter-workspace/igniter-lab/lang/igniter-vm
cargo test --test vm_candidate_proof_tests
```

Do not claim whole-workspace green unless you actually run the whole relevant suite.

## Acceptance

- [x] `lab-docs/STATUS.md` has an updated date.
- [x] The old known-red section is removed or replaced with "cleared by targeted recheck" evidence.
- [x] Exact commands and counts are recorded.
- [x] The status doc still says lab evidence is not canon/production authority.
- [x] No code changes.
- [x] `git diff --check` clean.

## Closed scope

No broad status-board rewrite, no implementing fixes, no claiming full suite green unless run.

## Next

After this, `LAB-HYGIENE-NET-P9-PATHS-P5` or resume main wave.

## Closing Report

Closed on 2026-06-22.

Updated `lab-docs/STATUS.md` so the front-door status no longer teaches stale
known-red test claims. The lab authority disclaimer remains in place: lab
evidence is not canon language specification, public runtime support, Reference
Runtime, release, or production surface.

Targeted rechecks:

```text
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab/lang/igniter-compiler
cargo test --test loop_conformance_tests
-> 14 passed, 0 failed

cd /Users/alex/dev/projects/igniter-workspace/igniter-lab/lang/igniter-vm
cargo test --test vm_candidate_proof_tests
-> 9 passed, 0 failed
```

Scope note: this is a targeted recheck only. It clears the stale known-red
entries; it does not claim whole-repo or whole-workspace green.

Verification:

```text
git diff --check
```

No code files changed.
