# LAB-TODOAPP-API-ACCOUNT-EXISTENCE-P38 — missing-account vs empty-list semantics

**Date:** 2026-06-23
**Type:** implementation after verify-first
**Delegation:** OPUS-TODOAPP-API-ACCOUNT-EXISTENCE-P38
**Depends on:** LAB-TODOAPP-API-ACCOUNT-EXISTENCE-SEMANTICS-P37 (design)
**Status:** landed (this doc is the proof packet)
**Authority note:** lab evidence only — igniter-lang is canon; a lab proof does not create canon authority.

## TL;DR

`GET /accounts/:id/todos` now distinguishes the two empty-ish outcomes a single `todos` read could not:

- **account exists, zero todos → `200 []`**
- **account does not exist → `404 account not found`** (app-owned)

The index handler is a **two-stage staged read**: stage 1 reads `accounts` to prove existence (empty ⇒
404); only then does stage 2 list `todos` (empty ⇒ `200 []`). Implemented generically in the runner; all
product meaning stays in `.ig` + host policy. `igniter-server` is untouched.

## Verify-first decision

P37 suspected the runner could not run a continuation that itself returns a `ReadThen` (it returned 500).
**Confirmed:** `dispatch_with_read` handled exactly one `ReadThen` level. But adding sequential support is a
**small, generic loop** — *not* a broad runner rewrite — so per the card I implemented the slice (no
readiness delta). Three live-code facts shaped the design:

| Fact | Source | Implication |
| --- | --- | --- |
| One-level `ReadThen` only; a second → `map_decision` → 500 | `server/igniter-web/src/lib.rs` (old `dispatch_with_read`) | Need a bounded loop over `ReadThen`. |
| A continuation receives only `{ req, rows_json }` — **no `ctx`/route captures** | same | The 2nd read needs `account_id`, which the entry has but the continuation does not → thread it. |
| `.ig` has `split` but **no positional collection index** (`first`/`last` only) | `lang/igniter-stdlib/stdlib/collections.ig` | Can't recover `account_id` from `req.path` in `.ig` → carry it instead. |
| The real read adapter is **table-generic** (`SELECT … FROM {plan.source}`) and `PostgresReadPolicy` is already multi-source | `runtime/igniter-machine/src/postgres_real.rs:246`; `postgres_read.rs` | Reading `accounts` needs only a policy/config that allows it — no adapter change. |

## Design

**Generic primitive — `carry` on `ReadThen`.** The prelude variant became
`ReadThen { plan, then, carry : String }`. `carry` is an **opaque** string the host threads from a
`ReadThen` to its continuation input (`{ req, rows_json, carry }`); the host never interprets it. It lets
the entry pass the route-captured `account_id` to the continuation that builds the second plan.

**Bounded sequential loop.** `dispatch_with_read` now loops: dispatch → if `ReadThen`, run the staged read,
re-dispatch `then` with `{req, rows_json, carry}`, repeat; any non-`ReadThen` decision is terminal. The loop
is capped at `MAX_READ_HOPS = 8` (a generic safety rail, not a product limit) — exceeding it fails closed to
a host 500, so a buggy continuation chain can never spin forever.

**Two-stage `.ig` (account-first).**
```
AccountTodoIndex(req, ctx)        → ReadThen { FindAccount(ctx.account_id), then: CheckAccountThenList, carry: account_id }
CheckAccountThenList(req, rows, carry)
  rows == "[]"                     → Respond 404 "account not found"
  else                            → ReadThen { ListTodosByAccount(carry), then: AccountTodoIndexFromRows, carry: "" }
AccountTodoIndexFromRows(req,rows) → Respond 200 rows      (unchanged; now 200 [] only for existing accounts)
```

**Multi-source read config.** `[postgres.read.<name>]` sections add extra allowlisted sources (backward
compatible with the single `source`/`fields`). The example app's `host.example.toml` adds
`[postgres.read.accounts]` (`fields = "id,name"`) so the **real binary** can run the two-stage read.

## Authority split

| Concern | Owner | Where |
| --- | --- | --- |
| Sequential `ReadThen` loop + `carry` threading + bound | host runner (generic) | `lib.rs::dispatch_with_read` |
| Which tables are readable (allowlist) | host policy | `[postgres.read.*]` → `read_policy_binding` |
| "Account exists?" read, the 404 vs `200 []` decision, the `accounts` source name | app (`.ig`) | `FindAccount` / `CheckAccountThenList` |
| Generic read executor, adapter, SQL | machine | unchanged |

`igniter-server` carries no Todo/DB logic. `carry` is opaque to the host.

## HTTP / status mapping (exact, live)

| Scenario | Status | Owner | Decided by |
| --- | --- | --- | --- |
| existing account + todos | `200` rows | app | stage-2 rows → `AccountTodoIndexFromRows` |
| existing account + zero todos | `200 []` | app | stage-2 empty → `AccountTodoIndexFromRows` |
| missing account | `404 account not found` | app | stage-1 empty → `CheckAccountThenList` |
| denied source/field (e.g. `accounts` not allowlisted) | `403` | host | `StagedReadResult::Denied` → `dispatch_with_read` (adapter never called) |
| adapter/read failure (connect/query error, unknown outcome) | `503` | host | `StagedReadResult::HostError` → `dispatch_with_read` |
| runaway continuation chain (> `MAX_READ_HOPS`) | `500` | host | loop bound in `dispatch_with_read` |

## What changed

| File | Change |
| --- | --- |
| `lang/igniter-compiler/src/igweb.rs` | `ReadThen` variant gains `carry : String`. |
| `server/igniter-web/src/lib.rs` | `dispatch_with_read` → bounded sequential-`ReadThen` loop threading `carry`. |
| `server/igniter-web/src/host_config.rs` | parse `[postgres.read.<name>]` extra sources (`extra_sources`); 2 parser tests. |
| `server/igniter-web/src/host_binding.rs` | `read_policy_binding` allows each extra source. |
| `…/examples/todo_postgres_app/todo_handlers.ig` | `FindAccount` + `CheckAccountThenList`; `AccountTodoIndex` two-stage; `carry: ""` on the show `ReadThen`. |
| `…/examples/todo_postgres_app/host.example.toml` | `[postgres.read.accounts]`. |
| `tests/fixtures/read_then_fixture/read_then_fixture.ig` | `carry: ""` on the existing `ReadThen`; new self-looping `LoopForever` (bound test). |
| `tests/*` | account-existence matrix (fake + real PG), bounded-loop test, multi-source config tests; existing index tests updated to seed `accounts` + two-read counts. |

## Evidence

- `cargo test --features machine` (igniter-web): **28 suites green, 0 failures**, incl.
  - `runaway_readthen_chain_is_bounded` — a self-looping `ReadThen` fails closed to 500 with a bounded
    number of adapter reads (≤ 8).
  - `read_missing_account_via_runner_404` / `read_found_…_200` (2 reads) / `read_empty_…_200_empty_list`
    (2 reads) — the full matrix through the real machine runner + fake multi-source read host.
  - `read_denied_by_host_is_403_no_leak` — denied source → 403, adapter untouched.
  - `postgres_read_extra_sources_parse` — multi-source config round-trips.
- `cargo test` (igniter-compiler): **green** (prelude `carry` change; only 3 `ReadThen` emitters, all updated).
- `IGNITER_TODO_PG_DSN=… cargo test --features "machine postgres" --test todo_postgres_local_e2e_tests -- --test-threads=1`: **13 passed**, incl.
  - `local_account_existence_missing_404_and_existing_empty_200` — real PG, both cases isolated.
  - `subprocess_product_command_read_write_replay_e2e` — the **real `igweb-serve` binary** returns
    `404 account not found` for a never-created account (the old code returned `200 []`).
- `git diff --check`: clean.

## Acceptance (card)

- [x] Existing account with rows → `200` and rows JSON.
- [x] Existing account with zero todos → `200 []`.
- [x] Missing account → `404` app-owned response (not host infra error).
- [x] Denied account source/field → host-owned `403`, adapter not called.
- [x] Adapter/read failure remains host-owned infra status (`503`; mapping table above).
- [x] Nested/sequential `ReadThen` is generic and bounded (`MAX_READ_HOPS`, proven by `runaway_readthen_chain_is_bounded`).
- [x] No DB-specific or Todo-specific logic enters `igniter-server`.
- [x] API.md + RUNBOOK reflect the account-existence semantics.
- [x] Fake/no-DB tests cover the semantic matrix.
- [x] Real/local Postgres e2e covers missing account and existing-empty account (skips cleanly without DSN).
- [x] `cargo test --features machine` passes.
- [x] `cargo test --features "machine postgres" --test todo_postgres_local_e2e_tests -- --test-threads=1` passes (skips without DSN).
- [x] `git diff --check` clean.

## Closed surfaces honoured

- No object-body/id-generation changes (P35/P36 untouched).
- No global query planner / JOIN support — each stage is one single-table plan.
- No hidden host interpretation of product meaning — `carry` is opaque; the `accounts` source name and the
  404 decision live in `.ig`.
- No server route table.
- Schema: tests reuse the existing local fixture DDL (`accounts` table already present); no migration runner.

## Honest limits

- The DSN-gated suite runs with `--test-threads=1` (pre-existing: several tests share an account id; the
  two-stage reads use one extra `SELECT` on `accounts` per index request).
- `carry` is a single opaque `String` — enough for one route capture. Richer continuation state (multiple
  values / typed) is not modelled; a continuation needing more would pass a delimited string or await a
  future typed-carry card.
- Two reads per index request (account existence + list). No JOIN/single-round-trip optimization (an
  explicit closed surface).
