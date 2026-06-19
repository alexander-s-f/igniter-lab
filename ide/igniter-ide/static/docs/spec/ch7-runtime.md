# Ch7: RuntimeMachine

Source PROPs: PROP-005, PROP-006, PROP-008, PROP-009, PROP-009.1, PROP-011,
PROP-022, PROP-022A, PROP-028, PROP-030, PROP-030A, PROP-038
Status: synced for approved-restricted Stage 3 Gate 3 Phase 1 semantics and
S3-R16 proof-local lib boundary (2026-05-09); R86 adds PROP-038 strict-refusal
non-runtime boundary
Primary evidence:

- `experiments/runtime_machine_memory_proof/` ��� load/evaluate/checkpoint/resume PASS
- `experiments/stdlib_execution_kernel_stage1/` ��� stdlib execution kernel PASS
- `experiments/temporal_cache_key_proof/` ��� CORE vs TEMPORAL cache-key proof PASS
- `experiments/runtime_cache_proof_local_memoization/` ��� proof-local cache semantics PASS
- `experiments/temporal_runtime_load_guard/` ��� TEMPORAL load guard PASS
- `docs/gates/gate3-decision-record-v0.md` ��� approved-restricted Phase 1 decision
- `docs/proposals/PROP-030A-temporal-scope-exclusion-errata-v0.md` ��� scope exclusion refusal
- `docs/tracks/prop-005-temporal-read-observation-v0.md` ��� temporal read observation envelope PASS
- `docs/tracks/compatibility-report-composition-v0.md` ��� composed report shape PASS
- `docs/tracks/runtime-temporal-executor-lib-prep-v0.md` ��� `IgniterLang::TemporalExecutor::Phase1` proof-local lib boundary PASS 17/17
- `docs/gates/prop038-strict-refusal-live-implementation-acceptance-decision-v0.md` ��� internal-only compiler strict-refusal foundation
- `docs/tracks/prop038-strict-refusal-canon-sync-v0.md` ��� PROP-038 canon sync

---

## 7.1 Lifecycle

```text
boot        ��� initialize RuntimeMachine instance, verify environment
load        ��� parse .igapp/ manifest + contract files -> LoadedProgram
evaluate    ��� resolve supported nodes -> EvaluationResult
checkpoint  ��� serialize current evaluation state -> CheckpointBundle (ESCAPE)
resume      ��� restore from CheckpointBundle -> LoadedProgram (ESCAPE)
```

Each step is typed. Boot must precede load; load must precede evaluate.

---

## 7.2 Load Semantics

```text
RuntimeMachine.load(path) -> LoadedProgram | LoadRefusal
```

Load reads:

- `manifest.json`
- `compilation_report.json`
- `contracts/<Name>.json`
- `requirements.json`
- `compatibility_metadata.json`

Load verifies:

- manifest shape and contract list
- compilation report `pass_result == "ok"`
- each contract artifact exists and is not `fragment_class: "oof"`
- schema descriptor compatibility
- for TEMPORAL contracts, `manifest.contract_index` agrees with contract files

CompatibilityReport is evaluated after boot + verification, not before.

Gate invariant:

```text
CompatibilityReport must not be trusted before Boot + Verification complete.
```

### 7.2.1 PROP-038 Strict Refusal Is Not A Runtime Surface

R84 accepts PROP-038 strict refusal only as an internal compiler/orchestrator
foundation. It is not a RuntimeMachine load or evaluate capability.

Accepted compiler-side boundary:

```text
internal strict requirement source
  -> orchestrator-level strict requirement decision path
  -> report-only compiler_profile_contract_validation evidence
  -> non-persisting strict terminal CompilerResult when selected
```

Runtime implications:

- strict terminal paths produce no loadable `.igapp`;
- strict terminal paths write no sidecar and no compilation report artifact;
- strict terminal paths do not enter `RuntimeMachine.load`;
- strict terminal paths do not produce or consume a CompatibilityReport;
- `CompilerProfileContractValidator` output remains compiler evidence, not
  runtime authority;
- nested `compile_refusal_authorized: false` remains report-only evidence.

Closed surfaces:

```text
public API/CLI strict source
loader/report strict source or status
CompatibilityReport strict source or status
RuntimeMachine/Gate 3 strict-refusal behavior
runtime/production strict-refusal behavior
```

Any future runtime or loader/report interpretation of PROP-038 strict refusal
requires a separate Architect decision.

---

## 7.3 Evaluate Semantics

```text
RuntimeMachine.evaluate(program, inputs) -> EvaluationResult | EvaluateRefusal
```

Evaluate:

- validates all required inputs are present and typed;
- resolves supported executable nodes in dependency order;
- emits `computation_observation` for supported CORE computation;
- refuses unsupported runtime surfaces with structured diagnostics.

Supported Stage 1 executable node kinds:

```text
input_node
compute_node
output_node
```

TEMPORAL assembled artifacts may load for inspection. Gate 3 Phase 1
implementation is approved only for `History[T]` valid-time evaluation through
an abstract non-Ledger TBackend adapter. S3-R16 added the proof-local
`IgniterLang::TemporalExecutor::Phase1` lib boundary, but live reads remain
blocked until post-lib-prep regression/safety review and an explicit live-read
decision addendum. See ��7.8.

---

## 7.4 Stdlib and Operator Execution

The previous stdlib/operator line is no longer a blocker.

Stage 1/2 evidence proves:

```text
integer add/sub/mul/div/comparison
float add/mul
decimal add/sub/mul/rescale
bool and/or/not
string concat
collection map/filter/fold/count
option or_else
```

Runtime operator lookup and stdlib kernel execution are PASS in the Stage 1/2
proof suite. Unknown or unresolved stdlib operators remain assembler/compiler
refusals rather than runtime surprises.

---

## 7.5 Checkpoint / Resume

```text
RuntimeMachine.checkpoint(program) -> CheckpointBundle (ESCAPE)
RuntimeMachine.resume(bundle)      -> LoadedProgram    (ESCAPE)
```

Both are ESCAPE because they touch external state/storage.

Resume compatibility states:

```text
trusted      ��� schema_fingerprint unchanged; full resume
provisional  ��� safe drift detected; resume with degraded mode
downgraded   ��� breaking but recoverable; migration required
blocked      ��� incompatible; cannot resume
```

---

## 7.6 Compatibility Dimensions

`CompatibilityReport` has independent dimensions:

```text
runtime_check   ��� runtime version compatibility
backend_check   ��� TBackend adapter compatibility
obs_check       ��� observation envelope format compatibility
schema_check    ��� contract schema compatibility
cache_check     ��� cache key/freshness policy compatibility, when cache exists
runtime_gate_check        ��� Gate 3 state and approved scope
executor_approval_check   ��� ExecutorApprovalToken validation
executor_readiness        ��� executor implementation/readiness
```

All required dimensions must be `ok` for trusted execution. A blocked dimension
blocks the relevant load/evaluate/cache path.

Descriptor and temporal capability evidence may be report-only; report-only
metadata does not authorize live Ledger/TBackend binding.

For Gate 3 Phase 1, readiness must be represented by one composed
CompatibilityReport:

```json
{
  "kind": "compatibility_report",
  "composition": {
    "mode": "single_report",
    "single_report_required": true,
    "split_fragments_allowed": false
  },
  "report_only": false,
  "runtime_enforced": true,
  "runtime_gate_check": { "decision": "ok" },
  "executor_approval_check": { "decision": "ok" },
  "executor_readiness": { "decision": "ok" },
  "cache_key_check": { "decision": "ok" },
  "evaluation_readiness": {
    "decision": "ready",
    "reason_code": "runtime.temporal_evaluation_ready",
    "blocks_before_executor": false
  }
}
```

Split report-only and enforcement fragments are forbidden.
`runtime_enforced: true` is valid only on the composed report for the approved
Phase 1 path.

---

## 7.7 Runtime Cache Key Contract

Production RuntimeMachine memoization is not enabled. The cache contract below
defines the required shape before production cache can exist.

### CORE Cache Keys

CORE keys use contract identity plus canonical non-temporal inputs:

```json
{
  "kind": "runtime_cache_key",
  "version": "runtime-cache-key-v1",
  "fragment": "CORE",
  "contract_ref": "contract/Add/sha256:<prefix>",
  "input_hash": "sha256:<canonical non-temporal inputs>",
  "temporal_coordinates": null
}
```

Formula:

```text
cache_key_hash = hash(version, fragment, contract_ref, input_hash)
```

### TEMPORAL Valid-Time Keys

History-style temporal keys add the explicit valid-time coordinate:

```json
{
  "kind": "runtime_cache_key",
  "version": "runtime-cache-key-v1",
  "fragment": "TEMPORAL",
  "axis": "valid_time",
  "contract_ref": "contract/HistoryAxesTest/sha256:<prefix>",
  "input_hash": "sha256:<canonical non-temporal inputs>",
  "temporal_coordinates": {
    "as_of": "2026-05-08T12:00:00Z"
  }
}
```

Formula:

```text
cache_key_hash = hash(version, fragment, axis, contract_ref, input_hash, as_of)
```

### TEMPORAL Bitemporal Keys

BiHistory-style temporal keys add both valid and transaction time:

```json
{
  "kind": "runtime_cache_key",
  "version": "runtime-cache-key-v1",
  "fragment": "TEMPORAL",
  "axis": "bitemporal",
  "contract_ref": "contract/BiHistoryAxesTest/sha256:<prefix>",
  "input_hash": "sha256:<canonical non-temporal inputs>",
  "temporal_coordinates": {
    "valid_time": "2026-05-08T12:00:00Z",
    "transaction_time": "2026-05-08T13:00:00Z"
  }
}
```

Formula:

```text
cache_key_hash = hash(
  version,
  fragment,
  axis,
  contract_ref,
  input_hash,
  valid_time,
  transaction_time
)
```

TEMPORAL coordinates are distinct key material. A CORE-shaped key for a
TEMPORAL contract is a cache schema mismatch, never a fallback.

### Freshness States

| State | Meaning | Runtime may return cached value? |
| --- | --- | --- |
| `fresh` | Key schema matches and dependencies/coordinates are verified current. | yes |
| `stale` | Runtime has evidence that dependency state or coordinate meaning changed. | no |
| `unknown` | Runtime cannot verify freshness because evidence is missing. | no by default |
| `provisional` | Runtime can return only with downgraded trust and explicit observation. | yes, marked provisional |

`unknown` must not silently become `fresh`. `provisional` is a trust mark, not
a convenience synonym for `fresh`.

### Cache Entry Envelope

```json
{
  "kind": "runtime_cache_entry",
  "version": "runtime-cache-entry-v1",
  "cache_key": {
    "key": "cache/<short-hash>",
    "hash": "sha256:<key-material>",
    "schema": "runtime-cache-key-v1"
  },
  "fragment": "CORE | TEMPORAL",
  "axis": "valid_time | bitemporal | null",
  "contract_ref": "contract/...",
  "program_id": "semanticir/...",
  "value_hash": "sha256:<canonical output>",
  "value_ref": "runtime-value/<hash-or-local-ref>",
  "freshness": "fresh | stale | unknown | provisional",
  "temporal_coordinates": null,
  "evidence_links": []
}
```

Cache observations should expose hashes, refs, fragment, axis, and freshness.
They should not expose raw sensitive inputs by default.

---

## 7.8 TEMPORAL Gate 3 Phase 1 Guard

Current Stage 3 policy:

```text
load_accept_phase1_pre_live_refuse
```

Meaning:

- Load may accept a well-formed TEMPORAL `.igapp/` for inspection,
  descriptor checks, and compatibility reporting.
- Load must validate `manifest.contract_index` against the contract artifact.
- Phase 1 implementation is approved only for `History[T]` valid-time reads
  through an abstract proof-local or non-Ledger TBackend adapter.
- Evaluate must still refuse live reads until post-lib-prep regression/safety
  review passes and an explicit live-read addendum authorizes opening the gate.
- Production cache remains closed; only TEMPORAL cache-key schema validation is
  approved.
- Ledger package binding, Ledger reads/writes/replay, BiHistory, stream/OLAP
  executors, and parser syntax changes remain closed.

### Phase 1 Lib Boundary

S3-R16 names the current proof-local implementation boundary:

```text
IgniterLang::TemporalExecutor::Phase1
```

This is an implementation boundary, not a language semantic. It does not add
parser syntax, SemanticIR node kinds, cache behavior, Ledger binding, or a
general temporal executor contract.

Required construction default:

```ruby
IgniterLang::TemporalExecutor::Phase1.new(
  backend: proof_local_memory_backend,
  gate3_authorized: false
)
```

`gate3_authorized: false` is the required default. A default-constructed
executor must refuse evaluation before any backend read. Setting
`gate3_authorized: true` is still not a deployment authorization by itself; it
is only valid inside proof-local checks or after a separate Architect live-read
decision addendum.

The lib boundary guard order is:

```text
approval_token
  -> gate_state
  -> scope
  -> TEMPORAL cache-key schema
  -> execution kernel
```

The boundary must build or attach one composed CompatibilityReport-shaped
result for each evaluation path. It must validate the ExecutorApprovalToken
before the gate-state check, and the token `authority_ref` must exactly match
the Gate 3 decision authority:

```text
architect-supervisor://igniter-lang/gates/gate3/runtime-temporal-executor/restricted-history-valid-time-v0/2026-05-09
```

The current lib boundary is proof-local Phase 1 only:

```text
allowed: History[T] valid_time, history_read, read_as_of(as_of)
closed: Ledger, BiHistory, stream, OLAP, writes, production cache, parser changes
```

Machine-readable pre-live guard in `compatibility_metadata.json` may retain the
existing load/evaluate split:

```json
{
  "runtime_execution": {
    "status": "approved_restricted_pre_live_blocked",
    "guard_policy": "load_accept_phase1_pre_live_refuse",
    "guard_at": "evaluate",
    "load": {
      "decision": "accept_for_inspection",
      "requires_contract_index": true
    },
    "evaluate": {
      "decision": "refuse_until_pre_live_conditions_pass",
      "reason_code": "runtime.temporal_pre_live_conditions_unmet"
    }
  }
}
```

TEMPORAL load refusal gates include:

```text
L-T1  missing manifest.contract_index for a TEMPORAL contract
L-T2  manifest fragment disagrees with contract fragment
L-T3  manifest axes disagree with temporal access nodes
L-T4  required capabilities disagree with escape_boundaries/node caps
L-T5  TEMPORAL contract advertises CORE cache hint
L-T6  TEMPORAL entry omits explicit temporal coordinates
```

TEMPORAL evaluate refusals include:

```text
runtime.temporal_execution_unsupported
runtime.temporal_capability_missing
runtime.executor_approval_missing
runtime.executor_approval_malformed
runtime.executor_approval_signature_invalid
runtime.executor_approval_authority_untrusted
runtime.executor_approval_expired
runtime.executor_approval_revoked
runtime.executor_approval_wrong_gate
runtime.executor_approval_wrong_scope
runtime.executor_approval_artifact_mismatch
runtime.executor_approval_contract_mismatch
runtime.executor_approval_capability_mismatch
runtime.executor_approval_evidence_missing
runtime.temporal_gate3_closed
runtime.temporal_pre_live_conditions_unmet
runtime.temporal_scope_exclusion
runtime.temporal_cache_schema_mismatch
```

`runtime.temporal_scope_exclusion` is the canonical refusal when an artifact
reaches the TEMPORAL executor but is outside the approved Phase 1 scope:

| Incoming surface | Refusal |
| --- | --- |
| CORE contract reaches `TemporalExecutor` | `runtime.temporal_scope_exclusion` |
| STREAM contract or `stream_nodes` reach `TemporalExecutor` | `runtime.temporal_scope_exclusion` |
| OLAP temporal/multidimensional surface reaches `TemporalExecutor` | `runtime.temporal_scope_exclusion` |
| `BiHistory[T]` / bitemporal axis reaches `TemporalExecutor` | `runtime.temporal_scope_exclusion` |
| Ledger write/replay/compact surface reaches temporal executor path | `runtime.temporal_scope_exclusion` |
| Unknown temporal surface reaches `TemporalExecutor` | `runtime.temporal_scope_exclusion` |

Proof-local lib aliases from early S3-R16 summaries are diagnostic aliases only;
new emissions should use the canonical code:

| Legacy/narrow code | Canonical code |
| --- | --- |
| `runtime.non_temporal_not_covered` | `runtime.temporal_scope_exclusion` |
| `runtime.temporal_executor_bihistory_excluded` | `runtime.temporal_scope_exclusion` |
| `runtime.temporal_executor_core_refusal` | `runtime.temporal_scope_exclusion` |

The Phase 1 check ordering is:

```text
load validation
  -> composed CompatibilityReport evaluation_readiness
  -> approval token validation
  -> Gate 3 state check
  -> temporal scope check
  -> TEMPORAL cache-key schema check
  -> artifact guard
  -> executor/TBackend call
```

Every refusal before the final step has a no-live-call invariant:

```text
temporal_executor_call_attempted == false
live_tbackend_call_attempted == false
ledger_call_attempted == false
cache_call_attempted == false
```

### AT-1..AT-12 Summary

Phase 1 live reads require all acceptance conditions from the Gate 3 request:

| AT | Runtime requirement |
| --- | --- |
| AT-1 | `CompatibilityReport.runtime_enforced == true` explicitly for Phase 1. |
| AT-2 | CompatibilityReport is one composed production report. |
| AT-3 | RuntimeMachine checks `evaluation_readiness` before executor/cache/TBackend. |
| AT-4 | ExecutorApprovalToken validates all PROP-030 fields. |
| AT-5 | Gate 3 state is checked independently of token presence. |
| AT-6 | TEMPORAL cache-key schema is checked before cache or backend access. |
| AT-7 | BiHistory artifacts refuse; no live bitemporal evaluation. |
| AT-8 | No Ledger write, append, replay, or compact operation is called. |
| AT-9 | Trusted authority ref is recorded in the Architect decision record. |
| AT-10 | Every authorized live History read emits `temporal_read_observation`. |
| AT-11 | Stage 1/2 and S3-R7..R10 regression proof chain remains PASS. |
| AT-12 | TEMPORAL executor refuses CORE/out-of-scope artifacts before evaluation. |

Approved Phase 1 scope:

```text
History[T] + valid_time + history_read + read_as_of(as_of: DateTime)
```

Closed scopes:

```text
Ledger package binding
Ledger reads through package code
Ledger write/append/replay/compact/subscribe
BiHistory[T] / at(vt:, tt:)
stream executor
OLAP executor
invariant persistence
production RuntimeMachine cache/memoization
parser coordinate syntax
MCP / mesh temporal routing
```

## 7.9 Temporal Read Observation

Every authorized Phase 1 read attempt emits a structured observation:

```text
temporal_read_observation
```

Minimum shape:

```json
{
  "kind": "temporal_read_observation",
  "format_version": "0.1.0",
  "observation_id": "obs/history-read/<id>",
  "operation": "history_read_as_of",
  "fragment_class": "TEMPORAL",
  "contract": {
    "contract_id": "TechnicianJobCountAt",
    "contract_ref": "contract/TechnicianJobCountAt/sha256:..."
  },
  "store": {
    "store_ref": "tbackend/memory-history/proof-local",
    "store_kind": "MemoryHistoryBackend"
  },
  "temporal": {
    "axis": "valid_time",
    "as_of": "2026-05-03T00:00:00Z",
    "valid_time": "2026-05-03T00:00:00Z"
  },
  "authorization": {
    "approval_ref": "approval/2026-05-09/gate3/history-phase1/proof-001",
    "gate_ref": "gate3-decision-record-v0#phase1-history-valid-time",
    "authority_ref": "architect-supervisor://igniter-lang/gates/gate3/runtime-temporal-executor/restricted-history-valid-time-v0/2026-05-09"
  },
  "evidence": {
    "compatibility_report_ref": "compatibility-report/history-phase1/proof-001",
    "executor_approval_token_ref": "approval/2026-05-09/gate3/history-phase1/proof-001",
    "cache_key_ref": "cache-key/temporal/history-valid-time/proof-001"
  },
  "result": {
    "status": "selected",
    "value": { "kind": "some", "value": 7 }
  },
  "persistence": {
    "mode": "proof_local",
    "persisted": false,
    "audit_receipt_ref": null
  }
}
```

Observation emission is mandatory for authorized live reads. Persistence and
durable audit receipts remain separate future work.

---

## 7.10 Proven Behaviour

Stage 1/2 runtime:

```text
PASS RuntimeMachine.load(hand_authored.igapp) -> LoadedProgram
PASS RuntimeMachine.evaluate(program, {a:3, b:4}) -> {result: 7}
PASS RuntimeMachine.checkpoint(program) -> CheckpointBundle
PASS RuntimeMachine.resume(bundle) -> LoadedProgram
PASS CompatibilityReport with schema_check
PASS schema_descriptor carried on LoadedProgram
PASS stdlib execution kernel and operator lookup
```

Stage 3 proof-local temporal/cache:

```text
PASS temporal_cache_key_proof
PASS runtime_cache_proof_local_memoization
PASS temporal_runtime_load_guard
PASS executor_approval_token_report_proof
PASS guarded_runtime_executor_approval_enforcement
PASS compatibility_report_composition
PASS temporal_read_observation_proof
PASS temporal_executor_lib_prep
```

The proof-local cache demonstrates key construction, freshness handling, and
observations. It is not production RuntimeMachine memoization.

---

## 7.11 Evidence References

| Evidence | What It Proves |
| --- | --- |
| `tracks/runtime-temporal-cache-contract-v0.md` | S3-R3-C3: cache key schema, freshness states, no production memoization |
| `tracks/runtime-cache-proof-local-memoization-v0.md` | S3-R4-C5: proof-local CORE/TEMPORAL cache behavior |
| `tracks/temporal-assembler-manifest-contract-index-v0.md` | S3-R5-C1: manifest contract index and cache schema hint |
| `tracks/temporal-runtime-load-guard-v0.md` | S3-R5-C2: load accepts for inspection, evaluate refuses unsupported TEMPORAL |
| `docs/gates/gate3-decision-record-v0.md` | S3-R13-C1: approved-restricted Phase 1 implementation; live reads still blocked until pre-live checks |
| `proposals/PROP-030A-temporal-scope-exclusion-errata-v0.md` | S3-R13-C2: `runtime.temporal_scope_exclusion` |
| `tracks/prop-005-temporal-read-observation-v0.md` | S3-R13-C3: `temporal_read_observation` envelope PASS |
| `tracks/compatibility-report-composition-v0.md` | S3-R13-C4: single composed CompatibilityReport PASS |
| `tracks/runtime-temporal-executor-lib-prep-v0.md` | S3-R16-C1: `IgniterLang::TemporalExecutor::Phase1` proof-local lib boundary PASS 17/17; live reads blocked by default |
| `experiments/stdlib_execution_kernel_stage1/` | stdlib/operator execution PASS |
