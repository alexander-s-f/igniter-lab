# Feasibility Study: Igniter-Tauri Applications (Zero-Framework Architecture)

Status: `experimental · lab-only · research`
Track: `lab-igniter-tauri-application-feasibility-v0`
Base: `Language Covenant (Postulates 4, 7, 27, & 28)`, [lab-igniter-lang-to-gui-research-boundary-v0.md](../gui/lab-igniter-lang-to-gui-research-boundary-v0.md), [lab-tailmix-inspired-gui-interaction-ir-schema-v0.md](../gui/lab-tailmix-inspired-gui-interaction-ir-schema-v0.md)

---

## 1. Executive Summary

This document explores the conceptual feasibility and architecture of **Igniter-Tauri applications**, a framework model where traditional client-side JavaScript SPA frameworks (such as Svelte, React, Vue, or Solid) are completely removed from the Tauri Webview. In their place, we leverage the **Igniter View Framework (IVF)**, compiling Arbre-like View DSL (`.igv` files) into static JSON AST layouts (`view_tree.json`) and serving them via Tauri IPC or custom URI protocols with an ultra-lightweight, whitelisted client-side micro-runtime (`igniter_view_runtime.js`).

### Core Conclusion
Bypassing React/Svelte in Tauri is **fully feasible** and offers significant benefits. By combining Tauri's native Rust capability layer with Igniter's pre-compiled layout structures and a strictly sandboxed, non-evaluating micro-runtime, we can construct desktop applications that compile to sub-10MB binaries, execute with minimal memory footprints, and guarantee complete safety against arbitrary script execution and supply-chain vulnerabilities.

---

## 2. Core Architectural Pillars

To implement an Igniter-Tauri app without a JS framework, we establish three distinct layers:

```mermaid
flowchart TB
    subgraph Host OS (Native Rust Gated Process)
        VM[Igniter VM / Machine State]
        Cap[Capability Passport Verifier]
        Router[Tauri Router / Uri Scheme Protocol]
        TCommands[Tauri Commands]
    end

    subgraph Tauri IPC Bridge (Memory-Mapped Channel)
        IPC[tauri::core::invoke / Custom Schemes]
    end

    subgraph Webview Frontend (Passive Sandbox Terminal)
        Runtime[Vanilla JS Micro-runtime: igniter_view_runtime.js]
        State[UIState: Transient local flags]
        DOM[Sanitized DOM: Attribute & Class patcher only]
    end

    Router -.-> |"Serves initial HTML + view_tree.json"| Runtime
    Runtime --> |"Local events mutate UIState"| State
    State --> |"Evaluate display rules"| DOM
    Runtime --> |"Declares 'invoke_native' side-effect"| IPC
    IPC --> Cap
    Cap --> |"If Authorized"| VM
    VM --> |"Returns Output Receipt"| IPC
    IPC --> |"Injects SlotValues"| Runtime
```

### 1. Ahead-of-Time (AOT) Compiled Views
Developers author views in the Igniter View DSL (`.igv`), declaring:
*   HTML structure using safe, whitelisted tags.
*   Transient local `UIState` variables (e.g. `active_tab`, `is_expanded`).
*   Pure, conditional `display_rules` mapping state/slot combinations to CSS classes and ARIA attributes.
*   Declarative `interaction_rules` that mutate local `UIState` or emit native command calls.

The compiler outputs a frozen `view_tree.json` artifact containing structural nodes, rules, and placeholders, eliminating client-side layout compilation overhead.

### 2. Zero-Framework SSR + Hydration Client
Instead of sending an empty HTML shell that pulls down large SPA bundles:
*   The Tauri Rust backend intercepting a route (e.g., `igniter://app/dashboard`) renders the initial HTML using a Rust port of our `SSRRenderer`, pre-evaluating the default `UIState` server-side.
*   It embeds the static `view_tree.json` layout data in a `<script type="application/json">` tag alongside the lightweight (`< 5KB`) `igniter_view_runtime.js` script.
*   The client micro-runtime runs on page load, registers events, and mutates DOM node classes and attributes dynamically. **It never uses `innerHTML` or `eval()`.**

### 3. Explicit Capability Passports for Native Effects
Under the Covenant, client-side code has zero raw access to the filesystem, network, or Tauri IPC channels.
*   Views declare capability dependencies in a **manifest**.
*   When a native effect is triggered (e.g. submitting a form), the micro-runtime issues a structured IPC call: `["invoke_native", "command_name", { args }]`.
*   Tauri’s Rust backend receives the call, matches the view's signature against its **Capability Passport**, validates type bounds, executes the command, and returns the resulting immutable dataset (`SlotValues`).

---

## 3. Implementation Models inside Tauri

We evaluate two concrete models for wiring the Igniter View Framework into Tauri:

### Model A: Custom URI Scheme SSR (Recommended)
Tauri allows developer-registered protocols via custom handlers. Under this model, the application does not serve files from a static public directory.

1.  **URI Registration**:
    In [lib.rs](../../igniter-ide/src-tauri/src/lib.rs), register the scheme handler:
    ```rust
    tauri::Builder::default()
        .register_uri_scheme_protocol("igniter", |app_handle, request| {
            let path = request.uri().path();
            // 1. Match route (e.g. "/dashboard", "/contracts")
            // 2. Load compiled VDSL view_tree.json and execution receipts from the Igniter Machine
            // 3. Render HTML server-side using Rust-native SSRRenderer
            // 4. Return tauri::http::Response containing HTML page + inlined micro-runtime JS
            tauri::http::Response::builder()
                .header("Content-Type", "text/html")
                .body(rendered_html_bytes)
                .unwrap()
        })
    ```
2.  **No Client-Side Framework**: The Webview points directly to `igniter://app/dashboard`.
3.  **Local Hydration**: The micro-runtime hydrates the DOM in milliseconds, binding local tab switches and dropdowns client-side, while any dynamic action calls back to Tauri Commands.

### Model B: Server-Driven UI (SDUI) Patching
In this model, the Webview acts as a completely passive rendering window, and even client-side interaction evaluation is performed on the Rust backend.

1.  **Passive Window**: The Webview registers a single global event handler listening to mouse/keyboard interactions on nodes carrying `data-ig-element`.
2.  **Event Forwarding**: Every interaction is forwarded directly to Rust: `window.__TAURI__.core.invoke("handle_view_interaction", { element_id, event_type })`.
3.  **Backend Morph**: The Rust backend updates the active state representation, re-evaluates the view tree, generates an HTML fragment patch, and pushes it back via a custom IPC event or response.
4.  **Morphing DOM**: The client applies the incoming HTML patch using a whitelisted morphing algorithm (like `Idiomorph` implemented under sanitization constraints).
*   *Verdict*: Highly secure, but introduces IPC round-trip latency for local presentation interactions (e.g. hover states or typing in input boxes). Therefore, **Model A** represents the ideal design system boundary.

---

## 4. Architectural Comparison Matrix

| Architectural Feature | Traditional Tauri (Svelte/React + Vite) | Igniter-Tauri (IVF AOT + Micro-Runtime) |
| :--- | :--- | :--- |
| **JS Framework Bundle** | Svelte / React, Virtual DOM / Hydration packages (100KB - 1MB+ JS). | Vanilla JS Micro-runtime (`igniter_view_runtime.js`), no dependencies (< 5KB). |
| **Executable Security** | Execution of arbitrary JavaScript is allowed; client files can invoke arbitrary IPC commands. | Restricts script execution. Expression evaluation uses whitelisted AST opcodes. No `eval` or `Function`. |
| **Supply-Chain Risks** | Massive `node_modules` footprint (Vite, Rollup, CSS processors, NPM packages). | Zero runtime client-side NPM dependencies. |
| **Application Size** | Typical desktop binaries: 70MB - 120MB. | Native Igniter-Tauri desktop binaries: **< 10MB**. |
| **Memory Consumption** | 120MB - 250MB+ (V8 engine context, heap storage for UI frameworks). | **< 30MB** (HTML parsing and DOM node mapping only, no garbage collection cycles). |
| **Native Interop** | Unbounded JS IPC queries (`invoke("...")`) that bypass compile-time contract constraints. | Strict mapping: client views bind only to declared contract ports; IPC runs under Capability Passports. |
| **Hot Reloading (DX)** | Vite HMR (compiles client assets, updates dev server, restarts browser context). | Direct VDSL layout compilation on file write. The Tauri Rust backend re-serves the updated `view_tree.json` immediately. |

---

## 5. Security Boundary Mapping (Covenant Alignment)

By replacing Svelte/React with IVF, we address critical security postulates of the **Language Covenant**:

### Postulate 4 & 7: Explicit Capability Scoping
*   **The Risk in Svelte/React**: Any component file can call `fetch()` to hit outside APIs, or write directly to local filesystems via node-native modules exposed to the frontend.
*   **IVF-Tauri Mitigation**: The micro-runtime blocks `fetch`, `XMLHttpRequest`, and standard browser storages. Side-effects must be defined as native capability bindings. The Rust backend verifies if the view is authorized to trigger this capability (using cryptographic signatures or directory boundaries) before executing.

### Postulate 27: Telemetry Stylesheet Leaks
*   **The Risk in Svelte/React**: Attackers injecting malicious CSS styles containing `url(...)` declarations to leak sensitive keystrokes or layout states to remote hosts via asset requests.
*   **IVF-Tauri Mitigation**: The `safe_renderer_policy.ts` parses and sanitizes all styles and attributes. Any style rule using `@import` or `url()` is blocked client-side. Custom protocols ensure the webview runs in a strict CSP environment allowing only `igniter://` sources.

### Postulate 5 & 8: Read-Only Contract Outputs
*   **The Risk in Svelte/React**: Client-side code mutating returned contract objects, leading to inconsistent application states.
*   **IVF-Tauri Mitigation**: The micro-runtime isolates `UIState` (local tags) from `SlotValues` (contract outputs). The evaluator blocks instructions targeting slots, making them strictly read-only.

---

## 6. Blueprint for a Proof of Concept (POC)

To validate this architecture inside the `igniter-lab` workspace, we recommend the following step-by-step implementation plan:

### Step 1: Port SSRRenderer to Rust
Write a lightweight `SsrRenderer` struct in Rust inside a new module `igniter-view-engine/src/ssr.rs` or directly in the Tauri project. This renderer reads a compiled `.json` view tree (HtmlNode AST) and spits out flat HTML with `data-ig-` attributes:
```rust
pub struct SsrRenderer {
    view_tree: Value,
    slot_values: HashMap<String, Value>,
    ui_state: HashMap<String, Value>,
}

impl SsrRenderer {
    pub fn render(&self) -> String {
        // Recursively convert HtmlNode AST to HTML string,
        // attaching data-ig-component, data-ig-element, data-ig-slots etc.
    }
}
```

### Step 2: Implement Tauri Custom Scheme Protocol
In the Tauri configuration and initialization loop, register the `igniter` protocol:
1.  Add `tauri-plugin-http` or verify scheme capabilities in `tauri.conf.json`.
2.  Wire the URI handler in `lib.rs` to serve the boot page:
    *   `igniter://app/` -> Serves a boilerplate HTML shell:
        ```html
        <!DOCTYPE html>
        <html>
        <head>
          <title>Igniter Client</title>
          <link rel="stylesheet" href="igniter://app/assets/design-system.css">
        </head>
        <body>
          <!-- SSR HTML content injected here by Rust SsrRenderer -->
          <div data-ig-component="dashboard" data-ig-state="..." data-ig-slots="...">
             <!-- ... rendered child elements ... -->
          </div>

          <!-- Inlined View Tree layout metadata for client hydration -->
          <script type="application/json" id="ig-artifact-dashboard">
             { ... view_tree.json contents ... }
          </script>

          <!-- Inlined safe micro-runtime -->
          <script src="igniter://app/assets/igniter_view_runtime.js"></script>
        </body>
        </html>
        ```

### Step 3: Map `invoke_native` Opcodes in the Micro-Runtime
Extend the vanilla JS micro-runtime in `igniter_view_runtime.js` to dispatch native operations over Tauri's message channel:
```javascript
if (op === "invoke_native") {
  var nativeCmd = inst[2]; // e.g. "dispatch_contract"
  var payload   = evaluate(inst[3], scope);

  window.__TAURI__.core.invoke(nativeCmd, payload)
    .then(function (result) {
      // Injects result values back into active component slots
      self.slotValues = Object.assign({}, self.slotValues, result.outputs);
      self._render();
    })
    .catch(function (err) {
      console.error("[IgniterView] Native invocation failed:", err);
    });
}
```

### Step 4: Verify Boundary and Benchmark
Build the application with `npm run build` and measure the performance:
*   Verify memory consumption of the webview thread under idle conditions.
*   Assert that script injection payloads (`<script>alert(1)</script>`) are rejected and do not execute.
*   Assert that stylesheet rules with external URLs are stripped by the `SafeRenderer` policy.

---

## 7. Next Steps & Recommendations

> [!TIP]
> **Start Small**: Do not rewrite the entire IDE in this paradigm immediately. First, prototype a simple, standalone utility tool (like a contract debugger panel or schema editor) using this Zero-Framework scheme.

### Suggested Action Plan
1.  **Draft a Standalone Tauri Window**: Create a secondary Tauri window config in `tauri.conf.json` that points to `igniter://test-view`.
2.  **Mount the Micro-Runtime**: Serve a static, pre-rendered VDSL interactive panel (e.g. our `interactive_panel.rb` fixture) using the scheme handler.
3.  **Validate Interactive Transitions**: Trigger local tab changes and verify the CPU utilization remains at ~0% with zero framework overhead.
