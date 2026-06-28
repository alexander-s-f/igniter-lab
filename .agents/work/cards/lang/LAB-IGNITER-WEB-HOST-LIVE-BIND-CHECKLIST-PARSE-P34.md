# LAB-IGNITER-WEB-HOST-LIVE-BIND-CHECKLIST-PARSE-P34

Status: CLOSED (2026-06-28)
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

- [x] Host config has an explicit live-bind checklist section.
- [x] Non-loopback bind without checklist fails closed before listener bind.
- [x] Incomplete checklist fails with actionable diagnostics.
- [x] Loopback bind remains unchanged.
- [x] Tests do not open public listeners.
- [x] Implemented Surface names what is implemented and what remains readiness
      only.
- [x] `git diff --check` passes.
- [x] Card is closed with a concise report.

## Report (2026-06-28)

Implemented P33 Decision Alternative A: a parse-only `[host.live_bind]` +
`[host.live_bind.inbound_tls]` checklist in `server/igniter-web/src/host_config.rs`. It
is READINESS ONLY — the runner still calls `authorize_bind(addr, None)`, so a complete
checklist does NOT open a non-loopback listener, and `[host] mode = "public"` is still
refused.

Answers to the card questions:

1. **Shape** — `[host.live_bind]` (`signed_passport_path`, three `*_enabled` boolean
   assertions, `operator_signoff`) + `[host.live_bind.inbound_tls]` (`mode` +
   mode-specific refs). Quoted-value uniform (booleans are `"true"`/`"false"`). Mirrors
   the server `LiveBindChecklist` fields. Full schema in the proof doc.
2. **Hard requirements vs diagnostics** — all five top-level fields + a TLS `mode` are
   required; the three booleans must be `"true"` (false ⇒ `LiveBindFalseAssertion`);
   `native_tls` requires `cert_file`+`key_file`, `terminated_upstream` requires
   `upstream_header_policy`. Absent section ⇒ `live_bind: None` (no diagnostic).
3. **Sync vs machine async** — the section is parsed in `host_config` regardless of mode;
   it only flows through the `--host-config` (machine) runner, which parses+resolves
   before any bind. Neither mode is granted a non-loopback bind by it.
4. **TLS** — parsed as METADATA only (file-path refs); no live TLS. `native_tls` stays
   blocked (no transport); `none` is refused.
5. **Operator message** — diagnostics name the missing/false field, the bad bool/mode
   value, or the inline-secret/template key; never resolved secret values or file
   contents. All classify as `CONFIG_PARSE` (exit 2), before any listener bind.

Also strengthened `INLINE_SECRET_KEYS` with `key`/`cert` so an inline TLS private
key/certificate fails closed with the "use a file reference" diagnostic. Added committed
parse-only example `examples/todo_postgres_app/host.live_bind.example.toml` (+ guard
test).

Files: `src/host_config.rs` (parser + structs + errors + 18 unit tests + example guard),
`tests/igweb_serve_diagnostics_tests.rs` (3 subprocess tests),
`examples/todo_postgres_app/host.live_bind.example.toml`, `IMPLEMENTED_SURFACE.md`,
`lab-docs/lang/lab-audit-control-board-v1.md` (A10), proof packet
`lab-docs/lang/lab-igniter-web-host-live-bind-checklist-parse-p34-v0.md`.

Verification: `--lib host_config` 74 PASS; `--test igweb_serve_diagnostics_tests` 8 PASS;
`--features machine` full crate PASS (0 failures); `git diff --check` PASS. (Bare
no-features `cargo test` does not compile the pre-existing, untouched, ungated
`tests/signed_effect_passport_tests.rs` — run the `--features machine` superset.)

Next (a GATE DECISION, not a parse slice): verify operator assertions → mint the server
`LiveBindChecklist`, wire signed-passport verification at the inbound seam, ship TLS
transport for `native_tls`, then a human-gated non-loopback bind proof.

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

