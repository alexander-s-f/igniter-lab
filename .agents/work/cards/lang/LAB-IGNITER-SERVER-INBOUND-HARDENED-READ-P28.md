# LAB-IGNITER-SERVER-INBOUND-HARDENED-READ-P28 - shared body cap, read timeout, and fail-closed auth

Status: DONE
Lane: igniter-lab / server / web / machine / foundation-hardening / T1
Type: implementation / transport hardening
Date: 2026-06-27
Skill: idd-agent-protocol
Source:
- `lab-docs/igniter-server-core-foundation-audit-p1.md`
- `lab-docs/igniter-web-core-foundation-audit-p1.md`
- `lab-docs/igniter-machine-core-foundation-audit-p1.md`
- `lab-docs/igniter-foundation-hardening-next-wave-p1.md`

## Agent Onboarding Header

This is T1-3: transport hardening before any non-loopback/live bind. Current
read loops can allocate unbounded request bodies and lack read timeouts. Auth is
also opt-in/fail-open in places. This card hardens the local server/machine
front doors without changing application semantics.

## Goal

Introduce one shared hardened-read policy where practical:

```text
body cap before allocation
read timeout before app dispatch
fail-closed empty auth token
machine-mode web runner composes configured middleware
strip/refuse inbound x-auth-ok spoofing if that header is used
```

Do not add public TLS/listener support here; this is the prerequisite hardening
that the later loopback→live gate will require.

## Verify-First Anchors

Before editing, verify live line numbers:

```text
server/igniter-server/src/host.rs
  read_request
server/igniter-server/src/effect_host.rs
  read_server_request
  serve_once_effect
server/igniter-server/src/middleware.rs
  AuthTokenApp
  BodyLimitApp
server/igniter-web/src/lib.rs
  compose(...)
server/igniter-web/src/bin/igweb-serve.rs
  machine-mode runner / compose gap
runtime/igniter-machine/src/ingress.rs
  serve_once_effect / ingress read loop
```

Fresh grep from card creation showed:

```text
igniter-server/host.rs:213 read_request
igniter-server/effect_host.rs:156 read_server_request
igniter-server/middleware.rs:85 AuthTokenApp
igniter-web/lib.rs:904 compose
igniter-web/bin/igweb-serve.rs:299 / :327 machine-mode policy paths
igniter-machine/ingress.rs:1110 serve_once_effect
```

## Current Authority

- Live server/web/machine source/tests decide behavior.
- Audit docs are evidence only.
- This card may edit `server/igniter-server`, `server/igniter-web`, and
  `runtime/igniter-machine` only as needed for the transport read/auth seam.

## Closed Surfaces

- Do not add public bind support.
- Do not add outbound network capability.
- Do not change app route/domain behavior, `.igweb` grammar, VM, compiler,
  stdlib, frame-ui, home-lab, SparkCRM, or canon `igniter-lang`.
- Do not solve signed passports here except to preserve compatibility with P26/P27.

## Required Design

- Prefer a small `ReadLimits` / `HardenedReadPolicy` type over scattered magic
  numbers.
- Bound request body before allocating the full body buffer.
- Use deterministic timeout errors.
- `AuthTokenApp::new` with an empty token must fail closed or be impossible to
  construct.
- Machine-mode IgWeb runner must use the same middleware composition semantics
  as sync mode when manifest middleware is configured.

If one crate cannot share code directly without a dependency cycle, duplicate a
tiny policy shape and document the follow-up; do not create a broad new crate in
this slice.

## Acceptance

- [x] Oversized request is rejected before app dispatch in sync server path.
- [x] Oversized request is rejected before app dispatch in effect/machine path.
- [x] Slow/incomplete read times out deterministically.
- [x] Empty auth token fails closed.
- [x] Machine-mode IgWeb path honors configured middleware composition.
- [x] Existing loopback tests remain green.
- [x] Focused server/web/machine tests pass.
- [x] `git diff --check` passes.

## Proof / Closing

Write:

```text
lab-docs/lang/lab-igniter-server-inbound-hardened-read-p28.md
```

Close with exact policy defaults, exact paths covered, commands/results, and
remaining TLS/public-bind follow-up.
