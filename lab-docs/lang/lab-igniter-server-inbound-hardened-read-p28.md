# LAB-IGNITER-SERVER-INBOUND-HARDENED-READ-P28

Date: 2026-06-27
Status: CLOSED
Lane: igniter-lab / server / web / machine / foundation-hardening / T1

## Scope

This proof closes the local inbound hardening slice only. It does not add public
bind support, TLS, outbound network capability, app route semantics, grammar,
VM/compiler/stdlib changes, frame-ui changes, home-lab changes, SparkCRM
integration, or canon `igniter-lang` authority.

## Policy Defaults

Shared server policy:

- `DEFAULT_MAX_HEADER_BYTES = 16 * 1024`
- `DEFAULT_MAX_BODY_BYTES = 1024 * 1024`
- `DEFAULT_READ_TIMEOUT = 5s`

`server/igniter-server/src/host.rs` now exposes `HardenedReadPolicy` and uses it
for the sync loopback host. `server/igniter-server/src/effect_host.rs` reuses
the same policy for async machine-backed server reads.

`runtime/igniter-machine/src/ingress.rs` duplicates the same tiny
`HardenedReadPolicy` shape because directly sharing server code would couple the
machine crate back to the server crate. The duplicate is intentionally narrow:
same defaults, same cap-before-body-read behavior, same timeout mapping.

Read error HTTP mapping:

- timeout / would-block: `408 {"error":"request timeout"}`
- body too large: `413 {"error":"payload too large"}`
- headers too large: `431 {"error":"request headers too large"}`
- other malformed read: `400 {"error":"bad request"}`

## Paths Covered

- `server/igniter-server/src/host.rs`
  - caps request headers before unbounded header accumulation
  - rejects `Content-Length > max_body_bytes` before reading the full body
  - applies socket read timeout before app dispatch
  - writes read-error responses without calling `ServerApp::call`

- `server/igniter-server/src/effect_host.rs`
  - async read policy mirrors sync host behavior
  - read errors write hardened responses before `ServerApp::call`

- `runtime/igniter-machine/src/ingress.rs`
  - ingress read loop now has cap, timeout, and read-error responses before
    `IngressRouter::handle` / `handle_effect`

- `server/igniter-server/src/middleware.rs`
  - empty expected bearer token fails closed
  - inbound `x-auth-ok` is removed before auth evaluation
  - successful auth inserts a fresh host-owned `x-auth-ok: true`

- `server/igniter-web/src/machine_runner.rs`
  - loaded async runner gained `LoadedMiddleware`
  - machine-mode request flow mirrors sync manifest middleware order:
    `BodyLimit -> Auth -> Trace -> loaded dispatch`

- `server/igniter-web/src/bin/igweb-serve.rs`
  - machine-mode runner builds `LoadedMiddleware::from_manifest(&manifest)`
    and passes it to both real write-host and fallback effect-host paths

## Proof Commands

```text
cd server/igniter-server
cargo test --test loopback_tests --test middleware_tests
```

Result: PASS, 7/7 `loopback_tests`, 10/10 `middleware_tests`.

```text
cd server/igniter-server
cargo test --features machine --test effect_machine_tests
```

Result: PASS, 10/10.

```text
cd runtime/igniter-machine
cargo test --test service_http_ingress_tests
```

Result: PASS, 11/11.

```text
cd server/igniter-web
cargo test --features machine --test async_machine_runner_tests
```

Result: PASS, 7/7.

```text
cd server/igniter-web
cargo test --features machine --test igweb_serve_machine_mode_tests
```

Result: PASS, 12/12.

```text
git diff --check
```

Result: PASS, no whitespace errors.

## Acceptance Mapping

- Oversized sync request rejected before app dispatch:
  `oversized_content_length_rejected_before_app_dispatch`

- Oversized effect/machine request rejected before dispatch:
  `async_read_policy_rejects_oversized_content_length`,
  `ingress_read_policy_rejects_oversized_content_length`

- Slow/incomplete read times out deterministically:
  `incomplete_body_times_out_before_app_dispatch`,
  `async_read_policy_times_out_incomplete_body`,
  `ingress_read_policy_times_out_incomplete_body`

- Empty auth token fails closed:
  `auth_empty_expected_token_fails_closed`

- Inbound `x-auth-ok` spoof refused/stripped:
  `auth_strips_inbound_auth_ok_spoof`,
  `loaded_runner_applies_manifest_auth_and_trace_before_dispatch`

- Machine-mode IgWeb honors configured middleware:
  `loaded_runner_applies_manifest_auth_and_trace_before_dispatch`,
  `loaded_runner_applies_manifest_body_limit_before_dispatch`,
  `igweb_serve_machine_mode_tests`

## Remaining Follow-Up

Public bind support and TLS remain closed here. The hardened read/auth seam is a
prerequisite for a later loopback-to-live gate, not a live listener enablement.
