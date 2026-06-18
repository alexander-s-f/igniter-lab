# lab-machine-igniter-server-serving-loop-readiness-p5-v0 — serving loop design

**Card:** `GEM-SERVER-B3` (Serving Loop After P4 Readiness)  
**Status:** READINESS / DESIGN — recommended serving loop shape for `igniter-server` after P4 hot-reload.  
**Authority:** Lab-only. Lab evidence does not create canon authority by itself. The Ruby framework is not consulted as language authority.  
**Delegation-Code:** `GEMINI-20260618-SERVER-WAVE-B`

---

## 0. Context & Goal

This document defines the recommended v0 design for the `igniter-server` serving loop (`P5`). Building on the `P2` protocol, `P3` machine effect execution, and `P4` hot-reload mechanics, `P5` defines how the server process processes requests sequentially or concurrently over a reloadable `ServerApp` pointer without turning into an unkillable background daemon.

The core design principle is: **The host owns the loop, transport, and execution cadence; the app owns the decision logic.** The server has no product routing knowledge, and no background worker thread exists to leak state.

---

## 1. Cadence Without Daemon Semantics

To prevent the serving loop from running as an unkillable background daemon, we specify a targeted, structured loop architecture:

1.  **Deterministic Exit Criteria**: The host loop operates over a pre-configured `ServingPolicy` defining a strict `max_requests` budget. The loop terminates and the function returns immediately when this count is reached.
2.  **Explicit Execution Cadence**: The loop owns recovery boot and retry ticks, but does not use background timers or native thread schedulers.
    *   **Boot Recovery**: Executed exactly once (`EffectOrchestrator::boot`) before accepting any connections.
    *   **Tick Cadence**: Orchestrator ticks (`EffectOrchestrator::tick`) are driven on request events (e.g., tick every `N` requests) within the main execution thread or future chain.
    *   **Drain-on-Stop**: An optional `tick_on_stop: bool` runs one final tick after the request budget is exhausted, ensuring a clean exit state.

By executing everything synchronously or inside a single top-level future, when the loop function resolves, the entire process context is cleaned up.

---

## 2. Reloadable App Pointer Integration

The active `ServerApp` is maintained in a reloadable pointer (suggested shape: `Arc<RwLock<Arc<dyn ServerApp>>>` or `Arc<ArcSwap<dyn ServerApp>>>`). The loop integrates with this pointer under the following rules:

1.  **Request-Start Pinning**: At the start of each connection processing iteration, the loop acquires a read lock on the pointer, clones the inner `Arc<dyn ServerApp>`, and releases the lock immediately.
2.  **No Lock Contention**: Because the read lock is held only long enough to perform a pointer copy (an atomic reference increment), contention is minimized even under concurrent execution.
3.  **Request Isolation**: Once cloned, the `Arc<dyn ServerApp>` instance is pinned to that request's call lifecycle. Any hot-swap (updating the pointer via a write lock) affects only subsequent connections. In-flight requests continue executing against the specific app version they started with.

---

## 3. Machine Feature Path & Helper Reuse

Under the `machine` feature gate, the loop reuses the `P3` `MachineEffectHost` adapter and the `P4` reloadable app pointer:

1.  **Layered Pipeline**: The incoming raw stream is parsed by the host into a `ServerRequest`.
2.  **App Evaluation**: The cloned `ServerApp::call` evaluates the request and returns a `ServerDecision`.
3.  **Forwarding and Execution**:
    *   `Respond`: Handled directly by writing `ServerResponse` back to the connection socket.
    *   `Invoke` / `InvokeEffect`: Forwarded to `MachineEffectHost::dispatch`, which translates the request to the `IngressRequest` expected by `ingress::handle_effect`.
4.  **Preservation of Guarantees**: By forwarding decisions through `MachineEffectHost`, the loop inherits exactly-once duplicate filtering (`DuplicatePolicy`), single-flight task collapsing, and database transaction/receipt recording verbatim from the machine core.

---

## 4. Observation-Only Metrics

The serving loop returns a derived summary struct (e.g., `ServingReport` or `ConcurrentServingReport`). This struct is strictly observation-only:

1.  **Scope**: Limited to loop counters (e.g., `requests_served`, `ticks_run`, `retries_drained`).
2.  **No Authority**: The report does not act as a ledger or transaction log. The only authoritative facts remain the receipt log (`__receipts__`) and WAL facts stored in RocksDB/Postgres.
3.  **No Side-Log**: No independent log files or metrics databases are managed by the loop.

---

## 5. Verification Test Suite

To prove the safety of the serving loop, the implementation must pass the following test conditions:

### Test Case 1: No Leaked Worker
*   **Setup**: Run `run_concurrent` using a `ConcurrentServingPolicy` with `max_requests = 10` and `max_in_flight = 3`.
*   **Action**: Wait for the loop to resolve.
*   **Assertion**: Verify that all processed connections are terminated, `FuturesUnordered` is empty, and no background task handles or threads are leaked.

### Test Case 2: No Public Listener
*   **Setup**: Initialize `ServingLoop` with a `TcpListener` explicitly bound to a non-loopback interface (e.g., `0.0.0.0` or a public IP).
*   **Action**: Start the loop.
*   **Assertion**: Verify that the host returns an error or panic before entering the accept loop. The loop must structurally only accept pre-bound local-loopback listeners (`127.0.0.1`).

### Test Case 3: Version Swap Integrity
*   **Setup**: Configure a serving loop with a mock app pointer. Prepare two requests.
*   **Action**: Dispatch request 1 (sees App v1). Swap the pointer to App v2 mid-flight before request 1 completes. Dispatch request 2.
*   **Assertion**: Verify that request 1 resolves using App v1 logic, while request 2 resolves using App v2 logic, with no socket restart.
