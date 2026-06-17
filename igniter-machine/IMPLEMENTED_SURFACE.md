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
>
> **IO wave digest (whole-wave front door):** for the full picture — capability-IO substrate,
> HTTP/TLS/SparkCRM executor, coordination/service runtime, bridge/wire contour, and hardening
> P18–P25, plus the explicit "what is NOT proven (live gate)" — read
> `../lab-docs/lang/lab-machine-io-wave-digest-p1-v0.md` (card `LAB-MACHINE-IO-WAVE-DIGEST-P1`).
> It routes to the per-phase cards; this file stays the live code-anchored index.
>
> **Readiness/design (post-P25, not implemented):** operator console over P20+P23 —
> `../lab-docs/lang/lab-machine-operator-console-p1-v0.md` (`LAB-MACHINE-OPERATOR-CONSOLE-P1`);
> SparkCRM webhook auction policy over P7 —
> `../lab-docs/lang/lab-sparkcrm-webhook-auction-policy-p1-v0.md` (`LAB-SPARKCRM-WEBHOOK-AUCTION-POLICY-P1`);
> Postgres connector + ORM boundary map —
> `../lab-docs/lang/lab-machine-postgres-capability-readiness-p1-v0.md` (`LAB-MACHINE-POSTGRES-CAPABILITY-READINESS-P1`):
> v0 = host `CapabilityExecutor` (SparkCRM pattern over SQL), NOT a `TBackend`, NOT an in-VM ORM.
> **The fake-adapter Postgres slices P2 (read) + P3 (write gate) + P4 (reconcile) are IMPLEMENTED**
> (fake adapter/resolver, no dep; see the "Postgres-shaped read executor" / "Postgres-shaped write
> gate" / "Postgres write reconcile" capability rows + docs
> `../lab-docs/lang/lab-machine-postgres-read-executor-p2-v0.md`,
> `…-postgres-write-gate-p3-v0.md`, `…-postgres-reconcile-p4-v0.md`). Real local Postgres behind an
> opt-in `postgres` feature stays a later human gate. The operator-console and webhook-auction
> designs above remain design/readiness only — no code yet.

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
| **correlation reconciliation** | ✅ | `correlation::{CorrelationResolver, CorrelationLookup, reconcile_unknown_by_correlation, CorrelationReconcileResult, MapCorrelationResolver}` — resolves an `unknown_external_state` write by its `correlation_id` (first-class P11) via a READ-ONLY resolver (Landed→committed / NotFound→permanent_failure / Unavailable→still-unknown). Precise per-request identity → closes P7's same-value caveat (same value + different correlation no longer false-matches); missing correlation → explicit `MissingCorrelation` (fall back to P7). Never re-sends (no executor param). `write_receipt` now pulls correlation from result OR payload/args. (LAB-MACHINE-CAPABILITY-IO-CORRELATION-RECONCILE-P13) |
| **external HTTP profile (P14, fake TLS)** | ✅ (policy proof, fake transport) | `http::HttpCapabilityExecutor::{external_profile, require_https, forbid_mutations}` + `HttpTransportError::CertInvalid` — first step past loopback: vetted host allowlist (refused before DNS/connect), https-only, read-only (no external POST). Cert-invalid→`permanent` (security failure) vs transient TLS/DNS/connect→`retryable`; redirects (3xx) NOT followed→permanent; secrets redacted; replay no re-send; correlation recorded; transport errors are auditable receipts. **Fake TLS-aware transport** for the policy proof. **P14-impl: real `TlsLoopbackHttpTransport`** (rustls 0.21 over tokio TCP, behind the opt-in `tls` feature) proven against a LOCAL self-signed CA-chain server — real handshake; `InvalidCertificate(_)`→`CertInvalid`(permanent) vs other handshake→`Tls`(retryable). No external internet/public-CA. (LAB-MACHINE-CAPABILITY-HTTP-EXTERNAL-P14 + -TLS-P14-IMPL) |
| **SparkCRM domain executor (P15)** | ✅ (capstone, local fake TLS upstream) | `sparkcrm::SparkCrmExecutor` — the first DOMAIN executor; ONE struct implements `CapabilityExecutor` (forward `POST /leads` → run_write_effect/receipt), `CorrelationResolver` (`GET /status` → reconcile P7/P13), and `CompensatableExecutor` (`POST /leads/{id}/cancel` → compensation P12), over the real TLS transport (P14-impl) with redaction + status taxonomy (P10/P14). Credentials = secret REFERENCE (never recorded). Ties the whole stack together with NO new primitives — proves the boundary composes. Proven vs a LOCAL fake SparkCRM HTTPS server (no prod/credentials/internet). (LAB-MACHINE-CAPABILITY-SPARKCRM-EXECUTOR-P15) |
| **effect compensation (`aborted`)** | ✅ (design + fake-executor proof) | `compensation::{CompensatableExecutor, run_compensation, CompensationResult, FakeCompensatableExecutor}` — REVERSE a committed effect (distinct from retry=re-attempt-failed / reconcile=read-back-unknown). `committed` → successful compensation → `aborted` (terminal update; the committed fact is preserved → auditable). Authority-continuity gated (compensator digest must match original); irreversible effects (`is_compensatable()==false`) refused, compensator never runs; compensation `unknown` does NOT abort (no blind reversal); replay = idempotent `AlreadyAborted`. Linked by `compensation_correlation_id`. NO external HTTP / SparkCRM / saga scheduler / auto-policy / contract-body. (LAB-MACHINE-CAPABILITY-IO-COMPENSATION-P12) |
| **agent coordination foundation** | ✅ (P2) | `coordination::{CoordinationHub, AgentIdentity/AgentKind/AgentStatus, CapsulePool/PoolVisibility, PoolRight, CapsuleRef, PoolGrant, PoolRefusal}` — coordination = **Capability IO applied to a new domain**: one `guard()` boundary = P5 `verify_passport` (WHO + op-class scope) → pool ACL (`owner ‖ developer ‖ explicit PoolGrant`, WHAT-on-WHICH) → `AuditEvent` fact (allowed AND denied) in `__coord_audit__`. Ops: register/create_pool/add_capsule/list_capsules/check_right/grant/transfer_ownership. **CapsuleRef content-addressed** (dedup by blake3 digest). Developer = local root-of-trust (privileged but audited). Schema keeps production-mode reachable (visibility `Production`, transferable ownership, `RuntimeActor`/`vendor:*` actor) but does NOT serve. VM untouched. (LAB-MACHINE-AGENT-POOLS-P2) |
| **agent messenger bus** | ✅ (P3) | `coordination::{Message, MessageKind, send_message, escalate, ack, list_inbox, read_thread, pending_requests}` — append-only messages as FACTS in `__messenger__` (NOT a mutable inbox; list=query, pending=requests-minus-acks via `in_reply_to`). Direct note / request+ack / developer escalation (reserved `"developer"` mailbox); participant-only thread/inbox visibility; carrying a `CapsuleRef` does NOT grant access (pool ACL still governs); revoked agent can't send/read; every op audited. Shared `authed()` (P5 verify_passport). No delivery worker / federation / voting. (LAB-MACHINE-AGENT-MESSENGER-P3) |
| **capsule transfer envelopes** | ✅ (P4) | `coordination::{TransferEnvelope, TransferState, propose_transfer, accept_transfer, reject_transfer, revoke_transfer}` — audited TWO-PHASE handoff (`proposed→accepted/rejected/revoked`, `expired` reserved) as facts in `__transfers__` (state-in-id, latest tx wins). PATTERN reuse of P6 write lifecycle (proposed≈prepared, accepted≈committed), not the write module. Propose=`ExportCapsule` on source (capsule must be in pool); accept=`ImportCapsule` on target → imports a **content-addressed ref** (no byte copy, source immutable) + grants ONLY `rights_granted`; idempotent accept; reject/revoke terminal; developer override; `recipe_digest` carried-but-inert (future handoff). Every transition audited. ACL via shared `pool_authorized`. (LAB-MACHINE-AGENT-TRANSFER-P4) |
| **service recipe + agentless serving** | ✅ (P5) | `coordination::{ServiceRecipe, accept_recipe, invoke, read_recipe}` — the dev→prod BRIDGE: developer (root-of-trust) signs a `ServiceRecipe` (capsule_digest+entry_contract+required_scopes+pool_sizing…) → pool → `Production`, dev-owned (recipe fact in `__recipes__`). `invoke(vendor passport, pool, inputs)` = REAL capsule activation (`IgniterMachine::resume_bytes` + `dispatch(entry_contract)`), NOT messenger; gated by accepted-recipe + production + required_scopes + `ActivateCapsule` grant + capsule-digest match; audited. Homogeneous = content-addressed replicas (one stored image). Proven end-to-end on a real `Add` capsule → 5/42. In-process; no HTTP ingress / messenger hot path / MCP / federation. (LAB-MACHINE-SERVICE-RECIPE-P5) |
| **HTTP ingress front door** | ✅ (P6, loopback) | `ingress::{IngressRouter, IngressRequest, IngressResponse, map_refusal, serve_once}` + `coordination::audit_ingress` — the INBOUND edge (not the P10/P11 outbound executor): vendor webhook → validate passport (before activation) → `route(path→pool)` → `hub.invoke` (real capsule activation) → HTTP status/body → audit (correlation id + idempotency). `map_refusal` PoolRefusal→401/403/404/409. `serve_once` = real loopback HTTP/1.1 (tokio TCP). Proven incl. a real `127.0.0.1` round-trip (`POST → 200 → 42`). Hot path holds only `&CoordinationHub` + calls only invoke/audit (no messenger). Loopback only; no public internet / SparkCRM creds / outbound effect / federation. (LAB-MACHINE-SERVICE-HTTP-INGRESS-P6) |
| **service↔effect bridge** | ✅ (joins the two lines) | `bridge_effect::{ServiceEffectBridge, BridgeOutcome}` — ties the coordination serving line to the capability-IO effect line: webhook → `hub.invoke` (capsule activation, PURE) → output = effect intent → `run_write_effect` (host performs effect, receipt) → outcome→HTTP (Committed→200 / Unknown→202 accepted-unknown / Denied→403 / Permanent→502 / Retryable→503). TWO authorities (vendor passport authorizes the pool; host effect_passport authorizes the downstream effect). Effect executor = ANY `CapabilityExecutor` (fake / TBackend write / P15 SparkCRM). Replay = effect runs ONCE despite re-activation (idempotency in the receipt, not the activation). NO new primitives. (LAB-MACHINE-SERVICE-EFFECT-BRIDGE-P16) |
| **atomic idempotency gate (P18)** | ✅ (concurrency) | `single_flight::{SingleFlight, run_write_effect_atomic}` — closes the exactly-one-effect gap UNDER CONCURRENCY (the receipt protocol was sequential-only: two parallel same-key requests could both read no-receipt→both prepare→both execute→double effect). Per-key async lock keyed by `capability:idempotency_key`, held across the whole `run_write_effect`: same-key serializes (effect once, the rest replay), different keys run parallel. Bridge uses it (`ServiceEffectBridge.single_flight`). Production-hardening blocker #1 (meta `…-PRODUCTION-HARDENING-P17`). In-process only (multi-process = distributed lock/backend-CAS later; lock map unbounded). (LAB-MACHINE-CAPABILITY-IO-ATOMIC-GATE-P18) |
| **durable recovery (P19)** | ✅ (crash recovery) | `recovery::{recover_dangling_writes, recover_dangling_by_correlation, RecoveryReport}` — after restart, a `prepared` receipt is DANGLING (crash between prepare and terminal receipt); the sweep RECONCILES each (P7 value read-back / P13 correlation), NEVER re-executes (no executor param). Closes the **write-succeeded-but-receipt-failed** window: effect landed but receipt stuck at prepared → read-back → committed; not landed → permanent_failure. Receipts/queue/dedup durable on RocksDB (survive restart). `reconcile_*` guards widened to accept dangling `prepared`. Blocker #2 (meta `…-P17`). RocksDB/tempdir, no live network. (LAB-MACHINE-CAPABILITY-IO-DURABLE-RECOVERY-P19) |
| **effect orchestrator (P20)** | ✅ (host-driven loop) | `orchestrator::{EffectOrchestrator, OrchestratorStatus}` — explicit host-called control loop (NO daemon, NO infinite loop): `boot()`=P19 recovery sweep + dead-letter unresolved; `tick()`=drain DUE retry intents (P9) + dead-letter exhausted/blocked; `report()`=status snapshot. Every boot/tick writes an audit fact (`__orchestrator_audit__`); stuck items → dead-letter fact (`__dead_letter__`) — no silent skip. Compensation (P12) NOT auto-driven (explicit only); enqueue stays upstream. Composes existing primitives, no new effect logic. Blocker #3 (meta `…-P17`). (LAB-MACHINE-CAPABILITY-IO-ORCHESTRATOR-P20) |
| **signed passport (P21)** | ✅ (security) | `capability::{sign_passport, PassportVerifier, verify_passport_signed, run_effect_with_verified_passport}` + `AuthRefusal::Untrusted` — makes passport authority VERIFIABLE: `evidence_digest` = blake3 keyed-hash MAC over `subject\|capability\|sorted-scopes\|issued_at\|expires_at` (binds identity+validity; scope can't be widened post-sign). `PassportVerifier` holds trusted issuer keys; verified path authenticates BEFORE the executor (Untrusted→refuse no receipt), then P5 checks (expiry/revoked/scope) remain. `authority_digest` now includes the signature → replay requires same signed passport. Opt-in (presence-only path untouched). Local MAC only — no asymmetric PKI/OAuth/JWT. Blocker #4a (meta `…-P17`). (LAB-MACHINE-CAPABILITY-IO-SIGNED-PASSPORT-P21) |
| **secret providers (P22)** | ✅ (security; closes blocker #4) | `secrets::{EnvSecretProvider, FileSecretProvider, LayeredSecretProvider}` (impl `http::SecretProvider`) — hardens the secret SOURCE: env (allowlist-only, non-allowlisted→None), file (`root/<name>`, traversal-safe `[A-Za-z0-9_-]`), layered (first hit wins, override). Secret value never enters receipt/audit/result; inputs carry only `{{secret:name}}` reference; missing→refuse-before-send; redaction preserved — all proven with the REAL providers through `run_write_effect`. `SecretProvider` = adapter point for a future external vault (NOT faked — no external service). Blocker #4b → **security blocker #4 CLOSED**. (LAB-MACHINE-CAPABILITY-IO-SECRET-PROVIDER-P22) |
| **observability (P23)** | ✅ (operator visibility) | `observability::{observe, ObservabilitySnapshot, EffectMetrics, DeadLetterInbox, DeadLetter}` — metrics + dead-letter inbox aggregated FROM facts (receipts/retry-queue/dead-letters) as a pure read-only projection (NO side-log, NO daemon, NO Prometheus). Counters: effects by latest receipt state, compensation(=aborted), retry intents by state, dead_letters, secret_missing/auth_refusals (derived from receipt details — executor-reached only). `DeadLetterInbox` grouped by reason, correlation joined from the receipt. `to_json()` export for an operator UI. Facts remain source of truth (`observe` writes nothing). Blocker #5 (meta `…-P17`). (LAB-MACHINE-CAPABILITY-IO-OBSERVABILITY-P23) |
| **load/correctness evidence (P24)** | ✅ (evidence-only) | `tests/capability_io_load_tests.rs` — multi-thread (real OS-parallel) load proof: same-key storm (2000 concurrent) → effect EXACTLY ONCE; distinct keys (3000) → all committed, no duplicates (P23 snapshot=3000); all-timeout (800) → 0 committed. Throughput ~40–50k effects/s (≫ 2–5k rpm target); distinct p50≈54µs; same-key serialized (the correct cost of exactly-one falls only on same-key contention). NO code tuning (no correctness bug). **ALL in-lab hardening #1–#6 CLOSED; only #7 human-gated live remains.** Blocker #6 (meta `…-P17`). (LAB-MACHINE-CAPABILITY-IO-LOAD-P24) |
| **ingress duplicate policy** | ✅ (P6, business) | `coordination::{DuplicatePolicy (on ServiceRecipe), record_ingress_dedup, ingress_dedup_history}` + `ingress::{DuplicateDecision, decide_duplicate, apply_duplicate}` — **configurable business** duplicate strategy (NOT canon): `idempotency=safety envelope` (same key + different payload → 409) is always on; the policy decides repeats: `dedup_strict` (replay, no re-activation) / `treat_as_fresh` (re-activate, distinct `attempt_index` per repeat → auction case: same input, distinct generated code) / `bounded_fresh(n)`+`after_limit` (dedup_last\|deny) / off. attempt_index injected into the recipe's `seed_field`; dedup facts in `__ingress_dedup__` record key/attempt/decision; policy lives on the recipe (round-trips), not the VM. (LAB-MACHINE-SERVICE-INGRESS-DUPLICATE-POLICY-P7) |
| **homogeneous pool fanout** | ✅ (P8) | `coordination::{select_replica, replica_count, invoke_replica, invoke_fanout}` — proves "production pool = homogeneous stateless replica set over an immutable content-addressed image". N refs sharing one digest = N replicas (ONE stored byte image, no copy); a non-matching digest is EXCLUDED. `select_replica` deterministic (round-robin \| hash-by-key, no random); `invoke_replica` serves one (output-invariant across replicas; audit `replica:i/N`); `invoke_fanout` activates all → identical output with per-replica failure isolation (`"disabled"` label/failing replica reported, not fatal; audit `fanout:N`). Non-production pool can't fanout. Shared `authorize_invoke`/`activate_digest`. (LAB-MACHINE-SERVICE-POOL-FANOUT-P8) |
| **replica selection in ingress** | ✅ (P9) | `ingress::IngressRouter` `route_with_strategy` + `serve_one` → `invoke_replica` (P8) in the hot path: webhook → passport → duplicate policy (P7, attempt/key) → ONE replica selected (`select_replica`: hash_key stable / hash_key_attempt / round_robin, NO random) → activation → response + `coordination::audit_serve` (replica_index/replica_count/strategy/seed_digest). **Single replica, NEVER fanout** (scaling compute must not multiply downstream effects; `invoke_fanout` stays diagnostic). Output-invariant. Duplicate policy decided before selection. (LAB-MACHINE-SERVICE-INGRESS-REPLICA-P9) |
| **service→effect bridge (replica)** | ✅ (P10, glass box) | `ingress::{EffectBridgeConfig, IngressRouter::handle_effect}` + `coordination::audit_bridge` — combines P7 dup-policy + P9 single-replica + the capability-IO effect: webhook → dup policy → ONE replica → capsule INTENT → `run_write_effect` (host effect passport, distinct from vendor) = ONE effect → receipt → HTTP. **Effect idem key = `duplicate_key:attempt_index`** so dup policy controls effect count: `dedup_strict`→one effect ever (repeat replays, no 2nd effect); `bounded_fresh(n)`→up to n distinct-keyed effects (auction leads). Single replica → ≤1 effect; fanout never effects. Unknown→202+correlation. audit links correlation/attempt/replica/effect_receipt_id. Fake executor only. (LAB-MACHINE-SERVICE-BRIDGE-REPLICA-P10) |
| **wire-to-effect contour** | ✅ (P11 MILESTONE, real socket) | `ingress::serve_once_effect` (+ shared `read_one_request`/`write_one_response`) — a real `127.0.0.1` HTTP/1.1 POST drives the FULL contour: parser → passport → duplicate policy → ONE replica → capsule intent → ONE effect → receipt → real HTTP response. All P10 invariants hold over real transport (one-replica-one-effect, dedup_strict replay no 2nd effect, bounded_fresh attempts 0..n, unknown→202, denied→403, audit links). **"wire-to-effect production contour proven in lab"** — front door `LAB-MACHINE-SERVICE-WIRE-EFFECT-MILESTONE`. Fake executor; no live SparkCRM (human-gated staging). (LAB-MACHINE-SERVICE-WIRE-EFFECT-P11) |
| **host serving loop** | ✅ (P12, host-owned) | `serving_loop::{ServingLoop, ServingPolicy, ServingReport}` — the in-lab **host shell** that shows the machine living as a process without a daemon: `boot()` recovery ONCE → accept/process `max_requests` connections via repeated `ingress::serve_once_effect` (P11) → optional host-owned tick cadence (`tick_every`/`tick_on_stop`) draining due retries via `EffectOrchestrator::tick` (P20) → `report/observe` stay queryable. **Host owns the loop and cadence; the machine exposes only functions** — no `tokio::spawn`, no background worker, no hidden scheduler (when `run` returns nothing of the loop remains). Sequential processing → introduces no concurrency → cannot weaken the P18 atomic gate: duplicate same-key requests still perform exactly one effect. Bounded, deterministic stop (`max_requests`, never unbounded). Loopback only (caller passes a `127.0.0.1` listener; the helper opens no address). NOT deployment topology (no daemon/supervisor/systemd/Dockerfile, no live vendor). `ServingReport` is a derived counter, NOT a side-log — facts remain the truth. (LAB-MACHINE-SERVING-LOOP-P12) |
| **bounded concurrent serving** | ✅ (P13, structured concurrency) | `serving_loop::{ConcurrentServingPolicy, ConcurrentServingReport}` + `ServingLoop::run_concurrent` — additive over P12 (sequential `run` untouched): boot once → drive a `FuturesUnordered` of `serve_once_effect` calls topped up to `max_in_flight` → bounded stop at `max_requests` → optional host-owned `tick_on_stop`. **Structured, NOT spawned** — in-flight calls are polled by the same task, no `tokio::spawn`/detached task, so nothing can outlive `run_concurrent` (stronger than join-on-shutdown: no worker to leak). `max_in_flight_observed` = peak in-flight reached. Invariant held: distinct keys served concurrently (proven observed-concurrency > 1, one effect each), same-key concurrent → **exactly one effect + one committed receipt**. NOTE: same-key collapse on this wire path is the `run_write_effect` receipt-replay gate over the **non-yielding in-memory** receipt store (NOT the P18 SingleFlight lock, which `serve_once_effect` does not use); a *yielding* receipt backend would need `run_write_effect_atomic` threaded into `handle_effect` (named follow-on). Cooperative concurrency (one polling task), not OS-parallel. Loopback only; no daemon/public ingress/live vendor. (LAB-MACHINE-SERVING-LOOP-CONCURRENCY-P13) |
| **frame projection (substrate only)** | ✅ (FP-P1 proven, EXTRACTED to `igniter-frame` P2) | The machine is the state-kernel SUBSTRATE: `TBackend` facts (e.g. a `__world__` store) project deterministically to frames. The projection runtime — `Frame`/`Camera`/`RenderHost`/world projection/frame receipts — was **extracted OUT of the machine** into the sibling `igniter-frame` crate (the kernel owns no frame/camera/render code; `src/frame.rs` deleted). `igniter-frame` core builds machine-free; its `machine` feature adapts the `FrameSource`/`FrameSink`/`RenderHost` ports to `TBackend` (`__world__`/`__frames__`). Machine = boring kernel; projection = a consumer (`fact-to-frame`, inverse of wire-to-effect). (LAB-MACHINE-FRAME-PROJECTION-P1 → LAB-FRAME-PROJECTION-EXTRACT-P2) |
| **Postgres-shaped read executor** | ✅ (fake-adapter proof) | `postgres_read::{PostgresReadExecutor<A>, PostgresReadAdapter, PostgresReadResult, PostgresReadPolicy, QueryPlan, QueryFilter, FakePostgresAdapter}` — first Postgres-shaped read capability, the `SparkCrmExecutor` pattern applied to SQL. A contract emits a **typed `QueryPlan`** (NO SQL string, NO DB handle); the executor (a `CapabilityExecutor`, so receipts/idempotency/replay come free from `run_effect`) runs gates **before** the single adapter call: raw-SQL refusal · source allowlist · read-only(mutation refusal) · op allowlist · field allowlist · row-limit **clamp**(≠denial). Outcome: rows/empty→Succeeded, unavailable→UnknownExternalState, transient→Retryable, query-error→PermanentFailure. **Fake in-memory adapter only — no `tokio-postgres`/`sqlx`/`diesel`, no SQL, no network, no new dependency.** Schema authority = host-side `PostgresReadPolicy` (not contract input, not introspection); filter-predicate evaluation deferred (`LAB-FILTER-EVAL-P1`); Postgres-as-`TBackend` is a separate deferred track. (LAB-MACHINE-POSTGRES-READ-EXECUTOR-P2) |
| **Postgres-shaped write gate** | ✅ (fake-adapter proof) | `postgres_write::{PostgresWriteExecutor<A>, PostgresWriteAdapter, PostgresWriteResult, PostgresWriteIntent, PostgresWritePolicy, FakePostgresWriteAdapter, FakeWriteBehavior}` — Postgres-shaped WRITE, driven by the EXISTING `write::run_write_effect` two-phase receipt (NO new write machinery; the `TBackendWriteExecutor` pattern). Contract emits a typed `PostgresWriteIntent` (NO SQL, NO handle); gates before the adapter: raw-SQL refusal · target allowlist · op allowlist. **TWO idempotency layers**: machine `__receipts__` (replay / different-payload refusal / no-blind-retry) + a fake PG-side `effect_receipts(idempotency_key)` upsert in ONE modelled txn (blocks a 2nd business mutation even if the machine receipt is LOST). Taxonomy: commit/duplicate→Committed, denied→Denied, constraint→PermanentFailure, serialization-rollback→Retryable, lost-after-send→UnknownExternalState (no blind retry; reconcile=P4). Receipt records correlation+idempotency key, not raw SQL/values. **Fake adapter only — no `tokio-postgres`/`sqlx`/`diesel`, no SQL, no network, no new dependency.** (LAB-MACHINE-POSTGRES-WRITE-GATE-P3) |
| **Postgres write reconcile** | ✅ (fake-resolver proof) | `postgres_write::{reconcile_postgres_unknown_write, PostgresWriteReceiptResolver, PostgresReceiptLookup, PostgresReconcileResult}` — closes the P3 `unknown` hole: resolves an `unknown_external_state` (or dangling `prepared`, P19) write receipt by an EXACT, READ-ONLY lookup of the PG-side `effect_receipts(idempotency_key)` table — found→committed / not-found→permanent_failure / unavailable→still-unknown. **Never re-runs the executor** (`transact`) — the resolver trait has no mutating method (structural). Keyed by idempotency identity (NOT values) → P7 same-value false positive impossible (the SQL form of P13 correlation reconcile). Reuses the P13 `write_resolved` upgrade (preserves authority+payload digests) → a reconciled-committed receipt REPLAYS through `run_write_effect` with no re-execution; looked-up correlation/target/key kept as evidence. Fake resolver only; `run_write_effect`/retry/orchestrator unchanged. (LAB-MACHINE-POSTGRES-RECONCILE-P4) |

## Surfaces

| Surface | Status |
|---|---|
| Rust lib | ✅ kernel API above |
| Ruby FFI (magnus, `Igniter::Machine`) | ✅ new/resume/load_contract/dispatch/checkpoint/write_fact/read_fact (`ffi` feature) |
| REPL `igniter-repl` | present (`repl` feature) — not yet verified live here |
| MCP server `igniter-mcp` | ✅ **verified live** — JSON-RPC 2.0 over stdio (`initialize`/`tools/list`/`tools/call`); 11 tools. Drove a full agent session: load `Add` → dispatch →`42`, write_fact, status, time_travel. `igniter_time_travel` now takes optional `valid_at` → routes to `read_bitemporal` (both bitemporal axes agent-drivable). |
| backends | ✅ in-memory, **`MpkFileBackend`** (persistent; `"rocksdb"` mode + back-compat alias `RocksDBBackend`), remote-TCP — **NB:** the persistent backend is a **pure-Rust `.mpk` file store**, NOT the real RocksDB crate. **Hardened in P3** (`LAB-MACHINE-FACTSTORE-DURABILITY-HARDENING-P3`, `../lab-docs/lang/lab-machine-factstore-durability-hardening-p3-v0.md`): **atomic** temp→fsync→rename writes, corruption is **observable+refused** (`corrupt_files()` / `EngineError::Corruption`, no more silent `unwrap_or_default` loss), receipt spine goes through this hardened path. Crash/torn-write atomic + fsync-to-OS; **full power-loss durability remains platform-gated** (macOS needs `F_FULLFSYNC`). P2 audit: `../lab-docs/lang/lab-machine-rocksdb-durability-p2-v0.md`. |

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
- `tests/capability_io_http_external_tests.rs` (10) — **external HTTP policy** (fake TLS transport):
  non-allowlisted host refused before send; allowlisted HTTPS GET succeeds+receipt+correlation;
  cert-invalid→permanent vs TLS/DNS/connect→retryable; timeout→retryable; redirect→permanent; secrets
  redacted; replay no re-send; transport error auditable; no external POST; plain-http refused.
- `tests/capability_io_http_tls_tests.rs` (7, feature `tls`) — **real TLS transport**
  (`TlsLoopbackHttpTransport`, rustls): real handshake vs a LOCAL self-signed CA-chain server →
  succeeds + correlation + receipt; untrusted cert→permanent; transient handshake→retryable;
  non-allowlisted/plain-http refused before connect; redirect→permanent; replay no 2nd TLS conn;
  secrets redacted. Deps opt-in (`tls` feature), offline-cached (precheck).
- `tests/capability_io_sparkcrm_tests.rs` (8, feature `tls`) — **SparkCRM domain executor** (capstone):
  forward create succeeds + receipt redacts auth + stores correlation; replay no re-send; lost
  response→unknown; **reconcile by correlation** (status 200→committed / 404→permanent_failure);
  compensation aborts committed (POST cancel); 429→retryable + P9 retry intent; 4xx→permanent /
  5xx-POST→unknown; non-allowlisted host refused. Real TLS vs a local fake SparkCRM upstream.
- `tests/capability_io_bridge_tests.rs` (6) — **service↔effect bridge**: webhook→capsule activation
  (Add 20+22=42)→effect (output+correlation reach payload+receipt); replay performs effect ONCE
  despite re-activation; missing idempotency key fails closed; unknown→202; serving refusal→403;
  **concurrent same-key webhooks → effect once (P18)**.
- `tests/capability_io_atomic_tests.rs` (4) — **atomic idempotency gate** (P18): concurrent same-key
  → effect ONCE (serialized, max-in-flight=1); different keys run parallel (max-in-flight=2); same
  key+different payload → one wins; dangling `prepared` (crash) stays recoverable (unknown, no re-exec).
- `tests/capability_io_recovery_tests.rs` (7) — **durable recovery** (P19, RocksDB): receipt survives
  restart; window #2 (effect landed, receipt stuck at prepared → committed); window #1 (not landed →
  permanent_failure); recovery never mutates substrate (no re-exec); recovery by correlation;
  recovered-committed then replays no re-exec; retry queue survives restart.
- `tests/capability_io_orchestrator_tests.rs` (6) — **host-driven orchestrator** (P20): boot recovers
  dangling + audited; boot idempotent; unresolvable→dead-letter; tick drains due retry intent (effect
  performed) + audited; exhausted→dead-letter; report reflects receipt states.
- `tests/capability_io_signed_passport_tests.rs` (5) — **signed passport** (P21): valid signed →
  authorizes+receipt; untrusted/bogus sig → refused (no executor/receipt); tampered scope → no
  escalation; signed-but-expired/revoked/wrong-scope still refused; refusal taxonomy unit.
- `tests/capability_io_secrets_tests.rs` (5) — **secret providers** (P22): env allowlist-only; file
  reads root + rejects traversal; layered override+fall-through; file-sourced secret never in receipt
  (resolved value reached transport, not the fact); missing secret → refuse before send.
- `tests/capability_io_observability_tests.rs` (6) — **observability** (P23): metrics aggregate
  receipt states (+ secret_missing); dead-letter inbox grouped by reason; dead-letter joins
  correlation; retry intent counts; JSON export; projection read-only + idempotent.
- `tests/capability_io_load_tests.rs` (3) — **load/correctness** (P24, multi-thread): same-key storm
  (2000) → effect once; distinct keys (3000) → all committed no duplicates; all-timeout (800) → 0
  committed. Throughput ~40–50k effects/s; exactly-one holds at 2000-way concurrency.
- `tests/capability_io_correlation_tests.rs` (8) — **reconcile by correlation id**: unknown→committed
  (landed) / →permanent_failure (not-found); **same value + different correlation → no false match**;
  missing correlation → MissingCorrelation (fall back to P7); unavailable → still-unknown; never
  re-sends; compensation references original correlation; committed→NotApplicable/absent→NoReceipt.
- `tests/capability_io_compensation_tests.rs` (7) — **effect compensation / `aborted`**: committed
  → compensation → aborted (committed fact preserved, auditable, correlation recorded); compensation
  unknown/denied keeps committed; irreversible refuses (compensator never runs); replay = AlreadyAborted
  (runs once); only committed is compensatable (else NotCommitted/NoReceipt); authority mismatch refused.
- `tests/coordination_pools_tests.rs` (9) — **agent/pool coordination foundation** (P2): owner
  creates pool + adds capsule (audited); other agent denied list/activate/fork without grant;
  explicit grant enables only the granted op; content-addressed dedup (identical bytes→one image);
  developer grants + takes ownership, audited, visibility→production; revoked agent denied;
  passport failure refused before ACL (no state change); every op (allowed+denied) audited as a
  fact; runtime/vendor actor (`vendor:acme`, `RuntimeActor`) schema supported.
- `tests/coordination_messenger_tests.rs` (9) — **messenger bus** (P3): send note; recipient
  lists/reads; third party denied thread/inbox; request pending until ack; ack linked to request +
  routed to requester; developer escalation → developer mailbox, audited; capsule ref in message
  does NOT grant pool access; revoked agent can't send/read; all message ops audited (allowed+denied).
- `tests/coordination_transfer_tests.rs` (9) — **transfer envelopes** (P4): propose→accept imports a
  content-addressed ref, source pool/ref immutable (no byte copy); recipient without import denied;
  rejected/revoked don't import (revoke prevents future accept); duplicate accept idempotent (one
  ref); grants only declared rights; developer override audited; all transitions audited; carries
  optional ServiceRecipe digest (not served).
- `tests/coordination_recipe_tests.rs` (7) — **service recipe + agentless serving** (P5): developer
  signs recipe → pool production+dev-owned; vendor passport invokes real `Add` capsule (resume+
  dispatch→5/42) audited; no-grant agent refused; homogeneous replicas share one digest/image;
  capsule-digest mismatch refused; invoke is activation not messenger (no IO receipts); full
  transfer→accept→sign→invoke bridge → 42.
- `tests/service_http_ingress_tests.rs` (9) — **HTTP ingress front door** (P6, loopback): webhook→200+
  result; invalid passport→401 before activation; unknown route→404; non-production pool→404; audit
  for accepted+denied; no messenger in hot path; digest-mismatch→409 mapping; correlation+idempotency
  recorded; **real 127.0.0.1 HTTP/1.1 round-trip → 200 OK + 42**.
- `tests/service_ingress_duplicate_policy_tests.rs` (8) — **configurable duplicate policy** (P7):
  dedup_strict replays no-activation; **treat_as_fresh → same input, distinct codes 1000/1001/1002**
  (auction case via injected attempt_index); bounded_fresh(3)→dedup_last + bounded_fresh(2)→deny(429);
  same-key/different-payload→409 conflict; variant_payload opt-in allows it; dedup facts record
  key/attempt/decision; policy round-trips on recipe + missing-key+require→400.
- `tests/service_pool_fanout_tests.rs` (8) — **homogeneous pool fanout** (P8): pool_sizing=N → N
  replicas / ONE stored image (no copy); different-digest ref excluded; deterministic selection
  (hash-by-key + round-robin wrap); invoke_replica output-invariant across replicas; fanout →
  identical output; audit records replica/fanout; non-production can't fanout; one disabled replica
  isolated+reported while others succeed.
- `tests/service_ingress_replica_tests.rs` (7) — **replica selection in ingress** (P9): hash-by-key
  same key→same replica; round-robin cycles 0/1/2; hash_key_attempt → attempt participates in seed;
  serve audit has replica_index/count/strategy/seed_digest; output unchanged; exactly ONE replica
  served (fanout never on hot path); non-production refused.
- `tests/service_bridge_replica_tests.rs` (6) — **service→effect bridge × replica** (P10, glass box):
  one request → one replica → one committed effect (200); dedup_strict repeat replays NO 2nd effect;
  bounded_fresh(6) → distinct-keyed effects (IO.SparkCRM:E1:0/1/2); audit links correlation/attempt/
  replica/effect_receipt_id; unknown effect → 202 + correlation; fanout never on bridge path.
- `tests/service_wire_effect_tests.rs` (5) — **wire-to-effect** (P11 MILESTONE, real 127.0.0.1):
  HTTP POST → handle_effect → committed 200; dedup_strict wire replay → no 2nd effect; bounded_fresh
  over repeated POSTs → 3 distinct effects; status mapping unknown→202 / denied→403; bridge audit
  links correlation/attempt/replica/effect_receipt_id over the wire.
- `tests/postgres_read_tests.rs` (9) — **Postgres-shaped read executor** (P2, fake adapter): impl
  `CapabilityExecutor`; allowlisted source → rows (projection-shaped) + receipt; empty→success/empty;
  raw-SQL input → permanent + adapter untouched; unknown-source / forbidden field (projection AND
  filter) / mutation op all refused BEFORE the adapter (call count 0); row-limit clamp reflected in
  result + persisted receipt; adapter unavailable→unknown, transient→retryable; replay same key →
  adapter call count stays 1. No DB / SQL / network / dependency.
- `tests/postgres_write_tests.rs` (10) — **Postgres-shaped write gate** (P3, fake adapter): through
  `run_write_effect` — commit lifecycle prepared→committed + business row + PG effect receipt;
  raw-SQL payload → permanent + adapter untouched; replay same key+payload bypasses adapter
  (machine receipt); same key + different payload refused before adapter; **PG-side dedup blocks a
  2nd mutation when the machine receipt is LOST** (attempts 2, business rows 1); serialization→
  retryable; lost→unknown + no blind retry; constraint→permanent; denial→denied; policy gates
  (target/op) refuse before the adapter. No DB / SQL / network / dependency.
- `tests/postgres_reconcile_tests.rs` (7) — **Postgres write reconcile** (P4, fake resolver):
  landed-but-unknown (`CommitButLost`) → found → committed (attempts/business rows unchanged,
  evidence preserved); unknown + no effect receipt → permanent_failure; resolver down → stays
  unknown; dangling `prepared` → committed (no transact); reconciled-committed receipt replays via
  `run_write_effect` with no re-execution; same values + different key → not-found → permanent (no
  false positive) while the landed key → committed; committed → NotApplicable / missing → NoReceipt.
- `tests/serving_loop_tests.rs` (4) — **host serving loop** (P12, real 127.0.0.1): one loop instance
  boots once + serves two requests (observe() projects 2 committed); duplicate same-key over the loop →
  exactly one effect; host-owned tick drains a due retry intent; deterministic bounded shutdown
  (re-entrant, no leaked acceptor, system stays queryable).
- `tests/serving_loop_concurrency_tests.rs` (5) — **bounded concurrent serving** (P13, multi-thread,
  real 127.0.0.1): distinct keys served concurrently (observed == max_in_flight > 1, all effects run);
  6 same-key concurrent → exactly one effect + one committed receipt; mixed batch → one effect per
  distinct key (duplicates serialized); deterministic bounded shutdown (re-entrant, no leaked task);
  host-owned tick drains a due retry. Stable over 10 consecutive runs.
- frame projection (6 checks) lives in the **`igniter-frame` crate** now, not here
  (`igniter-frame/tests/frame_projection_tests.rs`; `cargo test` there) — extracted per
  LAB-FRAME-PROJECTION-EXTRACT-P2. The machine only proves its facts are a projection substrate.
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
`capability_io_http_loopback_tests.rs` 9 + `capability_io_correlation_tests.rs` 8 +
`capability_io_compensation_tests.rs` 7 + `capability_io_http_external_tests.rs` 10 = 137
capability+machine; full `cargo test --no-default-features` = 164 incl. the parallel coordination
track. The header count is the historical baseline.)

## Boundary (per README)

Lab prototype — retains the right to breaking change pre-v1; not canon, no stable
`.igm` format authority. (Intended for production use as a SparkCRM companion kernel —
the "lab-only" wording is change-freedom + canon discipline, not a quality limit.)
