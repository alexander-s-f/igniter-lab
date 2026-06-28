# LAB-AUDIT-CONTROL-BOARD-V1

Date: 2026-06-28
Status: living control board
Lane: igniter-lab / audit-assimilation / foundation-hardening

## Purpose

This is the audit decision board: one place to track each foundation-audit
finding from source audit to decision, closure evidence, and the next safe
slice. It is not a new audit and not canon authority.

Use this board before opening another foundation-hardening card:

1. Find the audit item here.
2. Check whether it is already closed, stale, queued, or deliberately deferred.
3. If it is queued, dispatch the named next card only after re-verifying live
   source and current `IMPLEMENTED_SURFACE.md`.

Historical source audits remain evidence snapshots. Current truth comes from
live source, package-local `IMPLEMENTED_SURFACE.md`, proof packets, and commits.

## Status Legend

| Status | Meaning |
|---|---|
| CLOSED | Finding was implemented/proven or made unreachable for the stated surface. Do not reopen without fresh regression evidence. |
| PARTLY CLOSED | The original blocker is gone, but a named policy/product follow-up remains. |
| READY | Readiness/design is complete; implementation card can be dispatched. |
| QUEUED | Real issue remains, but not yet sliced or not next in priority. |
| DEFERRED | Real but intentionally not blocking the current wave. |
| STALE / NOT CONFIRMED | Audit claim was overtaken by later work, did not reproduce, or should route to a different surface. |

## Control Board

| ID | Audit item | Category | Decision | Status | Closure / evidence | Next safe slice |
|---|---|---|---|---|---|---|
| A01 | Compiler parser recursion and float-literal panic | Blocker / crash-safety | Budget parser depth and turn non-finite/overflowing float literals into diagnostics. | CLOSED | `LAB-IGNITER-COMPILER-INPUT-ROBUSTNESS-P1`; refreshed in `lab-audit-foundation-status-refresh-p2-v0.md`. | None unless a new crash reproducer appears. |
| A02 | VM integer overflow, eval depth, collection/range allocation, non-progress loop | Blocker / runtime safety | Checked arithmetic plus eval-depth, collection, and step budgets. | CLOSED | `LAB-IGNITER-VM-EVAL-DEPTH-AND-COLLECTION-BUDGET-P2`; checked arithmetic sweep; refresh marks old VM blockers closed. | None for covered specimens; source-run/REPL remains separate DX. |
| A03 | Decimal money wrap/truncate/scale comparison | Correctness / money | Use checked i128 arithmetic, exact-only division, bounded scale, scale-normalized compare. | CLOSED | `LAB-STDLIB-DECIMAL-MONEY-CONTRACT-READINESS-P1`; `LAB-STDLIB-DECIMAL-MONEY-SAFE-P2`; current waves show exact `to_text(Decimal)` and money route proofs. | Route-specific Bool/Decimal adoption only after row-shape review. |
| A04 | stdlib IO write symlink escape | Safety / sandbox | Canonicalize sandbox root and write parents; refuse symlink write targets. | CLOSED | `lab-stdlib-io-sandbox-hardening-p1`. | Host-routed capability readiness later; do not reopen symlink escape from old audit alone. |
| A05 | render-html `safe_url` control-character bypass and attribute escaping | Safety / XSS | Fail closed for C0/control/protocol-relative URL forms; keep renderer-owned escaping. | CLOSED | `lab-igniter-web-render-html-output-safety-p1`. | Richer view vocab must continue through renderer-owned escaping. |
| A06 | frame-ui empty `leads` panic | Blocker / UI crash | Empty leads return schema error, not panic/WASM abort. | CLOSED | `LAB-FRAME-UI-EMPTY-LEADS-PANIC-P1`. | Frame-ui product work can proceed; no crash-safety block remains here. |
| A07 | Machine forgeable passport on data-plane | Security / authority | Use signed data-plane entrypoints; legacy unsigned surfaces are compatibility only. | CLOSED for signed entrypoints | `LAB-MACHINE-SIGNED-PASSPORT-DATAPLANE-P26`; signed paths and forged-passport negatives exist. | Choose signed entrypoints in new wiring; future removal of unsigned compat is policy work. |
| A08 | IgWeb forgeable effect passport | Security / authority | Sign IgWeb effect-host passports before machine write bridge. | CLOSED | `LAB-IGNITER-WEB-SIGNED-EFFECT-PASSPORT-P27`. | Durable/operator-provided signing key config remains future work. |
| A09 | Inbound unbounded reads / slowloris / auth composition | Security / transport | Shared hardened read policy: header/body caps, timeouts, middleware ordering. | CLOSED | `lab-igniter-server-inbound-hardened-read-p28`; current waves mark inbound read caps/timeouts implemented. | Public bind still closed until TLS/checklist operator config. |
| A10 | Loopback-to-live gate missing | Security / production gate | Keep non-loopback bind behind explicit server authorization/checklist. | PARTLY CLOSED | Server gate API `LAB-IGNITER-SERVER-LIVE-BIND-GATE-P31`; IgWeb pre-bind wiring `P32`; live-bind TLS checklist readiness `P33`. | `LAB-IGNITER-WEB-HOST-LIVE-BIND-CHECKLIST-PARSE-P34` / TLS checklist parse before any public bind. |
| A11 | MCP unauthenticated local tools and checkpoint path escape | Security / local tool authority | Local env-token gate for `tools/call`; checkpoint paths root-confined; reserved stores refused. | CLOSED | `lab-machine-mcp-auth-checkpoint-sandbox-p30`. | Network auth / signed passport MCP is future, not current local-stdio claim. |
| A12 | Compiler lock computed but not enforced on build | Supply chain | Support locked/frozen project compile before emit. | PARTLY CLOSED | `LAB-IGNITER-COMPILER-LOCK-ON-BUILD-P2`; `compile --project-root ... --locked` / `--frozen`; `LAB-IGNITER-COMPILER-DEP-PATH-CONTAINMENT-P3` for local deps. | Compile-lock default policy and registry/signing/remote-source readiness. |
| A13 | Local dependency path escape | Supply chain | Refuse absolute, lexical `..`, and symlink escapes outside workspace trust root. | CLOSED | Commit `7fca309`; proof packet `lab-igniter-compiler-dep-path-containment-p3-v0.md`; diagnostic `OOF-IMP10`. | None unless new dep resolver surface is added. |
| A14 | IgWeb route-chain scale wall | Performance / product scale | Replace linear nested route chain with prefix-grouped lowering while preserving authored-order tie-breakers. | CLOSED | `lab-igniter-web-prefix-grouped-lowering-p4-v0.md`; current tests include bounded large route lowering. | Source-map/readability card only if debugging pressure appears. |
| A15 | `igweb-serve` sync async trap for DB/effects | Product blocker / host IO | Async machine runner bypasses sync `call()` path and drives reads/effects in Tokio runner mode. | CLOSED for async machine mode | `lab-igniter-web-async-machine-runner-p2-v0.md`; ReadThen/EffectHost runner rows in current waves. | Sync mode remains observe-only by design; public/operator hardening tracked separately. |
| A16 | Host config could not express typed Bool/Decimal read kinds | Product blocker / Todo API | Add typed read field kinds to host config. | CLOSED | Commit `7c46b98`; `lab-igniter-web-host-config-typed-field-kinds-p33-v0.md`. | Route-specific typed Bool/Decimal adoption after row-shape review. |
| A17 | Multi-source read config missing | Stale product claim | `extra_sources` / `[postgres.read.<source>]` supports multiple allowed sources. | STALE / NOT CONFIRMED | Current waves and `host_config.rs` mark multi-source read config implemented. | Only multi-DSN/cross-DB joins remain readiness-only. |
| A18 | VM map-lambda `call_contract`, `variant_construct`, machine fleet blockers | Correctness / VM parity | Add eval-ast parity and variant construction support for covered specimens. | CLOSED | `lab-vm-map-lambda-callcontract-parity-p1-v0.md`; `LAB-VM-EVALAST-VARIANT-CONSTRUCT-IMPL-P5`; fleet recheck 13/13 in status refresh. | Dynamic dispatch remains governance-gated; recursive self-call/TCO separate. |
| A19 | Type IR is stringly / name-only soundness holes | Correctness / compiler soundness | Replace stringly type surfaces with an `IgType` enum model. | READY | `lab-igniter-compiler-type-ir-enum-readiness-p4-v0.md`. | `LAB-IGNITER-COMPILER-TYPE-IR-ENUM-P5`. |
| A20 | Pure contract can launder effects through `def` | Correctness / effect system | Interprocedural effect summary over call graph/SCC. | READY | `lab-igniter-compiler-effect-summary-readiness-p5-v0.md`. | `LAB-IGNITER-COMPILER-EFFECT-SUMMARY-P6`. |
| A21 | Durable exactly-once / replay ordering / fsync foundation | Durability / machine-TBackend substrate | Server-assigned `seq_id`, durable CAS/prepared, fsync group commit. | QUEUED | Roadmap lever L6; still a real substrate gap. | `LAB-MACHINE-DURABLE-CAS-SEQID-FSYNC-P*` or TBackend-specific split after owner routing. |
| A22 | det_* cross-arch claim needs evidence | Science / determinism | Keep claims tiered; use qemu/hardware golden-bit proof before stronger cross-arch language. | QUEUED / external parallel | Current waves point to det-math evidence lanes; public science work stays repo-local. | T1/T2 det-math qemu/hardware cards in emergence/science lane. |
| A23 | VM direct source-run / REPL missing | DX | Build source-to-run/REPL as a product DX surface, not as audit safety. | QUEUED | Current waves mark `.igapp` runtime implemented but source-run missing. | `LAB-IGNITER-VM-SOURCE-RUN-REPL-P*`. |
| A24 | Frame-ui IDE preview still tied to legacy view engine / product unpause | Product / UI DX | Rehome preview onto Rust projector and continue form/view-engine bridge work. | QUEUED / parallel | Frame-ui P2/P3/P5/P6 proofs exist; current waves track frame-ui separately. | Let active frame-ui agent continue; do not mix into foundation audit batch. |

## Not Reopened

These items appeared in older audit or agent reasoning but should not be routed
as fresh blockers without new live evidence:

| Claim | Current handling |
|---|---|
| "Parser depth and float literals still crash the compiler." | Closed by A01. |
| "VM arithmetic/eval depth/huge collections are still open blockers." | Closed by A02 for covered surfaces. |
| "Todo/Postgres cannot express Bool/Decimal typed rows in host config." | Closed by A16; product routes still need reviewed adoption. |
| "IgWeb machine runner cannot execute effects because `igweb-serve` is sync." | Closed for async machine mode by A15; sync mode intentionally remains observe-only. |
| "Multi-source read config is not implemented." | Stale after A17. |
| "Frame generated Cargo.lock is a tracked dirty tail." | Closed by commit `2b9269f`; local generated lock remains ignored. |
| "Route matching scale is only a micro-optimization." | Reclassified and closed as a compile/scale blocker by prefix-grouped lowering (A14). |

## Decision Gates

### Gate 1: Audit Exit

We can exit the current foundation-audit digestion when:

- all `Blocker` and `Safety` rows are either `CLOSED`, `PARTLY CLOSED` with a
  named gate, or `QUEUED` with an owner lane;
- no agent routes work from a historical audit packet without checking this
  board and the current `IMPLEMENTED_SURFACE.md`;
- the next wave contains only named, narrow implementation/readiness cards.

Current state: **audit digestion is controlled, not finished**. Severe now-live
crash/XSS/sandbox findings are closed. Remaining work is primarily compiler
soundness, effect summaries, live-bind checklist, durability, and DX.

### Gate 2: Public / Non-Loopback Bind

Public bind remains closed. Required before any non-loopback listener:

- signed authority on the relevant path;
- hardened inbound read policy;
- live-bind authorization/checklist parsed from operator config;
- TLS/operator story explicitly accepted;
- human approval.

### Gate 3: New Science / Product Claims

Do not upgrade lab evidence into public/canon claims without the matching proof
tier:

- package admission proves artifact identity, not deployed remote execution;
- det-math T0/T1/T2 evidence scopes the reproducibility claim;
- Todo API DB-free/fake proofs do not imply production DB ownership or schema
  migration policy.

## Recommended Next Audit Wave

Dispatch these as separate cards, not one blended task:

1. `LAB-IGNITER-COMPILER-TYPE-IR-ENUM-P5`
   - Why: highest remaining compiler soundness item with readiness complete.
   - Boundary: compiler IR/type model only; no language surface promise beyond
     existing semantics.

2. `LAB-IGNITER-COMPILER-EFFECT-SUMMARY-P6`
   - Why: closes pure/effect laundering over existing call graph.
   - Boundary: compiler summary and diagnostics; no runtime IO changes.

3. `LAB-IGNITER-WEB-HOST-LIVE-BIND-CHECKLIST-PARSE-P34`
   - Why: turns live-bind readiness into operator-checkable config without
     opening public bind.
   - Boundary: parse/diagnose/checklist only; no non-loopback demo.

4. Compile-lock default policy readiness
   - Why: P2/P3 made locked compile possible and contained deps; policy is the
     remaining ambiguity.
   - Boundary: readiness/policy first; do not flip defaults without explicit
     acceptance matrix.

5. Durable CAS / seq_id / fsync owner split
   - Why: real substrate gap, but needs owner decision between machine and
     TBackend lanes.
   - Boundary: readiness/split first unless the active TBackend wave already
     owns the implementation.

6. `LAB-IGNITER-VM-SOURCE-RUN-REPL-P*`
   - Why: DX payoff after safety pass.
   - Boundary: direct source execution surface only; no dynamic contract
     dispatch governance shortcut.

## Maintenance Rule

When a card closes one of the rows above, update only:

- the row status/evidence here;
- the relevant package-local `IMPLEMENTED_SURFACE.md` if user-facing current
  truth changed;
- `current-waves-index.md` only if the wave map changed.

Do not create a second audit board.
