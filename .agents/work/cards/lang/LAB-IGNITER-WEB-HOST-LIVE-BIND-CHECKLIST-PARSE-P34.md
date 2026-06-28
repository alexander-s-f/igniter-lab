# LAB-IGNITER-WEB-HOST-LIVE-BIND-CHECKLIST-PARSE-P34

Status: OPEN
Route: standard / main-audit / igniter-web / live-bind gate
Skill: idd-agent-protocol
Depends-On: `LAB-IGNITER-SERVER-LIVE-BIND-GATE-P31`,
`LAB-IGNITER-WEB-LIVE-BIND-GATE-WIRING-P32`,
`lab-docs/lang/lab-igniter-server-live-bind-tls-checklist-readiness-p33-v0.md`

## Goal

Turn live-bind readiness into an operator-checkable host-config parse/diagnostic
surface, without opening public bind.

This is audit-control-board row A10. The live-bind gate exists; this card gives
IgWeb an explicit checklist input and fail-closed diagnostics so agents stop
treating public bind as a hidden or ad hoc CLI decision.

## Current Authority

Live source wins. Read first:

- `lab-docs/lang/lab-audit-control-board-v1.md`
- `lab-docs/lang/lab-igniter-server-live-bind-tls-checklist-readiness-p33-v0.md`
- `server/igniter-web/IMPLEMENTED_SURFACE.md`
- `server/igniter-web/src/host_config.rs`
- `server/igniter-web/src/host_binding.rs`
- `server/igniter-web/src/bin/igweb-serve.rs`
- relevant server live-bind gate source/docs if imported by IgWeb
- `server/igniter-web/tests/igweb_serve_machine_mode_tests.rs`
- `server/igniter-web/tests/igweb_serve_diagnostics_tests.rs`

Known live facts to re-verify:

- public/non-loopback bind is still closed by default;
- IgWeb already preauthorizes listener binds through the server gate;
- TLS/checklist readiness exists, but operator-config parse/enforcement is not
  yet the implemented surface.

## Scope

Allowed:

- Add a small host-config schema for live-bind checklist fields.
- Parse and validate the checklist before constructing a non-loopback bind.
- Add diagnostics for missing/incomplete/invalid checklist.
- Add tests that non-loopback remains refused without the checklist.
- Add tests that loopback behavior remains unchanged.
- Update `server/igniter-web/IMPLEMENTED_SURFACE.md` and proof docs.

Closed:

- Do not actually bind a public/non-loopback listener in tests or examples.
- Do not add TLS implementation unless the readiness packet explicitly scoped a
  parse-only placeholder.
- Do not weaken loopback defaults.
- Do not change server-core transport semantics beyond consuming the existing
  gate API.
- Do not introduce production deploy instructions.

## Questions To Answer

1. What exact host-config shape represents the checklist?
2. Which fields are hard requirements vs explicit "not configured" diagnostics?
3. How does this interact with sync mode vs machine async mode?
4. Does the checklist include TLS paths as parsed metadata or require live TLS?
5. What message tells an operator what is missing without leaking secrets?

## Acceptance

- [ ] Host config has an explicit live-bind checklist section.
- [ ] Non-loopback bind without checklist fails closed before listener bind.
- [ ] Incomplete checklist fails with actionable diagnostics.
- [ ] Loopback bind remains unchanged.
- [ ] Tests do not open public listeners.
- [ ] Implemented Surface names what is implemented and what remains readiness
      only.
- [ ] `git diff --check` passes.
- [ ] Card is closed with a concise report.

## Suggested Verification

```bash
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab
cargo test --manifest-path server/igniter-web/Cargo.toml --test igweb_serve_diagnostics_tests
cargo test --manifest-path server/igniter-web/Cargo.toml --features machine --test igweb_serve_machine_mode_tests
cargo test --manifest-path server/igniter-web/Cargo.toml
git diff --check
```

## Required Packet

Create:

```text
lab-docs/lang/lab-igniter-web-host-live-bind-checklist-parse-p34-v0.md
```

Packet must state:

- exact config schema;
- refusal taxonomy;
- why public bind remains closed;
- what would be required to authorize a real live-bind proof later.

