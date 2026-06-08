# Lab Proof Runner Timeout and Process Hygiene

Status: complete
Date: 2026-06-08
Card: LAB-PROOF-HYGIENE-P1
Authority: lab-only — not canon, not production, not stable API

---

## Problem Statement

A lab run left multiple `igniter_compiler` processes running at ~100% CPU for
hours, causing machine overheating. Root cause: every proof runner invoked
external processes (compiler, VM, cargo) via Ruby's backtick operator
`` `cmd` `` or `system()` — both of which have no timeout and no process-group
cleanup. A hung compiler silently blocked the proof, and the child was never
killed.

---

## Fix Summary

A shared helper `tools/proof_harness/bounded_command.rb` replaces every
unbounded external invocation in high-risk proof runners.

**Guarantee:** no proof runner that uses BoundedCommand can leave an
`igniter_compiler`, `igniter-vm`, `rustc`, or `cargo` child process alive
after failure or timeout.

---

## Helper: `tools/proof_harness/bounded_command.rb`

```
BoundedCommand.run(cmd, label:, timeout:) → Result
BoundedCommand.run_checked(cmd, label:, timeout:) → Result   # prints FAIL/TIMEOUT if not ok
BoundedCommand.print_result(result)                          # print compact failure summary
```

### Timeout policy (seconds)

| Env var | Default | Applies to |
|---------|---------|------------|
| `IGNITER_PROOF_TIMEOUT_SECONDS` | 10 | compiler/VM binary per fixture |
| `IGNITER_PROOF_CARGO_TIMEOUT_SECONDS` | 120 | cargo build / cargo run / cargo test |
| `IGNITER_PROOF_WIDE_TIMEOUT_SECONDS` | 300 | proof-wide guard (not auto-applied; caller opt-in) |

### Process cleanup

- Spawns each child in its own process group (`pgroup: true` in `Open3.popen3`).
- On timeout: SIGTERM → 300ms grace → SIGKILL to the entire process group.
- Pipe drain happens in background threads (prevents deadlock).
- Belt-and-suspenders: SIGKILL attempt after wait in case group has new children.
- `Errno::ESRCH` / `Errno::EPERM` from kill are silently ignored (process already gone).

### Timeout reporting

On timeout, `print_result` emits:

```
[TIMEOUT] compile:fixture_name
          elapsed=10.312s  limit=10s  pid=12345
          stdout: ...last 3 lines...
          stderr: ...last 3 lines...
```

Timeout is always reported as FAIL. `result.ok?` is `false`. `result.timed_out`
is `true`. There is no code path that returns `ok=true` after a timeout.

---

## Proof runners updated

### igniter-compiler/

| Script | Compiler | Cargo build | VM | Change |
|--------|----------|-------------|-----|--------|
| `verify_compiler.rb` | ✅ bounded | ✅ bounded | — | compile loop + build guard |
| `verify_g1_canon_loop.rb` | ✅ bounded | ✅ bounded | ✅ bounded | full vertical slice |
| `verify_g3_conformance.rb` | ✅ bounded | ✅ bounded | ✅ bounded | compile_src + run_vm + build |
| `verify_g4_body_semantics.rb` | ✅ bounded | ✅ bounded | — | compile_src + build |
| `verify_g5_recur.rb` | ✅ bounded | ✅ bounded | — | compile_src + build |
| `verify_loops.rb` | ✅ bounded | ✅ bounded | ✅ bounded | inline calls |
| `verify_oof_r3.rb` | ✅ bounded | ✅ bounded | — | compile_src + build |
| `verify_str_core.rb` | ✅ bounded | ✅ bounded | — | compile_src + build |
| `verify_str_value_semantics.rb` | ✅ bounded | ✅ bounded | — | compile_src + build |
| `verify_unicode_text_runtime.rb` | ✅ bounded | — (binary already built) | ✅ bounded | compile_src + run_vm |

### igniter-vm/proofs/

| Script | Change |
|--------|--------|
| `vm_candidate_proof.rb` | `run_cmd` replaced — was `Open3.capture3` (unbounded), now BoundedCommand |

---

## Proof runners NOT updated (and why)

| Script | Reason |
|--------|--------|
| `igniter-compiler/proofs/experimental_io_capability_effect_surface_proof.rb` | Uses backtick for compiler; lower risk (short compiler invocations). Candidate for P2. |
| `igniter-compiler/proofs/contract_invocation_forms_*.rb` | Same pattern as above. Candidate for P2. |
| `igniter-apps/benchmark-app/verify_bench.rb` | Benchmark runner; different risk profile. |
| `acts-as-tbackend/verify_shadow.rb` | Backtick for shadow comparison; no long-running binary risk. |
| `igniter-tbackend/verify_*.rb` | Use Open3 for network service proofs; timeout approach differs. |
| `igniter-view-engine/proofs/verify_p*.rb` | Invoke compiler; candidate for P2. |
| `igniter-research/ivm-ruby-runtime/examples/*.rb` | Research scripts; process hygiene reviewed case-by-case. |
| `igniter-stdlib/proofs/*.rb` | No external binary invocations confirmed. |
| `igniter-stdlib/verify_stdlib.rb` | Uses Fiddle (in-process FFI); no child process risk. |

---

## Can a runaway `igniter_compiler` still be left alive?

After this change:

- **Updated runners**: NO. BoundedCommand kills the full process group on
  timeout. The `test_bounded_command.rb` self-test proves `kill(0, pid)` returns
  `ESRCH` (no such process) after cleanup.

- **Uninstrumented runners** (proofs/ subdirectory, view-engine, research):
  YES, still possible. They are in the P2 candidate list above.

---

## Remaining risk

| Risk | Severity | Mitigation |
|------|----------|------------|
| `experimental_io_capability_effect_surface_proof.rb` backtick loops | Medium | P2 candidate |
| `view-engine` proof runners invoking compiler | Medium | P2 candidate |
| `research/ivm-ruby-runtime` research scripts | Low-medium | reviewed separately |
| cargo hangs during build (P1 already covers this) | Low (120s limit) | ✅ mitigated |

---

## Verification

### Self-test (11/11 PASS)

```
ruby tools/proof_harness/test_bounded_command.rb
```

| Check | What it proves |
|-------|---------------|
| BC-T1 | timeout detected for long-sleep command |
| BC-T2 | timed-out child pid is not alive after cleanup |
| BC-T3 | timeout returns ok?=false (not silently PASS) |
| BC-T4 | elapsed >= timeout threshold |
| BC-T5 | exit-0 command returns ok?=true |
| BC-T6/b | non-zero exit returns ok?=false, timed_out=false |
| BC-T7 | stdout captured correctly |
| BC-T8 | stderr captured correctly |
| BC-T9 | command-not-found returns ok?=false |
| BC-T10 | print_result emits [TIMEOUT] label |

### Syntax check

All 11 updated scripts pass `ruby -c`.

### No stale processes

`pgrep igniter_compiler` and `pgrep igniter-vm` both returned empty at time of
implementation.

---

## Process scan guidance

Before and after a lab proof run involving compiler/VM:

```bash
pgrep -l igniter_compiler
pgrep -l igniter-vm
pgrep -l "cargo"      # broader; filter by ppid if needed
```

If stale processes are found after an updated runner, something bypassed
BoundedCommand — check for uninstrumented backtick calls.

---

## NOT changed

- Canon language semantics — unchanged
- Compiler behavior — unchanged (BoundedCommand only wraps invocation)
- Public API — unchanged
- CI / release / packaging — not touched
- Production / runtime — not touched

---

## Next recommendation

**LAB-PROOF-HYGIENE-P2**: Extend BoundedCommand to the remaining proof runners
listed in the "not updated" section above:
- `igniter-compiler/proofs/experimental_io_capability_effect_surface_proof.rb`
- `igniter-compiler/proofs/contract_invocation_forms_*.rb`
- `igniter-view-engine/proofs/verify_p*.rb`
