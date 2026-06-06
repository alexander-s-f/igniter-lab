# Lab Documentation: Experimental Capability-Bound I/O Candidate Proof (v0)

**Card**: `LAB-STDLIB-IO-P1`
**Track**: `lab-experimental-io-stdlib-candidate-proof-v0`
**Route**: `EXPERIMENTAL / LAB-ONLY`
**Status**: `conditional_accept_with_boundary_review`

---

## 1. Design Stance and Motivation

In the mainline Igniter design, side effects must be explicitly declared and audited (Postulate 4 and Postulate 27 of the Covenant). Under this design pressure:
- I/O operations are **not** part of pure `CORE` execution.
- Ambient accesses (e.g. standard file system reads/writes, network sockets, environment access) are strictly blocked by default.
- Every I/O operation must be accompanied by an explicit **Capability** token that specifies permitted scopes, files, and directories.
- Successful I/O operations return structured metadata packets (**Receipts** for writes, **Observations** for reads), providing lineage.

This lab-only experiment maps a Rust-based, C ABI-compatible implementation of capability-bound I/O inside `igniter-stdlib`, demonstrating safe, sandboxed, and accountable file system access.

---

## 2. Capability System Architecture

An I/O Capability is modeled as a structured JSON object passed across the FFI boundary:

```json
{
  "capability_id": "cap-io-01",
  "sandbox_dir": "out/sandbox",
  "allowed_absolute_paths": ["<redacted-explicit-host-path>/explicit_mapped.txt"],
  "read_allowed": true,
  "write_allowed": true
}
```

### Safety & Sandboxing Policies
1. **Sandbox Bound**: Any relative path is resolved relative to the designated `sandbox_dir`. The absolute resolved path of `sandbox_dir` itself **must** reside under `igniter-stdlib/out/`. Attempts to specify a sandbox directory outside of this path fail closed with `SandboxSecurityViolation`.
2. **Path Traversal Block**: Any path resolving containing `..` or `.` components is lexically cleaned and resolved. If the final path escapes the sandbox boundaries, the operation fails closed with `PathTraversalError`.
3. **Absolute Path Block**: By default, absolute paths fail closed with `CapabilityError`, preventing arbitrary file access. Absolute paths are only permitted if they are explicitly listed in the capability's `allowed_absolute_paths` array.
4. **Explicit Permissions**: Capability must carry `read_allowed: true` for read operations, and `write_allowed: true` for write operations; otherwise, the request fails closed with `CapabilityError`.

---

## 3. C ABI FFI Signatures

The standard library dynamic library exports C ABI compatible entry points. All functions accept null-terminated UTF-8 strings (`*const c_char`) and return dynamically allocated, null-terminated JSON strings (`*mut c_char`):

- `stdlib_io_read_text(path, capability) -> *mut c_char`
- `stdlib_io_write_text(path, content, capability) -> *mut c_char`
- `stdlib_io_read_json(path, capability) -> *mut c_char`
- `stdlib_io_write_json(path, value_json, capability) -> *mut c_char`
- `stdlib_io_exists(path, capability) -> *mut c_char`
- `stdlib_io_list_dir(path, capability) -> *mut c_char`
- `stdlib_io_free_string(ptr)` — Releases the memory allocated by Rust for the returned C-string.

---

## 4. Return Taxonomy (Results, Receipts, and Observations)

### Success Monad
- **Read Result**: Returns the file content along with observation metadata (bytes read, FNV-1a content digest, and capability ID).
  ```json
  {
    "ok": "file content here",
    "metadata": {
      "path": "test.txt",
      "bytes_read": 36,
      "content_digest": "d81c30dc283f3108",
      "capability_id": "cap-io-01"
    }
  }
  ```
- **Write Receipt**: Returns metadata mapping the write consequence.
  ```json
  {
    "ok": {
      "path": "test.txt",
      "bytes_written": 36,
      "content_digest": "d81c30dc283f3108",
      "timestamp": 1780660731,
      "capability_id": "cap-io-01"
    }
  }
  ```

### Failure Monad
- Returns a structured error dictionary outlining the failure mode:
  ```json
  {
    "err": {
      "error_type": "FileNotFound" | "CapabilityError" | "PathTraversal" | "IoError" | "InvalidJson",
      "message": "Error details description string",
      "path": "test.txt"
    }
  }
  ```

---

## 5. Verification Results

Running the verification script `ruby proofs/experimental_io_stdlib_candidate_proof.rb` verifies 21 assertions checking the 12 proof matrices:

| Check | Matrix ID | Scope Checked | Status |
|---|---|---|---|
| `IO-1` | `IO-1.signature_exists` | `stdlib/io.ig` signature presence | **PASS** |
| `IO-2` | `IO-2.module_exists` | `src/io.rs` module presence | **PASS** |
| `IO-3` | `IO-3.read_text_sandbox` | Relative read inside sandbox + metadata | **PASS** |
| `IO-4` | `IO-4.write_text_sandbox` | Relative write inside sandbox + receipt | **PASS** |
| `IO-5` | `IO-5.read_json_success` | Parsing and returning JSON objects | **PASS** |
| `IO-6` | `IO-6.read_json_fails_structured` | Invalid JSON on reads and writes fails structured | **PASS** |
| `IO-7` | `IO-7.missing_file_structured` | Missing file returns structured `FileNotFound` | **PASS** |
| `IO-8` | `IO-8.path_traversal_blocked` | Path traversal (e.g. `../`) returns `PathTraversal` | **PASS** |
| `IO-9` | `IO-9.abs_path_fails_closed` | Absolute path block by default / succeeds when mapped | **PASS** |
| `IO-10` | `IO-10.read_restricted` | Permission restrictions and malformed capability JSON | **PASS** |
| `IO-12` | `IO-12.closed_surface_integrity` | Mainline directory safety verification (no external edits) | **PASS** |

---

## 6. Non-Claims
As per the IDD Agent Protocol, this work does **not** claim:
- Mainline `igniter-lang` stdlib API stability.
- Reference VM/runtime native support.
- Production-readiness or general portability guarantees.
- Network socket I/O capabilities.

---

## 7. Recommendations
With all 21 assertions passing, we recommend a `conditional_accept_with_boundary_review` route to proceed with:
1. Formalizing the capability delegation and lifetime algebra (Covenant Postulate 4/19).
2. Designing the compiler-side effect surface validation (CSM / Gap-D).
