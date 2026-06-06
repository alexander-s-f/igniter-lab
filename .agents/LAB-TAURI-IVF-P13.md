Card: LAB-TAURI-IVF-P13
Agent: [Igniter-Lang Research Agent]
Role: research-agent
Track: lab-tauri-ivf-external-trace-subscription-boundary-design-v0
Status: done

[D] Decisions
- Designed the external trace event JSON envelope structure including trace/contract/status metadata, payload digests, and public-key signatures.
- Outlined a strict ingress gateway redaction gate that converts raw diagnostic/output maps to SHA-256 digests and extracts slot keys before dropping raw slot values from memory.
- Selected the Tauri Event Bridge as the recommended transport mechanism over SSE/WebSockets to prevent open-port vulnerabilities and maintain isolated message-passing boundaries.
- Formulated backpressure burst protection: rates exceeding 10 updates/second drop intermediate telemetry events to prevent UI thread blocking.

[S] Shipped / Signals
- Authored the design specification document at `igniter-lab/lab-docs/lab-tauri-ivf-external-trace-subscription-boundary-design-v0.md`.
- Formulated the transport options comparison matrix comparing local file drops, named pipes, SSE, WebSockets, and Tauri events.
- Drafted the future P14 implementation checklist and proof matrix (`TIVF-P14-1..8`).

[T] Tests / Proofs
- verified: All design constraints outlined in card scope are satisfied (no active transport implemented, no open port daemon created, no live VM execution introduced, no raw values persisted, no mainline igniter-lang files edited).

[R] Risks / Recommendations
- Recommendation: Proceed to card **LAB-TAURI-IVF-P14** to prototype a mock event emitter sidecar/listener using the Tauri Event Bridge channel.
- Risk: Avoid polling directories or watcher threads as they degrade host disk performance and bypass security sandboxing.

[Next] Suggested next slice
- Propose LAB-TAURI-IVF-P14 to implement the Event Bridge trace listener in Tauri and test it with a mock emitter script.
