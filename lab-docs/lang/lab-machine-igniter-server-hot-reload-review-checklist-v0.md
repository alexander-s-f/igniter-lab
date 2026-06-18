# lab-machine-igniter-server-hot-reload-review-checklist-v0 — P4 Hot Reload Review Checklist

**Delegation-Code:** `GEMINI-20260618-SERVER-WAVE-B`  
**Status:** DRAFT / REVIEW-ONLY  
**Target Card:** `LAB-MACHINE-IGNITER-SERVER-HOT-RELOAD-P4`  
**Scope:** Review and audit criteria for hot-swapping `ServerApp` instances dynamically within the `igniter-server` shell.

---

## 1. Arc Clone Lock Scope
* **Criterion:** The read lock on the active application reference container (e.g., `RwLock<Arc<dyn ServerApp>>`) must be held for the minimum duration required to clone the `Arc` pointer.
* **Audit Steps:**
  1. Inspect `serve_once_reloadable` and `serve_once_effect_reloadable` in
     `igniter-server/src/host.rs` and `igniter-server/src/effect_host.rs`.
  2. Verify that the read lock guard is explicitly dropped or goes out of scope *before* calling `app.call(req)` or executing the resulting `ServerDecision`.
  3. Ensure the scoping matches the targeted pattern:
     ```rust
     let app = {
         let guard = active_app.read().unwrap();
         guard.clone()
     }; // Lock guard is dropped here
     
     let decision = app.call(req);
     ```
* **Anti-patterns:** 
  - Calling `active_app.read().unwrap().call(req)` directly, which extends the read lock guard lifetime across the entire request lifecycle, serializing request execution and introducing deadlocks.

---

## 2. Trait Object Send+Sync Shape
* **Criterion:** Reloadable/concurrent host surfaces must use a thread-safe trait object
  (`dyn ServerApp + Send + Sync`) when moving app instances across threads. The base `ServerApp`
  trait may remain protocol-simple; the important boundary is the host-owned reloadable pointer.
* **Audit Steps:**
  1. Inspect the reloadable pointer type in `igniter-server/src/reload.rs`.
  2. Verify that the active pointer uses `Arc<dyn ServerApp + Send + Sync>`:
     ```rust
     Arc<RwLock<Arc<dyn ServerApp + Send + Sync>>>
     ```
  3. Verify that the fixture `DemoApp` and any test mock apps satisfy the `Send + Sync` compiler
     constraints when wrapped in `ReloadableApp`.

---

## 3. In-Flight Isolation
* **Criterion:** A swap of the active `ServerApp` pointer in the host must have zero effect on active requests currently in flight.
* **Audit Steps:**
  1. Verify that active requests hold a strong clone of the `Arc<dyn ServerApp>`.
  2. Verify that the old application instance remains fully allocated, immutable, and functional until the last request utilizing it finishes and drops its `Arc` clone.
  3. Check the test suite in `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-server/tests/` to ensure a test explicitly validates in-flight isolation (e.g., using a slow/delayed mock application, swapping the pointer mid-request, and asserting that the old request returns the old app's output).

---

## 4. AppIdentity as Observability, Not Authority
* **Criterion:** `AppIdentity` metadata (`name`, `version`, `digest`) must remain strictly targeted at observability, telemetry, and auditing. It must never represent authority or drive routing logic in the host.
* **Audit Steps:**
  1. Inspect `igniter-server/src/host.rs` and `igniter-server/src/effect_host.rs` to ensure that
     the host never branches on `AppIdentity` values.
  2. Ensure the host only routes requests based on the structured data in `ServerDecision` (`Respond`, `Invoke`, `InvokeEffect`), maintaining the target separation of concerns.
  3. Confirm that the application identity fields are only used to populate structured JSON audit logs or HTTP response headers (e.g. `X-App-Version`).

---

## 5. No Middleware Mixed into P4
* **Criterion:** The P4 implementation must remain strictly focused on hot-reloading the `ServerApp` instance. It must not introduce request filter pipelines, interceptors, or middleware wrappers.
* **Audit Steps:**
  1. Verify that no middleware traits or wrapper structs are introduced.
  2. Confirm that request flow remains: `ServerRequest` -> `ServerApp::call` -> `ServerDecision` -> `host::execute` / `dispatch`.
  3. Ensure that any future middleware design is isolated to separate, dedicated cards.

---

## 6. No Daemon, File Watcher, or Public Listener
* **Criterion:** The server shell must stay protocol-first, exit-controlled, and local loopback-only.
* **Audit Steps:**
  1. Verify that the host is NOT daemonized and does not spawn automatic background file-watching threads (e.g., watching a directory for new binary builds or configuration changes).
  2. Confirm that swapping `ServerApp` references is done programmatically by the host wrapper or test harness.
  3. Verify that `Cargo.toml` contains no automatic reload or filesystem-watching crates (such as `notify` or `hotwatch`).
  4. Confirm that the listener binds to `127.0.0.1` only. Public binds (e.g., `0.0.0.0`) are forbidden.

---

## 7. Machine-Feature Regression Expectations
* **Criterion:** The addition of hot reload must not break the existing default (protocol-only) or gated (`machine`) builds and tests.
* **Audit Steps:**
  1. Run the default test suite to ensure protocol and loopback tests compile and pass:
     ```bash
     cargo test
     ```
  2. Run the gated test suite to ensure effect host integration tests compile and pass:
     ```bash
     cargo test --features machine
     ```
  3. Verify that the changes did not modify or break any `igniter-machine` regression test surfaces.
