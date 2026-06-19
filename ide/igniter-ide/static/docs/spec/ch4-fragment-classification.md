# Ch4: Fragment Classification

Source PROPs: PROP-003, PROP-020, PROP-023, PROP-028
Status: synced for Stage 3 TEMPORAL boundary (2026-05-08)
Proof:

- `experiments/classifier_pass_proof/` ��� CORE/OOF/stream + TEMPORAL classifier cases
- `experiments/typechecker_proof/` ��� History/BiHistory temporal diagnostics
- `experiments/temporal_semanticir_access_node/` ��� TEMPORAL SemanticIR nodes

---

## 4.1 Fragment Classes

Stage 3 refines the original `CORE | ESCAPE | OOF` model. Known temporal and
stream surfaces now have named fragment classes instead of being collapsed into
generic ESCAPE.

```text
CORE      Decidably valid, terminating, deterministic.
          No external capability required.

STREAM    Requires a stream/window capability.
          A bounded fold may produce a CORE value, but the contract remains
          stream-involved.

TEMPORAL  Requires TBackend read capability under explicit temporal
          coordinates. Produces CORE-typed values, but the contract remains
          temporal.

OOF       Out-of-fragment violation.
          Compile-time rejection; never reaches loadable SemanticIR.
```

Refined ordering:

```text
OOF > TEMPORAL > STREAM > CORE
```

`ESCAPE` remains a legacy/coarse compatibility label for external surfaces that
have not yet been refined into `STREAM` or `TEMPORAL`. New Stage 3 rules should
classify known stream and temporal constructs directly.

Classification remains static and decidable; it runs before or at the
classifier/typechecker boundary and does not depend on runtime values.

---

## 4.2 Node Class vs Value Class

Stage 3 distinguishes three related facts:

```text
node_fragment_class
value_fragment_class
contract_fragment_class
```

For a temporal read:

```text
node_fragment_class  = temporal
value_fragment_class = core
contract_fragment_class includes temporal
```

The node requires a TBackend capability, but the symbol it binds is an ordinary
typed value. Downstream pure computes that consume the bound value remain CORE
nodes. The containing contract remains TEMPORAL because evaluating it depends
on temporal coordinates.

Example classification:

```text
read price_history: History[Money] ...
compute taxed = price_at.value * tax_rate

read price_history       node_fragment_class: temporal
price_history symbol     value_fragment_class: core
compute taxed            node_fragment_class: core
contract                 contract_fragment_class: temporal
```

---

## 4.3 Construct Classification Table

| Construct | Node class | Bound value class | Contract impact | Notes |
|-----------|------------|-------------------|-----------------|-------|
| `input` | CORE | CORE | CORE | Always |
| `const` | CORE | CORE | CORE | Always |
| pure `compute` | CORE | CORE | max deps by value class | No external capability |
| `output` | source node class or CORE | source value class | no new class | Output itself does not add capability |
| `stream name: T` | STREAM | STREAM handle | STREAM | Unbounded source |
| bounded `fold_stream(...)` | STREAM | CORE | STREAM | Window closes stream to a value; no `fold_temporal` analog |
| direct stream value access | OOF | none | OOF | `OOF-S4` |
| `read History[T]` with explicit `as_of` | TEMPORAL | CORE | TEMPORAL | Requires `history_read` |
| `read BiHistory[T]` with explicit `vt`/`tt` | TEMPORAL | CORE | TEMPORAL | Requires `bihistory_read` |
| temporal `olap_access_node` | TEMPORAL | CORE | TEMPORAL | OLAP-backed temporal view |
| generic external `read` not known temporal/stream | ESCAPE | ESCAPE or receipt | ESCAPE | Legacy/coarse category |
| `escape Name` | ESCAPE | ESCAPE or receipt | ESCAPE | Explicit boundary |
| `fold(Collection[T], ...)` | CORE | CORE | CORE | Bounded collection |
| `T where ��` decidable | CORE | CORE | CORE | Refinement type |
| `T where ��` arbitrary predicate | ESCAPE | ESCAPE | ESCAPE | `refinement_predicate` |
| `||` composition with external branch | branch-local | branch-local | external class stays local | Parallel branch isolation |
| `>>` sequential composition with external dependency | propagated | propagated | propagated | Sequential chain depends on prior capability |
| unknown DSL extension | OOF | none | OOF | Default |

Legacy proof fixtures may still serialize stream surfaces as `escape`; the
semantic class for known stream constructs is `STREAM`.

---

## 4.4 History and BiHistory Rules

### History

`History[T]` access is TEMPORAL only when it has an explicit valid-time
coordinate.

```text
read History[T] + as_of: DateTime
  node_fragment_class  = temporal
  value_fragment_class = core
  required_capability  = history_read
  temporal_axis        = valid_time
```

Missing or invalid coordinates are OOF:

```text
OOF-TM1 / OOF-H1   History read missing as_of
OOF-TM3 / OOF-BT1  History as_of is not DateTime
```

### BiHistory

`BiHistory[T]` access is TEMPORAL only when both valid-time and
transaction-time coordinates are explicit.

```text
read BiHistory[T] + vt: DateTime + tt: DateTime
  node_fragment_class  = temporal
  value_fragment_class = core
  required_capability  = bihistory_read
  temporal_axis        = bitemporal
```

Missing or invalid axes are OOF:

```text
OOF-TM4 / OOF-BT2  BiHistory read missing valid_time / vt
OOF-TM5 / OOF-BT3  BiHistory read missing transaction_time / tt
OOF-TM6 / OOF-BT4  BiHistory axis is not DateTime
```

`bitemporal_read` may appear as a compatibility alias, but the canonical
capability is `bihistory_read`.

---

## 4.5 Parser Coordinate Syntax Status

The source spelling for temporal coordinates is not yet canonical.

Examples such as:

```text
read price_history: History[Money] from prices as_of as_of
read avail_history: BiHistory[String] from avail vt valid_time tt transaction_time
```

are explanatory pressure, not frozen grammar. Current Stage 3 proofs use
hand-authored ParsedProgram/ClassifiedProgram fixtures and typed lowering. A
future parser-syntax proposal must choose canonical spelling and negative parse
rules before these examples become accepted syntax.

This does not weaken the semantic rule: any accepted temporal read surface must
provide explicit typed temporal coordinates.

---

## 4.6 Named External Capability Vocabulary

The external capability vocabulary is closed for known names:

```text
stream_input             stream source capability
history_read             History[T] valid-time read
bihistory_read           BiHistory[T] valid-time + transaction-time read
olap_point_read          OLAP-backed temporal/multidimensional read
refinement_predicate     arbitrary refinement predicate
causal_clock             logical/vector clock operation
platform_extension_code  FFI / host interop / external library calls
soft_real_time           deadline annotations
```

Unknown capability names are OOF unless a proposal explicitly adds them.

---

## 4.7 OOF Detection Rules

Core classifier/typechecker OOF rules:

```text
OOF-P1   Unresolved symbol
OOF-P2   Pipeline operator (|>) used inside contract body
OOF-P4   Compute cycle
OOF-CE4  ConfidenceLabel value used as Bool
OOF-OS2  Alert emitted without evidence links
```

Stream rules:

```text
OOF-S1   fold_stream without bounded window
OOF-S2   stream declaration/use without matching window
OOF-S3   ESCAPE construct inside fold_stream accumulator
OOF-S4   stream value accessed outside fold_stream
```

Temporal rules:

```text
OOF-TM1  Temporal read without explicit temporal coordinate
OOF-TM2  Temporal read uses ambient time
OOF-TM3  History coordinate is not DateTime
OOF-TM4  BiHistory read missing valid_time / vt
OOF-TM5  BiHistory read missing transaction_time / tt
OOF-TM6  BiHistory axis is not DateTime
OOF-TM7  TEMPORAL construct inside CORE-required lambda/body
OOF-TM8  TEMPORAL read without required TBackend capability
OOF-TM9  TEMPORAL contract declared/cacheable as CORE
```

Compatibility aliases currently proven:

```text
OOF-H1   -> OOF-TM1
OOF-BT1  -> OOF-TM3
OOF-BT2  -> OOF-TM4
OOF-BT3  -> OOF-TM5
OOF-BT4  -> OOF-TM6
```

Severity:

- `error` blocks SemanticIR emission or loadable artifact construction.
- `warning` may pass through as a diagnostic when a rule explicitly permits it.

---

## 4.8 ClassifiedProgram Shape

Classifier output records contract and declaration fragments. TEMPORAL reads
also carry node/value split metadata.

```json
{
  "kind": "classified_program",
  "contracts": [
    {
      "name": "HistoryAxesTest",
      "fragment_class": "temporal",
      "symbols": [
        {
          "name": "price_history",
          "kind": "temporal_read",
          "fragment_class": "core"
        }
      ],
      "declarations": [
        {
          "kind": "read",
          "name": "price_history",
          "fragment_class": "temporal",
          "node_fragment_class": "temporal",
          "value_fragment_class": "core",
          "required_capability": "history_read",
          "temporal_axis": "valid_time"
        }
      ],
      "oof_log": []
    }
  ]
}
```

Contract `fragment_class` is the maximum node class under the refined fragment
ordering. The symbol bound by a temporal read is still a CORE value.

---

## 4.9 Propagation Rules

```text
1. Input/Const              -> node CORE, value CORE
2. Stream source            -> node STREAM, value STREAM handle
3. Bounded fold_stream      -> node STREAM, value CORE, contract STREAM
4. History/BiHistory read   -> node TEMPORAL, value CORE, contract TEMPORAL
5. Pure compute             -> node max(value classes of deps)
6. Output                   -> does not add capability; reflects source value
7. One OOF dep              -> dependent compute/output is OOF
8. Sequential composition   -> external class propagates through dependency
9. Parallel composition     -> external class remains branch-local unless joined
```

Contract class:

```text
contract_fragment_class = max(node_fragment_class*)
```

using:

```text
OOF > TEMPORAL > STREAM > CORE
```

Temporal value-flow rule:

```text
TEMPORAL read node -> CORE value -> downstream pure compute remains CORE
```

The contract remains TEMPORAL because the read node is present.

---

## 4.10 Decidability

Fragment classification remains decidable:

- Per declaration: local kind/type lookup plus dependency references.
- Per contract: graph traversal/topological propagation.
- Cycle detection: OOF-P4 via DFS or equivalent DAG check.
- Total complexity remains linear in program size plus dependency graph size.

Temporal coordinate type validation occurs at the classifier/typechecker
boundary. It does not require runtime values.
