# lab-igniter-machine-host-io-substrate-readiness-p1-v0

**Card:** `LAB-IGNITER-MACHINE-HOST-IO-SUBSTRATE-READINESS-P1`
**Status:** READINESS (v0)
**Date:** 2026-06-22
**Lane:** machine / host IO / architecture

---

## 1. Executive Summary / Decision

**The common host IO substrate already exists in `igniter-machine`.** The question is not "what to build"
but "how each runner surface plugs in without making IO a web-only feature or leaking authority into `.ig`."

Three compounding problems block the first full consumer (IgWeb):

1. **Sync socket loop** — `igweb-serve` uses `std::net::TcpListener` + sync `serve_loop`; async effects
   and staged reads cannot be awaited inside a synchronous loop.
2. **Nested `block_on`** — `IgWebServerApp::call` is sync and does `rt.block_on(machine.dispatch(...))`
   internally. Porting the socket loop to `tokio::net::TcpListener` is not enough; you cannot nest
   `block_on` inside an already-running tokio context.
3. **Missing operator config seam** — no standard `host.toml` shape for DSN, target→route bindings, and
   passports. Current wiring lives in test harnesses only.

**Decision for P1 (this card):** name the substrate, classify IO, inventory what exists, identify the
missing seams, and recommend the smallest next implementation card. No code changes.

**Recommended first implementation slice:** `LAB-IGNITER-WEB-ASYNC-MACHINE-RUNNER-P2` — replace the
sync `igweb-serve` transport with an async tokio runtime, wire `serve_loop_effect`, and add the `ReadThen`
runner seam. This fixes the web async trap without touching the machine crate or other runner surfaces.

---

## 2. Live-Code Evidence Table

| File | Key Contents | Relevant Findings |
|------|-------------|-------------------|
| `server/igniter-web/src/bin/igweb-serve.rs` | `main()`, `ReloadableApp`, `ServingPolicy` | Sync `std::net::TcpListener`; calls `serve_loop` (pure reads only); no machine wiring in binary |
| `server/igniter-web/src/lib.rs` | `IgWebServerApp`, `IgWebBuildInput`, `IgwebManifest` | `call()` is **sync**; holds `tokio::runtime` (current-thread); every dispatch = `rt.block_on(machine.dispatch(...))`; nesting hazard |
| `server/igniter-server/src/serving_loop.rs` | `serve_loop`, `ServingPolicy`, `ServingReport` | Bounded exit (max_requests budget); caller pre-binds TcpListener; observation-only; no tokio spawn |
| `server/igniter-server/src/effect_host.rs` | `MachineEffectHost`, `serve_loop_effect`, `dispatch` | Async throughout; effect passport injected; `run_invoke_effect` → `router.handle_effect(...).await`; exists and works in harness |
| `runtime/igniter-machine/src/ingress.rs` | `IngressRouter`, `EffectBridgeConfig`, `DuplicatePolicy`, `handle`, `handle_effect` | Full async effect + read path; dual dedup (machine receipt + PG layer); deterministic replica selection; passport validation before activation |
| `runtime/igniter-machine/src/capability.rs` | `CapabilityExecutor`, `OutcomeKind`, `CapabilityPassport`, `CapabilityExecutorRegistry`, receipts | Uniform async executor boundary; failure taxonomy (Succeeded/Denied/Retryable/PermanentFailure/UnknownExternalState); blake3 MAC passport |
| `runtime/igniter-machine/src/postgres_read.rs` | `PostgresReadExecutor`, `QueryPlan`, `PostgresReadAdapter`, host gates | Structural plan (no SQL); 6-layer gate before adapter; fake adapter proven; `TokioPostgresReadAdapter` opt-in (`postgres` feature) |
| `runtime/igniter-machine/src/postgres_write.rs` | `PostgresWriteExecutor`, `PostgresWriteIntent`, two-layer idempotency | Typed mutation (no SQL); machine receipt + PG-side `effect_receipts` unique constraint; `FakePostgresWriteAdapter` with behavior scripts |
| `runtime/igniter-machine/src/postgres_real.rs` | `TokioPostgresReadAdapter` | Real PG read only (no write adapter yet); parameterized queries; identifier quoting; feature-gated `postgres` |
| `runtime/igniter-machine/src/lib.rs` | Module index | `backend`, `bridge`, `capability`, `capsule`, `coordination`, `fact`, `ingress`, `machine`, `postgres_read/write/real`, `reconcile`, `registry`, `retry`, `single_flight`, `wal`, `write`; Ruby/Magnus FFI removed |
| `lang/igniter-vm/src/experiment.rs` | Kuramoto/Boids experiment runner | Accepts `--kernel`, emits `provenance.json`; no machine/capability wiring; filesystem IO only; `artifact_digest: null` until package admission wired |

No `experiment.rs` exists in `runtime/igniter-machine/src/` — the experiment runner lives in `lang/igniter-vm/`.

---

## 3. IO Class Taxonomy

Igniter needs seven distinct IO classes across its runner surfaces.

### 3A. Inline read (read-before-respond)

Caller needs rows in the response body. Host executes the read between entry dispatch and continuation
dispatch. Response cannot be sent until rows are available.

- Mechanism: `ReadThen { plan, then }` decision → async host staged driver → continuation
- Latency contract: bounded by adapter query time; must complete within request timeout
- Already proven: harness (P6); runner seam missing (P10 design)

### 3B. Deferred effect / write (fire-and-receipt)

Caller needs only a receipt (committed proof). The side-effect is idempotent and the machine absorbs
retry/dedup. Response is the receipt, not data rows.

- Mechanism: `InvokeEffect` decision → `MachineEffectHost` → `IngressRouter::handle_effect` →
  `CapabilityExecutor` → machine receipt
- Latency contract: bounded by executor execution time; immediate 200/receipt after effect completes
- Already proven: P4 (harness), P9 (runner contour); async socket loop still needed

### 3C. Read-then-write (conditional mutation)

App reads state first, then optionally emits a write based on what it sees. Host runs two sequential
async steps in one request scope.

- Mechanism: `ReadThen` → host read → continuation returns `InvokeEffect` → host effect
- Latency contract: read latency + write latency, sequential
- Not yet implemented; seam designed in P5/P10

### 3D. Export (descriptor → bytes)

Project manifest or computation result is projected to bytes for storage or transmission. No external
state mutation; no receipt needed. May be sync or async.

- Examples: `ViewArtifact → HTML` (already exists in `lib.rs::render_to_decision`), future: `.igpkg` export, CSV export, report generation
- Mechanism: pure host fn (sync or async); no capability machinery
- Already exists for HTML render; needs generalization for other formats

### 3E. File / storage IO

Runtime artifact persistence: provenance.json, series.csv, REPORT.md. Local filesystem; crash-safe via
OS atomics (write-then-rename pattern).

- Owner: runner (science runner owns filesystem output; web runner owns access logs)
- Mechanism: `tokio::fs` or `std::fs` depending on runner runtime
- Already used in experiment runner (`lang/igniter-vm/src/experiment.rs`)
- No machine receipt; crash-safety is OS-layer concern

### 3F. Remote node call

Cross-process ingress dispatch over HTTP. Functionally the same as local capability execution but with
network latency. Passport and correlation ID cross the wire.

- Mechanism: `IngressRouter::handle` or `handle_effect` over HTTP client (not yet wired)
- Already supports: bearer token → passport, route → pool, correlation/idempotency headers
- Missing: HTTP capability executor that targets a remote host instead of local pool
- Latency contract: tolerate 50–500ms; backpressure = 429/503 from remote

### 3G. Experiment artifact write (science runner)

Provenance-gated output bundle (provenance.json, summary.json, series.csv). Distinct from general file
IO because writes are gated on a completed experiment lifecycle, not on an external capability passport.

- Owner: science runner only (igniter-vm experiment)
- Mechanism: `build_provenance_json` → `std::fs::write` (or `tokio::fs`)
- `artifact_digest` field present but `null` until package admission seam is wired (P6 provenance card)
- No machine receipt; the experiment result IS the artifact

---

## 4. Existing Substrate Inventory

Everything listed below already exists in `igniter-machine` / `igniter-server`. The substrate is rich;
the missing pieces are runner wiring, operator config, and one compiler arm.

| Component | Source file | Role |
|-----------|-------------|------|
| `CapabilityExecutor` trait | `runtime/igniter-machine/src/capability.rs` | Uniform async effect boundary for all external IO |
| `CapabilityExecutorRegistry` | `runtime/igniter-machine/src/capability.rs` | Named executor lookup by `capability_id` (host-owned) |
| `CapabilityPassport` + `PassportVerifier` | `runtime/igniter-machine/src/capability.rs` | Bearer token → scopes; blake3 MAC; revocation; expiry |
| `OutcomeKind` + `EffectOutcome` | `runtime/igniter-machine/src/capability.rs` | 5-way failure taxonomy; epistemic `UnknownExternalState` |
| Receipt store (`__receipts__`) | `runtime/igniter-machine/src/capability.rs` | Machine-layer idempotency gate; replayed effects never re-run executor |
| `IngressRouter` | `runtime/igniter-machine/src/ingress.rs` | Route → capsule pool; passport validation; duplicate policy; deterministic replica selection |
| `EffectBridgeConfig` | `runtime/igniter-machine/src/ingress.rs` | Capability registry + receipts backend + effect clock + effect passport + SingleFlight gate |
| `DuplicatePolicy` / `DuplicateDecision` | `runtime/igniter-machine/src/ingress.rs` | `strict` / `treat_as_fresh` / `bounded_fresh(n)` dedup strategies |
| `SingleFlight` gate | `runtime/igniter-machine/src/single_flight.rs` | Concurrent same-key serialization at effect level |
| `MachineEffectHost` | `server/igniter-server/src/effect_host.rs` | target → route binding; effect bridge; `run_invoke_effect` async fn |
| `serve_loop_effect` | `server/igniter-server/src/effect_host.rs` | Bounded async serving loop over `MachineEffectHost` |
| `ServingPolicy` / `ServingReport` | `server/igniter-server/src/serving_loop.rs` | max_requests budget; loopback guard; observation output |
| `PostgresReadExecutor` | `runtime/igniter-machine/src/postgres_read.rs` | Structural `QueryPlan` → `CapabilityExecutor` (implements executor trait); 6-layer gate |
| `PostgresWriteExecutor` | `runtime/igniter-machine/src/postgres_write.rs` | `PostgresWriteIntent` → `CapabilityExecutor`; two-layer idempotency |
| `FakePostgresReadAdapter` | `runtime/igniter-machine/src/postgres_read.rs` | In-memory read for harness (proven P3–P6) |
| `FakePostgresWriteAdapter` | `runtime/igniter-machine/src/postgres_write.rs` | In-memory write + behavior scripts (proven P4, P9) |
| `TokioPostgresReadAdapter` | `runtime/igniter-machine/src/postgres_real.rs` | Real PG read; parameterized queries; feature-gated `postgres` (proven P6/P8) |
| `CoordinationHub` | `runtime/igniter-machine/src/coordination.rs` | Pool management; capsule lifecycle |
| Reconcile path | `runtime/igniter-machine/src/reconcile.rs` | Recovery for `UnknownExternalState` (present; not yet wired to runner) |
| `retry_queue.rs` | `runtime/igniter-machine/src/retry_queue.rs` | Retry queue (present; scope of current integration unclear) |
| `wal.rs` | `runtime/igniter-machine/src/wal.rs` | Write-ahead log (present; durable background jobs candidate) |

---

## 5. Missing Seams

| Gap | Description | Blocking what |
|-----|-------------|---------------|
| **Async host driver (runner-level)** | `serve_loop_effect` exists but `igweb-serve` still uses sync socket + `serve_loop`. Need to boot tokio runtime in binary and use async serve path. | Web machine-backed runner |
| **`ReadThen` compiler arm** | Decision variant designed (P5) and harness-proven (P6); not in compiler prelude or VM dispatcher. App cannot author `ReadThen` today. | Staged read in any runner |
| **Async staged read driver** | The async two-dispatch pattern (entry → host read → continuation dispatch) is hand-orchestrated in P6 harness; needs extraction as a named async fn usable from a tokio task. | ReadThen in production runner |
| **Operator config schema** | No standard `host.toml` shape. DSN, target→route bindings, capability passports, and pool policy live in test harnesses only. Productization requires file-parseable operator config. | Any machine-backed runner (web, CLI, desktop, science) |
| **Real tokio-postgres write adapter** | Read adapter exists (`TokioPostgresReadAdapter`, proven P8). Write adapter (`TokioPostgresWriteAdapter`) not yet present. | Real write execution against live PG |
| **Worker pool / concurrency limit** | `ServingPolicy.max_requests` is a lifetime budget (exits after N requests), not a concurrency limiter. No max-concurrent-effects cap. | Backpressure under sustained load |
| **Durable background job mailbox** | `retry_queue.rs` and `wal.rs` exist; unclear if usable as a durable queue for deferred effects that must survive server restarts. Not needed for P2 but needed before any "fire and forget with durability" claim. | Background job semantics |
| **HTTP capability executor for remote nodes** | Machine handles cross-process ingress over HTTP (IngressRouter protocol), but there is no `HttpCapabilityExecutor` that acts as an outbound HTTP client to a remote igniter-machine. | Remote node calls |
| **Package admission → runner input seam** | Experiment runner accepts `--kernel <path>` (plain path); `artifact_digest` remains null. No `--package <file.igpkg>` intake. | Science provenance integrity |

---

## 6. Proposed Architecture

### Layer diagram

```
┌──────────────────────────────────────────────────────────────────────┐
│  .ig contracts                                                        │
│  Pure graph; values; decisions; no ambient IO authority               │
│  Decision arms: Respond | RespondView | InvokeEffect | Render         │
│                 RenderView | ReadThen{plan,then} [designed, not impl] │
└───────────────────────────────┬──────────────────────────────────────┘
                                │ machine.dispatch(entry, input).await
┌───────────────────────────────▼──────────────────────────────────────┐
│  VM / IgniterMachine                                                  │
│  Executes pure graph; emits structured Decision                       │
│  No ambient IO; no hidden await                                       │
└───────────────────────────────┬──────────────────────────────────────┘
                                │ Decision
┌───────────────────────────────▼──────────────────────────────────────┐
│  Async host driver  (async fn, runner-specific, NEW for P2)           │
│  Matches Decision arms:                                               │
│    Respond / RespondView / Render / RenderView  → immediate response  │
│    InvokeEffect  → MachineEffectHost::run_invoke_effect().await       │
│    ReadThen      → async staged read driver                           │
│                    → machine.dispatch(continuation, rows).await       │
│                    → recurse into final Decision                      │
└─────┬─────────────────────────┬─────────────────────────────────────┘
      │ InvokeEffect            │ ReadThen
┌─────▼──────────┐   ┌──────────▼──────────────────────────────────────┐
│ MachineEffect  │   │  PostgresReadExecutor (host gates → adapter)     │
│ Host           │   │  Gate sequence:                                  │
│ bind_target    │   │   1. Raw-SQL refusal                             │
│ run_invoke     │   │   2. Source allowlist                            │
│ _effect        │   │   3. Field allowlist                             │
└─────┬──────────┘   │   4. Predicate/order validation                 │
      │              │   5. Row-limit clamp                             │
┌─────▼──────────┐   │   6. Adapter query                              │
│ IngressRouter  │   └─────────────────────────────────────────────────┘
│ handle_effect  │
│ Passport check │
│ Route resolve  │
│ Dedup policy   │
│ Replica select │
│ handle_effect  │
└─────┬──────────┘
      │
┌─────▼──────────────────────────────────────────────────────────────┐
│  CapabilityExecutor  (Postgres write, HTTP, future: remote node)    │
│  OutcomeKind: Succeeded | Denied | Retryable | Permanent | Unknown  │
│  Machine receipt + PG-side effect_receipts  (two-layer idempotency) │
└────────────────────────────────────────────────────────────────────┘
```

### Runner surface mapping

```
igweb-serve (web)       → tokio socket → serve_loop_effect → async host driver
igweb-serve (CLI)       → stdin/args   → async host fn    → async host driver  [future P4]
desktop runner          → native event → async host fn    → async host driver  [future]
igniter-vm experiment   → --kernel     → sync fs           → filesystem IO only [no machine]
igniter-vm + package    → --package    → async host fn    → async host driver  [future, P7-prov]
remote node             → HTTP ingress → IngressRouter     → async host driver  [future]
```

---

## 7. Web / CLI / Desktop / Science / Remote-Node Mapping

### Web (`igweb-serve`)

- Event: HTTP request over TCP socket
- Entry: `IgWebServerApp` (compiled `.igweb` → `.ig` contracts)
- Decision routing: `map_decision` in `lib.rs`
- Effects: `MachineEffectHost` → `IngressRouter::handle_effect`
- Reads: `ReadThen` → async staged driver → `PostgresReadExecutor` [not yet in runner]
- Socket path: must migrate from `std::net::TcpListener` + `serve_loop` to tokio + `serve_loop_effect`
- First consumer target for the substrate; `LAB-IGNITER-WEB-ASYNC-MACHINE-RUNNER-P2`

### CLI runner

- Event: CLI command invocation (stdin, file argument, or pipe)
- Entry: `.ig` contract, no igweb routing layer
- Decision routing: host interprets final `Respond` or `Render` as stdout
- Effects: same `MachineEffectHost` machinery (operator config for capability passports)
- Reads: same `ReadThen` driver; results printed or piped
- Async boundary: host boots tokio runtime for machine-backed invocations; CLI process exits after one dispatch cycle
- NOT imported: HTTP semantics (no correlation_id headers, no 200/503 status codes in response)
- Future card: `LAB-IGNITER-CLI-ASYNC-HOST-P4`

### Desktop runner (future)

- Event: native UI event (button click, form submit)
- Entry: `.ig` contract dispatched via host UI bridge
- Effects: same machinery; passports stored in OS keychain (not DSN file)
- Reads: same `ReadThen` driver
- Async boundary: tokio runtime per window or shared app-level runtime
- IO distinction: response may write to in-process UI state, not HTTP socket
- No web transport layer

### Science / experiment runner (`igniter-vm experiment`)

- Event: CLI invocation with `--kernel` / `--entry` / `--config`
- Entry: `.ig` experiment kernel
- No machine-backed effects today; filesystem only
- IO: local `std::fs::write` for `provenance.json`, `summary.json`, `series.csv`, `REPORT.md`
- Future machine wiring: `--package <file.igpkg>` + admitted-package seam feeds `artifact_digest` (P7-prov)
- NO capability passport, NO IngressRouter, NO receipt store — science runner is deliberately isolated
- Cross-cutting concern: provenance schema is authoritative science record; integrity comes from package admission hash, not machine receipts

### Remote node

- Event: HTTP ingress from another igniter-machine instance
- Entry: same `IngressRouter::handle` / `handle_effect` (already handles cross-process HTTP)
- Effects: remote node calls → need `HttpCapabilityExecutor` as outbound client (missing)
- Passport: same bearer token → `CapabilityPassport` model; tokens for remote trust provisioned by host
- Distinction from web runner: the host IS the transport (no igweb.toml, no app routing layer)
- Future card: `LAB-IGNITER-REMOTE-NODE-CAPABILITY-P5` (post-web productization)

---

## 8. Mailbox vs Inline-Read Decision Table

| IO class | Mechanism | Inline or mailbox? | Reason |
|----------|-----------|-------------------|--------|
| Inline read (`ReadThen`) | Async host staged driver, awaited in request | **Inline** | Response must contain rows; no benefit from durable queue; idempotent |
| Final write (`InvokeEffect`) | `MachineEffectHost` → executor, awaited | **Inline with receipt** | Machine receipt IS the durability guarantee; immediate 200/receipt on completion |
| Read-then-write | Sequential: host read → continuation → `InvokeEffect` | **Inline, two steps** | App must see rows before deciding; both steps bounded by request timeout |
| Background / deferred job | Machine receipt gate → async task spawn (unimplemented) | **Deferred, no mailbox yet** | `retry_queue.rs` + `wal.rs` are candidates; not addressable in P2 slice |
| Export (descriptor→bytes) | Sync or async host fn | **Inline** | Pure computation; no external state; no receipt needed |
| File / storage IO | `tokio::fs` or `std::fs` | **Inline** | OS atomics handle crash-safety; no receipt needed |
| Remote node call | `IngressRouter` over HTTP client | **Inline with receipt** | Same idempotency model as local; latency tolerated via caller timeout |
| Experiment artifact | `std::fs::write` | **Inline** | Science runner is single-threaded; output written after experiment completes |

**Mailbox principle:** mailbox/queue semantics are needed only when the caller must decouple from the
effect's completion time AND durability across restarts is required. Today's machine receipt gate provides
idempotency-and-replay but is not a durable queue. Durable background jobs require WAL + explicit worker
pool — this is a separate card, not part of the web runner productization.

---

## 9. Authority and Security Boundary

### What `.ig` contracts NEVER carry

```
capability_id, scope, operation name
DSN, postgres://, host, port, tls, sslmode
Bearer token, passport, secret, signing key
[effects] manifest section
IngressRouter path or pool_id
SQL, raw_sql, query (any string resembling SQL)
ip address, socket, port binding
[pool], [replica], [dedup] config
```

### What the host ALWAYS owns

```
target → ingress route binding  (MachineEffectHost.bind_target)
capability_id → CapabilityExecutor  (CapabilityExecutorRegistry)
Bearer token → CapabilityPassport   (IngressRouter.token)
Effect passport (distinct from serving passport)
Source/field allowlists  (PostgresReadPolicy, PostgresWritePolicy)
Row-limit policy  (PostgresReadPolicy.max_limit)
DuplicatePolicy  (IngressRouter.route_with_strategy)
DSN, TLS config  (operator-owned host.toml, never igweb.toml)
Receipt store     (__receipts__, machine authority)
```

### What the server owns

```
TCP socket binding
TLS termination (future)
Request size limit (BodyLimitApp middleware)
Auth token extraction (AuthTokenApp middleware)
Trace/correlation ID assignment (TraceApp middleware)
serve_loop budget (ServingPolicy.max_requests)
Loopback enforcement (ServingPolicy.loopback_only)
```

### Cross-boundary invariants

- App decision names only logical `target` (not `capability_id`)
- Host injected `idempotency-key` + `x-correlation-id` headers; not sourced from URL params
- Effect idempotency key from app decision OVERRIDES raw request header (normalized value is canonical)
- `EffectBridgeConfig` carries capability registry + receipts backend; never serialized to response
- PassportVerifier uses constant-time comparison (`blake3::verify_keyed_mac`)
- No raw SQL key in `QueryPlan` args (hard error: keys `sql`, `raw_sql`, `query` rejected before adapter)

---

## 10. Backpressure and Failure Model

### Request lifecycle (async mode)

```
accept connection
  → loopback check (if loopback_only)
  → snapshot app (ReloadableApp)
  → middleware stack (BodyLimit → AuthToken → Trace)
  → machine.dispatch(entry, input).await
  → match Decision {
      Respond/RespondView/Render/RenderView → immediate HTTP response
      InvokeEffect →
        passport validation → route → dedup → replica → executor → receipt → response
      ReadThen →
        host gates → adapter query → continuation dispatch → final Decision
    }
  → decrement max_requests budget
  → loop or exit
```

### Failure taxonomy

| Condition | HTTP response | Retry safe? | Notes |
|-----------|--------------|-------------|-------|
| Passport denied (before activation) | 403 | No | No executor reached; no state mutation possible |
| Source/field denied (read gate) | 403 | No | Policy gate; operator config error |
| Raw SQL key in plan | 400/5xx | No | Structural error; app-layer bug |
| Dedup replay (strict policy) | 200 (replayed body) | N/A | Machine receipt found; exact response returned |
| Write committed | 200 | No | Machine receipt + PG receipt committed |
| Write serialization failure | 503 | Yes | Executor KNOWS no mutation occurred |
| Write unknown state | 202 | Reconcile path | Executor cannot determine mutation status |
| Write permanent failure | 5xx | No | Schema/constraint error; deterministic |
| Read transient (adapter) | 503 | Yes | Read is idempotent; retry safe |
| Read unavailable (adapter) | 503 | Yes | Connection unavailable; retry |
| Read not-found (empty rows) | App-owned 404 | N/A | Empty result is NOT an error; continuation decides |
| max_requests budget exhausted | Process exits | N/A | Caller (process manager) restarts; by design |

### Backpressure (current state)

- **max_requests budget** (`ServingPolicy`) — hard lifetime cap per process instance; bounded exit, not concurrency limit
- **SingleFlight gate** — per-idempotency-key serialization for concurrent same-key effects; prevents double-mutation under concurrent load
- **No worker pool limit today** — async tasks spawned per connection; unbounded under high concurrency
- **Needed before production claim:** configurable max-concurrent-effects (tokio `Semaphore` or bounded channel); `429 Too Many Requests` response when concurrency cap exceeded

### Failure model for async runner (P2 target)

```
incoming connection rate  > processing rate  → OS TCP accept backlog (bounded at socket level)
concurrent effects cap    → 429 (Semaphore::try_acquire fails)
adapter unavailable       → 503 (retryable)
adapter timeout           → 503 (retryable; caller must retry with same idempotency_key)
budget exhausted          → process exits; manager restarts; idempotent effects replay cleanly
```

---

## 11. `igweb-serve` Target Shape

### Current shape (async trap)

```
igweb-serve run <app-dir>
  boots: standard library binary, no tokio runtime
  socket: std::net::TcpListener (sync)
  loop: serve_loop (sync, pure reads only)
  dispatch: IgWebServerApp::call (sync, internal block_on per call)
  machine: none (only if caller builds IgWebServerApp with machine feature)
```

**Two compounding hazards:**
1. `std::net::TcpListener` + sync `serve_loop` — cannot await effects or staged reads
2. `IgWebServerApp::call` does `rt.block_on(machine.dispatch(...))` internally — cannot nest this inside
   an outer tokio runtime's async task without `spawn_blocking` or a separate thread-per-request

### Target shape (P2)

```
igweb-serve run <app-dir>                          # mode 1: pure read (default, unchanged)
  tokio runtime: not started
  socket: std::net::TcpListener
  loop: serve_loop (sync)
  dispatch: IgWebServerApp::call

igweb-serve run <app-dir> --host-config host.toml  # mode 2: machine-backed (new)
  tokio runtime: started at binary entry
  socket: tokio::net::TcpListener
  loop: serve_loop_effect (async)
  dispatch: async host driver (bypasses IgWebServerApp::call entirely)
             machine.dispatch(entry, input).await
             match Decision → async host fn arms
```

### Host config file shape (operator-owned, not app manifest)

```toml
# host.toml — operator-owned; never committed with app source
[database]
dsn = "postgres://alex@localhost/igniter_dev"

[[targets]]
name = "todo-create"
route = "/w"
capability = "postgres.write"

[[tokens]]
bearer = "..."           # never in igweb.toml
capability_id = "..."
scopes = ["write"]
```

The `igweb.toml` (app manifest) has no `[effects]`, no DSN, no capability bindings. Those are rejected
at manifest parse time.

### Binary feature gates

```toml
# igweb-serve Cargo.toml (conceptual)
[features]
default = []
machine = ["igniter-machine", "tokio"]   # enables async mode
postgres = ["machine", "tokio-postgres"] # enables real DB adapters
```

Default build stays Postgres-free and tokio-free.

---

## 12. Next Cards with Acceptance Matrices

### `LAB-IGNITER-WEB-ASYNC-MACHINE-RUNNER-P2` (recommended first)

**Scope:** Fix the two async hazards in `igweb-serve`; wire `ReadThen` runner seam; promote P4/P6 harness
proofs to runner tests.

**Acceptance:**

- [ ] `igweb-serve run <app-dir> --host-config host.toml` boots tokio runtime and uses `serve_loop_effect`
- [ ] No nested `block_on` — async host driver calls `machine.dispatch().await` directly (not through `IgWebServerApp::call`)
- [ ] `ReadThen { plan, then }` arm matched in async host driver; staged read executes before continuation
- [ ] P4 write proof promoted: request over real socket → `MachineEffectHost` → fake write executor → machine receipt
- [ ] P6 read proof promoted: real socket request → staged read → continuation dispatch → 200 with rows
- [ ] `host.toml` parsed and validated; rejected if DSN, `[effects]`, or capability fields in `igweb.toml`
- [ ] Default (no `--host-config`) still uses sync `serve_loop`; 0 tokio dep in default build
- [ ] `cargo test` passes (machine feature and default suites)
- [ ] `git diff --check` clean

### `LAB-IGNITER-HOST-CONFIG-SCHEMA-P3`

**Scope:** Define operator-owned `host.toml` schema and parser; reject capability fields from `igweb.toml`.

**Acceptance:**

- [ ] `host.toml` round-trips: DSN, target→route, capability_id, scopes, tokens
- [ ] `igweb.toml` parse rejects `[effects]`, `dsn`, `capability` fields (structural error, not runtime)
- [ ] Operator config loaded from `--host-config` path only, never from app manifest
- [ ] No secrets logged in error messages
- [ ] `git diff --check` clean

### `LAB-IGNITER-POSTGRES-WRITE-REAL-ADAPTER-P4`

**Scope:** Add `TokioPostgresWriteAdapter` (counterpart to `TokioPostgresReadAdapter`) for real PG write.

**Acceptance:**

- [ ] `PostgresWriteAdapter` impl against real `tokio_postgres::Client`
- [ ] Parameterized `INSERT` / `UPDATE` / `DELETE` (no interpolation)
- [ ] PG-side `effect_receipts` table created by host DDL (not by app)
- [ ] Two-layer idempotency: machine receipt check + PG constraint both verified
- [ ] Feature-gated `postgres`; fake adapter remains default
- [ ] `git diff --check` clean

### `LAB-IGNITER-CLI-ASYNC-HOST-P5` (future)

**Scope:** CLI runner gets same async host driver pattern without web semantics.

**Acceptance:**

- [ ] CLI dispatches `.ig` contract through `IgniterMachine::dispatch().await` (no block_on nesting)
- [ ] No HTTP status codes, no correlation_id headers, no `igweb.toml` in CLI path
- [ ] Same `CapabilityPassport` model; passports from operator config, not web headers
- [ ] CLI exits cleanly after one dispatch cycle; no background tokio tasks left running
- [ ] `git diff --check` clean

---

## Evidence Grounding

All findings in this packet are grounded in live source files read 2026-06-22:

- `server/igniter-web/src/bin/igweb-serve.rs` — confirmed sync TcpListener, no machine wiring in binary
- `server/igniter-web/src/lib.rs` — confirmed `rt.block_on` internal pattern; `call()` sync API
- `server/igniter-server/src/serving_loop.rs` — confirmed bounded exit, no tokio spawn
- `server/igniter-server/src/effect_host.rs` — confirmed `serve_loop_effect` + `run_invoke_effect` async
- `runtime/igniter-machine/src/ingress.rs` — confirmed full async ingress + dedup + receipt machinery
- `runtime/igniter-machine/src/capability.rs` — confirmed executor trait, passport model, receipt store
- `runtime/igniter-machine/src/postgres_read.rs` — confirmed structural plan, 6-layer gate, fake adapter
- `runtime/igniter-machine/src/postgres_write.rs` — confirmed typed intent, two-layer idempotency
- `runtime/igniter-machine/src/postgres_real.rs` — confirmed `TokioPostgresReadAdapter`, feature-gated
- `runtime/igniter-machine/src/lib.rs` — confirmed module index; no `experiment.rs` in this crate
- `lang/igniter-vm/src/experiment.rs` — confirmed science runner owns filesystem IO; no machine wiring
- Prior proof docs P3–P10 (IgWeb series), P6-provenance, P9-experiment-runner — read and cross-referenced

No implementation changes made. No CLI changes. No code added or removed.

`git diff --check` must be clean.
