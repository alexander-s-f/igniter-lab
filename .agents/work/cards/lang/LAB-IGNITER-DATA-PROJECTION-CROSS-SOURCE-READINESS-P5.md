# LAB-IGNITER-DATA-PROJECTION-CROSS-SOURCE-READINESS-P5

Status: CLOSED (readiness packet delivered 2026-06-25)
Route: standard / architecture readiness
Skill: idd-agent-protocol

## Closing report (2026-06-25)

Packet: `lab-docs/lang/lab-igniter-data-projection-cross-source-p5-v0.md`.

**One classifying axis (the core result):** a source is a **typed-projection source iff the host holds schema
authority OR the data already carries typed Igniter values + integrity; otherwise it is a decoder source.**
That is the *trust + schema authority* line — exactly the design bias. Grounded live: Postgres is projectable
because `PostgresReadValueKind` exists (`postgres_read.rs:299`); HTTP is **not** because its body is an opaque
`String` (`http.rs:66`) — host owns acquisition, not typing.

**Classification (10 families, Q1/Q2):** PROJECTION = Postgres, **tbackend facts** (`Fact.value` already
typed, `fact.rs:4`), in-process compute/sim state (`Collection[Oscillator]` — native, no boundary), trusted
remote-node (content-addressed, `coordination.rs:135,190`), host-schema science files. DECODER = HTTP JSON,
CSV/file (`batch_importer` ESCAPE doctrine), user body, untrusted remote, raw science files. Export = outbound
reverse arrow (not inbound projection). Lanes are NOT interchangeable.

**Provenance (Q3):** invariant core `DatasetMeta { source, count, truncated }` for all; per-source companions
(no generics → no `Dataset[T]`). Most important non-SQL addition = `TemporalMeta { valid_at, known_at }`
(`backend.rs:33-44`) for facts/ledger. Integrity (`source_digest` blake3 / receipt lineage) host-side by
default, crosses only for trust branching.

**Trust/package (Q5):** reuse existing primitives — `CapsuleRef` blake3 content-address (`coordination.rs:190`),
sha256 content-locks, receipts. No new capability.

**Vocabulary, no SQL bias (Q4):** boundary = "typed projection"; container = `Collection[<DomainRecord>]`;
**element noun is domain-chosen** (`Row`/`Fact`/`Observation`/`Lead`/`Payload`), never imposed by the language
(fleet already does this: `query_engine` Row, `batch_importer` RawRow, emergence Oscillator). Provenance =
`DatasetMeta`; avoid `Rows`/`ResultSet`/`TableMeta`.

**Second proof after Postgres (Q6): tbackend facts/history** — most host-native, NO external system / NO new
capability (in-process `read_bitemporal`), exercises the bitemporal window Postgres can't (validates
`TemporalMeta`, proves the boundary isn't SQL-shaped), ties to the determinism/emergence line. CSV/import =
the second *decoder* proof.

**Risks flagged:** SQL bias; collapsing the two lanes; premature HTTP-projection (needs a host response-schema
policy that doesn't exist); inventing provenance primitives; bloating `DatasetMeta`; conflating export with
projection; wrapping native in-process data in projection ceremony.

**Payoff noted:** a clean cross-source boundary makes the P4 view/transform→HTML layer **source-independent**
— the team's next arc (rich HTML expression / templating dialects over the contract graph) sits atop ANY
projection source.

**Next cards:** `LAB-IGNITER-DATA-PROJECTION-FACTS-SECOND-SOURCE-P7` (impl), `LAB-IGNITER-DATA-PROJECTION-DECODER-CONTRACT-P8` (impl, untrusted
lane), future `LAB-MACHINE-HTTP-RESPONSE-SCHEMA-POLICY` (readiness, pressure).

**Boundary honored.** No code / capability / network / canon. Docs only. `git diff --check` clean; grep →
`/tmp/igniter-data-projection-cross-source-grep.txt` (10901 hits).

## Goal

Stress-test the Data Projection Boundary beyond Postgres.

If the concept only works for SQL rows, it is too narrow. This card should decide how the same boundary
applies to:

- HTTP JSON API responses;
- CSV/file imports;
- report/export descriptors;
- scientific datasets;
- ledger/tbackend facts/history;
- remote-node payloads.

## Current Authority

- P1/P2/P3 packets.
- Live machine capability code (`http`, `postgres`, tbackend/facts if present).
- Existing fleet apps (`batch_importer`, `query_engine`, science apps).

## Questions To Answer

1. Which sources are host-owned typed projection sources?
   - Postgres;
   - tbackend facts;
   - scientific dataset files after host parser;
   - others.
2. Which sources should use decoder contracts instead?
   - user request bodies;
   - arbitrary HTTP JSON;
   - CSV/file imports;
   - remote payloads.
3. Is `DatasetMeta { source, count, truncated }` enough across sources?
   - What about file path, URL, ledger store, time window, schema version?
   - Which metadata stays host-only?
4. How should the vocabulary avoid SQL bias?
   - `Row` vs `Record` vs `Observation` vs `Fact`;
   - `Dataset` vs `Rows`.
5. Does this touch package/provenance/remote trust?
   - artifact digest;
   - source digest;
   - receipt lineage.
6. Which source should be the second proof after Postgres?
   - tbackend facts/history?
   - CSV/import?
   - science dataset?
   - HTTP JSON?

## Design Bias

Keep the core boundary generic:

```text
host acquisition + typing + bounding + provenance
  -> typed projection
  -> app transform
```

But do not force trusted and untrusted sources into the same DX. Decoder is likely primary for untrusted
payloads and fallback for typed projection.

## Boundary

Allowed:

- Write a readiness packet.
- Read live source/docs.
- Recommend second-source proof cards.

Closed:

- No code changes.
- No new capability.
- No public network/remote-node implementation.
- No canon claim.

## Required Packet

Create:

`lab-docs/lang/lab-igniter-data-projection-cross-source-p5-v0.md`

Must include:

- source classification table;
- projection-vs-decoder decision per source;
- metadata/provenance matrix;
- second proof recommendation after Postgres;
- risks to avoid.

## Verification

Run:

```bash
rg -n "Http|HTTP|tbackend|Fact|ledger|CSV|RawRow|RowResult|Dataset|source|artifact_digest|provenance|receipt" \
  runtime apps lab-docs server lang \
  > /tmp/igniter-data-projection-cross-source-grep.txt

git diff --check
```

## Acceptance

- [x] Packet exists.
- [x] It generalizes the boundary without SQL bias.
- [x] It classifies at least six source families.
- [x] It says projection vs decoder for each.
- [x] It names one best second-source proof after Postgres.
- [x] No code changed.
- [x] `git diff --check` clean.

## Reporting

Close with:

- recommended generic vocabulary;
- second-source proof choice;
- projection/decoder split;
- next cards.
