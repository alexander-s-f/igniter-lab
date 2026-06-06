# Design Specification: Experimental Capability Delegation Passport System (v0)

**Card**: `LAB-STDLIB-IO-P4`
**Track**: `lab-experimental-io-capability-delegation-passport-v0`
**Route**: `EXPERIMENTAL / LAB-ONLY`
**Status**: `proposed`

---

## 1. Design Stance and Motivation

In the Igniter Language Covenant, computations must satisfy explicit lifecycle, capability, and effect constraints. In the multi-contract space:
- Runtimes must ensure that when a contract invokes another contract (either via explicit call syntax or form-directed dispatch), capabilities are explicitly delegated.
- Under the **non-escalation policy**, a called contract (callee) cannot execute with more capabilities or permissions than those explicitly granted by the calling contract (caller).
- Capabilities must be attenuated (restricted) dynamically down the call stack to satisfy the principle of least privilege.
- Any attempt to bypass the delegation chain, escalate permissions, or escape sandboxes must fail closed at the boundary.

This document specifies a playground-local **minimum artifact passport boundary** configuration to verify capability delegation and composition algebra.

---

## 2. Artifact Passport Schema

An **artifact passport (evidence/compatibility metadata)** is a JSON-serialized configuration that defines the execution context, identities, and active capability grants for a contract session.

### Schema JSON Structure

```json
{
  "runtime_implementation_id": "ivm.ruby.v0",
  "backend_implementation_id": "none",
  "consumer_surface_id": "igniter-lab",
  "surface_dimension": "runtime",
  "artifact_kind": "igapp_dir",
  "artifact_digest": "sha256:73aed09d5295e8ecdfe22736b46ef329f626245e8",
  "active_grants": {
    "io_file_read": {
      "capability_id": "cap-io-01",
      "sandbox_dir": "out/sandbox",
      "allowed_absolute_paths": [],
      "read_allowed": true,
      "write_allowed": false
    }
  }
}
```

### Schema Fields
- **`runtime_implementation_id`**: String matching the runtime engine (e.g. `"ivm.ruby.v0"`).
- **`backend_implementation_id`**: String mapping the bound temporal storage (e.g. `"none"` or `"ledger_tcp"`).
- **`consumer_surface_id`**: Identifier of the application calling the contract.
- **`surface_dimension`**: Segment indicator (e.g. `"runtime"`, `"compiler"`, `"tbackend"`).
- **`artifact_kind`**: Descriptor matching the compiled output format (canonicalized as `"igapp_dir"`).
- **`artifact_digest`**: SHA-256 digest of the contract program artifact.
- **`active_grants`**: Map of logical capability names to their active `CapabilityGrant` configs.

---

## 3. Capability Delegation Algebra

A `CapabilityGrant` represents an active authorization mapping:

$$G = \langle \text{id}, \text{resource\_type}, \text{scope}, \text{permissions} \rangle$$

Where:
- $\text{scope} = \langle \text{sandbox\_dir}, \text{allowed\_absolute\_paths} \rangle$
- $\text{permissions} = \langle \text{read\_allowed}, \text{write\_allowed} \rangle$

### The Sub-Grant Ordering Relation ($\sqsubseteq$)

A grant $G_2$ is a valid delegation of $G_1$ (denoted $G_2 \sqsubseteq G_1$) if and only if:

1. **Type Identity**:
   $$G_2.\text{resource\_type} == G_1.\text{resource\_type}$$
2. **Permission Non-Escalation**:
   $$G_2.\text{read\_allowed} \implies G_1.\text{read\_allowed}$$
   $$G_2.\text{write\_allowed} \implies G_1.\text{write\_allowed}$$
3. **Sandbox Inclusion**:
   - The resolved physical path of $G_2.\text{sandbox\_dir}$ must be equal to or a subdirectory of the resolved path of $G_1.\text{sandbox\_dir}$. That is, it must not escape the parent directory.
   - The set of allowed absolute paths is a subset:
     $$G_2.\text{allowed\_absolute\_paths} \subseteq G_1.\text{allowed\_absolute\_paths}$$

### Overlap & Composition Algebra ($\text{ESCAPE} \circ \text{ESCAPE}$)

When composing contracts sequentially or concurrently:
1. **Disjoint Capabilities**: If contract $A$ and contract $B$ have disjoint capability sets, the parent composing contract must possess the union of all capabilities:
   $$\text{Req}(A \circ B) = \text{Req}(A) \cup \text{Req}(B)$$
2. **Dynamic Delegation**: If contract $A$ calls contract $B$, $A$ must delegate a specific grant $G_{delegated}$ to $B$. The runtime checks that:
   $$G_{delegated} \sqsubseteq G_{held}$$
   Where $G_{held}$ is the active grant in $A$'s stack frame.

---

## 4. Contract-to-Contract Call Boundary Verification Rules

During virtual machine execution of a contract invocation (e.g. `OP_CALL` or form-resolved equivalent):

1. **Call Frame Isolation**: A call frame represents a closed local environment. It possesses only the input parameters and explicitly passed capability arguments.
2. **Undeclared Escalation Guard**: A callee contract cannot ambiently access capabilities from the caller's stack frame. All capabilities required by the callee must be passed as arguments.
3. **Dynamic Boundary Verification**: When callee contract $B$ starts execution:
   For each capability parameter $p_i$ of $B$ mapped to caller argument $a_i$:
   - The runtime looks up the actual `CapabilityGrant` $G_A$ bound to $a_i$ in caller $A$.
   - The callee $B$ associates $p_i$ with $G_B$ inside its frame.
   - The interpreter verifies:
     $$G_B \sqsubseteq G_A$$
   - If verification fails, the call boundary fails closed immediately with `CapabilityDelegationError`.
4. **Execution Log Telemetry**: Every boundary check writes to a dynamic receipt log mapping the delegation link from parent to child.

---

## 5. Non-Claims

This work does **not** claim:
- Mainline `igniter-lang` capability system API stability.
- Reference VM/runtime support or production-readiness.
- Support for distributed consensus protocols or cryptographically-signed authorization tokens.
