# Lab Proof: Portability & Hardening of SlotValues Tauri Bridge

Status: `experimental · lab-only · research`
Track: `lab-tauri-ivf-slotvalues-bridge-portability-hardening-v0`
Card: LAB-TAURI-IVF-P4
Base: `lab-tauri-ivf-scoped-slotvalues-command-bridge-v0.md`

---

## 1. Context & Architectural Design

This track implements **portability hardening** and **injection security** on the scoped SlotValues Tauri native command bridge. We remove absolute development-local paths from all source files and documentation, secure the webview command bridge against malicious string escaping, and adjust non-claims definitions.

---

## 2. Portability Resolution (Path Resolver)

To prevent breaking compiles across different developer workspaces, we replaced all absolute paths with a dynamic, process-relative resolver function `resolve_workspace_path` in `commands.rs`:

```rust
pub fn resolve_workspace_path(sub_path: &str) -> std::path::PathBuf {
    let mut path = std::env::current_dir().unwrap_or_else(|_| std::path::PathBuf::from("."));
    if path.ends_with("src-tauri") {
        path.pop();
    }
    path.pop(); // Go up from igniter-ide to igniter-lab
    path.join(sub_path)
}
```

This resolver dynamically popped the execution path context to target sub-folders of the `igniter-lab` root. This resolved the following locations:
*   **View Artifact**: `igniter-view-engine/out/tabs_view_artifact.json`
*   **SSR Specimen**: `igniter-view-engine/out/tabs_ssr_output.html`
*   **JS Hydration Runtime**: `igniter-view-engine/igniter_view_runtime.js`
*   **Telemetry Receipt**: `igniter-view-engine/out/tauri_bridge_receipt.json`

---

## 3. Webview Eval Injection Hardening (TIVF-P4-8)

To block cross-site scripting (XSS) or arbitrary code execution through crafted `view_id` payloads in the command line, we implemented a dual safety guard:

1.  **Character Filter**: The Rust backend command checks `view_id` character contents. If any character is not alphanumeric, a dot, or an underscore, it triggers immediate fail-closed rejection.
2.  **JSON String Escaping**: Instead of raw string interpolation, `payload.view_id` is serialized as a JSON string literal before being inserted into the `eval` string:
    ```rust
    let view_id_json = serde_json::to_string(&payload.view_id).unwrap_or_default();
    ```
    In Javascript, this is evaluated safely as a key lookup in the registry object:
    ```javascript
    if (window.IgniterView && window.IgniterView.components[view_id_json]) {
      window.IgniterView.components[view_id_json].updateSlots(sanitized_slots);
    }
    ```

---

## 4. Verification Matrix

| Rule / Check | Requirement | Verification Status | Notes / Proof Evidence |
| :--- | :--- | :--- | :--- |
| **TIVF-P4-1** | No absolute user/home paths in docs/source | `PASS` | No user or home path literals or local-file URI strings exist in source files or P3/P4 docs. |
| **TIVF-P4-2** | `cargo check` remains PASS | `PASS` | Checked with Cargo compiler; builds cleanly. |
| **TIVF-P4-3** | Valid slot injection still PASS | `PASS` | Hydrates and updates warn banner. |
| **TIVF-P4-4** | Unknown `view_id` fails closed | `PASS` | Blocked before webview delivery. |
| **TIVF-P4-5** | Digest mismatch fails closed | `PASS` | Stricter fail-closed check enforces artifact digest match. |
| **TIVP-P4-6** | Undeclared slot key rejects payload | `PASS` | Keys compared against schema; invalid keys reject whole payload. |
| **TIVF-P4-7** | Oversized payload fails closed | `PASS` | Max string size bound at 4096 bytes. |
| **TIVF-P4-8** | JS delivery is injection-proof | `PASS` | Character validation + JSON escaping of `view_id` prevents escaping. |
| **TIVF-P4-9** | Receipt output remains bounded | `PASS` | Output path written using relative workspace path resolver. |
| **TIVF-P4-10**| CSP remains strict | `PASS` | CSP declarations unchanged. |
| **TIVF-P4-11**| No VM/trace bridge added | `PASS` | Restricts bridge to SlotValues, no contract execution triggers. |
| **TIVF-P4-12**| `igniter-lang` untouched | `PASS` | Write bounds respected. |

---

## 5. Non-Claims & Framework Authority Bounds

To align with the Language Covenant, the following limits are established:
*   **Framework Status**: The Igniter View Framework (IVF) is a lab-only research prototype. It does not claim production readiness, stable API, or portability.
*   **Webview Capabilities**: The client-side runtime has **no general filesystem or network access**.
*   **Backend Capabilities**: The `inject_slot_values` bridge has **bounded proof-local artifact read and receipt write only**. It does not authorize arbitrary file executions or VM triggers.
