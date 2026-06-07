# Bounded GUI Introspection Receipt Viewer Specification
**Route**: `EXPERIMENTAL / LAB-ONLY / IDE-ONLY`  
**Status**: `experimental` · `lab-only` · `no-canon` · `no-stable-schema` · `no-performance-claim`

This specification covers the design, safety boundaries, and verification criteria for the bounded GUI introspection receipt viewer in `igniter-ide`.

---

## 1. Safety Boundary Model

The introspection receipt viewer runs in a secure sandbox without execution authority:
1. **Size Limits**: The backend command limits the receipt file size to exactly 65KB (`65536` bytes). Files larger than this ceiling fail closed.
2. **Traversal Check**: Paths are canonicalized via `std::path::Path::canonicalize` on the backend. Any attempt to read a file that is not situated within the workspace folder boundary is immediately rejected.
3. **Safe UI Rendering**: The Svelte UI uses standard curly-bracket expression bindings (`{value}`), which are auto-escaped by the template compiler. No raw HTML, script execution, or dynamic evaluation exists.
4. **Value Redaction**: Introspection receipts contain layout structural nodes, not raw `SlotValues` payloads, preventing unintended data leaks to the front-end inspector.

---

The viewer reads receipt artifacts only through the bounded
`read_introspection_receipt` command. Hot reload does not use the generic
`read_file` API, so the same canonicalization, size, and schema checks apply to
manual loads and background refreshes.

## 2. Verification Matrix (IDEV-P1)

| Check ID | Verification Goal | Method / Scenario | Expected Result | Status |
|---|---|---|---|---|
| **IDEV-P1-1** | Path Traversal Protection | Read file located outside workspace folder (e.g. system temp) | Command returns `Err` containing "Path traversal check failed" | **PASSED** |
| **IDEV-P1-2** | File Size Boundary | Read file exceeding 65KB (65536 bytes) size constraint | Command returns `Err` containing "Oversized receipt payload" | **PASSED** |
| **IDEV-P1-3** | JSON Schema Parsing | Read file with malformed JSON structure | Command returns `Err` containing "Malformed receipt JSON structure" | **PASSED** |
| **IDEV-P1-4** | Value Set Constraints | Read file with invalid domain enum (e.g. invalid containment name) | Command returns `Err` containing "Invalid containment value" | **PASSED** |
| **IDEV-P1-5** | Introspection Success Path | Read valid `scene_introspection_receipt.json` | Command returns `Ok(IntrospectionReceipt)` mapping `igniter.lab.dashboard` | **PASSED** |

---

## 3. Rust Unit Test Reference

The verification logic is tested via `cargo test` in `commands.rs`. The corresponding test outputs are shown below:

```
running 9 tests
test commands::tests::test_cross_language_hmac_test_vector ... ok
test commands::tests::test_ruby_vm_telemetry_preflight_envelope ... ok
test commands::tests::test_read_introspection_receipt_all_cases ... ok
test commands::tests::test_telemetry_history_packet_generation_and_eviction ... ok
test commands::tests::test_adapted_vm_trace_ingress ... ok
test commands::tests::test_external_trace_ingress ... ok
test commands::tests::test_mock_vm_runner_trace_ingress ... ok
test commands::tests::test_mock_session_runner_lifecycle_success ... ok
test commands::tests::test_mock_session_runner_rejections ... ok

test result: ok. 9 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0.67s
```
