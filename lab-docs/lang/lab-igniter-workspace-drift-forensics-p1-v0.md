# Igniter Workspace Drift Forensics Report

**Card:** LAB-IGNITER-WORKSPACE-DRIFT-FORENSICS-P1
**Status:** COMPLETE (forensic report)
**Date:** 2026-06-22
**Authority:** Lab evidence and workspace hygiene analysis. No code changes, no file moves.

---

## 1. Executive Summary: Top 5 Drift Risks

The following are the five most critical drift and alignment risks identified across the workspace:

1. **Async/Sync Serving Loop Hazard**: The primary CLI runner `igweb-serve` executes a synchronous loop over a blocking `std::net::TcpListener`, making it impossible to run live async database effects (via `tokio-postgres` and `MachineEffectHost`) despite tests claiming end-to-end support by bypassing the CLI.
2. **Stale Deliverable Paths in Closed Cards**: `LAB-STDLIB-NET-P9` was resolved by `LAB-HYGIENE-NET-P9-PATHS-P5` on 2026-06-22; broader closed-card path drift remains a hygiene risk.
3. **Stale Workaround in Emergence Kernels**: The public `igniter-emergence` Kuramoto kernel still contains a complex workaround (returning `Collection[Float]` instead of `Collection[Oscillator]`) due to a documented record-construction-in-lambdas limitation that was actually fixed and regression-tested.
4. **Workspace-Level Directory Restructuring Out of Sync**: The root `README.md` and `igniter-lab-value-transfer.md` document flat subproject structures directly under `igniter-lab/` (e.g., `igniter-compiler/`), while in reality, they have been nested under domain umbrellas (`lang/`, `runtime/`, `server/`, `frame-ui/`).
5. **Card ID Suffix Collisions (P9/P22)**: Suffixes like `P9` and `P22` are duplicated across completely different cards in the same folder, confusing agents and leading to tracking collisions.

---

## 2. False Blockers

These are areas where documentation or cards claim a feature is "blocked" or "deferred," but the live code or tests show it is fully implemented and operational:

*   **Inconsistency 1: Single-Package Admission Block**:
    *   *Stale Claim*: In `igniter-lab/lab-docs/lang/lab-igniter-package-remote-trust-readiness-p22-v0.md` (lines 15-18), single-package admission was described as a gap since the compiler's safe-archive-entry checker blocked the root path `.` as unsafe.
    *   *Live Truth*: The issue was resolved in card `LAB-IGNITER-PACKAGE-EMERGENCE-PACK-P24`. The compiler code in `igniter-lab/lang/igniter-compiler/src/project.rs` (line 1297) now explicitly accepts `.` as a safe entry path:
        ```rust
        fn is_safe_archive_entry_path(path: &str) -> bool {
            path.is_empty() || path == "." || is_safe_archive_path(path)
        }
        ```
*   **Inconsistency 2: Lambda Record Construction Workaround**:
    *   *Stale Claim*: The kernel file `igniter-emergence/kernels/kuramoto_per_omega_tick.ig` (lines 11-15) documents that constructing a new record in a lambda body (e.g., `o -> ({theta: ..., omega: ...})`) compiles but crashes the VM with `"Unsupported operator: stdlib.collection.map"`.
    *   *Live Truth*: The nested-HOF execution fixes in P3 and P4 resolved this. Record literals can be constructed in lambda bodies if parenthesized. This is verified by the regression test in `igniter-lab/lang/igniter-vm/tests/record_construction_in_lambda_tests.rs` (lines 78-95), where `kuramoto_per_omega_record_tick_executes` runs successfully.

---

## 3. Real Blockers

These are blockers that are verified to still be active and unresolved in the live code:

*   **Inconsistency 3: Async/Sync Runner Socket Hazard**:
    *   *Blocker*: `igweb-serve` (in `igniter-lab/server/igniter-web/src/bin/igweb-serve.rs` line 37) binds a blocking `std::net::TcpListener`:
        ```rust
        let listener = TcpListener::bind(cli.addr)?;
        ```
        However, the `MachineEffectHost` and the Postgres database write effects require async execution (the `serve_loop_effect` in `igniter-lab/server/igniter-server/src/effect_host.rs` line 232 is an `async fn` taking `&tokio::net::TcpListener`). Running live database writes under `igweb-serve` is blocked until the main CLI loop is migrated to an async Tokio runtime.
*   **Inconsistency 4: Unwired Experiment Provenance Artifact Digest**:
    *   *Blocker*: The experiment runner provenance builder in `igniter-lab/lang/igniter-vm/src/experiment.rs` (line 969) hardcodes the `artifact_digest` to `None` / `null`:
        ```rust
        let provenance = build_provenance_json(
            &config.kernel_mode,
            &args.entry,
            &meta.kernel_source,
            &meta.kernel_hash,
            &meta.config_hash,
            &meta.compiler_version,
            &meta.stdlib_version,
            None,
        );
        ```
        The admitted `.igpkg` artifact identity from package admission is completely unwired from the experiment runner's outputs.
*   **Inconsistency 5: ReadThen VM/Compiler Support**:
    *   *Status as of 2026-06-22*: `ReadThen` is `designed` and `harness-proven`, but not `implemented` and not `runner-integrated`.
    *   *Live source inventory*: `rg "ReadThen|read then|staged read"` over `lang/igniter-compiler/src`, `server/igniter-web/src`, `server/igniter-server/src`, and `lang/igniter-vm/src` returns no source matches. The IgWeb prelude currently has final `Decision` arms `Respond`, `InvokeEffect`, `RespondView`, `Render`, and `RenderView`; `map_decision` handles those final arms; `ServerDecision` has `Respond`, `Invoke`, and `InvokeEffect`.
    *   *Implication*: P5/P10 design prose and P6/P7 read harnesses are evidence for the staged-read shape, not proof that a live `ReadThen` arm or runner exists. Agents should route implementation to a `ReadThen` dispatch/runner card, not assume it is active.

---

## 4. Overclaims

These are instances where documentation implies production-level, canonical, or stable behavior, but it is actually only lab evidence:

*   **Inconsistency 6: SparkCRM Route Shape Claims**:
    *   *Overclaim*: The document `igniter-lab/lab-docs/lang/lab-igniter-web-sparkcrm-route-shape-p5-v0.md` implies deep compatibility and scaling with SparkCRM's real route table.
    *   *Live Truth*: This is a static file characterization only. There is no active SparkCRM execution, no Ruby FFI integration, and no live database access. It is purely diagnostic data pressure.
    *   *P8 hygiene verification (2026-06-22)*: The route-shape doc already carries this scope guard in its title/status, acceptance mapping, closed scope, and footer. No route-shape doc edit was needed.
*   **Inconsistency 7: Float Determinism and PRNG Swarm Claims**:
    *   *Overclaim*: Docs in `igniter-lab/lab-docs/lang/lab-stdlib-math-determinism-readiness-p3-v0.md` discuss cross-architecture float determinism.
    *   *Live Truth*: The claim is a fixed-algorithm/golden-vector lab surface through vendored pure-Rust `libm`; qemu cross-arch and physical multi-arch identity remain pending proof gates.

---

## 5. Status Hygiene

These are status discrepancies between cards, status reports, and live files:

*   **Inconsistency 8: Stale Test Failure Claims in STATUS.md**:
    *   *Discrepancy*: `igniter-lab/lab-docs/STATUS.md` (lines 47-49) states that `igniter-compiler` has 4 failing `loop_conformance_tests` and `igniter-vm` has 1 failing `vm_candidate_proof_tests`.
    *   *Live Truth*: Targeted rechecks pass: `cargo test --test loop_conformance_tests` in `lang/igniter-compiler` reports 14/14 passed, and `cargo test --test vm_candidate_proof_tests` in `lang/igniter-vm` reports 9/9 passed. The status file is stale.
*   **Inconsistency 9: Stale Deliverable Paths for LAB-STDLIB-NET-P9**:
    *   *Resolved 2026-06-22 by `LAB-HYGIENE-NET-P9-PATHS-P5`*: Card `igniter-lab/.agents/work/cards/lang/LAB-STDLIB-NET-P9.md` now lists the post-rehome paths `frame-ui/igniter-view-engine/fixtures/network_http_client/mock_transport_table_domain.json` and `frame-ui/igniter-view-engine/proofs/network_http_upstream_call_contract_proof.rb` as "DONE".
    *   *Live Truth*: The files exist at `igniter-lab/frame-ui/igniter-view-engine/fixtures/network_http_client/mock_transport_table_domain.json` and `igniter-lab/frame-ui/igniter-view-engine/proofs/network_http_upstream_call_contract_proof.rb`. This was path drift, not a missing deliverable.

---

## 6. Path/Reorg Drift

These are stale paths that refer to locations prior to workspace reorganization:

*   **Inconsistency 10: Workspace README.md subproject mapping**:
    *   *Drift*: The workspace-level `README.md` (lines 60-79) lists paths directly under `igniter-lab/` (e.g., `igniter-compiler/`, `igniter-vm/`, `igniter-stdlib/`).
    *   *Live Truth*: The directories have been moved under domain umbrellas (e.g., `igniter-lab/lang/igniter-compiler`, `igniter-lab/lang/igniter-vm`, `igniter-lab/lang/igniter-stdlib`).
*   **Inconsistency 11: igniter-view-engine Split and Duplication**:
    *   *Drift*: The workspace root lists `igniter-view-engine` as a top-level repository (`/Users/alex/dev/projects/igniter-workspace/igniter-view-engine`), but a second `igniter-view-engine` exists under `igniter-lab/frame-ui/igniter-view-engine` as a stub.
*   **Inconsistency 12: Stale targets in igniter-lab-value-transfer.md**:
    *   *Drift*: `igniter-lab/igniter-lab-value-transfer.md` (lines 52-71) lists targets like `igniter-gui-engine/` and `igniter-design-system/` relative to the flat workspace root, ignoring that they are now nested inside `igniter-lab/frame-ui/`.

---

## 7. Naming Collisions & Ambiguous IDs

Card suffixes are duplicated heavily within the flat `.agents/work/cards/lang` directory:

1.  **Duplicate P9 Suffixes**:
    *   `LAB-IGNITER-EXPERIMENT-RUNNER-PROVENANCE-P9`
    *   `LAB-TODOAPP-API-RUNNER-PRODUCTIZATION-P9`
    *   `LAB-MACHINE-CAPABILITY-IO-RETRY-QUEUE-P9`
    *   `LAB-FRAME-UI-KIT-FORMS-P9`
    *   `LAB-STDLIB-NET-P9`
    *   `LAB-MACHINE-IGNITER-SERVER-EXAMPLE-APP-READINESS-P9`
    *   `LAB-IGNITER-PACKAGE-MODULE-EXPORTS-READINESS-P9`
    *   `LAB-STDLIB-MATH-NBODY-PRESSURE-P9`
2.  **Duplicate P22 Suffixes**:
    *   `LAB-IGNITER-PACKAGE-REMOTE-TRUST-READINESS-P22`
    *   `LAB-IGNITER-PACKAGE-ARCHIVE-PACK-VERIFY-P22`
    *   `LAB-HOMELAB-HP-BUNDLE-BUILD-VERIFY-P22`
    *   `LAB-IGNITER-WEB-VIEWARTIFACT-CONDITIONAL-LISTS-P22`
    *   `LAB-IGNITER-WEB-ROUTING-COMPOSITE-GUARD-P22`

---

## 8. Agent Footguns

The following workspace patterns frequently cause agents to waste time:

1.  **Trusting proof docs over live compiler/VM state**: Agents read old design proofs (such as P9 or P10) and assume features like `ReadThen` are implemented, or that certain record-in-lambda structures are blocked, without checking live tests.
2.  **Ambiguous P-number card references**: When told to work on "P9" or "P22," agents may open the wrong card due to flat directory name collisions in `.agents/work/cards/lang/`.
3.  **Executing blocking cargo commands**: Running compiler/VM tests without checking feature flags (like `postgres` or `machine`) leads to compile or database connection failures.
4.  **Implicit file:// vs raw paths**: Formatting report references with `file://` URIs instead of raw paths violates transfer boundaries and breaks document portability.

---

## 9. Recommended Hygiene Cards

The following are 7 concrete, small hygiene cards recommended for the next wave:

1.  **`LAB-HYGIENE-STALE-PATHS-README-P1`**: Update the root `README.md` and `igniter-lab-value-transfer.md` to reflect the current domain-umbrella nesting (`lang/`, `runtime/`, `server/`, `frame-ui/`, `ide/`).
2.  **`LAB-HYGIENE-STATUS-CLEAN-P2`**: Update `lab-docs/STATUS.md` to show that all compiler and VM tests are 100% green at HEAD.
3.  **`LAB-HYGIENE-EMERGENCE-KERNEL-SIMPLIFY-P3`**: Update `igniter-emergence/kernels/kuramoto_per_omega_tick.ig` to return `Collection[Oscillator]` directly and delete the stale workaround comments now that parenthesized record literals in lambdas are verified.
4.  **`LAB-HYGIENE-CARD-NAMES-P4`**: Rename duplicated card filenames in `.agents/work/cards/lang/` to include unique lane prefixes (e.g. `LAB-LANG-STDLIB-NET-P9.md` or `LAB-SERVER-TODOAPP-API-P9.md`) to avoid name collisions.
5.  **`LAB-HYGIENE-NET-P9-PATHS-P5`**: CLOSED 2026-06-22. `LAB-STDLIB-NET-P9` and adjacent docs now point at the post-rehome `frame-ui/igniter-view-engine/...` deliverable paths.
6.  **`LAB-TODOAPP-API-RUNNER-CONFIG-P11`**: Migrate the `igweb-serve` CLI to an async loop under a Tokio runtime to resolve the async socket hazard for Postgres effects.
7.  **`LAB-PROVENANCE-BRIDGE-P6`**: Wire the package admission `artifact_digest` into the experiment runner's `provenance.json` rather than passing `None`.

---

## 10. Appendix: Commands Run and Skipped Checks

### Commands Run
*   `cargo test` inside `igniter-lab/lang/igniter-compiler` (Completed: 50 tests passed, 0 failed).
*   `cargo test` inside `igniter-lab/lang/igniter-vm` (Completed: 67 tests passed, 0 failed).

### Skipped Checks
*   Skipped running any database migrations or live Postgres instances (out of scope).
*   Skipped physical cross-architecture hardware checks on ESP32 (out of scope).
