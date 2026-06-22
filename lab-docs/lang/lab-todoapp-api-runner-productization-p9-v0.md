# lab-todoapp-api-runner-productization-p9-v0 — Todo API runner contour design

**Card:** `LAB-TODOAPP-API-RUNNER-PRODUCTIZATION-P9` · **Delegation:** `OPUS-TODOAPP-API-RUNNER-PRODUCTIZATION-P9`
**Status:** CLOSED (lab design-proof) — Readiness analysis and design plan for the next productization slice of the Todo API runner shell.

## Verification of Live Status

We analyzed the current codebase of `server/igniter-web`, `server/igniter-server`, and `runtime/igniter-machine` to confirm the exact boundaries of runner manifestation:

1. **Manifest Restrictions (`igweb.toml`)**:
   - The parser strictly rejects any `[effects]` section at load-time (`RunnerError::Manifest("[effects] is unsupported in v0...")`), maintaining the boundary that effect target bindings are host-side infrastructure topology, not application concern.
   - It contains no fields or parser support for database configurations (e.g., DSNs, TLS, table policies, or capabilities).

2. **Postgres Connectivity**:
   - Database connections and DDL setups are entirely test-only today. They are controlled by test harnesses (`tests/todo_postgres_local_e2e_tests.rs`) using environment variables.
   - The CLI runner (`igweb-serve`) has no database awareness or feature gating to connect to tokio-postgres.

3. **ReadThen Concept**:
   - **Status as of 2026-06-22:** `ReadThen` is `designed` and `harness-proven`, but not `implemented` and not `runner-integrated`.
   - Live source inventory: `rg "ReadThen|read then|staged read"` over `lang/igniter-compiler/src`, `server/igniter-web/src`, `server/igniter-server/src`, and `lang/igniter-vm/src` returns no source matches. The injected IgWeb prelude `Decision` arms are `Respond`, `InvokeEffect`, `RespondView`, `Render`, and `RenderView`; `server/igniter-web/src/lib.rs::map_decision` maps those five final arms only; `server/igniter-server/src/protocol.rs::ServerDecision` has `Respond`, `Invoke`, and `InvokeEffect`.
   - Category snapshot:
     - `designed`: yes — P5/P10 describe `ReadThen { plan : Unknown, then : String }`.
     - `harness-proven`: yes — read host tests hand-orchestrate `QueryPlan -> host_read -> rows_json -> continuation`.
     - `implemented`: no — no prelude arm, compiler lowering, VM opcode/eval path, or `map_decision` arm exists.
     - `runner-integrated`: no — `igweb-serve` does not drive staged reads.

4. **Async/Sync Hazards**:
   - The current `igweb-serve` binary runs synchronously via `std::net::TcpListener` and `serving_loop::serve_loop`.
   - The `MachineEffectHost` and postgres adapters execute asynchronously via Tokio (`IngressRouter::handle_effect` is `async` and uses `.await`).
   - Wiring them requires running the runner loop within an asynchronous context (`serve_loop_effect`) under a Tokio runtime.

---

## Required Answers

### 1. Which seam should productize first: write, read, or config?
**Config (local Postgres config/manifest shape)**. Before the runner can execute write effects or read operations, the host needs a clean way to receive operator-owned configurations (e.g., database connection credentials, host security policies, target-to-ingress-route bindings) without hardcoding them in the Rust binary or violating the boundary that the application manifest `igweb.toml` remains authority-free. 

### 2. What is operator-owned config and what remains app-owned?
- **Operator-owned (host config)**:
  - Connection DSN (`postgres://...`) and TLS/SSL settings.
  - Logical target mappings to ingress routes (e.g., `"todo-create" -> "/w"`).
  - Security policies (e.g., allowlisted tables, allowable operations like `select` / `insert` / `upsert`).
  - Access control passports and bearer tokens.
- **App-owned (application folder)**:
  - Contract and route definitions (`.ig` / `.igweb` files).
  - Entry point module/contract selection.
  - Logical targets invoked by the app (e.g., `InvokeEffect { target: "todo-create" }`), but not their destination pools or credentials.

### 3. What must stay test-only?
- **Database DDL (schemas)**, migrations, and mock data seeding. The IgWeb runtime is a data access and transaction execution engine, not an ORM or migration framework. Database setup remains outside the compiler/runner boundary.

### 4. What is the smallest command a developer would run?
A command that specifies the application directory and passes the database credentials through the host environment or a separate operator configuration file:
```bash
IGNITER_TODO_PG_DSN="postgres://localhost/todo_dev" igweb-serve run --host-config host.toml examples/todo_postgres_app
```

### 5. Which parts are blocked by async/socket-loop shape?
The synchronous blocking loop in `igweb-serve.rs` (`std::net::TcpListener`) is blocked from executing asynchronous Tokio-based write effects and Postgres queries. The runner main function must be updated to boot a Tokio runtime and run the async `serve_loop_effect` loop.

---

## Next Implementation Card

### `LAB-TODOAPP-API-RUNNER-CONFIG-P10` — Local Postgres Config & Async Runner Wiring

Naming note: `LAB-IGNITER-WEB-READTHEN-RUNNER-P10` is already active in the current workstream. If this config
slice is opened, use a non-colliding card id (for example `LAB-TODOAPP-API-RUNNER-CONFIG-P11`).

#### Goal
Implement the operator/host-config parser, migrate the `igweb-serve` CLI to an asynchronous loop under a Tokio runtime, and wire up the `MachineEffectHost` to resolve database connections dynamically from host configuration.

#### Scope & Closed Boundaries
- **No DDL/Migration**: The runner will execute against an existing DB schema. No migration capabilities will be added.
- **No Public Bind**: The serving loop remains bounded and loopback-only.
- **Operator Config**: Define a host configuration file (`host.toml` or `runner.toml`) to declare:
  - Postgres DSN and TLS mode.
  - Target-to-ingress-route mappings.
  - Allowed read/write table policies.

#### Acceptance Criteria
1. `igweb-serve` supports an optional `--host-config <file>` CLI flag.
2. The runner boots an async Tokio runtime and runs the async `serve_loop_effect` when the `machine` or `postgres` features are active.
3. Logical targets are mapped to ingress routes dynamically based on the host config.
4. Reads/writes fail gracefully when the database is unavailable, mapping to structured responses.
5. All existing test suites remain green.
