# Card: LAB-IGNITER-RELATIONAL-QUERYPLAN-BRIDGE-P3 — `.ig` QueryPlan to fake Postgres executor

**Lane:** standard / lab implementation proof · **Skill:** idd-agent-protocol  
**Status: CLOSED**  
**Delegation:** OPUS-RELATIONAL-QUERYPLAN-BRIDGE-P3

## Intent

Bridge the relational Todo language shape from P2 to the existing **fake**
Postgres read executor, without a live DB:

```text
pure .ig relational query contract shape
  -> structured QueryPlan JSON/value
  -> runtime/igniter-machine PostgresReadExecutor (fake adapter)
  -> allowlist gates + row-limit clamp + receipt/replay
```

This card proves the `.ig` intent shape and machine read boundary meet cleanly.
It does **not** implement real DB behavior, SQL, typed reads, or a new language
feature.

## Authority

Lab proof only. Current authorities:

- language shape: P2 fixture + real compiler;
- machine read behavior: `runtime/igniter-machine/src/postgres_read.rs`;
- safety gates: `CapabilityExecutor` / `run_effect` receipt path.

This card may change:

- tests under `runtime/igniter-machine/tests/` or a narrow shared test-support
  fixture if already conventional;
- optionally a small test fixture under `lang/igniter-compiler/tests/fixtures/`
  only if the P2 fixture must be reused from tests;
- one proof doc under `lab-docs/lang/`;
- this card's closing report.

Prefer no production source changes. If a tiny test-only adapter/helper is
needed, justify it in the proof.

Closed:

- no live Postgres;
- no `postgres` feature / DSN;
- no `tokio-postgres` tests;
- no compiler/typechecker/parser changes;
- no VM changes;
- no real SQL execution;
- no DB schema/migrations;
- no IgWeb runner/server change;
- no ORM or SQL DSL.

## Verify First

Read current surfaces:

- `lab-docs/lang/lab-igniter-relational-contracts-todo-p2-v0.md`
- `lang/igniter-compiler/tests/fixtures/relational_todo/relational_todo.ig`
- `lang/igniter-compiler/tests/relational_todo_tests.rs`
- `runtime/igniter-machine/src/postgres_read.rs`
- `runtime/igniter-machine/tests/postgres_read_tests.rs`
- `runtime/igniter-machine/src/capability.rs`
- `runtime/igniter-machine/IMPLEMENTED_SURFACE.md`

Re-verify paths: after repo reorg, machine lives under
`runtime/igniter-machine/`.

## Core Decision To Make

There are two possible proof shapes. Pick the smallest honest one after
verify-first:

### A. Real VM evaluation bridge

If existing test infrastructure can execute the P2 `.ig` contract and get its
`QueryPlan` result as JSON/value cheaply, use it.

Proof:

```text
RelationalTodo.TodosByAccount("acct-7") executed
  -> QueryPlan value
  -> PostgresReadExecutor fake adapter
```

### B. Host-side mirror bridge

If executing compiled `.ig` from the machine test is not a small existing path,
do **not** invent a new runtime bridge. Instead, create a host-side mirror JSON
that is byte/shape-aligned to the P2 fixture and feed that to
`PostgresReadExecutor`.

Proof:

```text
P2 fixture compiles and defines the shape
host test constructs the same QueryPlan JSON shape
  -> PostgresReadExecutor fake adapter
```

If choosing B, the proof doc must say clearly that actual VM-result extraction
is deferred to a later card. Do not overclaim.

## Required Behavior

Use the existing fake `PostgresReadExecutor` path. Prove:

1. **Shape match.** A P2-style plan:

   ```json
   {
     "source": "todos",
     "op": "select",
     "projection": ["id", "account_id", "title", "done"],
     "filters": [{"field": "account_id", "op": "eq", "value": "acct-7"}],
     "limit": 50
   }
   ```

   parses into `QueryPlan` and reaches the executor.

2. **Allowlist gates.**

   - source `todos` allowed -> proceeds;
   - source `secrets` denied before adapter;
   - projection field not in allowlist denied before adapter;
   - filter field not in allowlist denied before adapter;
   - non-read op denied.

3. **Fake adapter result.**

   Configure fake rows for `todos`. The executor returns rows through
   `EffectOutcome::Succeeded` / receipt path. Remember: fake v0 may carry filters
   but not evaluate them; do not overclaim filtering unless live code does it.

4. **Limit clamp.**

   Plan limit above policy is clamped to policy max.

5. **Replay bypasses adapter.**

   Same idempotency key + same payload returns cached receipt/result and adapter
   query count remains one, matching existing capability semantics.

6. **Raw SQL refused.**

   A plan containing `sql`, `raw_sql`, or `query` string is refused structurally.

7. **No live DB.**

   Test must pass in default build with no `postgres` feature and no DSN env.

## Suggested Test File

Prefer a new focused file:

```text
runtime/igniter-machine/tests/relational_queryplan_bridge_tests.rs
```

Use existing harness patterns from:

```text
runtime/igniter-machine/tests/postgres_read_tests.rs
```

The test should be default-build green:

```text
cd runtime/igniter-machine && cargo test --no-default-features --test relational_queryplan_bridge_tests
```

If the crate's canonical command is different after reorg, verify and use the
live command.

## Required Proof Doc

Create:

```text
lab-docs/lang/lab-igniter-relational-queryplan-bridge-p3-v0.md
```

It must include:

1. executive summary;
2. chosen proof shape (A real VM eval or B host-side mirror) and why;
3. verified P2 `.ig` QueryPlan shape;
4. verified machine `QueryPlan`/executor shape;
5. tests and what each proves;
6. exact commands and pass counts;
7. limitations;
8. next recommendation.

## Acceptance

- [x] P2 fixture remains compiler-clean.
- [x] New bridge test feeds a P2-shaped `QueryPlan` to fake
      `PostgresReadExecutor`.
- [x] Allowlist source/field/op gates are proven.
- [x] Raw SQL refusal is proven.
- [x] Limit clamp is proven.
- [x] Fake adapter success path returns rows through existing receipt machinery.
- [x] Replay bypasses adapter.
- [x] No live DB, no `postgres` feature, no DSN.
- [x] No compiler/typechecker/VM/source changes unless explicitly justified as
      test-support only.
- [x] Proof doc exists with exact counts.
- [x] Card is marked CLOSED with compact closing report.

---

## Closing Report (2026-06-19)

**Proof shape: B (host-side mirror).** Verify-first confirmed executing compiled `.ig` from a machine test
is **not** a small existing path (needs compiler crate + `.igapp` load + VM dispatch + value extraction),
so — per the card — no runtime bridge was invented. Instead a `QueryPlan` JSON mirroring the P2
`TodosByAccount` plan is fed to the fake `PostgresReadExecutor`, and the mirror is **tied** to the fixture:
the test `include_str!`s the P2 fixture and asserts it declares the exact `QueryPlan`/`QueryFilter` fields
`QueryPlan::from_args` reads. VM-result extraction is explicitly deferred to `…-VM-EXECUTION-BRIDGE-P4`.

**Key live fact:** the executor's `from_args` reads `source/op/projection/filters:[{field,op,value}]/limit`
— **field-for-field identical** to the P2 `.ig` `QueryPlan`/`QueryFilter` types. So a serialized P2 plan
lands cleanly; the bridge is real, not coincidental.

**Deliverable:** `runtime/igniter-machine/tests/relational_queryplan_bridge_tests.rs` — **6 tests**:
shape-tie, rows-via-receipt, source/field/op allowlist denials (adapter untouched), limit clamp, replay
bypass, raw-SQL refusal (`sql`/`raw_sql`/`query`). Proof doc:
`lab-docs/lang/lab-igniter-relational-queryplan-bridge-p3-v0.md`.

**Proof — all green:**
- `cargo test --no-default-features --test relational_queryplan_bridge_tests` → **6 passed** (default
  build: no `postgres` feature, no DSN, no live DB).
- `cargo test --test relational_todo_tests` (P2) → **4 passed** (still compiler-clean).
- `git diff --check` clean; **no production source changed** (only a new test file).

**Honest bounds:** mirror not VM-run; filters carried not evaluated (machine v0); rows are JSON; fake
adapter only. **Next:** `LAB-IGNITER-RELATIONAL-IGWEB-VIA-P4` (relational query contract from an IgWeb
`via` guard); parallel `LAB-MACHINE-POSTGRES-TYPED-READ-P10`; `…-VM-EXECUTION-BRIDGE-P4` only if real
`.ig` result extraction is needed.

## Closed Surfaces

Do not implement typed read values here (`LAB-MACHINE-POSTGRES-TYPED-READ-P10`
owns that). Do not implement predicate evaluation. Do not connect to Postgres.
Do not add pool/TLS/migrations/schema registry. Do not change IgWeb. Do not add
ORM behavior. Do not add raw SQL.

## Next Routes

Likely next after this:

- `LAB-MACHINE-POSTGRES-TYPED-READ-P10` — typed read values on machine side.
- `LAB-IGNITER-RELATIONAL-IGWEB-VIA-P4` — use a relational query contract from
  an IgWeb `via` guard once the bridge is proven.
- `LAB-IGNITER-RELATIONAL-VM-EXECUTION-BRIDGE-P4` — only if P3 chose host-side
  mirror and we need actual compiled `.ig` result extraction.

## Notes For The Agent

This is a bridge proof, not a framework. The right outcome may be modest:
"the shapes line up and fake executor gates them correctly." That is enough.
