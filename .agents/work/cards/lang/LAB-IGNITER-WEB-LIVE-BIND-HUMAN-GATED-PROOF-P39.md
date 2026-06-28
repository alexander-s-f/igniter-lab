# LAB-IGNITER-WEB-LIVE-BIND-HUMAN-GATED-PROOF-P39

Status: OPEN
Route: standard / main-audit / igniter-web / live-bind gate / lab proof
Skill: idd-agent-protocol
Depends-On:
- `LAB-IGNITER-WEB-LIVE-BIND-DRY-RUN-VERDICT-P36`
- `LAB-IGNITER-WEB-INBOUND-SIGNED-PASSPORT-DURABLE-KEY-P37`
- `LAB-IGNITER-WEB-TLS-TERMINATED-UPSTREAM-RUNBOOK-P38`

## Goal

Close the A10 live-bind audit tail with the smallest honest **lab-only,
human-gated** proof that a non-loopback bind can be authorized only when the
P36/P37/P38 checklist is complete and explicitly acknowledged by the operator.

This is **not** a production public-bind feature. It is a bounded proof path that
demonstrates the already-designed authority chain without turning normal
`igweb-serve run` into a public hosting surface.

## Current Authority

Live source wins. Read first:

- `lab-docs/lang/lab-audit-control-board-v1.md` row A10.
- `server/igniter-web/IMPLEMENTED_SURFACE.md` live-bind rows.
- `lab-docs/lang/lab-igniter-web-live-bind-dry-run-verdict-p36-v0.md`
- `lab-docs/lang/lab-igniter-web-inbound-signed-passport-durable-key-p37-v0.md`
- `lab-docs/lang/lab-igniter-web-tls-terminated-upstream-runbook-p38-v0.md`
- `server/igniter-server/src/serving_gate.rs`
- `server/igniter-web/src/host_config.rs`
- `server/igniter-web/src/live_bind_check.rs`
- `server/igniter-web/src/bin/igweb-serve.rs`
- `server/igniter-web/tests/igweb_live_bind_dry_run_tests.rs`
- `server/igniter-web/tests/igweb_serve_diagnostics_tests.rs`

Known live facts to re-verify:

- Normal `Run` still calls `authorize_bind(addr, None)`, so non-loopback is
  refused before `TcpListener::bind`.
- `live-bind-check` is report-only and never opens a socket.
- P37 host-verifies `signed_passport_path` only in the check path.
- P38 defines `terminated_upstream` as an operator topology assertion; native
  TLS is not implemented.

## Scope

Allowed:

- Add a lab-only proof command/mode if and only if it remains explicitly
  human-gated and bounded.
- Reuse the P36/P37 dry-run checklist conversion so the proof path authorizes
  the same host-verified `LiveBindChecklist`.
- Require a loud human acknowledgement, for example an env var with an exact
  phrase, before any non-loopback bind can be attempted.
- Require `terminated_upstream` and reject `native_tls` for this proof.
- Require bounded serving, preferably one request / one-shot behavior, so the
  proof cannot silently become a daemon.
- Add tests for all fail-closed paths without opening non-loopback sockets:
  missing ack, missing/malformed verifier, `native_tls`, incomplete checklist,
  and normal `run` still refused.
- If a real lab bind is demonstrated, document the exact command and evidence,
  and keep it human-gated/manual. Automated tests must not depend on opening a
  public or LAN listener.
- Update `IMPLEMENTED_SURFACE.md`, the audit board, and a proof packet only
  after live proof/implementation exists.

If the implementation is larger or riskier than expected, stop after a
readiness packet that names the exact smaller implementation card. Do not widen.

Closed:

- Do not make normal `igweb-serve run` use the checklist automatically.
- Do not enable production public bind.
- Do not implement native TLS, ACME, proxy protocol, KMS, key rotation, or
  remote identity.
- Do not trust `X-Forwarded-*` headers from arbitrary direct clients.
- Do not log or commit verifier key material, passports, DSNs, or secrets.
- Do not edit `.igweb` language semantics, Todo routes, or frame-ui.

## Questions To Answer

1. Should P39 be a new subcommand, a hidden/lab flag on `run`, or a
   manual-only proof script?
2. What is the exact human acknowledgement string and where is it checked?
3. Does the proof path bind a real non-loopback address, or does it stop at
   `authorize_bind(..., Some(checklist))` plus manual runbook evidence?
4. How is P37 verifier loading shared with P39 without duplicating secret-risky
   parsing?
5. What is the exit-code / diagnostic shape for refusal?
6. After P39, can A10 move from `PARTLY CLOSED` to `CLOSED for lab proof`, or
   should production bind remain a separate deferred row?

## Acceptance

- [ ] Live P36/P37/P38/server-gate surfaces characterized before editing.
- [ ] Normal `igweb-serve run` non-loopback behavior remains refused.
- [ ] Any actual non-loopback bind path is lab-only, human-gated, and bounded.
- [ ] Missing acknowledgement refuses before bind.
- [ ] Missing/malformed signed-passport verifier refuses before bind.
- [ ] `native_tls` refuses for the proof path.
- [ ] `terminated_upstream` is treated as operator topology assertion, not
      transport proof.
- [ ] Tests prove fail-closed behavior without depending on public/LAN sockets.
- [ ] Proof packet created under `lab-docs/lang/`.
- [ ] `IMPLEMENTED_SURFACE.md` and `lab-audit-control-board-v1.md` updated only
      to the exact live truth.
- [ ] `git diff --check` passes.
- [ ] Card closed with concise report.

## Suggested Verification

Adapt after live discovery, but start with:

```bash
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab
cargo test --manifest-path server/igniter-web/Cargo.toml --features machine live_bind_check
cargo test --manifest-path server/igniter-web/Cargo.toml --features machine --test igweb_live_bind_dry_run_tests
cargo test --manifest-path server/igniter-web/Cargo.toml --features machine --test igweb_serve_diagnostics_tests
cargo test --manifest-path runtime/igniter-machine/Cargo.toml --test signed_passport_dataplane_tests
git diff --check
```

If a manual lab proof is run, capture:

- exact command;
- exact bind address;
- acknowledgement value presence without printing secrets;
- one request success;
- listener shutdown / bounded exit;
- proof no verifier material was printed.

## Required Packet

Create:

```text
lab-docs/lang/lab-igniter-web-live-bind-human-gated-proof-p39-v0.md
```

Packet must include:

- what was implemented vs only documented;
- the human gate;
- the checklist authority chain;
- refusal taxonomy;
- proof that normal public bind remains closed;
- whether A10 can be marked closed for lab proof or remains production-deferred.
