Card: LAB-PROOF-HYGIENE-P1
Category: core
Agent: [Igniter-Lab Implementation Agent]
Role: implementation-agent
Track: lab-proof-runner-timeout-and-process-hygiene-v0
Route: EXPERIMENTAL / LAB-ONLY / SAFETY-HARDENING
Date: 2026-06-08
Status: complete

---

## Summary

Proof harness safety hardening: unbounded backtick / system() / Open3.capture3
calls in lab proof runners replaced with a bounded helper that kills the child
process group on timeout.

Root cause: a hung `igniter_compiler` was left at ~100% CPU for hours with no
timeout, causing machine overheating.

---

## Deliverables

| Artifact | Path | Status |
|----------|------|--------|
| Shared helper | `tools/proof_harness/bounded_command.rb` | ✅ written |
| Self-test | `tools/proof_harness/test_bounded_command.rb` | ✅ 11/11 PASS |
| Lab doc | `lab-docs/lab/lab-proof-runner-timeout-and-process-hygiene-v0.md` | ✅ written |
| verify_compiler.rb | igniter-compiler/ | ✅ updated |
| verify_g1_canon_loop.rb | igniter-compiler/ | ✅ updated |
| verify_g3_conformance.rb | igniter-compiler/ | ✅ updated |
| verify_g4_body_semantics.rb | igniter-compiler/ | ✅ updated |
| verify_g5_recur.rb | igniter-compiler/ | ✅ updated |
| verify_loops.rb | igniter-compiler/ | ✅ updated |
| verify_oof_r3.rb | igniter-compiler/ | ✅ updated |
| verify_str_core.rb | igniter-compiler/ | ✅ updated |
| verify_str_value_semantics.rb | igniter-compiler/ | ✅ updated |
| verify_unicode_text_runtime.rb | igniter-compiler/ | ✅ updated |
| vm_candidate_proof.rb | igniter-vm/proofs/ | ✅ updated |

---

## Explicit answers

**Which proof runners were updated?**

10 in `igniter-compiler/` (verify_compiler.rb, verify_g1_canon_loop.rb,
verify_g3_conformance.rb, verify_g4_body_semantics.rb, verify_g5_recur.rb,
verify_loops.rb, verify_oof_r3.rb, verify_str_core.rb,
verify_str_value_semantics.rb, verify_unicode_text_runtime.rb) and 1 in
`igniter-vm/proofs/` (vm_candidate_proof.rb). 11 total.

**Which proof runners remain unbounded?**

- `igniter-compiler/proofs/experimental_io_capability_effect_surface_proof.rb`
- `igniter-compiler/proofs/contract_invocation_forms_*.rb`
- `igniter-view-engine/proofs/verify_p*.rb` (invoke compiler)
- Various `igniter-research/ivm-ruby-runtime/examples/` scripts
- `igniter-tbackend/verify_*.rb` (network proofs, different risk profile)

These are P2 candidates. They do not include the scripts that caused the
reported overheating issue.

**Can runaway `igniter_compiler` still be left alive by updated runners?**

No. BoundedCommand kills the full process group (SIGTERM → SIGKILL) on timeout.
Verified by self-test BC-T2: child pid does not respond to `kill(0, pid)` after
cleanup.

**Is timeout treated as proof failure?**

Yes. `result.ok?` is `false` and `result.timed_out` is `true`. There is no code
path in BoundedCommand that returns `ok=true` after a timeout.

**Did any production/canon behavior change?**

No. BoundedCommand wraps the subprocess invocation only. Compiler and VM source
code, canon grammar, language semantics, and public API are all unchanged.

**Exact next recommendation:**

LAB-PROOF-HYGIENE-P2: extend coverage to the remaining uninstrumented proof
runners in `igniter-compiler/proofs/` and `igniter-view-engine/proofs/`.

---

## Timeout policy

| Env var | Default | Scope |
|---------|---------|-------|
| IGNITER_PROOF_TIMEOUT_SECONDS | 10s | compiler/VM binary per fixture |
| IGNITER_PROOF_CARGO_TIMEOUT_SECONDS | 120s | cargo build / run / test |
| IGNITER_PROOF_WIDE_TIMEOUT_SECONDS | 300s | proof-wide guard (caller opt-in) |

---

## Verification

```
ruby tools/proof_harness/test_bounded_command.rb
# → 11/11 PASS

ruby -c igniter-compiler/verify_compiler.rb \
        igniter-compiler/verify_g1_canon_loop.rb \
        igniter-compiler/verify_g3_conformance.rb \
        igniter-compiler/verify_g4_body_semantics.rb \
        igniter-compiler/verify_g5_recur.rb \
        igniter-compiler/verify_loops.rb \
        igniter-compiler/verify_oof_r3.rb \
        igniter-compiler/verify_str_core.rb \
        igniter-compiler/verify_str_value_semantics.rb \
        igniter-compiler/verify_unicode_text_runtime.rb \
        igniter-vm/proofs/vm_candidate_proof.rb
# → Syntax OK

pgrep -l igniter_compiler   # → empty (no stale processes at implementation time)
pgrep -l igniter-vm         # → empty
```
