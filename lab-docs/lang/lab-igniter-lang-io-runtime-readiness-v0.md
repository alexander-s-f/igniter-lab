# IO Runtime Readiness — igniter-lang v0

**Card:** LAB-IGNITER-LANG-IO-RUNTIME-P1  
**Track:** lab-igniter-lang-io-runtime-readiness-boundary-v0  
**Status:** CLOSED — readiness packet authored  
**Authority:** evidence + route decision only / no implementation  
**Date:** 2026-06-13

---

## Scope

This document establishes the real `igniter-lang` IO Runtime route for
microservice-capable Igniter. It answers all 12 questions posed in the card with
citations to `igniter-lang` canon and `igniter-lab` evidence. No runtime code is
implemented here.

**Authority boundary:** `igniter-lang` canon only. The old Ruby `igniter` gem,
`Igniter::ContractBuilder`, `GraphCompiler`, Rack gem, ActiveRecord, and ORM are
**not authority** for any finding in this document.

---

## Q1 — Current RuntimeMachine Status

**Evidence:** `igniter-lang/docs/spec/ch7-runtime.md`, `experiments/runtime_machine_memory_proof/`

RuntimeMachine load/evaluate/checkpoint/resume are **proven** at Stage 1/2:

```
PASS RuntimeMachine.load(hand_authored.igapp)  -> LoadedProgram
PASS RuntimeMachine.evaluate(program, inputs)  -> EvaluationResult
PASS RuntimeMachine.checkpoint(program)        -> CheckpointBundle
PASS RuntimeMachine.resume(bundle)             -> LoadedProgram
PASS CompatibilityReport with schema_check
PASS stdlib execution kernel + operator lookup
```

Supported executable node kinds at evaluate (Ch7 §7.3):

```
input_node
compute_node
output_node
```

SemanticIR supports ESCAPE fragment class (`ch6-semanticir.md §6.3`). The
fragment precedence is:

```
OOF > TEMPORAL > STREAM > ESCAPE > CORE
```

TEMPORAL Phase 1 is approved-restricted: `History[T]` valid-time only, with
ExecutorApprovalToken + CompatibilityReport gate.

**Profile system status:** PROP-033 (via profile binding) and PROP-040 (profile
declarations + OOF-M7/M8) are experiment-pass. Runtime profile injection and
broader profile policy authority remain closed.

**SemanticIR requirements derivation:** `requirements.json` is derived from
`escape_boundaries[].required_caps` — the mechanism already exists for
capability negotiation, but no executor reads it for IO dispatch.

---

## Q2 — Effect Surface Gap (Ch12)

**Evidence:** `igniter-lang/docs/spec/ch12-effect-surface.md`, `docs/language-covenant.md`

Ch12 status: **proposed** — PROP-035 not yet authored. Authorship is gated on
PROP-031 passing (PROP-031 is accepted).

| Ch12 Surface | Status | Evidence |
|---|---|---|
| `capability` / `effect_binding` grammar | `experiment-pass` | PROP-035 capability/effect_binding subset; io_capability_proof 43/43 PASS |
| OOF-M2 (pure + capability = error) | `experiment-pass` | io_capability_proof CAP-OOF-M2 sections |
| OOF-M4 (orphan effect_binding) | `experiment-pass` | io_capability_proof CAP-OOF-M4 sections |
| OOF-M5 (unbound capability) | `experiment-pass` | io_capability_proof CAP-OOF-M5 sections |
| `affects` clause | `planned PROP` | PROP-035 pending |
| `authority` clause | `planned PROP` | PROP-035 pending (Postulate 9) |
| `reversibility` clause | `planned PROP` | PROP-035 pending (Postulate 19) |
| `idempotency` clause | `planned PROP` | PROP-035 pending (Postulate 16) |
| `receipt` clause | `planned PROP` | PROP-035 pending (Postulate 8) |
| `failure` clause + 7-outcome taxonomy | `planned PROP` | PROP-035 pending (Postulate 15) |
| `compensation` clause | `planned PROP` | PROP-035 pending (Postulate 17) |
| Effect Surface in SemanticIR contract_ir | `planned PROP` | Ch12 §12.6: "Effect Surface fields are emitted into contract_ir as effect_surface object" — not yet wired |
| Receipt field enforcement | `planned PROP` | PROP-035 pending |

**Summary:** the capability gate (`capability` + `effect_binding`) is accepted
at the parser/classifier/typechecker level. The seven Effect Surface fields that
must appear between the return type and the `via` clause are all pending
PROP-035.

---

## Q3 — IO.* Capability Shape and Opacity

**Evidence:** `docs/language-covenant.md §CR-001`, `source/io_capability_basic.ig`,
`source/io_capability_oof_blocked.ig`, `experiments/io_capability_proof/io_capability_proof.rb`

**Canon Boundary Rule CR-001** (adopted 2026-06-07):

> The igniter-lang canon grammar may accept external type names (e.g.
> `IO.NetworkCapability`, `IO.FileCapability`) as opaque string identifiers. The
> compiler normalizes all `IO.*` names to the `"IO.Capability"` sentinel in the
> typed IR. The canon must not import, validate, or generate behavior that
> depends on the internal schema, field list, or delegation semantics of any
> type whose schema is defined outside igniter-lang itself.

Confirmed by proof (CAP-TYPE-4):

```
io_capability_proof CAP-TYPE-4:
  cap_decl.fetch("type").fetch("name") == "IO.Capability"   -- PASS
  (not "IO.NetworkCapability", not "IO.FileCapability")
```

This is the mechanism that prevents Rack/HTTP/gem schemas from bleeding into
canon. `IO.NetworkCapability`, `IO.FileCapability`, `IO.StorageCapability` are
lab-level names; the canon TypeChecker sees only `"IO.Capability"`.

The existing source fixtures prove three live IO.* names:

```
source/io_capability_basic.ig:
  capability net_conn: IO.NetworkCapability
  effect connect_to_service using net_conn

(io_capability_proof fixtures also cover IO.FileCapability, multi-capability)
```

---

## Q4 — Runtime Gap: What Prevents Real IO Execution Today

**Evidence:** `ch7-runtime.md §7.3`, `ch12-effect-surface.md`, `experiments/io_capability_proof/`

**Separate from parser/classifier/typechecker support:**

| Layer | IO capability support | Gap |
|---|---|---|
| Parser | `capability` / `effect_binding` grammar accepted | None at parse level |
| Classifier | ESCAPE fragment class assigned; capability/effect_binding symbols classified | None at classify level |
| TypeChecker | `IO.*` resolved to `IO.Capability` sentinel; OOF-M2/M4/M5 enforced | None at TC level (opacity enforced) |
| SemanticIR emitter | ESCAPE fragment class emitted; escape_boundaries present | `effect_surface` object not yet emitted (PROP-035 pending) |
| Assembler | ESCAPE fragment class assembles; no `effect_nodes` section exists yet | No assembled capability executor binding |
| RuntimeMachine evaluate | Supports `input_node`, `compute_node`, `output_node` only | **No CapabilityExecutor registry; no effect dispatch** |

**The blocking gap is at RuntimeMachine evaluate.** Even if an effect contract
compiles to ESCAPE and assembles to `.igapp/`, evaluate has no path to:

1. Recognise an `effect_binding_node` in the contract artifact.
2. Look up a `CapabilityExecutor` for the declared IO family.
3. Pass inputs and capability passport to the executor.
4. Receive a typed receipt or failure variant back.
5. Record the observation and return it as output.

Everything above that line in the pipeline is already accepted or experiment-pass.

---

## Q5 — Minimal CapabilityExecutor Interface

**Evidence:** `ch12-effect-surface.md §12.3`, `lab-docs/lang/lab-igniter-lang-io-capability-grammar-v0.md`,
`LAB-STORAGE-CAPABILITY-P1.md`, `LAB-FILE-IO-P1.md`

The minimal `CapabilityExecutor` for one IO family without ambient IO:

```
CapabilityExecutor {
  family: String              -- "storage" | "file" | "network" | "queue"

  execute(
    effect_name:   String,    -- declared effect_binding name
    capability:    CapabilityPassport,
                              -- runtime passport for this family
    inputs:        Map[String, Value],
    authority_ref: String,    -- from effect contract authority clause
    idempotency_key: String | nil
  ) -> EffectResult
}

EffectResult = one of:
  succeeded(receipt: EffectReceipt)
  denied(reason: String, gate: String)
  failed(error: EffectError)
  timed_out(after_ms: Integer)
  unknown_external_state(last_known_ref: String)
  compensated(compensation_receipt: CompensationReceipt)
  cancelled(reason: String)
```

**Fail-closed invariants:**

- No registered executor for the declared capability family → refuse; `effect_unsupported_family`
- Executor registered but capability passport missing → refuse; `effect_missing_passport`
- Executor registered, passport present but expired/revoked → refuse; `effect_passport_invalid`
- Idempotency key required but absent (retry-enabled profile) → refuse; compile-time OOF-M4
- Authority missing on `privileged` / `irreversible` → refuse; `effect_authority_missing`

The executor is **not** a Rack handler, not an ActiveRecord connection, and not
an ORM. It is a typed bridge between the RuntimeMachine evaluate path and a
single IO family substrate.

---

## Q6 — Result Envelope: Receipts and Failures

**Evidence:** `ch12-effect-surface.md §12.3 (failure taxonomy)`, `ch12 §12.2 (grammar)`,
`Covenant Postulate 8 (Receipts Are Proof)`, `Postulate 15 (Timeout Is Not Failure)`,
`LAB-STORAGE-CAPABILITY-P1 (QueryExecutionReceipt)`, `LAB-FILE-IO-P1 (FileReadReceipt)`

The Covenant defines the 7-outcome taxonomy in Ch12:

| Outcome | Covenant rule | Type |
|---|---|---|
| `succeeded` | Operation completed; receipt is immutable proof | `EffectReceipt` |
| `failed` | Known error from external system | `EffectError` |
| `partial` | Partial completion; reconciliation needed | `PartialReceipt` |
| `timed_out` | Time limit exceeded; outcome unknown | **P15: this is `UnknownExternalOutcome`, NOT `ObservedFailure`** |
| `unknown_external_state` | Request sent; no confirmation received | `UnknownExternalOutcome` |
| `compensated` | Compensation triggered and executed | `CompensationReceipt` |
| `cancelled` | Cancelled before completion | `CancellationReceipt` |

**P15 is load-bearing:** `timed_out` and `unknown_external_state` are
`UnknownExternalOutcome` variants, not `ObservedFailure`. They require
reconciliation, not retry. A future compiler check (OOF from PROP-035) will
enforce that code branching on a timeout does not treat it as failure.

Minimum common receipt envelope (all families must include):

```
EffectReceipt {
  receipt_id:       String,       -- immutable, content-addressed
  effect_name:      String,       -- from effect_binding declaration
  capability_id:    String,       -- from CapabilityPassport
  family:           String,       -- IO family
  authority_ref:    String,       -- who authorized this effect
  idempotency_key:  String | nil,
  idempotency_key_used: Bool,
  inputs_hash:      String,       -- sha256 of canonical inputs
  outcome:          EffectOutcome, -- one of the 7 above
  substrate:        String,       -- "storage" | "file" | "http" | "queue" | ...
  emitted_at:       String,       -- ISO8601 timestamp (from clock binding, not now())
  evidence_refs:    [String]      -- references to prior evidence this builds on
}
```

Receipts are evidence only. They do not re-authorize subsequent executions
(same invariant as `QueryExecutionReceipt` in LAB-STORAGE-CAPABILITY-P1 and
`FileReadReceipt` in LAB-FILE-IO-P1).

---

## Q7 — Microservice Model: What Igniter Microservice Means with Native IO

**Evidence:** `ch7-runtime.md`, `ch12-effect-surface.md`, `LAB-IO-BOUNDARY-P1.md`,
`LAB-RACK-P14.md`

An Igniter microservice with native IO owns this pipeline:

```
┌─────────────────────────────────────────────────────────────────────┐
│ Ingress                                                              │
│   receive typed input envelope (HTTP body, queue message, IPC call) │
│   parse to typed Map[String, Value] — no ambient env, no globals    │
│   emit ingress_observation (typed, timestamped from clock binding)  │
└────────────────────────┬────────────────────────────────────────────┘
                         │
┌────────────────────────▼────────────────────────────────────────────┐
│ RuntimeMachine evaluate (pure nodes)                                 │
│   load .igapp manifest + effect contracts                           │
│   evaluate input_node + compute_node DAG                            │
│   build EffectPlan: ordered list of declared effects with inputs    │
│   no IO occurs here — evaluate is deterministic                     │
└────────────────────────┬────────────────────────────────────────────┘
                         │
┌────────────────────────▼────────────────────────────────────────────┐
│ CapabilityExecutor dispatch (for each declared effect in plan)       │
│   verify capability passport present and valid                      │
│   verify authority clause satisfied                                 │
│   verify idempotency key if retry-enabled profile                   │
│   call registered executor for the IO family                        │
│   collect EffectResult (succeeded | failed | timed_out | ...)       │
│   emit EffectReceipt for each attempt                               │
└────────────────────────┬────────────────────────────────────────────┘
                         │
┌────────────────────────▼────────────────────────────────────────────┐
│ Response construction (pure)                                         │
│   map EffectResults to typed output contract                        │
│   attach receipts as output evidence                                │
│   build typed response envelope                                     │
└────────────────────────┬────────────────────────────────────────────┘
                         │
┌────────────────────────▼────────────────────────────────────────────┐
│ Egress                                                               │
│   serialize typed output to substrate response format               │
│   HTTP: typed status + headers + body (Rack substrate binding)      │
│   queue: typed message body                                         │
│   IPC: typed response record                                        │
└────────────────────────┬────────────────────────────────────────────┘
                         │
┌────────────────────────▼────────────────────────────────────────────┐
│ Audit trail                                                          │
│   receipts archived with program_id + contract_ref                  │
│   ingress_observation + effect_receipts + response_observation form │
│   a closed evidence chain per request                               │
│   Postulate 26: decision is complete only when outcome feedback loop│
│   closes (PostAuditReceipt — spec_candidate per Covenant P26)       │
└─────────────────────────────────────────────────────────────────────┘
```

**Key distinction from the "pure HTTP wrapper" half-measure:**

The half-measure (`igniter-lang` calls pure contracts, external host owns IO)
delegates all authority to the host and can never close the audit loop at the
language boundary. A real Igniter microservice owns the entire pipeline above —
its CapabilityExecutors are declared, gated, and evidence-producing. The host
does not own IO; the executor bridge does.

---

## Q8 — Substrate Separation

**Evidence:** `ch12-effect-surface.md`, `LAB-IO-BOUNDARY-P1.md`, `LAB-RACK-P14.md`,
`LAB-STORAGE-CAPABILITY-P1.md`, `LAB-FILE-IO-P1.md`

| Layer | Owner | Surfaces |
|---|---|---|
| **Semantics layer** | `igniter-lang` | Effect Surface declarations; capability/effect_binding grammar; fragment classification; SemanticIR ESCAPE nodes; CapabilityExecutor interface contract; receipt type system; OOF codes |
| **HTTP / Rack substrate** | External binding | Accept-loop; HTTP verb/path parsing; Rack env; response serialization. Rack is one substrate binding, not the architecture. |
| **DB / SQL substrate** | External binding | Query execution; connection pool; ORM. Only exposed via `IO.StorageCapability` passport — cannot reach the runtime without a declared capability. |
| **File substrate** | External binding | Filesystem reads/writes; encoding; symlinks. Only via `IO.FileCapability` passport. |
| **Queue substrate** | External binding | Enqueue/dequeue; acknowledgement; retry schedule. Only via `IO.QueueCapability` passport (not yet proven). |
| **Clock / time** | External binding | Wall-clock reads; deadline tracking. Covenant forbids `now()` — time enters via explicit `TemporalCtx` or clock binding. |
| **Random / entropy** | External binding | Seed generation; nonce. Requires explicit `IO.EntropyCapability` (not yet proven). |
| **IPC / process** | External binding | Subprocess spawn; stdin/stdout. Requires explicit `IO.ProcessCapability` — HOLD per LAB-IO-BOUNDARY-P1. |

**Rule:** the semantic layer defines what may be touched and at what cost. The
substrate binding defines how the touch is carried out. The two must never mix:
Rack env is not a SemanticIR node; `IO.StorageCapability` is not an
ActiveRecord connection string.

---

## Q9 — Replay and Determinism Under Real IO

**Evidence:** `ch7-runtime.md §7.9 (temporal_read_observation)`, `Covenant Postulate 8`,
`LAB-STORAGE-CAPABILITY-P1 (receipt evidence-only invariant)`

The Covenant requires a deterministic audit trail. When real IO occurs:

**What must be recorded:**

| Evidence | Purpose |
|---|---|
| `effect_binding_name` | Which declared effect ran |
| `capability_id` | Which capability passport was used |
| `inputs_hash` | Canonical hash of inputs passed to the executor |
| `outcome` | One of the 7 EffectOutcome variants |
| `substrate` | Which substrate handled the execution |
| `emitted_at` | Timestamp from the clock binding (not `now()`) |
| `idempotency_key` | For replay — same key = same logical operation |
| `authority_ref` | Who authorized the execution |

**Replay invariant:** given the same `inputs_hash` + `idempotency_key` +
`capability_id`, a re-execution with the same key must not create a duplicate
external effect. The executor is responsible for deduplication at the substrate
level. The language is responsible for recording the key.

**Unknown external state:** if the executor cannot determine whether the effect
completed (network timeout, queue unavailable), it must return
`unknown_external_state`, not `failed`. The receipt records the last-known
reference. Reconciliation is the caller's obligation, not the runtime's.

**Ledger / BiHistory analogy:** TEMPORAL Phase 1 uses `temporal_read_observation`
per authorized read. IO effects must analogously emit one `effect_observation`
per execution attempt, regardless of outcome.

---

## Q10 — Safety Gates: What Must Refuse by Default

**Evidence:** `Covenant CR-001`, `ch12-effect-surface.md §12.5`, `LAB-STORAGE-CAPABILITY-P1 (denial-as-data)`,
`LAB-FILE-IO-P1 (gate coverage)`, `ch7-runtime.md §7.8 (temporal refusals)`

All gates are **fail-closed**: missing authorization returns a structured refusal,
not an exception and not a silent no-op.

| Situation | Refusal code | Returns |
|---|---|---|
| Effect contract in pure context | `OOF-M1` / `OOF-M2` | Compiler error; no `.igapp` |
| Capability declared but not bound to an effect | `OOF-M5` | Compiler error |
| Effect binding references undeclared capability | `OOF-M4` | Compiler error |
| No executor registered for the IO family | `effect.unsupported_family` | RuntimeRefusal |
| Capability passport missing from evaluate inputs | `effect.missing_passport` | RuntimeRefusal |
| Passport present but authority mismatch | `effect.authority_mismatch` | RuntimeRefusal |
| Non-idempotent effect in retry-enabled profile | `OOF-M4` (future PROP-035) | Compiler error |
| Reversibility exceeds profile maximum | `OOF-M2` (future PROP-035 / P19) | Compiler error |
| Unknown external outcome after timeout | `unknown_external_state` | EffectResult variant (not exception) |
| No receipt emitted after execution attempt | Executor contract violation | Runtime assertion failure |
| Effect contract calls `now()` | `OOF-L6` (Covenant) | Compiler error |
| Ambient capability (no declared capability block) | `OOF-M2` | Compiler error |

**Denial-as-data pattern (from Storage and File lab evidence):** every refusal
flows as a typed variant, not as a raised exception. The consumer branches on
`result.kind`. This invariant must hold at the IO Runtime level too.

---

## Q11 — First Executable Slice: P2 IO Family Selection

**Evidence:** `LAB-IO-BOUNDARY-P1.md (readiness table)`, `LAB-STORAGE-CAPABILITY-P1.md`,
`LAB-EXECUTE-QUERY-P1/P2/P3.md`, `LAB-FILE-IO-P1.md`

Candidate families evaluated:

| Family | Lab evidence depth | Readiness per LAB-IO-BOUNDARY-P1 | Verdict |
|---|---|---|---|
| Storage read | StorageCapability design (P1) + 6-gate pipeline (P1/P2) + full unified proof (P3, 68/68) | READY for design-only adapter card | **Strongest evidence; recommended for P2** |
| File read | FileCapability shape + mocked registry + 8-gate pipeline (LAB-FILE-IO-P1, 78/78) | READY for mocked adapter | Strong second option |
| HTTP outbound | Network capability grammar, FFI boundary, delegation algebra (P6–P9) | Mocked boundary strong; real transport HOLD | Third option |
| Queue enqueue | Sidekiq analogy proven (P1–P5); no queue capability schema yet | No capability passport shape yet | Deferred |

**Recommendation: Storage read family for P2.**

Reasons:
1. Deepest proof chain (LAB-EXECUTE-QUERY-P1 through P3, plus StorageCapability P1/P2, plus unified gate pipeline).
2. Denial-as-data already proven at all 6 gates.
3. `QueryExecutionReceipt` 15-field schema is already designed.
4. `IO.StorageCapability` schema (v0) is already locked.
5. The `ExecuteQuery` effect contract form is already drafted as a design target.
6. Storage read is the most common microservice IO operation.

---

## Q12 — Closed Surfaces for P1

The following surfaces are **closed for this card** and remain closed:

| Surface | Status |
|---|---|
| No implementation changes | CLOSED |
| No Rack implementation or Rack authority | CLOSED |
| No ActiveRecord / ORM / AR references | PERMANENTLY CLOSED |
| No old Ruby `igniter` framework dependency | PERMANENTLY CLOSED |
| No real DB / SQL / network / file / queue / process / clock / random execution | CLOSED |
| No production runtime claim | CLOSED |
| No Reference Runtime claim | CLOSED |
| No public or stable API claim | CLOSED |
| No capability widening by config/env/global state | CLOSED |
| No generic ambient IO | CLOSED |
| No canon claim from lab evidence alone | CLOSED (CR-001, CR-002) |

---

## IO Runtime Route Definition

This is the route confirmed by evidence:

```
effect contract / observed contract
  -> explicit Effect Surface (affects / authority / reversibility / idempotency /
     receipt / failure / compensation)      [PROP-035 pending]
  -> capability declaration (capability Name: IO.FamilyCapability)  [experiment-pass]
  -> effect_binding (effect Name using CapabilityRef)               [experiment-pass]
  -> SemanticIR: ESCAPE fragment class + escape_boundaries           [accepted]
  -> assembler: .igapp with effect_nodes section                     [planned]
  -> RuntimeMachine load: verify effect manifest + capability index  [planned]
  -> RuntimeMachine evaluate:
       - evaluate pure compute_nodes first (deterministic)
       - build EffectPlan from resolved effect_binding nodes
  -> CapabilityExecutor registry lookup by IO family                 [planned]
  -> executor: verify passport + authority + idempotency
  -> executor: call substrate binding
  -> receive EffectResult (7-outcome taxonomy)
  -> emit EffectReceipt (immutable evidence)
  -> return typed output + receipt chain
  -> optional substrate bindings:
       HTTP inbound   — ingress substrate
       DB/storage     — Storage executor (recommended P2)
       file           — File executor
       queue          — Queue executor
       clock          — TemporalCtx binding
       random/entropy — Entropy executor
       IPC            — Process executor (HOLD)
```

---

## Evidence Summary Table

| Evidence source | What it proves | Authority level |
|---|---|---|
| `ch7-runtime.md` | Load/evaluate/checkpoint/resume proven; no IO executor | Canon spec |
| `ch12-effect-surface.md` | 7-field Effect Surface defined; PROP-035 pending | Canon spec (proposed) |
| `language-covenant.md CR-001` | IO.* names are opaque sentinels at canon TypeChecker | Canon governing |
| `language-covenant.md P15` | `timed_out` ≠ `ObservedFailure`; reconciliation required | Canon governing |
| `io_capability_proof.rb` | capability/effect_binding parse/classify/typecheck PASS | Experiment-pass |
| `io_capability_basic.ig` | IO.NetworkCapability normalizes to IO.Capability in TC | Canon source |
| `LAB-IO-BOUNDARY-P1` | IO family taxonomy; substrate readiness checklist | Lab governance |
| `LAB-STORAGE-CAPABILITY-P1/P2` | StorageCapability schema; 6-gate denial-as-data | Lab evidence |
| `LAB-EXECUTE-QUERY-P3` | Full mocked pipeline 68/68; no real DB | Lab evidence |
| `LAB-FILE-IO-P1` | File capability shape; mocked read; 78/78 | Lab evidence |
| `LAB-RACK-P14` | Rack as typed response substrate, not architecture | Lab evidence |
| `LAB-SIDEKIQ-P1` | Queue analogy; StorageCapability + SchedulerCapability pressure | Lab evidence |
| `runtime_smoke.rb` | Proof-local runtime: not production, not Reference Runtime | Proof-local only |
| `quickstart.rb` | Experimental delegated runtime: not canonical, not Reference Runtime | Experiment-local |

---

## Recommended Next Routes

**Immediate — if P1 confirms expected route (confirmed):**

1. **LANG-IO-CAPABILITY-EXECUTOR-P1** — proposal for CapabilityExecutor
   interface, capability passport shape, supported effect kinds, fail-closed
   behavior, receipt contract.

2. **LAB-IGNITER-LANG-IO-RUNTIME-P2** — first executable mocked IO runtime
   slice for Storage read family. Mocked executor, denial-as-data, receipt
   emission. No real DB.

3. **LAB-IGNITER-LANG-MICROSERVICE-P1** — service runtime envelope only after
   P2: ingress → evaluate → effect dispatch → response + receipts.
