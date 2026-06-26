# Igniter Lab Current Waves Index

**Status:** living navigation index for active lab directions. This is not canon, not a dated
status snapshot, and not backlog authority. Old cards and proof packets are evidence of what was
true when written; current truth comes from package-local `IMPLEMENTED_SURFACE.md`, live source,
tests/scripts, and the latest status docs.

**Use this first:** pick the wave, verify its anchors, then dispatch one narrow next card. Do not
merge DB, web, science, package trust, VM, and public-science work into one task.

## Front Doors

- `server/igniter-web/IMPLEMENTED_SURFACE.md` — IgWeb routing, ViewArtifact, ReadThen,
  `MachineEffectHost`, Todo API.
- `runtime/igniter-machine/IMPLEMENTED_SURFACE.md` — machine runtime, capability IO,
  Postgres read/write, receipts, host policy.
- `lang/igniter-vm/IMPLEMENTED_SURFACE.md` — VM/runtime surface, stdlib/package proof pointers.
- `lab-docs/STATUS.md` — repo boundary, active lanes, and targeted status-board checks.
- `lab-docs/lang/lab-igniter-package-remote-trust-p23-v0.md` and
  `lab-docs/lang/lab-igniter-package-emergence-pack-p24-v0.md` — package admission and
  emergence package trust front doors.

## Wave Map

| Wave | Implemented | Harness-proven | Readiness-only | Deferred / blocked | Next cards |
| --- | --- | --- | --- | --- | --- |
| TodoApp API / product hardening | Object create body, host surrogate id, account existence semantics, app error envelope, delete, keyset pagination. Verify in `server/igniter-web/IMPLEMENTED_SURFACE.md`, `examples/todo_postgres_app/API.md`, `scripts/check_todo_product_surface.sh`. | DB-free async HTTP runner and fake Postgres adapter paths: `tests/todo_postgres_async_runner_smoke_tests.rs`, `runtime/igniter-machine/tests/postgres_write_tests.rs`. Real local DB tests exist but are DSN-gated. | Product polish choices such as a typed `{items,next}` JSON envelope, client `limit`, and DB-backed HTML adoption. | Global protocol error envelope, schema migration runner, production DB ownership. | `LAB-TODOAPP-VIEW-TYPED-ROW-LINKS-P19`; `LAB-LANG-NUMBER-TO-TEXT-P1`; `LAB-TODOAPP-API-PAGINATION-ENVELOPE-READINESS-P*`; `LAB-TODOAPP-API-CONTRACT-EXAMPLES-P*`. |
| IgWeb routing / rendering / ViewArtifact | `scope`, `resource`, nested routes, route-level `via`, context `let`/same-name `guard`, `Render`, `RenderView`, raw response mapping, link node/nav, and typed rows -> HTML. Verify in `lang/igniter-compiler/src/igweb.rs`, `lang/igniter-compiler/tests/igweb_lowering_tests.rs`, `server/igniter-web/src/lib.rs`, `tests/typed_html_tests.rs`, `tests/todo_view_app_tests.rs`. | Todo view/render fixtures prove authored HTML and renderer behavior: `examples/todo_view_app`, `tests/todo_view_app_tests.rs`, `igniter-render-html` tests. | File export and richer grouped layout vocabulary remain design threads. | Public hosting, stable CLI, `.igweb` public language authority, `.igv`/projection dialect canon. | `LAB-TODOAPP-VIEW-TYPED-ROW-LINKS-P19`; `LAB-IGNITER-WEB-FILE-EXPORT-READINESS-P*`; `LAB-IGNITER-WEB-LAYOUT-VOCAB-P*`; `LAB-IGNITER-WEB-ROUTING-SOURCE-MAP-READINESS-P*`. |
| Machine / Postgres / host IO | Capability IO, host clock/passport/receipts, real local Postgres read/write under opt-in `postgres`, Text range/order with `COLLATE "C"`, delete op, reconcile. Verify in `runtime/igniter-machine/IMPLEMENTED_SURFACE.md`, `src/postgres_read.rs`, `src/postgres_real.rs`, `src/postgres_write.rs`. | Fake adapter and receipt-gated paths are broad and cheap: `tests/postgres_read_tests.rs`, `tests/postgres_write_tests.rs`, `tests/postgres_reconcile_tests.rs`, capability IO test family. | Operator console and SparkCRM webhook auction policy are design/readiness only. | Connection pool, `postgres-tls`, rich type mapping, Postgres-as-`TBackend`, in-VM ORM, live DB claims without DSN-gated proof. | `LAB-MACHINE-POSTGRES-TLS-READINESS-P*`; `LAB-MACHINE-POSTGRES-RICH-TYPES-P*`; `LAB-MACHINE-OPERATOR-CONSOLE-P2` after product need is concrete. |
| ReadThen / EffectHost runner | `ReadThen { plan, then, carry }` is runner-integrated and bounded; typed continuations receive `rows : Collection[AppRow]` + `DatasetMeta`; legacy `rows_json` remains compatible; source-independent typed-shape diagnostics fail `igweb-serve check` with `PROJECTION_SCHEMA_INVALID`; final `InvokeEffect` routes through `MachineEffectHost` in async machine mode. Verify in `server/igniter-web/src/lib.rs`, `src/read_continuation.rs`, `src/read_dispatch.rs`, `src/machine_runner.rs`, `scripts/check_implemented_surface.sh`. | DB-free socket/runner tests prove staged reads and final effects without live DB: `readthen_socket_runner_tests`, `igweb_serve_machine_mode_tests`, `todo_postgres_async_runner_smoke_tests`; typed rows are covered by `typed_readthen_tests`, `typed_html_tests`, `boot_diagnostic_tests`. | Nicer staged-read authoring syntax and product-route adoption of typed JSON envelopes are still design/app work. | Sync mode still observes `InvokeEffect`; current Todo JSON list/show still use legacy `rows_json`; no multi-DSN/cross-DB joins; source-dependent host-kind drift remains first-dispatch. | `LAB-TODOAPP-VIEW-TYPED-ROW-LINKS-P19`; `LAB-LANG-NUMBER-TO-TEXT-P1`; `LAB-IGNITER-WEB-READTHEN-AUTHORING-SYNTAX-P*`; `LAB-IGNITER-WEB-MULTI-DSN-READINESS-P*` only after real product pressure. |
| Stdlib science | Deterministic math surface, Tier-2 math pieces, `to_float`, collection `zip`, Vec3 and Mat3 package proofs. Verify in `lang/igniter-stdlib/stdlib/collections.ig`, `lang/igniter-vm/tests/stdlib_math_hof_tests.rs`, `linalg_vec3_tests.rs`, `linalg_mat3_tests.rs`. | Third-ISA det-math evidence exists for math surface via `LAB-STDLIB-DET-MATH-T2-THIRD-ISA-P4`; package proofs run through real compiler + VM. | Probability/distribution library and promoted reusable stats package are still next-shape work. | Generic matrix library, arbitrary nested HOF coverage, non-finite value model, public science claims without null/baseline controls. | `LAB-STDLIB-PROBABILITY-DISTRIBUTIONS-P*`; `LAB-STDLIB-STATISTICS-PACKAGE-P*`; `LAB-STDLIB-LINALG-MATN-READINESS-P*`. |
| Package / workspace / archive / admission / remote trust | Local workspace deps, exports/closed default, transitive graph, lock/verify, `igc package graph`, `.igpkg` pack/verify, `igc package admit`. Verify in `lang/igniter-compiler/src/main.rs`, `src/project.rs`, `tests/package_workspace_tests.rs`, `tests/package_lockfile_cli_tests.rs`. | Kuramoto fixture package trust loop is proven: pack -> verify -> admit with deterministic identity in `LAB-IGNITER-PACKAGE-EMERGENCE-PACK-P24` and `cli_admit*` tests. | Provenance bridge from admitted identity into experiment execution is readiness-only unless a runner takes admitted metadata as input. | Registry, semver solver, signing, deploy, remote execution, and package execution from admission. | `LAB-PROVENANCE-BRIDGE-ADMITTED-RUNNER-P*`; `LAB-IGNITER-PACKAGE-IMPORT-EXPLAIN-P*`; `LAB-IGNITER-PACKAGE-SIGNING-READINESS-P*` later. |
| VM / language pressure | VM bytecode/runtime path, app-local `def` function registry, trace/bytecode map, HOF `map/filter/fold/reduce` lowering, stdlib/linalg proofs. Verify in `lang/igniter-vm/IMPLEMENTED_SURFACE.md`, `lang/igniter-vm/src`, `lang/igniter-compiler/tests`. | HOF/eval_ast math parity and linalg package fixtures are tested; loop conformance stale-red was cleared by targeted `cargo test --test loop_conformance_tests` (14 passed). | Signature-bound contract surface and effect/read binding syntax remain design/readiness unless a specific implementation card exists; IgWeb typed row crossing is tracked in the ReadThen row, not VM authority. | 2026-06-24 machine fleet is **HOLD 11/13**: `batch_importer` needs `eval_ast variant_construct`; `web_router` needs match-arm record-literal/block disambiguation. `rule_engine` dynamic dispatch remains governance-gated; recursive self-call/TCO and single `source -> run` / REPL remain missing. | `LAB-VM-EVALAST-VARIANT-CONSTRUCT-IMPL-P5`; `LAB-COMPILER-MATCH-ARM-RECORD-LITERAL-FIX-P1`; then rerun `cargo test --test machine_tests test_machine_fleet_sweep`. |
| Emergence / public science boundary | Public emergence work has reproducible receipts/result bundles and null/baseline discipline; lab has a package-admitted Kuramoto fixture. Verify public science in `igniter-emergence` receipts and lab package trust in `lab-igniter-package-emergence-pack-p24-v0.md`. | Local package/admission proof for Kuramoto kernel is harness/lab evidence; public experiment receipts remain source-backed science evidence, not runtime authority. | Provenance bridge and admitted-package experiment runner are readiness until live execution consumes admitted metadata. | Do not import private home-lab host details; do not mutate public emergence docs from this hygiene card; no distributed-runtime claim from local/null experiments. | `LAB-PROVENANCE-BRIDGE-ADMITTED-RUNNER-P*`; `EMERGENCE-DEGREE-NORMALIZED-FOLLOWUP-P*` in public repo only if separately authorized; `LAB-IGNITER-EMERGENCE-LOCAL-MULTINODE-SIM-P*` after deterministic runner boundary. |
| Remote node / substrate | Legacy remote-node archaeology is mapped into modern host capability + package trust language; package admission gives node-admission identity but no node execution. | Mock/local transport and package-admit loops are the right evidence shape; older Ruby network-in-graph surfaces are not language authority. | Snapshot consistency, mock transport receipts, and per-node verified artifact policy need readiness before implementation. | Real network, Pi/tailnet ops, production deployment, remote graph IO, and dynamic remote contract dispatch. | `LAB-IGNITER-REMOTE-NODE-SNAPSHOT-CONSISTENCY-READINESS-P*`; `LAB-IGNITER-REMOTE-NODE-MOCK-TRANSPORT-P*`; `LAB-IGNITER-REMOTE-NODE-PACKAGE-TRUST-P*`. |

## Recommended Next Parallel Wave

Run the next parallel wave around **provenance + typed-row product payoff**, because it connects the
freshest live surfaces without crossing production boundaries:

1. `LAB-PROVENANCE-BRIDGE-ADMITTED-RUNNER-P*` — bind admitted package identity into experiment
   provenance without allowing a fabricable digest flag.
2. `LAB-TODOAPP-VIEW-TYPED-ROW-LINKS-P19` — use typed row fields for per-row detail links and keyset
   load-more hrefs.
3. `LAB-LANG-NUMBER-TO-TEXT-P1` — unblock `DatasetMeta.count`, numeric badges, and report labels.
4. `LAB-STDLIB-PROBABILITY-DISTRIBUTIONS-P*` — keep science pressure moving on explicit PRNG state.

Keep these parallel, not merged: provenance/package identity, typed-row product adoption, Todo product API, and
stdlib science have different authorities and proof styles.

## Parking Lot

- Public hosting, production listeners, schema migrations, registry/semver/signing, and deploy remain
  closed until separate cards authorize them.
- Old Ruby framework or remote-node surfaces are archaeology/evidence only, never language authority.
- Public emergence claims must stay baseline/null-aware and repo-local; lab package admission does not
  upgrade a public science result by itself.
