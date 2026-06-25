# lab-igniter-data-projection-cross-source-p5-v0

Card: `LAB-IGNITER-DATA-PROJECTION-CROSS-SOURCE-READINESS-P5`
Route: standard / architecture readiness · Skill: idd-agent-protocol
Status: readiness packet (no code changed; no new capability; no canon claim)
Date: 2026-06-25
Builds on: P1 boundary · P2 materialization · P3 contract-and-errors · P4 transform-DX packets.

> **Authority boundary.** Design only. No code, no new capability, no public-network/remote-node
> implementation, no canon claim. Every concrete claim is cited against live `igniter-lab` source.

---

## Headline

The Data Projection Boundary generalizes cleanly — but only along one axis. **A source belongs to the
typed-projection lane iff the host holds schema authority *or* the data already carries typed Igniter values
(plus integrity); every other source belongs to the decoder lane (app-owned validation).** That single
axis — *trust + schema authority* — classifies all six+ families without SQL bias. The boundary's core
stays generic; the trusted/untrusted DX split is preserved exactly as the design bias demands.

**Recommended second proof after Postgres: tbackend facts / history** — the *most host-native* typed source
(`Fact.value` is already a typed Igniter value, `runtime/igniter-machine/src/fact.rs:4`), needing **no
external system and no new capability**, and exercising a dimension Postgres cannot: the **bitemporal time
window** (`read_bitemporal(store, key, valid_at, known_at)`, `runtime/igniter-machine/src/backend.rs:39-44`),
which stress-tests `DatasetMeta`'s generality and proves the boundary is not SQL-shaped.

---

## 1. The one axis that classifies every source

P1-P4 built the boundary around Postgres. The generalizing question is *not* "what other sources exist" but
"**what makes a source projectable.**" Two live facts fix the answer:

- **Postgres is projectable because the host owns a typed field policy.** `PostgresReadValueKind`
  (`runtime/igniter-machine/src/postgres_read.rs:299-314`) is the host's schema authority; rows are decoded
  to typed values before crossing.
- **HTTP is *not* projectable today because there is no such policy.** The HTTP executor returns
  `HttpResponse { status, body : String }` (`runtime/igniter-machine/src/http.rs:66,72-74`) and
  `map_response` maps only the *status* taxonomy — the **body is an opaque String**. The host owns
  *acquisition* (redaction, rate limits, body caps, status taxonomy, correlation) but **not typing**.

So the axis is:

> **A source is a typed-projection source iff the host holds schema authority for it (e.g. a field-kind
> policy) OR the data already carries typed Igniter values with integrity. Otherwise it is a decoder
> source.**

This is the same *trust + schema authority* line the design bias draws ("do not force trusted and untrusted
sources into the same DX"). Projection's promise — rows enter `.ig` *total + typed* (P3) — is only keepable
when the host can guarantee the types. Where it cannot, the app must own validation: that is the decoder.

---

## 2. Source classification (Q1, Q2) — well beyond six families

| # | Source family | Host schema authority? | Already typed values? | Lane | Live status |
| --- | --- | --- | --- | --- | --- |
| 1 | Postgres relational read | **Yes** — `PostgresReadValueKind` (`postgres_read.rs:299`) | host-decoded | **Projection** | live (P1-P4) |
| 2 | **tbackend facts / history** | implicit (the writer); host owns the store + bitemporal read | **Yes** — `Fact.value` is a typed value (`fact.rs:4-12`) | **Projection** (most native) | live (`read_bitemporal`, `backend.rs:39`) |
| 3 | In-process compute / simulation state | n/a (produced in-language) | **Yes** — `Collection[Oscillator]` (`igniter-emergence/kernels/kuramoto_per_omega_tick.ig:17`) | **Native** (no boundary — it is already `.ig` data) | live (emergence) |
| 4 | Scientific reference dataset **file** | only if a host parser declares a schema | after parse | **Projection** if host-schema, else **Decoder** | not live (no file reader) |
| 5 | HTTP JSON API response | **No** — body is a String (`http.rs:66`) | No | **Decoder** (default); Projection only with a future host response-schema policy | exec live; typing not |
| 6 | CSV / file import | **No** — a cell is text | No | **Decoder** (the ESCAPE boundary) | precedent (`batch_importer`, `apps/igniter-apps/batch_importer/types.ig:13-15`) |
| 7 | User request body | **No** | No | **Decoder** | live (`req.body_json` + `map_get_string`, `server/igniter-web/src/lib.rs:304`) |
| 8 | Remote-node payload — **trusted** Igniter node | n/a | **Yes** — content-addressed Igniter values | **Projection** + integrity provenance | primitives live (`CapsuleRef`, `coordination.rs:135,190`) |
| 9 | Remote-node payload — **untrusted** | No | No | **Decoder** (verify-then-trust) | — |
| 10 | Report / export descriptor | (outbound) | app produces typed rows | **Projection-in-reverse** (outbound lane) | `RenderView`/export precedent |

Notes that defuse SQL bias:
- **#3 is the deepest point:** the science line already passes `Collection[Oscillator]` / `Collection[NeighborPhase]`
  between kernels — *typed record collections produced in-language*. For native data there is **no projection
  boundary at all**; the boundary exists only where data *crosses from a host-owned external source*. This
  proves the boundary is a *seam*, not a universal tax.
- **#4 science split:** today science data is #3 (native) or #2 (recorded facts). An external dataset *file*
  would be #4 — host parser → projection (if the parser declares a schema) or decoder (raw format).
- **#10 export is the reverse arrow:** `Collection[<Record>] → host serializes → CSV/JSON/report`. Same
  vocabulary, opposite direction; do not conflate it with inbound projection.

---

## 3. Projection vs decoder — the decision rule

```text
            ┌─ host holds schema authority (field-kind policy)? ──────────┐
 source ────┤  OR data is already typed Igniter values + integrity?       ├── yes ─→ PROJECTION
            └─────────────────────────────────────────────────────────────┘            (host totality promise; P3 reconciliation)
                              │ no
                              ▼
                          DECODER  (app owns `RawValue -> Result[<Record>, Error]` / `RowResult{Valid|Invalid}`)
```

- **Projection lane:** Postgres (#1), facts (#2), trusted remote (#8), host-schema science files (#4a). The
  host guarantees total+typed rows; the app writes a *transform* (P4), never schema validation.
- **Decoder lane:** HTTP JSON (#5), CSV/file (#6), user body (#7), untrusted remote (#9), raw science files
  (#4b). The app owns validation via the `batch_importer` shape — `ValidateRow -> RowResult { Valid | Invalid }`
  (`apps/igniter-apps/batch_importer/validate.ig:22-28`, `types.ig:35-38`). Decoders yield typed rows *and*
  an error channel; they sit *under* the projection surface (P1 §5).

The lanes are not interchangeable: routing an untrusted source through projection would make the host promise
totality it cannot keep, re-importing the P2 drift hazard into app logic. Routing a host-typed relational
read through a decoder would duplicate the host's gating in `.ig`. Keep them distinct.

---

## 4. Provenance matrix (Q3) — invariant core + per-source companions

`DatasetMeta { source, count, truncated }` (P3) is the **invariant core** — every source has a logical
source name, a returned count, and a "was it capped" bit. Source-specific provenance is added as **small
per-source companion records** (user-record generics don't exist — P1 §1.3 — so there is no `DatasetMeta<Ext>`).

| Source | core `DatasetMeta` | source-specific companion | crosses to `.ig`? | host-only |
| --- | --- | --- | --- | --- |
| Postgres | source, count, truncated | `effective_limit` | core only | `plan_digest` (`read_dispatch.rs:23`), DSN, capability, receipt |
| **facts / history** | source(=store), count, truncated | **`TemporalMeta { valid_at, known_at }`** (`backend.rs:33-44`) | core + `as_of` (temporal branching) | `value_hash`, `causation` (`fact.rs`) |
| HTTP (decoder) | via decoder result | url/host, status, correlation_id (`http.rs`) | via decoder | secrets, auth headers (redacted, `http.rs:129`) |
| CSV/file (decoder) | via decoder result | file name, byte size, `parse_errors` count | via decoder | absolute path (redact) |
| trusted remote (#8) | source(=node), count, truncated | `source_digest` (blake3, `coordination.rs:190`) | core + `source_digest` for trust branching | receipt lineage, passport |
| science file | source(=dataset id), count, truncated | `schema_version`, units | as needed | raw path |

Recommendations:
- Keep `DatasetMeta { source, count, truncated }` as the **only universal record**. Do **not** bloat it with
  every source's fields.
- The **bitemporal window is the most important cross-source addition** — recommend a `TemporalMeta { valid_at,
  known_at }` companion for temporal sources (facts/ledger). It is also the cleanest *non-SQL* metadata,
  proving the model is not table-shaped.
- **Integrity provenance (`source_digest`, `artifact_digest`, receipt id) stays host-side by default**,
  crossing into `.ig` only when the app must *branch on trust*. `effective_limit`/`schema_version` excluded
  from the core (P3).

---

## 5. Package / provenance / remote trust (Q5)

Yes — for trusted-remote (#8) and any cross-node dataset — and it **reuses existing primitives; no new
capability**:

- **Content-address integrity:** `CapsuleRef { capsule_id == content_digest }` via `blake3::hash`
  (`runtime/igniter-machine/src/coordination.rs:135,190`); content deduped by digest (`:201`); transfers
  carry `recipe_digest` (`:986`). The package wave adds sha256 content-locks (`lang/igniter-compiler`).
- **Receipt lineage:** `run_effect` writes a receipt-as-fact; a cross-node projection's lineage is the
  read's receipt id/correlation (already host-tracked, P1 §6).

So a trusted-remote dataset projection attaches `source_digest` (blake3) + receipt lineage as **host
provenance**; `.ig` sees the logical `source` and, for trust-sensitive flows, an opaque `source_digest`. This
keeps the boundary aligned with the package/remote-trust wave without inventing a provenance primitive.

---

## 6. Vocabulary without SQL bias (Q4)

| Concept | Recommendation | Avoid |
| --- | --- | --- |
| The boundary | "**Data Projection**" / "typed projection" — already source-neutral | "query result", "row set" |
| The container | `Collection[<DomainRecord>]` — generic | — |
| The **element type name** | **app's choice, domain-named** — `Row` (tables), `Fact`/`Observation` (ledger/science), `Lead` (CRM), `Payload` (remote). The language imposes **none**. | standardizing on `Row` |
| Generic element noun (when truly source-neutral) | `Record` (the runtime value *is* `Value::Record`) | `Rows`, `ResultSet` |
| Provenance record | `DatasetMeta` — "dataset" is broad (science/ML use it; SQL says "result set") | `RowMeta`, `TableMeta` |
| Temporal companion | `TemporalMeta { valid_at, known_at }` | epoch-numbered "timestamp columns" |

The key anti-SQL-bias move: **the element type is named by the domain, not the boundary.** Because the app
declares the record (P3), `Collection[Fact]` / `Collection[Observation]` / `Collection[Lead]` are as native
as `Collection[TodoRow]`. There is no language-level "Row." This is already true in the fleet —
`query_engine` calls it `Row`, `batch_importer` calls it `RawRow`, emergence calls it `Oscillator`.

---

## 7. Second proof recommendation (Q6): tbackend facts / history

**Recommend `LAB-IGNITER-DATA-PROJECTION-FACTS-SECOND-SOURCE-P7` as the second projection proof.** Why it beats
the alternatives:

| Candidate | Verdict |
| --- | --- |
| **tbackend facts / history** | **Best.** Most host-native (`Fact.value` already typed, `fact.rs:4`); **no external system, no new capability** (in-process kernel, design-bias-clean); exercises the **bitemporal window** Postgres can't → validates `TemporalMeta` + proves the model isn't SQL-shaped; ties into the determinism/emergence research line. |
| CSV / import | Proves the **decoder** lane, not projection — it is the *fallback* proof, not the *primary*. Already has `batch_importer` as precedent. Good as the second *decoder* proof, not the second projection proof. |
| HTTP JSON | Needs the trusted-vs-untrusted split resolved first and a host response-schema policy that does not exist; pulls in network. Heavier; premature. |
| Science dataset file | Appealing (emergence tie-in) but needs a host file-parser + schema; more moving parts than facts. |

**Proof sketch (DB-free, in-process, no new capability):**
`read_bitemporal(store, key, valid_at, known_at)` → typed `Fact.value`s → host materializer (P2) →
continuation `input facts : Collection[<Fact-derived Record>]  input meta : DatasetMeta  input temporal :
TemporalMeta`, with the P3 boot reconciliation against the record type. Acceptance proves: typed field
access over facts; `temporal.valid_at`/`known_at` cross; the *same* projection contract serves a non-SQL
source; a kind-drift still trips `ProjectionSchemaDrift`.

Second *decoder* proof (separate): formalize the untrusted lane as
`LAB-IGNITER-DATA-PROJECTION-DECODER-CONTRACT-P8` over CSV/HTTP — standardize `RawValue -> Result[<Record>,
Error]` / `RowResult`, reusing `batch_importer`.

---

## 8. Risks to avoid

- **SQL bias.** Do not bake `Row`/`table`/`column` into the boundary; the element is domain-named (#6). The
  boundary is a *seam*, not a tabular model.
- **Collapsing the two lanes.** Untrusted sources (HTTP/CSV/user-body/untrusted-remote) MUST stay decoder —
  projection's totality promise needs host schema authority they lack. Conflating re-imports drift into app
  logic; the reverse (decoder for host-typed reads) duplicates host gating.
- **Premature HTTP projection.** HTTP is decoder until a host *response-schema* policy exists (the HTTP
  analogue of `PostgresReadValueKind`). Name it as pressure; do not assume it.
- **Inventing provenance/trust primitives.** Reuse blake3 content-address, sha256 content-locks, receipts
  (#5). No new capability.
- **Bloating `DatasetMeta`.** Keep the invariant core; add per-source companions (`TemporalMeta`, etc.).
- **Conflating export with projection.** Export is the outbound reverse arrow (#10), not inbound projection.
- **Forgetting native data needs no boundary.** In-process `Collection[Oscillator]` (#3) is already `.ig`
  data — don't wrap native values in a projection ceremony.

---

## 9. Payoff for the next research arc (view/HTML expression)

A clean cross-source boundary makes the **view/transform layer source-independent**: once *any* source
projects to `Collection[<Record>]`, the P4 transform → view → HTML pipeline applies unchanged. So the team's
next direction — richer HTML expression (templating / dialects over the contract graph) — sits atop *any*
projection source, not just Postgres. The projection boundary and the view-expression research compose: one
makes data uniform, the other makes its presentation rich.

---

## Verification

```bash
rg -n "Http|HTTP|tbackend|Fact|ledger|CSV|RawRow|RowResult|Dataset|source|artifact_digest|provenance|receipt" \
  runtime apps lab-docs server lang \
  > /tmp/igniter-data-projection-cross-source-grep.txt        # 10901 hits

git diff --check                                               # clean
```

---

## Reporting

- **Recommended generic vocabulary:** boundary = "typed projection"; container = `Collection[<DomainRecord>]`;
  provenance = `DatasetMeta { source, count, truncated }` (+ `TemporalMeta { valid_at, known_at }` for
  temporal sources). **The element noun is domain-chosen** (`Row`/`Fact`/`Observation`/`Lead`/`Payload`),
  never imposed — that is the anti-SQL-bias move.
- **Second-source proof choice:** **tbackend facts / history** — most host-native, no new capability, adds
  the bitemporal-window dimension, proves the boundary is not SQL-shaped. (CSV/import = the second *decoder*
  proof.)
- **Projection / decoder split:** projection iff host schema authority OR pre-typed values + integrity
  (Postgres, facts, trusted-remote, host-schema science); decoder otherwise (HTTP JSON, CSV/file, user body,
  untrusted-remote, raw science). Lanes are not interchangeable.
- **Next cards:** `LAB-IGNITER-DATA-PROJECTION-FACTS-SECOND-SOURCE-P7` (impl, after the Postgres typed-row
  crossing); `LAB-IGNITER-DATA-PROJECTION-DECODER-CONTRACT-P8` (impl, untrusted lane); a future
  `LAB-MACHINE-HTTP-RESPONSE-SCHEMA-POLICY` readiness (what would make vetted HTTP projectable) named as
  pressure.
