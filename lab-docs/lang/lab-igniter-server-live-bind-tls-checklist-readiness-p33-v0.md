# LAB-IGNITER-SERVER-LIVE-BIND-TLS-CHECKLIST-READINESS-P33

Date: 2026-06-27
Status: DONE
Route: standard / main-audit / server / public bind readiness

## Evidence

Live P31/P32 state was verified against source and tests:

- `server/igniter-server/src/serving_gate.rs` owns the pure pre-bind gate.
- Loopback addresses return `Ok(None)` without a checklist.
- Non-loopback addresses with no checklist return `non_loopback_without_checklist`.
- A complete `LiveBindChecklist` can mint an opaque `LiveBindToken`, but IgWeb does not
  construct or pass one today.
- `server/igniter-web/src/bin/igweb-serve.rs` calls `authorize_bind(addr, None)` before
  both sync `TcpListener::bind` and machine-mode Tokio binds.
- `server/igniter-web/src/host_config.rs` still accepts only `[host] mode = "loopback"`.
- `server/igniter-web/IMPLEMENTED_SURFACE.md` states public listener mode is closed.

This packet is lab evidence only. It does not create canon language authority, does not
enable public bind, does not add TLS, and does not change `.igweb`, app code, VM,
compiler, machine, home-lab, SparkCRM, or private governance files.

## Minimum Checklist

The production checklist should keep the server-owned structural fields from P31 and
make host-owned references explicit:

| Field | Kind | Required for non-loopback v1 | Notes |
| --- | --- | --- | --- |
| `mode = "public"` | operator assertion | yes | Separate from loopback DX; unsupported until the public-bind gate decision. |
| `signed_passport_path` | file reference | yes | File path only; never inline passport/token material. Parser proves the reference shape, not key validity. |
| `body_cap_enabled` | boolean assertion | yes | Must be `true`; config may also carry a numeric cap in a later slice. |
| `read_timeout_enabled` | boolean assertion | yes | Must be `true`; config may later carry timeout values. |
| `fail_closed_auth_enabled` | boolean assertion | yes | Must be `true`; means unauthenticated inbound effect/write surfaces fail closed. |
| `inbound_tls.mode` | enum assertion | yes | `terminated_upstream` or `native_tls`; no "none" for non-loopback v1. |
| `inbound_tls.cert_file` | file reference | only for `native_tls` | Certificate chain path. Fixture must use fake temp paths or parser-only examples. |
| `inbound_tls.key_file` | file reference | only for `native_tls` | Private-key path reference only; no committed key material. |
| `inbound_tls.upstream_header_policy` | opaque assertion | for `terminated_upstream` | Names the operator contract with proxy/LB, not a secret. |
| `operator_signoff` | opaque assertion | yes | Small marker such as `"present"` or a non-secret change-ticket id. No freeform secret values. |

TLS should be mandatory as a decision for non-loopback v1. `terminated_upstream` is
acceptable when the operator asserts that TLS terminates before IgWeb. `native_tls`
should remain blocked until a separate transport implementation exists.

## Secret Policy

Committed fixtures and examples may contain:

- env-var names such as `IGNITER_EFFECT_PASSPORT`
- file references such as `/etc/igniter/certs/site.crt`
- opaque non-secret operator labels
- booleans and enum values

Committed fixtures and examples must not contain:

- inline private keys
- certificate private material
- bearer tokens or passports
- DSNs
- passwords
- API keys
- interpolated secret templates such as `${TOKEN}`

Runtime diagnostics may name the missing field or env/file reference key, but must not
print resolved secret values or file contents.

## Alternatives Compared

### A. Inline `[host.live_bind]` in `host.toml`

Shape:

```toml
[host]
mode = "public"

[host.live_bind]
signed_passport_path = "/etc/igniter/passports/inbound.passport"
body_cap_enabled = true
read_timeout_enabled = true
fail_closed_auth_enabled = true
operator_signoff = "present"

[host.live_bind.inbound_tls]
mode = "terminated_upstream"
upstream_header_policy = "trusted_proxy_only"
```

Pros:

- Single operator file; fits the existing host-owned parser.
- Existing fail-closed unknown-section/unknown-key rules protect the surface.
- Easy to test parser refusal without opening sockets.

Cons:

- Grows `host.toml` into deployment policy.
- Needs careful separation between parser readiness and actual bind authorization.

### B. Sidecar checklist file referenced by `host.toml`

Shape:

```toml
[host]
mode = "public"
live_bind_checklist_file = "/etc/igniter/live-bind.toml"
```

Pros:

- Keeps production bind policy separate from app host bindings.
- Easier to permission separately on a host.

Cons:

- Adds second-file resolution and path policy before the first production slice needs it.
- Makes tests and operator diagnostics more complex.

### C. Environment-only / CLI checklist

Shape:

```text
IGNITER_LIVE_BIND_MODE=public
IGNITER_LIVE_BIND_TLS=terminated_upstream
igweb-serve --allow-public-bind ...
```

Pros:

- No committed config fields.
- Convenient for one-off operator experiments.

Cons:

- Weak audit trail and easy to drift from `host.toml`.
- Harder to express structured refusal modes.
- Too close to accidental public-bind enablement.

### D. Server-only token builder API

Shape: expose a helper in `igniter-server` that accepts a `LiveBindChecklist` and returns
the existing `LiveBindToken`, leaving all parsing to downstream hosts.

Pros:

- Preserves server as structural authority.
- Keeps parsing out of the low-level server crate.

Cons:

- Does not solve IgWeb operator config.
- Leaves each host to invent a checklist shape.

## Decision

Recommend Alternative A for the next implementation slice, but with a closed execution
contract:

- Add parser structs and diagnostics for `[host.live_bind]`.
- Keep `[host] mode = "public"` fail-closed until the card explicitly allows parse-only
  public mode.
- Do not pass a complete checklist into `authorize_bind` from IgWeb yet.
- Do not add native TLS transport.
- Do not open a public listener in tests.

This creates a stable host-owned checklist shape without changing runtime authority.
Public bind enablement should require a later gate decision after parser proof, operator
runbook proof, and TLS/proxy-mode review.

## Future Refusal Modes

Future parser/runner tests should prove these modes before any public listener can open:

- `CONFIG_PARSE`: unknown `[host.live_bind]` key.
- `CONFIG_PARSE`: inline secret key such as `token`, `passport`, `key`, `password`, `dsn`.
- `CONFIG_PARSE`: `mode = "public"` without `[host.live_bind]`.
- `CONFIG_PARSE`: missing `signed_passport_path`.
- `CONFIG_PARSE`: missing or false body cap/read timeout/fail-closed auth assertion.
- `CONFIG_PARSE`: missing `inbound_tls.mode`.
- `CONFIG_PARSE`: `inbound_tls.mode = "native_tls"` without cert/key file references.
- `CONFIG_PARSE`: `inbound_tls.mode = "none"` or any unknown mode.
- `CONFIG_PARSE`: missing `operator_signoff`.
- `BIND_REFUSED`: non-loopback still refused before bind when no runtime checklist is passed.

Tests should use parser-only fixtures and subprocess diagnostics asserting stdout never
contains `listening http://0.0.0.0` or any non-loopback bound address.

## Migration Path

Current DX remains:

```text
igniter serve <app> --addr 127.0.0.1:0 --max-requests 1
```

The migration should be staged:

1. Keep default serve loopback-only and bounded.
2. Add parse-only public checklist fields with fail-closed diagnostics.
3. Add operator runbook/examples with env/file references only.
4. Add an explicit gate decision for passing checklist data into `authorize_bind`.
5. Only then consider public bind, with `terminated_upstream` allowed before native TLS
   transport exists, and `native_tls` requiring its own implementation card.

## Recommended Next Card

```text
LAB-IGNITER-WEB-HOST-LIVE-BIND-CHECKLIST-PARSE-P34

Goal:
Add a host-owned, secret-free `[host.live_bind]` parser shape and diagnostics in
`server/igniter-web`, without enabling public bind and without passing a checklist
to `authorize_bind`.

Allowed:
- Extend `HostConfig` with parse-only live-bind checklist structs.
- Accept env/file references and booleans only.
- Add parser/unit/subprocess refusal tests.
- Update `server/igniter-web/IMPLEMENTED_SURFACE.md`.

Closed:
- No public listener enablement.
- No TLS transport.
- No real private keys/certs/tokens in fixtures.
- No `.igweb`, app, VM, compiler, machine, home-lab, SparkCRM, or canon changes.

Verification:
- `cargo test --manifest-path server/igniter-web/Cargo.toml --features machine --lib host_config`
- `cargo test --manifest-path server/igniter-web/Cargo.toml --features machine --test igweb_serve_diagnostics_tests`
- `cargo test --manifest-path server/igniter-web/Cargo.toml --test igniter_serve_wrapper_smoke_tests`
- `cargo test --manifest-path server/igniter-server/Cargo.toml --lib`
- `git diff --check`
```

## Verification Run

```text
cargo test --manifest-path server/igniter-server/Cargo.toml --lib
```

Result: PASS, 18 tests.

```text
cargo test --manifest-path server/igniter-web/Cargo.toml --test igniter_serve_wrapper_smoke_tests
```

Result: PASS, 17 tests.

```text
cargo test --manifest-path server/igniter-web/Cargo.toml --features machine --test igweb_serve_diagnostics_tests
```

Result: PASS, 5 tests.

```text
git diff --check
```

Result: PASS.
