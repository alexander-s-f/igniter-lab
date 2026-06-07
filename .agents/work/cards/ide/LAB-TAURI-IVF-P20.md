Card: LAB-TAURI-IVF-P20
Category: ide
Agent: [Igniter-Lang Implementation Agent]
Role: implementation-agent
Track: lab-tauri-ivf-mock-session-runner-hmac-proof-v0
Route: EXPERIMENTAL / LAB-ONLY
Status: done

[D] Decisions
- Implemented `ActiveSession` and `ActiveSessionState` in Rust/Tauri to manage transient telemetry session state (session_token, transaction_id, created_at).
- Developed a self-contained RFC 2104-compliant HMAC-SHA256 signature generator in Rust using only the `sha2` crate to keep dependencies minimal.
- Built a secure dynamic session runner `run_mock_session_runner_hmac_proof.rb` in Ruby to generate the signed JSON envelope per session.
- Prevented parallel test conflicts by suffixing JSON envelope files with the session's `transaction_id` (`out/ruby_session_ingress_envelope_<tx_id>.json`).
- Implemented file system cleanup to delete the transient signed JSON file immediately after reading.
- Validated all fail-closed rejection paths (wrong token, wrong transaction ID, timeout, replay, oversized payload, unknown status, unsigned payload) in Rust backend unit tests.
- Recommended proceeding to P21 to map the session runner dispatch inside Svelte UI.

[S] Shipped / Signals
- Created Ruby session runner: igniter-view-engine/run_mock_session_runner_hmac_proof.rb.
- Added session state management, hmac helpers, and command dispatch: igniter-ide/src-tauri/src/commands.rs.
- Registered managed state and command: igniter-ide/src-tauri/src/lib.rs.
- Created durable proof document: lab-docs/ide/lab-tauri-ivf-mock-session-runner-hmac-proof-v0.md.
- Created card receipt: .agents/work/cards/ide/LAB-TAURI-IVF-P20.md.

[T] Tests / Proofs
- verified: Cross-language HMAC test vector hashes match exactly in Python, Ruby OpenSSL, and Rust hmac_sha256 implementation.
- verified: Unit tests `test_mock_session_runner_lifecycle_success` and `test_mock_session_runner_rejections` pass successfully.
- verified: All backend unit tests pass (`8 passed; 0 failed; 0 ignored`).

[R] Risks / Recommendations
- Risk: Spawning Ruby as a subprocess introduces platform dependencies (Ruby must be in PATH). Ensure the host setup is documented.
- Recommendation: Proceed to P21 to wire this session dispatch hook into Svelte frontend control panel, allowing live interactive testing.

[Paths]
- Card receipt: .agents/work/cards/ide/LAB-TAURI-IVF-P20.md
- Durable doc: lab-docs/ide/lab-tauri-ivf-mock-session-runner-hmac-proof-v0.md
