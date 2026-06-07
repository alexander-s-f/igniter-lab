Card: LAB-TAURI-IVF-P19
Category: ide
Agent: [Igniter-Lang Research / Implementation Agent]
Role: research-implementation-agent
Track: lab-tauri-ivf-live-trace-bridge-design-and-session-boundary-v0
Route: EXPERIMENTAL / LAB-ONLY
Status: done

[D] Decisions
- Designed a transient, demand-driven session manager lifecycle that generates dynamic session tokens and transaction IDs per execution, closing the session immediately upon receipt or timeout.
- Developed the Producer/Signature Replacement Plan using HMAC-SHA256 signatures derived from the transient session token to prevent unauthorized local telemetry injection.
- Defined sourcing and validation policies for transaction_id and contract_id against current workspace states.
- Established strict redaction-before-UI and local file read boundaries.
- Formulated absolute prohibitions against TCP/UDP ports, watchers, and background listeners.
- Confirmed a fail-closed status vocabulary schema.
- Authorized the implementation of a mock session runner proof in phase P20.

[S] Shipped / Signals
- Created durable design document: lab-docs/ide/lab-tauri-ivf-live-trace-bridge-design-and-session-boundary-v0.md.
- Created card receipt: .agents/work/cards/ide/LAB-TAURI-IVF-P19.md.

[T] Tests / Proofs
- verified: Reviewed the agent mapping file and current Tauri commands.rs implementations to ensure the proposed session manager cleanly overlays the existing mock-runner-dispatch pipeline.
- verified: Validated the HMAC-SHA256 signature sequence analytically to guarantee compatibility with Ruby's openssl library and Rust's ring or hmac crates.

[R] Risks / Recommendations
- Recommendation: Proceed directly to phase P20 to implement the mock session runner proof, validating the token exchange and HMAC signature checking.
- Risk: Ensure that the session token is securely purged from memory upon timeout to prevent reuse windows.

[Paths]
- Card receipt: .agents/work/cards/ide/LAB-TAURI-IVF-P19.md
- Durable doc: lab-docs/ide/lab-tauri-ivf-live-trace-bridge-design-and-session-boundary-v0.md
