# LAB-IGNITER-WEB-LIVE-BIND-HUMAN-GATED-PROOF-P39 v0

Date: 2026-06-28
Status: DONE
Route: standard / main-audit / igniter-web / live-bind gate / lab proof
Skill: idd-agent-protocol
Card: `.agents/work/cards/lang/LAB-IGNITER-WEB-LIVE-BIND-HUMAN-GATED-PROOF-P39.md`
Depends-On: `LAB-IGNITER-WEB-LIVE-BIND-DRY-RUN-VERDICT-P36`,
`LAB-IGNITER-WEB-INBOUND-SIGNED-PASSPORT-DURABLE-KEY-P37`,
`LAB-IGNITER-WEB-TLS-TERMINATED-UPSTREAM-RUNBOOK-P38`
Implements: audit-control-board row **A10** lab authorization proof; production
public bind stays closed.

## Boundary

This card implements a lab-only, human-gated authorization proof:

```bash
IGNITER_LIVE_BIND_HUMAN_ACK=I_UNDERSTAND_IGNITER_LAB_LIVE_BIND_P39 \
  igweb-serve live-bind-proof --host-config PATH --addr 0.0.0.0:8080
```

The command opens no socket, starts no server, and grants no production bind
authority. It proves the P36/P37/P38 authority chain by reaching the server-owned
pure `authorize_bind(addr, Some(checklist))` gate only after the explicit human
acknowledgement and host-verified checklist are present.

Normal `igweb-serve run` remains unchanged and still calls
`authorize_bind(addr, None)`. A complete `[host.live_bind]` checklist still does
not relax normal `Run`.

## What Was Implemented

Code:

- `server/igniter-web/src/live_bind_proof.rs`
  - new `LIVE_BIND_PROOF_ACK_ENV =
    "IGNITER_LIVE_BIND_HUMAN_ACK"`;
  - new exact acknowledgement value
    `I_UNDERSTAND_IGNITER_LAB_LIVE_BIND_P39`;
  - requires a non-loopback target address;
  - requires `[host.live_bind.inbound_tls] mode = "terminated_upstream"`;
  - requires `upstream_header_policy = "trusted_proxy_only"`;
  - rejects `native_tls` for the proof path;
  - reuses P37 `config_to_checklist`, which loads and validates durable verifier
    material before setting `signed_passport_path_wired=true`;
  - calls the pure `igniter_server::serving_gate::authorize_bind`;
  - renders a secret-free `[LIVE_BIND_PROOF]` line with
    `bind_attempted=false socket_opened=false public_bind=closed`.
- `server/igniter-web/src/lib.rs`
  - adds `RunnerCliCommand::LiveBindProof`;
  - parses `igweb-serve live-bind-proof --host-config PATH [--addr HOST:PORT]`;
  - documents the human gate in CLI usage.
- `server/igniter-web/src/bin/igweb-serve.rs`
  - adds the `LiveBindProof` command arm;
  - loads `host.toml`, checks the acknowledgement env var, prints the proof
    verdict, exits 0 on authorization and 5 on refusal.
- `server/igniter-web/tests/igweb_live_bind_human_gated_proof_tests.rs`
  - subprocess coverage for missing ack, success, `native_tls`, missing verifier,
    and incomplete checklist.
- `server/igniter-web/tests/runner_tests.rs`
  - CLI parse/usage coverage.

No native TLS, ACME, proxy protocol, public listener, app route semantics,
Todo route semantics, `.igweb` language behavior, or frame-ui code was added.

## Authority Chain

The P39 proof path is:

1. Parse `host.toml` with the existing fail-closed host-config parser.
2. Require exact human acknowledgement:
   `IGNITER_LIVE_BIND_HUMAN_ACK=I_UNDERSTAND_IGNITER_LAB_LIVE_BIND_P39`.
3. Require a non-loopback address. Loopback is not accepted as a live-bind proof.
4. Require `terminated_upstream` and `trusted_proxy_only` per P38. This is an
   operator topology assertion, not TLS transport.
5. Reuse P37 verifier loading. The proof path sets
   `signed_passport_path_wired=true` only after the host reads and validates the
   v0 durable verifier file.
6. Call the pure server-owned `authorize_bind(addr, Some(checklist))`.
7. Print the resulting opaque checklist digest without field values or key
   material.

The command deliberately stops at authorization. It does not call
`TcpListener::bind`.

## Human Gate

The exact gate is:

```text
IGNITER_LIVE_BIND_HUMAN_ACK=I_UNDERSTAND_IGNITER_LAB_LIVE_BIND_P39
```

Any missing or different value refuses with:

```text
code=human_ack_missing_or_invalid missing_field=IGNITER_LIVE_BIND_HUMAN_ACK
```

The acknowledgement is not treated as a secret and is never sufficient by
itself. It only allows the command to continue toward the host-verified
checklist and pure gate check.

## Refusal Taxonomy

| Input | Verdict / diagnostic | Exit |
|---|---|---|
| Missing or wrong acknowledgement | `[LIVE_BIND_PROOF] ... verdict=would_refuse code=human_ack_missing_or_invalid missing_field=IGNITER_LIVE_BIND_HUMAN_ACK bind_attempted=false socket_opened=false public_bind=closed` | 5 |
| Loopback `--addr` | `code=loopback_not_live_bind_proof missing_field=addr` | 5 |
| Missing `[host.live_bind]` | `code=non_loopback_without_checklist` | 5 |
| `native_tls` | `code=native_tls_transport_not_implemented missing_field=inbound_tls.mode` | 5 |
| `terminated_upstream` with unsupported header policy | `code=unsupported_upstream_header_policy missing_field=upstream_header_policy` | 5 |
| Missing verifier material | `code=signed_passport_verifier_unavailable missing_field=signed_passport_path` | 5 |
| Malformed verifier material | `code=signed_passport_verifier_invalid missing_field=signed_passport_path` | 5 |
| Incomplete checklist shape | `[CONFIG_PARSE]`, no proof verdict | 2 |
| Complete `terminated_upstream` checklist + valid verifier + exact ack | `verdict=would_authorize checklist_digest=live-bind-v0:... bind_attempted=false socket_opened=false public_bind=closed` | 0 |

All proof verdicts are secret-free. Tests assert verifier paths and key material
do not appear in stdout/stderr.

## Public Bind Status

A10 can be marked **closed for lab authorization proof**: the code now
demonstrates the explicit authority chain from human acknowledgement through
P37 verifier-backed checklist into the server-owned pure gate.

Production public bind remains closed and deferred:

- normal `igweb-serve run` still refuses non-loopback before `TcpListener::bind`;
- `live-bind-check` and `live-bind-proof` both print `socket_opened=false`;
- P39 does not implement TLS transport;
- P39 does not demonstrate or authorize an internet-facing listener;
- `native_tls` remains blocked for this proof.

## Verification

Commands run from `/Users/alex/dev/projects/igniter-workspace/igniter-lab`:

```bash
cargo test --manifest-path server/igniter-web/Cargo.toml --features machine live_bind_proof
cargo test --manifest-path server/igniter-web/Cargo.toml --features machine --test igweb_live_bind_human_gated_proof_tests
cargo test --manifest-path server/igniter-web/Cargo.toml --features machine --test runner_tests cli_live_bind_proof_parses_as_human_gated_command
cargo test --manifest-path server/igniter-web/Cargo.toml --features machine --test igweb_live_bind_dry_run_tests
cargo test --manifest-path server/igniter-web/Cargo.toml --features machine live_bind_check
cargo test --manifest-path server/igniter-web/Cargo.toml --features machine --test igweb_serve_diagnostics_tests
cargo test --manifest-path runtime/igniter-machine/Cargo.toml --test signed_passport_dataplane_tests
```

Results:

- `live_bind_proof`: 6 passed.
- `igweb_live_bind_human_gated_proof_tests`: 5 passed.
- `runner_tests cli_live_bind_proof_parses_as_human_gated_command`: 1 passed.
- `igweb_live_bind_dry_run_tests`: 8 passed.
- `live_bind_check`: 9 passed.
- `igweb_serve_diagnostics_tests`: 8 passed.
- `signed_passport_dataplane_tests`: 5 passed.

Warnings observed are pre-existing unused/dead-code warnings in adjacent crates.
