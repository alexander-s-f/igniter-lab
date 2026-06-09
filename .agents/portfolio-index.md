# igniter-lab: Portfolio Index

**Maintained by:** Portfolio Architect Supervisor
**Last updated:** 2026-06-09 (LAB-RACK-P14: Rack-shaped ContractResult composition — 6-branch kind→FullRackResponse (found/created/not_found/capability_denied/upstream_error/upstream_unavailable); map_get→Option[String]+or_else→String TypeChecker-proved; 10 contracts compiled; VM-proved 9/10 (map_get gap acknowledged); 60/60 PASS)
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
| LAB-RACK-P14 (Rack-shaped ContractResult composition — 6-branch kind→FullRackResponse mapping (found/created/not_found/capability_denied/upstream_error/upstream_unavailable); map_get→Option[String]+or_else→String; P13 record upgrade; VM-proved 9/10 contracts; map_get VM gap acknowledged) | igniter-lab | ✅ DONE | 60/60 |
| LAB-RECORD-VM-P1 (VM record construction — zero new VM/compiler code; OP_PUSH_RECORD+BTreeMap proved; RackResponse + JobReceipt end-to-end; deterministic alphabetical serialization; covers Rack P14 + Sidekiq P5; see shared section below) | igniter-lab | ✅ DONE | 43/43 |
| LAB-RECORD-VM-P2 (dispatched record field access — OP_GET_FIELD added; response.status/body + receipt.status/budget_remaining/job_class proved; field values usable in arithmetic; missing-field OOF-P1 compile-time; Tier 2 field access fail-closed) | igniter-lab | ✅ DONE | 42/42 |
| LAB-RECORD-VM-P3 (nested record field values — one compiler.rs line; envelope.headers.content_type + envelope.meta.priority proved; typechecker + VM construction unchanged; direct local Unknown-typed chain fail-closed; non-record intermediate fail-closed) | igniter-lab | ✅ DONE | 49/49 |
| LAB-RECORD-MAP-P1 (Record/Map bridge — FullRackResponse {headers: Map[String,String]} proved; SIR params preserved through field access; VM store/retrieve works; C1 confirmed active (fix in P5); map_get gap documented; OOF-MAP1/2/3 in MapPipeline) | igniter-lab | ✅ DONE | 51/51 |
| Grammar analog | igniter-lang | ❌ lab pressure only (CR-001 applies) | — |

**Alignment gap:** LAB-RACK-P2..P14 + RECORD-VM-P1..P3 + RECORD-MAP-P1 → lang | VM record construction proved (P1); field access proved (P2); nested record field values proved (P3); Map[String,String] record field bridge proved (RECORD-MAP-P1, SIR params preserved). PROP-043-P5 closed: map_get(response.headers,key)→Option[String] + or_else→String end-to-end in production TypeChecker (55/55); C1 fix landed. P14 closed: 6-kind ContractResult→FullRackResponse branch mapping proved at TypeChecker + VM (9/10 contracts). Still open: VM map_get bytecode, Tier 2 type resolution, three-level chained field access, multi-output callee.

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

**Alignment gap:** LAB-SIDEKIQ-P1..P5 + RECORD-VM-P1..P3 + RECORD-MAP-P1 → lang | JobReceipt record typed and VM-executed (P1/P2); nested record field values proved (P3); Map[String,String] meta field bridge proved (RECORD-MAP-P1). PROP-043-P5 closed: map_get/or_else production TypeChecker live (55/55); C1 fix landed. LAB-SIDEKIQ-P5 closed: full upstream composition — all 4 job paths (success/denied/retry/exhausted) proved with Map[String,String] metadata; BudgetedLocalLoop simulation (48/48). Still open: three-level chained field access, enum/status type system, VM map_get bytecode, async retry, queue storage, effect-callee dispatch.

**Boundary:** Job processing vocabulary is lab-only. No Sidekiq compatibility claim. No StorageCapability, ServiceLoop, or scheduler surfaces open. `call_contract` is lab-only with no stable API.

### Concurrency / Scheduling (Lab only)

| Artifact | Repo | Status | Checks |
|---|---|---|---|
| LAB-CONCURRENCY-P1 (pure-DAG parallel scheduling boundary — wave-based concurrent eligibility; SequentialScheduler == ParallelSchedulerSimulation result identity proved; effectful nodes serialized in v0; SchedulingReceipt telemetry only; 5 inline graph fixtures: diamond, fanout, chain, mixed-effectful, impure-siblings; DagValidator cycle+dep checks; DagWaves read-isolation invariant; Category: lang, Track: lab-deterministic-pure-dag-parallel-scheduling-boundary-v0) | igniter-lab | ✅ DONE | 57/57 |

**Boundary:** Lab-only. SchedulingReceipt is telemetry evidence only — it does not create language semantic authority or open runtime concurrency authority. No `Thread`/`Fiber`/async-runtime infrastructure used. Concurrent-effectful dispatch remains closed in v0; requires a scheduling capability or policy fixture in a future gate. Parity invariant proved: `result_values` identical for all 5 fixtures across all intra-wave orderings.

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
28. ✅ LAB-TERM-T2-P2: OOF-R9 branch and multi-recur edge hardening (2026-06-08)
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
