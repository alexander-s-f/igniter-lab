# LAB-IO-BOUNDARY-P1 — IO Family Taxonomy and Substrate Readiness Boundary

**Status:** CLOSED — governance/design boundary  
**Route:** GOVERNANCE / DESIGN BOUNDARY / NO IMPLEMENTATION  
**Track:** io-family-taxonomy-and-substrate-readiness-boundary-v0  
**Authority:** lab/governance evidence only  

## Evidence basis

This packet reads the following as evidence, not implementation or canon authority:
- LAB-QUERY-V0-STABILIZATION-P1 for the Query v0 boundary.
- LAB-STORAGE-CAPABILITY-P1/P2 and PROP-046-P1 for StorageCapability gates and proposal-only storage authority.
- LAB-EXECUTE-QUERY-P1/P2/P3 plus filter/order/projection/typechecker support proofs for deterministic mocked query execution.
- LAB-STDLIB-NET-P6/P7/P8/P9 for mocked NetworkCapability request/response, headers, retry, and upstream composition.
- LAB-FAILURE-TAXONOMY-P1/P2/P3/P4 and PROP-047 for failure/outcome naming, including `unknown_external_state`, `timed_out`, `query_error`, and `partial_success`.
- LAB-APP-STATE-P1/P2 and LAB-IGV-TAILMIX-P1 for host-owned state, dispatch seams, and inert UI definitions.
- Canon language covenant CR-001 for opaque `IO.*` names, and canon Law 6 for explicit time.

No older Ruby framework surface is used as language authority.

## 1. Definition of the IO boundary

In Igniter, IO means any observation or effect that crosses from deterministic contract evaluation into an external authority, host substrate, runtime resource, clock, entropy source, process, device, UI shell, or persistence medium.

IO includes:
- Storage reads/writes against tables, collections, queues, databases, object stores, or durable records.
- Network transport against hosts, ports, schemes, methods, listeners, sockets, and upstream services.
- File/Text reads or writes against host paths, encodings, blobs, manifests, or text snapshots.
- Clock/Time observations, monotonic timers, deadlines, retry budgets, and scheduler wakeups.
- Random/Entropy generation for IDs, nonces, correlation tokens, seeds, and salts.
- Process/Command execution, including argv, env, cwd, stdout, stderr, exit status, and termination.
- UI/Host IPC across a browser/webview/Tauri/native shell boundary, including dispatch events and host-owned state.

IO does not include:
- A pure `QueryPlan` / `QueryPlanUnified` value.
- Query source, projection, filter, order, and limit records while they remain typed intent data.
- Capability records as data. A capability describes authority; it is not execution by itself.
- Receipts as data. A receipt records gates and result facts; it does not re-authorize an effect.
- Static `.igv` definitions, view definitions, sidecar metadata, lifecycle labels, pure reducers, or deterministic mocked rows/transports used inside lab proofs.

The boundary terms are deliberately separate:

| Term | Meaning | Authority status |
|---|---|---|
| Intent data | A typed description of desired work, such as `QueryPlan` or `HttpRequest` | Pure CORE data; no external authority |
| Capability data | A bounded grant shape, such as `IO.StorageCapability` or `IO.NetworkCapability` | Authority descriptor; must be checked before substrate execution |
| Receipt data | Evidence of gates, decisions, and observed result facts | Evidence only; no authority to replay or escalate |
| Substrate execution | The actual call into a database, network stack, filesystem, clock, entropy source, process runner, or host IPC channel | IO authority; must not open without a separate readiness proof |

Query v0 is therefore not IO authority. It defines typed query intent, mocked execution semantics, `QueryResult`, and `QueryExecutionReceipt`. Real storage execution belongs to a later IO adapter/substrate route.

## 2. IO family taxonomy

### Storage IO

Storage IO is authority over named sources/tables, read/write operations, row limits, include-all policy, and query execution receipts. The current evidence chain proves `IO.StorageCapability` gates and deterministic mocked execution, not a real database adapter.

Storage-specific authority includes `allowed_sources`, `allowed_ops`, `read_allowed`, `write_allowed`, `row_limit`, `allow_include_all`, and `deny_reason`. Its v0 outcome split is `rows`, `empty`, `denied`, `query_error`, and `system_error`; `row_limit` clamps and does not deny.

Closed in v0: real DB connections, SQL execution, ORM/ActiveRecord/Arel compatibility, migrations, transactions, joins, aggregates, writes, optimizer, persistence runtime, and public/stable API.

### Network IO

Network IO is authority over host, method, scheme, port, timeout budget, headers, transport result, and retry policy. Existing proofs cover mocked HTTP client boundaries, `Map[String,String]` headers, `HttpResult`, deterministic retry envelopes, capability denial, and upstream composition.

Network has a special unknown-state risk: a timeout or disconnect after dispatch may mean the external system received the request but no acknowledgement came back. PROP-047 keeps `timed_out` as a clock/transport observation and `unknown_external_state` as the epistemic outcome that requires reconciliation.

Closed before a real-transport route: DNS, TLS and certificate policy, redirects, streaming, body-size enforcement against real payloads, real sockets, listeners, connection pooling, service loops, retry timing, idempotency enforcement, and post-dispatch reconciliation.

### File/Text IO

File/Text IO is authority over paths, encodings, file capabilities, read/write distinctions, traversal controls, symlink handling, size limits, and snapshot receipts. Canon language currently treats `IO.FileCapability` as an opaque `IO.*` capability name; older lab/passport evidence names `read_file` and `write_file`, but that evidence is not a public or canon file API.

File/Text readiness must distinguish:
- Read snapshot: path was authorized, bytes/text were observed, encoding/size rules were applied, and a receipt can reproduce what was read.
- Write attempt: path was authorized, write mode was bounded, atomicity/overwrite policy was explicit, and partial/unknown write outcomes were classified.

Closed in v0: real file writes, ambient path reads, directory traversal, symlink following by default, implicit current working directory authority, and stable file API claims.

### Clock/Time IO

Clock/Time IO is authority over current time, monotonic time, deadlines, retry budgets, scheduler wakeups, and temporal replay. Canon Law 6 says time is explicit: no ambient `Time.now`; reads require `TemporalCtx` or an explicit event-time binding.

Clock readiness must keep three ideas separate:
- Declared time context (`TemporalCtx`, `tick.time`, `as_of`) as input data.
- Deadline/timeout observation as a clock signal.
- Outcome classification after the timeout, such as `unknown_external_state` only when dispatch started and acknowledgement is missing.

Closed in v0: ambient wall-clock reads, scheduler runtime, sleep/wakeup authority, real retry timers, and treating `timed_out` as a final outcome without epistemic classification.

### Random/Entropy IO

Random/Entropy IO is authority over nonce generation, ID generation, salts, seeds, and reproducibility. Proof-local use of host randomness, such as generating temporary IDs in lab tooling, is not language authority.

Random readiness requires an explicit entropy capability or seed policy, a receipt that records replay-relevant facts, and a deterministic proof mode. Randomness must not silently enter pure contract evaluation.

Closed in v0: ambient random IDs, unrecorded nonce generation, cryptographic authority claims, and stable entropy APIs.

### Process/Command IO

Process/Command IO is authority over command execution, argv, env, cwd, stdin, stdout, stderr, exit status, timeout/kill behavior, and sandbox boundaries. Existing compiler/proof-runner process hygiene is host tooling evidence only; it is not Igniter process IO authority.

Process readiness requires a much stronger security gate than storage or mocked network because commands can read files, write files, fork, access environment secrets, and escape project boundaries.

Closed in v0: process execution from contracts, shell execution, inherited environment authority, implicit cwd access, stable command API, and generic sandbox claims.

### UI/Host IPC

UI/Host IPC is IO-like because an Igniter app or `.igv` definition crosses into a browser, Tauri shell, native backend, or host-owned state holder. It is not the same as Storage or Network IO: the authority holder is the host dispatch boundary and state lifetime owner, not a table source or remote endpoint.

App-State P1/P2 show state values and transitions can be modeled as typed records and pure reducers while holders remain external. IGV Tailmix P1 defines `.igv` definitions as inert data with a tiny JS instruction interpreter and a host `dispatch(event) -> contract` seam. That proves a boundary shape, not Tauri implementation authority.

Closed in v0: Tauri implementation, host state persistence, browser storage claims, client-side VM authority, public `.igv` API, and implicit capability grants from UI events.

## 3. Cross-family matrix

| Family | Authority holder | Capability shape | Deterministic proof mode | Receipt requirements | Denial/failure vocabulary | Replayability | Security boundary | Closed in v0 |
|---|---|---|---|---|---|---|---|---|
| Storage | Storage adapter / source registry | `IO.StorageCapability`: sources, ops, read/write flags, row limits | Mocked rows and deterministic gate simulator | Gate, effective limit, clamp, result kind, rows returned | `denied`, `query_error`, `system_error`, `rows`, `empty` | High for mocked rows; real adapter needs snapshot/fixture contract | Source allowlist, op allowlist, include-all policy, row cap | DB, SQL, ORM, writes, joins, aggregates, transactions |
| Network | Transport adapter / host policy | `IO.NetworkCapability`: host, method, scheme, port, timeout, header policy | Mocked transport table and retry envelope | Dispatch marker, ack marker, status/error, retry facts, redaction facts | `denied`, `system_error`, `timed_out`, `unknown_external_state`, domain-local HTTP kinds | Partial; post-dispatch unknown requires reconciliation | Host/scheme/port policy, redaction, timeout, idempotency | DNS, TLS, redirects, streaming, sockets, listeners |
| File/Text | Filesystem adapter / path policy | File capability with roots, modes, encodings, size limits | Mocked file snapshots | Canonical path, mode, encoding, size, content digest/snapshot facts | `denied`, `system_error`, `unknown_external_state`, `partial_success` for bounded batch writes | High for reads if snapshot is recorded; writes require atomicity model | Root jail, traversal, symlink, overwrite/atomicity | Real writes, ambient reads, stable file API |
| Clock/Time | Clock adapter / TemporalCtx provider | Time capability or explicit temporal context | Fixed clock fixture, monotonic sequence fixture | Observed time, source, deadline, elapsed budget | `timed_out` as observation; classify outcome separately | High with fixed clock; scheduler replay separate | No ambient clock; explicit time source | Ambient `Time.now`, scheduler runtime, sleeps |
| Random/Entropy | Entropy adapter / seed provider | Entropy capability with purpose, seed/replay policy | Fixed seed or recorded generated value | Purpose, seed policy, generated value digest/value as appropriate | `denied`, `system_error`; no unknown unless external entropy service used | High only if seeded or recorded | No ambient random; purpose-bound entropy | Ambient IDs, crypto API claims |
| Process/Command | Command runner / sandbox | Command capability with argv/env/cwd/stdio/timeouts | Mocked command result table | argv, env policy, cwd, stdout/stderr digest, exit status, timeout/kill facts | `denied`, `system_error`, `timed_out`, `unknown_external_state` if command effects escaped before kill | Low unless all side effects are mocked or sandboxed | Strong sandbox, env scrubbing, cwd jail | Real commands, shell, inherited env |
| UI/Host IPC | Host shell / dispatch seam / state holder | Host/IPC capability or dispatch manifest | Event fixture + pure reducer + mocked host reply | event id, state lifetime, dispatch target, host response facts | `denied`, `system_error`, domain-local validation/result kinds | Medium; depends on event log and host state snapshot | Host-owned state, IPC message schema, no implicit grants | Tauri implementation, browser storage authority, client VM |

## 4. Substrate readiness definition

A real IO adapter is not ready until all of the following are true for its family:

1. Explicit capability/passport shape exists, with named authority fields and no ambient fallback.
2. Mock proof exists for the same request/intent/capability/receipt path.
3. Denial-as-data is proved for capability failure; denial does not raise or collapse into `system_error`.
4. Receipt schema records gates and result facts without becoming authority.
5. Deterministic/replay mode exists for lab and regression proofs.
6. Timeout and unknown-state classification is family-specific and aligned with PROP-047.
7. No hidden host globals are required: no ambient cwd, clock, env, network stack, filesystem, database handle, or UI singleton.
8. Failure vocabulary aligns with the six stable PROP-047 terms where applicable: `denied`, `unknown_external_state`, `timed_out`, `system_error`, `query_error`, `partial_success`.
9. Public/stable API claims remain closed until a separate governance route promotes them.
10. Implementation authority is opened by an explicit later card, not inferred from this readiness document.

## 5. Storage IO readiness

Storage has the strongest current readiness because Query v0 and `IO.StorageCapability` have a coherent evidence chain:
- Query v0 defines typed intent AST, pure builders, mocked execution, `QueryResult`, and `QueryExecutionReceipt`.
- StorageCapability P1/P2 define and prove the gate sequence, row-limit clamp, include-all `query_error`, denial-as-data, and receipt invariants.
- ExecuteQuery P1/P2/P3 prove a complete deterministic mocked query pipeline.

Readiness decision:

| Route | Decision | Reason |
|---|---|---|
| Design-only adapter card | READY | The boundary can define adapter inputs/outputs without real substrate calls |
| Mocked adapter proof | READY WITH SCOPE | Must use fixture tables/mock adapter records only; no DB/SQL/ORM |
| Real adapter proof | HOLD | Missing adapter authority model, connection lifecycle, transaction/write story, snapshot/replay strategy, and real failure classification |
| Production/public API | HOLD | No stable surface authorized |

Recommended immediate route: **LAB-STORAGE-ADAPTER-P1 — mocked storage adapter contract hardening**. It should harden an adapter contract shape around existing Query v0 intent/receipt semantics, while keeping real DB execution closed.

## 6. Network IO readiness

Network evidence is substantial but not ready for real transport:
- P6 proves a minimal mocked HTTP client request/response boundary for `IO.NetworkCapability`.
- P7 proves `Map[String,String]` headers and redaction preservation.
- P8 proves `HttpResult`, deterministic retry policy, denial-as-data, and retry envelope behavior.
- P9 proves upstream HTTP call composition into domain `ContractResult`.
- Failure taxonomy P2/P3/P4 and PROP-047 separate `timed_out`, `unknown_external_state`, `system_error`, `denied`, and `partial_success`.

Unsafe before real transport:
- DNS and name resolution.
- TLS handshake, trust roots, certificate validation, and SNI.
- Redirect policy and cross-host redirect capability escalation.
- Streaming, chunking, partial body reads, and backpressure.
- Real payload/body limits and redaction under large or binary bodies.
- Retry timing under real clocks.
- Idempotency keys, replay safety, and reconciliation after post-dispatch unknown state.
- Connection pooling, socket lifetime, listener/accept loops, and service-loop lifecycle.

Recommended route: **Network real-transport HOLD card** before any real transport proof. That card should inventory DNS/TLS/redirect/streaming/idempotency hazards and define the smallest safe mocked-to-real transition criteria.

## 7. File / Clock / Random / Process readiness

### File/Text

Known evidence: canon permits opaque `IO.FileCapability` names; lab/passport work has proof-local `read_file`/`write_file` vocabulary and path-sandbox evidence. Missing evidence: family-specific path capability shape, canonicalization rules, encoding rules, symlink policy, snapshot receipt shape, write atomicity, partial write classification, and stable mock fixture model.

Recommended first proof: **LAB-FILE-IO-P1 — file/text capability shape and mocked read snapshot proof**.

Closed surfaces: real file writes, ambient reads, directory traversal, symlink traversal by default, public file API.

### Clock/Time

Known evidence: canon Law 6 requires explicit time; `TemporalCtx` and event-time bindings exist as language concepts; network retry proofs use deterministic budgets. Missing evidence: clock capability shape, monotonic-vs-wall-clock distinction, deadline receipt, scheduler substrate, replay contract, and timeout-to-outcome classifier outside mocked network.

Recommended first proof: **LAB-CLOCK-P1 — deterministic clock observation and deadline receipt boundary**.

Closed surfaces: ambient `Time.now`, scheduler runtime, sleeps/wakeups, real retry timers.

### Random/Entropy

Known evidence: proof-local host randomness exists in older lab tooling only. Missing evidence: entropy capability shape, purpose binding, seed policy, replay policy, receipt shape, and cryptographic/non-cryptographic distinction.

Recommended first proof: **LAB-RANDOM-P1 — deterministic seed/nonce receipt boundary**.

Closed surfaces: ambient random IDs, unrecorded entropy, crypto authority claims, public random API.

### Process/Command

Known evidence: proof-runner subprocess hardening exists for tooling, including explicit pipes and timeout behavior. Missing evidence: contract-level command capability, argv/env/cwd policy, sandbox model, stdout/stderr receipt shape, side-effect containment, and unknown-state classification after forced termination.

Recommended route: HOLD until storage/file/clock/random are cleaner. If needed later, open **LAB-PROCESS-BOUNDARY-P1 — command authority threat model and mocked result shape**, design-only.

Closed surfaces: real command execution, shell execution, inherited environment, implicit cwd, public command API.

## 8. UI/Host IPC readiness

App-State P1/P2 and IGV Tailmix P1 show a promising split:
- State records and transitions can be pure data/reducer work.
- State holders remain host-owned.
- `.igv` definitions are inert definitions, not capability grants.
- Host dispatch is a seam: event in, contract result/receipt out.

Host IPC is IO-like because the host can observe local/session/window state, call native APIs, persist state, or dispatch effects. It is not Storage IO because the authority is not a table/source grant. It is not Network IO because the security boundary is not host/scheme/port; it is message schema, dispatch target, state lifetime, and host-owned capability injection.

Readiness decision:
- Design boundary: READY.
- Mocked host dispatch proof: READY WITH SCOPE.
- Tauri implementation: HOLD.
- Client-side VM authority: CLOSED.

Recommended first proof: **LAB-HOST-IPC-P1 — host dispatch seam, state lifetime receipt, and mocked IPC result boundary**.

## 9. Recommended route map

Immediate next card:
- **LAB-STORAGE-ADAPTER-P1 — mocked storage adapter contract hardening**. Scope: adapter contract shape, fixture-backed table source, same Query v0 `QueryResult` / `QueryExecutionReceipt`, no real DB/SQL/ORM.

Parallel safe cards:
- **LAB-FILE-IO-P1 — file/text capability shape and mocked read snapshot proof**.
- **LAB-CLOCK-P1 — deterministic clock observation and deadline receipt boundary**.
- **LAB-RANDOM-P1 — deterministic seed/nonce receipt boundary**.
- **LAB-HOST-IPC-P1 — host dispatch seam and mocked IPC receipt boundary**.

Hold cards:
- **Network real-transport HOLD card** — DNS/TLS/redirect/streaming/idempotency hazard inventory before any real sockets.
- **LAB-PROCESS-BOUNDARY-P1** — command authority threat model only, after safer IO families are stabilized.
- Any real DB adapter, file write, scheduler/clock runtime, entropy runtime, Tauri implementation, public API, or canon promotion route.

## 10. Closed authority surfaces

This packet does not authorize:
- Parser/compiler/VM changes.
- Real DB execution.
- SQL execution.
- ORM/ActiveRecord/Arel compatibility.
- Real network transport.
- File writes.
- Process execution.
- Clock/random runtime authority.
- Tauri implementation.
- Public/stable API.
- Canon claim.

## 11. Decision

IO should remain a family taxonomy, not a single undifferentiated bucket. Storage is the first candidate for a design/mock adapter route because Query v0 and StorageCapability already define intent, gates, mocked execution, and receipts. Network remains mocked-only until real transport hazards are isolated. File, Clock, Random, Process, and UI/Host IPC each require family-specific readiness proofs before implementation authority opens.
