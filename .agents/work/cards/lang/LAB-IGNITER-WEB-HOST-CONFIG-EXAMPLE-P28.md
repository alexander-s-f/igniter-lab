# LAB-IGNITER-WEB-HOST-CONFIG-EXAMPLE-P28 - operator-safe host.toml example

Status: CLOSED
Lane: IgWeb / runner production hygiene
Type: implementation + documentation
Delegation code: OPUS-WEB-HOST-CONFIG-EXAMPLE-P28
Date: 2026-06-22
Skill: idd-agent-protocol

## Context

Recent closed inputs:

- `LAB-IGNITER-WEB-IGWEB-SERVE-READ-BINDING-P25` - real Postgres reads wired into `igweb-serve`.
- `LAB-IGNITER-WEB-IGWEB-SERVE-WRITE-BINDING-P26` - real Postgres writes/effects wired into `igweb-serve`.
- `LAB-TODOAPP-API-IGWEB-SERVE-LOCAL-POSTGRES-P12` - real subprocess proof with temp `host.toml`.
- Commit `0be5b18 Wire igweb serve to postgres host bindings`.

Current gap:

The working `host.toml` shape exists mainly inside tests. A human/operator still has to mine test
helpers to learn the safe config fields, env-var names, effect routes, bearer-token env vars, and
what must NOT be committed.

## Goal

Add an operator-safe example config for `examples/todo_postgres_app` and wire it into README/docs so
`igweb-serve --host-config` can be repeated without reading Rust tests.

## Verify first

Read live code before editing:

- `server/igniter-web/src/host_config.rs`
- `server/igniter-web/src/host_binding.rs`
- `server/igniter-web/src/bin/igweb-serve.rs`
- `server/igniter-web/tests/todo_postgres_local_e2e_tests.rs`
- `server/igniter-web/examples/todo_postgres_app/host_policy.md`
- `server/igniter-web/README.md`

Confirm the exact current keys for `[postgres.read]`, `[postgres.write]`, and `[effects.*]`.

## Implementation bias

Prefer:

- `server/igniter-web/examples/todo_postgres_app/host.example.toml`
- Optional small section in `host_policy.md` or README pointing at it.
- Example uses **only env-var references**, never inline DSN or bearer token values.

Example should be runnable after setting env vars, but safe to commit:

```toml
[host]
mode = "loopback"

[postgres.read]
dsn_env = "IGNITER_TODO_PG_DSN"
source = "todos"
fields = "id,account_id,title,done"
row_limit = "100"
capability = "IO.PostgresRead"

[postgres.write]
dsn_env = "IGNITER_TODO_PG_DSN"
targets = "todos"
ops = "insert,upsert"
capability = "IO.TodoWrite"
key_column = "id"
columns = "account_id,title,done"

[effects.todo-create]
route = "/w"
passport_env = "IGNITER_TODO_EFFECT_TOKEN"

[effects.todo-done]
route = "/w"
passport_env = "IGNITER_TODO_EFFECT_TOKEN"
```

Adjust fields if live code says otherwise.

## Acceptance

- [x] Closing report states exact files changed.
- [x] `host.example.toml` parses with `load_host_config`.
- [x] Example contains no inline DSN, password, bearer token, raw SQL, or production host.
- [x] Example includes both read and write sections plus both Todo effect targets.
- [x] Docs show the exact command to run with `--features postgres -- --host-config ...`.
- [x] Docs clearly say `host.example.toml` is commit-safe and local copies with secrets are not.
- [x] Existing tests remain green for `server/igniter-web cargo test --features machine`.
- [x] `server/igniter-web cargo test --features postgres --test todo_postgres_local_e2e_tests -- --test-threads=1` passes or skips cleanly without DSN.
- [x] `git diff --check` clean.

## Closed surfaces

- No new parser features.
- No DDL migration runner.
- No public CLI stability claim.
- No production DB or SparkCRM interaction.
- No `.ig`/`.igweb` changes.

## Closing report

**Date:** 2026-06-22

### Files changed

- **NEW** `server/igniter-web/examples/todo_postgres_app/host.example.toml` — commit-safe operator
  config: `[host] mode`, `[postgres.read]` (dsn_env/source/fields/row_limit/capability),
  `[postgres.write]` (dsn_env/targets/ops/capability/key_column/columns), and BOTH effect targets
  `[effects.todo-create]` / `[effects.todo-done]` (route `/w` + `passport_env`). Env-var **names** only;
  no inline DSN, password, bearer token, raw SQL, or production host. Header comments give the exact
  `export …` + `cargo run --features postgres … --host-config …` command. Comments are on their own
  `#` lines (the parser rejects inline trailing comments because `parse_quoted` requires the value to
  end in `"`).
- **M** `server/igniter-web/src/host_config.rs` — added unit test `committed_host_example_toml_parses`
  (feature-free; runs on every `cargo test`) that loads the committed example via `CARGO_MANIFEST_DIR`
  and asserts it parses with both Postgres sections (exact keys/values) and both Todo effect targets.
  Durable guard so the example can never silently drift from the live parser.
- **M** `server/igniter-web/README.md` — new "Postgres Host Config (Operator)" section: the exact run
  command, what the example wires, and a precise commit-safety note (host.toml is commit-safe *by
  construction* — the parser rejects inline secret keys/templates — and the thing to keep out of VC is
  the environment that backs the `*_env` names: the DSN string and bearer token).
- **M** `server/igniter-web/examples/todo_postgres_app/host_policy.md` — added a top pointer to the
  runnable `host.example.toml` + README section as the exact config source of truth (the policy tables
  remain the conceptual view).

### Live verification

The exact documented command was run against a dedicated local DB (`igniter_todo_test`, never SparkCRM):
the binary parsed the committed example, resolved both DSNs, connected both real executors
("postgres.read/write executor connected"), served a real read returning `HTTP/1.1 200 OK`, and exited
deterministically (`served 1 request(s); exiting`). Smoke data cleaned afterward.

### Acceptance

- `host.example.toml` parses with `load_host_config` (unit test + live binary run).
- Contains no inline DSN/password/bearer token/raw SQL/production host (env-var names only).
- Includes both read and write sections plus both Todo effect targets.
- Docs show the exact `--features postgres -- --host-config …` command (README + the example's own header).
- Docs state host.toml is commit-safe and that the backing secret environment must not be committed.
- `cargo test --features machine` green; new parse test green on default `cargo test`.
- `cargo test --features postgres --test todo_postgres_local_e2e_tests -- --test-threads=1` → 8 pass,
  skips cleanly with no DSN set.
- `git diff --check` clean.

### Scope honored

No new parser features, no DDL migration runner, no CLI stability claim, no production/SparkCRM DB, no
`.ig`/`.igweb` changes.
