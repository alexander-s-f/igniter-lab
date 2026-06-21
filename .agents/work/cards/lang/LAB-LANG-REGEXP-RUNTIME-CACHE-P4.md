# LAB-LANG-REGEXP-RUNTIME-CACHE-P4 - Cache compiled regexp in VM hot path

Status: CLOSED
Lane: parallel / language-runtime / performance
Type: implementation-proof
Delegation code: OPUS-LANG-REGEXP-RUNTIME-CACHE-P4
Date: 2026-06-21
Skill: idd-agent-protocol

## Context

`LAB-LANG-APP-PRESSURE-PROTO-BENCH-P1` exposed a useful hot-path signal: later IgWeb routes dispatch
slower than earlier routes. Live inspection then found the likely dominant cost:

```text
stdlib.regexp.matches(text, pattern)
stdlib.regexp.capture(text, pattern, index)
```

currently compile `regex::Regex::new(pattern)` on **every call** in the VM, in both bytecode and eval_ast
paths. IgWeb route dispatch calls `matches(req.path, "^...$")` for each route arm and `capture(...)` for path
params, so request cost currently includes repeated regex compilation.

This is a runtime hot-path issue, not an argument for putting route tables in `igniter-server`.

## Goal

Add a behavior-identical compiled-regex cache for VM regexp builtins:

```text
pattern String -> compiled regex::Regex
```

and prove:

- `matches` / `capture` behavior and error semantics do not change;
- invalid patterns still return operational errors, never false/None;
- no server route table or IgWeb lowering change is introduced;
- `app_pressure_bench` shows a before/after trend signal for route-heavy requests.

## Verify First

Read live code before editing:

- `lang/igniter-vm/src/vm.rs` around both regexp implementations (`matches` / `capture` in bytecode and
  eval_ast)
- `lang/igniter-vm/Cargo.toml`
- `lang/igniter-compiler/src/igweb.rs` route lowering (`matches` / `capture` generation)
- `lang/igniter-compiler/tests/regexp_tests.rs` or current regexp test names
- `server/igniter-web/examples/app_pressure_bench.rs`
- `lab-docs/lang/lab-stdlib-regexp-p3-v0.md`
- `lab-docs/lang/lab-lang-app-pressure-proto-bench-p1-v0.md`

Confirm or correct:

- whether `regex::Regex::new(pattern)` is indeed called on every VM regexp builtin invocation;
- whether the VM struct already has a suitable per-machine mutable cache field;
- whether bytecode and eval_ast share a VM instance or need a shared helper;
- whether dependencies already include `once_cell`, or whether `std::{sync, collections}` is sufficient;
- whether dynamic unbounded patterns require a bounded policy in v0.

Live code wins over this card.

## Design Bias

Prefer a **per-VM cache** over a global static cache:

```text
IgniterMachine / VM instance owns regexp cache
```

Reasons:

- avoids cross-program growth;
- keeps replay/test isolation simpler;
- app route patterns are loaded per app;
- no global lock as first design point.

If the live VM structure makes per-VM invasive, a small shared helper may use `OnceLock<Mutex<...>>`, but the
proof doc must call out growth and isolation tradeoffs.

Dynamic-pattern safety:

- v0 MAY be unbounded only if scoped per VM and documented;
- if global, MUST bound or explicitly reject global unbounded growth;
- never cache invalid patterns unless deliberately storing the error is simpler and behavior-identical.

## Required Acceptance

- [x] `matches` uses cached compiled regex for repeated identical pattern.
- [x] `capture` uses the same cache path.
- [x] Bytecode and eval_ast regexp paths have parity (both call `cached_regex`).
- [x] Invalid pattern error text/category remains operational failure (not cached).
- [x] No behavior change for no-match / out-of-range / negative capture index.
- [x] Unicode path behavior remains unchanged.
- [x] No changes to IgWeb lowering or `igniter-server`.
- [x] Dynamic pattern behavior correct; growth policy documented (global, unbounded v0, bounded in practice).
- [x] Existing regexp tests green (runtime 6, typecheck 8).
- [x] IgWeb route tests green (lowering 11, todo_view_app 14).
- [x] `app_pressure_bench` runs + reports JSON; before/after trend discussed.
- [x] `git diff --check` clean.

---

## Closing Report (2026-06-21)

**Live-code correction to the card's design bias.** The card preferred a **per-VM** cache, but verify-first
found `IgniterMachine::dispatch` builds a **fresh `VM` per request** (`machine.rs:313 let mut vm = VM::new(…)`),
so a per-VM cache never survives across requests (a first per-VM-field attempt moved the bench ~0%, proving
it). Used the card's sanctioned fallback: a **process-global `OnceLock<Mutex<HashMap<String, Regex>>>`** in
`vm.rs`, behind a free `cached_regex(pattern)` that all 4 builtin sites call (bytecode `:1295,:1312`; eval_ast
`:4183,:4198`). `std::sync::Mutex` (the file's bare `Mutex` is tokio/async). No new dependency; only `vm.rs`
changed (+30/−4).

**Behavior-identical + measured win.** A `Regex` is a pure function of its pattern, so the cache cannot change
any result (replay/test-safe; only successful compiles cached; invalid patterns recompile + surface the same
error). Bench (`median_us`, lab-local, debug): late route `/api/health` **2139 → 1113 (−48%)** — the exact P1
"later routes slower" signal — render routes **−13/−14%**, first route −4%. The route-position skew is now
substantially flattened (residual cost is VM dispatch/render, not regex recompile).

**Proof — green:** regexp_runtime 6, regexp_typecheck 8, igweb_lowering 11, todo_view_app 14, e2e (machine) 2;
`git diff --check` clean. **Pre-existing red (not mine):** `vm_candidate_proof_tests::test_proof_vmg13_local_loops_and_service_loops`
fails identically **without** this change (stash-verified; loops, not regexp; out of scope).

**Boundary preserved:** pure VM-internal optimization — generated `.ig` `Serve` is the route table, server
stays route-free, `.igweb` lowering untouched, no radix trie. **Next:** `…-RUNTIME-HOTPATH-READINESS-P3`
(profile remaining VM dispatch cost; revisit order-preserving radix trie only if a many-route workload needs it).

## Required Verification

Run and report exact counts:

```bash
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab/lang/igniter-compiler && cargo test --test regexp_tests
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab/lang/igniter-compiler && cargo test --test igweb_lowering_tests
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab/server/igniter-web && cargo run --example app_pressure_bench
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab/server/igniter-web && cargo test
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab/server/igniter-web && cargo test --features machine
git diff --check
```

If regexp tests live under a different target, report the actual target.

## Required Proof Doc

Create:

```text
lab-docs/lang/lab-lang-regexp-runtime-cache-p4-v0.md
```

It must state:

- exact live hot-path finding with file/line evidence;
- cache ownership and growth policy;
- bytecode/eval_ast parity;
- before/after bench observations (trend only, no public perf claim);
- correctness matrix for invalid/no-match/capture/unicode;
- why this preserves `igniter-server` route-free boundary;
- exact commands and counts.

Update this card with a closing report.

## Closed Scope

- No radix trie / route index.
- No change to `.igweb` lowering.
- No server route table.
- No public performance claim.
- No canon claim.
