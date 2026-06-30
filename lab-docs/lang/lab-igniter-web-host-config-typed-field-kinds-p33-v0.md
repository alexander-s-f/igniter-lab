# lab-igniter-web-host-config-typed-field-kinds-p33-v0

Card: `LAB-IGNITER-WEB-HOST-CONFIG-TYPED-FIELD-KINDS-P33`
Route: standard / main-audit / igweb / host config / typed read adoption
Skill: idd-agent-protocol
Status: implemented (lab IgWeb host-config surface) - no canon claim
Date: 2026-06-27

> **Authority boundary.** Lab IgWeb implementation. This exposes already-proven typed Postgres read lanes
> through operator `host.toml`; it does not add `.igweb` syntax, compiler semantics, VM semantics, schema
> inference, migrations, or a production deployment promise.

## Syntax

Per-source typed read kinds live in a dedicated table next to the existing source allowlist:

```toml
[postgres.read]
dsn_env = "IGNITER_PG_READ_DSN"
source = "todos"
fields = "id,title,done,amount"

[postgres.read.todos.fields]
done = "bool"
amount = "decimal:2"

[postgres.read.accounts]
fields = "id,active"

[postgres.read.accounts.fields]
active = "bool"
```

The `fields` comma-list remains the allowlist. The `[postgres.read.<source>.fields]` table only declares
decode kinds for already-allowlisted fields. A missing kind is backwards-compatible `Text`.

## Supported Kinds

| Config string | Host kind | Landing |
| --- | --- | --- |
| `text` | `PostgresReadValueKind::Text` | JSON string / `.ig String` or `Text` |
| `integer` | `PostgresReadValueKind::Integer` | JSON integer / `.ig Integer` |
| `bool` | `PostgresReadValueKind::Boolean` | JSON bool / `.ig Bool` |
| `decimal:<scale>` | `PostgresReadValueKind::Decimal { scale }` | exact decimal string decoded by adapter, host-materialized as `{value,scale}`, then `.ig Decimal[scale]` |

Only `decimal:<scale>` is accepted for typed Decimal. `decimal` without a scale is refused.

## Refusal Taxonomy

| Refusal | Where | Outcome |
| --- | --- | --- |
| Unknown kind string, e.g. `timestamp` | `parse_host_config` | `HostConfigError::Parse` before bind |
| `decimal` or `decimal:` without a valid `u32` scale | `parse_host_config` | `HostConfigError::Parse` before bind |
| `[postgres.read.<source>.fields]` without matching primary/extra source | `parse_host_config` final validation | `HostConfigError::Parse` before bind |
| Kind declared for a non-allowlisted field | `parse_host_config` final validation | `HostConfigError::Parse` before bind |
| Field omitted from kind map | `read_policy_binding` / `PostgresReadPolicy::field_kind` | Backwards-compatible `Text` |
| App row type incompatible with host kind | typed `ReadThen` reconcile | `projection_schema_drift` before continuation dispatch |
| Row value shape violates declared host kind | materializer | `projection_row_mismatch` / typed schema mismatch before app logic |

## Implementation

- `server/igniter-web/src/host_config.rs`
  - Adds `PostgresReadConfig.field_kinds`.
  - Parses `[postgres.read.<source>.fields]` before generic `[postgres.read.<name>]`.
  - Validates kind tables against configured source/field allowlists.
- `server/igniter-web/src/host_binding.rs`
  - Maps config kinds into `PostgresReadPolicy.field_kinds`.
  - Keeps source/field allowlist authority in `fields`.
- `server/igniter-web/tests/typed_readthen_tests.rs`
  - `matched_policy` and drift policy now come from `parse_host_config -> read_policy_binding`.
- `server/igniter-web/tests/decimal_crossing_tests.rs`
  - Decimal policy now comes from `amount = "decimal:<scale>"`.

## Tests

Verified:

```bash
cargo test --manifest-path server/igniter-web/Cargo.toml --lib host_config
cargo test --manifest-path server/igniter-web/Cargo.toml --lib host_binding
cargo test --manifest-path server/igniter-web/Cargo.toml --features machine --test typed_readthen_tests
cargo test --manifest-path server/igniter-web/Cargo.toml --features machine --test decimal_crossing_tests
```

Expected counts from this slice: `host_config` 53 passed, `host_binding` 10 passed, `typed_readthen_tests`
9 passed, `decimal_crossing_tests` 4 passed.

## Remaining Gaps

Still closed/deferred: Timestamp config strings, nested JSON-to-record decoding, native Postgres array typing,
schema inference from DB, migration runner, multi-DSN reads, `.igweb` authoring syntax changes, compiler/VM/canon
changes, and automatic product-route migration. Route-specific Bool/Decimal adoption should be a separate card
that reviews the app row type before changing the shipped route policy.
