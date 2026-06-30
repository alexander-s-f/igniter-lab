# LAB-IGNITER-WEB-TLS-TERMINATED-UPSTREAM-RUNBOOK-P38

Status: DONE
Route: standard / main-audit / igniter-web / live-bind gate / TLS runbook
Skill: idd-agent-protocol
Depends-On:
- `LAB-IGNITER-WEB-LIVE-BIND-GATE-DECISION-READINESS-P35`
- `LAB-IGNITER-WEB-LIVE-BIND-DRY-RUN-VERDICT-P36`

## Goal

Close the A10 TLS/operator gap needed before any human-gated non-loopback proof:
define and verify the **terminated-upstream** TLS runbook, without adding TLS
transport and without opening a public listener.

P35 chose `terminated_upstream` as the first acceptable live-bind TLS mode.
P36 can dry-run a complete checklist. This card must turn
`inbound_tls.mode = "terminated_upstream"` from a vague assertion into a
reviewable operator contract: what proxy/LB promises, what headers are trusted,
what is explicitly not trusted, what the app/server logs, and what P39 must
prove before binding.

## Current Authority

Live source wins. Read first:

- `lab-docs/lang/lab-audit-control-board-v1.md` row A10.
- `lab-docs/lang/lab-igniter-server-live-bind-tls-checklist-readiness-p33-v0.md`
- `lab-docs/lang/lab-igniter-web-live-bind-gate-decision-readiness-p35-v0.md`
- `lab-docs/lang/lab-igniter-web-live-bind-dry-run-verdict-p36-v0.md`
- `server/igniter-server/src/serving_gate.rs`
- `server/igniter-web/src/host_config.rs`
- `server/igniter-web/src/live_bind_check.rs`
- current `server/igniter-web/IMPLEMENTED_SURFACE.md`
- current distribution/devops docs if they mention reverse proxy, TLS, or bind
  exposure.

Known facts to re-verify:

- `native_tls` is not implemented for the server bind path.
- `terminated_upstream` is metadata/checklist only today.
- P36 dry-run never opens a socket and never grants bind authority.
- The real bind path still keeps public bind closed.

## Scope

Allowed:

- Produce a runbook/readiness packet for `terminated_upstream` TLS.
- Define the minimal operator contract for proxy/LB termination.
- Define trusted and untrusted headers. Be conservative: header presence from an
  untrusted direct client must not be treated as TLS proof.
- Define how P39 should prove it is behind a trusted terminator, or explicitly
  state that v0 P39 is still a lab-only human proof with no production claim.
- Add doc-only examples for `host.toml` with placeholders only; no secrets.
- Optionally add a small validation/test if live code already has an obvious
  parser or diagnostic gap for `upstream_header_policy`.
- Update audit board only if this card reaches a clear P39 precondition.

Closed:

- Do not implement native TLS.
- Do not add proxy protocol, certificate handling, ACME, rustls server accept,
  or public deploy instructions.
- Do not open or demonstrate a public/non-loopback listener.
- Do not trust `X-Forwarded-*` headers from arbitrary clients as proof of TLS.
- Do not change runtime behavior unless the change is a tiny fail-closed
  diagnostic improvement.

## Questions To Answer

1. What exact claim does `terminated_upstream` make in Igniter v0?
2. Which headers can be used as observability hints, and which can be used as
   authority? If the answer is "none without a trusted upstream boundary", say
   that plainly.
3. What host topology is acceptable for the first P39 human-gated proof:
   localhost reverse proxy, LAN-only lab proxy, or external LB?
4. What must be included in the P39 checklist beyond P36/P37?
5. What should `igweb-serve live-bind-check` report or refuse when TLS mode is
   `native_tls` vs `terminated_upstream`?

## Acceptance

- [x] Live P33/P35/P36 surfaces are characterized.
- [x] Packet clearly distinguishes TLS **transport**, TLS **termination
      assertion**, and header **hints**.
- [x] `terminated_upstream` runbook is secret-free and uses placeholders only.
- [x] Native TLS remains explicitly blocked/deferred.
- [x] Public bind remains closed; no listener is opened.
- [x] P39 preconditions are listed as a checklist.
- [x] Any doc/code touched passes `git diff --check`.
- [x] Card closed with concise report.

## Suggested Verification

This is primarily doc/readiness. If code is touched, also run the targeted
diagnostic tests.

```bash
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab
cargo test --manifest-path server/igniter-web/Cargo.toml --features machine --test igweb_live_bind_dry_run_tests
cargo test --manifest-path server/igniter-web/Cargo.toml --features machine --test igweb_serve_diagnostics_tests
git diff --check
```

## Required Packet

Create:

```text
lab-docs/lang/lab-igniter-web-tls-terminated-upstream-runbook-p38-v0.md
```

Packet must include:

- exact `terminated_upstream` v0 meaning;
- operator topology/runbook;
- trusted-header policy;
- refusal boundaries;
- P39 precondition checklist;
- explicit statement that native TLS and public bind remain closed.

## Closing Report

Closed in:

- `lab-docs/lang/lab-igniter-web-tls-terminated-upstream-runbook-p38-v0.md`
- `server/igniter-web/IMPLEMENTED_SURFACE.md`
- `lab-docs/lang/lab-audit-control-board-v1.md`

Result:

- P33/P35/P36 are characterized as gate/checklist/dry-run surfaces only.
- `terminated_upstream` is defined as an operator termination assertion backed
  by trusted topology evidence, not IgWeb TLS transport.
- Forwarding headers are observability hints only unless the request is already
  behind a trusted upstream boundary.
- P39 must stay lab-only/human-gated, use `terminated_upstream`, and refuse
  `native_tls` for actual non-loopback proof until a real TLS accept path
  exists.
- Public bind remains closed; no listener was opened.

Verification:

```text
git diff --check
```
