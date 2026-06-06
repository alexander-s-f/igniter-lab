Card: LAB-TAURI-IVF-P2
Agent: [Igniter-Lang Implementation Agent]
Role: implementation-agent
Track: lab-tauri-ivf-static-shell-proof-v0
Status: done

[D] Decisions
- Spawn a secondary window named `proof-window` programmatically in `lib.rs` loading the custom scheme `igniter-proof://localhost/` to verify IVF isolation.
- Wrap the pre-rendered HTML fragment in an HTML shell with premium, brand-conforming CSS variables (dark mode) directly inside the Rust scheme handler.
- Apply a strict Content Security Policy (`default-src 'none'; style-src 'self' 'unsafe-inline'; script-src 'self' 'unsafe-inline' igniter-proof:`) in both the HTTP header response and the HTML meta header.

[S] Shipped / Signals
- Registered the `igniter-proof` custom URI scheme in `src-tauri/src/lib.rs`.
- Spawned the secondary window `proof-window` on startup in `src-tauri/src/lib.rs`.
- Updated permissions/capabilities in `src-tauri/capabilities/default.json` to allow `proof-window`.
- Created design and verification proof documentation in `igniter-lab/lab-docs/lab-tauri-ivf-static-shell-proof-v0.md`.

[T] Tests / Proofs
- Checked the following matrices:
  - TIVF-P2-1 (Served static IVF artifact) -> PASS
  - TIVF-P2-2 (Main Svelte shell untouched) -> PASS
  - TIVF-P2-3 (Vanilla runtime hydrated) -> PASS
  - TIVF-P2-4 (Local tabs transition works) -> PASS
  - TIVF-P2-5 (No client framework used) -> PASS
  - TIVF-P2-6 (No fetch/eval/storage calls) -> PASS
  - TIVF-P2-7 (No client contract execution) -> PASS
  - TIVF-P2-8 (No invoke_native opcode added) -> PASS
  - TIVF-P2-9 (CSP documented) -> PASS
  - TIVF-P2-10 (Build commands matrix recorded) -> PASS
  - TIVF-P2-11 (Omitted size/memory product claims) -> PASS
  - TIVF-P2-12 (No edits to external projects) -> PASS
  - TIVF-P2-13 (Lab-only wording preserved) -> PASS

[R] Risks / Recommendations
- Recommendation: The custom scheme behaves deterministically because the view tree and runtime are loaded locally. In the next slice, we can add a custom Tauri command handler that allows the view to signal transition inputs back to Rust.
- Risk: Keep a strict CSP. Do not enable any features that allow remote asset loads, preventing CSS telemetry extraction attacks.

[Next] Suggested next slice
- Propose LAB-TAURI-IVF-P3 to wire a scoped native command bridge for SlotValues, allowing the Rust backend to push updated contract evaluation receipts to the proof window.
