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
| A10 | Loopback-to-live gate missing | Security / production gate | Keep non-loopback bind behind explicit server authorization/checklist. | PARTLY CLOSED | Server gate API `LAB-IGNITER-SERVER-LIVE-BIND-GATE-P31`; IgWeb pre-bind wiring `P32`; live-bind TLS checklist readiness `P33`; parse-only operator checklist + fail-closed diagnostics `LAB-IGNITER-WEB-HOST-LIVE-BIND-CHECKLIST-PARSE-P34` (`[host.live_bind]`, NOT wired to real `Run` `authorize_bind` — public bind still closed); gate-decision packet `LAB-IGNITER-WEB-LIVE-BIND-GATE-DECISION-READINESS-P35` = HOLD enablement, authority chain + cards named; report-only dry-run `LAB-IGNITER-WEB-LIVE-BIND-DRY-RUN-VERDICT-P36` DONE (`igweb-serve live-bind-check`; `socket_opened=false`, never binds); inbound durable signed-passport backing `LAB-IGNITER-WEB-INBOUND-SIGNED-PASSPORT-DURABLE-KEY-P37` DONE for the dry-run/check path (`signed_passport_path_wired=true` only after host loads/validates a v0 64-hex trusted issuer key file into `PassportVerifier`; missing/malformed material refuses secret-safely); terminated-upstream TLS runbook `LAB-IGNITER-WEB-TLS-TERMINATED-UPSTREAM-RUNBOOK-P38` DONE (operator contract only; headers are hints without trusted upstream boundary; `native_tls` blocked for actual proof; no listener opened). | Next: P39 lab-only/human-gated bind proof with P36+P37+P38 checklist; public bind remains closed until then. |
| A11 | MCP unauthenticated local tools and checkpoint path escape | Security / local tool authority | Local env-token gate for `tools/call`; checkpoint paths root-confined; reserved stores refused. | CLOSED | `lab-machine-mcp-auth-checkpoint-sandbox-p30`. | Network auth / signed passport MCP is future, not current local-stdio claim. |
| A12 | Compiler lock computed but not enforced on build | Supply chain | Support locked/frozen project compile before emit. | PARTLY CLOSED (default policy decided) | `LAB-IGNITER-COMPILER-LOCK-ON-BUILD-P2`; `compile --project-root ... --locked` / `--frozen`; `LAB-IGNITER-COMPILER-DEP-PATH-CONTAINMENT-P3` for local deps; default-policy readiness `lab-igniter-compiler-lock-default-policy-readiness-p4-v0.md` (decision: keep explicit `--locked`, defer default-on). | Default-on enforcement deferred to `LAB-IGNITER-COMPILER-LOCK-DEFAULT-ENFORCE-P5` (gated on registry/signing/remote-source readiness). |
| A13 | Local dependency path escape | Supply chain | Refuse absolute, lexical `..`, and symlink escapes outside workspace trust root. | CLOSED | Commit `7fca309`; proof packet `lab-igniter-compiler-dep-path-containment-p3-v0.md`; diagnostic `OOF-IMP10`. | None unless new dep resolver surface is added. |
| A14 | IgWeb route-chain scale wall | Performance / product scale | Replace linear nested route chain with prefix-grouped lowering while preserving authored-order tie-breakers. | CLOSED | `lab-igniter-web-prefix-grouped-lowering-p4-v0.md`; current tests include bounded large route lowering. | Source-map/readability card only if debugging pressure appears. |
| A15 | `igweb-serve` sync async trap for DB/effects | Product blocker / host IO | Async machine runner bypasses sync `call()` path and drives reads/effects in Tokio runner mode. | CLOSED for async machine mode | `lab-igniter-web-async-machine-runner-p2-v0.md`; ReadThen/EffectHost runner rows in current waves. | Sync mode remains observe-only by design; public/operator hardening tracked separately. |
| A16 | Host config could not express typed Bool/Decimal read kinds | Product blocker / Todo API | Add typed read field kinds to host config. | CLOSED | Commit `7c46b98`; `lab-igniter-web-host-config-typed-field-kinds-p33-v0.md`. | Route-specific typed Bool/Decimal adoption after row-shape review. |
| A17 | Multi-source read config missing | Stale product claim | `extra_sources` / `[postgres.read.<source>]` supports multiple allowed sources. | STALE / NOT CONFIRMED | Current waves and `host_config.rs` mark multi-source read config implemented. | Only multi-DSN/cross-DB joins remain readiness-only. |
| A18 | VM map-lambda `call_contract`, `variant_construct`, machine fleet blockers | Correctness / VM parity | Add eval-ast parity and variant construction support for covered specimens. | CLOSED | `lab-vm-map-lambda-callcontract-parity-p1-v0.md`; `LAB-VM-EVALAST-VARIANT-CONSTRUCT-IMPL-P5`; fleet recheck 13/13 in status refresh. | Dynamic dispatch remains governance-gated; recursive self-call/TCO separate. |
| A19 | Type IR is stringly / name-only soundness holes | Correctness / compiler soundness | Replace stringly type surfaces with an `IgType` enum model. | CLOSED (IgType slices done; stdlib later) | `lab-igniter-compiler-type-ir-enum-p5-v0.md` (`enum IgType` helper boundary, variant-field generic check fails closed `OOF-KIND2`, SIR byte-identical); `lab-igniter-compiler-user-fn-signature-check-p6-v0.md` (B-U1: user-`def` call arity + parameter-type check at `Expr::Call`, `OOF-TY0`, structural via `IgType`); `lab-igniter-compiler-record-literal-noninline-field-typing-p7-v0.md` (B-U3: non-inline record-literal field values compared structurally via `IgType`); `lab-igniter-compiler-call-contract-arg-typing-p8-v0.md` (B-U2: literal `call_contract` per-argument type check vs callee `input_types`, same `IgType` boundary as P6, `OOF-TY0`; Unknown-bearing deferred; 4 regression-lock tests; IgWeb lowering green). **P8a follow-up (found by P1 verify-first, machine fleet sweep): `IgType::structurally_assignable` treated `String`≠`Text`, so P8 wrongly rejected `erp_logistics` (string literal → `Text` input); fixed with `canonical_scalar_name` (`String`≡`Text`) in `type_ir.rs` — fleet 13/13, also strengthens P6/P7.** **`LAB-IGNITER-COMPILER-ARRAY-LITERAL-ELEMENT-TYPING-P9` DONE** — `check_array_literal_shape` non-record elements now compare via `IgType` structural assignability; mixed scalar arrays fail closed, `String`→`Text` alias inherited, record arrays still shape-check, complex elements remain Unknown-compatible; 6 new tests + full compiler suite (`lab-igniter-compiler-array-literal-element-typing-p9-v0.md`). | Stdlib arg-typing later if a live gap remains. |
| A20 | Pure contract can launder effects through `def` | Correctness / effect system | Interprocedural effect summary over call graph/SCC. | CLOSED (def + call_contract) | P6 `lab-igniter-compiler-effect-summary-p6-v0.md` (`OOF-M1` transitive-via-def, Tarjan SCC, 7/7). P7 `lab-igniter-compiler-effect-summary-call-contract-p7-v0.md`: `call_contract` laundering **closed by construction** — v0 allows only `pure` literal callees (`OOF-TY0`), pure callees provably I/O-free; 3 regression-lock tests (no propagation needed). | Contract-level effect propagation `LAB-IGNITER-COMPILER-EFFECT-SUMMARY-CONTRACT-GRAPH-P8` only if v0 relaxes the pure-only callee rule; dynamic dispatch + SIR metadata still deferred. |
| A21 | Durable exactly-once / replay ordering / fsync foundation | Durability / machine-TBackend substrate | Server-assigned `seq_id`, durable CAS/prepared, fsync group commit. | PG-CAS + WAL + seq DONE | `lab-machine-durable-cas-seqid-fsync-owner-split-p1-v0.md` (owner split); **`LAB-MACHINE-DURABLE-CAS-PG-EXACTLY-ONCE-P2` CLOSED** — DB-native `effect_receipts(idempotency_key)` UNIQUE CAS proven for multi-process exactly-once (2 concurrent writers/2 processes → 1 mutation/receipt), canonical `EFFECT_RECEIPTS_DDL`, DDL-drift→`PermanentConfig` (`lab-machine-durable-cas-pg-exactly-once-p2-v0.md`). **`LAB-MACHINE-WAL-FSYNC-NONSILENT-RECOVERY-P2` CLOSED** — WAL `append` per-record `fdatasync` (default `WalDurability::Sync`); `replay_reported()` flags benign torn tail vs mid-stream `CrcMismatch`/`Deserialize` corruption (byte offsets); boot `replay()` fails closed on corruption (`EngineError::Corruption`), tolerates tail; fsync-to-OS, NO power-loss claim (`lab-machine-wal-fsync-nonsilent-recovery-p2-v0.md`). Verify-first: TBackend daemon (`pure_core`) owns fact-log seq_id/CAS/group-commit (P9/P6/P12). **`LAB-MACHINE-RECEIPT-SEQID-ORDERING-READINESS-P3` DONE** — receipt ordering authority = wall-clock `transaction_time`; equal-tx prepared→terminal resolution relies on incidental push order (`max_by` last-equal) + non-monotonic `SystemClock`; decision = ADOPT a local per-process `receipt_seq` tie-break (NOT TBackend seq_id) via `LAB-MACHINE-RECEIPT-SEQ-TIEBREAK-P4` (`lab-machine-receipt-seqid-ordering-readiness-p3-v0.md`). **`LAB-MACHINE-RECEIPT-SEQ-TIEBREAK-P4` CLOSED** — per-process `receipt_seq` stamped on every receipt fact; latest-receipt selection = `(transaction_time, receipt_seq)` via one shared `receipt_is_newer_or_equal` helper across write-resolution/recovery/observability; equal-tx prepared→terminal now deterministic (adversarial-push-order proof), replay writes no new receipt/seq, tx stays primary (non-monotonic boundary documented); 8 tests, DB-free (`lab-machine-receipt-seq-tiebreak-p4-v0.md`). | Seq tail DONE. Later: WAL group-commit (perf); deferred cross-project `LAB-MACHINE-TBACKEND-RECEIPT-ADOPTION-READINESS-P2`. |
| A22 | det_* cross-arch claim needs evidence | Science / determinism | Keep claims tiered; use qemu/hardware golden-bit proof before stronger cross-arch language. | QUEUED / external parallel | Current waves point to det-math evidence lanes; public science work stays repo-local. | T1/T2 det-math qemu/hardware cards in emergence/science lane. |
| A23 | VM direct source-run / REPL missing | DX | Build source-to-run/REPL as a product DX surface, not as audit safety. | CLOSED for machine one-shot | Readiness `lab-igniter-vm-source-run-repl-readiness-p1-v0.md`: **verify-first overturned "REPL missing"** — `igniter-machine`'s `igniter-repl` (feat `repl`) already compiles `.ig` source in-memory (`load_contract_source`) + `dispatch`es, with a headless `--script` mode (`repl_headless_smoke_tests`). **`LAB-IGNITER-MACHINE-RUN-SOURCE-ONESHOT-P2` CLOSED** — `igniter-repl --run <source.ig> <ContractName> <json|@file>` reuses `load_contract_source` + `dispatch`, prints only JSON result, handles bad JSON/source/unknown contract non-zero; `--script` tests remain green (`lab-igniter-machine-run-source-oneshot-p2-v0.md`). | `igc run` / unified `igniter run` deferred to command-center DX, not audit blocker. |
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

## Latest Audit Wave Closure

Dispatched and closed on 2026-06-28 after the first foundation-hardening wave.

| Card | Outcome |
|---|---|
| `LAB-IGNITER-COMPILER-USER-FN-SIGNATURE-CHECK-P6` | Implemented user-`def` arity and parameter-type checking at `Expr::Call` via the `IgType` structural boundary. |
| `LAB-IGNITER-COMPILER-EFFECT-SUMMARY-CALL-CONTRACT-P7` | Characterized + regression-locked: `call_contract` laundering is closed by construction because v0 allows only literal `pure` callees. |
| `LAB-MACHINE-DURABLE-CAS-PG-EXACTLY-ONCE-P2` | Hardened/proved DB-native durable CAS: `effect_receipts(idempotency_key)` UNIQUE/PK, concurrent real-PG proof, DDL drift maps to `PermanentConfig`. |
| `LAB-MACHINE-WAL-FSYNC-NONSILENT-RECOVERY-P2` | Implemented explicit WAL durability policy and non-silent recovery report; boot fails closed on mid-stream corruption. |
| `LAB-IGNITER-WEB-LIVE-BIND-GATE-DECISION-READINESS-P35` | Gate decision only: public bind still HOLD; authority chain and P36-P39 future cards named. |

Remaining natural follow-ups are named in the row-level `Next safe slice`
cells. Do not dispatch `LAB-IGNITER-COMPILER-LOCK-DEFAULT-ENFORCE-P5` until
registry/signing/remote-source readiness creates enough pressure to flip the
default policy. Do not mix frame-ui into this foundation audit batch while its
separate agent is active.

## Latest Tail-Closure Wave

Dispatched and closed on 2026-06-28 to close the remaining audit tails before
widening into new foundation themes:

| Card | Row | Boundary |
|---|---|---|
| `LAB-IGNITER-COMPILER-RECORD-LITERAL-NONINLINE-FIELD-TYPING-P7` | A19 | Closed B-U3: non-inline record literal field typing via `IgType`; no Ruby/canon changes. |
| `LAB-IGNITER-COMPILER-CALL-CONTRACT-ARG-TYPING-P8` | A19 | Closed B-U2: literal `call_contract` argument typing via `IgType`; no dynamic dispatch/effect changes. P8a scalar alias fix (`String` = `Text`) also landed. |
| `LAB-IGNITER-WEB-LIVE-BIND-DRY-RUN-VERDICT-P36` | A10 | Closed report-only dry-run; public bind remains closed. |
| `LAB-IGNITER-WEB-INBOUND-SIGNED-PASSPORT-DURABLE-KEY-P37` | A10 | Closed dry-run host-verified signed-passport verifier backing; public bind remains closed. |
| `LAB-IGNITER-WEB-TLS-TERMINATED-UPSTREAM-RUNBOOK-P38` | A10 | Closed terminated-upstream operator contract; native TLS and public bind remain closed. |
| `LAB-MACHINE-RECEIPT-SEQID-ORDERING-READINESS-P3` | A21 | Closed readiness: adopt local `receipt_seq` tie-break; no TBackend adoption implementation. |
| `LAB-IGNITER-VM-SOURCE-RUN-REPL-READINESS-P1` | A23 | Closed readiness: REPL/source-run mostly exists; one-shot source-run remains. |

## Active Audit Wave

Dispatched on 2026-06-28 after the tail-closure wave:

| Card | Row | Boundary |
|---|---|---|
| `LAB-MACHINE-RECEIPT-SEQ-TIEBREAK-P4` | A21 | DB-free local receipt ordering repair: `(transaction_time, receipt_seq)`; not TBackend seq_id and not PG CAS. |
| `LAB-IGNITER-MACHINE-RUN-SOURCE-ONESHOT-P2` | A23 | Machine-owned one-shot source-run DX over `load_contract_source` + `dispatch`; no `igc run` unification. |
| `LAB-IGNITER-COMPILER-ARRAY-LITERAL-ELEMENT-TYPING-P9` | A19 | Compiler collection-element typing via `IgType`; no parser/SIR/VM/canon changes. |

## Maintenance Rule

When a card closes one of the rows above, update only:

- the row status/evidence here;
- the relevant package-local `IMPLEMENTED_SURFACE.md` if user-facing current
  truth changed;
- `current-waves-index.md` only if the wave map changed.

Do not create a second audit board.
