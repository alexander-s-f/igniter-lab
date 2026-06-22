# LAB-IGNITER-HOST-CONFIG-SCHEMA-P3 - operator-owned host.toml schema and secret hygiene

Status: READY
Lane: machine / host IO / config hygiene
Type: implementation or readiness if P2 has not landed
Delegation code: OPUS-HOST-CONFIG-SCHEMA-P3
Date: 2026-06-22
Skill: idd-agent-protocol

## Context

P1 named `host.toml` as the missing operator-owned seam for machine-backed runners. Gemini's review flagged a
real safety issue: examples that put raw DSNs or passports into `host.toml` teach operators to commit secrets.

For v0, the rule should be stricter and simpler than string interpolation:

```text
host.toml stores names of environment variables, never secret values.
```

## Goal

Define and enforce the v0 host config schema shared by IgWeb machine runner and future CLI/desktop/science
runners.

This card may implement the parser if P2 has already landed a narrow parser. If P2 has not landed, write a
readiness/schema packet and leave code untouched.

## Verify first

Read:

```text
lab-docs/lang/lab-igniter-machine-host-io-substrate-readiness-p1-v0.md
server/igniter-web/src/lib.rs
server/igniter-web/src/bin/igweb-serve.rs
server/igniter-server/src/effect_host.rs
runtime/igniter-machine/src/ingress.rs
runtime/igniter-machine/src/capability.rs
```

Search for any host config work already added by P2:

```text
rg -n "host.toml|host_config|passport_env|dsn_env|target_routes|bind_target" server runtime lang
```

## v0 schema constraints

Allowed fields should be explicit and boring:

```toml
[host]
mode = "loopback"

[effects.<target>]
route = "/w"
passport_env = "IGNITER_EFFECT_PASSPORT"

[postgres.read]
dsn_env = "IGNITER_PG_DSN"

[postgres.write]
dsn_env = "IGNITER_PG_WRITE_DSN"
```

Rules:

- `*_env` value is an environment variable name, not an interpolated template.
- Unknown top-level sections fail closed.
- Unknown keys fail closed.
- Inline secret-ish keys fail closed: `dsn`, `password`, `secret`, `token`, `passport`, `api_key`.
- Empty env var names fail closed.
- Missing env var at runtime is an operator error before serving requests.
- `igweb.toml` must remain app-owned and must not grow effects/DSN/passport fields.

## Alternatives to compare if writing readiness

1. Env-name only (`dsn_env`) — recommended v0.
2. `${VAR}` interpolation — more familiar, but more parser surface and stringly secret leakage.
3. External secret provider abstraction — future, not v0.

## Closed surfaces

- No registry, cloud secret manager, Vault, Kubernetes-specific behavior, or production deployment claim.
- No `.ig`/`.igweb` syntax changes.
- No real DB connection required.
- No host config in app manifests.

## Acceptance

- [ ] Live source checked for existing host config surface.
- [ ] Env-name-only v0 rule is either implemented or specified with exact parser errors.
- [ ] Inline raw secret fields are rejected.
- [ ] `igweb.toml` remains app-owned and cannot name DSN/passport/effect identity.
- [ ] If implemented, tests cover allowed config, unknown keys, inline secret refusal, and missing env refusal.
- [ ] If readiness-only, packet names the exact implementation file/test targets.
- [ ] `git diff --check` clean.

## Closing report

TBD.
