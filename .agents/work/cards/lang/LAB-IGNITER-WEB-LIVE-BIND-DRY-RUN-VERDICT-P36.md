# LAB-IGNITER-WEB-LIVE-BIND-DRY-RUN-VERDICT-P36

Status: OPEN
Route: standard / main-audit / igniter-web / live-bind gate
Skill: idd-agent-protocol
Depends-On: `LAB-IGNITER-WEB-LIVE-BIND-GATE-DECISION-READINESS-P35`

## Goal

Implement the first P35 follow-up: a report-only live-bind dry-run verdict that
evaluates the parsed `[host.live_bind]` checklist and server gate without ever
opening a non-loopback listener.

This closes the next A10 tail while preserving the public-bind HOLD decision.
The output should tell an operator "would this host config be accepted by the
server gate, and why not?" without granting bind authority.

## Current Authority

Live source wins. Read first:

- `lab-docs/lang/lab-audit-control-board-v1.md`
- `lab-docs/lang/lab-igniter-web-live-bind-gate-decision-readiness-p35-v0.md`
- `lab-docs/lang/lab-igniter-web-host-live-bind-checklist-parse-p34-v0.md`
- `server/igniter-web/IMPLEMENTED_SURFACE.md`
- `server/igniter-web/src/host_config.rs`
- `server/igniter-web/src/bin/igweb-serve.rs`
- `server/igniter-server/src/serving_gate.rs`
- IgWeb diagnostics tests.

Known facts to re-verify:

- P34 parses checklist but runner still calls `authorize_bind(addr, None)`;
- P35 says first implementation must be dry-run/report-only;
- public/non-loopback bind must remain closed.

## Scope

Allowed:

- Add a CLI/config path that evaluates the live-bind checklist and emits a
  structured verdict without binding.
- Convert parsed checklist into server-gate input only for dry-run evaluation.
- Add tests for accept-shaped, missing, incomplete, and refused verdicts.
- Ensure normal serve path remains unchanged and non-loopback still refused.
- Update implemented surface/proof packet.

Closed:

- Do not open a public/non-loopback listener.
- Do not wire dry-run success into actual bind authority.
- Do not implement TLS transport.
- Do not implement durable inbound signed-passport key handling.
- Do not create production deploy instructions.

## Questions To Answer

1. Is the dry-run exposed as `igweb-serve --check-live-bind`, a host-config
   validation mode, or another existing diagnostics path?
2. What structured verdict shape should tests assert?
3. Which fields are copied operator assertions, and which are host-verified
   runtime state?
4. How does the verdict prove no listener was opened?
5. What remains for P37/P38/P39?

## Acceptance

- [ ] Live P34/P35/server-gate surfaces characterized before editing.
- [ ] Dry-run verdict exists and never binds sockets.
- [ ] Complete checklist produces an accept-shaped verdict but still no bind
      authority.
- [ ] Missing/incomplete/invalid checklist produces actionable refusal verdict.
- [ ] Existing loopback serve behavior unchanged.
- [ ] Non-loopback serve path remains refused outside dry-run.
- [ ] Proof packet states public bind remains closed.
- [ ] `git diff --check` passes.
- [ ] Card is closed with a concise report.

## Suggested Verification

```bash
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab
cargo test --manifest-path server/igniter-web/Cargo.toml --test igweb_serve_diagnostics_tests
cargo test --manifest-path server/igniter-web/Cargo.toml --features machine --test igweb_serve_machine_mode_tests
git diff --check
```

## Required Packet

Create:

```text
lab-docs/lang/lab-igniter-web-live-bind-dry-run-verdict-p36-v0.md
```

Packet must include:

- verdict shape;
- proof no sockets are opened;
- accept/refusal taxonomy;
- remaining authority chain.
