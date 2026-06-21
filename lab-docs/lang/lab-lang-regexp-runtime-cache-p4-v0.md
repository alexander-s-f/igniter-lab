# lab-lang-regexp-runtime-cache-p4-v0 — cache compiled regexp in the VM hot path

**Card:** `LAB-LANG-REGEXP-RUNTIME-CACHE-P4` · **Delegation:** `OPUS-LANG-REGEXP-RUNTIME-CACHE-P4`
**Status:** CLOSED (lab implementation-proof) — the VM `matches`/`capture` builtins now reuse a
**process-global compiled-regex cache** instead of recompiling on every call. Behavior-identical; the
bench shows a real cross-request improvement on the late-route hot path (the signal that started this).
**Only `igniter-vm/src/vm.rs` changed; no IgWeb lowering, no server route table, no canon claim.**
**Authority:** Lab runtime. Pure execution optimization; the generated `.ig` `Serve` contract is unchanged.

## Live hot-path finding (file:line)

1. **Regex recompiled per call.** `vm.rs` compiled `regex::Regex::new(pattern)` **inline on every**
   `matches`/`capture` invocation — in **both** execution paths:
   - bytecode path (`execute_with_grants`, `&self`): `vm.rs:1269` (matches), `:1286` (capture);
   - eval_ast path (free fn `eval_ast(…, vm: &VM)`): `vm.rs:4157` (matches), `:4172` (capture).
   IgWeb route dispatch runs `matches(req.path, "^…$")` for each route arm + `capture(...)` per param, so
   every request recompiled every pattern it touched — wasted work scaling as `routes × requests`.
2. **Per-VM caching would NOT work** (a key live-code correction to the card's design bias):
   `IgniterMachine::dispatch` builds a **fresh `VM` per request** — `machine.rs:313` `let mut vm = VM::new(...)`.
   So a per-VM cache never survives across requests, and within a single request each route pattern appears
   once → **no within-request reuse either**. (Measured: a first per-VM-field attempt moved the bench by
   ~0%, confirming the granularity was wrong.)

The card anticipated this — *"if per-VM is invasive, a small shared helper may use `OnceLock<Mutex<…>>`,
call out growth/isolation tradeoffs."* That is the chosen design.

## What changed (vm.rs only)

A module-level cache + a free function the four builtin sites call:
```rust
static REGEX_CACHE: OnceLock<Mutex<HashMap<String, regex::Regex>>> = OnceLock::new();

fn cached_regex(pattern: &str) -> Result<regex::Regex, regex::Error> {
    let cache = REGEX_CACHE.get_or_init(|| Mutex::new(HashMap::new()));
    if let Some(re) = cache.lock().unwrap().get(pattern) { return Ok(re.clone()); }
    let re = regex::Regex::new(pattern)?;                 // only successful compiles are cached
    cache.lock().unwrap().insert(pattern.to_string(), re.clone());
    Ok(re)
}
```
All four sites changed `match regex::Regex::new(pattern)` → `match cached_regex(pattern)`, keeping the
exact surrounding `Ok/Err` arms and error-format strings. `std::sync::Mutex` (not the file's `tokio::sync::Mutex`)
because the critical section never crosses an `await`; the cheap (Arc-backed) `Regex` clone is matched
outside the lock. **No new dependency** (`regex` already a dep; `OnceLock`/`Mutex`/`HashMap` are std).

## Cache ownership & growth policy

- **Ownership:** process-global (`OnceLock`), because the VM is per-dispatch (above). Persists across all
  dispatches → a route's anchored patterns compile **once process-wide**.
- **Growth:** keyed by pattern **string**; an app's route-regex set is small and stable, so v0 leaves it
  **unbounded** (documented). A future bound (LRU / per-machine cache) is a follow-on only if a real
  many-pattern workload appears.
- **Isolation / replay safety:** a compiled `Regex` is a **pure function of its pattern string**, so a
  shared/cached `Regex` matches **identically** to a freshly compiled one — sharing across programs/tests
  **cannot change any result**, and replay stays deterministic. This is why a global cache is safe here.

## Bytecode / eval_ast parity

Both paths route through the same `cached_regex` (bytecode `vm.rs:1295,1312`; eval_ast `vm.rs:4183,4198`),
so they cannot diverge on compile/cache behavior.

## Before / after bench (trend only — NOT a public perf claim)

`cargo run --example app_pressure_bench`, debug build, one machine, `median_us`:

| Scenario | P1 (no cache) | P4 (global cache) | Δ |
|---|---|---|---|
| `dispatch_render_list_html` | 1320 | 1150 | −13% |
| `dispatch_render_pending_html` | 1423 | 1217 | −14% |
| `dispatch_respond_view_json` (`/`, first route) | 1105 | 1061 | −4% |
| **`dispatch_respond_plain` (`/api/health`, late route)** | **2139** | **1113** | **−48%** |

The biggest win is the **late route** (`/api/health`), which runs the most `matches()` arms — exactly the
P1 signal ("later routes dispatch slower"). The route-position skew is now **substantially flattened**
(late route 1113 ≈ the render routes 1061–1217, vs ~2× before), so the remaining per-request cost is now
dominated by actual VM dispatch/render, not regex recompilation. Lab-local trend only.

## Correctness matrix (behavior-identical)

| Case | Before | After |
|---|---|---|
| valid pattern, match / no-match | `re.is_match` | identical (same `Regex`) |
| `capture` index in range / out of range / **negative** | `Nil` on neg, `None`→`Nil` on miss | identical |
| **invalid pattern** | `Err("…: invalid pattern: {e}")` | identical — not cached, recompiles, same error |
| **Unicode** | `regex` crate Unicode-default | identical (same compile flags) |

Proven green: `regexp_runtime_tests` 6/6, `regexp_typecheck_tests` 8/8, `igweb_lowering_tests` 11/11
(generated `matches`/`capture` unchanged), `todo_view_app_tests` 14/14, e2e `--features machine` 2/2.

## Why this preserves the `igniter-server` route-free boundary

The cache is a **pure VM-internal execution detail**. The route table is still the generated `.ig` `Serve`
contract; the server still never sees patterns; `.igweb` lowering is untouched; no radix trie / route index
was added. The optimization changes *how fast* the same `matches`-chain runs, never *what* it means —
determinism, replay, and inspectability are unchanged.

## Commands & counts

```text
$ cd lang/igniter-vm       && cargo test --test regexp_runtime_tests   → 6 passed
$ cd lang/igniter-compiler && cargo test --test regexp_typecheck_tests → 8 passed
$ cd lang/igniter-compiler && cargo test --test igweb_lowering_tests   → 11 passed
$ cd server/igniter-web    && cargo test                               → all suites green (todo_view_app 14, …)
$ cd server/igniter-web    && cargo test --features machine --test todo_postgres_api_read_write_e2e_tests → 2 passed
$ cd server/igniter-web    && cargo run --example app_pressure_bench    → JSON, all_ok=true (table above)
$ git diff --check                                                     → clean (only vm.rs, +30/-4)
```

**Pre-existing red (not mine):** `lang/igniter-vm` `vm_candidate_proof_tests::test_proof_vmg13_local_loops_and_service_loops`
fails — verified it fails **identically without this change** (stash test), is about loops/service-loops
(no regexp), and is out of scope for this card.

## Acceptance — mapping

- [x] `matches` uses the cached compiled regex for a repeated identical pattern.
- [x] `capture` uses the same cache path.
- [x] Bytecode + eval_ast parity (both call `cached_regex`).
- [x] Invalid-pattern error text/category unchanged (operational failure, not cached).
- [x] No behavior change for no-match / out-of-range / negative capture index.
- [x] Unicode behavior unchanged.
- [x] No IgWeb lowering or `igniter-server` change.
- [x] Dynamic-pattern behavior correct; growth policy documented (global, unbounded v0, bounded in practice).
- [x] Existing regexp tests green (runtime 6, typecheck 8); IgWeb route tests green (lowering 11, view 14).
- [x] `app_pressure_bench` runs + reports JSON; before/after trend discussed.
- [x] `git diff --check` clean.

## Closed scope (honored)

No radix trie / route index; no `.igweb` lowering change; no server route table; no public performance
claim; no canon claim. One file (`vm.rs`), behavior-identical.

## Next

- `LAB-LANG-RUNTIME-HOTPATH-READINESS-P3` — now that regex recompilation is removed, profile the remaining
  per-request cost (VM dispatch/render) before any further optimization; revisit the route-match structure
  (order-preserving radix trie) only if a many-route workload shows the residual linear scan matters.
- Optional later: bound the cache (LRU / per-machine) if a real many-distinct-pattern workload appears.

---

*Lab implementation-proof. Compiled 2026-06-21; one file (`vm.rs`), behavior-identical (regexp 6 + typecheck
8 + igweb 11 + view 14 + e2e 2 green), late-route dispatch −48% in the lab-local bench, route-free boundary
preserved, `git diff --check` clean. The route hot path no longer recompiles regexes per request.*
