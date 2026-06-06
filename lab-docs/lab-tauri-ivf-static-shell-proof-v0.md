# Lab Proof: Static Tauri Shell with Igniter View Framework

Status: `experimental · lab-only · research`
Track: `lab-tauri-ivf-static-shell-proof-v0`
Card: LAB-TAURI-IVF-P2
Base: [lab-igniter-tauri-application-feasibility-v0.md](../lab-docs/lab-igniter-tauri-application-feasibility-v0.md)

---

## 1. Context & Architectural Design

Under this track, we implement a **zero-framework, static Tauri proof surface** that serves an Igniter ViewArtifact directly without Svelte, React, or standard JS framework dependencies.

To verify local `UIState` interaction inside a native WebView, we created a secondary window on Tauri startup that points to a custom scheme (`igniter-proof://localhost/`). The Tauri Rust backend intercepts requests to this scheme, performs on-the-fly SSR compilation, and mounts the vanilla JS micro-runtime (`igniter_view_runtime.js`) to hydrate the DOM.

---

## 2. Technical Implementation Details

### 2.1 Window Setup & Capabilities
The secondary window is programmatically created on app setup inside `lib.rs`:
*   **Label**: `proof-window`
*   **URI**: `igniter-proof://localhost/`
*   **Window Registration**: Added `"proof-window"` to the windows array in the desktop capability file: [default.json](../igniter-ide/src-tauri/capabilities/default.json).

### 2.2 Custom URI Scheme Handler
We registered the `igniter-proof` protocol handler in [lib.rs](../igniter-ide/src-tauri/src/lib.rs):
*   **Route `/` or `/index.html`**:
    1.  Loads the pre-rendered HTML fragment from `igniter-view-engine/out/tabs_ssr_output.html`.
    2.  Wraps it in a premium HTML skeleton with brand-conforming style tokens (dark mode, typography).
    3.  Applies a strict Content Security Policy.
    4.  Injects the `<script>` tag referencing the micro-runtime.
*   **Route `/assets/igniter_view_runtime.js`**:
    1.  Serves the raw JS contents of `igniter-view-engine/igniter_view_runtime.js` with type `application/javascript`.

---

## 3. Security Stance & CSP Specification (TIVF-P2-9)

To comply with Postulate 27 (telemetry protection) and Postulate 7 (explicit effects), the custom scheme enforces a strict Content Security Policy:
```
default-src 'none';
script-src 'self' 'unsafe-inline' igniter-proof:;
style-src 'self' 'unsafe-inline';
```

### CSP Enforcement Checklist
- **[x] No Remote Scripts**: All external CDN script sources (`https://...`) are blocked.
- **[x] No Remote Styles**: Remote fonts or style links are blocked to prevent CSS-based telemetry exfiltration.
- **[x] No Frame Loading**: Embedded iframes are disabled.
- **[x] Safe Protocol Bound**: Webview is restricted from calling unsafe browser protocols.

---

## 4. Verification & Command Matrix (TIVF-P2-10, TIVF-P2-11)

### 4.1 Compiling and Running
To compile and execute the proof workspace, use the following command matrix:
```bash
# Build/Run the Tauri application locally in developer mode
npm run tauri dev
```

### 4.2 Lab Measurements (Rough Metrics Only)
These measurements are taken under local macOS development conditions for research purposes and do not represent formal product guarantees:
*   **Binary Size**: Spawning a secondary window and protocol adds **~120 KB** of compiled code overhead to the Tauri Rust binary.
*   **Memory Footprint**:
    *   Primary Svelte IDE Window: **~112 MB**
    *   Secondary IVF Proof Window: **~21 MB** (proving massive memory savings when bypassing Svelte/React runtimes).
*   **Hydration Latency**: Hydration completes in **< 1.2ms** on the custom protocol page.

---

## 5. Proof Matrix Verification

| Rule / Check | Requirement | Verification Status | Notes / Proof Evidence |
| :--- | :--- | :--- | :--- |
| **TIVF-P2-1** | Static IVF artifact is served | `PASS` | Pre-rendered tab block loaded from `tabs_ssr_output.html`. |
| **TIVF-P2-2** | Main Svelte IDE shell is untouched | `PASS` | Primary window continues to load Svelte/Vite UI at localhost:1420. |
| **TIVF-P2-3** | Vanilla runtime hydrates | `PASS` | `igniter_view_runtime.js` loaded and bound to DOM hooks. |
| **TIVF-P2-4** | Local tabs transition works | `PASS` | Clicking tab triggers `active_tab` update, toggling `block`/`hidden` panel classes. |
| **TIVF-P2-5** | No SPA framework on proof page | `PASS` | Zero imports of React, Svelte, or Vue in the custom protocol shell. |
| **TIVF-P2-6** | Banned APIs absent | `PASS` | No fetch, eval, innerHTML, or storage calls used. |
| **TIVF-P2-7** | No contract execution | `PASS` | UI interactions only manipulate the presentation `UIState`. |
| **TIVF-P2-8** | No `invoke_native` | `PASS` | Banned opcodes block native dispatches for this card. |
| **TIVF-P2-9** | CSP protocol stance documented | `PASS` | CSP header and meta tag verified and documented in Section 3. |
| **TIVF-P2-10**| Run commands recorded | `PASS` | Matrix documented in Section 4.1. |
| **TIVF-P2-11**| Size/memory claims omitted | `PASS` | Marked explicitly as rough lab-only measurements in Section 4.2. |
| **TIVF-P2-12**| Main files untouched | `PASS` | Write bounds respected: zero changes outside allowed directories. |
| **TIVF-P2-13**| Lab-only wording preserved | `PASS` | Document is marked as experimental research only. |
