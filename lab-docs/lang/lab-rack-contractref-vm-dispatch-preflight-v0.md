# Lab: ContractRef VM Dispatch Preflight (v0)

> Status: experiment-pass · lab-only · 25/25 checks PASS
> Card: LAB-RACK-P3
> Date: 2026-06-08
> Category: lang / web
> Track: lab-rack-contractref-vm-dispatch-preflight-v0
> Precedes: LAB-RACK-P2 (core contract shape proof)
> Authority: lab-only evidence — no canon claim, no stable-API surface, no production commitment

---

## Pre-v1 Language Note

All Igniter constructs in this document are drawn from accepted spec chapters
and PROPs and reflect the current spec vocabulary. They are not stable APIs.
This document is lab-only research evidence. It does not constitute canon
specification, a PROP, or a production commitment.

---

## 1. Purpose

LAB-RACK-P3 answers the question: **where exactly does ContractRef-as-handler-boundary break in
the lab compiler/VM?** The goal is not to prove "Rack works" but to produce a precise gap packet
that locates each broken layer so future work can target it directly.

**Proof axiom:** a check PASSES when it precisely characterises a gap or confirms a working
baseline. PASS does not mean "the feature works." PASS on a dispatch check means the gap is
confirmed at a specific layer.

**What this proof establishes:**

1. A single-contract HelloHandler compiles cleanly and executes correctly in the VM (`status: 200`).
2. Direct cross-contract function-call syntax (`HelloHandler(method, path)`) is rejected at the
   TypeChecker layer — the Dispatcher contract is never emitted into SemanticIR.
3. `ContractRef[A, B]` type annotation is **NOT** rejected by the parser or typechecker. It
   compiles and is represented in SemanticIR as `{ kind: "type_ref", name: "ContractRef", params:
   ["String", "Integer"] }`. The compiler treats it as an opaque structural type reference.
4. The form-dispatch mechanism (`AddInteger` form → `{ kind: "call", fn: "AddInteger" }`) preserves
   contract identity in SemanticIR IR nodes. The IR shape exists; the VM execution does not.
5. The VM compiler always executes `contracts[0]` from a multi-contract `semantic_ir_program.json`.
   There is no entrypoint selector; a multi-contract igapp never reaches its secondary contracts.
6. The VM's `OP_CALL` handler covers stdlib/builtin functions only. Any user-defined contract name
   falls through to: `"OP_CALL: Unknown/unimplemented function '<name>' with N arguments"`.

**What this proof does NOT establish:**

- ContractRef dynamic dispatch at runtime (gap confirmed — this does not work)
- Cross-contract call routing (gap confirmed — VM has no mechanism)
- A production ContractRef type in the language grammar
- Any modification to canon grammar or the igniter-lang canon

---

## 2. Proof Structure

**Proof file:** `igniter-view-engine/proofs/verify_p3_contractref_dispatch.rb`
**Fixtures:** `igniter-view-engine/fixtures/rack_core/` (3 new `.ig` fixture files)
**Reference artifact:** `igniter-compiler/out/contract_invocation_forms_semanticir_lowering_proof/positive.igapp`
**Result:** 25/25 PASS

### 2.1 Sections and Check Count

| Section | Checks | Coverage |
|---------|--------|----------|
| P3-BASELINE | 3 | P2 continuity; HelloHandler compile + VM exec |
| P3-DISPATCH | 6 | Direct call gap; ContractRef type-annotation finding |
| P3-IR | 6 | SemanticIR shape: HelloHandler, ContractRef, form-dispatch |
| P3-VM | 4 | VM exec baseline; compiler entrypoint gap; OP_CALL gap |
| P3-SURFACE | 4 | Closed-surface scan |
| P3-GAP-PACKET | 2 | Structured gap packet completeness |
| **Total** | **25** | **15 proof-matrix items covered** |

---

## 3. Gap Packet

The structured gap packet from the proof run:

### Layer: Parser
**Status:** NONE (no parser gap)

`ContractRef[A, B]` is accepted by the Igniter parser and typechecker without error.
It is compiled to a `type_ref` node in SemanticIR:
```json
{
  "kind": "type_ref",
  "name": "ContractRef",
  "params": ["String", "Integer"]
}
```
The compiler treats it as an opaque structural type reference. There is no parser-level
rejection of `ContractRef[A, B]`.

**Evidence:** `contractref_annotation.igapp` — status: ok, zero diagnostics, type_ref confirmed.

---

### Layer: TypeChecker
**Status:** GAP

Direct cross-contract function-call syntax (`HelloHandler(method, path)`) is rejected by the
TypeChecker. The call is treated as an unknown function. The Dispatcher contract is never
emitted into SemanticIR.

**Error class:** TypeChecker diagnostic (OOF-TY0 or equivalent unknown-function rule).

**Evidence:** `direct_call_attempt.ig` compilation — non-ok status, diagnostics array non-empty.

---

### Layer: SemanticIR
**Status:** PARTIAL

Form-resolved cross-contract calls ARE preserved in SemanticIR as `{ kind: "call", fn:
"ContractName" }` nodes. The IR identity survives. Example from the existing
`contract_invocation_forms_semanticir_lowering_proof` artifact:
```json
{
  "kind": "compute",
  "name": "total",
  "expr": {
    "kind": "call",
    "fn": "AddInteger",
    "args": [{"kind": "ref", "name": "a"}, {"kind": "ref", "name": "b"}]
  }
}
```
However:
- `ContractRef[A, B]` is represented as a structural `type_ref` but has no dispatch-semantic node type.
- A Dispatcher contract calling HelloHandler directly never reaches SemanticIR (TypeChecker gap blocks it).

**Evidence:** `positive.igapp` UseIntegerAdd IR node; `direct_call.igapp` absent (Dispatcher not emitted).

---

### Layer: VM Entrypoint
**Status:** GAP

The VM bytecode compiler (`igniter-vm/src/compiler.rs`, line 32) always selects `contracts[0]`
from a multi-contract `semantic_ir_program.json`:
```rust
contracts_arr.get(0).ok_or("No contracts found in semantic_ir_program")?
```
There is no entrypoint selector, no `--entry` flag, and no dispatch table. A multi-contract
program can only execute its first contract. This means even if a Dispatcher contract compiled
successfully, the VM would never reach it.

---

### Layer: VM Dispatch
**Status:** GAP

The VM's `OP_CALL` handler (`igniter-vm/src/vm.rs`, lines 387–1291) contains a large match block
over stdlib/builtin function names. User-defined contract names are not present. The fallthrough:
```rust
return Err(format!("OP_CALL: Unknown/unimplemented function '{}' with {} arguments", fn_name, arg_count));
```
Any attempt to call a user-defined contract name via `OP_CALL` returns this error.

**Evidence:** `vm.rs` line 1291; form-dispatch UseIntegerAdd → `OP_CALL "AddInteger"` → runtime error.

---

## 4. Fixture Files

| File | Purpose |
|------|---------|
| `hello_handler_standalone.ig` | Single pure contract; VM baseline (compiles + executes: status 200) |
| `direct_call_attempt.ig` | Two contracts; Dispatcher calls HelloHandler — TypeChecker gap target |
| `contractref_annotation.ig` | `input handler: ContractRef[String, Integer]` — type-annotation finding |

---

## 5. Key Findings

### Finding 1: ContractRef type-annotation is not a parser gap

`ContractRef[A, B]` compiles cleanly and emits `{ kind: "type_ref", name: "ContractRef",
params: [...] }` in SemanticIR. This is a **positive finding**: the compiler already handles
unknown parameterized type references gracefully. Future work can attach dispatch semantics
to `type_ref` nodes with `name: "ContractRef"` without grammar surgery.

### Finding 2: TypeChecker is the shallowest blocking gap for cross-contract calls

The TypeChecker rejects direct `ContractName(args)` syntax before SemanticIR is emitted.
This is the first blocking layer. Fixing this gap would require the TypeChecker to recognize
contract-to-contract call expressions and route them through a cross-contract call form.

### Finding 3: Form-dispatch is the only existing cross-contract IR path

The form system (`a + b` → `call { fn: "AddInteger" }`) IS a working cross-contract IR pathway
at the compiler level. It confirms that `kind: "call"` with `fn: "ContractName"` is the right IR
shape. The only missing layer is the VM executor recognizing user-defined names in `OP_CALL`.

### Finding 4: VM entrypoint gap is a hard structural constraint

The VM always runs `contracts[0]`. A static handler-table approach (LAB-RACK-P4) can work around
this by encoding all logic in a single contract rather than relying on VM-level multi-contract dispatch.

---

## 6. Comparison to P1 and P2

| Proof | What it proved |
|-------|----------------|
| LAB-LANG-HTTP-TYPES-P1 (41/41) | HTTP type schema + ContractRef dispatch at the Ruby proof-algebra level |
| LAB-RACK-P2 (46/46) | Static middleware pipeline shape + RackEnvAdapter + typed failures |
| **LAB-RACK-P3 (25/25)** | **Precise gap map at each compiler/VM layer for dynamic ContractRef dispatch** |

P3 does not extend P1 or P2 functionality — it maps the exact boundary between what the lab
compiler/VM can and cannot do for cross-contract dispatch.

---

## 7. Next Route

| Priority | Card | Rationale |
|----------|------|-----------|
| **HIGH** | LAB-RACK-P4: Route dispatch (static handler table) | Proves a static route-dispatch table encoded as a single contract — bypasses VM entrypoint gap and OP_CALL gap by keeping dispatch in the data-plane, not the call-frame. No ContractRef runtime needed. |
| **MEDIUM** | VM OP_CALL user-contract extension | Add a case to vm.rs OP_CALL for user-defined contract names by looking up contracts by name in the loaded semantic_ir_program and evaluating them in a new frame. Closes vm_dispatch gap. |
| **MEDIUM** | VM entrypoint selector | Add `--entry <contract_name>` flag to VM run command. Closes vm_entrypoint gap. |
| **LOW** | ContractRef dispatch semantic | Attach a dispatch semantic to `type_ref` nodes with name "ContractRef" — requires TypeChecker cross-contract call support first. |

**Recommended immediate next:** LAB-RACK-P4 (static route dispatch), because it makes
meaningful progress on the Rack track without requiring VM source changes. The static handler
table is directly expressible as pure Igniter contracts using existing VM capabilities.

---

## 8. Compact Summary

LAB-RACK-P3 precisely maps each gap layer for ContractRef-as-handler-boundary in the Igniter
lab compiler/VM. Key findings: `ContractRef[A,B]` is accepted as an opaque `type_ref` (no parser
gap); direct cross-contract call syntax is rejected at the TypeChecker (first blocking gap);
form-resolved calls preserve IR identity as `kind:call, fn:ContractName` (SemanticIR partial
path exists); the VM always executes `contracts[0]` from a multi-contract program (entrypoint
gap); and the VM `OP_CALL` handler covers only stdlib/builtins with user-contract names
producing "Unknown/unimplemented function" errors (dispatch gap). HelloHandler standalone
compiles and executes correctly (VM result: 200), confirming the single-contract baseline.
The gap packet is complete. 25/25 PASS.
