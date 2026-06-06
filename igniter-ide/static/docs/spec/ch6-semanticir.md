# Ch6: SemanticIR, CompilationReport, and .igapp Artifacts

Source PROPs: PROP-019, PROP-019.1, PROP-022A, PROP-028, PROP-032
Status: synced for Stage 3 TEMPORAL boundary + PROP-032 assumptions Phase 3 (2026-05-11)
Primary evidence:

- `experiments/source_to_semanticir_fixture/` ��� Stage 1 SemanticIR golden PASS
- `experiments/temporal_semanticir_access_node/` ��� TEMPORAL SemanticIR PASS
- `experiments/temporal_assembler_boundary/` ��� TEMPORAL `.igapp/` assembly PASS
- `experiments/temporal_requirements_from_escape_boundaries/` ��� requirements derivation PASS
- `experiments/temporal_runtime_load_guard/` ��� load guard PASS
- `experiments/assumptions_proof/` ��� PROP-032 assumptions Classifier/TypeChecker/SemanticIR PASS

---

## 6.1 CompilationReport

The compiler writes a `CompilationReport` for every attempted compile,
including OOF/error cases.

```json
{
  "kind": "compilation_report",
  "format_version": "0.1.0",
  "program_id": "report/<prefix16>",
  "source_path": "source/add.ig",
  "source_hash": "sha256:<hex>",
  "pass_result": "ok | oof | error",
  "semantic_ir_ref": "<program_id> | null",
  "diagnostics": [
    {
      "rule": "OOF-P1",
      "severity": "error | warning",
      "message": "Unresolved symbol: vendor_fetch",
      "node": "compute:vendor",
      "path": "contract:VendorLookup/compute:vendor",
      "line": 12
    }
  ]
}
```

`semantic_ir_ref` is non-null only when `pass_result == "ok"`. Negative cases
produce a report and no `SemanticIRProgram`.

---

## 6.2 SemanticIRProgram

`SemanticIRProgram` is emitted only for clean programs.

```json
{
  "kind": "semantic_ir_program",
  "format_version": "0.1.0",
  "program_id": "semanticir/<prefix16>",
  "grammar_version": "0.1.0",
  "source_hash": "sha256:<hex>",
  "source_path": "source/add.ig",
  "module": "Lang.Examples.Add",
  "compilation_report_ref": "compilation_report/<prefix16>",
  "contracts": ["<ContractIR>"]
}
```

OOF diagnostics do not live in `SemanticIRProgram`; they live in
`CompilationReport`.

---

## 6.3 ContractIR

A SemanticIR contract carries the contract-level fragment class and the node
set needed by later assembly/runtime gates.

```json
{
  "kind": "contract_ir",
  "contract_ref": "contract/Add/sha256:<prefix24>",
  "contract_name": "Add",
  "specialization_of": null,
  "type_args": {},
  "fragment_class": "core | stream | temporal | escape",
  "inputs": ["<PortIR>"],
  "outputs": ["<PortIR>"],
  "nodes": ["<NodeIR>"],
  "escape_boundaries": ["<EscapeBoundaryIR>"]
}
```

`fragment_class: "oof"` is forbidden in a loadable SemanticIR contract.

For Stage 3, TEMPORAL is first-class:

```text
OOF > TEMPORAL > STREAM > ESCAPE > CORE
```

`ESCAPE` remains the legacy non-core class for surfaces not yet refined into
STREAM or TEMPORAL.

### Assumption Provenance

PROP-032 adds SemanticIR provenance metadata for already-typed assumptions.
This is descriptive evidence-chain metadata, not runtime assumption injection.

At program level, accepted typed programs that declare assumptions may carry:

```json
{
  "assumption_registry": [
    {
      "kind": "assumption_ir",
      "name": "homophily",
      "fields": {
        "kind": "heuristic",
        "statement": "People with similar beliefs interact more often.",
        "strength": 0.7,
        "source": null
      },
      "declared_in_module": "Risk.Scoring"
    }
  ]
}
```

At contract level, contracts that declare `uses assumptions NAME` carry:

```json
{
  "assumption_refs": ["homophily"],
  "nodes": [
    {
      "kind": "assumption_ref_node",
      "name": "homophily",
      "assumption_ref": "homophily",
      "type": {
        "name": "Assumption",
        "params": []
      },
      "fragment": "epistemic"
    }
  ]
}
```

OOF-A1 and TASSUMP-1 diagnostics remain outside `SemanticIRProgram`.
Blocked typed programs produce a `CompilationReport` with diagnostics and
`semantic_ir_ref: null`.

---

## 6.4 STREAM Replay Metadata Nodes

STREAM contracts lower their replay-relevant surface into explicit SemanticIR
nodes. The nodes are not a production stream executor contract; they are the
minimum metadata a loader/proof-local evaluator needs to replay a bounded
window without hidden defaults.

### `stream_input_node`

```json
{
  "kind": "stream_input_node",
  "name": "readings",
  "type": "Integer",
  "window_ref": "integer/{device_id}",
  "escape_capability": "stream_input",
  "fragment": "escape"
}
```

### `window_decl_node`

```json
{
  "kind": "window_decl_node",
  "ref": "integer/{device_id}",
  "key": "integer/{device_id}",
  "window_kind": "count",
  "size": 3,
  "on_close": "snapshot",
  "bounded": true
}
```

`window_kind`, at least one bounding coordinate such as `size`, and
`bounded: true` are required for replayable proof-local STREAM windows.

### `fold_stream_node`

```json
{
  "kind": "fold_stream_node",
  "name": "total",
  "stream_ref": "readings",
  "init": {
    "kind": "integer_literal",
    "value": 0
  },
  "fn_ref": "integer_sum_lambda",
  "bound": {
    "kind": "window_bounded",
    "window_ref": "integer/{device_id}"
  },
  "event_binding": {
    "event_ref": "event",
    "value_ref": "reading",
    "value_path": ["value"]
  },
  "result_type": {
    "name": "Integer",
    "params": []
  },
  "escape_capability": "stream_input",
  "result_fragment": "core"
}
```

`init`, `fn_ref`, `bound.window_ref`, and `event_binding.value_path` are
required metadata. Missing replay metadata is a compiler/assembler proof gap,
not a runtime default.

---

## 6.5 TEMPORAL SemanticIR Nodes

`History[T]` and `BiHistory[T]` lower to explicit temporal nodes in
SemanticIR. The read node is TEMPORAL, but the value it binds is CORE-typed.

### `temporal_input_node`

```json
{
  "kind": "temporal_input_node",
  "name": "price_history",
  "type": {
    "constructor": "History",
    "element_type": "String"
  },
  "store_ref": "sku/{sku}/price",
  "lifecycle": "durable",
  "axis": "valid_time",
  "node_fragment_class": "temporal",
  "value_fragment_class": "core",
  "required_capability": "history_read",
  "required_caps": ["history_read"],
  "fragment": "temporal"
}
```

### `temporal_access_node`

```json
{
  "kind": "temporal_access_node",
  "name": "price_at",
  "source_ref": "price_history",
  "temporal_axis": "valid_time",
  "axis_refs": ["as_of"],
  "coordinate_refs": {
    "as_of": "as_of"
  },
  "result_type": {
    "name": "Option",
    "params": [
      {
        "name": "String",
        "params": []
      }
    ]
  },
  "node_fragment_class": "temporal",
  "value_fragment_class": "core",
  "required_capability": "history_read",
  "required_caps": ["history_read"],
  "evidence_policy": "link_selected_append_observation",
  "fragment": "temporal",
  "as_of_ref": "as_of"
}
```

BiHistory uses:

```json
{
  "temporal_axis": "bitemporal",
  "coordinate_refs": {
    "valid_time": "valid_time",
    "transaction_time": "transaction_time"
  },
  "valid_time_ref": "valid_time",
  "transaction_time_ref": "transaction_time",
  "required_capability": "bihistory_read",
  "required_caps": ["bihistory_read"]
}
```

The contract also carries an `escape_boundaries` entry for the temporal
capability:

```json
{
  "name": "history_read",
  "required_caps": ["history_read"],
  "produces": ["history_access_observation"]
}
```

---

## 6.6 Assembled .igapp Contract Artifacts

The assembler writes `.igapp/` directories, not raw SemanticIR only. Stage 3
TEMPORAL assembly preserves temporal nodes as a non-compute contract artifact
section.

```text
.igapp/
  manifest.json
  compilation_report.json
  semantic_ir_program.json
  requirements.json
  compatibility_metadata.json
  contracts/
    <contract>.json
```

### `contracts/<contract>.json`

Assembled contract files separate executable compute nodes from non-compute
temporal nodes:

```json
{
  "contract_id": "HistoryAxesTest",
  "source_contract_ref": "contract/HistoryAxesTest/sha256:<prefix24>",
  "fragment_class": "temporal",
  "input_ports": [
    {
      "name": "as_of",
      "type_tag": "DateTime",
      "lifecycle": "local",
      "required": true
    }
  ],
  "output_ports": [
    {
      "name": "price_at",
      "type_tag": "Option[String]",
      "lifecycle": "session",
      "required": true
    }
  ],
  "compute_nodes": [],
  "temporal_nodes": [
    {
      "kind": "temporal_input_node",
      "name": "price_history",
      "type_tag": "History[String]",
      "axis": "valid_time",
      "node_fragment_class": "temporal",
      "value_fragment_class": "core",
      "required_capability": "history_read",
      "required_caps": ["history_read"],
      "obs_kind": "temporal_source_observation"
    },
    {
      "kind": "temporal_access_node",
      "name": "price_at",
      "source_ref": "price_history",
      "temporal_axis": "valid_time",
      "coordinate_refs": {
        "as_of": "as_of"
      },
      "required_capability": "history_read",
      "required_caps": ["history_read"],
      "obs_kind": "temporal_access_observation"
    }
  ],
  "escape_set": [
    {
      "name": "history_read",
      "required_caps": ["history_read"],
      "produces": ["history_access_observation"]
    }
  ]
}
```

`temporal_nodes` is the canonical assembled contract artifact section for
`temporal_input_node` and `temporal_access_node`. It does not imply production
runtime execution.

STREAM contract artifacts analogously preserve replay metadata in
`stream_nodes`:

```json
{
  "stream_nodes": [
    {
      "kind": "stream_input_node",
      "name": "readings",
      "type_tag": "Integer",
      "window_ref": "integer/{device_id}",
      "obs_kind": "stream_replay_metadata"
    },
    {
      "kind": "window_decl_node",
      "name": "integer/{device_id}",
      "ref": "integer/{device_id}",
      "window_kind": "count",
      "size": 3,
      "bounded": true,
      "on_close": "snapshot",
      "obs_kind": "stream_window_observation"
    },
    {
      "kind": "fold_stream_node",
      "name": "total",
      "stream_ref": "readings",
      "init": { "kind": "integer_literal", "value": 0 },
      "fn_ref": "integer_sum_lambda",
      "bound": {
        "kind": "window_bounded",
        "window_ref": "integer/{device_id}"
      },
      "event_binding": {
        "event_ref": "event",
        "value_path": ["value"]
      },
      "result_type_tag": "Integer",
      "obs_kind": "stream_replay_metadata"
    }
  ]
}
```

This section is sufficient for proof-local finite replay to avoid defaults for
window size/kind/boundedness, fold initial value/function reference, and event
payload binding. It still does not authorize a production stream executor.

---

## 6.7 Manifest Fragment Summary and Contract Index

PROP-022A Stage 3 errata adds a load-time manifest index. Contract files remain
the canonical semantic source; the manifest index is the first load-time
dispatch projection and must validate against contract files.

```json
{
  "kind": "igapp_manifest",
  "format_version": "0.1.0",
  "fragment_class": "temporal",
  "fragment_summary": {
    "fragment_classes": ["temporal"],
    "max_fragment_class": "temporal",
    "precedence_high_to_low": ["oof", "temporal", "stream", "escape", "core"]
  },
  "contracts": ["HistoryAxesTest"],
  "contract_index": {
    "HistoryAxesTest": {
      "contract_ref": "contract/HistoryAxesTest/sha256:<prefix24>",
      "contract_path": "contracts/history_axes_test.json",
      "fragment_class": "temporal",
      "temporal": {
        "axes": ["valid_time"],
        "required_capabilities": ["history_read"],
        "coordinates": [
          {
            "name": "as_of",
            "axis": "valid_time",
            "source_ref": "input:as_of",
            "type": "DateTime"
          }
        ],
        "cache_key_schema_hint": {
          "schema": "runtime-cache-key-v1",
          "fragment": "TEMPORAL",
          "axis": "valid_time",
          "coordinate_names": ["as_of"]
        }
      }
    }
  }
}
```

For BiHistory, `temporal.axes` is `["valid_time", "transaction_time"]` and
`cache_key_schema_hint.axis` is `"bitemporal"`.

`manifest.fragment_class: "mixed"` may remain as a backward-compatible package
summary for mixed bundles, but it is not authoritative for TEMPORAL load/cache
dispatch. Loaders must use `manifest.contract_index`.

---

## 6.8 requirements.json from escape_boundaries

`requirements.json` is derived from SemanticIR evidence, not static defaults.

Source of truth:

- `contracts[].escape_boundaries[].required_caps`
- `contracts[].escape_boundaries[].produces`
- temporal node axes and coordinate refs
- contract `fragment_class`

History example:

```json
{
  "capabilities": {
    "effect_kinds": ["history_access_observation"],
    "required_caps": ["history_read"]
  },
  "fragments": ["temporal"],
  "required_tbackend_caps": {
    "append_atomic": false,
    "read_as_of": true,
    "replay_enabled": false
  },
  "temporal": {
    "axes": ["valid_time"],
    "requires_valid_time": true,
    "requires_transaction_time": false,
    "requires_replay": false,
    "coordinate_refs": [
      {
        "axis": "valid_time",
        "node": "price_at",
        "coordinates": {
          "as_of": "as_of"
        }
      }
    ]
  }
}
```

BiHistory example:

```json
{
  "capabilities": {
    "effect_kinds": ["bihistory_access_observation"],
    "required_caps": ["bihistory_read"]
  },
  "fragments": ["temporal"],
  "required_tbackend_caps": {
    "append_atomic": false,
    "read_as_of": true,
    "replay_enabled": true
  },
  "temporal": {
    "axes": ["bitemporal"],
    "requires_valid_time": true,
    "requires_transaction_time": true,
    "requires_replay": true,
    "coordinate_refs": [
      {
        "axis": "bitemporal",
        "node": "avail_at",
        "coordinates": {
          "valid_time": "valid_time",
          "transaction_time": "transaction_time"
        }
      }
    ]
  }
}
```

`requirements.json` is a package-level capability negotiation summary. It is
not the semantic authority for temporal axes; it must agree with
`manifest.contract_index` and the contract file.

---

## 6.9 Compatibility Metadata Guard Policy

TEMPORAL `.igapp/` artifacts may load for inspection, descriptor checks, and
compatibility reporting, but production evaluation is guarded until a future
RuntimeMachine temporal executor/TBackend adapter is approved.

`compatibility_metadata.json` carries the machine-readable policy:

```json
{
  "kind": "igapp_compatibility_metadata",
  "runtime_execution": {
    "status": "unsupported",
    "guard_policy": "load_accept_evaluate_refuse",
    "guard_at": "evaluate",
    "load": {
      "decision": "accept_for_inspection",
      "requires_contract_index": true
    },
    "evaluate": {
      "decision": "refuse_temporal_contract",
      "reason_code": "runtime.temporal_execution_unsupported"
    }
  }
}
```

This guard does not authorize runtime cache, Ledger binding, live TBackend
reads, or production temporal execution.

---

## 6.10 Assembler and Load Gates

Stage 1 A1-A6 assembler gates are closed and no longer a pending spec blocker.
Stage 3 extends them with TEMPORAL manifest/load checks:

```text
L-T1  TEMPORAL contract requires manifest.contract_index entry.
L-T2  manifest temporal entry must match contract fragment_class.
L-T3  temporal axes in manifest must match temporal access nodes.
L-T4  temporal required_capabilities must match escape_boundaries/node caps.
L-T5  TEMPORAL cache_key_schema_hint must use runtime-cache-key-v1 + TEMPORAL.
L-T6  TEMPORAL entries require explicit temporal coordinates.
```

Runtime policy:

```text
load     accepts valid TEMPORAL artifacts for inspection
evaluate refuses TEMPORAL contracts without approved runtime support/caps
cache    remains disabled for production TEMPORAL execution
Ledger   remains unbound
```

---

## 6.10 Expression Nodes

### `if_expr` expression node (R190 Internal Compiler Support)

A typed `if_expr` lowers to a flat expression node in SemanticIR. It is
embedded as the `expr` field of a `compute` node when the compute declaration
uses an `if_expr` expression.

```json
{
  "kind": "if_expr",
  "condition":   { "...": "lowered condition expression" },
  "then_branch": { "...": "lowered then final expression" },
  "else_branch": { "...": "lowered else final expression" },
  "resolved_type": { "name": "Integer", "params": [] }
}
```

SemanticIR shape conventions:

- Keys are `condition`, `then_branch`, `else_branch` ��� not the TypeChecker
  stage names `cond`, `then`, `else` with branch wrappers.
- `then_branch` and `else_branch` hold the lowered final expression directly,
  without a `{ "kind": "branch", "expr": ... }` wrapper. The branch wrapper is
  a TypeChecker internal convention, not a SemanticIR node convention.
- No `deps` key on the lowered `if_expr` node. Dependency union is a TypeChecker
  evidence policy recorded at the TypeChecker stage; it is not a SemanticIR
  node field in v0.
- `resolved_type` carries the matched branch type (same type for both branches;
  see Ch3 Rule IF-v0).

Recursive lowering consistency:

```text
Every nested if_expr ��� regardless of whether it appears in condition,
then_branch, or else_branch position ��� lowers to the same
condition / then_branch / else_branch SemanticIR key convention.
```

A nested `if_expr` in the `then_branch` of an outer `if_expr` produces:

```json
{
  "kind": "if_expr",
  "condition":   { "...": "outer condition" },
  "then_branch": {
    "kind": "if_expr",
    "condition":   { "...": "inner condition" },
    "then_branch": { "...": "inner then" },
    "else_branch": { "...": "inner else" },
    "resolved_type": { "name": "Integer", "params": [] }
  },
  "else_branch": { "...": "outer else" },
  "resolved_type": { "name": "Integer", "params": [] }
}
```

Evidence: `experiments/branch_conditional_if_expr_v0_implementation_proof/` ���
28/28 PASS, R190 accepted (S3-R190-C1-A).

Non-claims:

```text
runtime/lazy branch execution is not claimed;
if_expr assembly into .igapp compute_nodes does not imply runtime evaluate support;
accepted release evidence (igniter_lang 0.1.0.alpha.1) excludes if_expr
and remains unchanged by this SemanticIR node definition.
```

---

## 6.11 Evidence References

| Evidence | What It Proves |
| --- | --- |
| `tracks/temporal-semanticir-access-node-v0.md` | S3-R3-C2: `temporal_input_node` / `temporal_access_node` in SemanticIR |
| `tracks/runtime-temporal-cache-contract-v0.md` | S3-R3-C3: CORE vs TEMPORAL cache-key contract, no production memoization |
| `tracks/temporal-assembler-boundary-v0.md` | S3-R4-C1: temporal nodes assemble into contract `temporal_nodes` |
| `tracks/prop-022a-temporal-manifest-errata-v0.md` | S3-R4-C2: dual-index manifest decision |
| `tracks/temporal-requirements-from-escape-boundaries-v0.md` | S3-R4-C3: `requirements.json` derived from `escape_boundaries` |
| `tracks/temporal-assembler-manifest-contract-index-v0.md` | S3-R5-C1: manifest `fragment_summary` + `contract_index` PASS |
| `tracks/temporal-runtime-load-guard-v0.md` | S3-R5-C2: load accepts for inspection, evaluate refuses unsupported TEMPORAL |
