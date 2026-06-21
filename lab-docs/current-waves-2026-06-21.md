# Igniter Current Waves — 2026-06-21

**Status:** working index, not canon. This file is a navigation map for active lab/home-lab waves so we can slice cards without keeping the whole ecosystem in short-term memory.

## How to use this map

- Treat each wave as a lane with its own authority boundary and proof style.
- Prefer one next card per lane; do not merge DB, web, science, and package work into one card.
- Readiness cards answer "what shape"; implementation cards prove one narrow slice.
- Current truth lives in code/tests/cards; this file is an operator index and may go stale.
- Cross-repo note: `igniter-lab` owns language/runtime/web/package proofs; `igniter-home-lab` owns deployment/science apparatus and physical-node pressure.

## Wave map

| Wave | What is proven now | Main open pressure | Best next card shape |
|---|---|---|---|
| IgWeb app/runtime | `igweb-serve`, `igweb.toml`, routing sugar, context composition, prefix-grouped route lowering, render decisions, raw response, Todo view HTML | runner async/effect/read productionization | one host-runner seam at a time |
| TodoApp API + DB | relational contracts, fake read bridge, typed PG reads, write/effect host proofs, fake read/write e2e | product-level read/write API with local PG loop | local-PG and runner-productization slices after fake e2e |
| View/render/assets/export | ViewArtifact JSON -> HTML, typed `RenderView`, app-local helper contracts, select/list authoring | file export, static assets/shell, richer layout vocabulary | descriptor-to-bytes readiness before xlsx/pdf/csv impl |
| Package manager | local deps, lock/verify, exports, closed default, transitive graph, archive pack/verify, CI strictness | remote/registry trust, package UX, import explain polish | remote/package-trust readiness or DX polish, not semver registry yet |
| Language surface | signature-bound contracts, fallible bindings, record spread/punning, comprehensions, loops conformance recovered | effect/read syntax, dense binding semantics, app ergonomics under pressure | syntax readiness with SIR parity and app-pressure examples |
| VM/eval_ast | nested map/filter/sum/fold in HOF bodies, math parity through shared eval path | `filter_map`/`reduce`, performance, in-process repeated dispatch | small eval_ast parity cards plus runner benchmarks |
| Stdlib science | deterministic math, numeric basics, integer roots/mod, `to_float`, statistics, Vec3 package proof, PRNG boundary | distributions, matrices, scientific rigor library | one pure library/package proof per topic |
| Machine/Postgres/effect | typed reads, predicates/order_by, write receipts, effect host, read host harness | keyset pagination, production runner binding, local PG productization | read/write host runner seam or keyset predicate proof |
| Home-lab emergence | Kuramoto K-sweep observed, deterministic apparatus, remote-node substrate archaeology | in-process runner, network Kuramoto, local multi-node simulator | runner readiness first, then network Kuramoto readiness |
| Remote node/substrate | old Ruby remote-node split: network-in-graph rejected; cluster/control-plane preserved | snapshot consistency, transport receipts, package trust per node | local multi-node simulator before real network |
| Repo hygiene | workspace domains split, view-engine status clarified, generated/stale inventory | ongoing organization and avoiding mixed domains | only when repo structure blocks active lanes |

## Active lane details

### 1. IgWeb App Runtime

**Current assets**

- Generic runner: `server/igniter-web` with `igweb-serve`, manifest parser, dry `check`, loopback runner.
- Routing: `scope`, `resource`, nested composition, `via`, context composition/accumulation, route tree scaling proof.
- Rendering: `Render`, `RenderView`, `igniter-render-html`, raw `text/html` response path.
- Todo view app: JSON views, HTML preview, typed ViewArtifact records, helpers, list/select authoring.

**Open pressure**

- Route matching scale was promoted from latency to buildability pressure; prefix-grouped lowering has now removed the route-depth wall.
- Runner still has host seams that are proven in harnesses but not fully productized in socket-loop form.

**Next slices**

1. `LAB-IGNITER-WEB-EFFECT-HOST-RUNNER-P*` — productionize write-effect host in runner after P4 proof.
2. `LAB-IGNITER-WEB-READTHEN-RUNNER-P*` — staged read/continuation runner seam after P6 proof.
3. `LAB-IGNITER-WEB-ROUTE-SCALE-REGRESSION-P*` — keep 500/1000-route buildability locked as app pressure grows.

### 2. TodoApp API + Postgres

**Current assets**

- Relational `.ig` contracts can express `QueryPlan` and `WriteIntent` without SQL/ORM authority.
- Fake read bridge and read-host harness prove app query -> host policy -> continuation.
- Write effect host proves `InvokeEffect` -> executor -> receipt.
- Postgres typed reads and predicates are live on the machine side.

**Open pressure**

- App-level fake read/write e2e exists; the remaining pressure is local Postgres and runner productization.
- Real DB loop must stay operator-owned: schema/policy/DSN in host config, not `.igweb`.

**Next slices**

1. `LAB-TODOAPP-API-LOCAL-POSTGRES-E2E-P*` — local PG after fake app shape is green.
2. `LAB-TODOAPP-API-RUNNER-PRODUCTIZATION-P*` — move beyond direct-dispatch harness toward runner flow.
3. `LAB-MACHINE-POSTGRES-KEYSET-P*` — if product reads need pagination.

### 3. View, Assets, Export

**Current assets**

- Raw response gate in server core.
- `Render` from request-sourced ViewArtifact JSON.
- `RenderView` from typed `.ig` records.
- App-local helper contracts reduce ViewArtifact verbosity.

**Open pressure**

- File export is the same descriptor-to-bytes seam as HTML, but it introduces size/streaming/storage questions.
- Static shell/assets should remain app/host owned, not server-core route tables.

**Next slices**

1. `LAB-IGNITER-WEB-FILE-EXPORT-READINESS-P*` — descriptor -> bytes, inline vs async, xlsx/csv/pdf boundaries.
2. `LAB-TODOAPP-STATIC-SHELL-P*` — external static shell consuming JSON/ViewArtifact routes.
3. `LAB-IGNITER-WEB-LAYOUT-VOCAB-P*` — only if Todo view pressure needs nested layout.

### 4. Package Manager

**Current assets**

- Local packages, import ownership, exports, closed default, transitive graph, lock/verify, archive pack/verify.
- CI story exists: frozen lock and strict verify.
- Vec3 package is the first scientific consumer of package model.

**Open pressure**

- Remote package trust is now connected to remote-node substrate.
- Registry/semver is still later; local-first and content-addressed trust are enough for current science/app work.

**Next slices**

1. `LAB-IGNITER-PACKAGE-REMOTE-TRUST-READINESS-P*` — node pulls verified artifact, no registry yet.
2. `LAB-IGNITER-PACKAGE-IMPORT-EXPLAIN-P*` — DX polish for package errors.
3. `LAB-IGNITER-PACKAGE-LIBRARY-DISTRIBUTION-P*` — pure `.ig` stdlib/science libraries as packages.

### 5. Language Surface

**Current assets**

- Signature-bound contracts and denser app-oriented syntax are in the pressure stream.
- Record spread, punning, collection comprehension, fallible bindings, loop conformance are live.
- The `<-` idea is promising only if it marks an actual external/read/effect boundary; not as a universal binding glyph.

**Open pressure**

- App code wants dense signatures and fewer boilerplate `input/compute/output` blocks.
- Science code wants loops/HOFs, numeric clarity, explicit deterministic boundaries.

**Next slices**

1. `LAB-LANG-SIGNATURE-BOUND-CONTRACT-SURFACE-P*` — implementation/compat proof if readiness says go.
2. `LAB-LANG-EFFECT-BINDING-SYNTAX-READINESS-P*` — `=` pure vs `<-` external boundary, SIR parity, pure-invariant.
3. `LAB-LANG-APP-PRESSURE-ERGONOMICS-P*` — rewrite one Todo/Science contract in new surface and compare.

### 6. VM / eval_ast / Runner Performance

**Current assets**

- Nested HOF recovery: `map`, `filter`, scalar `sum`, and nested `fold` now execute in eval_ast.
- Math calls share one dispatch source between OP_CALL and eval_ast paths.

**Open pressure**

- `filter_map` and `reduce` are still guarded.
- In-process repeated dispatch is becoming a science blocker, especially for per-node simulations.

**Next slices**

1. `LAB-VM-NESTED-REDUCE-EVAL-AST-P*` — reduce parity or explicitly keep guarded.
2. `LAB-IGNITER-EXPERIMENT-INPROCESS-RUNNER-READINESS-P*` — load once, dispatch many, measure CLI delta.
3. `LAB-IGNITER-EXPERIMENT-INPROCESS-RUNNER-P*` — minimal implementation after readiness.

### 7. Stdlib Science

**Current assets**

- Deterministic `sin/cos/sqrt`, numeric basics, integer roots/mod, `to_float`.
- Descriptive statistics as pure `.ig` contracts.
- Vec3 as local package proof.

**Open pressure**

- Probability distributions over explicit PRNG state.
- Matrices and small fixed-shape linalg.
- Scientific datasets need stable statistics and reproducibility conventions.

**Next slices**

1. `LAB-STDLIB-PROBABILITY-DISTRIBUTIONS-P*` — `uniform_int`, `bernoulli`, maybe categorical over explicit RNG.
2. `LAB-STDLIB-STATISTICS-PACKAGE-P*` — promote stats into reusable package/library fixture.
3. `LAB-STDLIB-LINALG-MAT2-MAT3-P*` — fixed-shape matrix package proof.

### 8. Home-lab Emergence

**Current assets**

- Kuramoto K-sweep produced observed synchronization and null checks.
- Home-lab has Pi/deploy inventory/runbooks, but emergence proofs remain local/safe.
- Remote-node archaeology is documented.

**Open pressure**

- CLI-per-tick overhead blocks serious distributed/per-node simulation.
- Network Kuramoto needs a deterministic local reference before real network.

**Next slices**

1. `LAB-IGNITER-EXPERIMENT-INPROCESS-RUNNER-READINESS-P*` — shared with VM/perf lane.
2. `LAB-IGNITER-EMERGENCE-NETWORK-KURAMOTO-READINESS-P*` — topology, sync barrier, local/global order parameter.
3. `LAB-IGNITER-EMERGENCE-LOCAL-MULTINODE-SIM-P*` — in-memory mailbox, no network.

### 9. Remote Node / Substrate

**Current assets**

- Legacy Ruby archaeology found two ideas: remote HTTP as graph node (rejected) and cluster/control-plane peers (preserved).
- Modern mapping: pure local contract + runtime substrate + host transport capability + package trust.

**Open pressure**

- Snapshot consistency is the real design question: sync barrier vs latest-observed async.
- P6 real network must be measured as delta from deterministic P5 reference.

**Next slices**

1. `LAB-IGNITER-REMOTE-NODE-SNAPSHOT-CONSISTENCY-READINESS-P*` — define snapshot/read model and receipts.
2. `LAB-IGNITER-REMOTE-NODE-MOCK-TRANSPORT-P*` — in-memory transport capability with receipts.
3. `LAB-IGNITER-REMOTE-NODE-PACKAGE-TRUST-P*` — verified artifact per node.

## Suggested near-term card queue

This is the smallest queue that keeps the ecosystem coherent without drowning us:

1. `LAB-IGNITER-EXPERIMENT-INPROCESS-RUNNER-READINESS-P*`
   - Unblocks serious Kuramoto, local multi-node, performance baselines.
2. `LAB-IGNITER-PACKAGE-REMOTE-TRUST-READINESS-P*`
   - Connects package trust to future remote node substrate.
3. `LAB-TODOAPP-API-LOCAL-POSTGRES-E2E-P*`
   - Turns fake read/write e2e into a local DB proof.
4. `LAB-STDLIB-PROBABILITY-DISTRIBUTIONS-P*`
   - Builds on explicit PRNG without ambient randomness.
5. `LAB-IGNITER-WEB-EFFECT-HOST-RUNNER-P*`
   - Moves proven host seams toward the actual runner.

## Parking lot

- `.ig.html` remains deferred; current winner is structured descriptor -> renderer.
- Registry/semver remains deferred; local/content-addressed packages are enough now.
- Real Pi/network execution remains deferred until local deterministic reference exists.
- Streaming large files remains deferred; first export path can be bounded buffered bytes.
- Dynamic remote contract dispatch remains rejected unless reintroduced as host capability, never pure graph IO.
