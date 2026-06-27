# LAB-MACHINE-MCP-AUTH-CHECKPOINT-SANDBOX-P30

Date: 2026-06-27
Lane: igniter-lab / runtime / igniter-machine / MCP / foundation-hardening / T1
Status: DONE

## Scope

This packet records a lab implementation in `runtime/igniter-machine`.
It does not create canon language authority and does not change MCP transport,
server/web binding, package/deploy behavior, VM, compiler, stdlib, frame-ui,
home-lab, SparkCRM, or canon repos.

## Implemented Shape

MCP protected tool calls now use a process-local env token:

```text
IGNITER_MCP_AUTH_TOKEN=<local token>
tools/call params.arguments.authority_token=<same local token>
```

`tools/call` fails closed when the env token is missing, empty, or does not
match the presented `authority_token`. `tools/list`, `initialize`, `ping`, and
MCP notifications remain available for protocol discovery.

The tool schemas now expose `authority_token` as a required argument for every
MCP tool. The token is compared at the MCP edge and is not written to receipts
or fact payloads by this implementation.

## Checkpoint Sandbox

`igniter_checkpoint` no longer writes directly to an arbitrary user path.
The handler resolves checkpoint paths under:

```text
IGNITER_MCP_CHECKPOINT_ROOT
```

When that env var is unset, the default root is:

```text
.igniter-mcp/checkpoints
```

The resolver creates and canonicalizes the root, lexically normalizes the
requested path, refuses traversal and arbitrary absolute paths outside the
root, refuses symlink checkpoint targets, creates safe in-root parent
directories, and verifies the canonical parent remains inside the root before
calling `IgniterMachine::checkpoint`.

## Reserved Store Policy

`igniter_write_fact` now refuses public writes to reserved internal stores.
The policy refuses all stores with the `__` prefix and explicitly covers known
reserved constants:

```text
__receipts__
__coord_audit__
__messenger__
__transfers__
__recipes__
__ingress_dedup__
```

Core `IgniterMachine::write_fact` was not changed, so internal machine and
coordination paths can continue to write their own reserved stores.

## P26 Relationship

P26 signed passport data-plane support is present in the working tree, but this
card did not reuse it for MCP. The chosen P30 shape is a smaller local stdio
boundary: a process-local env token presented per MCP `tools/call`. This keeps
MCP hardening independent from signed passport JSON transport semantics.

## Evidence

Changed source:

```text
runtime/igniter-machine/src/bin/mcp.rs
```

Tests added in the same binary:

```text
tools_call_requires_local_authority_and_allows_valid_token
checkpoint_paths_are_confined_to_mcp_root
public_write_edge_refuses_reserved_stores
tool_schemas_require_authority_token
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
cargo fmt: pass
cargo test --no-default-features --bin igniter-mcp: pass, 4 tests
cargo test --no-default-features: pass
git diff --check: pass
```
