# lab-machine-igniter-server-wave-checkpoint-p14-v0 — server wave digest / front door

**Card:** `LAB-MACHINE-IGNITER-SERVER-WAVE-CHECKPOINT-P14`
**Status:** CHECKPOINT / NAVIGATION (not new authority) — one compact, source-backed front door for the
`igniter-server` wave so future agents don't re-open settled questions. **No code, no new behavior, no
live/deploy, no canon claim.**
**Authority:** Lab-only navigation artifact. Verified against live source + fresh command output
2026-06-18.

---

## 1. Executive summary

`igniter-server` is a **lab-only, Rack-like server substrate** — not a web framework. It owns
**wire/transport, concurrency/lifecycle, hot reload, a bounded serving loop, generic middleware, and an
optional machine/effect bridge**. It owns **no product domain**. An app is a `ServerApp`
(`fn call(&self, ServerRequest) -> ServerDecision`) implemented OUTSIDE core.

Core invariant (the whole wave in one line):

```text
server owns wire / concurrency / lifecycle / reload
app    owns routing / classification / product meaning   (a match inside ServerApp::call)
host   owns machine + effect authority                   (target→route binding, recipe, effect passport)
```

The app names **logical** decisions — `Respond` | `Invoke` | `InvokeEffect{ target, input,
correlation_id, idempotency_key }` — and **never** `capability_id`/`operation`/`scope`. That single
discipline is what preserves the P7/P8 exactly-one-effect guarantees end-to-end.

Default build is **machine-free** (`serde` only); `igniter_machine` + `tokio` are optional behind
feature `machine`.

---

## 2. Timeline P1–P14

| Step | Card | Kind | What it settled |
|---|---|---|---|
| P1 | `…-PROTOCOL-READINESS-P1` | readiness | 3-shape decision enum; routing relocates from server config → app |
| P2 | `…-BINARY-P2` | impl | std loopback binary; `Invoke{target}` + `InvokeEffect{…}`; `Respond` executed, others observed 202 |
| P3 | `…-EFFECT-P3` | impl | `InvokeEffect` executes via the EXISTING machine contour (`MachineEffectHost` → `IngressRouter::handle_effect`); feature `machine` |
| P4 | `…-HOT-RELOAD-P4` | impl | `ReloadableApp` snapshot-per-request swap; `AppIdentity` (observation, not authority) |
| P5 | `…-SERVING-LOOP-P5` | impl | bounded `serve_loop` (binds nothing; not a daemon); `ServingReport` |
| — | `SPARKCRM-SERVER-APP-READINESS-P1` | readiness | SparkCRM-shaped app design (logical targets, duplicate policy) |
| — | `SPARKCRM-SERVER-APP-SHADOW-P2` | impl | offline SparkCRM app proof; canonical key → generic `idempotency-key` gate |
| P6 | `…-APP-BOUNDARY-P6` | refactor | domain app moved OUT of core into a test fixture; core de-vocabularized |
| P7 | `…-EXTENSIONS-READINESS-P7` | readiness | extension model: static `ServerApp` apps + wrapper middleware; dynamic plugins deferred |
| P8 | `…-MIDDLEWARE-P8` | impl | zero-cost wrapper middleware `Trace`/`Auth`/`BodyLimit` + `ServerAppExt`; route-agnostic |
| P9 | `…-EXAMPLE-APP-READINESS-P9` | readiness | first external example shape (Cargo example, neutral `ticket-intake`) |
| P10 | `…-EXAMPLE-APP-P10` | impl | `examples/server_app_basic.rs` + tests (the raw-trait example) |
| P11 | `…-ASSETS-READINESS-P11` | readiness | v0 = `Respond`(JSON); verbatim HTML/binary deferred (wire body always JSON) |
| P12 | `…-APP-PACKAGING-READINESS-P12` | readiness | v0 packaging = library `build_app(config)→Arc<dyn ServerApp+Send+Sync>` + thin runner |
| P13 | `…-APP-RUNNER-EXAMPLE-P13` | impl | `examples/server_app_runner.rs` + tests (build_app + thin runner + swap) |
| P14 | `…-WAVE-CHECKPOINT-P14` | digest | **this document** |

All P1–P13 cards are **CLOSED** (verified via card `Status:` lines).

---

## 3. Implemented surface map (`igniter-server/src`)

| Module | Role | Key proof / tests |
|---|---|---|
| `protocol.rs` | `ServerApp` trait (`call` + default `identity`); `ServerRequest`/`ServerResponse`; `ServerDecision` (`Respond`/`Invoke`/`InvokeEffect`); `AppIdentity{name,version,digest}` | unit tests in-module (target-not-contract; no effect identity) |
| `host.rs` | std loopback HTTP/1.1 parse/encode; `serve_once`/`serve_bounded`; `serve_once_reloadable[_observed]` | `loopback_tests.rs` (5) |
| `effect_host.rs` *(feature `machine`)* | `MachineEffectHost` (`target→route` infra binding; force-inserts canonical `idempotency-key`); `dispatch`; `serve_once_effect[_reloadable[_observed]]`; `serve_loop_effect` | `effect_machine_tests.rs` (8), `sparkcrm_shadow_tests.rs` (5) |
| `reload.rs` | `ReloadableApp = Arc<RwLock<Arc<dyn ServerApp+Send+Sync>>>`; `current`/`swap`/`identity` | `reload_tests.rs` (4) |
| `serving_loop.rs` | `serve_loop`; `ServingPolicy{max_requests, loopback_only}`; `ServingReport` | `serving_loop_tests.rs` (5) |
| `middleware.rs` | `TraceApp`/`AuthTokenApp`/`BodyLimitApp` + `ServerAppExt` (`with_trace/with_auth/with_body_limit`) | `middleware_tests.rs` (8) |
| `fixture.rs` | the in-core generic `DemoApp` (core's own tests/binary) | `loopback_tests.rs` |
| `bin/igniter-server.rs` | P2 loopback binary over `DemoApp` | — |
| `examples/server_app_basic.rs` | external raw-trait example (`ExampleApp`, `ticket-intake`) | `example_app_tests.rs` (8) |
| `examples/server_app_runner.rs` | packaging example (`build_app` + thin runner + swap) | `app_runner_example_tests.rs` (7) |
| `tests/fixtures/sparkcrm_app.rs` | SparkCRM domain app as a **test fixture** (P6) | `sparkcrm_app_tests.rs` (5), `sparkcrm_shadow_tests.rs` (5) |

---

## 4. Command / evidence block (fresh, 2026-06-18)

```text
$ cd igniter-server && cargo build --examples
  Finished `dev` profile (0 warnings)

$ cd igniter-server && cargo test                     → 49 passed; 0 failed
   lib(unit) 7 · loopback 5 · reload 4 · serving_loop 5 · middleware 8 · sparkcrm_app 5
   · example_app 8 · app_runner_example 7 · (effect_machine 0, sparkcrm_shadow 0 — feature-gated off)

$ cd igniter-server && cargo test --features machine  → 62 passed; 0 failed
   the above + effect_machine_tests 8 + sparkcrm_shadow_tests 5
```

`igniter-server` is warning-clean in both builds; transitive warnings come from
`igniter_compiler`/`igniter_machine` (pre-existing, unrelated). `igniter-machine` was **never modified**
by this wave — the only machine-adjacent change was the `effect_host.rs` adapter's canonical-key
force-insert (SHADOW-P2), inert for P3/P4/P5.

---

## 5. Boundary / NOT proven (explicit)

- **No public listener / no live deploy** — the loop binds nothing; callers pass a `127.0.0.1`
  listener (`loopback_only` opt-in guard).
- **No live SparkCRM / vendor API** — the SparkCRM app is an offline test fixture over a fake executor.
- **No DB / credentials / TLS** — machine tests use in-memory backend + fake executor only.
- **No dynamic plugin system** — extension = static Rust apps compiled in (P7 deferred dynamic loading).
- **No raw HTML/SVG/binary response protocol** — `ServerResponse.body` is JSON; the wire body is always
  `serde_json::to_vec(body)` (P11). Verbatim non-JSON bytes are deferred.
- **No route-config framework / route table in core** — routing is a `match` inside `ServerApp::call`.
- **No release / canon claim** — lab evidence only.

---

## 6. Developer DX today (point to examples, don't duplicate)

- **Write a minimal `ServerApp`:** `impl ServerApp for YourApp { fn call(&self, req) -> ServerDecision
  { match (req.method.as_str(), req.path.as_str()) { … } } }`. See `examples/server_app_basic.rs`.
- **Package it:** export `build_app(config) -> Arc<dyn ServerApp + Send + Sync>` composing middleware at
  the edge; a thin runner owns the listener + `ServingPolicy` + `ReloadableApp`. See
  `examples/server_app_runner.rs`.
- **Compose middleware:** `app.with_trace().with_auth(token).with_body_limit(n)` (builds
  `BodyLimit→Auth→Trace→app`; `ReloadableApp` wraps the whole stack).
- **Reload:** `reloadable.swap(build_app(new_cfg))` — affects later requests; in-flight keeps its
  snapshot.
- **Serve:** `serve_loop(&listener, &reloadable, &ServingPolicy::new(n))` — bounded, returns a
  `ServingReport`; not a daemon.
- **Effects (optional, feature `machine`):** return `InvokeEffect{ target, … }`; the host binds
  `target→route` + supplies `EffectBridgeConfig`. The same app runs machine-free or machine-backed
  unchanged.

---

## 7. Next legitimate routes (bounded, non-live by default)

- **`LAB-MACHINE-SPARKCRM-SERVER-APP-SHADOW-REPORT-P3`** — summarize the offline shadow results; decide
  whether to revisit the human live-gate packet. *(Product work, still offline.)*
- **`LAB-MACHINE-IGNITER-SERVER-RAW-RESPONSE-P*`** — only if a real in-tree app needs verbatim
  HTML/SVG/binary (P11 trigger gate).
- **Separate sample app crate (`igniter-server-sample-app`)** — only when a real second consumer appears
  (P12).
- **`LAB-MACHINE-SPARKCRM-LIVE-GATE-P1`** and any public listener / live DB / vendor API — **human
  decision only**; never inferred from this wave.

---

## 8. Agent navigation protocol

- **Front doors:** this digest first; then `igniter-server/README.md` (architecture + boundary +
  examples); then the per-step docs `lab-docs/lang/lab-machine-igniter-server-<topic>-<Pn>-v0.md`.
- **Grep first:**
  - surface: `igniter-server/src/lib.rs` (module map) + `rg "pub fn|pub struct|pub trait" igniter-server/src`;
  - behavior: the test file per module (table §3) — tests are the live contract;
  - boundary check: `rg -n "SparkCRM|sparkcrm|auction|lead-" igniter-server/src` should return only
    negation comments (domain lives in `tests/fixtures/`, never `src/`).
- **Trust order:** live code + tests > these docs > card lore. If a doc disagrees with code, the code
  wins (verify-first).
- **Stale-claim guards:** anything implying a public listener, live SparkCRM/DB, a route-config
  framework, or raw-byte responses is NOT implemented — treat as not-proven until a card + code say
  otherwise. The README "Current contents" line ("exports the protocol module") is outdated shorthand;
  the real module map is `src/lib.rs` (§3).

---

## Conclusion

```text
igniter-server in-lab wave: CLOSED ENOUGH as substrate + DX proof (P1–P13 all CLOSED; 49/62 tests green)
  -> next PRODUCT work  = SparkCRM shadow report (offline) / app-specific gates
  -> next SUBSTRATE work = trigger-only: raw response, separate app crate, live gate (human)
```

*Checkpoint/navigation only. Compiled 2026-06-18 against live source + fresh `cargo` runs.*
