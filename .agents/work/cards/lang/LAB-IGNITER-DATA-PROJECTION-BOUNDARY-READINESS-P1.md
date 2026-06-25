# LAB-IGNITER-DATA-PROJECTION-BOUNDARY-READINESS-P1

Status: CLOSED (readiness packet delivered 2026-06-25)
Route: standard / architecture readiness
Skill: idd-agent-protocol

## Closing report (2026-06-25)

Packet: `lab-docs/lang/lab-igniter-data-projection-boundary-readiness-p1-v0.md`.

**Verified live current state first.** The seam is typed up to stage 3 — the host decodes rows per
`PostgresReadValueKind` and builds `{ kind, source, rows, count, effective_limit, row_limit_clamped }`
(`runtime/igniter-machine/src/postgres_read.rs:517-527`, `:299-314`) — then **deliberately flattens to a
JSON string** at `server/igniter-web/src/read_dispatch.rs:111`, so the continuation only sees
`rows_json : String` (`examples/todo_postgres_app/todo_handlers.ig:161-181`). "Typed row destructuring" is
`designed`, not implemented (`server/igniter-web/IMPLEMENTED_SURFACE.md:32,103`). The boundary is therefore
not "how to type the rows" (host already did) but "what Igniter-native value crosses instead of the string."

**Recommended vocabulary.** *Data Projection Boundary*; v0 crossing = a **typed row projection** into an
**app-declared `<AppRow>` record** → `Collection[<AppRow>]`, with a fixed **`DatasetMeta` { source, count,
truncated }** provenance sidecar. Lower layer = **`decoder` / `RowResult`** (the `batch_importer` ESCAPE
shape).

**Chosen v0 direction.** Alternative #3 — host-side typed projection into app-declared records — because
(a) the host already decodes typed rows (`postgres_read.rs:602`); (b) the language cannot reconstruct types
itself — **no in-language JSON parser, no string→scalar coercion** (only `stdlib.math.to_float`,
`lang/igniter-compiler/src/typechecker/stdlib_calls.rs:329`), so any stringly surface strands Integer/Bool/
Decimal; (c) `Collection[Row]`/`Collection[RawRow]` is **already real contract I/O** with typed field access
(`apps/igniter-apps/query_engine/eval.ig:74-76`, `apps/igniter-apps/batch_importer/validate.ig:36-37`). The
view half is fully proven over fixtures (`examples/todo_view_app/todo_views.ig:138-148`); the only missing
link is getting a typed `Collection[<AppRow>]` out of a read.

**decoder vs transform.** `transform` (pure HOF over already-typed rows) is the primary DX for host-owned
relational reads; `decoder` (`RawValue -> Result/RowResult`) is the lower-level fallback for untrusted/file/
API input. Decoders sit *under* the projection surface.

**Deliberately lower-level / deferred.** `decoder`/`RowResult` (fallback, not default); generic `Dataset[T]`
envelope (blocked on user-record generics — not in language); declarative projection-on-`QueryPlan`
(a HOF suffices in v0); DataFrame/columnar (out of scale).

**Next cards.** `LAB-IGNITER-DATA-PROJECTION-TYPED-ROW-CROSSING-P6` (smallest proof: fake rows →
`Collection[TodoRow]` → typed field access + HOF, DB-free), then
`LAB-IGNITER-DATA-PROJECTION-DATASET-META-AND-HTML-P3` (provenance sidecar + read→HTML join). Acceptance
sketches in the packet §8.

**Boundary honored.** No code, no `.igweb`/compiler/runtime/Postgres changes, no Todo-HTML implementation,
no "typed projection is implemented" claim, no canon claim. Only docs added (packet + this report).

**Verification.** `rg` live-grep written to `/tmp/igniter-data-projection-live-grep.txt` (257 hits);
`git diff --check` clean. Acceptance checklist below all met.

## Goal

Define the Igniter-native boundary for external data entering `.ig` programs.

This card exists because `ReadThen` currently proves the host seam with:

```text
QueryPlan -> host read executor -> rows_json : String -> continuation
```

That is a good proof harness, but it is not a good authoring model. If left unnamed, Todo HTML,
Postgres APIs, file imports, reports, science datasets, ledger history, and remote-node payloads will all
invent local `String -> parse/decode` workarounds.

Find the right v0 vocabulary and first implementation slice for:

```text
external source
  -> host-owned authority/execution
  -> bounded dataset value
  -> typed projection into Igniter values
  -> app-owned transform / view model / domain contract
```

## Current Authority

Live source wins:

- `server/igniter-web/IMPLEMENTED_SURFACE.md`
- `server/igniter-web/src/lib.rs` (`dispatch_with_read`, `ReadThen`, `rows_json`, `body_json`)
- `server/igniter-web/src/read_dispatch.rs`
- `server/igniter-web/examples/todo_postgres_app/`
- `runtime/igniter-machine/src/postgres_read.rs`
- `runtime/igniter-machine/src/postgres_real.rs`
- `runtime/igniter-machine/IMPLEMENTED_SURFACE.md`
- `lang/igniter-compiler` / `lang/igniter-vm` row/record/map/collection support

Old proof packets are evidence only. If they say "typed rows deferred", verify against live source, then
state the current truth.

## Pressure To Read

Read at least:

- Todo API product path:
  - `server/igniter-web/examples/todo_postgres_app/API.md`
  - `server/igniter-web/examples/todo_postgres_app/todo_handlers.ig`
  - tests covering list/show/create/done/delete/pagination
- Todo HTML/ViewArtifact pressure:
  - `server/igniter-web/examples/todo_view_app/todo_views.ig`
  - `server/igniter-web/tests/todo_view_app_tests.rs`
  - `LAB-IGNITER-WEB-VIEWARTIFACT-HELPER-CONTRACTS-P20`
- Language pressure:
  - record spread / record ergonomics cards if present
  - collection comprehension / HOF cards if present
  - current VM support for `Map[String, Unknown]`, records, `Collection[T]`, `map/filter/fold/reduce`
- Machine/Postgres typed read:
  - typed field policy / value kinds
  - how rows are represented before JSON serialization

## Questions To Answer

1. What is the right name for the boundary?
   - candidates: `Dataset`, `Rows`, `DataFrame`, `ResultSet`, `Projection`, `DataProjection`,
     `ExternalDataset`, `HostDataset`.
2. What is the right v0 semantic shape?
   - `Collection[Map[String, Unknown]]`
   - `Collection[Row]` with schema metadata
   - `Collection[TodoRow]` typed by an app-declared record
   - decoder contracts
   - host-side typed projection
   - a hybrid
3. Where does `decoder` belong?
   - Treat decoder as a **lower-level fallback / validation primitive**, not the main DX if possible.
   - Compare it against a higher-level `project` / `transform` surface.
4. What does "transform" mean in Igniter terms?
   - pure contract from row record to domain/view model?
   - collection map/comprehension?
   - projection declaration attached to `QueryPlan`?
   - host-provided typed rows plus app-owned transform?
5. Who owns schema mismatch?
   - DB/host schema drift → host error?
   - user JSON/body mismatch → app validation error?
   - file/import mismatch → typed decoder result?
6. How does provenance travel?
   - source name, projection fields, row count, cap/clamp, receipt/query digest, schema version?
   - which of these are visible to `.ig`, which stay host diagnostics?
7. How does this generalize beyond Postgres?
   - HTTP JSON API response
   - CSV/file import
   - report/export descriptors
   - scientific datasets
   - ledger/tbackend facts/history
   - remote-node payloads
8. How does it feed Todo HTML?
   - `Collection[TodoRow] -> Collection[TodoViewModel] -> Collection[HtmlNode] -> RenderView`
   - identify the missing language/runtime pieces without implementing them here.
9. What is the smallest next proof card?
   - DB-free typed-row projection harness?
   - fake Postgres rows -> app-declared `TodoRow` collection?
   - pure transform fixture over `Collection[TodoRow]`?
   - Todo HTML list after typed projection?

## Design Bias

Do **not** choose "just parse JSON strings in `.ig`" unless evidence proves every higher-level option is
too large.

Preferred direction to test:

```text
QueryPlan(projection = ["id","title","done"])
  -> host executes with allowlist + typed field policy
  -> HostDataset rows, bounded + provenance
  -> typed projection: Collection[TodoRow]
  -> app transform: TodoRow -> TodoViewModel -> HtmlNode
```

Decoder contracts are still valuable, but likely as:

- a low-level escape hatch;
- file/API import validation;
- explicit app-owned validation of untrusted user input;
- a mechanism under a nicer projection/transform surface.

They should not be the primary app DX for normal host-owned relational reads.

## Alternatives To Compare

Compare at least these:

1. Keep `rows_json : String` and add JSON parser helpers.
2. `Collection[Map[String, Unknown]]` as the generic row surface.
3. Host-side typed projection into app-declared records.
4. Decoder contracts (`RowValue -> Result[TodoRow, Error]`) as explicit app validation.
5. Projection contracts (`ProjectRows[TodoRow]`) or named `transform` contracts.
6. A `Dataset` record carrying `rows`, `schema`, `provenance`, and `warnings`.
7. DataFrame/table-like abstraction (likely too large for v0, but evaluate).

For each: DX, type safety, host authority, error taxonomy, replay/provenance, implementation size,
and whether it generalizes beyond Postgres.

## Boundary

Allowed:

- Write a readiness packet in `lab-docs/lang/`.
- Update this card with closing report.
- Add a tiny appendix of pseudo-code examples.

Closed:

- No code changes.
- No `.igweb` syntax changes.
- No compiler/runtime changes.
- No new Postgres feature.
- No Todo HTML implementation.
- No claim that a typed projection surface is implemented today.
- No canon claim.

## Required Packet

Create:

`lab-docs/lang/lab-igniter-data-projection-boundary-readiness-p1-v0.md`

The packet must include:

- live current-state summary;
- glossary / proposed vocabulary;
- comparison table of alternatives;
- recommended v0 direction;
- explicit decoder-vs-transform decision;
- error ownership taxonomy;
- how this unblocks Todo HTML without becoming Todo-specific;
- first two implementation cards with acceptance sketches.

## Verification

Run:

```bash
rg -n "rows_json|body_json|ReadThen|Map\\[String, Unknown\\]|Collection\\[.*Row|RenderView|QueryPlan" \
  server/igniter-web runtime/igniter-machine lang/igniter-compiler lang/igniter-vm \
  > /tmp/igniter-data-projection-live-grep.txt

git diff --check
```

If you mention a concrete live capability, cite the file/test path in the packet.

## Acceptance

- [x] Packet exists at the required path.
- [x] It verifies live current state before choosing a design.
- [x] It treats `decoder` as a lower-level option and evaluates a higher-level transform/projection DX.
- [x] It names a recommended v0 boundary and why.
- [x] It states who owns schema/data mismatch errors.
- [x] It generalizes beyond Postgres.
- [x] It gives a Todo HTML path without implementing Todo HTML.
- [x] It proposes the next two concrete cards.
- [x] No code changed.
- [x] `git diff --check` clean.

## Reporting

Close with:

- recommended vocabulary;
- chosen v0 direction;
- what remains deliberately lower-level/deferred;
- next cards;
- exact verification commands.
