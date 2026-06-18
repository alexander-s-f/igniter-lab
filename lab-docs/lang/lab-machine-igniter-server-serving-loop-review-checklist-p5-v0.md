# lab-machine-igniter-server-serving-loop-review-checklist-p5-v0 — Serving Loop P5 Reviewer Checklist

**Delegation-Code:** `GEMINI-20260618-SERVER-WAVE-C`  
**Status:** RECOMMENDED CHECKLIST (v0)  
**Target Card:** `LAB-MACHINE-IGNITER-SERVER-SERVING-LOOP-P5`  
**Scope:** Review criteria for the bounded serving loop implementation over the reloadable app pointer
in `igniter-server`. **No public network bindings, no live databases, no credentials, and no live
SparkCRM integrations.**

---

## 1. Loop Cadence & Process Bounds

### Bounded Max Requests (No Unbounded Daemon)
* [ ] **Strict request budget**: Verify the host loop accepts an explicit serving policy configuration defining `max_requests`.
* [ ] **Deterministic termination**: Verify the serving loop terminates and returns control immediately once the `max_requests` count is reached.
* [ ] **No infinite loops**: Confirm there is no code path or default value that allows the server loop to run indefinitely or without a pre-configured exit budget.

### Cadence & Pacing Ownership
* [ ] **Host owns cadence when enabled**: If a later machine-enabled serving loop wires recovery boot (`EffectOrchestrator::boot`) or tick pacing (`EffectOrchestrator::tick`), verify that the host drives it explicitly. The default P5 loop may keep orchestrator cadence absent/deferred.
* [ ] **App is pure data**: Confirm that the application layer (`ServerApp`) does not drive or schedule a tick timeline, remaining a stateless decision function.
* [ ] **No background timers**: Ensure there are no background scheduling threads, `std::thread::sleep` loops, or system cron integrations pacing the loop.

---

## 2. Worker Leak Protection

### No Detached Work
* [ ] **No leaked background workers**: Verify the loop uses structured concurrency (such as polling futures inside a `FuturesUnordered` container) to process requests concurrently rather than detaching tasks via `tokio::spawn`.
* [ ] **Sequential is acceptable**: If the v0 loop is sequential, verify that it uses no concurrency
      primitives and therefore has no worker to leak.
* [ ] **Resource lifetime bound**: If a future concurrent helper is introduced, confirm that all
      concurrent connection tasks are bound to the lifecycle of the loop's future, ensuring that if
      the loop is cancelled or returns, all active futures are immediately dropped/cancelled and no
      network handles or workers are leaked.
* [ ] **Justification of tokio::spawn**: If `tokio::spawn` is explicitly used, verify that it is accompanied by a robust, test-proven join-on-shutdown handle map and documented architectural necessity.

---

## 3. Reloadable App Pointer Integration

### Snapshot and Lock Pacing
* [ ] **Request-start pinning**: Verify that at the start of processing each connection, the loop acquires a read lock on the reloadable pointer (`ReloadableApp`), clones the active `Arc<dyn ServerApp>`, and releases the lock immediately.
* [ ] **No execution under lock**: Confirm that the read lock is dropped before the loop evaluates `app.call(request)` or executes any returned decisions, preventing lock contention under concurrent request storms.
* [ ] **Swap isolation**: Verify that calling `ReloadableApp::swap` updates the active pointer for future requests only, while in-flight requests continue executing to completion against the specific `ServerApp` snapshot they started with.

---

## 4. Machine/Effect Path & Helper Reuse

### Integration with P3/P4 Contours
* [ ] **Feature-gated reuse**: Under `#[cfg(feature = "machine")]`, verify that the loop forwards decisions to `MachineEffectHost` and executes `InvokeEffect` through `ingress::handle_effect`.
* [ ] **No logic duplication**: Ensure that the loop does not re-implement duplicate filtering, database write routing, or execution gates, relying entirely on the proven machine ingress contour.
* [ ] **Preservation of invariants**: Confirm that executing `InvokeEffect` through the loop inherits exactly-once guarantees (`DuplicatePolicy`) and single-flight request collapsing.
* [ ] **Zero effect-identity leakage**: Verify that the app decisions never carry fields like `capability_id`, `operation`, or `scope`.

---

## 5. Security & Network Boundaries

### Loopback-Only Socket Binding
* [ ] **Pre-bound listener**: Verify the serving loop accepts a pre-bound `TcpListener` passed by the caller, rather than binding sockets internally.
* [ ] **Loopback enforcement**: Verify the loop never binds sockets itself. If an opt-in
      `loopback_only` policy exists, verify it refuses non-loopback listeners before accepting. Do
      not require this policy to be always-on unless a later deployment card explicitly opens that
      authority.
* [ ] **No public ingress exposure**: Verify that no part of the server code enables public connections or exposes endpoint routers to the external network.

---

## 6. Observability & Metrics

### Observation-Only Reports
* [ ] **Derived stats**: Verify the loop returns an informational summary struct (e.g., `ServingReport` or `ConcurrentServingReport`) containing simple loop statistics (requests processed, ticks executed, retries drained).
* [ ] **No transactional authority**: Confirm that the returned report is never treated as a ledger. Authoritative transaction and effect history must reside solely in the machine's `__receipts__` and audit logs.
* [ ] **No independent log writers**: Ensure the loop does not manage separate metrics files or external database writes.

---

## 7. Expected Test Coverage

### Default Build (Machine-Free, Protocol/Reload Only)
* [ ] **Sequential stop**: Verify sequential serving terminates exactly at `max_requests`.
* [ ] **No leaked worker**: Verify the v0 loop terminates cleanly. If it is sequential, the proof is
      absence of spawned workers; if a concurrent helper exists, verify all in-flight futures are
      joined/dropped by loop completion.
* [ ] **Safe hot swap**: Assert that swapping the app pointer mid-flight resolves the in-flight request on `v1` while subsequent requests resolve on `v2` without restarting the listener.
* [ ] **Listener check**: If `loopback_only` is enabled, verify that attempt to start the loop with a listener bound to a public port fails before entering the accept loop.

### Gated Build (`--features machine`)
* [ ] **Committed loopback execution**: Assert that executing `InvokeEffect` through the serving loop commits the effect to the InMemory/RocksDB backend and records a valid receipt.
* [ ] **Deduplication preservation**: Verify that replaying requests with duplicate keys yields cached response receipts and executes zero additional write attempts.
* [ ] **Single-flight verification**: Verify that concurrent, identical-keyed requests collapse to exactly one write effect execution.
