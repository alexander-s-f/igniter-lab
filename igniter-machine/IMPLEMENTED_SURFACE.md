# igniter-machine — Implemented Surface

**Status:** live implementation index for the fused machine (compiler + VM + tbackend
in one process). **Verify-first:** any doc claiming this is "only a PROP-042 sketch"
or "not implemented" is **stale** — this file + `cargo test` are ground truth.
Last verified: **2026-06-15** (70 tests pass, `cargo test --no-default-features`).

> Reality check: the old `igniter-delta-1.md` claim that igniter-machine "contains
> only PROP-042.md" is FALSE. It is a working, tested fused kernel.

> **Capability IO front door:** the read/write capability IO rows below (P1–P6b) are one
> coherent track — read `.agents/work/cards/lang/LAB-MACHINE-CAPABILITY-IO-MILESTONE-P1.md`
> before pulling any single slice out of context.

## Kernel API (`src/machine.rs::IgniterMachine`)

| Capability | Status | How |
|---|---|---|
| construct | ✅ | `new(data_dir, "in_memory" \| "rocksdb" \| "remote_tcp[:addr]")` |
| compile + load source | ✅ | `load_contract_source(src, name)` — full front-end pipeline in-process; **registers ALL contracts in the source** (by `contract_name` field) |
| multi-file load | ✅ | `load_program(paths, name)` — `multifile::compile_units` merges modules+imports → single program → registers all (runs real fleet apps) |
| diagnostics only | ✅ | `check_source(src)` → typed diagnostics (no register) |
| dispatch (run) | ✅ | `dispatch(name, inputs)` → VM execute; **builds dispatch_table from the whole registry** so cross-contract `call_contract` resolves |
| bitemporal facts | ✅ | `write_fact` / `read_fact(store, key, as_of)` (transaction-time axis) |
| **bitemporal query** | ✅ | `read_bitemporal(store, key, valid_at, known_at)` — both axes explicit (`known_at`=transaction/audit, `valid_at`=valid/effective); `valid_time=None` strictly excluded. Default trait method → all backends. (LAB-MACHINE-BITEMPORAL-AXIS-P1) |
| checkpoint | ✅ | `checkpoint(.igm)` / `checkpoint_bytes()` — MessagePack `SemanticImage{contracts(BTreeMap), facts(sorted), observations}`; **deterministic → byte-identical roundtrip** |
| resume | ✅ | `resume(.igm)` / `resume_bytes(&[u8])` — restores contracts + facts (in-memory capsule) |
| **capsules (control panel)** | ✅ | `capsule::CapsuleManager` — named immutable frames: `snapshot`/`list`/`instantiate`/`activate`(dispatch over a frame)/`fork`(branch+patch+freeze). Filmstrip-proven (immutable base, divergent forks, same activation diverges). + filmstrip activate_many; 6 live MCP tools (capsule_snapshot/list/activate/fork/diff/activate_many), agent-driven. (LAB-MACHINE-CAPSULE-MANAGER-P1) |
| inherits the VM wave | ✅ | path-dep on `igniter_vm` → closures / match / HOF / dispatch-unification all run through `dispatch` |
| **capability IO boundary** | ✅ (fake-executor proof) | `capability::{CapabilityExecutor, CapabilityExecutorRegistry, run_effect}` — ServiceLoop-like data-plane: preflight authority/idempotency → executor once → **receipt written as a bitemporal fact** (store `__receipts__`) → typed outcome. Idempotency = receipt lookup; replay = executor bypass; `unknown_external_state` kept epistemic (≠ failure); denial-as-data. `TBackend` = first proven capability family. **Fake executors only** (Echo/KvRead) — no real DB/HTTP. (LAB-MACHINE-CAPABILITY-IO-P1) |
| **declared-effect host entrypoint** | ✅ (fake-executor proof) | `service_loop::{discover_effect_surface, run_service, EffectDescriptor, HostRequest}` — discovers a contract's declared effect surface from its **already-emitted IR** (`modifier`/`capabilities[{name,type}]`/`effects[{name,capability_ref}]`), resolves effect→capability→executor, routes through `run_effect` with `machine.storage` as the receipt store. Proven on the **real** `ExecuteQuery` effect contract. **Contract body does no IO** (dispatch has no executor registry by construction — call-count 0 after dispatch, 1 after host entrypoint). Not an MCP path. (LAB-MACHINE-CAPABILITY-IO-P2) |
| **real substrate executor** | ✅ (first real, read-only) | `executors::TBackendReadExecutor` — read-only `CapabilityExecutor` over a real `Arc<dyn TBackend>` (RocksDB on disk / remote-TCP). `run_service` + receipts UNCHANGED; only the executor is real. Outcome mapping: found→Succeeded, none→PermanentFailure, backend Err→UnknownExternalState (unavailable=epistemic). Proven on real RocksDB read + real RemoteTcp dead-port unavailability. Read-only — no writes/HTTP/scheduler. (LAB-MACHINE-CAPABILITY-IO-P3) |
| **host clock capability** | ✅ | `clock::{ClockProvider, FixedClock, SystemClock}` — receipt `transaction_time` from an injected provider, read ONLY at the ServiceLoop boundary (`run_effect_with_clock` / `run_service_with_clock`; `run_effect`/`run_service` default to `SystemClock`). No `now()` in the language; `dispatch` has no clock (contract can't read time). Replay writes no receipt → never rewrites a timestamp. (LAB-MACHINE-CAPABILITY-IO-CLOCK-P4) |
| **typed capability authority** | ✅ | `capability::{CapabilityPassport, verify_passport, AuthRefusal, run_effect_with_passport}` + `service_loop::run_service_with_passport` — verifiable passport (subject/capability/scopes/expiry/revoked/evidence) checked at the host boundary before the executor; expiry uses the injected clock; refusals (wrong-cap/missing-scope/revoked/expired) write NO receipt; executor denial stays denial-as-data; receipt records `authority_digest`; replay requires the same digest. Shared `run_effect_core` (zero churn to P1–P4). No OAuth/JWT/roles. (LAB-MACHINE-CAPABILITY-IO-AUTHORITY-P5) |
| **receipt-gated write** | ✅ (lifecycle + real local write) | `write::{run_write_effect, WriteState, WriteRequest, WriteResult, FactWrite, payload_digest, FakeWriteExecutor}` + `executors::TBackendWriteExecutor` — two-phase receipt: `prepared` (gate, before executor) → `committed`/`denied`/`unknown_external_state` (`aborted` reserved). Idempotency binds capability+operation+authority+`payload_digest` (payload_digest FORCED to include store+key+value+valid_time): same payload→replay, different payload→refuse-no-write; timeout/failure→unknown with NO blind retry; prepare-receipt failure → executor not called. **P6b: real `TBackendWriteExecutor` over on-disk RocksDB** behind the same protocol (write→committed+read-back; failure→unknown). Reuses P4 clock + P5 passport. (LAB-MACHINE-CAPABILITY-IO-WRITE-P6 a+b) |
| **unknown-write reconciliation** | ✅ | `reconcile::{reconcile_unknown_write, ReconcileResult}` — resolves an `unknown_external_state` write receipt by READING the target back (`facts_for` history scan; never re-writes/retries): our value present→`committed`, absent→`permanent_failure` (new `WriteState`), substrate error→still-unknown. Receipt records `target_store`/`target_key`/`value_digest` for read-back; reconciled receipt upgrades the unknown one; idempotent on terminals. Prerequisite for a retry scheduler. (LAB-MACHINE-CAPABILITY-IO-RECONCILIATION-P7) |
| **bounded reconcile-gated retry** | ✅ | `retry::{run_write_with_retry, RetryPolicy, RetryOutcome}` — retries a write safely: fresh idempotency key per attempt (`base:a{n}`); transient/permanent split via `WriteState::Retryable` + `EffectOutcome::retryable` (executor asserts no-mutation); on `unknown` it RECONCILES (P7) and continues only on a proven not-landed; bails `Unresolved` on still-unknown (no double-write); denial/hard-permanent not retried; bounded by attempt count. In-call only. (LAB-MACHINE-CAPABILITY-IO-RETRY-P8) |
| **durable retry queue** | ✅ | `retry_queue::{RetryIntent, IntentState, enqueue_retry, drain_due_retries, backoff_due}` — retry over TIME: intents are facts in `__retry_queue__` (key=base idempotency key, latest fact=live state) with `due_at = now + base_delay*2^attempt`. Explicit `drain_due_retries(clock, passport)` runs DUE pending intents (authority-digest-gated) via `run_write_effect`, same reconcile-gating as P8; transitions pending→done/exhausted/abandoned/blocked, all auditable facts. NO background worker / wall-clock timer (host calls drain). (LAB-MACHINE-CAPABILITY-IO-RETRY-QUEUE-P9) |
| **HTTP executor** | ✅ (policy P10 + real loopback P11) | `http::{HttpCapabilityExecutor, HttpTransport, SecretProvider, LoopbackHttpTransport, http_request_digest, HttpMethod, HttpTransportError, url_host}` + fakes. Maps HTTP→`EffectOutcome`: 2xx→Succeeded, 4xx→Permanent, 429→Retryable(+retry_after), 5xx idempotent→Retryable/POST→Unknown, timeout idempotent→Retryable/POST→Unknown, connect/DNS/TLS→Retryable. Non-idempotent requires key; forced request-identity digest; secret headers redacted; injected `SecretProvider` (`{{secret:NAME}}`, missing→refuse before send); body cap; replay never re-sends; **`correlation_id` first-class receipt field**. **P11: real `LoopbackHttpTransport`** (HTTP/1.1 over tokio TCP) proven against a `127.0.0.1` test server; `loopback_only()`/`with_allowed_hosts` allowlist (non-loopback refused before send). No external internet / TLS / SparkCRM (P12+). (LAB-MACHINE-CAPABILITY-HTTP-P10/P11) |

## Surfaces

| Surface | Status |
|---|---|
| Rust lib | ✅ kernel API above |
| Ruby FFI (magnus, `Igniter::Machine`) | ✅ new/resume/load_contract/dispatch/checkpoint/write_fact/read_fact (`ffi` feature) |
| REPL `igniter-repl` | present (`repl` feature) — not yet verified live here |
| MCP server `igniter-mcp` | ✅ **verified live** — JSON-RPC 2.0 over stdio (`initialize`/`tools/list`/`tools/call`); 11 tools. Drove a full agent session: load `Add` → dispatch →`42`, write_fact, status, time_travel. `igniter_time_travel` now takes optional `valid_at` → routes to `read_bitemporal` (both bitemporal axes agent-drivable). |
| backends | ✅ in-memory, RocksDB (persistent), remote-TCP |

## Proven by tests (`tests/machine_tests.rs`)

- `test_machine_in_memory_lifecycle` — load + dispatch (`Add` → 42).
- `test_machine_persistent_rocksdb_lifecycle` — facts through RocksDB.
- `test_machine_checkpoint_and_resume` — checkpoint → resume → dispatch (30) + facts.
- `test_machine_runs_wave_hof_closures` — **VM wave through the machine** (map/filter +
  closure capturing an enclosing compute) → 3.
- `test_machine_cross_contract_dispatch` — **orchestrator → `call_contract("Helper")`**
  resolves and runs → 10.
- `test_machine_loads_multifile_app` — **real fleet app `web_router` (3 files,
  modules+imports)** via `load_program` → dispatch `RunArticle` → `{body, status:200}`
  (identical to the CLI).
- `test_machine_fleet_sweep` — **13 fleet apps** (advanced_logistics, air_combat,
  audit_ledger, batch_importer, call_router, erp_logistics, igniter_parser, job_runner,
  lead_router, query_engine, reconciler, vector_editor, web_router) loaded + dispatched
  through the machine → **13/13 ok = full machine↔CLI parity**, no divergence.
- `tests/capability_io_tests.rs` (13) — **production capability IO boundary**: receipt-as-fact,
  idempotency prevents the 2nd executor call, replay bypasses the executor, `unknown_external_state`
  stays epistemic (distinct from `permanent_failure`), preflight refusal vs executor denial-as-data,
  receipts live in the same TBackend store. Fake executors only.
- `tests/capability_io_host_tests.rs` (9) — **declared-effect host entrypoint**: discovers the
  effect surface of the real `ExecuteQuery` effect contract from its IR; host performs the effect
  while the contract body does none (executor untouched by `dispatch`); idempotency + replay
  through `run_service`; preflight refuses pure/undeclared-effect/unregistered-capability/missing-
  authority with no receipt; in-process data-plane (no MCP). Fake executors only.
- `tests/capability_io_real_tests.rs` (5) — **first real substrate**: `TBackendReadExecutor` over
  a real on-disk `RocksDBBackend` (read succeeds + receipt; idempotency replays without re-reading;
  missing record → permanent_failure, no panic) and a real `RemoteTcpBackend` → dead port
  (unavailable → unknown_external_state). Contract body still does no IO. Read-only.
- `tests/capability_io_clock_tests.rs` (5) — **host clock capability**: receipt tt from the injected
  clock; replay/later-same-key never rewrite tt; distinct effects carry their own stamps; SystemClock
  returns a real epoch; `CountingClock` proves 0 reads from `dispatch` and 1 read at the host boundary.
- `tests/capability_io_authority_tests.rs` (9) — **typed capability passport**: valid passport
  authorizes + records digest; wrong-cap/missing-scope/revoked/expired refused with no receipt;
  expiry uses injected clock; replay requires same authority digest; executor denial stays
  denial-as-data; authority is host-side (`dispatch` gets no passport). Real `ExecuteQuery`.
- `tests/capability_io_write_tests.rs` (9) — **receipt-gated write lifecycle** (fake executor):
  two-phase prepared→committed; duplicate same-payload replays (mutation once); different-payload
  refused pre-executor; denial→denied state; timeout→unknown + no blind retry; prepare-failure
  blocks executor; authority refusal writes no receipt; replay-different-authority refused.
- `tests/capability_io_write_real_tests.rs` (8) — **real local write** (`TBackendWriteExecutor`
  over on-disk RocksDB): success→committed + read-back; duplicate same-payload → one backend write;
  different-payload refused; missing-authority no-write; injected failure → unknown + no blind
  retry; replay no-write; contract body cannot write; payload digest includes target identity.
- `tests/capability_io_reconcile_tests.rs` (6) — **unknown-write reconciliation**: read-back
  resolves unknown→committed (value landed) / →permanent_failure (absent) / →still-unknown
  (substrate unavailable); no substrate write (no blind retry); idempotent on terminals;
  reconciled-committed then replays without re-exec.
- `tests/capability_io_retry_tests.rs` (7) — **bounded reconcile-gated retry**: transient retries
  then commits; persistent transient exhausts; unknown→reconcile-not-landed→retry→commit (one
  version); unknown-but-landed→reconcile committed (no retry, one version); unknown+unreconcilable
  →bail Unresolved; denial + hard-permanent not retried. Scripted outcome-sequence executor.
- `tests/capability_io_retry_queue_tests.rs` (8) — **durable retry queue**: enqueue→intent fact
  with due_at; drain before due no-op; drain at due runs+commits; unknown reconciled before
  reschedule (and unreconcilable→blocked); committed terminal not re-drained; max attempts→
  exhausted; every transition is an auditable fact.
- `tests/capability_io_http_tests.rs` (12) — **HTTP executor policy** (fake transport): full
  status/timeout taxonomy; idempotency-key policy; secret resolution + redaction (secret never in
  result/receipt); forced request-identity digest; body-size cap; replay never re-sends.
- `tests/capability_io_http_loopback_tests.rs` (9) — **real loopback HTTP** (HTTP/1.1 over tokio
  TCP → 127.0.0.1 test server): GET 200+receipt; 404→permanent / 429→retryable; POST lost-response
  →unknown; missing-secret + keyless-POST + non-loopback-URL all refused before send; Authorization
  redacted from receipt; replay sends exactly once; correlation id sent + first-class receipt field.
- `test_machine_time_travel_out_of_order` — write fact versions OUT of transaction_time
  order (300, 100, 200) → read as-of boundaries (50→None, 150→tt100, 250→tt200,
  350→tt300) all correct. **(Fix: `igniter-tbackend/timeline.rs::latest_for` now scans
  for max transaction_time ≤ as_of instead of `partition_point` on a not-necessarily-
  sorted timeline — backfills/corrections no longer break as-of.)**

## Known gaps (pressure frontier)

- REPL `igniter-repl` not yet exercised live (MCP is — see Surfaces; both bitemporal axes
  via `igniter_time_travel`).
- Persistent-backend (RocksDB) fleet sweep + capsule store (current sweep/capsules are in-memory).
- MCP `igniter_load_contract` uses single-source `load_contract_source`, not `load_program`
  (multifile) — multifile apps not yet loadable via MCP.
- Interval valid_time (v0 = point); `valid_policy` fallback.

(`machine_tests.rs` 12 + `capability_io_tests.rs` 13 + `capability_io_host_tests.rs` 9 +
`capability_io_real_tests.rs` 5 + `capability_io_clock_tests.rs` 5 + `capability_io_authority_tests.rs` 9
+ `capability_io_write_tests.rs` 9 + `capability_io_write_real_tests.rs` 8 +
`capability_io_reconcile_tests.rs` 6 + `capability_io_retry_tests.rs` 7 +
`capability_io_retry_queue_tests.rs` 8 + `capability_io_http_tests.rs` 12 +
`capability_io_http_loopback_tests.rs` 9 = 112 pass — the header count is the historical baseline.)

## Boundary (per README)

Lab prototype — retains the right to breaking change pre-v1; not canon, no stable
`.igm` format authority. (Intended for production use as a SparkCRM companion kernel —
the "lab-only" wording is change-freedom + canon discipline, not a quality limit.)
