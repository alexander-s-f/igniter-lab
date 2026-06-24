# Igniter Lab Closed Card Index

**Status:** living archive navigation for CLOSED language/lab cards.

This file compacts the closed-card trail by direction. It is evidence navigation, not canon,
not backlog authority, and not a substitute for source, tests, or the package-local
`IMPLEMENTED_SURFACE.md` files.

## Agent Entrypoint

Start here before opening old cards:

1. `server/igniter-web/IMPLEMENTED_SURFACE.md` for IgWeb routing, ViewArtifact, ReadThen,
   `MachineEffectHost`, and Todo API.
2. `runtime/igniter-machine/IMPLEMENTED_SURFACE.md` for machine runtime, capability IO,
   Postgres read/write, receipts, and host policy.
3. `lang/igniter-vm/IMPLEMENTED_SURFACE.md` for VM/runtime surface, stdlib, package, and
   admission proof pointers.
4. `lab-docs/lang/current-waves-index.md` for active lab directions and next-card routing.
5. `lab-docs/STATUS.md` for repo-boundary and status-board context.

Cards prove what was claimed when they were written. They do not, by themselves, prove current
implementation. If a closed card conflicts with a current front door, verify live source/tests and
update the current front door, not the old card.

## How To Read This Index

- Duplicate priority numbers are normal; disambiguate by title, not by `P*`.
- Do not move, delete, rename, or mass-edit closed cards from this index.
- Treat old Ruby framework and remote-node surfaces as archaeology unless a current lab front door
  explicitly re-admits them.
- Use `rg '^Status: CLOSED' .agents/work/cards/lang -g '*.md'` to refresh the raw archive set.

## Topic Index

### IgWeb Routing, Render, Context

**Current front doors:** `server/igniter-web/IMPLEMENTED_SURFACE.md`;
`lab-docs/lang/current-waves-index.md` rows for IgWeb and ReadThen.

**Notable closed milestones:** `LAB-IGNITER-WEB-ROUTING-SCOPE-P16`,
`LAB-IGNITER-WEB-ROUTING-RESOURCE-SUGAR-P17`, `LAB-IGNITER-WEB-ROUTING-NESTED-P18`,
`LAB-IGNITER-WEB-ROUTING-VIA-P20`, `LAB-IGNITER-WEB-ROUTING-COMPOSITE-GUARD-P22`,
`LAB-IGNITER-WEB-CONTEXT-COMPOSITION-P26`, `LAB-IGNITER-WEB-CONTEXT-ACCUMULATION-P27`,
`LAB-IGNITER-WEB-RENDER-DECISION-P16`, `LAB-IGNITER-WEB-VIEWARTIFACT-AUTHORING-P19`,
`LAB-IGNITER-WEB-VIEWARTIFACT-LIST-AUTHORING-P21`,
`LAB-IGNITER-WEB-VIEWARTIFACT-CONDITIONAL-LISTS-P22`,
`LAB-IGNITER-WEB-VIEWARTIFACT-SELECT-OPTIONS-P23`,
`LAB-IGNITER-WEB-IGWEB-SERVE-READTHEN-P23`,
`LAB-IGNITER-WEB-IGWEB-SERVE-WRITE-BINDING-P26`,
`LAB-IGNITER-WEB-IMPLEMENTED-SURFACE-GUARD-P33`.

**Superseded assumptions to ignore:** "ReadThen is not implemented"; "final effects are only
observed"; "routes are only flat"; "ViewArtifact is only a sketch"; "single-table reads are the only
supported host shape."

**Do not start here:** do not start from older readiness cards when deciding current runner status.
Open the current web surface first, then verify the named tests/scripts.

### TodoApp API

**Current front doors:** `server/igniter-web/IMPLEMENTED_SURFACE.md`;
`examples/todo_postgres_app/API.md`; `server/igniter-web/scripts/check_todo_product_surface.sh`.

**Notable closed milestones:** `LAB-TODOAPP-API-SHAPE-P2`, `LAB-TODOAPP-API-READ-P3`,
`LAB-TODOAPP-API-WRITE-P4`, `LAB-TODOAPP-API-READ-WRITE-E2E-P5`,
`LAB-TODOAPP-API-LOCAL-POSTGRES-P8`, `LAB-TODOAPP-API-ASYNC-RUNNER-SMOKE-P10`,
`LAB-TODOAPP-API-IGWEB-SERVE-LOCAL-POSTGRES-P12`,
`LAB-TODOAPP-API-DONE-BUSINESS-KEY-P15`, `LAB-TODOAPP-API-CREATE-BODY-P16`,
`LAB-TODOAPP-API-CONTRACT-SURFACE-P17`, `LAB-TODOAPP-API-BODY-CONTRACT-HARDENING-P18`,
`LAB-TODOAPP-API-IDEMPOTENCY-CONFLICT-P19`, `LAB-TODOAPP-API-ERROR-CONTRACT-P20`,
`LAB-TODOAPP-API-PRODUCT-SMOKE-CI-P27`, `LAB-TODOAPP-API-HOST-SURROGATE-ID-P36`,
`LAB-TODOAPP-API-ACCOUNT-EXISTENCE-P38`, `LAB-TODOAPP-API-ERROR-ENVELOPE-IMPL-P43`,
`LAB-TODOAPP-API-DELETE-P44`, `LAB-TODOAPP-API-CREATE-BODY-LEGACY-REMOVAL-P45`,
`LAB-TODOAPP-API-PAGINATION-KEYSET-P47`.

**Superseded assumptions to ignore:** string create body; business `id` equals idempotency key;
account existence is only product prose; no delete endpoint; no keyset pagination; error envelopes
are only readiness text.

**Do not start here:** do not infer production DB state or public API stability from old Todo cards.
Use current API docs, smoke scripts, and DSN-gated tests.

### Machine, Postgres, Host IO

**Current front doors:** `runtime/igniter-machine/IMPLEMENTED_SURFACE.md`;
`server/igniter-web/IMPLEMENTED_SURFACE.md` for web host binding.

**Notable closed milestones:** `LAB-MACHINE-CAPABILITY-IO-P1`,
`LAB-MACHINE-CAPABILITY-IO-P2`, `LAB-MACHINE-CAPABILITY-IO-P3`,
`LAB-MACHINE-CAPABILITY-IO-CLOCK-P4`, `LAB-MACHINE-CAPABILITY-IO-AUTHORITY-P5`,
`LAB-MACHINE-CAPABILITY-IO-RECONCILIATION-P7`, `LAB-MACHINE-CAPABILITY-IO-RETRY-P8`,
`LAB-MACHINE-CAPABILITY-IO-RETRY-QUEUE-P9`, `LAB-MACHINE-CAPABILITY-HTTP-P10`,
`LAB-MACHINE-CAPABILITY-HTTP-P11`, `LAB-MACHINE-CAPABILITY-IO-CORRELATION-RECONCILE-P13`,
`LAB-MACHINE-CAPABILITY-HTTP-EXTERNAL-P14`, `LAB-MACHINE-CAPABILITY-HTTP-TLS-P14-IMPL`,
`LAB-MACHINE-SERVICE-EFFECT-BRIDGE-P16`, `LAB-MACHINE-CAPABILITY-IO-ATOMIC-GATE-P18`,
`LAB-MACHINE-CAPABILITY-IO-DURABLE-RECOVERY-P19`,
`LAB-MACHINE-CAPABILITY-IO-ORCHESTRATOR-P20`,
`LAB-MACHINE-CAPABILITY-IO-SIGNED-PASSPORT-P21`,
`LAB-MACHINE-CAPABILITY-IO-SECRET-PROVIDER-P22`,
`LAB-MACHINE-CAPABILITY-IO-OBSERVABILITY-P23`, `LAB-MACHINE-CAPABILITY-IO-LOAD-P24`,
`LAB-MACHINE-POSTGRES-CAPABILITY-READINESS-P1`,
`LAB-MACHINE-POSTGRES-READ-EXECUTOR-P2`, `LAB-MACHINE-POSTGRES-WRITE-GATE-P3`,
`LAB-MACHINE-POSTGRES-RECONCILE-P4`, `LAB-MACHINE-POSTGRES-LOCAL-FEATURE-READINESS-P5`,
`LAB-MACHINE-POSTGRES-LOCAL-READ-P6`, `LAB-MACHINE-POSTGRES-WIRE-ATOMIC-P7`,
`LAB-MACHINE-POSTGRES-LOCAL-WRITE-P8`, `LAB-MACHINE-POSTGRES-TYPED-READ-P10`,
`LAB-MACHINE-POSTGRES-PREDICATES-P11`.

**Superseded assumptions to ignore:** Postgres is fake-only; real local reads exist but writes do
not; Text keyset ordering is unsupported; delete is not available at the substrate; DSN-gated tests
can be treated as always green; runtime credentials may be recorded in cards.

**Do not start here:** do not start from private host details, old live DB claims, or Spark-shaped
surrogates. The lab authority is the machine surface, local tests, and opt-in DSN proof.

### Package, Workspace, Archive, Admission

**Current front doors:** `lab-docs/lang/current-waves-index.md` package row;
`lab-docs/lang/lab-igniter-package-remote-trust-p23-v0.md`;
`lab-docs/lang/lab-igniter-package-emergence-pack-p24-v0.md`;
`lang/igniter-vm/IMPLEMENTED_SURFACE.md` package notes.

**Notable closed milestones:** `LAB-IGNITER-PACKAGE-MANAGER-READINESS-P1`,
`LAB-IGNITER-PACKAGE-WORKSPACE-RESOLVER-P2`, `LAB-IGNITER-PACKAGE-LOCK-PROVENANCE-P3`,
`LAB-IGNITER-PACKAGE-LOCKFILE-CLI-P4`, `LAB-IGNITER-PACKAGE-VERSION-PROVENANCE-P5`,
`LAB-IGNITER-PACKAGE-STDLIB-VERSION-CONSTANT-P6`,
`LAB-IGNITER-PACKAGE-IMPORT-SCOPING-P7`,
`LAB-IGNITER-PACKAGE-LOCKFILE-FROZEN-CI-P8`,
`LAB-IGNITER-PACKAGE-MODULE-EXPORTS-P10`,
`LAB-IGNITER-PACKAGE-EXPORTS-CI-P11`,
`LAB-IGNITER-PACKAGE-EXPORTS-CLOSED-DEFAULT-P12`,
`LAB-IGNITER-PACKAGE-TRANSITIVE-GRAPH-P14`,
`LAB-IGNITER-PACKAGE-TRANSITIVE-GRAPH-CI-P15`,
`LAB-IGNITER-PACKAGE-MISSING-DEP-DIAGNOSTIC-P16`,
`LAB-IGNITER-PACKAGE-GRAPH-CLI-P18`,
`LAB-IGNITER-PACKAGE-DIAGNOSTIC-DETAILS-P19`,
`LAB-IGNITER-PACKAGE-EXPLAIN-IMPORT-CLI-READINESS-P20`,
`LAB-IGNITER-PACKAGE-ARCHIVE-READINESS-P21`,
`LAB-IGNITER-PACKAGE-ARCHIVE-PACK-VERIFY-P22`,
`LAB-IGNITER-PACKAGE-REMOTE-TRUST-READINESS-P22`,
`LAB-IGNITER-PACKAGE-REMOTE-TRUST-P23`, `LAB-IGNITER-PACKAGE-EMERGENCE-PACK-P24`.

**Superseded assumptions to ignore:** package work stopped at local deps; package archives are only
readiness; admission means execution; admission means registry/signing/remote deploy; SHA-looking
text in docs is package identity without `pack -> verify -> admit` proof.

**Do not start here:** do not begin with registry, semver solver, signing, or deploy unless a current
card explicitly authorizes that slice.

### Stdlib Collections, Math, Linalg, Statistics, Random

**Current front doors:** `lang/igniter-vm/IMPLEMENTED_SURFACE.md`;
`lab-docs/lang/current-waves-index.md` stdlib row.

**Notable closed milestones:** `LAB-STDLIB-COLLECTION-ZIP-READINESS-P1`,
`LAB-STDLIB-COLLECTION-ZIP-PROOF-P2`, `LAB-STDLIB-MATH-TRANSCENDENTALS-P2`,
`LAB-STDLIB-MATH-DETERMINISM-READINESS-P3`, `LAB-STDLIB-MATH-KURAMOTO-PROOF-P4`,
`LAB-STDLIB-MATH-DET-TIER1-P5`, `LAB-STDLIB-MATH-TIER2-READINESS-P6`,
`LAB-STDLIB-MATH-NUMERIC-BASICS-P7`, `LAB-STDLIB-NUMERIC-TO-FLOAT-P8`,
`LAB-STDLIB-MATH-INTEGER-ROOTS-AND-MOD-P8`, `LAB-STDLIB-MATH-EVAL-AST-PARITY-P10`,
`LAB-STDLIB-MATH-NBODY-SWEEP-P11`, `LAB-STDLIB-MATH-DET-TIER2-LN-EXP-P1`,
`LAB-STDLIB-MATH-DET-TIER2-TAN-P2`,
`LAB-STDLIB-DET-MATH-CANON-PROMOTION-READINESS-P3`,
`LAB-STDLIB-DET-MATH-T2-THIRD-ISA-P4`, `LAB-STDLIB-LINALG-READINESS-P1`,
`LAB-STDLIB-LINALG-VEC3-PACKAGE-P2`, `LAB-STDLIB-LINALG-MAT3-P3`,
`LAB-STDLIB-STATISTICS-READINESS-P1`, `LAB-STDLIB-STATISTICS-DESCRIPTIVE-P2`,
`LAB-STDLIB-STATISTICS-COVARIANCE-CORRELATION-READINESS-P3`,
`LAB-STDLIB-RANDOM-PROBABILITY-READINESS-P1`,
`LAB-STDLIB-RANDOM-PRNG-WITHOUT-BITOPS-P2`,
`LAB-STDLIB-RANDOM-DISTRIBUTIONS-P3`.

**Superseded assumptions to ignore:** `zip` is missing and blocks covariance forever; Vec3 is the
only linalg package proof; deterministic math has no cross-ISA evidence; stdlib science results
become canon automatically; probability distributions are already implemented because PRNG
readiness exists.

**Do not start here:** do not promote lab math to canon from this repo. Canon language changes belong
in `igniter-lang` and require explicit authority.

### VM And Language Pressure

**Current front doors:** `lang/igniter-vm/IMPLEMENTED_SURFACE.md`;
`lab-docs/lang/current-waves-index.md` VM row.

**Notable closed milestones:** `LAB-LANG-SURFACE-ERGONOMICS-READINESS-P0`,
`LAB-LANG-FALLIBLE-BINDING-READINESS-P1`, `LAB-LANG-FALLIBLE-BINDING-P2`,
`LAB-LANG-COLLECTION-COMPREHENSION-READINESS-P1`,
`LAB-LANG-COLLECTION-COMPREHENSION-P2`, `LAB-LANG-RECORD-SPREAD-P2`,
`LAB-LANG-RECORD-FIELD-PUNNING-P2`,
`LAB-LANG-SIGNATURE-BOUND-CONTRACT-SURFACE-READINESS-P1`,
`LAB-LANG-SIGNATURE-BOUND-CONTRACT-SURFACE-P2`,
`LAB-LANG-SIGNATURE-BOUND-BOUNDARY-BINDINGS-P3`,
`LAB-LANG-APP-PRESSURE-ERGONOMICS-SCORECARD-P4`,
`LAB-LANG-LOOP-IR-CONFORMANCE-RECOVERY-P1`,
`LAB-LANG-MATCH-ARM-BINDINGS-READINESS-P1`, `LAB-LANG-MATCH-ARM-BINDINGS-P2`,
`LAB-VM-NESTED-HOF-EVAL-AST-RECOVERY-P3`,
`LAB-VM-NESTED-FOLD-MAP-REDUCE-AGGREGATE-P4`, `LAB-VM-EVALAST-MATCH-P1`,
`LAB-VM-AGGREGATE-SOURCE-REF-P1`, `LAB-VM-RUNTIME-AIR-COMBAT-P1`,
`LAB-VM-ENTRYPOINT-SELECTION-P1`.

**Superseded assumptions to ignore:** loop conformance is still stale-red; HOF/eval_ast work implies
all nested HOF cases are covered; `rule_engine` dynamic dispatch can be treated as lab-authorized;
signature-bound contracts are implemented because readiness cards closed.

**Do not start here:** do not treat language-pressure cards as canon. Verify whether a feature is
lab-implemented, readiness-only, or governance-gated.

### Emergence And Public Science Pointers

**Current front doors:** public science evidence in `../igniter-emergence`; lab package trust in
`lab-docs/lang/lab-igniter-package-emergence-pack-p24-v0.md`;
`lab-docs/lang/current-waves-index.md` emergence row.

**Notable closed milestones:** `LAB-IGNITER-PACKAGE-EMERGENCE-PACK-P24`,
`LAB-PROVENANCE-BRIDGE-P6`, plus public emergence cards and receipts in the separate public repo.

**Superseded assumptions to ignore:** local package admission upgrades a public science claim;
public null/baseline receipts prove distributed runtime; private home-lab host details belong in
public-science or lab-language docs.

**Do not start here:** do not edit `igniter-emergence` from this archive hygiene card and do not pull
private governance or home-lab facts into public evidence.

### Hygiene, Readiness, Meta

**Current front doors:** this file; `lab-docs/lang/current-waves-index.md`;
package-local `IMPLEMENTED_SURFACE.md` files; `lab-docs/STATUS.md`.

**Notable closed milestones:** `LAB-IGNITER-WORKSPACE-DRIFT-FORENSICS-P1`,
`LAB-HYGIENE-NET-P9-PATHS-P5`, `LAB-HYGIENE-READTHEN-STATUS-CLARITY-P7`,
`LAB-HYGIENE-SPARKCRM-ROUTE-SCOPE-P8`, `LAB-HYGIENE-MATH-DETERMINISM-SCOPE-P9`,
`LAB-HYGIENE-STATUS-CLEAN-P2`, `LAB-HYGIENE-CARD-STATUS-NORMALIZATION-P10`,
`LAB-HYGIENE-CARD-ID-COLLISION-INDEX-P4`, `LAB-IGNITER-WEB-RUNNER-DOCS-SWEEP-P30`,
`LAB-IGNITER-WEB-READTHEN-EFFECTHOST-DOC-SWEEP-P32`,
`LAB-IGNITER-WEB-IMPLEMENTED-SURFACE-GUARD-P33`,
`LAB-IGNITER-LAB-REPO-BOUNDARY-READINESS-P1`, `LAB-IGNITER-ECOSYSTEM-MAP-P1`.

**Superseded assumptions to ignore:** closed card title equals current backlog item; status text
alone proves implementation; old route/surface docs are safer than current front doors; duplicate
card IDs imply one of the cards is invalid.

**Do not start here:** do not use hygiene cards as product authority. Use them to choose the next
verification path.

## Drift Assumptions To Retire

1. "ReadThen is absent or harness-only." Current web surface says it is runner-integrated with bounded
   staged reads.
2. "`MachineEffectHost` is not wired." Current async machine mode routes final `InvokeEffect` through
   `MachineEffectHost` when a write host is configured.
3. "Todo create still accepts the legacy string body." Current Todo API uses the object body; legacy
   removal is closed.
4. "Todo business id equals the idempotency key." Current host mints a surrogate business id while
   receipts still key on idempotency.
5. "Todo has no delete or keyset pagination." Delete and `?after=` keyset pagination are implemented;
   `{items,next}` remains readiness-only.
6. "Postgres is fake-only." Fake adapters remain the cheap proof path, but opt-in real local read/write
   adapters exist behind DSN-gated tests.
7. "Package work stopped before archive/admission." Pack, verify, graph, and local deterministic admit
   exist; registry/signing/deploy do not follow from that.
8. "`zip` is missing, so statistics cannot progress." Collection `zip` is implemented/proven; statistics
   package promotion remains a separate task.
9. "Vec3 is the only linalg package proof." Mat3 package proof now exists; generic MatN does not.
10. "Deterministic math proof means canon promotion." Third-ISA lab evidence supports readiness; canon
    promotion still belongs outside lab authority.
11. "Public emergence receipts prove distributed runtime." They are public science evidence with null
    and baseline controls, not runtime authority.
12. "A closed card is a current instruction." Closed cards are audit trail; current work starts from
    front doors plus live verification.

## Audit Trail Preservation

This index intentionally leaves the archive intact. No card should be moved, deleted, renamed,
or status-edited as part of closed-card compaction. To refresh:

```sh
rg '^Status: CLOSED|^\\*\\*Status:\\*\\* CLOSED' .agents/work/cards/lang -g '*.md'
```

If the archive count changes, update this index by topic and keep the old card filenames visible
enough for `rg`-based audit.
