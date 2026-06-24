# Independent Review Report: Hygiene Gemini Verify Wave P5

- **Verdict:** hold
- **Date:** 2026-06-24
- **Reviewer:** Gemini Detective
- **Skill:** idd-agent-protocol

---

## Verdict Description

The repository is on **HOLD** due to active cargo test failures in the fleet sweep under `runtime/igniter-machine` (`test_machine_loads_multifile_app` and `test_machine_fleet_sweep` fail). The exact blockers must be resolved before the next feature wave is launched.

### Exact Blockers

1. **Parser Block Ambiguity on Match Arm Record Literals** (in `igniter-compiler` / `web_router`):
   The parser treats any match arm body starting with `{` as a block body rather than a record literal (implemented in `LAB-LANG-MATCH-ARM-BINDINGS-P2`). Because of this, writing a record literal directly as a match arm body (e.g., `Created { body } => { status: 201, body: body }` in `apps/igniter-apps/web_router/serve.ig`) causes syntax compilation errors (`Unexpected token in expression: Colon`). This breaks the compilation of `web_router` in the fleet sweep.
   - *Actionable Fix:* A temporary workaround in the code is wrapping the record literal in parentheses `({ status: 201, body: body })`, which prevents the parser from matching the leading `{` as a block body. A permanent fix should disambiguate record literals from block bodies at the parser level.

2. **VM Evaluator (`eval_ast`) Lacks Support for `variant_construct`** (in `igniter-vm` / `batch_importer`):
   When a contract uses a variant constructor inside a HOF or lambda body (e.g., in `apps/igniter-apps/batch_importer`), the VM walks the AST using `eval_ast`. However, `eval_ast` in `lang/igniter-vm/src/vm.rs` lacks a case for `variant_construct`, causing a runtime panic/error: `Unsupported AST kind in VM evaluator: variant_construct`. This breaks the execution of `batch_importer` in the fleet sweep.
   - *Actionable Fix:* Implement support for the `variant_construct` AST kind in `eval_ast` (mirroring the compiler's lowering of variants to record literals with `__arm` discriminants).

---

## Findings

### 1. Document Contradicting Live Code
* **Fleet Sweep Test Status**
  * **File Path:** `lang/igniter-vm/IMPLEMENTED_SURFACE.md` and `runtime/igniter-machine/IMPLEMENTED_SURFACE.md`
  * **Evidence:** The docs claim that the 13 fleet apps are all green (RUN-OK 24/25, CLI-parity), but live cargo tests fail on `batch_importer` (runtime dispatch crash) and `web_router` (compile parse error).
* **Test Suite Size Discrepancy**
  * **File Path:** `runtime/igniter-machine/IMPLEMENTED_SURFACE.md`
  * **Evidence:** The header claims "70 tests pass," but the actual test suite has grown to 164 tests (as verified by the cargo test log and line 361 in the same file).
* **Ruby FFI & Magnus Bindings**
  * **File Path:** `README.md`
  * **Evidence:** The root README lists `igniter-ruby` as the owner of the Ruby Framework and package umbrella, and line 38 suggests Ruby is used for runtime playgrounds. However, in-process Ruby FFI Magnus bindings were completely removed from `igniter-machine` on 2026-06-17, and the VM runs exclusively as separate processes interacting over HTTP.
* **OOF-M1 Modifier Enforcement**
  * **File Path:** `../igniter-gov/DELTA-LEDGER.md` (Row D-005)
  * **Evidence:** The delta ledger claims that `observed`/`privileged`/`irreversible` modifiers are not enforced at runtime ("classifier.rs OOF-M1 present but unwired"). Statically, however, they are fully wired and checked by `classifier.rs` and `assembler.rs` which produce compiler diagnostics and block compilation. The VM doesn't perform runtime checks, but the compiler enforces them statically, so they are not "unwired".

### 2. Overclaims
* **Package Admission (`igc package admit`)**
  * **File Path:** `lab-docs/lang/lab-igniter-package-remote-trust-p23-v0.md` and `lab-docs/lang/current-waves-index.md`
  * **Evidence:** Wording around admission suggests it acts as a package execution, deployment, registry, or secure signature solver. The actual implementation is a local, deterministic pre-flight check (verifying tree digests, lock integrity, and compiler versions) without networking or signature validation.
* **Real Postgres support**
  * **File Path:** `runtime/igniter-machine/IMPLEMENTED_SURFACE.md`
  * **Evidence:** Wording around real Postgres support is over-strong. Live code has a loopback/localhost-only, single-connection, DSN-gated driver. It does not support a connection pool, Postgres TLS, advanced schema migrations, or complex filters.
* **Power-Loss Durability**
  * **File Path:** `runtime/igniter-machine/IMPLEMENTED_SURFACE.md`
  * **Evidence:** Durability claims for `MpkFileBackend` state it is "fsync-to-OS; full power-loss durability remains platform-gated (macOS needs F_FULLFSYNC)". On macOS, `F_FULLFSYNC` is not wired, meaning hardware power-loss durability is not guaranteed on all platforms.

### 3. Missing Implemented Surfaces from Front-Door Docs
* **Keyset Pagination (`?after=`)**
  * **Evidence:** Keyset pagination is implemented in `igniter-web` (P47) and `igniter-machine` (using `COLLATE "C"` for text ordering), but is not mentioned in router/web docs outside `IMPLEMENTED_SURFACE.md` and `examples/todo_postgres_app/API.md`.
* **Atomic Concurrency Gate (`SingleFlight`/`run_write_effect_atomic`)**
  * **Evidence:** Closes the double-prepare concurrency race (P18/P7), implemented in `igniter-machine` and wired into `igweb-serve` / `handle_effect`, but not highlighted in high-level sheets.
* **Durable Recovery Sweep**
  * **Evidence:** Startup sweep for dangling `prepared` receipts, undocumented.
* **Configurable Duplicate Policies**
  * **Evidence:** `dedup_strict`/`treat_as_fresh`/`bounded_fresh(n)` on `ServiceRecipe` for repeating webhook handling.

---

## False Blockers Removed

- **Legacy Create Body Compatibility**: Some older docs claim the Todo API must maintain bare string create body support. This legacy compatibility was fully removed in P45, simplifying the contract.
- **Business Key Decoupling**: Replays do not suffer from business ID collision because the business `id` was fully decoupled from the idempotency key (surrogate ID minted by host via Blake3).

---

## Recommended Follow-up Cards (max 5)

1. **`LAB-VM-EVALAST-VARIANT-CONSTRUCT-IMPL-P*`**
   - *Goal:* Implement `variant_construct` in `eval_ast` inside `igniter-vm` to fix the `batch_importer` runtime failure.
2. **`LAB-COMPILER-MATCH-ARM-RECORD-LITERAL-FIX-P*`**
   - *Goal:* Disambiguate block bodies from record literals in match arm parser logic inside `igniter-compiler` to fix the `web_router` compilation failure.
3. **`LAB-TODOAPP-API-PAGINATION-ENVELOPE-READINESS-P*`**
   - *Goal:* Decouple/extend pagination to support the `{items, next}` envelope.
4. **`LAB-PROVENANCE-BRIDGE-ADMITTED-RUNNER-P*`**
   - *Goal:* Bind admitted package identity into experiment provenance.
