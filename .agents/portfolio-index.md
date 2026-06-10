# igniter-lab: Portfolio Index

**Maintained by:** Portfolio Architect Supervisor
**Last updated:** LAB-STORAGE-ADAPTER-P1 CLOSED (80/80 PASS - mocked Storage adapter boundary; Query v0 semantics reused; missing mock source => system_error; real DB/SQL/ORM HOLD) | LAB-IGV-TAILMIX-P3 CLOSED (70/70 PASS — Sidebar+FileTreeRow bundle dedup, slot values, nested compose, per-instance isolation)
**Scope:** Cross-repo state map for igniter-lab ↔ igniter-lang

---

## Canon Boundary Rules (igniter-lang)

| Rule | Statement | Adopted |
|------|-----------|---------|
| CR-001 | Canon type opacity: IO.* types are opaque identifiers; schema is lab-only | 2026-06-07 |
| CR-002 | Lab diagnostic boundary: E-NET-* codes are lab-local; OOF promotion requires PROP+grammar review | 2026-06-07 |
| CR-003 | Profile binding is intent record only — not validated authority until PROP-040 OOF-M7/M8 active | 2026-06-07 (closed by PROP-040) |

---

## Tracks and Status

### IO.NetworkCapability

| Artifact | Repo | Status | Checks |
|---|---|---|---|
| LAB-STDLIB-NET-P2 (schema, delegation algebra) | igniter-lab | ✅ DONE | 53/53 |
| LAB-STDLIB-NET-P3 (FFI surface, stub mode) | igniter-lab | ✅ DONE | 61/61 |
| LAB-STDLIB-NET-P4 (compiler escape classification, E-NET-* codes) | igniter-lab | ✅ DONE | 42/42 |
| LAB-STDLIB-NET-P5 (hardening: glob, chains, bind-address, wildcard) | igniter-lab | ✅ DONE | 44/44 |
| LAB-STDLIB-NET-P6 (dead grant, compose bind_address) | igniter-lab | ✅ DONE | ~36/36 |
| LAB-STDLIB-NET-P6/HTTP (HTTP-client boundary — typed HttpRequest/Response records, capability policy, mocked transport, telemetry redaction, error taxonomy; Category: lang, Track: lab-network-http-client-request-response-boundary-proof-v0) | igniter-lab | ✅ DONE | 48/48 |
| LAB-STDLIB-NET-P7 (HTTP boundary Map alignment — Map[String,String] headers; map_get/or_else/has_key type rules; OOF-MAP1/2/3; redaction preserves Map shape; policy unchanged; P6 regression green; Category: lang, Track: lab-network-http-boundary-record-map-alignment-v0) | igniter-lab | ✅ DONE | 55/55 |
| LAB-STDLIB-NET-P8 (HTTP error result + retry envelope — HttpResult ok/denied/error; RetryPolicy 5xx/4xx/denial; RetrySimulatorP8 BudgetedLocalLoop analog; capability denial as data; Map headers; E-HTTP-SERVER-ERROR/CLIENT-ERROR; Category: lang, Track: lab-network-http-error-result-and-retry-envelope-proof-v0) | igniter-lab | ✅ DONE | 50/50 |
| LAB-STDLIB-NET-P9 (HTTP upstream call contract composition — ContractResult typed domain envelope; ItemRequestBuilderP9→mocked boundary→HttpResult→DomainResponseMapperP9; Rack single-call + Sidekiq retry; capability denial as typed branch; upstream_unavailable on budget exhaustion; call_contract proof-local; Category: lang, Track: lab-network-http-upstream-call-contract-composition-proof-v0) | igniter-lab | ✅ DONE | 55/55 |
| PROP-035: capability/effect_binding grammar + OOF-M2/M4/M5 | igniter-lang | ✅ experiment-pass | 64/64 |
| `lab-docs/lang/lab-igniter-lang-io-capability-grammar-v0.md` | igniter-lab | ✅ bridge doc | — |

**Boundary:** Canon grammar names IO types as opaque identifiers (CR-001). Schema, delegation
algebra, FFI, E-NET-* codes remain lab-only. Runtime injection is Phase 2.
HTTP-client boundary (P6/HTTP): typed HttpRequest/Response records + capability policy + mocked transport
+ telemetry redaction proved (48/48). Real network I/O, DNS, TLS, and accept-loop startup remain closed.
Map alignment (P7): Map[String,String] headers proved for both record shapes; map_get/or_else typechain
clean; redaction preserves Map shape; policy is header-agnostic; 55/55 PASS.
PROP-043-P5 production Map with Record/Map bridge landed 2026-06-09 (55/55); P7 uses same proof-local architecture.
Error result + retry envelope (P8): HttpResult typed envelope (ok/denied/error discriminant); RetryPolicy
5xx→retry/4xx→no retry/denial→no retry; RetrySimulatorP8 BudgetedLocalLoop analog (no scheduler/clock);
capability denial as typed data through full envelope; 50/50 PASS.
Upstream call contract composition (P9): ContractResult typed domain envelope (found/created/not_found/
upstream_error/capability_denied/upstream_unavailable); Rack single-call + Sidekiq retry scenarios;
DomainResponseMapper shields domain code from transport internals; call_contract proof-local; 55/55 PASS.

### Profile System (PROP-033 / PROP-040)

| Artifact | Repo | Status | Checks |
|---|---|---|---|
| PROP-033: `via <profile>` binding on contract declarations | igniter-lang | ✅ experiment-pass | 52/52 |
| PROP-040: module-level `profile <name> { authority: <modifier> }` declarations | igniter-lang | ✅ experiment-pass | 63/63 |
| OOF-M7 (modifier below profile authority) / OOF-M8 (unknown profile) | igniter-lang | ✅ active in classifier | — |
| CR-003 closed by PROP-040 | igniter-lang | ✅ | — |

**Profile chain:** `profile_binding` (PROP-033) + `profile_authority` (PROP-040) propagate through
all four pipeline stages (parser → classifier → typechecker → SemanticIR). Via references
to undeclared profiles now trigger OOF-M8 at classify time.

### Contract Modifiers (PROP-031 / PROP-035)

| Artifact | Repo | Status |
|---|---|---|
| PROP-031: pure/observed/effect/privileged/irreversible | igniter-lang | ✅ experiment-pass |
| PROP-035: Effect Surface (capability/effect_binding, OOF-M2/M4/M5) | igniter-lang | ✅ experiment-pass |

### Assumptions Block (PROP-032)

| Artifact | Repo | Status |
|---|---|---|
| PROP-032: `assumptions {}` + `uses assumptions NAME` | igniter-lang | ✅ experiment-pass (bounded compiler surface) |

### Text / String Core (igniter-string-core-units-and-pure-stdlib-boundary-v0)

| Artifact | Repo | Status |
|---|---|---|
| Track doc | igniter-lang | ✅ experiment-pass — compiler surface 2026-06-08 |
| `Text` canonical type | igniter-lang | ✅ TypeChecker + ch3/ch2/ch8 reconciled |
| `stdlib.text.*` (14 ops) | igniter-lang | ✅ experiment-pass — 60/60 PASS |
| `source/string_extension.ig` | igniter-lang | ✅ superseded → `TextWorkflow`; old `StringWorkflow` legacy/held |
| Lab STR-CORE Rust symmetry | igniter-lab | ✅ closed 2026-06-08 — verify_str_core.rb 29/29 PASS (P2: concat disambiguated) |
| Lab STR-CORE-P3 value-semantics proof (bounds, UTF-8, UAX #29) | igniter-lab | ✅ closed 2026-06-08 — verify_str_value_semantics.rb 33/33 PASS (compile-time; runtime-gated gaps documented) |
| LAB-STR-UNICODE-P1 Unicode policy design | igniter-lab | ✅ design-locked 2026-06-08 — UTF-8 validity, UAX #29, no normalization, bounds clamp, grapheme receipt design |
| LAB-STR-UNICODE-P2 Unicode VM runtime ops | igniter-lab | ✅ closed 2026-06-08 — 8 functional ops (rune_length, grapheme_length, byte/rune/grapheme_slice, ends_with, replace, replace_all) + qualified aliases + split/replace empty-input guards; unicode-segmentation = "1.11" (lock: 1.13.3); verify_unicode_text_runtime.rb 43/43 PASS |
| LAB-STR-UNICODE-P3 handler hygiene + receipt | igniter-lab | ✅ closed 2026-06-08 — bare `split` guard aligned (P3 hygiene, no bypass via legacy name); unicode_runtime_receipt.json emitted (lab-only-evidence); 41/41 PASS |

**Formula:** `Text` is canonical contract type for text values. `String` literal compat via v0 rule only.
`stdlib.text.*` is experiment-pass compiler surface. Runtime Unicode/value semantics proven in lab VM.
Handler-policy consistency proven (bare and qualified split/replace both fail-closed on empty input).
Stable public API and runtime-execution gate remain closed.

**v0 surface (14 ops):** `concat`, `trim`, `contains`, `starts_with`, `ends_with`, `split`, `replace`, `replace_all`,
`byte_length`, `rune_length`, `grapheme_length`, `byte_slice`, `rune_slice`, `grapheme_slice`

**SemanticIR:** `kind: "call"`, `fn: "stdlib.text.*"`; no new IR kind needed (consistent with `stdlib.integer.*`)

**Closed:** runtime execution, bounds policy, locale case folding, regex, tokenizer,
TextEngine, streaming text, method syntax forms, stable public stdlib.text API.

**Track doc:** `igniter-lang/.agents/work/tracks/string-core-units-pure-stdlib-boundary-v0.md`

### Managed Recursion and Loop Classes (PROP-039)

| Artifact | Repo | Status |
|---|---|---|
| PROP-039: loop-class vocabulary + recursion design | igniter-lang | ✅ accepted; Gates 1+3+4+5+6+7+8 closed; Gate 5 recur() closed |
| FiniteLoop / BudgetedLocalLoop / StructuralRecursion / FuelBoundedRecursion | igniter-lang | ✅ experiment-pass compiler surface |
| OOF-L1/L5/L7/L8 / OOF-R1/R2/R4/R5/R6/R7 | igniter-lang | ✅ experiment-pass — active in TypeChecker/Classifier |
| OOF-L2/L3/L4 | igniter-lang | candidates only — not yet proven |
| OOF-R3 | igniter-lang | ✅ experiment-pass — OOF-R3 gate closed 2026-06-08; oof_r3_syntactic_variant_decrease_proof 33/33 |
| OOF-R3 Lab Rust symmetry | igniter-lab | ✅ closed 2026-06-08 — classifier.rs + typechecker.rs + emitter.rs; verify_oof_r3.rb 34/34 |
| OOF-R8 (missing size_relation) / OOF-R9 (call-site mismatch) | igniter-lang | ✅ experiment-pass — PROP-041-P3 proof-local gate 2026-06-08; prop041_structural_size_relation_proof 48/48 |
| PROP-041 T2 production (structural_size_v1 SemanticIR) | igniter-lang | ✅ PROP-041-P7 production — verify_prop041_t2_production.rb 48/48; verify_oof_r3.rb 33/33 |
| LAB-TERM-T2-P1 Rust symmetry | igniter-lab | ✅ closed 2026-06-08 — parser.rs + classifier.rs + typechecker.rs + emitter.rs; verify_t2_structural_size_relation.rb 52/52 PASS |
| LAB-TERM-T2-P2 OOF-R9 edge hardening | igniter-lab | ✅ closed 2026-06-08 — IfExpr fix; multi-recur/branch/nested-arith; verify_t2_oof_r9_edge_cases.rb 21/21 PASS |
| PROP-042-P1 T3 numeric measure proposal | igniter-lang | ✅ proposal authored 2026-06-09 — grammar + builtins + OOF-R10/R11 + SemanticIR + call-site obligation + P2 fixture matrix |
| PROP-042-P2 T3 proof-local experiment | igniter-lang | ✅ CLOSED 2026-06-09 — T3Pipeline + T3TypeChecker + T3Emitter; OOF-R10/R11 candidates proven; 36/36 PASS |
| PROP-042-P3 T3 acceptance decision | igniter-lang | ✅ CLOSED 2026-06-09 — P2 accepted; OOF-R10/R11 → experiment-pass; P4 production-edit planning authorized |
| PROP-042-P4 T3 production-edit planning | igniter-lang | ✅ CLOSED 2026-06-09 — exact +112-line plan; classifier no-change; OOF-R9 confirmed production-safe; P5 authorized |
| PROP-042-P5 T3 production implementation | igniter-lang | ✅ CLOSED 2026-06-09 — parser.rb + typechecker.rb + semanticir_emitter.rb; numeric_measure_v0 live; 45/45 PASS; T1/T2/R3 regressions clean; LAB-T3-P1 unblocked |
| LAB-T3-P1 Rust T3 numeric measure symmetry | igniter-lab | ✅ CLOSED 2026-06-09 — parser.rs + typechecker.rs + emitter.rs; OOF-P1 suppression via RefCell<T3Context>; verify_t3_numeric_measure.rb 45/45; T2/R9/R3/G5 regressions clean |
| ServiceLoop | → PROP-037 exclusive | excluded from PROP-039 |
| Parser / TypeChecker / SemanticIR | igniter-lang | ✅ experiment-pass compiler surface |
| Runtime / recursive execution / termination proof / VM stack / TCO | igniter-lang | **closed** — separate authorization required |

**Boundary:** Lab/Rust implementations are conformance consumers of canon proofs, not language authority.
Runtime execution, `igc run`, `.igbin`, RuntimeSmoke, and public/stable/production remain closed.

---

### External Progression / Service Liveness (PROP-037)

| Artifact | Repo | Status |
|---|---|---|
| PROP-037: Progression, ProgressionSource, ProgressionEvent | igniter-lang | accepted; proposal-only |
| clock.every, tick.time bindings | igniter-lang | PROP-037 scope |
| OOF-SL* codes | igniter-lang | PROP-037 companion territory |

### HTTP-Types / Rack (Lab only)

| Artifact | Repo | Status | Checks |
|---|---|---|---|
| LAB-LANG-HTTP-TYPES-P1 (ContractRef, middleware compose, IgniterFailure) | igniter-lab | ✅ DONE | ~41/41 |
| LAB-RACK-P2 (HttpRequest/Response Records, RackEnvAdapter, RackTupleAdapter, HandlerContract, static middleware pipeline, typed failures, closed-surface) | igniter-lab | ✅ DONE | 46/46 |
| LAB-RACK-P3 (ContractRef VM dispatch preflight — precise gap map at each compiler/VM layer) | igniter-lab | ✅ DONE | 25/25 |
| LAB-RACK-P4 (static route dispatch — 5-route data-plane table + :id param extraction; stdlib.text.* VM gap found) | igniter-lab | ✅ DONE | 27/27 |
| LAB-RACK-P5 (VM stdlib.text.* alignment — 3 OP_CALL cases added; 5-route dispatch + param extraction execute end-to-end on VM) | igniter-lab | ✅ DONE | 20/20 |
| LAB-RACK-P6 (TypeChecker == and < alignment — idiomatic equality in route dispatch; exact match via path=="/" + method=="GET") | igniter-lab | ✅ DONE | 32/32 |
| LAB-RACK-P7 (VM named entrypoint selector — `--entry <name>` CLI flag; default contracts[0] preserved; unknown entry fails closed) | igniter-lab | ✅ DONE | 28/28 |
| LAB-RACK-P8 (ContractRef dispatch boundary preflight — design locked: explicit `call_contract` stdlib op, dispatch table, depth ≤ 8, pure-callee-only in v0) | igniter-lab | ✅ DONE — design | — |
| LAB-RACK-P9 (explicit named user-contract dispatch via `call_contract` — DispatchEntry, cycle detection, MAX_CALL_DEPTH=8, pure-callee-only, TypeChecker OOF-P1/Unknown fixes) | igniter-lab | ✅ DONE | 60/60 |
| LAB-RACK-P10 (call_contract output type verification design preflight — SemanticIR metadata confirmed, literal/dynamic distinction confirmed, module registry pattern viable, not ContractRef) | igniter-lab | ✅ DONE — design | 39/39 |
| LAB-RACK-P11 (call_contract TypeChecker literal callee resolution — build_contract_registry, two-tier policy, Tier 1 resolves output type, OOF-TY0 for unknown/effect/arity/self-recursion literal callees) | igniter-lab | ✅ DONE | 47/47 |
| LAB-RACK-P12 (typed response single-output dispatch — RackResponse type, handler RecordLiteral support, Tier 1 resolves dispatcher compute to RackResponse, Tier 2 stays Unknown) | igniter-lab | ✅ DONE | 45/45 |
| LAB-RACK-P13 (nominal record typechecking — output_type_hints pre-scan, check_record_literal_shape, field missing/extra/wrong-type OOF-TY0, Unknown → named type upgrade on success) | igniter-lab | ✅ DONE | 47/47 |
| LAB-RACK-P14 (Rack-shaped ContractResult composition — 6-branch kind→FullRackResponse mapping (found/created/not_found/capability_denied/upstream_error/upstream_unavailable); map_get→Option[String]+or_else→String; P13 record upgrade; VM-proved 9/10 contracts; map_get VM gap → closed by LAB-VM-MAP-P1) | igniter-lab | ✅ DONE | 60/60 |
| LAB-VM-MAP-P1 (VM runtime map_get/map_has_key/or_else — map_get+map_has_key OP_CALL handlers (bare + qualified aliases); or_else pre-existing; Value::Record = Map[String,String] runtime; compiler input field access fix (OP_LOAD_REF+"name"+OP_GET_FIELD("field")); Rack P14 HeadersAwareHandler 10/10 VM-executable; Sidekiq P5 MetadataReader VM gap closed; fixture: 7 contracts MapGetHit/Miss/OrElseHit/Miss/HasKeyHit/Miss/HeaderChain; 48/48 PASS) | igniter-lab | ✅ DONE | 48/48 |
| LAB-RECORD-VM-P1 (VM record construction — zero new VM/compiler code; OP_PUSH_RECORD+BTreeMap proved; RackResponse + JobReceipt end-to-end; deterministic alphabetical serialization; covers Rack P14 + Sidekiq P5; see shared section below) | igniter-lab | ✅ DONE | 43/43 |
| LAB-RECORD-VM-P2 (dispatched record field access — OP_GET_FIELD added; response.status/body + receipt.status/budget_remaining/job_class proved; field values usable in arithmetic; missing-field OOF-P1 compile-time; Tier 2 field access fail-closed) | igniter-lab | ✅ DONE | 42/42 |
| LAB-RECORD-VM-P3 (nested record field values — one compiler.rs line; envelope.headers.content_type + envelope.meta.priority proved; typechecker + VM construction unchanged; direct local Unknown-typed chain fail-closed; non-record intermediate fail-closed) | igniter-lab | ✅ DONE | 49/49 |
| LAB-RECORD-MAP-P1 (Record/Map bridge — FullRackResponse {headers: Map[String,String]} proved; SIR params preserved through field access; VM store/retrieve works; C1 confirmed active (fix in P5); map_get gap documented; OOF-MAP1/2/3 in MapPipeline) | igniter-lab | ✅ DONE | 51/51 |
| Grammar analog | igniter-lang | ❌ lab pressure only (CR-001 applies) | — |

**Alignment gap:** LAB-RACK-P2..P14 + RECORD-VM-P1..P3 + RECORD-MAP-P1 + LAB-VM-MAP-P1 → lang | VM record construction proved (P1); field access proved (P2); nested record field values proved (P3); Map[String,String] record field bridge proved (RECORD-MAP-P1, SIR params preserved). PROP-043-P5 closed: map_get(response.headers,key)→Option[String] + or_else→String end-to-end in production TypeChecker (55/55); C1 fix landed. P14 closed: 6-kind ContractResult→FullRackResponse branch mapping proved at TypeChecker + VM (9/10 contracts). LAB-VM-MAP-P1 closed: VM map_get bytecode live; HeadersAwareHandler 10/10 VM-executable (48/48 PASS). Still open: Tier 2 type resolution, three-level chained field access, multi-output callee.

**Boundary:** HTTP types may not enter canon grammar without a cross-repo PROP + governance review.
Rack/middleware vocabulary is lab-only.

### Job Processing / Sidekiq (Lab only)

| Artifact | Repo | Status | Checks |
|---|---|---|---|
| LAB-SIDEKIQ-P1 (Sidekiq reimplementation feasibility and language pressure map — job-as-contract, dispatch table, BudgetedLocalLoop retry analogy, closed surfaces) | igniter-lab | ✅ RESEARCH COMPLETE | — |
| LAB-SIDEKIQ-P2 (static job dispatch table — 3 pure job contracts + JobDispatcher, VM-backed via lab-only `call_contract`, all fail-closed cases, P9 regression green) | igniter-lab | ✅ DONE | 54/54 |
| LAB-SIDEKIQ-P3 (BudgetedLocalLoop retry policy — `RetryPolicy` arithmetic, `RetrySimulator` PROP-039 loop fuel enforcement `max_steps:5`, `RetryWithDispatch` dispatch+budget composability) | igniter-lab | ✅ DONE | 43/43 |
| LAB-SIDEKIQ-P4 (JobReceipt schema — `type JobReceipt` 5-field record, P13 nominal record typechecking, P11 Tier 1 literal callee → JobReceipt, Tier 2 dynamic → Unknown, all shape violations OOF-TY0) | igniter-lab | ✅ DONE | 46/46 |
| LAB-RECORD-VM-P1 (VM record construction — JobReceipt end-to-end in VM; see shared section above) | igniter-lab | ✅ DONE (shared) | 43/43 |
| LAB-RECORD-VM-P2 (dispatched record field access — receipt.status/budget_remaining/job_class proved; field values usable in compute; OP_GET_FIELD added; see shared section above) | igniter-lab | ✅ DONE (shared) | 42/42 |
| LAB-RECORD-VM-P3 (nested record field values — JobEnvelope with JobMeta; envelope.meta.priority + envelope.meta.queue proved; see shared section above) | igniter-lab | ✅ DONE (shared) | 49/49 |
| LAB-RECORD-MAP-P1 (Record/Map bridge — JobEnvelope {meta: Map[String,String]} proved; VM meta field store/retrieve; C1 confirmed; see shared section above) | igniter-lab | ✅ DONE (shared) | 51/51 |
| LAB-SIDEKIQ-P5 (upstream HTTP result composition — JobInput/JobReceipt/RetryEnvelope with Map[String,String] metadata; 5 contracts: MetadataReader+SuccessPath+DeniedPath+RetryablePath+ExhaustedPath; map_get(job.metadata,key)→Option[String]+or_else→String via C1 fix; next_attempt=attempt+1→Integer; BudgetedLocalLoop simulation; 4 paths proved; two-layer: Ruby TypeChecker + proof-local sim) | igniter-lab | ✅ DONE | 48/48 |
| Grammar analog | igniter-lang | ❌ lab pressure only (CR-001 applies) | — |

**Alignment gap:** LAB-SIDEKIQ-P1..P5 + RECORD-VM-P1..P3 + RECORD-MAP-P1 + LAB-VM-MAP-P1 → lang | JobReceipt record typed and VM-executed (P1/P2); nested record field values proved (P3); Map[String,String] meta field bridge proved (RECORD-MAP-P1). PROP-043-P5 closed: map_get/or_else production TypeChecker live (55/55); C1 fix landed. LAB-SIDEKIQ-P5 closed: full upstream composition — all 4 job paths (success/denied/retry/exhausted) proved with Map[String,String] metadata; BudgetedLocalLoop simulation (48/48). LAB-VM-MAP-P1 closed: MetadataReader VM gap closed; map_get(job.metadata,"queue") executes end-to-end in VM (48/48 PASS). Still open: three-level chained field access, enum/status type system, async retry, queue storage, effect-callee dispatch.

**Boundary:** Job processing vocabulary is lab-only. No Sidekiq compatibility claim. No StorageCapability, ServiceLoop, or scheduler surfaces open. `call_contract` is lab-only with no stable API.

### Concurrency / Scheduling (Lab only)

| Artifact | Repo | Status | Checks |
|---|---|---|---|
| LAB-CONCURRENCY-P1 (pure-DAG parallel scheduling boundary — wave-based concurrent eligibility; SequentialScheduler == ParallelSchedulerSimulation result identity proved; effectful nodes serialized in v0; SchedulingReceipt telemetry only; 5 inline graph fixtures: diamond, fanout, chain, mixed-effectful, impure-siblings; DagValidator cycle+dep checks; DagWaves read-isolation invariant; Category: lang, Track: lab-deterministic-pure-dag-parallel-scheduling-boundary-v0) | igniter-lab | ✅ DONE | 57/57 |
| LAB-CONCURRENCY-P2 (capability-aware effect scheduling policy boundary — PolicyEvaluator 6-gate sequence: capability_denied→no_policy→unknown_resource→resource_conflict→category_closed→eligible; EffectSpec resource_keys + effect_category + capability_id; 8 fixtures (default_effect_serialized, read_read_disjoint, write_write_same, read_write_same, net_disjoint, net_same_host_closed, unknown_resource_key, denied_capability); parity: eligible==serialized result_values; PolicySchedulingReceipt telemetry only; P1 pure-DAG regression green; Category: lang, Track: lab-capability-aware-effect-scheduling-policy-boundary-v0) | igniter-lab | ✅ DONE | 59/59 |
| LAB-CONCURRENCY-P3 (scheduling receipt determinism and replay — ReplayableReceipt with schema_version/graph_digest/policy_digest/result_digest/spec_digest fields; DigestableMixin 4 digest functions; ReceiptReplayerP3 10-gate validation: schema→graph_digest→policy_digest→node_membership→wave_assignment→same_wave_dep→spec_drift→eligibility_tamper→result_consistency→re_execution; all graph/policy/effect/result/wave tampering fails closed; consistent result tamper (values+digest both changed) caught by Gate 10 re-execution; legal intra-wave permutations are equivalent; scheduling-receipt-evidence-only-v0; Category: lang, Track: lab-scheduling-receipt-determinism-and-replay-proof-v0) | igniter-lab | ✅ DONE | 60/60 |
| LAB-CONCURRENCY-P4 (minimal scheduler substrate contract — five-phase model: PREPARE/PLAN/EXECUTE_WAVE/RECORD/FINALIZE_RECEIPT; 9 substrate invariants SI-1..SI-9 (graph-digest-fixed, policy-digest-fixed, read-isolation, write-once, topo-order, policy-gate, eligibility-recorded, denial-recorded, canonical-result-digest); substrate options matrix: single-thread OPEN, simulated-parallel OPEN, real-thread-pool HOLD pending P5, async HOLD pending separate card; failure-mode matrix: node failure/policy mismatch/partial execution/effect denial; readiness checklist per substrate tier; W1 necessary-but-not-sufficient for threading; design only — no proof runner; Category: lang, Track: lab-scheduler-substrate-readiness-and-minimal-runtime-contract-v0) | igniter-lab | ✅ DONE — design | — |

**Boundary:** Lab-only. `ReplayableReceipt`, `PolicySchedulingReceipt`, and `SchedulingReceipt` are telemetry evidence only — they do not create semantic authority over scheduling decisions and do not open runtime concurrency authority. No `Thread`/`Fiber`/async-runtime infrastructure used. Concurrent-effectful dispatch requires explicit `SchedulingPolicy` (P2); overlapping writes and unknown resource keys always fail-closed; capability denial is Gate 1. Parity invariant proved across all fixtures: `result_values` identical regardless of `concurrent_eligible` flag (P1+P2). Replay invariant proved (P3): tampered receipts fail closed across all drift categories; consistent result tampering caught by Gate 10 re-execution; legal intra-wave permutations are structurally equivalent. Minimal substrate contract named (P4): five-phase model + 9 invariants + substrate options matrix + failure-mode matrix; real threading HOLD until P5 thread-safety proof; async HOLD until separate authorization card.

### Governance (Design / Classification)

| Artifact | Repo | Status | Notes |
|---|---|---|---|
| LAB-IO-BOUNDARY-P1 (IO family taxonomy and substrate readiness — IO separated into Storage/Network/File-Text/Clock-Time/Random-Entropy/Process-Command/UI-Host IPC; Query v0 kept intent/receipt only; substrate readiness checklist locked; Storage ready for design/mock adapter hardening only; Network real transport HOLD; no real IO/public API/canon authority created) | igniter-lab | ✅ CLOSED — governance boundary | governance |
| PROP-047-P2 (Failure Outcome Naming Convention partial_success amendment — `partial_success` promoted after LAB-FAILURE-TAXONOMY-P4; stable term count now 6: denied/unknown_external_state/timed_out/system_error/query_error/partial_success; no parser/compiler/VM/runtime/type-system/OOF/global-enum/Outcome[T,E]/public-API authority created) | igniter-lang | ✅ CLOSED — amendment | governance |
| LAB-RESULT-ENVELOPE-P1 (Contract result envelope taxonomy + promotion boundary — 5 reusable patterns confirmed; HttpResult/ContractResult/FullRackResponse/JobReceipt classified domain-local; two RetryEnvelope shapes incompatible; denial-as-data is strongest invariant (6 proofs); no canon promotion; next: LAB-VM-MAP-P1 + LAB-RESULT-ENVELOPE-P2) | igniter-lab | ✅ DONE — analysis | governance |
| LAB-RESULT-ENVELOPE-P2 (Third-domain kind-discriminant pressure — form validation domain; ValidationResult 4-kind (valid/invalid/unauthorized/system_error); no HTTP status, no job fields; denial-as-data 7th proof; Map[String,String] 3rd context; kind-discriminant confirmed cross-domain; ValidationMapper three-layer confirmed; PROP-044 unblocked for proposal-authoring; 50/50 PASS) | igniter-lab | ✅ DONE — analysis | governance |
| PROP-044-P1 (Kind-discriminated outcome convention and sum type requirements — proposal authoring; KDR pattern defined; denial-as-data invariant stated; grammar gap enumerated (variant+match+narrowing); OOF-KIND1..4 namespace reserved; production implementation blocked; grammar proposal P2 authorized) | igniter-lang | ✅ DONE — proposal authored | governance |
| PROP-044-P2 (variant+match grammar design — VariantDecl EBNF; MatchExpr EBNF; VariantConstruct expr; type narrowing rules; OOF-KIND1..5 formal defs; SemanticIR shapes; parser+typechecker extension points; 15 decisions locked; P3 parser impl requires explicit auth) | igniter-lang | ✅ DONE — grammar design authored | governance |
| PROP-044-P3 (variant+match parser implementation — fat_arrow lexer; variant/match keywords; 6 new parse methods; ParsedProgram variants field + grammar_version=variant-v0; conflict boundaries proved; TypeChecker no-crash confirmed; all prior proofs clean; 50/50 PASS) | igniter-lang | ✅ DONE — parser implemented | lang |
| PROP-044-P4 (TypeChecker design — @variant_shapes 3-level store; classifier bridge (variant_declarations() + classified_program key); infer_variant_construct; infer_match_expr; unify_match_arm_types; OOF-KIND1..5 formal defs; per-arm narrowing; exhaustiveness algorithm; degraded mode; 16 design decisions; proof requirements 15 groups ~75-80 checks; P5 implementation requires explicit auth) | igniter-lang | ✅ DONE — typechecker design authored | governance |
| PROP-044-P5 (TypeChecker implementation — classifier bridge live; @variant_shapes store; infer_variant_construct; infer_match_expr full+degraded; unify_match_arm_types; OOF-KIND1..5 ACTIVE; variant_env in typed_program; 75/75 PASS; regressions clean 55+33+100+50) | igniter-lang | ✅ DONE — TypeChecker implemented | lang |
| PROP-044-P6 (SemanticIR emitter — semantic_variant_declarations (variant_env→variant_decl[]); semantic_variant_construct (arm/variant/fields/resolved_type); semantic_match_node (match_node kind; subject/subject_type/arms/exhaustive/has_wildcard); semantic_match_arm (pattern/body/resolved_type); wired into semantic_expr dispatch; variant_declarations at top-level semantic_ir_program; OOF-KIND1..5 → nil sir; 50/50 PASS; P5+P3+OOF-R3 regressions clean) | igniter-lang | ✅ DONE — SemanticIR emitter implemented | lang |

**Confirmed reusable patterns (no promotion yet):** denial-as-data (design law — **10 proofs**, 5 domains: network + HTTP + validation + query + storage), kind-discriminant (**confirmed cross-domain** — 5 domains: HttpResult + ContractResult + ValidationResult + QueryResult + StorageQueryResult), Map[String,String] (**4 contexts**: transport headers + job metadata + form metadata + query metadata), three-layer composition (**confirmed in validation domain**), attempt+max_attempts budget (domain-local — retry-capable domains only; NOT universal).  
**Blockers for any canon proposal:** ~~VM map_get bytecode~~ → ✅ closed; ~~only 2 domains~~ → ✅ 3 domains (P2); ~~proposal-authoring~~ → ✅ PROP-044-P1 authored; ~~grammar design~~ → ✅ PROP-044-P2 authored; ~~parser implementation~~ → ✅ PROP-044-P3 PASS 50/50; ~~typechecker design~~ → ✅ PROP-044-P4 authored; ~~TypeChecker implementation~~ → ✅ PROP-044-P5 PASS 75/75; ~~SemanticIR emitter~~ → ✅ PROP-044-P6 PASS 50/50; VM variant dispatch (P7) requires explicit authorization.  
**PROP-044 status:** ~~deferred~~ → ~~PROPOSAL-AUTHORING ONLY~~ → ~~P1 AUTHORED~~ → ~~P2 GRAMMAR DESIGN AUTHORED~~ → ~~P3 PARSER LIVE~~ → ~~P4 TYPECHECKER DESIGN AUTHORED~~ → ~~P5 TYPECHECKER LIVE~~ → **P6 SEMANTICIR EMITTER LIVE** — variant_decl/variant_construct/match_node; 50/50 PASS; P7 VM variant dispatch requires explicit authorization.  
**LAB-QUERY-P1:** Query/Arel-like data access boundary defined — QueryPlan v0 types (QuerySource/Projection/FilterPredicate/OrderBy/QueryPlan/QueryResult/StorageDenied) all expressible as named Records today; ORM permanently closed; joins/aggregates deferred to v1; StorageCapability boundary modelled on PROP-035; LAB-QUERY-P2 authorized (42 checks).

### Data Access / Query (LAB-QUERY)

| Artifact | Repo | Status | Notes |
|---|---|---|---|
| LAB-QUERY-P1 (Research: Arel-like query intent as typed records — QueryPlan/QueryResult/FilterPredicate/OrderBy types; ORM permanently closed; joins/aggregates deferred; StorageCapability boundary; denial-as-data 5-kind QueryResult; LAB-QUERY-P2 authorized) | igniter-lab | ✅ DONE — research + design boundary | lang / research |
| LAB-QUERY-P2 (QueryPlan pure builder proof — 6 contracts; 7 types; BuildQuerySource+BuildSelectQuery+BuildFilteredQuery+QueryResultDenied+QueryMetadataReader+QueryMapper; denial-as-data QueryResult{kind:"denied"}; C1 chain in 4th domain (result.metadata→Map[String,String]→Option[String]); all CORE fragment; 42/42 PASS) | igniter-lab | ✅ DONE — 42/42 PASS | lang / proof |
| LAB-STORAGE-CAPABILITY-P1 (IO.StorageCapability boundary design — allowed_sources/allowed_ops/row_limit/allow_include_all/read_allowed/write_allowed schema; 6-gate denial-as-data sequence; QueryExecutionReceipt shape; ExecuteQuery effect contract form (future); ESCAPE→STORAGE fragment; OOF-STORE1..5 candidates; 10 decisions locked) | igniter-lab | ✅ DONE — design-locked | lang / design |
| LAB-QUERY-P3 (QueryPlan v1 nested records + Collection[FilterPredicate] — 8 contracts; 7 types; nested QuerySource/Projection/OrderBy/Collection[FilterPredicate]; chained field access plan.source.table (LAB-RECORD-VM-P3 two-hop OP_GET_FIELD); C1 chain on richer QueryPlan; QueryResultDenied denial-as-data 8th proof; Rust typechecker array_literal gap documented; Layer A: Ruby TC; Layer B: Rust VM; Layer C: QueryExecutorSim; 44/44 PASS) | igniter-lab | ✅ DONE — 44/44 PASS | lang / proof |
| LAB-STORAGE-CAPABILITY-P2 (IO.StorageCapability mocked execution boundary proof — 6-gate denial sequence (G1–G6); G4=row-limit clamp (not denial); G5=include_all→query_error (not denied); denial-as-data 9th proof; QueryExecutionReceipt 15-field evidence record (6 invariants); KDR 5-kind vocabulary; separation from TBackend/TEMPORAL; two-fixture architecture (exec compile-only + receipts VM-executable); 4 boundary findings (B1: passport gap/ESCAPE class; B2: effect name closed vocab; B3: `read` keyword; B4: `message` keyword); Layer A Ruby TC + Layer B Rust VM + Layer C StorageCapabilityGates; 51/51 PASS) | igniter-lab | ✅ DONE — 51/51 PASS | lang / proof |
| LAB-EXECUTE-QUERY-P1 (ExecuteQuery effect contract and StorageCapability injection proof — 57/57 PASS; Stage 2+ first executable query path; ExecuteQuery effect contract (Layer A+B compile; ESCAPE class; two-fixture architecture); 6-gate denial sequence via Layer C ExecuteQuerySim; G4 clamp ≠ denial; G5 query_error ≠ denied; QueryExecutionReceipt 15-field invariants; BuildQueryPlanInline.filters=Collection[FilterPredicate] in Rust SIR (LAB-TC-ARRAY-P2 record-field-context confirmed); denial-as-data 10th proof; 5-kind KDR; TBackend absent; write ops CLOSED in v0; 12 pure contracts VM-executable; B3: deny_reason; B4: read_file; no DB/SQL/ORM/raise/persistence) | igniter-lab | ✅ DONE — 57/57 PASS | lang / proof |
| LAB-TC-ARRAY-P1 (Rust TypeChecker array-literal-in-Collection-context proof — closes LAB-QUERY-P3 finding B1; `compute filters = [{...},{...}]` / `[f1,f2]` now type as Collection[FilterPredicate] in a declared `output x : Collection[T]` position; CONTEXTUAL (mirrors RecordLiteral LAB-RACK-P13 upgrade); impl: collection_output_hints prescan + ArrayLiteral arm in infer_expr (Unknown free-standing, no OOF-TY0) + contextual upgrade block + check_array_literal_shape helper in typechecker.rs; empty array accepted ONLY with contextual type; free-standing stays Unknown; missing/extra/wrong-typed fields + mixed element shapes fail closed (OOF-TY0); Collection[FilterPredicate] survives into SIR type_tag (compute + output port); VM round-trips inline-constructed collection + full QueryPlan with inline filters; Layer B primary + Layer A parity; no new grammar; no DB/SQL/ORM/StorageCapability execution; 27/27 PASS; regressions clean: P3 44/44, P13 47/47, VM-MAP 48/48, record-vm 42/49/43) | igniter-lab | ✅ DONE — 27/27 PASS | lang / proof |
| LAB-TC-NESTED-RECORD-CONTEXT-P1 (Nested record literal context propagation — LAB FIX + PROOF / RUST TYPECHECKER HARDENING / NO QUERY SEMANTICS CHANGE; closes B9 gap from LAB-QUERY-PROJECTION-P1; extends check_record_literal_shape with type_shapes param + RecordLiteral arm; bounded contextual recursion (no global inference); natural projection syntax now compiles; two-level nesting works; fail-closed: missing/extra/wrong-type fields → OOF-TY0; LAB-TC-ARRAY-P1/P2 unaffected; Ruby TC B9 divergence documented (not fixed here); no VM/parser/grammar change; 6 pure contracts; 42/42 PASS) | igniter-lab | ✅ DONE — 42/42 PASS | lang / proof |
| LAB-TC-ARRAY-P2 (Rust TypeChecker array-literal-in-record-field-context proof — closes the non-blocking gap left by P1; an intermediate `compute filters = [...]` that feeds a typed record field (`compute plan = {..., filters: filters, ...}` / `output plan : QueryPlan` where QueryPlan.filters : Collection[FilterPredicate]) now types `filters` as Collection[FilterPredicate]; impl: order-independent prescan contributing record-field hints to the SAME collection_output_hints map P1 uses — for a RecordLiteral compute with a named-record output type, each bare-Ref field declared Collection[T] feeds hint T to the referenced compute (or_insert; P1 output hints win); LOCAL single-hop syntactic lookup, NO global/HM inference, NO retroactive symbol mutation (referenced compute typed first in dependency order); empty intermediate typed from field context iff field type known; bad/mixed elements still fail closed (OOF-TY0); P1 output-context + free-standing-Unknown preserved; VM round-trips plan.filters; no new grammar; no DB/SQL/ORM/StorageCapability; 19/19 PASS; regressions clean P1 27/27 + P3 44/44 + VM-MAP 48/48 + P13 47/47 + record-vm 43/42/49) | igniter-lab | ✅ DONE — 19/19 PASS | lang / proof |
| LAB-FILTER-EVAL-P1 (Filter predicate evaluation over mocked in-memory rows — 9 pure contracts (all CORE; no effect; no capability); v0 operators: eq/neq/contains/prefix; AND-only composition (filters.all?); Layer C FilterEvalSim proof-local Ruby evaluator; 5-row deterministic dataset; empty filter list → all rows; unknown field → no match (kind:"empty"); unknown op → kind:"query_error" (NOT "denied"); count==matched_rows.length invariant; BuildQueryPlanWithFilters.filters=Collection[FilterPredicate] in Rust SIR (LAB-TC-ARRAY-P2 record-field-context mechanism, 3rd confirmation); inline empty array → Collection[FilterPredicate] from record-field context; B1: VM has no iteration opcodes (Layer C correct boundary); B2: empty array field-context confirmed; B3: unknown field ≠ unknown op; B4: G1–G6 gate sequence orthogonal to filter evaluation; no DB/SQL/ORM/StorageCapability; KDR 3-kind routing: rows/empty/query_error; 50/50 PASS) | igniter-lab | ✅ DONE — 50/50 PASS | lang / proof |
| LAB-QUERY-ORDER-LIMIT-P1 (Order and limit semantics over mocked in-memory rows — 7 pure contracts (all CORE; no effect; no capability); OrderBy{field,direction}; v0 directions: asc/desc/empty/unknown; stable sort (equal keys preserve input order); limit>0→first N rows after ordering; limit==0→kind:"empty"; limit<0→kind:"query_error" (NOT "denied"); unknown direction→kind:"query_error" (NOT "denied"); missing order field in row→kind:"query_error" (fail-closed); order-then-limit invariant; Layer C OrderLimitSim proof-local Ruby evaluator; 5-row deterministic dataset; filter→order→limit pipeline composes; QueryPlan.limit ≠ StorageCapability row_limit gate (orthogonal); BuildQueryPlanOrderLimit.filters=Collection[FilterPredicate] in Rust SIR (LAB-TC-ARRAY-P2 mechanism, 4th confirmation); B1: VM has no sort/iteration opcodes (Layer C correct boundary); B2: Collection[FilterPredicate] from record-field context 4th confirmation; B3: unknown dir/neg limit/missing field all query_error not denied; B4: QueryPlan.limit ≠ StorageCapability row_limit; B5: message Ruby keyword confirmed (use reason); count==returned_rows.length invariant; KDR 3-kind routing: rows/empty/query_error; all comparisons lexicographic String in v0; 54/54 PASS) | igniter-lab | ✅ DONE — 54/54 PASS | lang / proof |
| LAB-EXECUTE-QUERY-P2 (First complete mocked ExecuteQuery pipeline — 8 pure contracts (all CORE; no effect; no capability authority); integrates gates + filter + order + limit + receipt in one IntegratedQuerySim; G1/G2/G3→denied; G4 clamp ≠ denial (effective_limit=min(plan.limit,cap.row_limit); cap_granted:true); G5→query_error (NOT denied); G6 filter+order+limit evaluation; gate failures short-circuit before filter/order/limit; query_error ≠ denied throughout pipeline; filter: eq/neq/contains/prefix; AND-only; unknown op→query_error; missing field→empty; order: asc/desc lexicographic stable sort; unknown direction→query_error; limit: applied after filter+order; limit==0→empty; limit<0→query_error; QueryExecutionReceipt 15-field verified (cap_checked/cap_granted/denial_gate/effective_limit/row_limit_clamped/rows_returned/result_kind); BuildIntegratedPlan.filters=Collection[FilterPredicate] in Rust SIR (LAB-TC-ARRAY-P2 record-field-context mechanism, 5th confirmation); all 8 contracts VM-executed; B1: gate short-circuit is correct model; B2: G4 clamp ≠ denial; B3: G5→query_error not denied; B4: query_error ≠ denied invariant throughout; B5: QueryPlan.limit ≠ StorageCapability row_limit orthogonal; B6: 5th confirmation of P2 mechanism; B7: message Ruby keyword (use deny_reason/reason); KDR 5-kind routing: rows/empty/denied/query_error/system_error; IntegratedQuerySim PROOF-LOCAL ONLY; no SQL/DB/ORM/StorageCapability authority; 73/73 PASS) | igniter-lab | ✅ DONE — 73/73 PASS | lang / proof |
| LAB-QUERY-MULTI-ORDER-P1 (Multi-column order semantics over mocked rows — 7 pure contracts (all CORE; no effect; no capability); QueryPlanMultiOrder with order: Collection[OrderBy] (new type, no mutation of existing QueryPlan); empty Collection[OrderBy]→preserve input order (no-op); empty direction in entry→query_error (explicit step must have direction; differs from single-order P1); unknown direction→query_error (NOT denied); missing field→query_error (NOT denied); stable sort: equal keys preserve input order (integer index tiebreaker); primary/secondary/tertiary key priority order; per-column asc/desc via ReverseComparable; limit applied AFTER all ordering; gates+filter+multi-order+limit compose correctly; Collection[OrderBy] from record-field context (LAB-TC-ARRAY-P2 mechanism, 6th confirmation); all 7 contracts VM-executed; MultiOrderSim PROOF-LOCAL ONLY; no SQL/DB/ORM/StorageCapability; 64/64 PASS) | igniter-lab | ✅ DONE — 64/64 PASS | lang / proof |
| LAB-QUERY-PROJECTION-P1 (Projection and include_all row-shaping semantics over mocked rows — 7 pure contracts (all CORE; no effect; no capability); Projection{fields:String,include_all:Bool} as final pipeline step after filter+multi-order+limit; include_all=true→full row passthrough (identity projection); include_all=false→comma-split field list; empty fields→query_error (malformed plan); missing field in row→query_error (fail-closed); duplicate fields→de-duplicate preserving first occurrence (not query_error); projection does not change row count; G5 include_all policy→query_error (NOT denied); LAB-TC-ARRAY-P2 7th confirmation (BuildFieldsProjectionPlan.order_list:Collection[OrderBy]); B9 TypeChecker nested-record-literal boundary documented (workaround: projection as input); ProjectionSim PROOF-LOCAL ONLY; no SQL/DB/ORM/StorageCapability; 62/62 PASS) | igniter-lab | ✅ DONE — 62/62 PASS | lang / proof |
| LAB-EXECUTE-QUERY-P3 (Unified mocked query execution receipt — 68/68 PASS; complete v0 pipeline: G1→G2→G3→G4→G5→filter→multi-order→limit→projection→receipt; QueryPlanUnified with Collection[FilterPredicate]+Collection[OrderBy]+Projection (new type; does not mutate existing QueryPlan/QueryPlanMultiOrder/QueryPlanProjection); projection final step; G4 clamp≠denial (cap_granted:true); G5 include_all→query_error NOT denied; query_error≠denied throughout; receipt mirrors result_kind+rows_returned after projection; row count invariant; 8 pure contracts (all CORE; no effect); all 8 VM-executed; LAB-TC-ARRAY-P2 8th confirmation (BuildUnifiedPlan.filters:Collection[FilterPredicate]); B9 boundary documented; UnifiedQuerySim PROOF-LOCAL ONLY; no SQL/DB/ORM/StorageCapability; integrates P2+MULTI-ORDER-P1+PROJECTION-P1) | igniter-lab | ✅ DONE — 68/68 PASS | lang / proof |
| LAB-STORAGE-ADAPTER-P1 (Mocked Storage adapter contract hardening — 80/80 PASS; explicit adapter boundary around Query v0 semantics; StorageAdapterRequest = QueryPlanUnified + StorageCapability-shaped record + MockStorageSource + request/execution ids; StorageAdapterReceipt adds adapter_id/mocked_source_id/fixture_digest/ambient_state_used without duplicating QueryExecutionReceipt gates; source not allowed→denied; allowed source missing from mock registry→system_error (not empty/query_error); bad filter/order/projection/limit/include_all→query_error; row_limit clamp→rows/empty with row_limit_clamped=true; deterministic replay digest stable; explicit fixture rows only; no real DB/SQL/ORM/writes/joins/aggregates/optimizer/public API/parser/compiler/VM/canon authority) | igniter-lab | ✅ DONE — 80/80 PASS | lang / proof |

**Boundary:** QueryPlan v1 = nested typed records (QuerySource/Projection/FilterPredicate/OrderBy) + Collection[FilterPredicate] + Map[String,String] metadata; all pure CORE contracts; no grammar changes; no SQL; no DB connections. ORM/ActiveRecord permanently incompatible. `IO.StorageCapability` schema designed (follows PROP-035 model; grammar impl requires PROP-035). QueryResult follows KDR convention (PROP-044-P1). ExecuteQuery = ESCAPE → STORAGE (Stage 2+). LAB-STORAGE-CAPABILITY-P1 design-locked. Rust typechecker array_literal gap: **CLOSED by LAB-TC-ARRAY-P1 (27/27 PASS)** — array literals now type as Collection[T] in declared Collection output contexts (contextual); inline filter construction compiles + VM round-trips; the P3 `filters`-as-input workaround is no longer required. **Record-field-position follow-up CLOSED by LAB-TC-ARRAY-P2 (19/19 PASS):** an intermediate array-literal compute feeding a typed record field (e.g. QueryPlan.filters) now types as Collection[T] via a local single-hop Ref-field hint prescan (no global inference); remaining edges (inline-in-field literals, multi-hop, conflicting hints) deferred to an optional v1 collection-inference card, not required before execution. With P1+P2, filter collections are fully constructible inline — expressivity is sufficient for LAB-EXECUTE-QUERY-P1. **LAB-STORAGE-CAPABILITY-P2 CLOSED (51/51 PASS):** 6-gate denial sequence proved; G4=clamp (not denial); G5→query_error (not denied); QueryExecutionReceipt 15-field invariants; denial-as-data 9th proof (StorageCapability 5th domain); ESCAPE class enforcement confirmed (effect contract passport gap = correct behavior); Rust effect name vocabulary closed ({read_file,read_json,read,write_file,write_json,write}); two-fixture architecture established for effect+pure contract lab separation. **LAB-EXECUTE-QUERY-P1 CLOSED (57/57 PASS):** first executable Stage 2+ query path proved; ExecuteQuery effect contract (Layer A+B compile; ESCAPE boundary correct); 6-gate sequence confirmed with QueryPlan + StorageCapability hashes; G4 clamp ≠ denial; G5 query_error ≠ denied; QueryExecutionReceipt invariants VM-verified; BuildQueryPlanInline.filters typed Collection[FilterPredicate] in Rust SIR (LAB-TC-ARRAY-P2 record-field-context confirmed in EXECQ fixture); denial-as-data 10th proof; TBackend/TEMPORAL absent (orthogonality confirmed); write ops CLOSED in v0; 12 pure contracts VM-executable; two-fixture architecture reused. **LAB-FILTER-EVAL-P1 CLOSED (50/50 PASS):** QueryPlan.filters is no longer just shape — it has a v0 semantic meaning over mocked in-memory rows; eq/neq/contains/prefix operators proved; AND composition narrows correctly (3<4); empty filter list → all rows; unknown field → kind:"empty" (not query_error); unknown operator → kind:"query_error" (NOT denied); count==matched_rows.length invariant; Layer C required for row evaluation semantics (VM has no iteration opcodes, correct boundary); inline empty array → Collection[FilterPredicate] (3rd confirmation of P2 mechanism); G1–G6 gate sequence orthogonal. **LAB-QUERY-ORDER-LIMIT-P1 CLOSED (54/54 PASS):** QueryPlan.order and QueryPlan.limit are no longer just shape — they have v0 semantic meaning over mocked in-memory rows; asc/desc lexicographic sort correct; stable sort (equal keys preserve input order); empty direction → preserve input order; unknown direction → kind:"query_error" (NOT denied); missing order field in row → kind:"query_error" (fail-closed); limit>0 → first N after ordering; limit==0 → kind:"empty"; limit<0 → kind:"query_error" (NOT denied); order-then-limit invariant; filter→order→limit pipeline composes; QueryPlan.limit ≠ StorageCapability row_limit gate (orthogonal); BuildQueryPlanOrderLimit.filters typed Collection[FilterPredicate] in Rust SIR (4th confirmation of LAB-TC-ARRAY-P2 mechanism); 7 pure contracts; all lexicographic String comparison in v0. **LAB-EXECUTE-QUERY-P2 CLOSED (73/73 PASS):** first complete mocked ExecuteQuery pipeline; StorageCapability gates + filter + order + limit + receipt integrated in one IntegratedQuerySim; G1/G2/G3 short-circuit before filter/order/limit; G4 clamp ≠ denial (effective_limit=min; cap_granted:true); G5→query_error (NOT denied); query_error ≠ denied invariant confirmed throughout; QueryExecutionReceipt 15-field invariants verified (cap_checked/cap_granted/denial_gate/effective_limit/row_limit_clamped/rows_returned/result_kind); BuildIntegratedPlan.filters=Collection[FilterPredicate] in Rust SIR (LAB-TC-ARRAY-P2 mechanism, 5th confirmation); all 8 contracts VM-executed; KDR 5-kind routing: rows/empty/denied/query_error/system_error; IntegratedQuerySim is PROOF-LOCAL ONLY; joins/aggregates/writes/production-runtime CLOSED. **LAB-QUERY-MULTI-ORDER-P1 CLOSED (64/64 PASS):** multi-column order semantics proved; QueryPlanMultiOrder with order: Collection[OrderBy] (new type; no mutation of existing QueryPlan); empty list→preserve input order (no-op); empty direction in entry→query_error (explicit step must have direction; differs from single-order P1 where empty=no sort); unknown direction→query_error (NOT denied); stable sort: equal keys preserve input order (integer index tiebreaker); primary/secondary/tertiary key priority order; per-column asc/desc via ReverseComparable pattern (all positions same type → Array#<=> correct); limit applied AFTER all ordering (order-then-limit invariant preserved); gates+filter+multi-order+limit compose correctly in integrated pipeline; Collection[OrderBy] from record-field context (LAB-TC-ARRAY-P2 mechanism, 6th confirmation); all 7 contracts VM-executed; MultiOrderSim is PROOF-LOCAL ONLY; numeric/date/collation ordering deferred; no SQL/DB/ORM/StorageCapability authority. **LAB-QUERY-PROJECTION-P1 CLOSED (62/62 PASS):** Projection{fields:String,include_all:Bool} row-shaping semantics proved; include_all=true→full row passthrough (identity projection); include_all=false→comma-split field list (split+strip+reject_empty); empty fields→query_error (malformed plan); missing field in row→query_error (fail-closed); duplicate fields→de-duplicate preserving first occurrence (not query_error); projection does not change row count; projection applied AFTER filter→multi-order→limit (final pipeline step); G5 include_all policy (allow_include_all=false)→query_error (NOT denied); query_error≠denied invariant confirmed throughout; LAB-TC-ARRAY-P2 7th confirmation (BuildFieldsProjectionPlan.order_list:Collection[OrderBy]); B9 TypeChecker boundary: nested record literals inside outer record literals do not get inner-field type context (workaround: pass projection as input; gap documented for future TC card); ProjectionSim is PROOF-LOCAL ONLY; fields:String v0 (Collection[String] grammar change deferred); no SQL/DB/ORM/optimizer/joins/writes/StorageCapability authority. **LAB-TC-NESTED-RECORD-CONTEXT-P1 CLOSED (42/42 PASS):** closes B9 gap from LAB-QUERY-PROJECTION-P1; extended check_record_literal_shape with type_shapes param + RecordLiteral arm for recursive contextual validation of inline nested record literals; bounded: one call per nesting level, no global inference, no Hindley-Milner, no retroactive mutation; natural projection syntax now compiles: compute plan = { ..., projection: { fields: "...", include_all: false }, ... }; two-level nesting (ContactRecord → Contact → Address) works; fail-closed: missing field/extra field/wrong-type field in nested literal → OOF-TY0 with informative messages; LAB-TC-ARRAY-P1/P2 unaffected; PROJECTION-P1 workaround (projection as input) still valid; Ruby TC B9 divergence documented (different bug in Ruby TC, not fixed here); fix scope: typechecker.rs only, no VM/parser/grammar/production-runtime change. **LAB-EXECUTE-QUERY-P3 CLOSED (68/68 PASS):** unified mocked query execution receipt proved; complete v0 pipeline: G1→G2→G3→G4→G5→filter→multi-order→limit→projection→receipt; QueryPlanUnified with Collection[FilterPredicate]+Collection[OrderBy]+Projection (new type; does not mutate existing QueryPlan/QueryPlanMultiOrder/QueryPlanProjection from prior fixtures); projection is the final pipeline step — AFTER filter+multi-order+limit; projection does not change row count (column selector, not row filter); G4 clamp remains NON-denial (cap_granted:true after clamp; effective_limit recorded in receipt); G5 include_all policy→query_error (NOT denied; fires before filter/order/limit/projection); query_error≠denied invariant confirmed throughout (G1/G2/G3→denied; all other failures→query_error); receipt mirrors result_kind and rows_returned after full pipeline (after projection; cap_granted:false iff denied/query_error); G1/G2/G3 short-circuit: filter/order/limit/projection NOT evaluated on denial; 8 pure contracts (all CORE; no effect; no capability); all 8 contracts VM-executed; LAB-TC-ARRAY-P2 8th confirmation (BuildUnifiedPlan.filters typed Collection[FilterPredicate] in Rust SIR via record-field-context); B9 TypeChecker nested-record-literal boundary documented (projection passed as input; not fixed here — already closed by LAB-TC-NESTED-RECORD-CONTEXT-P1); UnifiedQuerySim PROOF-LOCAL ONLY; no SQL/DB/ORM/optimizer/joins/writes/StorageCapability authority.

**Boundary (LAB-STORAGE-ADAPTER-P1):** mocked adapter contract only; Query v0 semantics reused, not redefined; `StorageAdapterReceipt` is adapter evidence, not authority; allowed source missing from mock registry is `system_error` (fixture/substrate missing), never `empty`; no real DB/SQL/ORM/writes/joins/aggregates/optimizer/public API/parser/compiler/VM/canon authority. Next storage route: LAB-STORAGE-ADAPTER-P2 receipt/replay hardening, or parallel LAB-FILE-IO-P1 / LAB-HOST-IPC-P1; real storage adapter remains HOLD.

### Web Framework / View Engine (Lab only)

| Artifact | Repo | Status | Checks |
|---|---|---|---|
| LAB-WEB-FRAMEWORK-P4 (LayoutEngine, fill_slot, render, inheritance) | igniter-lab | ✅ DONE | ~45/45 |
| Grammar analog | igniter-lang | ❌ lab-only for now | — |

### Dynamic Data Structures (LAB-DYNAMIC-DATA)

| Artifact | Repo | Status | Notes |
|---|---|---|---|
| LAB-DYNAMIC-DATA-P1: taxonomy + pressure map + boundary research | igniter-lab | ✅ CLOSED 2026-06-09 | Map/Record/JsonValue/Table/Unknown — research only |
| PROP-043-P1: Map[K,V] Stage 1 design lock | igniter-lang | ✅ CLOSED 2026-06-09 | 15 decisions; stdlib.map.* v0 surface; OOF-MAP1/2/3 candidates; P2 fixture matrix ≥18 checks |
| PROP-043-P2: Map[K,V] proof-local experiment | igniter-lang | ✅ CLOSED 2026-06-09 | MapPipeline + 15 fixtures + verify script; 42/42 PASS; OOF-MAP1/2/3 candidates proven; map_get/has_key/from_pairs/or_else type rules; FullRackResponse headers clean |
| PROP-043-P3: Map[K,V] acceptance decision | igniter-lang | ✅ CLOSED 2026-06-09 | P2 accepted; OOF-MAP1/2/3 → experiment-pass; Map[String,V] v0 accepted; map_empty conditional (C2); 9 P4-Q items; P4 authorized |
| PROP-043-P4: Map[K,V] production-edit planning | igniter-lang | ✅ CLOSED 2026-06-09 | 2-file scope: classifier.rb (1-line C1 fix) + typechecker.rb (+175 lines); SIR emitter + parser no change; or_else new addition; C1/C2 resolved; OOF-MAP wording locked; P5 authorized |
| PROP-043-P5: Map[K,V] production implementation + Record/Map bridge | igniter-lang | ✅ CLOSED 2026-06-09 | classifier.rb C1 fix + typechecker.rb (+180 lines); OOF-MAP1/2/3 active; map_get/has_key/from_pairs/empty + or_else; MAP-BRIDGE: map_get(response.headers,key)→Option[String] + or_else→String proved; C1 fix closes LAB-RECORD-MAP-P1 gap; verify_prop043_map_production.rb 55/55 PASS; all regressions clean |
| LAB-MAP-RUST-P1: Map[String,V] Rust lab compiler symmetry | igniter-lab | ✅ CLOSED 2026-06-09 | typechecker.rs: or_else Option[V] extraction fix; map_get/has_key/from_pairs/empty handlers; OOF-MAP1/2/3 parity; Record/Map bridge map_get(response.headers,key)→Option[String]+or_else→String; 32/32 PASS; all regressions clean; C1 not needed in Rust |

**Three-tier hierarchy (research finding):**
1. Named `Record` — known-schema data (proven: P12/P13/Sidekiq-P4)
2. `Map[K, V]` — dynamic-key homogeneous-value (✅ Stage 1 production live — PROP-043-P5; OOF-MAP1/2/3 active; map_get/has_key/from_pairs/empty + or_else + Record/Map bridge proved; Rust lab symmetry: LAB-MAP-RUST-P1)
3. `JsonValue` tagged sum (stdlib) — outermost IO boundary only; deferred

**Closed surfaces:** `Map[String, Any]` at contract boundaries; `Unknown` as user type; `Table/DataFrame` before Stage 2 OLAPPoint; `null` as a language value; runtime-only schema validation.

**Next design work:** ✅ LAB-MAP-RUST-P1 closed (32/32 PASS; Rust lab Map[String,V] symmetry proved; map_get→Option[V]; or_else→V; OOF-MAP1/2/3 parity; C1 finding: not needed in Rust). v1 expansion (keys/values/merge/size/to_pairs/map-literal) remains closed. Named Record production promotion (PROP-004 amendment). JSON boundary deferred. Table/DataFrame hold (Stage 2).

### Debugger / Source Map (LAB-SRCMAP)

| Artifact | Repo | Status | Checks |
|---|---|---|---|
| LAB-DEBUGGER-FEASIBILITY-P1 (feasibility report — debugger as textbook instrument; G-SRCMAP + G-TRACE gaps identified; proposed route LAB-SRCMAP-P1→P2→VMTRACE-P1→IDE-STEP-P1→TEXTBOOK-P1; no implementation authorized) | igniter-lab | ✅ DONE — feasibility report | research |
| LAB-SRCMAP-P1 (source-map substrate: stable `node_id` + source span metadata from parser → SemanticIR + `sourcemap.json` artifact; 12 node types covered; additive only; VM/bytecode/opcodes untouched; 61/61 PASS) | igniter-lab | ✅ DONE — 61/61 PASS | lab / proof |
| LAB-SRCMAP-P2 (bytecode instruction span bridge: thread `node_id` from SIR through VM compiler lowering; `bytecode-map` CLI subcommand; `bytecode_map.json` sidecar (schema_version="bytecode-map-v0"); each instruction offset carries node_id + sir_path + source_span cross-referenced from P1 sourcemap; infrastructure instructions (output LOAD_REG, RET) get null; parallel `node_id_map: Vec<Option<String>>` additive to Compiler struct; `Instruction` struct unchanged; vm.rs execute loop untouched; no new opcodes; P1 61/61 still green; P2 61/61 PASS, 8 sections: P2-COMPILE/P2-MAP-SCHEMA/P2-COVERAGE/P2-OFFSETS/P2-SOURCE/P2-STABILITY/P2-NONSEMANTIC/P2-CLOSED) | igniter-lab | ✅ DONE — 61/61 PASS | lab / proof |
| LAB-VMTRACE-P3 (loop, nested-branch, and error trace coverage hardening — LAB PROOF / TRACE COVERAGE / NO DEBUGGER; 65/65 PASS across 9 sections; adds trace fixtures `vmtrace_p3_loop.ig` + `vmtrace_p3_nested_branch.ig`; proves loop execution repeats the same proof-local loop source node without collapsing repeated offsets; exact LOOP_STEP seqs `[4,11,18,25]`; nested Green/Fast branch executed offsets `[0,1,2,3,4,5,6,9,10,11,12,13,14,15,16,17,18,19,20,21,22,31,40]`; skipped offsets `[7,8,23..30,32..39]` absent; error path status preserved with deterministic prefix to last control-flow transfer before fail-closed unsupported selected path; infra output/RET has no source attribution; trace/source_trace/view artifacts digest-identical across reruns; traced/untraced successful results equal; P1/P2/IDE-TRACE-VIEW-P1 regressions green) | igniter-lab | ✅ DONE — 65/65 PASS | lab / proof |
| LAB-IDE-TRACE-VIEW-P2 (static HTML trace viewer — LAB PROOF / STATIC VIEWER / NO DEBUGGER; 69/69 PASS across 9 sections; renders existing `source_trace.json` plus original `.ig` source into proof-local `igniter-view-engine/out/trace_view_p2/source_trace_view.html`; static HTML/CSS only with `<details>/<summary>`, anchor links, node/infra/error badges, source snippets, instruction counts, offsets, and mnemonics; loop repeated node offsets remain visible; nested branch non-contiguous offsets are explained as jump-driven execution; fail-closed trace gets an error panel and prefix timeline without inventing a successful output node; infrastructure instructions are visually distinct and source-less; renderer leaves `source_trace.json`, `vm_trace.json`, and `bytecode_map.json` digest-identical; P1 markdown view 50/50 and VMTRACE-P3 65/65 regressions green) | igniter-lab | ✅ DONE — 69/69 PASS | lab / proof |
| LAB-APP-STATE-P1 (application state / module / instance-composition design-boundary RESEARCH report — derive-from-pain, no implementation; central finding: Igniter has a state-LIFETIME vocabulary (:local/:session/:window/:durable/:audit) but NO state-HOLDER — holding is pushed outside the language and contracts are pure transforms over snapshots; the "flat application" pain = composition of {stateful facts + lifetimes + holders + public ops} is invisible in source; three missing pieces = state-instance identity, named app-fact↔holder binding, app-assembly artifact; everything else (typed values, lifecycles, effect/capability boundary, modifiers, intent) already exists & should be reused; 6-term separation enforced: value/instance/holder/transition/module/capability; 5 routes compared — A Host+Reducer, B Descriptive vocab, C Capability-handle, D Manifest .igapp, E Lifecycle-promote — + evaluation matrix; recommendation = STAGED, research-only→proof-candidate, NO keyword adopted: Stage0 Route A discipline (already true), Stage1 B⊕E hybrid prototyped proof-locally w/ ZERO compiler/parser/VM/keyword change, defer C to durable boundary + D until proof shows metadata insufficient; non-recommendations: state{} keyword (premature lock per Ch2 entrypoint/section caution), service/actor (hidden mutable identity breaks honesty/debuggability/proofability), module-as-instance (PROP-015 rejects), capability-for-all-state (fatal for hot editor state); pressure cases: code-editor (primary) + Query/Storage (non-editor: pure plan + capability boundary + KDR) + Epistemic unknown_external_state; no canon/no stable API/no runtime holder authorized; reviewed PROP-015/031/035/045 + Ch2/10/12 + debugger feasibility; next route = LAB-APP-STATE-P2 proof-local editor app-state model w/ gap packet gating any future proposal) | igniter-lab | ✅ DONE — research report | research / lang-arch |
| LAB-APP-STATE-P2 (proof-local code-editor app-state model — tests the P1 B⊕E recommendation using EXISTING Igniter concepts only, NO keyword/parser/compiler/VM change; 70/70 PASS, 9 sections COMPILE/SHAPE/LIFECYCLE/TRANSITION/PUBLIC/DURABLE/HOST/GAP/CLOSED; state-values = 11 typed records, transitions = 8 pure CORE contracts (snapshot+event)→next VM-verified incl composite ApplyEdit preserving nested records; E PATH WORKS IN-LANGUAGE — :local/:session/:window/:durable/:audit ride `output … lifecycle :x` into SIR output_ports[].lifecycle; durable save/load = effect+IO.StorageCapability / observed read-from-store with NO storage execution, split into 2nd fixture because VM rejects unbound-capability igapp load (two-fixture pattern from LAB-STORAGE-CAPABILITY-P2); holder stays host-owned, no mutable object, hot/session transitions need NO capability; six P1 terms kept separate (value/instance/holder/transition/module/capability), DocumentState reused for two distinct facts so instance≠type-name; FINDINGS: intent NOT parseable in lab toolchain (PROP-045 convention-only) so descriptive app vocabulary carried in proof-local sidecar registry editor_app_state.registry.json; modifier is partial visibility signal (separates effecting from pure, NOT pure-public-op from pure-helper); 4 P1 gaps all remain non-language but all expressible as inert sidecar metadata, none blocking — G1 instance-identity, G2 fact↔holder-binding, G3 app-assembly(event→op→fact), G4 public/internal-visibility each proven SIR-absent + sidecar-present; DECISION = A metadata-is-enough-for-now (hold proposals, document convention); smallest held future candidate = G4 visibility → LAB-MODULE-SURFACE-P1; G2→LAB-APP-STATE-P3, G3→LAB-APP-ASSEMBLY-P1 held further; NO impl files touched by this card; regressions clean P1-array 27/27 + P3 44/44; artifacts: fixtures/app_state/editor_app_state.ig + editor_app_state_durable.ig + editor_app_state.registry.json, proofs/verify_lab_app_state_p2.rb, lab-docs/lang/lab-code-editor-app-state-model-proof-local-v0.md, card LAB-APP-STATE-P2.md) | igniter-lab | ✅ DONE — 70/70 PASS | lab / proof |

**Boundary (LAB-APP-STATE-P2):** LAB PROOF / APP-STATE MODEL / NO KEYWORD — no new keyword, no `state{}`, no public/private/internal, no module instance, no service/actor/class holder, no app-manifest semantics, no storage execution, no parser/compiler/VM change (zero implementation files touched by this card), no canon/public/stable/framework API. Decision A: metadata (in-language lifecycle + inert sidecar) is enough now; hold proposals; the lab doc + registry sidecar ARE the documented convention. Next on pressure: smallest gap G4 public/internal visibility → LAB-MODULE-SURFACE-P1 (held, not opened speculatively).

**Boundary (LAB-APP-STATE-P1):** RESEARCH / DESIGN BOUNDARY only — no implementation authority, no compiler/parser/VM change, no new keyword adopted (`app_state`/`app` sketches are illustrative candidates only), no canon claim, no stable API, no runtime state-holder authorization, no public framework claim. Holder stays external by recommendation. Authorized writes were exactly three: the lab doc, this card, this portfolio. Next: LAB-APP-STATE-P2 (proof-local code-editor app-state model; B⊕E hybrid over existing lifecycle classes; no compiler/parser/VM/keyword/canon change) → its gap packet gates any proposal-authoring card.

| LAB-IGV-TAILMIX-P1 (Tailmix-on-Igniter view-runtime DESIGN BOUNDARY — RESEARCH / DESIGN / NO IMPLEMENTATION; fixes the view+interaction architecture for a Tauri IDE-for-Igniter-written-in-Igniter (fractal dogfooding, NOT a bootstrap paradox), mostly CRUD/forms + bounded interactivity, STATIC build-time component set; 10 locked decisions; KEY: D1 NO client-side VM — Tauri backend runs the canonical native Rust igniter-vm, webview↔VM over IPC (zero new parity surface; JS-VM/WASM/SIR→JS-codegen all rejected for this target); D2 NO Ruby runtime — reimplement the IDEA of Tailmix natively on Igniter, not the gem; D3 'Tailmix-on-Igniter' = 4 parts only — .igv DSL → definition-JSON compiler → ONE tiny generic JS instruction-interpreter → dispatch escalation seam (interpreter must NOT grow into a VM); D4 three tiers owned by lifecycle — :local→Tailmix definitions (client JS), :session/:durable→Igniter contracts (Rust VM via IPC), raw text edit→host widget; DISJOINT ownership (engines never share a fact) to avoid tri-parity; D5 single seam = dispatch(event)→host→contract; D6 type-vs-instance (=G1 from LAB-APP-STATE in UI form): definition is per-TYPE content-addressed (hash like SIR source_hash), render emits per-INSTANCE binding only; D7 static set → ONE build-time definition bundle loaded once into a client registry, API `render → {html, def_refs}` (definitions NEVER inlined per render → kills the many-component redundancy bottleneck; N instances = 1 definition + N tiny bindings); D8 CLOSED/frozen :local instruction vocabulary (toggle/set/add|remove|toggle_class/set_attr|aria/show|hide/match/dispatch), fail-closed, anything beyond → dispatch to a contract; D9 definitions = inert content-addressed inspectable artifacts (node_id/srcmap debuggable), NOT authority, NO capability; D10 bounded parity (Igniter initial-render ↔ JS interpreter) via a diff-oracle (canonical side = oracle, client differentially tested); SECURITY NOTE: client :local is honesty/structure NOT enforcement — real effect/privileged/irreversible authority stays backend-side; preserves the view-engine 'no contract execution in the view runtime' boundary; CLOSED — client-VM/Ruby/new-adopted-grammar/contract-exec-in-view/vocab-growth-into-computation/compiler-parser-VM-change/client-capability-authority/canon-stable-public-framework-API; ZERO implementation files touched; next route = LAB-IGV-TAILMIX-P2 proof-local (FileTreeRow .igv → content-addressed definition JSON; render→{html,def_refs} ships instance-binding only + N→1 dedup; reference-applier oracle diff-tested vs igniter_view_runtime.js over (definition,state,event) triples; fail-closed unknown-op; dispatch→host-event; ~40-60 checks, no Tauri, no toolchain change) → IDE then drives app-state follow-ups G1 instance-identity(open buffers)/G4 visibility(command palette)/G3 assembly(event→op→fact) = LAB-APP-STATE-P3 / LAB-APP-ASSEMBLY-P1; artifacts: lab-docs/view/lab-igv-tailmix-on-igniter-view-runtime-design-boundary-v0.md + .agents/work/cards/view/LAB-IGV-TAILMIX-P1.md) | igniter-lab | ✅ DONE — design boundary | view / architecture |

**Boundary (LAB-IGV-TAILMIX-P1):** RESEARCH / DESIGN BOUNDARY only — no implementation authority, no compiler/parser/VM/runtime change, no client-side VM (JS/WASM/SIR→JS-codegen), no Ruby runtime / no Tailmix gem, no new adopted grammar (.igv + definition/render JSON shapes are illustrative candidates only), no contract execution in the view runtime, no instruction-vocabulary growth into computation (frozen, fail-closed), no client-side capability authority (honesty not security; real authority backend-side), no canon/stable/public/framework API. Decision = design-locked (D1–D10) → proof candidate. Authorized writes were exactly three: the lab doc, this card, this portfolio. Next: LAB-IGV-TAILMIX-P2 proof-local (definition + render {html,def_refs} + diff-oracle; no toolchain change) → its evidence + the IDE itself drive LAB-APP-STATE-P3 / LAB-APP-ASSEMBLY-P1.

**Boundary:** `sourcemap.json`, `bytecode_map.json`, `vm_trace.json`, `source_trace.json`, proof-rendered `source_trace_view.md`, and proof-local static `source_trace_view.html` are lab-only sidecar/derived artifacts — not stable public APIs, not canon claims, not runtime authority, and not trace schema authority. The P2 HTML viewer is explanatory/read-only: no JavaScript requirement, no live VM, no server, no Tauri IPC, no debugger semantics. The P3 loop source-node annotation is proof-local in `/tmp` compiled artifacts only; it does not change compiler/VM semantics or canon source authority. VM execution loop, opcodes, Value enum, debugger/stepper/breakpoints/watch expressions, IDE UI/Tauri/Svelte, and public trace APIs remain closed.

**Route:** LAB-SRCMAP-P1 ✅ → LAB-SRCMAP-P2 ✅ → LAB-VMTRACE-P1 ✅ → LAB-VMTRACE-P2 ✅ → LAB-IDE-TRACE-VIEW-P1 ✅ → LAB-VMTRACE-P3 ✅ → LAB-IDE-TRACE-VIEW-P2 ✅. Next exact route: **A. LAB-IDE-TRACE-VIEW-P3 static UX polish / source drilldown may open**. LAB-IDE-STEP-P1 remains closed.

---

## Proposal Queue (igniter-lang Stage 3)

| PROP | Name | Status | Notes |
|---|---|---|---|
| PROP-031 | Contract modifiers | ✅ experiment-pass | Base modifier grammar |
| PROP-032 | Assumptions block | ✅ experiment-pass (bounded) | Compiler surface only |
| PROP-033 | via profile binding | ✅ experiment-pass | profile_binding in contract_ir |
| PROP-034 | output evidence syntax | ✅ experiment-pass | OOF-M9; evidence in IR output ports |
| PROP-035 | Effect Surface / IO.Capability | ✅ experiment-pass | OOF-M2/M4/M5 |
| PROP-036 | compiler_profile_id manifest | accepted; partial-impl | CLI B1..B9 closed |
| PROP-037 | External progression svc liveness | ✅ accepted; all OOF-PR1..9 closed | ServiceLoop auth; OOF-PR6/8 + schema ownership closed 2026-06-07 |
| PROP-038 | Compiler profile contract | accepted; partial-impl | schema + validator |
| PROP-039 | Managed local recursion/loops | ✅ accepted; proposal-only | Vocabulary only; impl closed |
| PROP-040 | Profile declarations | ✅ experiment-pass | OOF-M7/M8; closes CR-003 |
| PROP-041 | T2 structural-size relation | ✅ experiment-pass (proposal authored P5; P3 proof-local 48/48) | OOF-R8/R9 canonical; production edits → P6 |
| PROP-042 | T3 numeric measure expressions | ✅ P4 planning complete | OOF-R10/R11 experiment-pass; production implementation → P5 (authorized) |
| PROP-043 | Map[K,V] Stage 1 — production live + Rust lab symmetry | ✅ P1+P2+P3+P4+P5 complete; LAB-MAP-RUST-P1 closed | OOF-MAP1/2/3 active; map_get/has_key/from_pairs/empty + or_else live; C1 fix; Record/Map bridge: map_get(response.headers,key)→Option[String]; 55/55 PASS; Rust symmetry 32/32 PASS; all regressions clean |
| PROP-044 | Kind-discriminated outcome convention + sum type requirements | ✅ P1+P2+P3+P4+P5+P6 complete | P1: KDR convention; denial-as-data; OOF-KIND1..4 reserved. P2: VariantDecl+MatchExpr EBNF; OOF-KIND1..5; SemanticIR shapes; 15 decisions. P3: parser live; 50/50 PASS. P4: TypeChecker design; 16 decisions. P5: TypeChecker+OOF-KIND1..5 ACTIVE; 75/75 PASS. P6: SemanticIR emitter live; variant_decl/variant_construct/match_node; 50/50 PASS; P7 VM dispatch requires auth |
| PROP-045 | Source-level `intent` descriptor and queryable contract purpose | ✅ P1+P2 complete | P1: keyword `intent`; bounded plain string; module+contract placement; OOF-INTENT1..4 reserved; CR-003 orthogonal; 20 decisions locked. P2: production parser+classifier+typechecker+emitter; to_h fix; OOF-INTENT3 active; 53/53 PASS; 15 decisions locked |

**Next queue:**
1. ✅ PROP-039 gate 1: loop_class_semantics_proof — 66/66 PASS (2026-06-07)
2. ✅ PROP-039 gate 3: loop_class_parser_proof — 60/60 PASS (2026-06-07)
3. ✅ DA-005: archive pass complete — 12 dirs moved, 164 unknown intact
4. ✅ PROP-039 gate 4: loop_typechecker_proof — 49/49 PASS (2026-06-07)
   OOF-L1 (for_loop non-Collection source), OOF-R2 (recursive missing decreases),
   OOF-R4 (fuel_bounded/decreases-fuel missing max_steps)
5. ✅ PROP-039 gate 5: loop_semanticir_proof — 49/49 PASS (2026-06-07)
   loop_node IR shape: loop_class, termination evidence, source_ref, item, max_steps (budgeted);
   recursive/fuel_bounded modifier in contract_ir; OOF-blocking → nil semantic_ir;
   grammar_version="loop-v0" propagates all 4 stages; contract_ref includes loop identity
6. ✅ Lab G1: Rust compiler item-variable conformance — verify_g1_canon_loop.rb PASS (2026-06-07)
   parser.rs: `loop Name item in source` accepted; classifier/typechecker/emitter/vm compiler updated
   full slice: .ig → parse → classify → typecheck → emit → assemble → bytecode → VM exec; result=100 ✓
7. ✅ Lab G2: Rust compiler recursive/fuel_bounded conformance — verify_loops.rb PASS (2026-06-07)
   parser.rs: `recursive`/`fuel_bounded` modifiers + `Decreases`/`MaxSteps` BodyDecl variants
   conformance fixture: Factorial + LoopTester + SumList all compile; LoopTester executes correctly ✓
8. ✅ PROP-039 gate 6: OOF registry review — namespace resolved, governance shim set (2026-06-07)
   Active: OOF-L1 (typechecker), OOF-R2/R4 (classifier) → experiment-pass compiler surface
   Ch13 OOF-R2/R4 (service loop) migrated to OOF-SL* (PROP-037); conflict resolved
   Lab: G1+G2 closed, verify_loops.rb PASS, conformance fixture compiles all 3 contracts
   Tracked: igniter-lang/.agents/work/gates/PROP-039-gate6-oof-registry-review.md
9. ✅ PROP-039 gate 7: canonical conformance package — spine defined (2026-06-07)
   Grammar forms (FiniteLoop/BudgetedLocalLoop/StructuralRecursion/FuelBoundedRecursion) + OOF codes
   (OOF-L1/R2/R4) + SemanticIR shapes (loop_node) + lab consumption contract + PROP-037 boundary
   Lab G1+G2 conformance status documented; future gaps: G3 (PROP-037 split), G4 (body), G5 (recur())
   Tracked: igniter-lang/.agents/work/conformance/PROP-039-managed-repetition-conformance-package-v0.md
10. ✅ Lab G3: conformance alignment pass — all three sub-tasks closed (2026-06-08)
    G3a: OOF-R2 (recursive missing decreases) + OOF-R4 (fuel_bounded/decreases-fuel missing max_steps)
         classifier.rs — 5 diagnostic cases verified (fire/suppress)
    G3b: FiniteLoop `for Name item in source { body }` — parser.rs; vm/vm.rs fuel sentinel (u64::MAX)
         full slice: parse → classify → typecheck → emit → assemble → VM exec (5+10+15=30 ✓)
    G3c: IR shape kind="loop_node" (was "loop"); loop_class, termination, source_ref, max_steps at top level
         emitter.rs + vm/compiler.rs; BudgetedLocalLoop and FiniteLoop both verified
    verify_g3_conformance.rb: 14/14 PASS
11. ✅ Canon Gate 8: loop body semantics — `lead` keyword, lead_node+compute_node IR shape, OOF-L5/L7/L8 (2026-06-08)
    `lead name: Type = expr` loop-carried binding; body scope rules; OOF-L7 (read-only item), OOF-L8 (shadow)
    loop_body_semantics_proof: 100/100 PASS
    Tracked: igniter-lang/experiments/loop_body_semantics_proof/
12. ✅ Lab G4: Rust symmetry for Gate 8 — `lead` parser, OOF-L5/L7/L8 classifier+typechecker, two-track body (2026-06-08)
    `body=[lead_node*,compute_node*]` + `item_type` in emitter.rs; `body_nodes` VM execution field preserved
    verify_g4_body_semantics.rb: 18/18 PASS (incl. non-literal OOF-L5, clean OOF-L8 fixture)
13. ✅ Canon G5: recur() call semantics — OOF-R1/R5/R6/R7, `recur_call` sub-expr in SemanticIR (2026-06-08)
    Context validation (OOF-R1), arity (OOF-R5), type (OOF-R6), single-output (OOF-R7)
    recur_call is sub-expression only — must NOT appear as top-level node
    recursive_body_proof: 100/100 PASS
    Tracked: igniter-lang/experiments/recursive_body_proof/
14. ✅ Lab G5: Rust symmetry for G5 — OOF-R1/R5/R6/R7 in typechecker.rs, `recur_call` sub-expr in emitter.rs (2026-06-08)
    recur() context-check, arity-check, type-check, single-output-check all symmetric with canon
    verify_g5_recur.rb: 18/18 PASS
15. ✅ OOF-R3 gate: syntactic variant decrease proof — canon TypeChecker gate (2026-06-08)
    classifier.rb: decreases_variant extraction; typechecker.rb: OOF-R3 per recur() site + dotted-path fail-closed
    semanticir_emitter.rb: termination.variant_check="syntactic_v0" on clean contracts
    Whitelist: variant-N, variant.tail, variant.rest. Exempt: fuel_bounded, decreases fuel.
    verify_oof_r3.rb: 33/33 PASS
16. ✅ Lab OOF-R3: Rust symmetry — classifier.rs + typechecker.rs + emitter.rs (2026-06-08)
    decreases_variant extraction; OOF-R3 per recur() site + dotted-path fail-closed; termination.variant_check in SemanticIR
    Collection.tail/rest whitelist in FieldAccess inference; syntactic_decrease + syntactic_arg_desc free functions
    verify_oof_r3.rb: 34/34 PASS
17. ✅ Lab STR-CORE: Rust text stdlib symmetry — typechecker.rs + emitter.rs (2026-06-08)
    text_arg_compatible/check_text_stdlib_call helpers; all 14 ops; canon OOF-TY0 format; stdlib.text.* IR rewrite in emitter
    P2 (LAB-STR-CORE-P2): rewrite_concat_calls pass — concat(Text,Text)→stdlib.text.concat; concat(Collection,...)→stdlib.collection.concat
    verify_str_core.rb: 29/29 PASS
18. ✅ Lab STR-CORE-P3: Text value-semantics boundary proof (2026-06-08)
    byte/rune/grapheme unit separation proven; slice SIR shapes + resolved_type verified; OOF-TY0 index/arity enforcement
    split→Collection[Text] params shape; replace/replace_all SIR fn names; regex pattern treated as literal Text
    Declared policy (runtime-gated): bounds clamp, split("","x"), replace_all overlap, byte_slice UTF-8 boundary
    verify_str_value_semantics.rb: 33/33 PASS
19. ✅ LAB-STR-UNICODE-P1: Text Unicode policy design-lock (2026-06-08)
    UTF-8 validity: Text = valid UTF-8 (Value::String(Arc<str>)); UAX #29 = grapheme authority
    No implicit normalization; exact codepoint equality; trim = Unicode Pattern_White_Space
    slice bounds: [start,end) half-open; clamp; byte_slice invalid boundary → ""; split("") undefined v0
    grapheme backend: unicode-segmentation (UAX #29); version pin via Cargo.lock; canon receipt design
20. ✅ LAB-STR-UNICODE-P2: Unicode VM runtime ops implementation (2026-06-08)
    unicode-segmentation = "1.11" in Cargo.toml (lock: 1.13.3); UnicodeSegmentation import in vm.rs
    8 functional ops: rune_length, grapheme_length, byte_slice, rune_slice, grapheme_slice, ends_with, replace, replace_all
    Qualified aliases: stdlib.text.concat, trim, contains; stdlib.collection.concat
    empty-input guards: stdlib.text.split (empty delimiter → error); replace/replace_all (empty pattern → error)
    UAX #29 proven: rune_length("éx")=3, grapheme_length("éx")=2; NFC≠NFD no normalization
    verify_unicode_text_runtime.rb: 43/43 PASS
21. ✅ LAB-STR-UNICODE-P3: handler hygiene + Unicode runtime receipt (2026-06-08)
    bare "split" handler aligned with empty-delimiter fail-closed policy (LAB-STR-UNICODE-P3 hygiene)
    before: bare split("","") → Rust default (split at every char) — silent policy bypass possible
    after: bare split("","") → runtime operational error — no bypass via legacy handler name
    unicode_runtime_receipt.json: status=lab-only-evidence; lock=1.13.3; 4 handler guards confirmed
    verify_unicode_text_runtime.rb: 41/41 PASS (UNI-DEP/RCP/HYG/ERR/LENGTH/SLICE/REPLACE/SPLIT/ALIAS/AUTH/PATH)
22. ✅ PROP-041-P3/P4/P5/P6/P7: T2 structural-size relation — full production graduation (2026-06-08)
    P3: T2TypeChecker + T2Emitter sub-classes; 28 fixtures; verify_prop041_t2.rb 48/48 PASS (T2a–T2h)
    P4: authorization review — experiment-pass accepted; formal proposal authoring opened; production edits closed
    P5: formal proposal authored — grammar surface, STDLIB_REGISTRY, trust levels, OOF-R8/R9, SIR shape, backward compat
    P6: production-edit planning — minimal diff plan authorized; P7 dispatched
    P7: production implementation — parser.rb + classifier.rb + typechecker.rb + semanticir_emitter.rb updated
        verify_prop041_t2_production.rb 48/48 PASS; verify_oof_r3.rb 33/33 PASS (OOF-R3 scope unweakened)
        OOF-R8/R9 active in production pipeline; structural_size_v1 SemanticIR shape live
    Next: LAB-TERM-T2 Rust symmetry
23. ✅ LAB-PROOF-HYGIENE-P1: proof harness timeout + process-group cleanup (2026-06-08)
    Root cause: unbounded backtick/system() calls left igniter_compiler at ~100% CPU for hours
    tools/proof_harness/bounded_command.rb: hard timeout + process-group kill (SIGTERM → SIGKILL)
    11 proof runners updated (10 in igniter-compiler/, 1 in igniter-vm/proofs/)
    Self-test: test_bounded_command.rb 11/11 PASS
    Remaining unbounded: proofs/ subdirectory, view-engine proofs → P2 candidate
    Timeout policy: EXEC=10s, CARGO=120s, PROOF_WIDE=300s (all env-configurable)
24. ✅ LAB-COMPILER-LIVENESS-P1: compiler liveness risk map + diagnostic taxonomy (2026-06-08)
    Research/design only — no compiler code changed
    Risk map: 9 stages audited; MEDIUM risk in Rust typechecker/form-resolver/emitter (stack depth, no limit)
    Proposed E-COMPILER-BUDGET / E-COMPILER-CYCLE / E-COMPILER-NONPROGRESS / E-COMPILER-INTERNAL-INVARIANT codes
    Audit receipt shape: is_source_program_fault:false + is_compiler_internal:true (distinct from OOF)
    Four-way distinction: OOF (source) / E-COMPILER (compiler) / harness timeout / runtime max_steps
    Gates: P2 (instrumentation, non-fatal) → P3 (hard limits, E-COMPILER-BUDGET) → P4 (full guard)
    Next: LAB-COMPILER-LIVENESS-P2 (instrumentation pass — start here before P3 calibration)
25. ✅ LAB-COMPILER-LIVENESS-P2: non-fatal liveness instrumentation counters (2026-06-08)
    5 instrument points: tc.infer_expr, fr.walk_expr, em.lower_expr_for_targets, em.build_pipeline, parser.parse_import
    Thread-local RAII guards (TcInferGuard etc.) — zero call-site signature changes
    Adversarial 200-term fixture: tc_infer=200, fr_walk=200, status=ok (no behavior change)
    Canonical baselines: typical depth <10; calibration window confirmed for P3 limit selection
    Receipt injected on both ok and oof paths; stderr separation confirmed; non_fatal=true
    verify_liveness_p2.rb: 25/25 PASS
26. ✅ LAB-TERM-T2-P1: PROP-041 T2 structural-size relation — Rust symmetry proof (2026-06-08)
    parser.rs: SizeRelationDecl struct; size_relations field on SourceFile; parse_size_relation_decl(); order-independent
    classifier.rs: size_relations propagation (serde skip_if_empty)
    typechecker.rs: T2RegistryEntry/T2Context/T2Kind types; stdlib_size_registry(); NUMERIC_ACCESSORS; T2 dispatch;
        OOF-R8 (missing relation) + OOF-R9 (call-site mismatch); stateless design: t2_context as local var,
        check_t2_callsite_in_expr separate method; decreases_variant_t2 + size_relation_evidence on TypedContract
    emitter.rs: structural_size_v1 termination path — decreases, variant_check, size_relation.{accessor,trust,source}
    28 fixtures; verify_t2_structural_size_relation.rb 52/52 PASS (T2A–T2I)
    Regression: verify_oof_r3.rb 34/34 PASS; verify_g5_recur.rb 18/18 PASS
    Trust model: stdlib_certified (Collection.tail/rest, compiler_builtin) / user_assumed (source = module name)
    T2 = structural evidence with trust metadata — NOT a full termination proof; lab ≠ canon authority
    Next: LAB-COMPILER-LIVENESS-P3 (hard limits + E-COMPILER-BUDGET diagnostics; use P2 data)
26. ✅ LAB-COMPILER-LIVENESS-P3: calibrated E-COMPILER-BUDGET hard limits (2026-06-08)
    Fatal budget: tc.infer_expr limit=1000, fr.walk_expr limit=1000 (5× P2 adversarial max of 200)
    Observe-only: emitter/parser counters (insufficient calibration data — P2 measured 0)
    Budget breach → status="compiler_error" + E-COMPILER-BUDGET (is_compiler_internal=true, is_source_program_fault=false)
    1100-term breach fixture confirms fail-closed at depth 1001 > limit 1000
    200-term P2 probe still accepted (depth 200 < 1000) — no regression
    Canonical fixtures: ok, breaches=[]; OOF fixtures: still oof; stdout always valid JSON
    verify_liveness_p3.rb: 38/38 PASS; verify_liveness_p2.rb: 25/25 PASS (backward compat)
    E-COMPILER-BUDGET lab-local per CR-002; no canon OOF codes; no grammar/VM/lang changes
    Next: LAB-COMPILER-LIVENESS-P4 (calibrate emitter/parser observe-only; E-COMPILER-CYCLE candidate)
27. ✅ LAB-COMPILER-LIVENESS-P4: emitter/parser calibration + E-COMPILER-CYCLE preflight (2026-06-08)
    em_lower: calibrated to 30 (30-term form expression); mirrors tc_infer; P3 budget implicitly bounds it
    em_pipeline: calibrated to 10 (9 nested filters in if_expr); bounded by source nesting depth
    parse_import: STRUCTURAL BOUND — lexer merges uppercase-dotted paths to single Ident token;
      counter always 0 (no imports) or 1 (any import); cannot exceed 1 without lexer change
    E-COMPILER-CYCLE: risk classified LOW for all passes (finite AST, no form-calls-form, no back-edges)
    compiler_error sidecar: stdout-only is correct (unreliable record worse than no record)
    All three counters confirmed observe-only (data-justified, not assumption-based)
    New fixtures: liveness_emitter_form_lower.ig, liveness_emitter_pipeline_depth.ig, liveness_parser_import_steps.ig
    verify_liveness_p4.rb: 40/40 PASS; verify_liveness_p3.rb: 38/38 PASS; verify_liveness_p2.rb: 25/25 PASS
    Next: LAB-COMPILER-LIVENESS-P5 if: form-calls-form grammar change, production corpus data, or E-COMPILER-BUDGET PROP
28. ✅ LAB-COMPILER-LIVENESS-P5: parser non-progress and subprocess timeout hardening (2026-06-09)
    Root cause: peek_type returned false for Eof when current()=None (past EOF sentinel); all while!peek_type(Eof) loops hung
    Fix 1 (parser.rs): peek_type returns true for Eof when current()=None — single-function, zero semantic change
    Fix 2 (parser.rs): parse_body_decl_with_recovery wraps output/compute — on Err: advance, emit OOF-P1, skip to boundary
    Fix 3 (parser.rs): parse_type_decl field loop — explicit match-on-Err for name/colon/type; OOF-P1 per bad field
    BoundedCommand (verify_liveness_p5.rb): Process.spawn + killer thread (SIGTERM then SIGKILL); 15s default timeout
    Process invariant: pgrep count unchanged before/after 5 malformed compiles (P5-I)
    stdout bounded: all malformed inputs < 1KB, well-formed < 64KB cap; all valid JSON (P5-J)
    New fixtures: 5 malformed hang fixtures + 1 well-formed regression guard
    verify_liveness_p5.rb: 46/46 PASS; verify_liveness_p4.rb: 40/40 PASS (backward compat)
    No new OOF codes, no language semantics change, no canon impact, no runtime/VM change
    Next: extend parse_body_decl_with_recovery to all body-decl keywords; BoundedCommand for VM runner
29. ✅ LAB-COMPILER-LIVENESS-P6: body-declaration recovery generalisation (2026-06-09)
    Audit finding: name_token()/expect_type() ALWAYS advance unconditionally — even on error
    Migration: 11 .ok() arms → parse_body_decl_with_recovery (input, capability, effect, read, snapshot, escape, stream, fold_stream, invariant, lead, max_steps)
    Deferred to P7: window/loop/for — have inner {} blocks; skip_until_body_boundary stops at inner }, not contract }
    decreases arm: always returns Ok — .ok() is semantic no-op; documented and left unchanged
    Token-progress guarantee: all 19 arms either recover, always succeed, or fall to _ => advance
    Fixture discovery: use IntLit (42) after keywords to get independent failures without consuming next keyword
    verify_liveness_p6.rb: 54/54 PASS; verify_liveness_p5.rb: 46/46 PASS (backward compat)
    No new OOF codes; no language semantics change; no canon impact
    Next P7: skip_to_matching_brace for window/loop/for; consider peek-before-advance for expect_type
30. ✅ LAB-TERM-T2-P2: OOF-R9 branch and multi-recur edge hardening (2026-06-08)
    Root cause: check_t2_callsite_in_expr IfExpr arm only walked cond, not then/else_block bodies
    Fix: extended IfExpr arm to mirror check_recur_in_expr exactly (stmts + return_expr for both branches)
    5 new fixtures: multi_recur_both_correct, multi_recur_one_wrong, if_both_branches_correct,
      if_wrong_else_branch, nested_arith_wrong
    Proven: mixed correct/wrong fails closed; correct site does NOT suppress wrong-site OOF-R9
    OOF-R3/R8 precedence unchanged; T1 syntactic_v0 unaffected; no new OOF codes; no canon changes
    verify_t2_oof_r9_edge_cases.rb: 21/21 PASS
    Regression: verify_t2_structural_size_relation.rb 52/52; verify_oof_r3.rb 34/34; verify_g5_recur.rb 18/18
    LAB-TERM-T2 track complete (P1+P2). Next: PROP-042 T3 numeric measure proposal.
29. ✅ PROP-042-P1: T3 numeric measure expressions — formal proposal authored (2026-06-09)
    Depends on: PROP-041-T3-P1 design lock (CLOSED)
    Grammar: `decreases count(items)` function-call form; dispatch branch new (not T1/T2)
    NUMERIC_MEASURE_BUILTINS v0: count(Collection[T]) only; stdlib_numeric_certified trust; compiler_builtin source
    NUMERIC_ACCESSORS (T2) unchanged — T3 opens function-call path only, not dotted path
    OOF-R10 (unrecognized measure fn) + OOF-R11 (decrease obligation not met) — candidates until P2 gate
    SemanticIR: variant_check="numeric_measure_v0", numeric_measure.{fn, arg, trust, source}
    Call-site obligation: T2 structural coverage → numeric decrease implied (T2 registry reused)
    Backward compat: T1/T2 unchanged; T3-unaware compiler may emit OOF-R3 (conformance allowance)
    Proposal: igniter-lang/.agents/work/proposals/PROP-042-t3-numeric-measure-expressions-v0.md
    Card: igniter-lang/.agents/work/cards/lang/PROP-042-P1.md
    Deferred: Text length measures, user-defined measures, size/length aliases, count(x)-1 (T4)
    Next: PROP-042-P2 proof-local experiment gate (≥19 fixtures, T3a–T3i)
30. ✅ LAB-DYNAMIC-DATA-P1: dynamic data structure taxonomy + boundary research (2026-06-09)
    Scope: JSON / Map / Record / Collection / Table / Unknown — research only, no grammar/compiler changes
    Finding 1: Named Record covers ~80% of near-term needs (JobReceipt, RackResponse, HttpRequest proven)
    Finding 2: Map[String,String] is the most urgent unproven gap — Rack headers deferred since P12
    Finding 3: JSON stays boundary format only; JsonValue deferred until concrete IO boundary use case proven
    Finding 4: Table/DataFrame → Stage 2 OLAPPoint (PROP-024); no Stage 1 mechanism
    Finding 5: Unknown is compiler-internal state; not a dynamic type; Map[String,Any] permanently closed
    Taxonomy: Named Record > Map[K,V] > JsonValue (three tiers); all other combos closed
    Next: PROP-043 Map[K,V] design lock (immediate); Named Record production promotion; JSON boundary deferred; Table hold
    Docs: igniter-lab/lab-docs/lang/lab-dynamic-data-structures-json-map-table-research-boundary-v0.md
    Card: igniter-lang/.agents/work/cards/lang/LAB-DYNAMIC-DATA-P1.md
31. ✅ PROP-043-P1: Map[K,V] Stage 1 design lock (2026-06-09)
    Depends on: LAB-DYNAMIC-DATA-P1, LAB-RACK-P12/P13, LAB-SIDEKIQ-P4
    15 decisions locked: String-only keys (v0); no literal syntax (deferred MapLit to v1); from_pairs construction;
        Option[V] lookup always; Map≠Record design law; JSON stays closed; no new SemanticIR node kind (v0)
    v0 stdlib: stdlib.map.get → Option[V]; stdlib.map.has_key → Bool; stdlib.map.from_pairs; stdlib.map.empty
    v1 deferred: with_entry, keys, values, size, merge, to_pairs
    Diagnostics (candidates): OOF-MAP1 (K≠String), OOF-MAP2 (Map[K,Any]), OOF-MAP3 (Unknown annotation)
    P2 fixture matrix: MAP-A (annotations) + MAP-B (key restriction OOFs) + MAP-C (get/has_key) +
        MAP-D (FullRackResponse+headers) + MAP-E (SemanticIR shapes) + MAP-F (regression) = ≥18 checks
    Proposal: igniter-lang/.agents/work/proposals/PROP-043-map-kv-stage1-v0.md
    Card: igniter-lang/.agents/work/cards/lang/PROP-043-P1.md
32. ✅ PROP-043-P2: Map[K,V] proof-local experiment (2026-06-09)
    Depends on: PROP-043-P1, LAB-DYNAMIC-DATA-P1, LAB-RACK-P13, LAB-RECORD-VM-P1
    MapPipeline: MapTypeChecker < IgniterLang::TypeChecker; @output_type_hints pre-scan; no production edits
    15 fixtures: MAP-A (3 valid annotations) + MAP-B (3 OOF candidates) + MAP-C (3 stdlib lookups) +
        MAP-D (4 Rack pressure) + MAP-F (2 regression/boundary) = 15 fixture files
    Type rules proven: map_get(Map[String,V], String)→Option[V]; or_else(Option[V],V)→V; has_key→Bool;
        from_pairs(Collection[HeaderPair])→Map[String,String] via @type_shapes[elem]["value"] field
    FullRackResponse {headers: Map[String,String]}: record literal resolved correctly via output_type_hints
    OOF-MAP1/2/3 candidates proven; OOF-MAP3 output-only behavior confirmed
    JSON, Any, mutation, real TCP all remain closed; no SemanticIR kind added
    verify_prop043_map.rb: 42/42 PASS (MAP-A 7 + MAP-B 8 + MAP-C 7 + MAP-D 9 + MAP-E 5 + MAP-F 6)
    Card: igniter-lang/.agents/work/cards/lang/PROP-043-P2.md
33. ✅ PROP-043-P3: Map[K,V] acceptance decision (2026-06-09)
    Depends on: PROP-043-P2
    Decision: P2 accepted (proof-local experiment-pass); OOF-MAP1/2/3 elevated candidate→experiment-pass
    Map[String,V] v0 surface accepted: map_get/has_key/from_pairs all accepted; map_empty conditional (C2)
    5 named caveats evaluated: C1 (param strip, P4 item), C2 (map_empty usable scope, P4 item),
        C3 (short names, confirmed design), C4 (subclass arch, standard), C5 (OOF-MAP3 output-only, confirmed correct)
    P2 does NOT authorize production implementation; P4 production-edit planning authorized
    9 P4-Q items scoped: TypeChecker integration, @output_type_hints, param unification, or_else, map_empty scope,
        from_pairs fallback, SIR emitter confirm, regression matrix, OOF message wording
    Track: igniter-lang/.agents/work/tracks/prop043-map-kv-proof-local-acceptance-decision-v0.md
    Card: igniter-lang/.agents/work/cards/lang/PROP-043-P3.md
    Next: PROP-043-P4 production-edit planning (no production file edits; planning only)
35. ✅ PROP-043-P5: Map[K,V] production implementation + Record/Map bridge (2026-06-09)
    Track: map-kv-production-implementation-with-record-bridge-v0
    Depends on: PROP-043-P4, LAB-RECORD-MAP-P1
    classifier.rb: 1-line C1 fix (line 52: normalize_type → normalized_type_annotation for field annotations)
    typechecker.rb: MAP_STDLIB_FNS constant; @output_type_hints pre-scan; OOF-MAP annotation scan;
        array_literal/record_literal arms in infer_expr; MAP dispatch + or_else in infer_call;
        14 new private methods (infer_map_call, infer_map_get, infer_map_has_key, infer_map_from_pairs,
        infer_from_pairs_value_type, infer_map_empty, infer_or_else, infer_array_literal,
        infer_record_literal, check_map_annotation, param_type_name, map_type_ir, option_type_ir,
        collection_type_ir_from); 1-line type_shapes C1 fix (line 118)
    No parser/emitter/VM changes (confirmed)
    Bridge fixture: map_d_header_record_bridge.ig (ContentTypeFromResponse + HeaderPresenceCheck)
    Production verify: verify_prop043_map_production.rb 55/55 PASS
        MAP-A 7/7 (annotation acceptance + C1 param preservation)
        MAP-B 8/8 (OOF-MAP1/2/3 isolation)
        MAP-C 7/7 (map_get/or_else/has_key type rules)
        MAP-D 9/9 (FullRackResponse headers C1 end-to-end)
        MAP-E 5/5 (SemanticIR fn names + resolved_type)
        MAP-F 11/11 (regressions + closed surfaces + production-specific C1/C2/v1 checks)
        MAP-BRIDGE 8/8 (map_get(response.headers,key)→Option[String]; or_else→String; C1 closes gap)
    Record/Map bridge key finding: C1 fix makes @type_shapes["FullRackResponse"]["headers"]=Map[String,String];
        field access returns Map[String,String] (not Map no-params); map_get→Option[String] (not Option[Unknown])
    Regressions: verify_oof_r3.rb 33/33; verify_prop041_t2_production.rb 48/48;
        verify_prop042_t3_production.rb 45/45; verify_prop043_map.rb (proof-local) 42/42
    Next: Lab-Map-Rust-P1 (Rust lab Map[String,V] symmetry — unblocked by P5 graduation)
36. ✅ LAB-SIDEKIQ-P5: Sidekiq upstream HTTP result composition with Map[String,String] metadata (2026-06-09)
    Track: lab-sidekiq-upstream-http-result-retry-composition-proof-v0
    Depends on: PROP-043-P5, LAB-SIDEKIQ-P4, LAB-STDLIB-NET-P8/P9, LAB-MAP-RUST-P1, LAB-RECORD-MAP-P1
    Fixture: upstream_http_result_composition.ig — 5 types (HttpResult, ContractResult, JobInput, JobReceipt, RetryEnvelope)
    Contracts: MetadataReader, SuccessPath, DeniedPath, RetryablePath, ExhaustedPath
    Layer A (Ruby TypeChecker): map_get(job.metadata,"worker")→Option[String]; or_else→String (C1 fix end-to-end);
        record literal { ..., metadata: job.metadata, ... } → JobReceipt / RetryEnvelope via @output_type_hints;
        next_attempt = job.attempt + 1 → Integer (infer_binary field_access + literal); all 5 contracts accepted
    Layer B (UpstreamCompositionP5 simulation): BudgetedLocalLoop analog; success/denied/retry/exhausted;
        [error,error,found] → receipt.attempt=3; metadata passthrough (object identity); map_get+or_else behavioral
    SJOB5-TYPES/MAP/SUCCESS/DENIED/RETRY/EXHAUSTED/SIM/REG/CLOSED/GAP: 48/48 PASS
    Zero type_errors across all 5 fixture contracts
    No production file changes; proof-local + igniter-lang production TypeChecker used read-only
    Key finding: C1 fix chains through: @type_shapes["JobInput"]["metadata"]=Map[String,String] →
        job.metadata field_access → Map[String,String] → map_get → Option[String] (not Unknown)
    All 4 job paths with Map[String,String] metadata proved; BudgetedLocalLoop retry behavior proved

37. ✅ LAB-RESULT-ENVELOPE-P1: Contract result envelope taxonomy and promotion boundary (2026-06-09)
    Category: governance / Track: lab-contract-result-envelope-taxonomy-and-promotion-boundary-v0
    Route: DESIGN / GOVERNANCE / LAB-ONLY — analysis only; no code, no production changes
    Source: NET-P8/P9 + RACK-P14 + SIDEKIQ-P5 + RECORD-VM-P1/P2/P3 + PROP-043-P5

    Five confirmed reusable patterns (Category A):
      denial-as-data:       6-proof corpus (P6/P7/P8/P9/P14/P5) — strongest invariant; design law candidate
                            Every consumer handles capability denial as typed data; no exception/raise anywhere
      kind-discriminant:    HttpResult (3 values) + ContractResult (6 values); de facto lab convention
                            for typed unions; not yet syntax-supported (no sum types in grammar)
      budget-loop:          attempt+max_attempts in P8 RetryEnvelope + P5 RetryEnvelope + P5 JobReceipt
                            PROP-039 BudgetedLocalLoop confirmed as the right abstraction
      Map[String,String]:   PROP-043-P5 already production; headers (transport) + metadata (job) both use same shape
      three-layer:          HttpResult → ContractResult → consumer; appeared independently in P14 + P5

    Domain-local (stay classified):
      HttpResult:            NETWORK-LOCAL — 3-variant; `denied` HTTP-specific; transport internals
      ContractResult:        HTTP-DOMAIN-LOCAL — name too generic; 6-kind HTTP-bound; recommend future rename
      FullRackResponse:      RACK-LOCAL — integer HTTP status; Rack-only consumer
      JobReceipt:            SIDEKIQ-LOCAL — job_class/job_id Sidekiq-specific
      RetryEnvelope (P8/P5): INCOMPATIBLE SHAPES — P8 embeds HttpResult; P5 is re-enqueue instruction; don't unify

    No canon proposals authorized. Primary blockers: ~~VM map_get bytecode~~ → ✅ closed; ~~only 2 domains~~ → ✅ 3 domains (P2); ~~proposal-authoring~~ → ✅ PROP-044-P1 authored; ~~grammar design~~ → ✅ PROP-044-P2 authored; parser implementation (P3) requires explicit authorization
    Next authorized routes:
      ✅ immediate: LAB-VM-MAP-P1 CLOSED (48/48 PASS)
      ✅ next: LAB-RESULT-ENVELOPE-P2 CLOSED (50/50 PASS — 3rd domain; PROP-044 unblocked for authoring)
      ✅ next: PROP-044-P1 CLOSED (convention doc authored; grammar gap enumerated; OOF-KIND1..4 reserved)
      ✅ next: PROP-044-P2 CLOSED (VariantDecl+MatchExpr EBNF; OOF-KIND1..5; SemanticIR shapes; 15 decisions)
      ✅ next: PROP-044-P3 CLOSED (50/50 PASS — fat_arrow; 6 parse methods; grammar_version=variant-v0)
      ✅ next: PROP-044-P4 CLOSED (TypeChecker design — @variant_shapes; classifier bridge; OOF-KIND1..5; 16 decisions)
      ✅ next: PROP-044-P5 CLOSED (75/75 PASS — OOF-KIND1..5 ACTIVE; infer_variant_construct; infer_match_expr; regressions clean)
      ✅ next: PROP-044-P6 CLOSED (50/50 PASS — SemanticIR emitter live; variant_decl/variant_construct/match_node)
      next (explicit auth required): PROP-044-P7 VM variant dispatch

38. ✅ LAB-VM-MAP-P1: VM runtime map_get/map_has_key/or_else over Map[String,String] (2026-06-09)
    Category: lang / vm / Track: lab-vm-map-ops-runtime-proof-v0
    Route: LAB / VM / IMPLEMENTATION
    Depends on: LAB-RESULT-ENVELOPE-P1 (identified blocker), LAB-RACK-P14 (gap source), LAB-SIDEKIQ-P5,
                LAB-MAP-RUST-P1 (TypeChecker proofs), LAB-RECORD-VM-P2 (OP_GET_FIELD base)
    vm.rs: map_get("map_get"|"stdlib.map.get") handler — (Value::Record, String) → Nil|raw value
           map_has_key("map_has_key"|"stdlib.map.has_key") handler — (Value::Record, String) → Bool
           or_else was pre-existing — already handled Nil→fallback + non-Nil→identity correctly
    compiler.rs: input field access fix — OP_LOAD_REF("a.b") → OP_LOAD_REF("a")+OP_GET_FIELD("b")
                 enables MetadataReader and all contracts with nested input field access
    Map runtime: Value::Record(BTreeMap<String,Value>) — no new Value variant needed
    Option: None=Value::Nil, Some(v)=raw v — consistent with pre-existing or_else
    SIR names: bare "map_get" (emitter does not qualify map names unlike stdlib.text.*)
    Fixture: 7 contracts (MapGetHit/Miss, OrElseHit/Miss, HasKeyHit/Miss, HeaderChain)
    Rack P14: HeadersAwareHandler 9/10 → 10/10 VM-executable — LAB-RESULT-ENVELOPE-P1 blocker #2 closed
    Sidekiq P5: MetadataReader executes end-to-end in VM (queue present → value, absent → "default")
    Closed: mutation (map_set/map_delete), non-String keys, map literals, broad API (keys/values/size),
            JSON/JsonValue semantics, stable runtime API claim, canon authority
    verify_lab_vm_map_p1.rb: 48/48 PASS
      VMAP-COMPILE 4/4 | VMAP-TYPES 5/5 | VMAP-GET 6/6 | VMAP-HAS 4/4 | VMAP-OR 6/6 |
      VMAP-BRIDGE 4/4 | VMAP-RACK 4/4 | VMAP-SIDEKIQ 4/4 | VMAP-CLOSED 5/5 | VMAP-GAP 6/6

42. ✅ PROP-044-P2: variant+match grammar design (2026-06-09)
    Category: lang / Track: variant-and-exhaustive-match-design-v0
    Route: PROPOSAL / GRAMMAR DESIGN ONLY
    Depends on: PROP-044-P1, PROP-004 (ch3 type grammar), PROP-026 (parser OOF hardening)
    Grammar designed (no implementation):
      VariantDecl: new TopDecl form — "variant" Name "{" VariantArm+ "}"
        VariantArm: Name ("{" ArmField* "}")? — unit arms and record arms both supported
        Parse AST: { kind: "variant", name, arms: [{ name, fields: [{name, type_annotation}] }] }
      VariantConstruct: PascalCase-ident + "{" in parse_primary → { kind: "variant_construct", arm, fields }
      MatchExpr: new parse_primary form — "match" Expr "{" MatchArm+ "}"
        MatchArm: ArmPattern "{" Bindings "}" "=>" Expr | "_" "=>" Expr
        Parse AST: { kind: "match_expr", subject, arms: [{ pattern: {arm, bindings}, body }] }
      Type narrowing: per-arm binding scope; arm field types from variant declaration
      v0 restrictions: subject = ref or field-access only; no guards; no nested match
    OOF-KIND codes (formal definitions — candidates, not active):
      OOF-KIND1: non-exhaustive match (typechecker, error) — missing arm, no wildcard
      OOF-KIND2: arm/binding not in variant (classifier+typechecker, error)
      OOF-KIND3: unreachable arm (typechecker, warning) — wildcard before last, duplicate
      OOF-KIND4: match subject not a variant type (typechecker, error)
      OOF-KIND5: arm result types do not unify (typechecker, error) — new in P2
    SemanticIR shapes (design only): variant_decl (in variant_defs); variant_construct (expr);
      match_node (expr; exhaustive flag; per-arm bindings+resolved_types)
    Parser extension points: 4 sites identified (TopDecl dispatch; parse_primary kw branch;
      parse_primary ident/PascalCase branch; keyword table)
    Typechecker extension points: @variant_shapes store; check_variant_decl;
      infer_variant_construct; infer_match_expr
    15 design decisions locked (D1..D15)
    Closed: parser impl (P3 req. auth); typechecker (P4); emitter (P5); VM (P6);
            OOF activation; Option match; stable API
    Design doc: igniter-lang/.agents/work/proposals/PROP-044-variant-and-exhaustive-match-design-v0.md
    Card: igniter-lang/.agents/work/cards/lang/PROP-044-P2.md

44. ✅ PROP-045-P1: Source-level intent descriptor and queryable contract purpose (2026-06-09)
    Category: lang / Track: source-intent-descriptor-and-queryable-contract-purpose-v0
    Route: PROPOSAL AUTHORING ONLY
    Depends on: language-covenant.md (Axiom 1/2, Postulate 7), PROP-033, PROP-040, PROP-044-P1, LAB-RESULT-ENVELOPE-P2, LAB-QUERY-P1
    Design (no implementation):
      Keyword: `intent` — not `description` (conflicts with PROP-040 profile field); not `purpose`/`about`/`summary`
      Shape: bounded plain string (500-char advisory limit); no structured fields in v0; no interpolation
      Placement v0: module/file level (after ModuleDecl) + contract body (BodyDecl)
      Placement v1 (deferred): type decls, output/input decls, trait/impl blocks
      Required: optional in v0; mandatory deferred to later PROP
      Behavior digest: NOT included — intent is metadata only
      Source/docs digest: YES — intent_text in contract_ir and module metadata
      Behavioral compatibility: NONE — intent changes are metadata-only; not a breaking change
    CR-003 relationship: ORTHOGONAL — CR-003/PROP-040 covers profile_binding (which profile to bind);
      PROP-045 covers purpose metadata (what the contract does). Different surfaces.
    OOF-INTENT codes (candidates, not active): OOF-INTENT1 (too long), OOF-INTENT2 (secret pattern),
      OOF-INTENT3 (duplicate — error), OOF-INTENT4 (unsupported site)
    Authority: NEVER confers capability/policy/runtime authority
    P2 recommendation: parser implementation (explicit auth required); complexity: low
    20 design decisions locked
    Proposal: igniter-lang/.agents/work/proposals/PROP-045-source-intent-descriptor-and-queryable-contract-purpose-v0.md
    Card: igniter-lang/.agents/work/cards/lang/PROP-045-P1.md

44b. ✅ PROP-045-P2: Source-level intent descriptor — parser + metadata propagation proof (2026-06-10)
    Category: lang / Track: source-intent-descriptor-parser-and-metadata-proof-v0
    Route: PARSER / METADATA PROPAGATION PROOF
    Depends on: PROP-045-P1, PROP-033/040 (profile_binding precedent)
    Production changes:
      parser.rb: `intent` keyword; module-level parse (after module, before imports);
        `parse_intent_decl` method; `parse_body_decl` dispatch arm; `ParsedProgram#to_h` intent_text fix
      classifier.rb: intent body node → no symbol; OOF-INTENT3 on duplicate; contract + module intent_text propagation
      typechecker.rb: contract + module intent_text pass-through
      semanticir_emitter.rb: intent_text in typed_contract_ir + typed_semantic_ir_program
    Key fix: `ParsedProgram#to_h` was missing `intent_text` — AST had the value; to_h did not emit it
    OOF-INTENT3: NOW ACTIVE — fires in classifier; first intent kept; fragment_class → oof
    Proved: intent_text present in contract_ir when declared; absent when not; orthogonal to profile_binding;
      no fragment_class change; no type_errors; no compute node injection; no capability authority
    53/53 PASS (8+8+6+8+6+6+5+6 across 8 sections)
    Proof runner: igniter-lang/experiments/intent_descriptor_proof/intent_descriptor_proof.rb
    Card: igniter-lang/.agents/work/cards/lang/PROP-045-P2.md
    Closed: OOF-INTENT1/2/4 (not active); behavior digest inclusion; mandatory enforcement;
            type/output/field-level intent; stable query API; secret detection

45. ✅ LAB-STORAGE-CAPABILITY-P1: IO.StorageCapability query execution boundary design (2026-06-09)
    Category: lang / Track: lab-storage-capability-query-execution-boundary-design-v0
    Route: DESIGN / LAB-ONLY (no proof runner; design-locked)
    Depends on: PROP-035, LAB-QUERY-P1, LAB-QUERY-P2, LAB-CONCURRENCY-P4
    IO.StorageCapability schema (v0):
      allowed_sources: [String]   -- table names; empty = deny all (fail-closed)
      allowed_ops:     [String]   -- ["read"] in v0; "write" deferred
      row_limit:       Integer    -- clamp safety cap; 0 = deny all rows
      allow_include_all: Bool     -- false = G5 query_error on SELECT * plans
      read_allowed:    Bool       -- master read gate
      write_allowed:   Bool       -- always false in v0
      deny_reason:     String     -- surfaced in QueryResult.message
    Structural parallel to NetworkCapability: allowed_hosts→allowed_sources; connect_allowed→read_allowed; listen_allowed→write_allowed
    Denial-as-data gate sequence (6 gates, fail-closed, short-circuit):
      G1: source in allowed_sources? NO → denied
      G2: "read" in allowed_ops?    NO → denied
      G3: read_allowed==true?        NO → denied
      G4: plan.limit > row_limit?    YES → clamp (no denial); receipt records row_limit_clamped
      G5: include_all + !allow_include_all? → query_error (plan-formation error; not denial)
      G6: execute (mocked in v0) → rows/empty/system_error
    QueryExecutionReceipt: cap_id/plan_kind/source_table/op_requested/cap_checked/cap_granted/
      denial_gate/deny_reason/plan_limit/row_limit_cap/effective_limit/row_limit_clamped/
      rows_returned/result_kind/metadata — evidence only; does not re-authorize
    Future ExecuteQuery form (requires PROP-035 grammar):
      effect contract ExecuteQuery { capability storage: IO.StorageCapability; effect read_from_storage using storage; input plan:QueryPlan; output result:QueryResult }
    Fragment classification: plan-building=CORE (LAB-QUERY-P2); ExecuteQuery=ESCAPE→STORAGE (Stage 2+)
    OOF-STORE candidates (not active): OOF-STORE1 (dynamic source name — high); OOF-STORE2 (write on read-only — high); OOF-STORE3 (source not in list — medium); OOF-STORE4 (include_all on restricted cap — medium); OOF-STORE5 (row_limit:0 misconfig — low)
    10 design decisions locked (D1..D10)
    Permanently closed: real DB/SQL/ORM/ActiveRecord/migrations/transactions/persistence runtime
    Deferred: write ops (v1); JOINs/aggregates (v1); delegation algebra (v1); STORAGE fragment class (Stage 2+)
    ✅ Next: LAB-QUERY-P3 CLOSED (44/44 PASS — nested QuerySource/Projection/FilterPredicate/OrderBy; Collection[FilterPredicate]; chained field access; C1 chain; denial-as-data)
    ✅ Next: PROP-046-P1 CLOSED (proposal authored — 14 sections; 15 decisions; IO.StorageCapability boundary; ExecuteQuery ESCAPE→STORAGE; TBackend⊥StorageCapability)
    ✅ Next: LAB-STORAGE-CAPABILITY-P2 CLOSED (51/51 PASS — 6-gate denial sequence; row-limit clamp; include_all→query_error; denial-as-data 9th proof; QueryExecutionReceipt 15-field record; ESCAPE class enforcement confirmed; two-fixture architecture for effect+pure separation)
    Next authorized: LAB-EXECUTE-QUERY-P1 (Stage 2+ execution proof; capability injection); LAB-TC-ARRAY-P1 (Rust typechecker array_literal)
    Design doc: igniter-lab/lab-docs/lang/lab-storage-capability-query-execution-boundary-design-v0.md
    Card: igniter-lab/.agents/work/cards/lang/LAB-STORAGE-CAPABILITY-P1.md

46. ✅ LAB-QUERY-P3: QueryPlan v1 nested records + Collection[FilterPredicate] proof (2026-06-10)
    Category: lang / Track: lab-query-plan-nested-records-and-filter-collection-proof-v0
    Route: EXPERIMENTAL / LAB-ONLY
    Depends on: LAB-QUERY-P1, LAB-QUERY-P2, LAB-STORAGE-CAPABILITY-P1, LAB-RECORD-VM-P3, PROP-043-P5, LAB-VM-MAP-P1
    QueryPlan v1 shape (7 types):
      QuerySource { table:String, schema:String }
      Projection { fields:String, include_all:Bool }
      FilterPredicate { field:String, op:String, value:String }
      OrderBy { field:String, direction:String }
      QueryPlan { kind:String, source:QuerySource, projection:Projection, filters:Collection[FilterPredicate], order:OrderBy, limit:Integer, metadata:Map[String,String] }
      QueryResult { kind:String, count:Integer, message:String, metadata:Map[String,String] }
      StorageDenied { table:String, op:String, reason:String, kind:String }
    8 contracts: BuildFilterPredicate + BuildOrderBy + BuildProjection + BuildQuerySource + BuildRichSelectPlan + PlanNestedFieldReader + PlanMetadataReader + QueryResultDenied
    Key findings:
      B1 — Rust typechecker array_literal gap: [f1,f2] accepted Layer A (Ruby TC); blocked Layer B (Rust _ => catch-all); Collection[FilterPredicate] as input accepted both layers; candidate: LAB-TC-ARRAY-P1
      B2 — Chained field access plan.source.table: two-hop OP_GET_FIELD via LAB-RECORD-VM-P3 recursive compile_expr fix; confirmed on richer QueryPlan shape
      B3 — C1 chain portable: map_get(plan.metadata,key)+or_else on QueryPlan v1; chain is domain-shape-independent (4th domain)
      B4 — Denial-as-data 8th proof: QueryResult{kind:"denied"} constructed cleanly; no exception/raise; 4th domain
    Layer A: Ruby TypeChecker — 8/8 accepted; 0 type_errors; Collection[FilterPredicate] type env correct
    Layer B: Rust compiler + VM — 8/8 contracts compiled; all VM runs succeed; nested records preserved
    Layer C: QueryExecutorSim — 5-kind routing; denial-as-data; "empty" ≠ "denied" ≠ "query_error"
    All contracts pure CORE; no SQL; no DB; no ORM; no StorageCapability execution; no stable API
    ✅ Next: LAB-STORAGE-CAPABILITY-P2 CLOSED (51/51 PASS — 6-gate denial sequence; QueryExecutionReceipt 15 fields; denial-as-data 9th proof; ESCAPE class confirmed)
    Next authorized: LAB-TC-ARRAY-P1; LAB-EXECUTE-QUERY-P1; LAB-FILTER-EVAL-P1
    verify_lab_query_p3.rb: 44/44 PASS
      QPLAN3-COMPILE 4/4 | QPLAN3-TYPES 6/6 | QPLAN3-NESTED 5/5 | QPLAN3-BUILD 4/4 |
      QPLAN3-ARRAY 4/4 | QPLAN3-VM 8/8 | QPLAN3-CHAIN 4/4 | QPLAN3-KDR 4/4 | QPLAN3-CLOSED 5/5
    Doc: igniter-lab/lab-docs/lang/lab-query-plan-nested-records-and-filter-collection-proof-v0.md
    Card: igniter-lab/.agents/work/cards/lang/LAB-QUERY-P3.md

51. ✅ LAB-EXECUTE-QUERY-P1: ExecuteQuery effect contract and StorageCapability injection proof (2026-06-10)
    Category: lang / Track: lab-execute-query-effect-contract-and-storage-capability-injection-v0
    Route: LAB PROOF / STAGE 2+ / MOCKED STORAGE EXECUTION / NO REAL DB
    Depends on: LAB-QUERY-P3, LAB-STORAGE-CAPABILITY-P1, LAB-STORAGE-CAPABILITY-P2, LAB-TC-ARRAY-P2, PROP-035, PROP-046-P1
    Two-fixture architecture (B1 resolution — same pattern as LAB-STORAGE-CAPABILITY-P2):
      execute_query_capability.ig — effect contract + 4 pure contracts (Layer A + Layer B compile)
      execute_query_receipts.ig  — 12 pure contracts only (Layer B VM execution; Rust SIR type checks)
    Types proved: QuerySource/Projection/FilterPredicate/OrderBy/QueryPlan/QueryResult/QueryExecutionReceipt (15 fields)/StorageCapability (8 fields)
    17 contracts total: ExecuteQuery (effect, compile-only) + ReadPlanSource + ReadPlanProjection + BuildDeniedResult + ReadPlanMeta + BuildStorageCapability + BuildQueryPlanInline + ExecuteQueryRows + ExecuteQueryEmpty + ExecuteQueryDeniedSource + ExecuteQueryQueryError + ExecuteQuerySystemError + BuildAllowedReceipt + BuildDeniedGateReceipt + BuildClampedReceipt + QueryReceiptReader + QueryMetadataChain
    6-gate denial sequence proved (Layer C ExecuteQuerySim):
      G1: plan.source.table not in cap.allowed_sources → "denied"
      G2: "read" not in cap.allowed_ops → "denied"
      G3: cap.read_allowed==false → "denied"
      G4: plan.limit > cap.row_limit → CLAMP (not denial); row_limit_clamped:true; cap_granted:true
      G5: include_all + !allow_include_all → "query_error" (not "denied")
      G6: mocked execute → "rows"/"empty"/"system_error"
    QueryExecutionReceipt invariants (VM-verified): cap_granted:false iff {denied,query_error}; rows_returned:0 when denied; effective_limit==min(plan_limit,row_limit_cap); G4 clamp ≠ denial
    Rust SIR: BuildQueryPlanInline.filters types Collection[FilterPredicate] (LAB-TC-ARRAY-P2 record-field-context confirmed in EXECQ fixture)
    KDR 5 kinds: rows/empty/denied/query_error/system_error; denial-as-data 10th proof (StorageCapability 5th domain)
    5 boundary findings:
      B1: Effect contract passport gap — ExecuteQuery ESCAPE class; two-fixture architecture is correct separation
      B2: filters=Collection[FilterPredicate] in Rust SIR (LAB-TC-ARRAY-P2 record-field-context confirmed)
      B3: `deny_reason` used (not `message` — Ruby parser keyword)
      B4: `read_file` used in effect binding (not `read` — Ruby parser keyword)
      B5: TBackend/TEMPORAL absent from both fixtures — orthogonality confirmed
    Permanently closed: real DB/SQL/ORM/ActiveRecord/persistence runtime/write ops (v0)/TBackend/TEMPORAL/stable API
    verify_lab_execute_query_p1.rb: 57/57 PASS
      EXECQ-COMPILE 5/5 | EXECQ-SHAPE 8/8 | EXECQ-GATES 6/6 | EXECQ-RECEIPT 7/7 |
      EXECQ-VM 8/8 | EXECQ-MAP 4/4 | EXECQ-ARRAY 4/4 | EXECQ-COMPOSE 5/5 |
      EXECQ-CLOSED 5/5 | EXECQ-GAP 5/5
    Next authorized: Stage 2+ live execution (PROP-035 Stage 2+ auth + ch4 ExecuteQuery ESCAPE→STORAGE amendment); ✅ LAB-FILTER-EVAL-P1 CLOSED (50/50 PASS — in-memory predicate evaluation; eq/neq/contains/prefix; AND composition; FilterEvalSim; unknown op→query_error (not denied))
    Doc: igniter-lab/lab-docs/lang/lab-execute-query-effect-contract-and-storage-capability-injection-v0.md
    Card: igniter-lab/.agents/work/cards/lang/LAB-EXECUTE-QUERY-P1.md

52. ✅ LAB-FILTER-EVAL-P1: Filter predicate evaluation over mocked in-memory rows (2026-06-10)
    Category: lang / Track: lab-query-filter-predicate-evaluation-over-mocked-rows-v0
    Route: LAB PROOF / QUERY SEMANTICS / IN-MEMORY MOCKED ROWS / NO DB
    Depends on: LAB-QUERY-P3 (44/44), LAB-TC-ARRAY-P2 (19/19), LAB-EXECUTE-QUERY-P1 (57/57)
    9 pure contracts (all CORE; no effect; no capability; no IO):
      BuildFilterEq / BuildFilterNeq / BuildFilterContains / BuildFilterPrefix — 4 operator predicate shapes
      BuildQueryPlanWithFilters — QueryPlan with inline 2-filter array (LAB-TC-ARRAY-P2 mechanism, 3rd confirmation)
      FilterResultRows — QueryResult{kind:"rows", count:N}
      FilterResultEmpty — QueryResult{kind:"empty", count:0}
      FilterResultQueryError — QueryResult{kind:"query_error"} for unknown operator (≠ "denied")
      FilterResultMetadataReader — map_get(result.metadata, key) + or_else on filter output
    Layer A: Ruby TypeChecker — 9/9 accepted; 0 type_errors; FilterPredicate / QueryPlan / QueryResult shapes correct
    Layer B: Rust compiler + VM — fixture compiles; Rust SIR: BuildQueryPlanWithFilters.filters =
             Collection[FilterPredicate] (record-field-context mechanism — 3rd confirmation);
             inline empty array → Collection[FilterPredicate] from field context (confirmed);
             VM executes 6 of 9 contracts: filter shapes, plan, rows/empty/query_error, metadata chain
    Layer C: FilterEvalSim (proof-local Ruby only — NOT production runtime) — eq/neq/contains/prefix correct
             over 5-row deterministic dataset; AND composition narrows (3 < 4 each individually);
             empty filter list → all 5 rows (vacuous conjunction = true);
             unknown field in row → kind:"empty" (row fails predicate; NOT query_error);
             unknown operator → kind:"query_error" (NOT "denied")
    count==matched_rows.length invariant holds across all evaluations
    KDR 3-kind routing: rows (process) / empty (show empty state) / query_error (fix predicate before retry)
    4 boundary findings:
      B1: VM has no iteration opcodes — Layer C required for row evaluation semantics (correct boundary, not a workaround)
      B2: Empty filter array → Collection[FilterPredicate] from record-field context (3rd confirmation of P2 mechanism)
      B3: Unknown field ≠ unknown operator: field absence → kind:"empty"; bad op → kind:"query_error" — must not collapse
      B4: StorageCapability G1–G6 gate sequence orthogonal to filter evaluation
    Permanently closed: real DB/SQL/ORM/ActiveRecord/persistence runtime/write ops/FilterEvalSim as production runtime/stable API
    verify_lab_filter_eval_p1.rb: 50/50 PASS
      FEVAL-COMPILE 5/5 | FEVAL-SHAPE 7/7 | FEVAL-ARRAY 4/4 | FEVAL-SEMANTICS 7/7 |
      FEVAL-RESULT 6/6 | FEVAL-VM 8/8 | FEVAL-CLOSED 5/5 | FEVAL-GAP 8/8
    Next authorized: ✅ LAB-QUERY-ORDER-LIMIT-P1 CLOSED (54/54 PASS — order/limit semantics over mocked rows; asc/desc lexicographic sort; stable sort; limit>0/0/<0; unknown dir/neg limit→query_error not denied; filter→order→limit pipeline; QueryPlan.limit ≠ StorageCapability row_limit; OrderLimitSim proof-local only) | OR/NOT composition (explicit card + KNOWN_OPS extension); numeric operators (gt_integer/lt_integer — typed value variant card); production filter runtime (VM iteration opcodes or compiled-to-host — separate card); rows field in QueryResult (Collection[Map[String,String]] or typed Row — separate card)
    Doc: igniter-lab/lab-docs/lang/lab-query-filter-predicate-evaluation-over-mocked-rows-v0.md
    Card: igniter-lab/.agents/work/cards/lang/LAB-FILTER-EVAL-P1.md

53. ✅ LAB-QUERY-ORDER-LIMIT-P1: Order and limit semantics over mocked in-memory rows (2026-06-10)
    Category: lang / Track: lab-query-order-and-limit-semantics-over-mocked-rows-v0
    Route: LAB PROOF / QUERY SEMANTICS / IN-MEMORY MOCKED ROWS / NO DB
    Depends on: LAB-QUERY-P3 (44/44), LAB-EXECUTE-QUERY-P1 (57/57), LAB-FILTER-EVAL-P1 (50/50), LAB-TC-ARRAY-P2 (19/19), PROP-043-P5 (55/55), LAB-VM-MAP-P1 (48/48), LAB-RECORD-VM-P3 (49/49)
    7 pure contracts (all CORE; no effect; no capability; no IO):
      BuildOrderAsc — OrderBy { direction:"asc" } shape
      BuildOrderDesc — OrderBy { direction:"desc" } shape
      BuildQueryPlanOrderLimit — QueryPlan with order + limit + inline filter array (LAB-TC-ARRAY-P2 mechanism, 4th confirmation)
      OrderLimitRows — QueryResult{kind:"rows", count:N} — ordered/limited rows returned
      OrderLimitEmpty — QueryResult{kind:"empty", count:0} — limit==0 produces empty
      OrderLimitQueryError — QueryResult{kind:"query_error"} for unknown direction or negative limit (≠ "denied")
      OrderLimitMetadataReader — map_get(result.metadata, key) + or_else on order/limit output
    Layer A: Ruby TypeChecker — 7/7 accepted; 0 type_errors; OrderBy / QueryPlan / QueryResult shapes correct
    Layer B: Rust compiler + VM — fixture compiles; Rust SIR: BuildQueryPlanOrderLimit.filters =
             Collection[FilterPredicate] (record-field-context mechanism — 4th confirmation);
             QueryPlan.order typed OrderBy; QueryPlan.limit typed Integer; VM executes all 7 contracts
    Layer C: OrderLimitSim (proof-local Ruby only — NOT production runtime) — asc/desc lexicographic sort
             correct over 5-row deterministic dataset; stable sort (equal keys preserve input order);
             empty direction → preserve input order (no ordering applied);
             unknown direction → kind:"query_error" (NOT "denied");
             missing order field in any row → kind:"query_error" (fail-closed);
             limit>0 → first N rows after ordering; limit==0 → kind:"empty"; limit<0 → kind:"query_error" (NOT "denied");
             order-then-limit invariant: limit applied AFTER ordering;
             filter→order→limit pipeline composes (filter active rows, sort by name asc, limit 2 → alice/bob)
    count==returned_rows.length invariant holds across all evaluations
    QueryPlan.limit ≠ StorageCapability row_limit gate (orthogonal)
    KDR 3-kind routing: rows (process) / empty (show empty state) / query_error (fix plan field before retry)
    All comparisons are lexicographic String comparisons in v0; numeric/date ordering deferred
    5 boundary findings:
      B1: VM has no sort/iteration opcodes — Layer C required for order/limit semantics (correct boundary, not a workaround)
      B2: BuildQueryPlanOrderLimit.filters → Collection[FilterPredicate] from record-field context (4th confirmation of P2 mechanism)
      B3: Unknown direction ≠ negative limit ≠ missing field — all three produce kind:"query_error" (NOT "denied")
      B4: QueryPlan.limit and StorageCapability row_limit are orthogonal concerns; must not conflate
      B5: `message` is Ruby parser keyword — `input reason : String` used in OrderLimitQueryError (confirmed from LAB-EXECUTE-QUERY-P1 B4)
    Permanently closed: real DB/SQL order-by execution/ORM/ActiveRecord/persistence runtime/write ops/query optimizer/OrderLimitSim as production runtime/stable API
    verify_lab_query_order_limit_p1.rb: 54/54 PASS
      OLIMIT-COMPILE 5/5 | OLIMIT-SHAPE 7/7 | OLIMIT-SEMANTICS 8/8 | OLIMIT-LIMIT 7/7 |
      OLIMIT-RESULT 6/6 | OLIMIT-VM 8/8 | OLIMIT-COMPOSE 4/4 | OLIMIT-CLOSED 5/5 | OLIMIT-GAP 4/4
    ✅ Next: LAB-EXECUTE-QUERY-P2 CLOSED (73/73 PASS — first complete mocked ExecuteQuery pipeline; gates + filter + order + limit + receipt integrated in one IntegratedQuerySim; gate short-circuit; G4 clamp ≠ denial; query_error ≠ denied throughout; receipt 15-field invariants; 5th confirmation of P2 mechanism)
    Next authorized: multi-column ordering (order: Collection[OrderBy] — separate card); numeric/date ordering (type promotion in row values — deferred v0); production integrated query runtime (IntegratedQuerySim is PROOF-LOCAL only — separate card)
    Doc: igniter-lab/lab-docs/lang/lab-query-order-and-limit-semantics-over-mocked-rows-v0.md
    Card: igniter-lab/.agents/work/cards/lang/LAB-QUERY-ORDER-LIMIT-P1.md

54. ✅ LAB-EXECUTE-QUERY-P2: First complete mocked ExecuteQuery pipeline (2026-06-10)
    Category: lang / Track: lab-execute-query-integrated-gates-filter-order-limit-receipt-v0
    Route: LAB PROOF / INTEGRATED MOCKED QUERY EXECUTION / NO DB
    Depends on: LAB-EXECUTE-QUERY-P1 (57/57), LAB-FILTER-EVAL-P1 (50/50), LAB-QUERY-ORDER-LIMIT-P1 (54/54), LAB-STORAGE-CAPABILITY-P2 (51/51), LAB-QUERY-P3 (44/44), LAB-TC-ARRAY-P2 (19/19), PROP-043-P5 (55/55), LAB-VM-MAP-P1 (48/48), LAB-RECORD-VM-P3 (49/49)
    8 pure contracts (all CORE; no effect; no capability authority; no IO):
      BuildIntegratedPlan — QueryPlan with inline filter array (LAB-TC-ARRAY-P2 mechanism, 5th confirmation)
      BuildIntegratedCapability — StorageCapability plain Record shape (8 fields)
      BuildIntegratedRowsResult — QueryResult{kind:"rows", count:N} — rows after full pipeline
      BuildIntegratedEmptyResult — QueryResult{kind:"empty", count:0} — zero rows
      BuildIntegratedDeniedResult — QueryResult{kind:"denied", count:0} — G1/G2/G3 gate denial
      BuildIntegratedQueryErrorResult — QueryResult{kind:"query_error", count:0} — malformed plan field
      BuildIntegratedReceipt — QueryExecutionReceipt (15 fields) — allowed execution receipt
      IntegratedMetadataReader — map_get(result.metadata, key) + or_else on integrated QueryResult
    Layer A: Ruby TypeChecker — 8/8 accepted; 0 type_errors; all types in type_env with correct field types
    Layer B: Rust compiler + VM — fixture compiles; Rust SIR: BuildIntegratedPlan.filters =
             Collection[FilterPredicate] (record-field-context mechanism — 5th confirmation);
             QueryPlan.filters: Collection[FilterPredicate]; QueryPlan.order: OrderBy; receipt 15 fields;
             all 8 contracts VM-executed
    Layer C: IntegratedQuerySim (proof-local Ruby only — NOT production runtime)
             G1: source not in allowed_sources → denied (short-circuits before filter/order/limit)
             G2: "read" not in allowed_ops → denied (short-circuits before filter/order/limit)
             G3: read_allowed:false → denied (short-circuits before filter/order/limit)
             G4: plan.limit > cap.row_limit → effective_limit = min(plan.limit, cap.row_limit); NOT denial
             G5: include_all && !allow_include_all → query_error (NOT denied)
             G6: filter evaluation (eq/neq/contains/prefix; AND-only; bad op → query_error; missing field → empty)
                 order evaluation (asc/desc lexicographic stable sort; unknown direction → query_error)
                 limit evaluation (after filter+order; limit==0 → empty; limit<0 → query_error)
    QueryExecutionReceipt invariants: cap_checked:true always; cap_granted:false iff {denied,query_error};
    denial_gate records which gate fired; effective_limit = min(plan_limit, row_limit_cap);
    row_limit_clamped:true when cap reduced plan limit; rows_returned mirrors actual row count;
    result_kind mirrors QueryResult.kind
    query_error ≠ denied invariant confirmed: G1/G2/G3→denied; G5/G6-filter/G6-order/negative-limit→query_error
    QueryPlan.limit ≠ StorageCapability row_limit (orthogonal; G4 clamp runs before G6 evaluation)
    KDR 5-kind routing: rows (process) / empty (show empty state) / denied (do not retry) / query_error (fix plan) / system_error (retry later)
    7 boundary findings:
      B1: Gate short-circuit before filter/order/limit is the correct execution model
      B2: G4 clamp ≠ denial — effective_limit, cap_granted:true, row_limit_clamped:true
      B3: G5 → query_error (NOT denied) — include_all is a plan field
      B4: query_error ≠ denied invariant holds throughout integrated pipeline (all 73 checks)
      B5: QueryPlan.limit and StorageCapability row_limit are orthogonal — must not conflate
      B6: Collection[FilterPredicate] from record-field context — 5th confirmation (LAB-TC-ARRAY-P2)
      B7: `message` is a Ruby parser keyword — use `deny_reason`/`reason` for input names
    Permanently closed: SQL/DB/ORM/StorageCapability authority/joins/aggregates/writes/transactions/production runtime/stable API
    IntegratedQuerySim is PROOF-LOCAL ONLY — NOT production integrated query runtime
    verify_lab_execute_query_p2.rb: 73/73 PASS
      EXECQ2-COMPILE 5/5 | EXECQ2-SHAPE 8/8 | EXECQ2-GATES 6/6 | EXECQ2-FILTER 8/8 |
      EXECQ2-ORDER-LIMIT 8/8 | EXECQ2-INTEGRATED 7/7 | EXECQ2-RECEIPT 7/7 |
      EXECQ2-VM 8/8 | EXECQ2-CLOSED 9/9 | EXECQ2-GAP 7/7
    Next authorized: production integrated query execution (IntegratedQuerySim is PROOF-LOCAL only — separate card); ✅ multi-column ordering: LAB-QUERY-MULTI-ORDER-P1 CLOSED (64/64 PASS — Collection[OrderBy] stable multi-column sort; empty list no-op; empty direction→query_error; 6th P2 confirmation); numeric/date ordering (type promotion — deferred v0); joins/aggregates (single-source v0 — separate card); write execution (closed this track — separate card)
    Doc: igniter-lab/lab-docs/lang/lab-execute-query-integrated-gates-filter-order-limit-receipt-v0.md
    Card: igniter-lab/.agents/work/cards/lang/LAB-EXECUTE-QUERY-P2.md

55. ✅ LAB-QUERY-MULTI-ORDER-P1: Multi-column order semantics over mocked rows (2026-06-10)
    Category: lang / Track: lab-query-multi-column-order-over-mocked-rows-v0
    Route: LAB PROOF / QUERY SEMANTICS / NO DB
    Depends on: LAB-QUERY-ORDER-LIMIT-P1 (54/54), LAB-EXECUTE-QUERY-P2 (73/73), LAB-FILTER-EVAL-P1 (50/50), LAB-TC-ARRAY-P2 (19/19), LAB-TC-ARRAY-P1 (27/27), PROP-043-P5 (55/55), LAB-VM-MAP-P1 (48/48)
    7 pure contracts (all CORE; no effect; no capability authority; no IO):
      BuildMultiOrderPlan — QueryPlanMultiOrder with 2-key Collection[OrderBy]; dept+name asc (LAB-TC-ARRAY-P2 mechanism, 6th confirmation)
      BuildEmptyOrderPlan — QueryPlanMultiOrder with empty Collection[OrderBy] (no-op semantics)
      BuildThreeKeyOrderPlan — QueryPlanMultiOrder with 3-key Collection[OrderBy]; dept asc / level desc / name asc
      BuildMultiOrderRowsResult — QueryResult{kind:"rows"} for non-empty ordered result
      BuildMultiOrderEmptyResult — QueryResult{kind:"empty"} for zero rows
      BuildMultiOrderQueryErrorResult — QueryResult{kind:"query_error"} for malformed order specification
      MultiOrderMetadataReader — map_get(result.metadata, key) + or_else on QueryResult.metadata
    Layer A: Ruby TypeChecker — 7/7 accepted; 0 type_errors; QueryPlanMultiOrder.order: Collection[OrderBy]; filters: Collection[FilterPredicate]; limit: Integer; OrderBy 2 fields
    Layer B: Rust compiler + VM — fixture compiles; Rust SIR: BuildMultiOrderPlan.order_list =
             Collection[OrderBy] from record-field context (LAB-TC-ARRAY-P2 mechanism, 6th confirmation);
             all 7 contracts VM-executed
    Layer C: MultiOrderSim (proof-local Ruby only — NOT production runtime)
             Empty Collection[OrderBy] → preserve input order (no-op)
             Empty direction in entry → query_error (each entry is explicit step; direction required)
             Unknown direction → query_error (NOT denied)
             Missing order field in row → query_error (NOT denied)
             Sort keys applied left to right: first=primary, second=secondary, third=tertiary
             Stable sort: equal keys preserve input order (integer index as final tiebreaker)
             Per-column desc direction via ReverseComparable (all positions same type → Array#<=> safe)
             Limit applied AFTER all ordering (order-then-limit invariant)
    MultiOrderQuerySim (integrated — proof-local only): gates + filter + Collection[OrderBy] + limit compose correctly
    v0 multi-order results proved (5-row dataset):
      [] → charlie,alice,dave,bob,eve (input order)  |  [name asc] → alice,bob,charlie,dave,eve
      [dept asc, name asc] → alice,bob,charlie,dave,eve  |  [dept asc, level desc] → charlie,bob,alice,dave,eve
      [dept asc, level desc, name asc] → bob,charlie,alice,dave,eve (name asc resolves eng/senior tie)
    Stable sort: EQUAL_KEY_ROWS (dept=eng,level=senior,name=zoe for all 3) → idx=0,idx=1,idx=2 (input order)
    query_error ≠ denied invariant confirmed throughout (unknown direction / missing field / empty direction / negative limit)
    8 boundary findings:
      B1: Empty Collection[OrderBy] → preserve input order (no-op); valid, not an error
      B2: Empty direction in multi-order entry → query_error; differs from single-order P1 where empty=no sort
      B3: ReverseComparable: all desc positions have uniform type → Array#<=> correct throughout composite key
      B4: Integer index tiebreaker ensures stable sort for equal keys
      B5: query_error ≠ denied invariant confirmed for all malformed-order paths
      B6: Collection[OrderBy] from record-field context — 6th confirmation (LAB-TC-ARRAY-P2)
      B7: QueryPlanMultiOrder is a new type — does not mutate existing QueryPlan
      B8: Order-then-limit invariant: limit applied AFTER all sort keys resolved
    Permanently closed: SQL/DB/ORM/StorageCapability authority/joins/aggregates/writes/production runtime/stable API
    MultiOrderSim is PROOF-LOCAL ONLY — NOT production multi-column order runtime
    verify_lab_query_multi_order_p1.rb: 64/64 PASS
      MORDER-COMPILE 5/5 | MORDER-SHAPE 6/6 | MORDER-SINGLE 5/5 | MORDER-MULTI 8/8 |
      MORDER-STABLE 5/5 | MORDER-LIMIT 4/4 | MORDER-ERROR 5/5 | MORDER-INTEGRATED 6/6 |
      MORDER-VM 7/7 | MORDER-CLOSED 8/8 | MORDER-GAP 5/5
    Next authorized: numeric/date ordering (type promotion in row values — deferred v0); collation-aware ordering (deferred); integrated multi-order + QueryExecutionReceipt (extend LAB-EXECUTE-QUERY-P2 — separate card); production multi-order runtime (MultiOrderSim is PROOF-LOCAL only — separate card); **LAB-QUERY-PROJECTION-P1 — CLOSED (62/62)**
    Doc: igniter-lab/lab-docs/lang/lab-query-multi-column-order-over-mocked-rows-v0.md
    Card: igniter-lab/.agents/work/cards/lang/LAB-QUERY-MULTI-ORDER-P1.md

56. ✅ LAB-QUERY-PROJECTION-P1: Projection and include_all row-shaping semantics over mocked rows (2026-06-10)
    Category: lang / Track: lab-query-projection-and-include-all-over-mocked-rows-v0
    Route: LAB PROOF / QUERY SEMANTICS / NO DB
    Depends on: LAB-EXECUTE-QUERY-P2 (73/73), LAB-QUERY-MULTI-ORDER-P1 (64/64), LAB-FILTER-EVAL-P1 (50/50), LAB-QUERY-ORDER-LIMIT-P1 (54/54), LAB-TC-ARRAY-P2 (19/19), LAB-TC-ARRAY-P1 (27/27), PROP-043-P5 (55/55), LAB-VM-MAP-P1 (48/48)
    7 pure contracts (all CORE; no effect; no capability authority; no IO):
      BuildIncludeAllPlan — QueryPlanProjection with include_all=true, empty order; proves Projection input-typed
      BuildFieldsProjectionPlan — QueryPlanProjection with include_all=false, "name,status"; 2-key order (LAB-TC-ARRAY-P2 mechanism, 7th confirmation)
      BuildSingleFieldPlan — QueryPlanProjection with include_all=false, "name"; empty order
      BuildProjectionRowsResult — QueryResult{kind:"rows"} for projected rows
      BuildProjectionEmptyResult — QueryResult{kind:"empty"} for zero rows after projection pipeline
      BuildProjectionQueryErrorResult — QueryResult{kind:"query_error"} for malformed projection or policy violation
      ProjectionMetadataReader — map_get(result.metadata, key) + or_else on QueryResult.metadata
    Layer A: Ruby TypeChecker — 7/7 accepted; 0 type_errors; Projection.fields: String; Projection.include_all: Bool;
             QueryPlanProjection.projection: Projection; QueryPlanProjection.filters: Collection[FilterPredicate]; QueryPlanProjection.order: Collection[OrderBy]
             B9 boundary: nested record literals inside outer record literals do not get inner-field type context;
             workaround: projection as input (same pattern as execute_query_integrated.ig); gap documented
    Layer B: Rust compiler + VM — fixture compiles; Rust SIR: BuildFieldsProjectionPlan.order_list =
             Collection[OrderBy] from record-field context (LAB-TC-ARRAY-P2 mechanism, 7th confirmation);
             all 7 contracts VM-executed
    Layer C: ProjectionSim (proof-local Ruby only — NOT production runtime)
             include_all=true → full row passthrough (identity projection); all 5 fields per row preserved
             include_all=false → comma-split field list: split(",").map(&:strip).reject(&:empty?)
             empty fields → query_error (malformed plan; fix before retry)
             missing field in row → query_error (fail-closed; NOT denied)
             duplicate fields → de-duplicate preserving first occurrence (not query_error)
             projection does NOT change row count — column selector, not row filter
    ProjectionQuerySim (integrated — proof-local only): gates + filter + Collection[OrderBy] + limit + projection compose correctly
    Pipeline position: G1/G2/G3 denial → G4 clamp → G5 include_all policy → G6 filter+order+limit → projection
    G5: allow_include_all=false + include_all=true → query_error (NOT denied; fires before projection)
    v0 projection results proved (5-row dataset: alice/bob/carol/dave/eve):
      include_all=true: all 5 rows, all 5 fields unchanged
      fields="name,status": all 5 rows, each {name, status}
      fields="name": all 5 rows, each {name}
      fields=" name , status ": whitespace stripped → same as "name,status"
      fields="name,status,name": de-duplicated → same as "name,status"
      fields="" → query_error; fields="name,missing_col" → query_error
    Integrated pipeline: filter(active) → order(name asc) → limit(100) → projection(name,status) → 3 rows, 2 fields each
    query_error ≠ denied invariant confirmed throughout (empty fields / missing field / G5 policy / negative limit)
    10 boundary findings:
      B1: include_all=true → full row passthrough (identity projection)
      B2: fields parsed as comma-split+strip in v0
      B3: empty field list → query_error (malformed plan)
      B4: field absent in row → query_error (fail-closed)
      B5: duplicate fields → de-duplicate preserving first occurrence
      B6: projection does not change row count
      B7: projection applied AFTER filter → multi-order → limit
      B8: G5 include_all policy → query_error (NOT denied)
      B9: TypeChecker nested-record-literal boundary (workaround: projection as input; gap documented)
      B10: Collection[OrderBy] from record-field context (LAB-TC-ARRAY-P2 — 7th confirmation)
    Permanently closed: SQL/DB/ORM/StorageCapability authority/joins/aggregates/writes/production runtime/stable API
    ProjectionSim is PROOF-LOCAL ONLY — NOT production projection evaluation runtime
    verify_lab_query_projection_p1.rb: 62/62 PASS
      PROJ-COMPILE 5/5 | PROJ-SHAPE 7/7 | PROJ-INCLUDE-ALL 5/5 | PROJ-FIELDS 8/8 |
      PROJ-PIPELINE 6/6 | PROJ-POLICY 5/5 | PROJ-ERROR 6/6 | PROJ-VM 7/7 | PROJ-CLOSED 8/8 | PROJ-GAP 5/5
    Next authorized: TypeChecker nested-record-literal context propagation — **LAB-TC-NESTED-RECORD-CONTEXT-P1 CLOSED (42/42)**; Typed Row[T]/schema-aware projection (separate card); Collection[String] field list grammar (grammar change — separate card); **LAB-EXECUTE-QUERY-P3 — CLOSED (68/68)**; production projection runtime (ProjectionSim is PROOF-LOCAL ONLY — separate card)
    Doc: igniter-lab/lab-docs/lang/lab-query-projection-and-include-all-over-mocked-rows-v0.md
    Card: igniter-lab/.agents/work/cards/lang/LAB-QUERY-PROJECTION-P1.md

57. ✅ LAB-TC-NESTED-RECORD-CONTEXT-P1: Nested record literal context propagation (2026-06-10)
    Category: lang / Track: lab-typechecker-nested-record-literal-context-propagation-v0
    Route: LAB FIX + PROOF / RUST TYPECHECKER HARDENING / NO QUERY SEMANTICS CHANGE
    Depends on: LAB-TC-ARRAY-P1 (27/27), LAB-TC-ARRAY-P2 (19/19), LAB-RACK-P13, LAB-QUERY-PROJECTION-P1 (62/62)
    Fix: extended check_record_literal_shape in typechecker.rs
      Added type_shapes parameter; added Expr::RecordLiteral arm in step 3 field-value type checks
      When field value is RecordLiteral AND expected field type is a named record in type_shapes → recurse
      Bounded: one call per nesting level; no global inference; no Hindley-Milner; no retroactive mutation
      Non-named-record expected types (Map, Collection, scalar) → skip (Unknown-compatible)
      Updated both call sites: compute phase upgrade block (local_type_shapes) + check_array_literal_shape (type_shapes)
    6 pure contracts (all CORE; no effect; no capability authority; no IO):
      BuildPlanInlineProjection — inline Projection literal in QueryPlanProjection; proves B9 gap closed
      BuildPlanInlineSource — inline QuerySource literal in QueryPlanProjection
      BuildPlanBothInline — both Projection + QuerySource inline simultaneously
      BuildPlanTwoLevel — two-level nesting: ContactRecord → Contact → Address all inline
      BuildPlanMixedRefAndInline — mixed refs and inline literals
      BuildNaturalInlineQuery — exact B9 natural pattern from PROJECTION-P1 now compiles
    Layer A: Ruby TypeChecker — B9 divergence documented; Ruby TC checks inline literal against outer type
             (not fixed here; pre-existing different bug in Ruby TC); Rust TC is correct path
    Layer B: Rust compiler + VM — all 6 contracts compile; 0 diagnostics; correct type_tags;
             VM round-trips: BuildPlanInlineProjection.result.projection.fields="name,status";
             BuildNaturalInlineQuery runs; BuildPlanTwoLevel.result.contact.address.city="Westville"
    Layer C: Negative inline cases (5) — all fail closed OOF-TY0:
             missing include_all / extra bogus field / wrong type include_all:"yes" /
             two-level missing city / two-level extra zip
    query_error ≠ denied invariant: N/A (TypeChecker fix, not query semantics)
    9 boundary findings:
      B1: Gap was silent — Rust TC neither errored NOR validated inline nested record literals
      B2: Fix: RecordLiteral arm in step 3; recurse when expected type is a named record
      B3: Non-named-record field types → skip; Unknown-compatible; no false positive
      B4: Complex exprs (FieldAccess, Call) in field position → still Unknown-compatible
      B5: Two-level nesting works recursively
      B6: Fail-closed on missing/extra/wrong-type (all OOF-TY0 with informative messages)
      B7: PROJECTION-P1 workaround (projection as input) remains valid
      B8: Ruby TC B9 divergence documented; not fixed here; Rust TC correct path
      B9: Fix scope: typechecker.rs only
    Permanently closed: Ruby TC gap (separate divergence); global inference; query semantics change;
                       SQL/DB/ORM; parser; VM; grammar; production runtime; public API
    verify_lab_tc_nested_record_context_p1.rb: 42/42 PASS
      NRC-COMPILE 5/5 | NRC-TYPE 7/7 | NRC-QUERY 6/6 | NRC-DEEP 4/4 |
      NRC-FAIL 9/9 | NRC-BOUNDARY 5/5 | NRC-REG 6/6
    Next authorized: Ruby TC nested-record-literal parity (separate card — different Ruby TC bug);
                    multi-hop Ref nesting (deferred); inline Collection[T] in outer literal (investigate)
    Doc: igniter-lab/lab-docs/lang/lab-typechecker-nested-record-literal-context-propagation-v0.md
    Card: igniter-lab/.agents/work/cards/lang/LAB-TC-NESTED-RECORD-CONTEXT-P1.md

58. ✅ LAB-EXECUTE-QUERY-P3: Unified mocked query execution receipt (2026-06-10)
    Category: lang / Track: lab-execute-query-unified-filter-multiorder-projection-receipt-v0
    Route: LAB PROOF / INTEGRATED QUERY PIPELINE / NO DB
    Depends on: LAB-EXECUTE-QUERY-P2 (73/73), LAB-QUERY-MULTI-ORDER-P1 (64/64), LAB-QUERY-PROJECTION-P1 (62/62), LAB-FILTER-EVAL-P1 (50/50), LAB-QUERY-ORDER-LIMIT-P1 (54/54), LAB-STORAGE-CAPABILITY-P2 (51/51), LAB-TC-ARRAY-P2 (19/19), LAB-VM-MAP-P1 (48/48)
    New type: QueryPlanUnified { kind, source:QuerySource, projection:Projection, filters:Collection[FilterPredicate], order:Collection[OrderBy], limit:Integer, metadata:Map[String,String] }
      Does NOT mutate existing QueryPlan / QueryPlanMultiOrder / QueryPlanProjection from prior fixtures
    Layer C pipeline (10 steps):
      1. G1: source allowlist → denied
      2. G2: op allowlist → denied
      3. G3: read_allowed master → denied
      4. G4: row-limit clamp → effective_limit = min(plan.limit, cap.row_limit); NOT denial
      5. G5: include_all policy → query_error (NOT denied)
      6. Apply filters → rows / empty / query_error (bad op)
      7. Apply multi-column order → sorted rows / query_error (bad dir / missing field)
      8. Apply effective_limit → limited rows / empty / query_error (negative)
      9. Apply projection → shaped rows / query_error (empty fields / missing field)
     10. Build QueryResult + QueryExecutionReceipt
    G1/G2/G3 short-circuit: filter/order/limit/projection NOT evaluated on denial
    G4 clamp is NOT denial: cap_granted stays true after clamping; effective_limit recorded in receipt
    G5 → query_error, NOT denied; fires before filter/order/limit/projection
    Projection is the final step: comes after filter → multi-order → limit
    Projection does not change row count: column selector, not row filter
    query_error ≠ denied throughout: G1/G2/G3→denied; all other failures→query_error
    Receipt mirrors result_kind and rows_returned after full pipeline (after projection)
    8 pure contracts (all CORE; no effect; no capability):
      BuildUnifiedPlan — QueryPlanUnified with inline filters (LAB-TC-ARRAY-P2 8th confirmation)
      BuildUnifiedCapability — StorageCapability schema-shaped record
      BuildUnifiedRowsResult / BuildUnifiedEmptyResult / BuildUnifiedDeniedResult / BuildUnifiedQueryErrorResult
      BuildUnifiedReceipt — QueryExecutionReceipt (15 fields; same shape as P2)
      UnifiedMetadataReader — map_get + or_else
    All 8 contracts VM-executed
    TypeChecker boundary (B9 from PROJECTION-P1): projection passed as input (workaround still required);
      gap already closed by LAB-TC-NESTED-RECORD-CONTEXT-P1 (fix in typechecker.rs)
    LAB-TC-ARRAY-P2 8th confirmation: BuildUnifiedPlan.filters typed Collection[FilterPredicate] in Rust SIR
    10 boundary findings:
      B1: Full v0 pipeline order: G1→G2→G3→G4→G5→filter→multi-order→limit→projection→receipt
      B2: Projection is the final step — AFTER filter → multi-order → limit
      B3: G4 row-limit clamp remains NON-denial; cap_granted:true after clamp
      B4: G5 include_all policy → query_error (NOT denied); fires before projection
      B5: G1/G2/G3 short-circuit: filter/order/limit/projection NOT evaluated on denial
      B6: Projection does not change row count — column selector, not row filter
      B7: query_error ≠ denied throughout pipeline
      B8: Receipt mirrors result_kind and rows_returned after full pipeline (after projection)
      B9: TypeChecker nested-record-literal boundary (projection as input; not fixed here)
      B10: LAB-TC-ARRAY-P2 8th confirmation: BuildUnifiedPlan.filters Collection[FilterPredicate]
    Permanently closed: SQL/DB/ORM/StorageCapability authority/joins/aggregates/writes/production runtime/stable API
    UnifiedQuerySim is PROOF-LOCAL ONLY — NOT production unified query runtime
    verify_lab_execute_query_p3.rb: 68/68 PASS
      EXECQ3-COMPILE 5/5 | EXECQ3-SHAPE 8/8 | EXECQ3-GATES 6/6 | EXECQ3-PIPELINE 7/7 |
      EXECQ3-PROJECTION 7/7 | EXECQ3-RECEIPT 6/6 | EXECQ3-ERROR 8/8 | EXECQ3-VM 8/8 |
      EXECQ3-CLOSED 8/8 | EXECQ3-GAP 5/5
    Next authorized: LAB-TC-NESTED-RECORD-CONTEXT-P1 — **CLOSED (42/42)** (B9 gap);
                    Typed Row[T]/schema-aware projection (separate card);
                    Collection[String] field list grammar (grammar change — separate card);
                    Production unified query runtime (UnifiedQuerySim is PROOF-LOCAL ONLY — separate card)
    Doc: igniter-lab/lab-docs/lang/lab-execute-query-unified-filter-multiorder-projection-receipt-v0.md
    Card: igniter-lab/.agents/work/cards/lang/LAB-EXECUTE-QUERY-P3.md

59. ✅ LAB-QUERY-V0-STABILIZATION-P1: Query v0 boundary stabilization (2026-06-10)
    Category: governance / Track: query-v0-typed-intent-capability-mocked-execution-stabilization
    Route: GOVERNANCE / DESIGN STABILIZATION / NO NEW FEATURE WORK
    Decision: Query v0 is stabilized as typed query intent AST + StorageCapability gates +
      deterministic mocked execution + QueryResult / QueryExecutionReceipt + denial-as-data
      and query_error separation.
    Authority: lab evidence only; not canon authority, not public API, not real IO execution.
    Evidence base:
      LAB-QUERY-P1/P2/P3; LAB-STORAGE-CAPABILITY-P1/P2; LAB-EXECUTE-QUERY-P1/P2/P3;
      LAB-FILTER-EVAL-P1; LAB-QUERY-ORDER-LIMIT-P1; LAB-QUERY-MULTI-ORDER-P1;
      LAB-QUERY-PROJECTION-P1; LAB-TC-ARRAY-P1/P2; LAB-TC-NESTED-RECORD-CONTEXT-P1.
    Stable semantics:
      plan building is pure CORE; execution boundary is effect/capability-shaped;
      capability denial returns QueryResult{kind:"denied"}; malformed plan returns
      QueryResult{kind:"query_error"}; row_limit clamps and does not deny; projection
      happens after filter/order/limit; QueryExecutionReceipt records gates/result facts only.
    Closed surfaces:
      SQL execution, DB connection, ORM/ActiveRecord/Arel compatibility, persistence runtime,
      migrations, transactions, joins, aggregates, writes, query optimizer, StorageCapability
      live execution authority, production query runtime, public/stable API, canon change.
    Known v0 limits:
      mocked rows only; stringly Map[String,String] row values; no typed Row[T]; no joins;
      no aggregates; no writes; limited predicate language; no collation authority; no DB adapter.
    Boundary with IO:
      Query owns intent and receipts; IO owns adapter/substrate authority. Storage IO must not
      be silently equated with Network/File/Clock IO.
    Recommended next route:
      LAB-IO-BOUNDARY-P1 - IO family taxonomy and substrate readiness.
      Optional later: LAB-STORAGE-ADAPTER-P1; StorageCapability PROP only if governance
      decides grammar/public surface is needed.
    Doc: igniter-lab/lab-docs/governance/lab-query-v0-boundary-stabilization-v0.md
    Card: igniter-lab/.agents/work/cards/governance/LAB-QUERY-V0-STABILIZATION-P1.md

50. ✅ LAB-STORAGE-CAPABILITY-P2: IO.StorageCapability mocked execution boundary proof (2026-06-10)
    Category: lang / Track: lab-storage-capability-policy-gates-and-query-execution-receipt-v0
    Route: LAB PROOF / NO REAL DB / NO RUNTIME STORAGE
    Depends on: LAB-QUERY-P3, LAB-STORAGE-CAPABILITY-P1, PROP-035, PROP-046-P1, STAB-P4
    Two-fixture architecture (boundary finding B1 resolution):
      storage_capability_exec.ig — effect contract + 7 pure contracts (Layer A + Layer B compile)
      storage_capability_receipts.ig — 7 pure contracts only (Layer B VM execution)
    Types proved: QuerySource/Projection/FilterPredicate/OrderBy/QueryPlan/QueryResult/QueryExecutionReceipt (15 fields)
    8 contracts: ExecuteQuery (effect, compile-only) + BuildGrantedReceipt + BuildDeniedReceipt + BuildClampedReceipt + ReadReceiptFields + DeniedResult + QueryErrorResult + RowsResult
    6-gate denial sequence proved (Layer C StorageCapabilityGates):
      G1: source not in allowed_sources → "denied"
      G2: "read" not in allowed_ops → "denied"
      G3: read_allowed==false → "denied"
      G4: plan.limit > row_limit → CLAMP (not denial); row_limit_clamped=true
      G5: include_all + !allow_include_all → "query_error" (not "denied")
      G6: mocked execute → "rows"/"empty"/"system_error"
    QueryExecutionReceipt invariants (6 proved): cap_checked always true; cap_granted==false iff {denied,query_error}; rows_returned==0 when denied; effective_limit==min(plan_limit,row_limit_cap); row_limit_clamped==true iff effective_limit<plan_limit; source_table preserved
    KDR 5 kinds: rows/empty/denied/query_error/system_error; denial-as-data 9th proof (StorageCapability 5th domain)
    4 boundary findings:
      B1: Effect contract passport gap — VM requires capability injection for all contracts in same igapp; ESCAPE class enforcement correct (two-fixture pattern established)
      B2: Rust classifier effect name vocabulary closed: {read_file,read_json,read,write_file,write_json,write}; read_from_storage rejected
      B3: `read` is Ruby parser keyword; cannot use as effect binding name (parse_effect_binding_decl: ident-only)
      B4: `message` is Ruby parser keyword; cannot use as input name; renamed to `reason`
    TBackend ⊥ StorageCapability: orthogonal tracks; no type/grammar/runtime overlap
    Permanently closed: real DB/SQL/ORM/ActiveRecord/migrations/transactions/persistence runtime/stable API/write ops (v0)/TBackend
    verify_lab_storage_capability_p2.rb: 51/51 PASS
      SCAP2-COMPILE 4/4 | SCAP2-SCHEMA 6/6 | SCAP2-G1 4/4 | SCAP2-G2 3/3 | SCAP2-G3 3/3 |
      SCAP2-G4 4/4 | SCAP2-G5 3/3 | SCAP2-G6 4/4 | SCAP2-RECEIPT 6/6 | SCAP2-KDR 4/4 |
      SCAP2-COMPOSE 5/5 | SCAP2-CLOSED 5/5
    ✅ Next: LAB-EXECUTE-QUERY-P1 CLOSED (57/57 PASS — ExecuteQuery effect contract + mocked execution boundary; 6-gate sequence confirmed; QueryExecutionReceipt invariants VM-verified; denial-as-data 10th proof; TBackend orthogonality confirmed; write ops CLOSED v0)
    Next authorized: effect vocab expansion (B2 — explicit card required); Stage 2+ live execution (PROP-035 Stage 2+ auth + ch4 ExecuteQuery ESCAPE→STORAGE amendment); LAB-FILTER-EVAL-P1 (in-memory predicate evaluation)
    Doc: igniter-lab/lab-docs/lang/lab-storage-capability-policy-gates-and-query-execution-receipt-v0.md
    Card: igniter-lab/.agents/work/cards/lang/LAB-STORAGE-CAPABILITY-P2.md

49. ✅ PROP-046-P1: IO.StorageCapability boundary proposal (2026-06-10)
    Category: lang / governance / Track: storage-capability-query-execution-boundary-proposal-v0
    Route: PROPOSAL AUTHORING ONLY
    Depends on: PROP-035, LAB-QUERY-P1, LAB-QUERY-P2, LAB-QUERY-P3, LAB-STORAGE-CAPABILITY-P1, PROP-043-P5, LAB-VM-MAP-P1, STAB-P4
    Core formula (locked):
      QueryPlan         = pure typed intent data (CORE; no capability needed)
      StorageCapability = authority to attempt bounded storage execution (ESCAPE/STORAGE)
      QueryResult       = typed outcome/denial data (5-kind KDR)
      StorageCapability ≠ database connection / ORM / SQL runtime / TBackend (orthogonal)
    15 design decisions locked (D1..D15):
      D1: IO.StorageCapability name (IO.* opaque sentinel)
      D2: allowed_sources (not allowed_tables; mirrors QueryPlan vocabulary)
      D3: allowed_sources fail-closed (empty = deny all)
      D4: allowed_ops: ["read"] in v0; write deferred (not permanently closed)
      D5: row limit clamps (not denies); effective_limit = min(plan.limit, row_limit)
      D6: include_all violation → "query_error", not "denied"
      D7: read_allowed/write_allowed = master kill-switches (Gate G3)
      D8: deny_reason surfaced in QueryResult.message
      D9: QueryExecutionReceipt = evidence-only (no re-authorization)
      D10: ExecuteQuery = ESCAPE (v0) → STORAGE (Stage 2+; ch4 amendment required)
      D11: no delegation algebra in v0
      D12: SQL text generation is not a language surface
      D13: IO.StorageCapability ⊥ TBackend (orthogonal tracks)
      D14: no new grammar needed for P2 (PROP-035 sufficient)
      D15: write ops deferred (not permanently closed)
    6-gate sequence locked; QueryExecutionReceipt 15-field schema locked
    Implementation blocked: Stage 2+ STORAGE fragment class requires ch4 amendment
    ✅ Next: LAB-STORAGE-CAPABILITY-P2 CLOSED (51/51 PASS — 6-gate proof; QueryExecutionReceipt; denial-as-data 9th proof)
    Proposal: igniter-lang/.agents/work/proposals/PROP-046-storage-capability-query-execution-boundary-v0.md
    Card: igniter-lang/.agents/work/cards/lang/PROP-046-P1.md

48. ✅ PROP-044-P6: variant + match SemanticIR emitter implementation (2026-06-10)
    Category: lang / Track: variant-match-semanticir-emitter-proof-v0
    Route: SEMANTICIR EMITTER IMPLEMENTATION / BOUNDED
    Depends on: PROP-044-P5
    semanticir_emitter.rb changes (3 edits):
      typed_semantic_ir_program(): variant_env → semantic_variant_declarations(); result["variant_declarations"]
      semantic_expr(): elsif "variant_construct" → semantic_variant_construct(expr)
        elsif "match_expr" → semantic_match_node(expr) — before recur call check
      New methods (4):
        semantic_variant_declarations(variant_env): variant_env hash → [{kind:"variant_decl",
          name:, arms:[{name:, fields:[{name:, type:}]}]}]
        semantic_variant_construct(expr): typed_fields→fields rename; arm/variant/resolved_type
        semantic_match_node(expr): match_expr kind → match_node; subject/subject_type/arms/
          exhaustive/has_wildcard/resolved_type emitted
        semantic_match_arm(arm): pattern preserved; body lowered via semantic_expr; resolved_type
    Key IR shapes:
      variant_decl: top-level in semantic_ir_program (not in contracts); unit arms have fields:[]
      variant_construct: arm/variant/fields/resolved_type; typed_fields→fields rename
      match_node: kind renamed from match_expr; subject_type string; exhaustive/has_wildcard flags
    OOF guard: emit_typed checks type_errors.empty?; all OOF-KIND* programs → nil semantic_ir
    Closed: VM runtime; stable public API; grammar expansion; match guards
    Next authorized (explicit auth required): PROP-044-P7 VM variant dispatch
    verify_prop044_p6_semanticir.rb: 50/50 PASS
      SIR-VARDECL 5/5 | SIR-UNIT-ARM 5/5 | SIR-CONSTRUCT 5/5 | SIR-MATCH-KIND 5/5 |
      SIR-MATCH-ARMS 5/5 | SIR-MATCH-FLAGS 5/5 | SIR-OOF-GUARD 5/5 | SIR-REGRESSION 5/5 |
      SIR-DEGRADED 5/5 | SIR-BOUNDARY 5/5
    Regressions clean: P5-typechecker 75/75 | P3-parser 50/50 | OOF-R3 33/33
    Card: igniter-lang/.agents/work/cards/lang/PROP-044-P6.md

47. ✅ PROP-044-P5: variant + match TypeChecker implementation (2026-06-10)
    Category: lang / Track: variant-match-typechecker-and-oof-kind-activation-v0
    Route: TYPECHECKER IMPLEMENTATION / BOUNDED
    Depends on: PROP-044-P4
    classifier.rb changes (2 edits):
      variant_declarations(parsed_program) — maps parsed_program.fetch("variants", [])
        → normalized arm+field hashes; reuses normalized_type_annotation() (PROP-043 C1)
      classify(): result["variant_declarations"] = variant_decls unless variant_decls.empty?
    typechecker.rb changes (5 edits):
      typecheck(): @variant_shapes = variant_shapes(classified_program) after @type_shapes
      typecheck() result: result["variant_env"] = @variant_shapes unless @variant_shapes.empty?
      variant_shapes(classified_program) — 3-level builder (variant→arm→field→type_ir)
        mirrors type_shapes(); variant_type?(name); variant_arms(name); find_variant_for_arm(arm)
      infer_expr: when "variant_construct" / when "match_expr" before else→OOF-TY0
      infer_variant_construct: arm search; field validation; type_ir(variant_name) on success
      infer_match_expr: subject inference; OOF-KIND4 gate; per-arm narrowing; exhaustiveness;
        OOF-KIND1/2/3 checks; result type unification; degraded mode for non-variant/Unknown
      unify_match_arm_types: all-same→concrete; all-Unknown→Unknown; mixed-concrete→OOF-KIND5
    OOF-KIND codes now ACTIVE:
      OOF-KIND1: non-exhaustive match (missing arms, no wildcard)
      OOF-KIND2: undeclared arm/binding/field in construct or match pattern
      OOF-KIND3: unreachable arm (duplicate coverage)
      OOF-KIND4: match subject is not a variant type
      OOF-KIND5: divergent arm result types (concrete–concrete only; Unknown mix excluded)
    Key behaviors:
      Degraded mode: OOF-KIND4 fires; arm bodies still walked; Unknown result propagated
      Partial binding: absent fields in binding list do NOT fire OOF-KIND2 (intentional)
      Arm isolation: arm_scope = symbol_types.merge(arm_bindings); outer scope not mutated
      Output mismatch from degraded match: standard OOF-TY0 at output check (not suppressed)
    Closed: SemanticIR emitter; VM runtime; public/stable sum-type API
    ✅ Next: PROP-044-P6 CLOSED (50/50 PASS — SemanticIR emitter live; variant_decl/variant_construct/match_node; regressions clean)
    verify_prop044_p5_typechecker.rb: 75/75 PASS
      VTCK-SHAPES 5/5 | VTCK-CONSTRUCT-OK 5/5 | VTCK-CONSTRUCT-ERR 5/5 |
      VTCK-MATCH-OK 5/5 | VTCK-KIND1 5/5 | VTCK-KIND2-ARM 5/5 |
      VTCK-KIND2-BINDING 5/5 | VTCK-KIND3 5/5 | VTCK-KIND4 5/5 | VTCK-KIND5 5/5 |
      VTCK-SCOPE 5/5 | VTCK-UNIFY 5/5 | VTCK-DEGRADED 5/5 |
      VTCK-REGRESSION 5/5 | VTCK-BOUNDARY 5/5
    Regressions clean: PROP-043-P5 55/55 | OOF-R3 33/33 | loop_body 100/100 | P3-parser 50/50
    Card: igniter-lang/.agents/work/cards/lang/PROP-044-P5.md

45. ✅ PROP-044-P4: variant + match TypeChecker design (2026-06-09)
    Category: lang / governance / Track: variant-match-typechecker-and-oof-kind-planning-v0
    Route: TYPECHECKER DESIGN / NO IMPLEMENTATION
    Depends on: PROP-044-P3
    Design: @variant_shapes 3-level store (variant_name → arm_name → field_name → type_ir)
    Classifier bridge:
      New method variant_declarations(parsed_program) — reads parsed_program.fetch("variants", [])
        mirrors type_declarations(); reuses normalized_type_annotation() for PROP-043 C1
      Wired into classify() as result["variant_declarations"] = variant_decls unless empty
      TypeChecker reads via @variant_shapes = variant_shapes(classified_program)
    TypeChecker new methods:
      variant_shapes(classified_program) — builder (mirrors type_shapes())
      variant_type?(name), variant_arms(name), variant_arm_field_type(v,a,f), find_variant_for_arm(arm)
      infer_variant_construct — resolves variant by arm search; validates fields; returns type_ir(variant_name)
      infer_match_expr — resolves subject type; OOF-KIND4 gate; per-arm narrowed scopes;
        exhaustiveness (covered_arms set vs declared_arms set); OOF-KIND1/2/3; result unification
      infer_match_expr_degraded — walks arm bodies; returns Unknown; used when OOF-KIND4 fires
      unify_match_arm_types — all-same→concrete; all-Unknown→Unknown; mixed-concrete→OOF-KIND5
    infer_expr extension: when "variant_construct" / when "match_expr" → new handlers
      (replaces else→OOF-TY0 fallthrough for these two node kinds)
    OOF-KIND codes (reserved; activated in P5):
      OOF-KIND1: non-exhaustive match (missing arms, no wildcard)
      OOF-KIND2: undeclared arm/binding/field in construct or match pattern
      OOF-KIND3: unreachable arm (duplicate coverage or after wildcard)
      OOF-KIND4: match subject is not a variant type
      OOF-KIND5: divergent arm result types (concrete–concrete only; Unknown mix excluded)
    Per-arm scope: arm_symbol_types = symbol_types.merge(arm_bindings); not mutated; isolated
    Exhaustiveness: declared_arms.keys - covered_arms.keys; has_wildcard short-circuits
    Result propagation: variant_env added to typed_program (for SemanticIR P6 readiness)
    16 design decisions locked (DD-01..DD-16)
    Proof requirements for P5: 15 check groups, ~75-80 PASS gate
      VTCK-SHAPES, VTCK-CONSTRUCT-OK/ERR, VTCK-MATCH-OK, VTCK-KIND1..5,
      VTCK-SCOPE, VTCK-UNIFY, VTCK-DEGRADED, VTCK-REGRESSION, VTCK-BOUNDARY
    Closed: TypeChecker implementation; SemanticIR emitter; VM runtime; stable API
    ✅ Next: PROP-044-P5 CLOSED (75/75 PASS — OOF-KIND1..5 ACTIVE; infer_variant_construct; infer_match_expr)
    Design doc: igniter-lang/.agents/work/proposals/PROP-044-variant-match-typechecker-and-oof-kind-planning-v0.md
    Card: igniter-lang/.agents/work/cards/lang/PROP-044-P4.md

44. ✅ PROP-044-P3: variant + match parser implementation (2026-06-09)
    Category: lang / Track: variant-and-match-parser-proof-v0
    Route: PARSER IMPLEMENTATION / PROOF-LOCAL
    Depends on: PROP-044-P2
    Parser changes (8 edits to parser.rb):
      Lexer: fat_arrow (=>) — elsif peek(1) == ">" branch in "=" case
      Keywords: "variant" and "match" added to KEYWORDS array
      parse() accumulator: "variants" => [] added to program hash
      parse() dispatch: "variant" → program["variants"] << decl
      parse_top_decl: when "variant" → parse_variant_decl
      parse_primary kw branch: when "match" → parse_match_expr
      parse_primary ident branch: PascalCase + { peek → parse_variant_construct
      ParsedProgram#to_h: "variants" field + grammar_version "variant-v0" check
    New methods: parse_variant_decl, parse_variant_arm, parse_variant_construct,
                 parse_match_expr, parse_match_arm, parse_match_pattern
    Keyword fix: binding names in parse_match_pattern accept %i[ident keyword]
      (message, label, etc. are keywords from PROP-025; fixtures must avoid them as compute names)
    AST shapes confirmed: variant{name,arms[{name,fields}]}, variant_construct{arm,fields},
      match_expr{subject,arms[{pattern:{wildcard,arm,bindings},body}]}
    Conflict boundaries proved: type/record_literal/if/lowercase-ident all unaffected
    TypeChecker: no crash (passes unknown nodes); type_errors allowed; no OOF activation
    grammar_version: "variant-v0" for sources with variant decls or match/construct exprs
    All prior proofs clean after parser changes:
      PROP-043-P5: 55/55; PROP-042-P3: 45/45; OOF-R3: 34/34; loop_body: 100/100
    verify_prop044_p3_parser.rb: 50/50 PASS
      VPRS-KEYWORDS 5/5 | VPRS-UNIT 5/5 | VPRS-RECORD 5/5 | VPRS-MIXED 5/5 |
      VPRS-CONSTRUCT 5/5 | VPRS-MATCH 5/5 | VPRS-BINDINGS 5/5 | VPRS-INTEGRATE 5/5 |
      VPRS-CONFLICT 5/5 | VPRS-BOUNDARY 5/5
    Card: igniter-lang/.agents/work/cards/lang/PROP-044-P3.md
    ✅ Next: PROP-044-P4 CLOSED (TypeChecker design — @variant_shapes; classifier bridge; OOF-KIND1..5; 16 decisions)

43. ✅ LAB-QUERY-P2: QueryPlan pure builder proof (2026-06-09)
    Category: lang / Track: lab-query-plan-record-fixture-and-pure-builder-proof-v0
    Route: EXPERIMENTAL / LAB-ONLY
    Depends on: LAB-QUERY-P1, PROP-043-P5, LAB-VM-MAP-P1, LAB-RESULT-ENVELOPE-P2
    Types proved (7 — all expressible as named Records today; no grammar changes):
      QuerySource   { table:String, schema:String }
      Projection    { fields:String, include_all:Bool }
      FilterPredicate { field:String, op:String, value:String }
      OrderBy       { field:String, direction:String }
      QueryPlan     { kind:String, source_table, filter_field, filter_op, filter_value, order_field, order_dir, limit:Integer, metadata:Map[String,String] }
      QueryResult   { kind:String, count:Integer, message:String, metadata:Map[String,String] }
      StorageDenied { table:String, op:String, reason:String, kind:String }
    Contracts proved (6 — all pure/CORE; no IO; no StorageCapability):
      BuildQuerySource: QuerySource record construction
      BuildSelectQuery: full flat QueryPlan (kind="select")
      BuildFilteredQuery: simplified eq-filter plan (filter_op="eq"; limit=100)
      QueryResultDenied: denial-as-data (QueryResult{kind:"denied"}; no exception)
      QueryMetadataReader: map_get(result.metadata,"source")+or_else (C1 chain; 4th domain)
      QueryMapper: three-layer mapper (context→QueryResult; map_get(context,"message")+or_else)
    QueryResult kind vocabulary: rows / empty / denied / query_error / system_error
    C1 chain 4th domain: result.metadata→Map[String,String]→map_get→Option[String]→or_else→String
    KDR convention 4th domain: QueryResult follows kind+message+metadata shape
    "empty" kind: domain-specific to query (zero rows != error; not in ValidationResult/ContractResult)
    Two failure fixes (40→42): split string self-references + CLOSED-05 CORE-fragment proof
    ✅ Next: LAB-STORAGE-CAPABILITY-P1 CLOSED (IO.StorageCapability design-locked)
    ✅ Next: LAB-QUERY-P3 CLOSED (44/44 PASS — nested records; Collection[FilterPredicate]; chained field access; denial-as-data 8th proof)
    Next authorized: PROP-046 (grammar proposal); LAB-TC-ARRAY-P1 (Rust typechecker array_literal); LAB-EXECUTE-QUERY-P1 (ExecuteQuery effect contract + mocked StorageCapability)
    verify_lab_query_p2.rb: 42/42 PASS
      QPLAN-COMPILE 4/4 | QPLAN-TYPES 5/5 | QPLAN-BUILD 6/6 | QPLAN-DENIED 4/4 |
      QPLAN-MAP 4/4 | QPLAN-VM 5/5 | QPLAN-ROUTE 5/5 | QPLAN-COMPARE 4/4 | QPLAN-CLOSED 5/5

41. ✅ LAB-QUERY-P1: Query/Arel-like data access pressure boundary research (2026-06-09)
    Category: lang / Track: lab-query-arel-like-data-access-pressure-boundary-v0
    Route: RESEARCH / DESIGN / LAB-ONLY
    Depends on: PROP-043-P5, LAB-RESULT-ENVELOPE-P2, LAB-STDLIB-NET-P9, LAB-RACK-P14, LAB-SIDEKIQ-P5, LAB-CONCURRENCY-P4
    Core formula: Query v0 = typed intent AST + capability boundary + mocked execution
    QueryPlan v0 types (all expressible as named Records today — no new grammar):
      QuerySource { table:String, schema:String }
      Projection  { fields:Collection[String], include_all:Bool }
      FilterPredicate { field:String, op:String, value:String }  -- op: eq/neq/gt/gte/lt/lte/is_null
      OrderBy     { field:String, direction:String }
      QueryPlan   { source, projection, filters:Collection[FilterPredicate], order:Collection[OrderBy], limit:Integer, kind:String }
      QueryResult { kind:String, rows:Collection[Map[String,String]], count:Integer, message:String, metadata:Map[String,String] }
      StorageDenied { table:String, op:String, reason:String, kind:String }
    QueryResult kind vocabulary: rows / empty / denied / query_error / system_error
    Arel/ORM classification:
      Adopt: query-as-data, delayed execution, predicate composition, explicit projection, renderer/executor separation
      Permanently closed: ORM, ActiveRecord, lazy relations, global connection, callbacks, save!, implicit transactions, dynamic columns
      Deferred to v1: joins, aggregates, write ops, OR/NOT predicates, typed Row[T]
    Fragment classification: plan-building = CORE; execution (future) = ESCAPE → STORAGE class
    Capability boundary: IO.StorageCapability (follows PROP-035 model); pure plan-building needs none
    Denial-as-data: QueryResult{kind:"denied"} — never exception; 8th domain proof opportunity
    TBackend distinction: Store[T] = temporal substrate (PROP-008); QueryPlan = relational intent — orthogonal tracks
    ✅ Next: LAB-QUERY-P2 CLOSED (42/42 PASS — 6 contracts; 7 types; denial-as-data; C1 chain 4th domain)
    ✅ Next: LAB-STORAGE-CAPABILITY-P1 CLOSED (IO.StorageCapability design-locked)
    ✅ Next: LAB-QUERY-P3 CLOSED (44/44 PASS — nested records; Collection[FilterPredicate]; chained field access; denial-as-data)
    Next authorized: PROP-046 (StorageCapability grammar proposal); LAB-TC-ARRAY-P1 (Rust typechecker array_literal); LAB-EXECUTE-QUERY-P1 (ExecuteQuery + mocked StorageCapability)
    Doc: igniter-lab/lab-docs/lang/lab-query-arel-like-data-access-pressure-boundary-v0.md
    Card: igniter-lab/.agents/work/cards/lang/LAB-QUERY-P1.md

40. ✅ PROP-044-P1: Kind-discriminated outcome convention and sum type requirements (2026-06-09)
    Category: lang / governance / Track: kind-discriminated-outcome-convention-and-sum-type-requirements-v0
    Route: PROPOSAL AUTHORING ONLY
    Depends on: LAB-RESULT-ENVELOPE-P1, LAB-RESULT-ENVELOPE-P2, LAB-RACK-P14, LAB-SIDEKIQ-P5, PROP-043-P5
    Convention (today, no grammar needed):
      KDR pattern: type + kind:String + doc-declared vocabulary + Map[String,String] metadata
      3-domain corpus: HttpResult(3-kind), ContractResult(6-kind), ValidationResult(4-kind)
      Denial-as-data invariant: 7 proofs, cross-domain, design law (proven, unenforced)
      Three-layer composition: boundary → mapper → consumer; confirmed in 3 domains
    Grammar gap (blocks enforcement, not convention):
      variant declaration: OPEN (sealed kind vocabulary)
      exhaustive match: OPEN (OOF-KIND1 impossible without it)
      type narrowing: OPEN (post-match type refinement)
      OOF-KIND1..4: namespace reserved; not active until grammar lands
    Production implementation: BLOCKED (grammar must land first)
    Domain vocabularies: do not unify — each domain's kind space has local semantics
    Next authorized: PROP-044-P2 grammar proposal (variant+match design; requires explicit auth)
    Proposal: igniter-lang/.agents/work/proposals/PROP-044-kind-discriminated-outcome-convention-and-sum-type-requirements-v0.md
    Card: igniter-lang/.agents/work/cards/lang/PROP-044-P1.md

39. ✅ LAB-RESULT-ENVELOPE-P2: Third-domain kind-discriminant pressure proof (2026-06-09)
    Category: governance / Track: lab-result-envelope-third-domain-kind-discriminant-pressure-v0
    Route: EXPERIMENTAL / GOVERNANCE / LAB-ONLY
    Domain: Form validation and submission processing (orthogonal to HTTP and Sidekiq)
    Depends on: LAB-RESULT-ENVELOPE-P1, LAB-VM-MAP-P1, LAB-RACK-P14, LAB-SIDEKIQ-P5, PROP-043-P5
    ValidationResult: 4-kind envelope (valid/invalid/unauthorized/system_error)
      No HTTP status codes. No retry budget. No job identity fields.
      metadata: Map[String,String] for field context (rule, expected, field_name, etc.)
    P1 reclassifications:
      kind-discriminant: STRENGTHENED (2→3 domains; confirmed cross-domain)
      denial-as-data:    CONFIRMED CROSS-DOMAIN (6→7 proofs; unauthorized path in validation domain)
      Map[String,String]: CONFIRMED CROSS-DOMAIN (2→3 contexts; vr.metadata C1 chain works)
      three-layer composition: CONFIRMED (ValidationMapper = domain mapper in non-HTTP domain)
      budget-loop: DOMAIN-LOCAL (not universal; validation has no retry cycle)
      ContractResult name: CONFIRMED TOO GENERIC (HTTP-domain-bound; 6-kind space is HTTP-specific)
    PROP-044 status: deferred → PROPOSAL-AUTHORING ONLY authorized (3-domain bar met; grammar gap remains)
    VM executed: 6 contracts (ValidSubmission, MetadataInspector×2, ValidationMapper×2, UnauthorizedSubmission)
    verify_lab_result_envelope_p2.rb: 50/50 PASS
      VENV-COMPILE 4/4 | VENV-TYPES 5/5 | VENV-KINDS 6/6 | VENV-DENIED 4/4 | VENV-MAP 5/5 |
      VENV-VM 6/6 | VENV-ROUTE 5/5 | VENV-COMPARE 5/5 | VENV-PROMOTE 5/5 | VENV-CLOSED 5/5

34. ✅ PROP-043-P4: Map[K,V] production-edit planning (2026-06-09)
    Depends on: PROP-043-P3, PROP-043-P2, PROP-043-P1
    Scope: 2 files only — classifier.rb (1-line C1 fix at line 52: normalize_type → normalized_type_annotation)
        + typechecker.rb (~175 additive lines: MAP_STDLIB_FNS, infer_map_get/has_key/from_pairs/empty,
        infer_or_else, infer_array_literal, infer_record_literal, check_map_annotation, helpers,
        @output_type_hints pre-scan, OOF-MAP annotation scan, 2 infer_call arms, 2 infer_expr arms,
        1-line type_shapes C1 fix)
    SIR emitter: NO CHANGE — typed_ports + semantic_expr generic path already handle Map nodes
    parser.rb: NO CHANGE — Map annotations already parse; short names parse as call nodes
    P4-Q1..Q9 all resolved: insertion points exact; or_else confirmed absent (new addition);
        map_empty accepted as-is (C2, type_name equality only); from_pairs Unknown fallback silent;
        OOF-MAP wording templates locked; regression matrix defined (≥42 + T1/T2/T3 regressions)
    C1 fix: two-file (classifier.rb:52 + typechecker.rb:118) — normalized_type_annotation already exists
    C2 resolution: map_empty → Map[String,Unknown] passes type_name equality; context inference v1
    Track: igniter-lang/.agents/work/tracks/prop043-p4-map-kv-production-edit-planning-v0.md
    Card: igniter-lang/.agents/work/cards/lang/PROP-043-P4.md
    Next: PROP-043-P5 production implementation (classifier.rb + typechecker.rb + verify script)

---

## Workspace Repo Map

| Repo | Authority | Boundary |
|---|---|---|
| `igniter-lang` | Language canon: spec, proposals, grammar, compiler proof | Language meaning only |
| `igniter-lab` | Lab frontier: experiments, proofs, prototypes | Evidence only; not canon |
| `igniter-ruby` | Ruby Framework gem umbrella | Framework impl; not language spec |
| `igniter-org` | Public site (`igniter-lang.org`) | Projects current truth from lang/lab |
| `igniter-archive` | Recovery bucket from monorepo split | Not a default dependency |

**Monorepo note:** Workspace split from the `/igniter` monorepo. `igniter-archive` is the
quarantine bucket. Nothing there is a default dependency — review explicitly before pulling.

---

## Alignment Gaps

| Gap | Description | Action |
|---|---|---|
| NET-P2..P6 → lang | Lab delegation algebra has no grammar analog beyond PROP-035 | Runtime injection — Phase 2 |
| HTTP-TYPES → lang | ContractRef not in grammar; lab pressure only | Separate PROP when HTTP track matures |
| LAB-RACK-P2..P5 → lang | Static pipeline + ContractRef gap map + 5-route dispatch proven end-to-end on VM; TypeChecker == and < still open | LAB-RACK-P6 next (TypeChecker == and < alignment) |
| Web Framework → lang | LayoutEngine is lab-only; lab pressure only | Separate PROP when view track matures |
| PROP-039 loop impl | ✅ Gates 1+3+4+5+6+7+8 closed + Lab G1+G2+G3+G4+G5 conformance + Canon G5 recur() closed | lab Rust G5 symmetry closed 2026-06-08 — verify_g5_recur.rb 18/18 PASS |
| Lab G1 | ✅ closed 2026-06-07 — Rust lab parser accepts `loop Name item in source` | — |
| Lab G2 | ✅ closed 2026-06-07 — `recursive`/`fuel_bounded` contract modifiers + `decreases`/`max_steps` body decls | — |
| Lab G3 | ✅ closed 2026-06-08 — G3a OOF-R2/R4 in classifier + G3b FiniteLoop `for Name item in source` + G3c IR shape `kind="loop_node"` | — |
| Lab G4 | ✅ closed 2026-06-08 — `lead` keyword, OOF-L5/L7/L8, canon `body=[lead_node*,compute_node*]` + `item_type`, two-track `body`/`body_nodes`; verify_g4_body_semantics.rb 18/18 PASS | — |
| Canon G5 | ✅ closed 2026-06-08 — `recur()` context validation (OOF-R1), arity (OOF-R5), type (OOF-R6), single-output (OOF-R7), SemanticIR `recur_call` sub-expr; recursive_body_proof 100/100 PASS | — |
| Lab G5 | ✅ closed 2026-06-08 — OOF-R1/R5/R6/R7 in typechecker.rs, `recur_call` sub-expr in emitter.rs; verify_g5_recur.rb 18/18 PASS | — |
| Canon String Core | ✅ closed 2026-06-08 — 14 text stdlib ops (concat/trim/contains/starts_with/ends_with/split/replace/replace_all/byte_length/rune_length/grapheme_length/byte_slice/rune_slice/grapheme_slice); TEXT_STDLIB_FNS registry in typechecker.rb; string_core_proof 60/60 PASS | — |
| Lab String Core (Rust symmetry) | ✅ closed 2026-06-08 — typechecker.rs + emitter.rs; P2 concat disambiguation; verify_str_core.rb 29/29 PASS | — |
| Lab STR-CORE-P3 value semantics | ✅ closed 2026-06-08 — compile-time unit separation + SIR shapes + OOF enforcement proven; runtime-gated gaps documented; verify_str_value_semantics.rb 33/33 PASS | — |
| LAB-STR-UNICODE-P1 Unicode policy | ✅ design-locked 2026-06-08 — UTF-8 validity, UAX #29 grapheme, no normalization, bounds policy, `unicode-segmentation` lab recommendation, receipt design | — |
| LAB-STR-UNICODE-P2 Unicode VM ops | ✅ closed 2026-06-08 — 8 functional ops + qualified aliases + empty-input guards; UAX#29 runtime proven; 43/43 PASS | — |
| LAB-STR-UNICODE-P3 handler hygiene | ✅ closed 2026-06-08 — bare split guard aligned; unicode_runtime_receipt.json; 41/41 PASS | — |
| PROP-041 T2 structural-size P3/P4/P5 | ✅ closed 2026-06-08 — proof-local gate 48/48 PASS; formal proposal authored; grammar/OOF-R8/R9/SIR/trust locked | P6: production-edit planning authorization review |
| LAB-VM-MAP-P1 VM map_get/map_has_key | ✅ closed 2026-06-09 — map_get+map_has_key OP_CALL handlers (bare + qualified); compiler input field access fix; Value::Record = Map runtime; Rack P14 10/10; Sidekiq P5 MetadataReader VM closed; 48/48 PASS | — |
| experiments/ archive | ~150 experiments, Stage 1/2 closed | DA-005: archive pass (low priority) |

---

## Delegated Cards

| ID | Task | Status |
|---|---|---|
| DA-001 | current-status.md PROP-035/PROP-040 rows | ✅ DONE |
| DA-002 | PROP-031..039 status audit + §12 renumbering | ✅ DONE |
| DA-003 | lab-docs/lang IO capability grammar doc | ✅ DONE |
| DA-004 | portfolio-index.md | ✅ DONE (this file) |
| DA-005 | experiments/ archive pass (Stage 1/2) | ✅ DONE 2026-06-07 — 5→stage1, 7→stage2, 164 unknown left, 1 error (typechecker dir absent) |

---

## Meta Notes

**MFN-001 (Portfolio Meta-Architect → Portfolio Architect Supervisor, 2026-06-07):**
- PROP-040 queued before PROP-039 → both now closed
- CR-001/002/003 firewall rules adopted in language-covenant.md
- Rack/Web/Ruby pressure stays lab-only (CR-001)
- PROP-039 accepted as vocabulary authority; parallel track confirmed; implementation closed

| LAB-IGV-TAILMIX-P2 | view | CLOSED 56/56 | FileTreeRow definition JSON + render `{html,def_refs}` + oracle + diff-oracle interpreter; N→1 dedup, fail-closed unknown-op, dispatch seam proven |
| LAB-IGV-TAILMIX-P3 | view | CLOSED 70/70 | Sidebar+FileTreeRow bundle; 2 definitions; N rows → 2 unique def_refs; slot values; per-instance state isolation; oracle+interpreter parity for both components |

### LAB-IGV-TAILMIX-P2 boundary
**Track:** lab-igv-tailmix-definition-render-diff-oracle-proof-v0  
**Result:** 56/56 PASS  
**Key findings:**
- Content-addressed `def_id = sha256:d9e2a8bb…` verified self-consistent by proof runner (DEF-08)
- `render → { html, def_refs }`: HTML carries only instance binding (`data-igv-def` + `data-igv-state`); no rules/ops inlined (RENDER-07/08)
- **N→1 dedup:** 3 instances → `unique def_refs == 1` (DEDUP-02)
- Oracle/interpreter parity: all triples match (INTERP-01–08)
- `dispatch` → host event; state unchanged (DISPATCH-03/06)
- Unknown op → `{ error: "unknown_op:<op>" }` immediately; no partial execution (FAILCLOSED-01–06)
- Definition: no VM/SIR/capability/eval (CLOSED-01–04)  
**Next route:** LAB-IGV-TAILMIX-P3 (composition + slot values) or LAB-APP-STATE-P3/LAB-APP-ASSEMBLY-P1 on IDE pressure

### LAB-IGV-TAILMIX-P3 boundary
**Track:** lab-igv-tailmix-nested-composition-bundle-dedup-slot-values-v0
**Result:** 70/70 PASS
**Key findings:**
- Bundle model: `{ bundle_id, component_map, definitions }` — 2 types → 2 definitions; `bundle_id = sha256(component_map)`; both def_ids self-consistent (BUNDLE-07/08)
- **N→2 dedup:** 3-row and 5-row renders both produce `def_refs.uniq.length == 2` (DEDUP2-01/02)
- Slot values (`items`, `title`) drive row count and binding data without mutating definitions (SLOTS-01/05)
- State isolation: `FTR.expanded` ⊥ `Sidebar.search_active` — disjoint keys, no cross-contamination (ISOLATE-01/05)
- Oracle/interpreter parity: all Sidebar + FTR triples match; interpreter (P2, unchanged) handles both types (INTERP2-01–08)
- Fail-closed: unknown op in nested component, missing component in bundle → error, no state/host_event leak (FAILCLOSED2-01–06)
- `.igv` sketch marked non-canon (IGV-03)
**Next route:** LAB-IGV-TAILMIX-P4 (`.igv`→definition compiler, proof-local) or LAB-APP-STATE-P3/LAB-APP-ASSEMBLY-P1 on IDE pressure
