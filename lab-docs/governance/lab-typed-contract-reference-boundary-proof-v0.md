# Lab Doc: Typed Contract Reference — Boundary Proof v0

**Card:** LAB-TYPED-CONTRACT-REF-P1
**Track:** typed-contract-reference-and-stringly-call-contract-replacement-v0
**Date:** 2026-06-11
**Authority:** lab-only — proof-local model; no canon claim, no stable API, no compiler change.
**Predecessor:** LAB-CONTRACT-FORMS-P1 (SPLIT verdict; this card executes the first of the three tracks)
**Proof result:** 58/58 PASS — Verdict: **ACCEPT**

---

## 1. Problem Statement

The current `call_contract("Name", args...)` pattern has two compounding problems:

**Structural problem:** the dependency edge exists in the compiler (which sees it at type-check time for Tier 1 literals) but is invisible in source. A reader or tool inspecting source cannot enumerate what contracts a given contract depends on without compiling it.

**Typing problem:** the callee name is a string literal. It carries no module, no signature, no identity hash. Nothing prevents it from silently rotting (rename the callee contract, all callers keep compiling as Tier 2 unknowns until the pattern is split).

LAB-CONTRACT-FORMS-P1 identified "typed contract reference (`uses Other`)" as the first-priority intervention: smaller than forms, solves the stringly pain, produces a substrate forms can lower to. This document proves that the substrate is already present in SemanticIR and that a coherent proof-local model satisfies all required boundary properties.

---

## 2. Model (Proof-Local)

Four types, all proof-local — no compiler or VM changes.

### 2.1 ContractSignature

```
ContractSignature {
  contract_name : String
  module_name   : String
  modifier      : "pure" | "effect" | "query"
  inputs        : [{name: String, type: String}]
  outputs       : [{name: String, type: String}]
}
```

Constructed by reading `contracts[].modifier`, `contracts[].inputs`, `contracts[].outputs` from SemanticIR. **All fields already exist in SemanticIR** — no new emission required (A-06 PASS).

### 2.2 ContractRef

```
ContractRef {
  module_name       : String
  contract_name     : String
  source_hash       : String?             -- SHA256 prefix from manifest
  resolution_status : :pending | :resolved | :failed
  resolved_signature: ContractSignature?  -- populated after resolve!()
}

Derived:
  contract_ref : "contract/<Name>/sha256:<24-hex>"
```

**Deliberately absent:** `execute`, `runtime_dispatch`, `capability_grant`. A reference is not an invocation (D-01..D-03 PASS).

### 2.3 ContractDependency

```
ContractDependency {
  from_module         : String
  from_contract       : String
  to_ref              : ContractRef        -- must be :resolved
  call_site_node_name : String             -- the compute node in the source
}

Derived:
  to_edge_label : "M.A[node] → contract/B/sha256:..."
```

Represents one DAG edge. Extracted by scanning `nodes[]` for `expr.fn == "call_contract"` and `args[0].kind == "literal"`.

### 2.4 RefUseReceipt

```
RefUseReceipt {
  ref                : ContractRef
  site_contract      : String
  site_node          : String
  resolution_status  : :resolved | :unresolved
  resolved_signature : ContractSignature?
}
```

The static resolution receipt — proves that resolution happened and was conclusive. **No runtime field** (D-06 PASS).

---

## 3. Proof Sections and Key Findings

### A. Discovery (6/6)

| Finding | Evidence |
|---------|----------|
| Literal callee names detectable in SemanticIR AST | `args[0].kind == "literal" && type_tag == "String"` — same discriminant P10/P11 used |
| Dynamic callees (ref) distinguishable | `args[0].kind == "ref"` — Tier 2 path; typed-ref not applicable |
| Effect callee patterns classifiable as boundary violations | `modifier == "effect"` present in SIR for SideEffect |
| All ContractRef fields already in SIR | `contract_name`, `modifier`, `inputs[]`, `outputs[]` — zero new emission required |
| Stringly callee census: ≥5 literal callee names across 3 fixtures | Enumerable, classifiable, refactor-unsafe in stringly form |

### B. Positive Reference (8/8)

`Lab.TypedRef.Basic` — `Processor` calls `Validator`:
- `Validator` ContractRef resolves with module_name, contract_name, contract_ref, signature
- Signature: `pure`, 1 input (Integer), 1 output (Bool)
- Dependency edge extractable and carries source node name (`valid`)

`Lab.TypedRef.Chain` — `Step3 → Step2 → Step1`:
- Two dependency edges extracted; both resolved; DAG is acyclic (E-06)

`Lab.TypedRef.Multi` — `Composer → {Normalizer, Validator}`:
- Two edges from Composer; both targets resolved; serialized to JSON

### C. Negative Reference (8/8)

All fail-closed paths proven via Rust compiler:

| Violation | Diagnostic |
|-----------|-----------|
| Unknown callee name | `OOF-TY0`, mentions callee name |
| Effect callee in pure context | `OOF-TY0`, mentions callee name + pure constraint |
| Arity mismatch | `OOF-TY0`, mentions callee name |
| Self-recursive literal callee | `OOF-TY0` |
| Proof-local unresolved ref | `resolution_status: :failed`, not silent miss |

### D. Authority Boundary (6/6)

`ContractRef` has no `execute`, `runtime_dispatch`, or `capability_grant` method — by design, not by omission. Modifier of effect contracts is preserved in signature (not elided), so a future gate on "is this ref pointing to an effect contract?" is always possible without re-querying the compiler.

The declaring contract's fragment classification (`pure`) is unchanged by possessing a typed ref to another pure contract.

### E. Composition Boundary (6/6)

- `ContractRef` is not a `FormKind` (no form_kind attribute, no grammar production)
- `ContractRef` is not runtime `call_contract` dispatch
- **ContractRef IS a future lowering target for forms:** carries `module_name`, `contract_name`, `contract_ref`, `modifier`, `input_count` — exactly what LAB-CONTRACT-FORMS-P2 will need when lowering an invocation form to a `ContractInvocation` node
- Dependency edges are edges in the traced symmetric monoidal category graph (PROP-002): `ContractDependency.to_edge_label` = the string diagram edge label
- Chain DAG is acyclic (no self-edges at any link)

### F. Import Interaction (6/6)

Using the existing `multifile_compilation_p3/valid_cross_file_contract_call` fixture:
- Cross-file compilation succeeds; `DoubleValue` (callee.ig) and `UseDoubleValue` (caller.ig) both present in merged SIR
- File-order independence: reversed file order produces identical contract set (F-04)
- Import does not grant capability: `UseDoubleValue` remains `pure` after importing callee module
- Ambiguity model: two modules exporting same unqualified name → detectable collision → policy: diagnostic, not first-wins (F-06)

**Key limitation (documented in open gaps):** cross-module typed refs require the module table from `PROP-IMPORT-RESOLUTION-P3`. Same-module case is fully proven here; cross-module proof gates on import mainline.

### G. Trace (6/6)

- Edge label: `Lab.TypedRef.Basic.Processor[valid] → contract/Validator/sha256:...` — human-readable, tools-parseable
- Signature expansion: `{contract_name: "Validator", modifier: "pure", input_count: 1, outputs: [{type: "Bool"}]}`
- `RefUseReceipt` serializes to Hash; dependency graph serializes to JSON; round-trip stable
- `source_hash` from manifest populates `contract_ref` when available

### H. Closed Surface (6/6)

No TCP/socket, no network I/O, no canon claim, no compiler pipeline modification, no VM execution, no macro/form-system implementation.

### I. Gap Packet (6/6)

Verdict: **ACCEPT**. Full receipt in the proof runner (`GAP_PACKET` constant).

---

## 4. Data Flow (from source to typed ref)

```
.ig source file
  │
  ▼ Rust compiler (Tier 1 literal resolution — P11)
SemanticIR (JSON)
  │  contracts[].{contract_name, modifier, inputs, outputs}
  │  manifest.{source_hash}
  │
  ▼ proof-local build_contract_registry_from_sir()
ContractRef registry  { "Name" → ContractRef(resolved, signature) }
  │
  ▼ proof-local extract_dependencies()
[ContractDependency]  — DAG edges
  │
  ▼ RefUseReceipt     — per call site
  │
  ▼ to_h / JSON       — serializable evidence
```

No compiler change required in this proof. The Rust typechecker already builds an equivalent `HashMap<String, ContractRegistryEntry>` at Tier 1 (P11). The typed ref model is the **same information with an explicit type** on the reference object.

---

## 5. Open Gaps

| Gap | Status | Gate |
|-----|--------|------|
| Cross-module typed refs | Deferred | Requires module table from PROP-IMPORT-RESOLUTION-P3 |
| Visibility gating | Deferred | Requires PROP-MODULE-VISIBILITY |
| TH-2 coherence for forms | Deferred | Gates on import mainline (LAB-FORM-LAYER-THEORY-P1) |
| Gap-I Form Constructor (`form NAME → TypeTarget`) | Independent clock | LAB-FORM-CONSTRUCTOR-P1 (Covenant P27/P28) |
| `uses Contract` syntax | Successor | LANG-TYPED-CONTRACT-REF-PROP-P1 |

---

## 6. Recommendation

**ACCEPT** typed-ref substrate.

SemanticIR already carries all required fields. Proof-local model is coherent, satisfies authority boundary (ref ≠ execution), is order-independent, and serves as the future lowering target for forms (TH-1 conservativity path from LAB-FORM-LAYER-THEORY-P1).

Successor card: **LANG-TYPED-CONTRACT-REF-PROP-P1** — canon proposal for `uses Contract` syntax (or equivalent), scoping the new declaration form against P27/P28 commitment and PROP-002 algebra.

Alternate route: **LAB-CONTRACT-FORMS-P2** — PROP-Forms lineage reconciliation, which now has the typed-ref substrate as its lowering target and TH-1..TH-6 as its acceptance frame.

---

## 7. Proof Artifacts

| Artifact | Path |
|----------|------|
| Proof runner | `igniter-view-engine/proofs/verify_lab_typed_contract_ref_p1.rb` |
| Fixture: basic | `igniter-view-engine/fixtures/typed_contract_ref/basic_typed_ref.ig` |
| Fixture: chain | `igniter-view-engine/fixtures/typed_contract_ref/chain_ref.ig` |
| Fixture: multi-callee | `igniter-view-engine/fixtures/typed_contract_ref/multi_callee_ref.ig` |
| Agent card | `.agents/work/cards/governance/LAB-TYPED-CONTRACT-REF-P1.md` |
