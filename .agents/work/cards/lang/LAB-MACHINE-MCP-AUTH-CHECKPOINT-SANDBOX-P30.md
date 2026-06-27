# LAB-MACHINE-MCP-AUTH-CHECKPOINT-SANDBOX-P30 - gate MCP tools and sandbox checkpoint paths

Status: DONE
Lane: igniter-lab / runtime / igniter-machine / MCP / foundation-hardening / T1
Type: implementation / local authority hardening
Date: 2026-06-27
Skill: idd-agent-protocol
Depends-On:
- `LAB-MACHINE-SIGNED-PASSPORT-DATAPLANE-P26` if reusing the signed verifier path
Source:
- `lab-docs/igniter-machine-core-foundation-audit-p1.md`
- `lab-docs/igniter-foundation-hardening-next-wave-p1.md`

## Agent Onboarding Header

This is T1-4. The MCP binary is local/stdio, but if an untrusted local process
can speak MCP, unauthenticated tools become full machine authority. Checkpoint
also accepts arbitrary paths. Harden this edge without changing core machine
semantics.

## Goal

Make MCP authority explicit and fail-closed:

```text
MCP tools/call without valid local authority -> refused
checkpoint outside allowed root             -> refused
writes to reserved internal stores          -> refused at public write edge
normal authorized local MCP use             -> still works
```

## Verify-First Anchors

Before editing, verify live line numbers:

```text
runtime/igniter-machine/src/bin/mcp.rs
  tool dispatch around prior :922
  igniter_checkpoint handler around prior :601
runtime/igniter-machine/src/machine.rs
  checkpoint(path) around prior :435
runtime/igniter-machine/src/capability.rs
  RECEIPTS_STORE
runtime/igniter-machine/src/coordination.rs
  reserved stores like __messenger__, __transfers__, __recipes__, __ingress_dedup__
```

Fresh grep from card creation showed:

```text
bin/mcp.rs:601 handle_checkpoint
bin/mcp.rs:937 igniter_checkpoint dispatch
machine.rs:435 checkpoint(path)
capability.rs:298 RECEIPTS_STORE
coordination.rs reserved __...__ stores
```

## Current Authority

- Live `runtime/igniter-machine` source/tests decide behavior.
- Audit docs are evidence only.
- This card may edit only `runtime/igniter-machine` source/tests and this card.

## Closed Surfaces

- Do not add network MCP transport.
- Do not change package/deploy/public bind behavior.
- Do not edit web/server/VM/compiler/stdlib/frame-ui/home-lab/SparkCRM/canon.
- Do not require real secrets for tests.

## Required Design

- Choose one local MCP auth shape:
  - signed passport per tool call;
  - process-local env token mapped to a passport;
  - explicit `--dev-allow-unauthenticated` for tests only.
- Default must fail closed for protected tools if no authority is provided.
- Checkpoint path must be under a configured/canonical allowed root, or default
  to a safe local directory.
- Reserved store names (`__...__` and known constants) should not be writable
  through general public write tools unless the tool is explicitly internal.

If the correct MCP auth shape is not obvious, write a short readiness packet and
close this card as design-only; do not ship a confusing partial bypass.

## Acceptance

- [x] MCP protected tool without authority is refused.
- [x] Authorized MCP protected tool still works in a deterministic local test.
- [x] `igniter_checkpoint` refuses path traversal / arbitrary absolute path.
- [x] Public write edge refuses reserved store writes.
- [x] Existing machine tests pass or unrelated failures are isolated.
- [x] `git diff --check` passes.

## Proof / Closing

Write:

```text
lab-docs/lang/lab-machine-mcp-auth-checkpoint-sandbox-p30.md
```

Close with exact auth shape, checkpoint sandbox policy, reserved-store policy,
commands/results, and whether P26 was required or already live.

## Closure Evidence

Implemented in:

```text
runtime/igniter-machine/src/bin/mcp.rs
```

Proof packet:

```text
lab-docs/lang/lab-machine-mcp-auth-checkpoint-sandbox-p30.md
```

Auth shape:

```text
IGNITER_MCP_AUTH_TOKEN=<local token>
tools/call params.arguments.authority_token=<same local token>
```

Checkpoint root:

```text
IGNITER_MCP_CHECKPOINT_ROOT, default .igniter-mcp/checkpoints
```

Reserved store policy:

```text
refuse __* plus known internal stores at igniter_write_fact public edge
```

Commands:

```text
cargo fmt --manifest-path runtime/igniter-machine/Cargo.toml
cargo test --no-default-features --bin igniter-mcp
cargo test --no-default-features
git diff --check
```

Results:

```text
fmt pass
igniter-mcp bin tests pass: 4/4
machine crate tests pass
git diff --check pass
```

P26 signed passport data-plane support was not required for this MCP-local auth
shape. It remains a separate live path in the working tree.
