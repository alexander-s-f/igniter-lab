# LAB-IGNITER-WEB-HOST-LIVE-BIND-CHECKLIST-PARSE-P34

Date: 2026-06-28
Status: DONE
Route: standard / main-audit / igniter-web / live-bind gate
Implements: audit-control-board row A10 (loopback-to-live gate)
Depends-On: `LAB-IGNITER-SERVER-LIVE-BIND-GATE-P31`,
`LAB-IGNITER-WEB-LIVE-BIND-GATE-WIRING-P32`,
`lab-docs/lang/lab-igniter-server-live-bind-tls-checklist-readiness-p33-v0.md`

This packet is lab evidence only. It does not create canon language authority, does not
enable public bind, does not add TLS transport, and does not change `.igweb`, app code,
VM, compiler, machine, home-lab, SparkCRM, or private governance files.

## What changed

Implemented the P33 Decision (Alternative A): a host-owned, secret-free, **parse-only**
`[host.live_bind]` checklist in `server/igniter-web/src/host_config.rs`. The parser now
validates a live-bind readiness checklist and fails closed with actionable diagnostics on
an incomplete/invalid one — **without** passing any checklist into `authorize_bind`, so
non-loopback bind stays refused.

- `HostConfig.live_bind: Option<LiveBindConfig>` (parsed shape).
- `LiveBindConfig` + `LiveBindTlsConfig` (`TerminatedUpstream` | `NativeTls`).
- New fail-closed `HostConfigError` variants (all classify as `CONFIG_PARSE`).
- `INLINE_SECRET_KEYS` strengthened with `key` and `cert` so an inline TLS private key /
  certificate fails closed with the "use a file reference" diagnostic.
- Committed parse-only example `examples/todo_postgres_app/host.live_bind.example.toml`.
- Unit tests (`host_config`), subprocess tests (`igweb_serve_diagnostics_tests`).

The runner (`src/bin/igweb-serve.rs`) is **unchanged**: it still calls
`authorize_bind(addr, None)` before every listener bind. `[host] mode` still only accepts
`"loopback"`; `"public"` is still refused (even when a complete `[host.live_bind]` is
present).

## Exact config schema

```toml
[host]
mode = "loopback"            # still the only accepted mode; "public" is refused

[host.live_bind]
signed_passport_path = "/etc/igniter/passports/inbound.passport"  # file PATH reference only
body_cap_enabled = "true"            # must be "true"
read_timeout_enabled = "true"        # must be "true"
fail_closed_auth_enabled = "true"    # must be "true"
operator_signoff = "present"         # opaque non-secret marker (e.g. a change-ticket id)

[host.live_bind.inbound_tls]
mode = "terminated_upstream"         # "terminated_upstream" | "native_tls"; no "none"
upstream_header_policy = "trusted_proxy_only"   # required for terminated_upstream
# For mode = "native_tls" instead (parse-only; transport still blocked):
# cert_file = "/etc/igniter/certs/site.crt"     # PATH reference only
# key_file  = "/etc/igniter/certs/site.key"     # PATH reference only
```

Field reference:

| Field | Kind | Rule |
| --- | --- | --- |
| `signed_passport_path` | file ref | required; non-empty; no template `$`/`{`/`}` |
| `body_cap_enabled` | bool (`"true"`/`"false"`) | required; must be `"true"` |
| `read_timeout_enabled` | bool | required; must be `"true"` |
| `fail_closed_auth_enabled` | bool | required; must be `"true"` |
| `operator_signoff` | opaque | required; non-empty |
| `inbound_tls.mode` | enum | required; `terminated_upstream` or `native_tls` |
| `inbound_tls.upstream_header_policy` | opaque | required iff `terminated_upstream` |
| `inbound_tls.cert_file` | file ref | required iff `native_tls`; non-empty; template-free |
| `inbound_tls.key_file` | file ref | required iff `native_tls`; non-empty; template-free |

**Quoted-value note.** This is a minimal hand-rolled parser where every value is a quoted
string (matching `route`, `dsn_env`, etc.), so booleans are written `"true"`/`"false"`,
not bare TOML `true`. This is deliberate parser uniformity, not real TOML semantics.

**Why the section is split.** `[host.live_bind]` carries the structural assertions;
`[host.live_bind.inbound_tls]` isolates the mandatory TLS decision so `native_tls` cert/key
references live in one block. A dangling `[host.live_bind.inbound_tls]` with no
`[host.live_bind]` still triggers completeness validation and fails closed.

## Refusal taxonomy

Every live-bind parse failure maps to `DiagCode::CONFIG_PARSE` (exit 2) via
`classify_host_config_error` — none is a runtime resolve error — and is caught **before any
listener bind**. New `HostConfigError` variants:

| Variant | Trigger | Operator message names |
| --- | --- | --- |
| `LiveBindMissingField{field}` | required field absent (incl. `inbound_tls.mode`) | the missing field |
| `LiveBindFalseAssertion{field}` | a boolean assertion is `"false"` | the field that must be `"true"` |
| `LiveBindBadBool{key,value}` | boolean not `"true"`/`"false"` | the key + offending (non-secret) value |
| `LiveBindEmptyValue{key}` | empty file ref / signoff / policy / mode | the key |
| `LiveBindTemplateValue{key}` | `$`/`{`/`}` in a file ref | the key |
| `LiveBindUnsupportedTlsMode{mode}` | mode not in the allowlist (incl. `"none"`) | the rejected mode |
| `LiveBindMissingTlsField{mode,field}` | `native_tls` w/o cert/key, or `terminated_upstream` w/o policy | the mode + missing field |
| `InlineSecret{key}` (existing, extended) | bare `passport`/`token`/`key`/`cert`/… inlined | the secret-bearing key |
| `UnknownKey` / `UnknownSection` (existing) | any unknown key/section in the blocks | the key/section |

No diagnostic prints resolved secret values or file contents. Booleans, mode enums, and
operator markers are non-secret and may appear verbatim. File references are validated for
shape only — never read.

## Why public bind remains closed

The checklist is **readiness, not authority** (IDD axiom 2). Three independent locks keep a
public listener closed, all unchanged by this card:

1. The runner passes **no** checklist to `authorize_bind` — it always calls
   `authorize_bind(addr, None)`. A complete `[host.live_bind]` does not become a
   `LiveBindChecklist`/`LiveBindToken`; the server gate still returns
   `non_loopback_without_checklist` for any non-loopback address.
2. `[host] mode` still only accepts `"loopback"`; `"public"` is refused at parse time even
   with a complete checklist.
3. `ServingPolicy::loopback_only()` remains post-bind defense-in-depth.

Subprocess proof: `complete_live_bind_still_refuses_non_loopback_bind` — a full checklist
plus `--addr 0.0.0.0:0` exits non-zero with `[BIND_REFUSED] … non_loopback_without_checklist`
and never prints a `listening http` line. `complete_live_bind_loopback_still_serves_and_exits_zero`
proves loopback DX is unchanged.

## What would authorize a real live-bind proof later

A future card (a **gate decision**, per IDD) — not a parse slice — must, in order:

1. Decide the trust path that turns a parsed `LiveBindConfig` into the server-owned
   `LiveBindChecklist` (the boolean assertions are operator *claims*; the host must verify
   the underlying mechanisms — body cap, read timeout, fail-closed auth, signed-passport
   wiring — are actually in force, not just asserted).
2. Implement and wire the signed-passport verification at the inbound seam (the broader
   audit blocker: production must stop trusting a forgeable passport).
3. For `native_tls`, ship an actual TLS transport implementation (still blocked here);
   `terminated_upstream` may be allowed first, contingent on the proxy-mode review.
4. Pass the verified checklist into `authorize_bind` and prove a non-loopback bind opens
   **only** with a complete, verified checklist — under an explicit human-gated step on a
   security checklist, never as a default or ad-hoc CLI flag.

Until all of the above land, IgWeb is loopback-only and this section is operator-checkable
documentation of intent, nothing more.

## Verification run

```text
cargo test --manifest-path server/igniter-web/Cargo.toml --features machine --lib host_config
```
Result: PASS, 74 tests (incl. the P34 live-bind cases + committed-example guard).

```text
cargo test --manifest-path server/igniter-web/Cargo.toml --features machine --test igweb_serve_diagnostics_tests
```
Result: PASS, 8 tests (incl. incomplete→CONFIG_PARSE, complete+non-loopback→BIND_REFUSED,
complete+loopback→serves).

```text
cargo test --manifest-path server/igniter-web/Cargo.toml --features machine
```
Result: PASS (full crate under the machine feature).

```text
git diff --check
```
Result: PASS.

Note: bare `cargo test --manifest-path server/igniter-web/Cargo.toml` (no features) does not
compile `tests/signed_effect_passport_tests.rs`, which imports `igniter_server::effect_host`
unconditionally while that module is `machine`-gated. This is **pre-existing** (the file is
unchanged from HEAD; the P34 test additions live in the already-`machine`-gated diagnostics
file) and unrelated to this card. Run the `--features machine` superset above.
