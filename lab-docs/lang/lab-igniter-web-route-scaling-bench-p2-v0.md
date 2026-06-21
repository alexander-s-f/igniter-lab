# lab-igniter-web-route-scaling-bench-p2-v0 — IgWeb route cost at 10 / 50 / 90 routes (+ the wall)

**Card:** `LAB-IGNITER-WEB-ROUTE-SCALING-BENCH-P2` · **Delegation:** `OPUS-IGNITER-WEB-ROUTE-SCALING-BENCH-P2`
**Status:** CLOSED (lab measurement-proof) — a zero-dependency harness that synthesizes authored `.igweb`+`.ig`
apps with N routes and measures compile/load + early/middle/late/miss dispatch. **Headline finding: IgWeb
route lowering hits a HARD compile/LOAD wall at ~116 routes (serde recursion limit on the O(N)-deep nested-if
SemanticIR), well before dispatch latency matters.** Lab-local trend only — no public perf claim.
**Authority:** Lab measurement. No `igniter-server`/lowering change, no route trie. Regexp cache (P4) present.

## App shape (generated, no DB/network/env)

For each N, the harness writes to a tempdir an authored `.igweb` + `.ig` (real `build_igweb_app` path, not a
Rust shortcut):
- `routes.igweb`: `app SynthWeb entry Serve { handlers SynthHandlers; route GET "/r{i}/:id" -> Handler{i} … }`
  for `i` in `0..N` — N distinct anchored param patterns, source order preserved.
- `handlers.ig`: N `pure contract Handler{i} { input req; input id : Option[String]; compute d = Respond {200,"ok"} }`.

Dispatch positions per N: **first** `/r0/123`, **middle** `/r{N/2}/123`, **last** `/r{N-1}/123`, **miss**
`/nope/123` (matches no arm → 404, walks every arm). `compile_load` is timed separately from dispatch.

## Route counts & the wall

Default set **10 / 50 / 90** (all below the wall). The wall was probed per-N (a build failure aborts a
shared process, so each N runs in its own): **115 routes build OK; 118 routes FAIL** with
`Load("SerializationError(\"recursion limit exceeded …\"))`. Far beyond (~500) the typechecker itself
**stack-overflows**. So an app with **> ~115 routes cannot be built today**.

## Scenario table (median_us, debug, one machine — illustrative, NOT a claim)

| N | compile_load | first | middle | last | miss |
|---|---|---|---|---|---|
| 10 | 48,472 | 839 | 967 | 1074 | 1022 |
| 50 | 126,302 | 3,826 | 4,532 | 5,224 | 5,108 |
| 90 | 244,133 | 6,984 | 8,284 | 9,548 | 9,338 |

(`regexp_cache_p4_present: true`.) Raw JSON via `cargo run --example route_scaling_bench`; probe a single N
with `cargo run --example route_scaling_bench -- 118` (records the wall gracefully as a non-ok
`compile_load` scenario with a `note`, no panic).

## Interpretation (lab-local trend signals only)

1. **HARD compile/LOAD wall at ~116 routes — the headline.** Route lowering emits an **O(N)-deep nested
   `if matches(...) { … } else { if … }`** tree. The machine LOAD deserializes that SemanticIR with serde,
   whose default recursion limit (~128) is exceeded around N≈116 → `SerializationError`. This is a
   **structural ceiling**, not a slowdown: a real app cannot exceed ~115 routes. (At extreme N the
   typechecker's `infer_expr` recursion stack-overflows outright.)
2. **compile/load is super-linear:** 48 ms (10) → 126 ms (50) → 244 ms (90) — building N contracts + an
   ever-deeper nested IR.
3. **dispatch scales ~linearly with N, even WITH the P4 regexp cache.** Two components:
   - a **route-position effect** (last ≈ 1.35× first at every N; ~25–28 µs incremental per route between
     first and last) — the cost of walking the if-chain to the matched arm (VM eval per `if`/`matches`
     node; the regexp *compile* is cached, the per-node *eval* is not);
   - a **base O(N) per-dispatch cost** — `first` itself grows 839 → 3,826 → 6,984 µs as N grows, although
     route 0 short-circuits on the first arm. That base cost is independent of route position, consistent
     with per-dispatch setup over the N-contract program (`IgniterMachine::dispatch` builds a fresh VM +
     dispatch table each request).
4. **miss ≈ last** (both walk all arms), confirming the chain-depth model.

## Whether the regexp cache (P4) was present

**Yes** (`vm.rs` `cached_regex`, process-global). So this curve is the *post-cache* residual: the cache
removed per-call regex *recompilation* (P4's −48% on the late route), but the per-`if`-node *eval* cost and
the per-dispatch O(N) setup still scale with N. The cache does not change the compile/LOAD wall (that is the
nested-IR depth, not regex).

## Recommendation

**Open a route-index / flat-dispatch readiness card — motivated PRIMARILY by the compile/LOAD wall, not by
dispatch microseconds.** At realistic small N the dispatch latency does not justify a router. But the
**~116-route compile ceiling is a real prod blocker**: the O(N)-deep nested-if lowering structurally can't
scale. A **flat dispatch lowering** — emit the route table as DATA + a single bounded `match`/table walk
(an order-preserving route index, NOT a most-specific-wins trie) instead of N-deep nested `if`s — would
remove **both** (a) the serde/typechecker recursion wall and (b) the O(N) dispatch scan, in one structural
change. It must preserve authored-order priority (P18) and the route-free server boundary (the index is
still app-owned, derived from the `.igweb`, not a server route table). **Do not implement it here** (card
forbids the trie); this card delivers the curve + the wall that justify that readiness work.

## Acceptance — mapping

- [x] Bench runs with no DB/network/env.
- [x] Uses generated authored `.igweb` + `.ig` (real `build_igweb_app`), not a Rust-only shortcut.
- [x] Compile/load timing separated from dispatch.
- [x] Measures first/middle/last/miss — default 10/50/90; the 100/500 target is **not practical** (the
      ~116 build wall), documented with the probed cliff (115 OK / 118 FAIL).
- [x] Stable JSON with scenario names, iterations, median timing, `warning`/no-claim field.
- [x] Records `regexp_cache_p4_present: true`.
- [x] No Criterion / bench dependency (zero-dep `std::time::Instant`).
- [x] No `igniter-server` change; no route trie/index implemented.
- [x] `app_pressure_bench` remains runnable (verified `all_ok:true`).
- [x] `igniter-web cargo test` green; `git diff --check` clean (one new example file).

## Verification

```text
$ cargo run --example route_scaling_bench            → JSON, all_ok=true (10/50/90 curve above)
$ cargo run --example route_scaling_bench -- 115 118 → 115 ok, 118 ok=false "BUILD FAILED … recursion limit"
$ cargo run --example app_pressure_bench             → all_ok=true (P1 harness intact)
$ cd server/igniter-web && cargo test                → all suites green (todo_view_app 14, …)
$ git diff --check                                   → clean (only examples/route_scaling_bench.rs added)
```

## Closed scope (honored)

No optimizer; no trie/radix router; no route reordering; no server route table; no public perf claim; no
canon claim. One new example file; no production code change.

## Next

1. `LAB-IGNITER-WEB-ROUTE-INDEX-READINESS-P*` — design an order-preserving flat dispatch lowering (route
   table as data + bounded walk) to remove the ~116-route compile wall **and** the O(N) dispatch scan;
   boundary-safe (app-owned index derived from `.igweb`, server stays route-free), P18 priority preserved.
2. `LAB-LANG-RUNTIME-HOTPATH-READINESS-P3` — the per-dispatch O(N) setup cost (fresh VM + dispatch table per
   request) is the other lever surfaced here.

---

*Lab measurement-proof. Compiled 2026-06-21; zero-dep harness, default 10/50/90 dispatch curve, compile/LOAD
wall at ~116 routes (serde recursion limit) probed (115 ok / 118 fail), regexp cache P4 present, igniter-web
tests green, `app_pressure_bench` intact, `git diff --check` clean. Lab-local trend only — no public perf claim.*
