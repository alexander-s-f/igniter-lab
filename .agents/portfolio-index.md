# igniter-lab: Portfolio Index

**Maintained by:** Portfolio Architect Supervisor
**Last updated:** 2026-06-10 (LAB-FILTER-EVAL-P1: Filter predicate evaluation over mocked in-memory rows — LAB PROOF / QUERY SEMANTICS / IN-MEMORY MOCKED ROWS / NO DB; 50/50 PASS; 9 pure contracts (all CORE; no effect; no capability); v0 operators: eq/neq/contains/prefix; AND-only composition; Layer C FilterEvalSim proof-local Ruby evaluator (NOT production runtime); 5-row deterministic dataset; empty filter list → all rows; unknown field → no match (kind:"empty"); unknown op → kind:"query_error" (NOT "denied"); count==matched_rows.length invariant; BuildQueryPlanWithFilters.filters=Collection[FilterPredicate] in Rust SIR (LAB-TC-ARRAY-P2 record-field-context mechanism, 3rd confirmation); inline empty array → Collection[FilterPredicate] from record-field context; B1: VM has no iteration opcodes (Layer C correct boundary, not a workaround); B2: empty array field-context confirmed; B3: unknown field ≠ unknown op (must not collapse); B4: G1–G6 gate sequence orthogonal to filter evaluation; no DB/SQL/ORM/StorageCapability/production runtime; FEVAL-COMPILE 5/5|FEVAL-SHAPE 7/7|FEVAL-ARRAY 4/4|FEVAL-SEMANTICS 7/7|FEVAL-RESULT 6/6|FEVAL-VM 8/8|FEVAL-CLOSED 5/5|FEVAL-GAP 8/8; proof runner: igniter-view-engine/proofs/verify_lab_filter_eval_p1.rb; design doc: igniter-lab/lab-docs/lang/lab-query-filter-predicate-evaluation-over-mocked-rows-v0.md) | (LAB-VARIANT-VM-P1: Rust Lab VM variant/match lowering Path B — LAB VM LOWERING / PATH B / NO NEW OPCODES; 42/42 PASS; 10 sections; lowers variant_construct+match_node to existing VM opcodes in igniter-vm/src/compiler.rs; VVM-COMPILE: 7 fixtures (11–17) compile; VVM-CONSTRUCT: variant_construct→Record{__arm,__variant}+payload via OP_PUSH_RECORD sorted-keys; VVM-MATCH: unit arm selection via GET_FIELD("__arm")+EQ+JMP_UNLESS chain; VVM-BIND: payload field bindings into scoped temp regs, body refs via OP_LOAD_REG; VVM-WILDCARD: wildcard arm catches unlisted; VVM-FAILCLOSED: unknown arm→OP_UNSUPPORTED (error, not nil), malformed __arm→GET_FIELD error; VVM-TWONODES: two match nodes, independent subject registers, no collision; VVM-NESTED: nested match_expr (raw AST kind from annotate_expr_with_type) handled via "match_node"|"match_expr" Rust match union; VVM-EQUIV: ReconciliationOutcome 5 arms route to P4 KDR actions (accept/needs_human_review/retry/hold/hold); VVM-CLOSED: instructions.rs/vm.rs/value.rs closed—no OP_MATCH, no OP_PUSH_VARIANT, no Value::Variant; design: variant=Record(sorted keys); __arm=discriminant; compiler.rs-only change; match_expr alias covers nested arm body raw-AST form; has_wildcard=unwrap_or(false)→fail-closed default; 7 new fixtures: 11_vm_variant_construct_basic/12_vm_match_unit_arms/13_vm_match_payload_bindings/14_vm_match_wildcard/15_vm_match_two_nodes/16_vm_match_kdr_equivalence/17_vm_nested_match; proof runner igniter-view-engine/proofs/verify_lab_variant_vm_p1.rb; design doc igniter-lab/lab-docs/lang/lab-rust-variant-match-vm-lowering-path-b-v0.md; satisfies PROP-044-P7b gate; Outcome[T,E]/failure-taxonomy/canon all CLOSED) | (LAB-DEBUGGER-FEASIBILITY-P1: Igniter debugger & source-mapping feasibility report (out-of-track) — REPORT / FEASIBILITY / LAB-ONLY / NO IMPLEMENTATION; goal = interactive debugger as the instrument under a TEXTBOOK that teaches by showing execution across multiple abstraction levels (source→AST→fragment-classified→typed→SemanticIR→bytecode→live state→observations), the anti-black-box alternative to a REPL; VERDICT = FEASIBLE (high confidence, instrument + textbook); THESIS: Igniter is an honest layered IR BY DESIGN (Covenant: observation is typed, evidence chained, uncertainty non-discardable) → "dimensional learning" is architectural not aspirational; EXISTS TODAY: igniter-ide Tauri2+Svelte5 (monaco/d3/vis-network) with DebuggerPanel/ExecutionTracer(frame stepper)/TemporalTimeline(D3 playback)/ContractDAG/ObservationStream/ContractInspector + Rust bridge (load_contract/dispatch_traced/play_trace_playback/read_introspection_receipt/read_facts) per LAB-IDE-DEBUGGER-P1/P2 + LAB-TAURI-IVF-P3..P20 + LAB-IDE-VIEWER-P1; VM single dispatch loop + OP_EMIT_OBS observation sink + latency_us + temporal OP_LOAD_AS_OF audit trail; learning-by-contract curriculum lab-docs/tutorial (LAB-TUTORIAL-P1..P5); all 8 abstraction layers are REAL inspectable artifacts incl. fragment_class; TWO FOUNDATIONAL GAPS: G-SRCMAP (lexer captures line/col but PARSER DROPS it; Instruction={opcode,args} no provenance; NO bytecode→source map today; fix=additive node_id+span thread parse→SIR→bytecode + .sourcemap artifact) and G-TRACE (VM runs to completion, no step/snapshot/breakpoint; the *_trace_receipt.json files are RESULT receipts NOT execution traces; fix=record-only execute_traced → .trace.json, prove equivalence to untraced); both additive, single clean insertion points, low-medium risk; CAVEAT: dual toolchain — build source-map on the Rust VM SIR path first, parity to Ruby (same asymmetry theme as LAB-VARIANT-RUST-P1/PROP-044-P7-READINESS); synchronized multi-pane debugger joins everything on node_id (source span↔SIR node↔bytecode offset↔trace frame↔observations); proposed route (NONE authorized): keystone LAB-SRCMAP-P1 (node_id+span parse→SIR Rust-first + .sourcemap) → LAB-SRCMAP-P2 (bytecode spans) → LAB-VMTRACE-P1 (record-only trace, equivalence-proved) → LAB-IDE-STEP-P1 (synchronized panes) → LAB-TEXTBOOK-P1 (watchable lessons) → optional LAB-DEBUG-REVERSE-P1 (reverse/temporal scrubbing + line breakpoints); canon touched=NO, implementation authorized=NO; report lab-docs/ide/igniter-debugger-and-source-mapping-feasibility-report-v0.md) | (LAB-VARIANT-RUST-P1: Rust lab compiler variant/match front-end + SIR parity — LAB RUST PARITY / FRONT-END + SEMANTICIR / NO VM; 39/39 PASS; 8 sections; implements variant/match in igniter-compiler from lexer through SemanticIR emission producing structural SIR parity with Ruby PROP-044-P6; VRUST-LEX: FatArrow+variant+match keywords lexed (no OOF-G1); VRUST-PARSE: VariantDecl/VariantConstruct/MatchExpr in AST; VRUST-TYPE: VariantShapes registry, exhaustive match accepted, scope isolation; VRUST-OOF: OOF-KIND1..5 all fire correctly (non-exhaustive/unknown-arm/duplicate-arm/non-variant-subject/divergent-arm-types) + error fixtures blocked; VRUST-SIR: variant_declarations at top level + match_node with exhaustive/has_wildcard/subject_type/arm resolved_types; VRUST-PARITY: 8 structural keys match Ruby P6 SIR shape (variant_decl/match_node/pattern.arm+bindings+wildcard/arm resolved_type); VRUST-REG: 3 conformance fixtures unaffected; VRUST-CLOSED: igniter-vm/src/* untouched, no Value::Variant, no OP_MATCH, no OP_PUSH_VARIANT, no match_node lowering; design: annotated_expr flow (Option<Value> on TypedExpression/TypedDecl carries enriched SIR-ready JSON from TC to emitter, no new IR pass); VariantShapes=HashMap<variant→arm→field→type_ir>; match_expr→match_node rename in lower_annotated_expr; 10 fixtures (basic/unit-arm/wildcard/OOF-KIND1..5/scope-isolation/sir-parity); proof runner igniter-view-engine/proofs/verify_lab_variant_rust_p1.rb; design doc igniter-lab/lab-docs/lang/lab-rust-variant-match-front-end-and-sir-parity-v0.md; satisfies PROP-044-P7-READINESS precursor condition for P7b VM dispatch (Path B); VM/opcodes/bytecode/Outcome[T,E]/failure-taxonomy/Ruby-canon all CLOSED) | (LAB-EXECUTE-QUERY-P1: ExecuteQuery effect contract and StorageCapability injection proof — LAB PROOF / STAGE 2+ / MOCKED STORAGE EXECUTION / NO REAL DB; 57/57 PASS; 10 sections; proves first executable Stage 2+ query path: ExecuteQuery effect contract (Layer A+B compile; ESCAPE class; VM requires capability injection — correct enforcement boundary); 6-gate denial sequence (G1–G6) via Layer C ExecuteQuerySim with full QueryPlan + StorageCapability hashes; G4=row-limit clamp (not denial); G5→query_error (not denied); QueryExecutionReceipt 15-field invariants (cap_granted:false iff {denied,query_error}; rows_returned:0 when denied); BuildQueryPlanInline.filters typed Collection[FilterPredicate] in Rust SIR (LAB-TC-ARRAY-P2 record-field-context confirmed in EXECQ fixture); denial-as-data 10th proof (StorageCapability 5th domain); 5-kind KDR vocabulary proved; TBackend/TEMPORAL absent (orthogonal confirmed); write ops CLOSED in v0; two-fixture architecture (execute_query_capability.ig compile-only + execute_query_receipts.ig VM-executable 12 pure contracts); B3: deny_reason (message keyword); B4: read_file (read keyword); B5: TBackend absent; no DB/SQL/ORM/raise/persistence) | (PROP-044-P7-READINESS: VM variant/match dispatch readiness & risk map — GOVERNANCE / VM DISPATCH READINESS / NO IMPLEMENTATION; DECISION = HOLD P7 (VM dispatch); CORE FINDING: variant/match exists ONLY in the Ruby canon pipeline (PROP-044-P3 parser/P5 TypeChecker+OOF-KIND/P6 SIR emitter) — the ENTIRE Rust lab toolchain (igniter-compiler + igniter-vm, which is what every VM proof runs) has ZERO variant/match support at every layer: lexer KEYWORDS lacks variant/match (→OOF-G1), parser Expr enum has no Match node, typechecker has no variant/exhaustive/OOF-KIND, emitter emits no variant_declarations/variant_construct/match_node, VM Value enum has no Value::Variant (8 kinds), instructions.rs has no OP_MATCH (~34 ops), VM compiler.rs has no match_node lowering (fails closed on unknown nodes); so the Rust compiler REJECTS variant/match source before any node reaches the VM — "VM dispatch" is blocked behind a full Rust front-end re-implementation, NOT "add an opcode"; survey survey_variant_match_vm_readiness.rb 15/15 PASS grounds this (Rust→OOF-G1/no-SIR; Ruby parses variants; Rust source greps confirm absent surfaces; KDR P4 regression anchor green); PATH COMPARISON: Path A (native Value::Variant+opcodes — high VM surface/risk, true runtime identity) vs Path B RECOMMENDED (lower match_node→Record+if/else over OP_GET_FIELD/OP_EQ/OP_JMP_UNLESS/OP_PUSH_RECORD — NO new opcode, NO Value::Variant, compiler.rs-only, P4 ALREADY proved the lowered shape executes 46/46, low risk; removes string-dispatch fragility at SOURCE/typecheck layer where exhaustiveness+narrowing live, runtime stays tag== which is fine); design answers: vm_dispatch_ready=NO, recommended=Path B, new_opcodes=NO, Value::Variant=NO, match→ifelse=YES(proven), avoids ==/||-divergence for outcome routing (post-typecheck lowering, user writes match not ==) but does NOT fix it (STAB-P4 owns), requires Rust changes BOTH front-end+VM, Ruby changes=NO, authorizes failure-taxonomy PROP=NO, authorizes sealed Outcome[T,E]=NO, exhaustiveness=typecheck-only (VM trusts TC + lowers to FAIL-CLOSED default never silent Nil), arm-identity=compiler-owned; PRECURSOR ROUTE: PROP-044-P7a (Rust front-end variant/match + SIR PARITY with Ruby emitter, no VM — gate=P7a-PARITY Rust SIR≡Ruby SIR + OOF-KIND parity) → then PROP-044-P7b (VM dispatch Path B — gate=P7b-EQUIV variant Outcome routing yields SAME terminal actions as P4 KDR RouteReceipt); failure-taxonomy proposal-planning WAITS until ≥P7a lands; regression KDR P2 54/54 + P4 46/46 + P3 43/43 green, git only-new-files; 15/15 PASS) | (LAB-TC-ARRAY-P2: Rust TypeChecker array-literal-in-record-field-context proof — LAB PROOF / RUST TYPECHECKER / COLLECTION CONTEXT PROPAGATION; closes the non-blocking gap left by LAB-TC-ARRAY-P1; an intermediate `compute filters = [...]` that feeds a typed record field — `compute plan = {kind:"select",...,filters:filters,...}` / `output plan : QueryPlan` where QueryPlan.filters : Collection[FilterPredicate] — now types `filters` as Collection[FilterPredicate] (was Unknown in P1, data-preserved-but-type-lost); impl in typechecker.rs = an order-independent prescan contributing record-field hints to the SAME collection_output_hints map P1 introduced: for each RecordLiteral compute whose declared output type is a named record (output_type_hints), each field bound to a bare Ref whose record-type-declared field type is Collection[T] feeds element hint T to the referenced compute node (entry().or_insert — P1 output-context hints win); the compute-phase upgrade block is UNCHANGED (consults collection_output_hints); LOCAL single-hop syntactic Ref-field lookup — NO global/Hindley-Milner inference, NO unification, NO retroactive symbol mutation (the referenced `filters` compute is processed before the enclosing `plan` record literal in dependency order, so the array-literal node is upgraded in place); empty intermediate array typed from field context IFF expected field type known; bad/mixed record elements still fail closed (OOF-TY0) via check_array_literal_shape; P1 output-context typing + free-standing-Unknown preserved; Collection[FilterPredicate] survives into SIR type_tag (filters compute node); VM round-trips plan.filters (2 records / empty []); no new grammar; touches Ruby canon=NO (parity anchor); opens StorageCapability execution=NO; opens DB/SQL/ORM/runtime/storage=NO; PROP-046 unchanged; remaining edges deferred to optional v1 collection-inference (inline-in-field literal not via Ref, multi-hop Ref chains, conflicting hints first-wins); 19/19 PASS; regressions clean — P1 27/27, P3 44/44, VM-MAP 48/48, P13 47/47, record-vm construction/field-access/nested 43/42/49; next route = LAB-EXECUTE-QUERY-P1 (Stage 2+ capability-injection) — P1+P2 give sufficient inline-filter expressivity) | (LAB-EPISTEMIC-OUTCOME-P4: VM KDR ReconciliationReceipt flow proof — LAB PROOF / VM KDR RECEIPT FLOW / NO OUTCOME VARIANT; proves a KDR ReconciliationReceipt (11 fields: kind/request_id/resource/idempotency_key/observed_at/evidence_kind/compensation/attempt:Integer/budget_remaining:Integer/detail/metadata:Map) is PRODUCED, CARRIED, INSPECTED, ROUTED through the lab Rust VM as record data — P3 transition guards executed IN-VM as nested if/else; attempt typed Integer (numeric w/ budget guard, no String→Int coercion, Sidekiq precedent); 5 contracts (ReconcileFromLostAck producer pulls request_id/resource from env.metadata + preserves idempotency_key; MakeReceipt; RouteReceipt heart-router; RouteEnvelope; ReceiptInspector map-chain); VM-PROVED all P3 transitions: confirmed_succeeded+real|human→accept, +model→needs_human_review (evidence_kind LOAD-BEARING at runtime — No-Upward-Coercion executable), confirmed_failed+idem→retry(P16), +named-comp→compensate(P17), +neither→fail, still_unknown/reconciliation_error+budget→reconcile_again|+no-budget→hold, partially_confirmed→reconcile_remainder, reconciliation_denied/unknown-kind→hold(fail-closed), raw unknown/timed_out/partial→reconcile_required ONLY (NO VM branch to terminal success/failure); REAL Ruby/Rust DIVERGENCE surfaced+flagged for STAB-P4: production Ruby TypeChecker rejects String `==`/`||` (routers BLOCKED in Layer A) while Rust compiler accepts `==` (fixture avoids `||` by nesting) and Rust VM EXECUTES routing → routing is Rust-VM-only proof, not dual-impl (NOT resolved here); Layer A=Ruby TC proves receipt type-shape+producers accepted, Layer B=Rust compiler+VM proves routing execution; uses variant/match runtime=NO; implements sealed Outcome[T,E]=NO; opens storage/DB/network/runtime I/O=NO; authorizes failure-taxonomy PROP=NO; regression P2 54/54 + P3 43/43 green, git only-new-files; next=PROP-044-P7-READINESS (VM variant/match dispatch sequencing + risk map — true gate for sealed Outcome[T,E], also closes the ==-divergence), then only after: failure-taxonomy proposal-planning card; 46/46 PASS) | (LAB-TC-ARRAY-P1: Rust TypeChecker array-literal-in-Collection-context proof — LAB PROOF / RUST TYPECHECKER / NO STORAGE RUNTIME; closes LAB-QUERY-P3 finding B1 (Rust array_literal catch-all gap); `compute filters = [{field,op,value},{...}]` and `[f1,f2]` now type as Collection[FilterPredicate] in a declared `output x : Collection[T]` position; behavior is CONTEXTUAL — mirrors the RecordLiteral nominal upgrade (LAB-RACK-P13): an array literal is checked element-by-element against T and upgraded to Collection[T]; impl in typechecker.rs = collection_output_hints prescan (output decls with Collection annotation → element type IR) + explicit Expr::ArrayLiteral arm in infer_expr (types items for deps, resolves Unknown free-standing — removes OOF-TY0 "Unsupported expression kind: array_literal") + contextual upgrade block in compute phase + check_array_literal_shape helper (RecordLiteral element → check_record_literal_shape; Ref/Literal element → element type-name match; record-literal-vs-scalar → fail closed); empty array accepted ONLY with contextual type (0 elements → upgrade); free-standing array literal (no Collection output hint) stays Unknown (no fabricated type); missing/extra/wrong-typed record fields + mixed element shapes fail closed (OOF-TY0); Collection[FilterPredicate] survives into SIR type_tag (compute node + output port); VM round-trips inline-constructed collection (InlineFilterCollection→2 records, EmptyFilterCollection→[], BuildInlineSelectPlan→plan.filters 2-elem); Layer B (Rust compiler+VM) primary + Layer A (Ruby TC) parity anchor; no new grammar; touches Ruby canon=NO; opens DB/SQL/ORM/runtime/storage=NO; opens StorageCapability execution=NO; PROP-046 semantics unchanged; P3 workaround CLOSED; open follow-up (non-blocking) = record-field-position contextual typing for nested array literals (intermediate filters feeding a record field stays Unknown, data preserved); 27/27 PASS; regressions clean — P3 44/44, P13 47/47, VM-MAP 48/48, record-vm construction/field-access/nested 43/42/49; next route = LAB-EXECUTE-QUERY-P1 (Stage 2+ capability-injection) now unblocked OR record-field collection-typing follow-up if broader inference wanted first) | (LAB-EPISTEMIC-OUTCOME-P3: reconciliation-consumer boundary for unknown state — DESIGN NOTE / LAB-ONLY / NO IMPLEMENTATION AUTHORITY; defines how a downstream DAG node may consume unknown_external_state without coercing it into success/failure/retry/compensation; spine: reconciliation IS the explicit typed conversion the Covenant No-Upward-Coercion rule requires (unknown=low certainty → confirmed=observed); three state bands (effect kinds | reconciliation lifecycle reconcile_required/confirmed_succeeded/confirmed_failed/still_unknown/partially_confirmed/reconciliation_denied/reconciliation_error | terminal actions accept/deny/retry/compensate/fail/cancel/record/hold); allowed: unknown/timed_out/partial→reconcile_required→6 results; confirmed_succeeded→accept⇐real|human(P13); confirmed_failed→retry⇐idempotency(P16)|compensate⇐named(P17)|fail; still_unknown→reconcile⇐budget|hold; forbidden: unknown→succeeded/failed/accept/retry/compensate(direct), timed_out→failed(P15), reconcile_required→accept, model→real-without-conversion(P13); min ReconciliationReceipt KDR = kind+request_id+resource(required)+idempotency_key/observed_at/evidence_kind/compensation/attempt/metadata(typed,never-dropped); evidence_kind load-bearing (blocks model→real upgrade → needs_human_review); KDR-now/Outcome-later bridge (forbidden transitions rejected-by-convention now → unrepresentable-type-error later once VM variant dispatch proved); requires variant/match runtime=NO; authorizes Outcome[T,E] impl=NO; opens storage/IO=NO; proof-local pure-Ruby state machine verify_reconciliation_state_machine.rb 43/43 PASS (design evidence, not runtime); existing proofs unchanged (git: only new files); next=LAB-EPISTEMIC-OUTCOME-P4 executable reconciliation state-machine + parallel governance probe on VM variant/match dispatch sequencing (the real gate for Outcome[T,E]); failure-taxonomy PROP deferred until that gate understood) | (LAB-STORAGE-CAPABILITY-P2: IO.StorageCapability mocked execution boundary proof — 51/51 PASS; 6-gate denial sequence (G1–G6); G4=row-limit clamp (not denial); G5→query_error (not denied); QueryExecutionReceipt 15-field evidence record; denial-as-data 9th proof/5th domain; ESCAPE class enforcement confirmed (passport gap = correct behavior); two-fixture architecture (effect+pure contract lab separation); KDR 5th domain (5 kinds: rows/empty/denied/query_error/system_error); B2: Rust classifier effect name closed vocab {read_file,read_json,read,write_file,write_json,write}; B3/B4: read/message are parser keywords; no DB/SQL/ORM/raise/persistence) | (PROP-046-P1: IO.StorageCapability boundary proposal — PROPOSAL AUTHORING ONLY; 14 sections; 15 decisions locked (D1..D15); core formula: QueryPlan=pure CORE/StorageCapability=ESCAPE authority gate/QueryResult=typed KDR; StorageCapability≠DB/ORM/SQL/TBackend; 6-gate sequence locked; QueryExecutionReceipt 15-field schema locked; ExecuteQuery ESCAPE→STORAGE Stage 2+ (ch4 amendment required); write ops deferred; LAB-STORAGE-CAPABILITY-P2 authorized) | (LAB-EPISTEMIC-OUTCOME-P2: unknown-state KDR convention proof — LAB PROOF / KDR CONVENTION / NO IMPLEMENTATION AUTHORITY; domain: storage write commit-ack loss; OutcomeEnvelope KDR (kind:String + idempotency_key:String + metadata:Map[String,String]); 7 kinds (succeeded/denied/timed_out/unknown_external_state/partial/cancelled/compensated); 9 contracts; Layer A Ruby TC 9/9 accepted + Layer B Rust VM (7 kinds executed) + Layer C consumer sim ReconciliationRouter; PRIMARY: CommitWriteLostAck → unknown_external_state (NOT failed/system_error/upstream_unavailable), idempotency_key + reconcile metadata preserved through VM, StorageOutcomeMapper lost-ack → unknown not system_error; invariants: timeout≠failure (P15), retry gated on explicit idempotency (P16 — no key⇒no retry, denied never retried), denied≠unknown (not-sent vs sent-unconfirmed), partial≠unknown, reconciliation is data not raise; KDR sufficient as v0 = YES; proves enforced Outcome[T,E] = NO (no variant/match); authorizes PROP impl = NO; storage/network/runtime I/O opens = NO; existing Query/Rack/Sidekiq proofs not changed (git: only new files; P14 58/60 = pre-existing map_get VM-gap); next = LAB-EPISTEMIC-OUTCOME-P3 reconciliation-consumer design note; 54/54 PASS) | (LAB-EPISTEMIC-OUTCOME-P1: epistemic outcome model + unknown-state boundary — GOVERNANCE/DESIGN/LAB-ONLY; finding: canon already declares the model (Ch12 7 outcomes incl. unknown_external_state ch12:131 + Covenant P11/P13/P15/P16/P17 + Epistemic State Machine/No-Upward-Coercion) but it is unimplemented (UnknownExternalOutcome/ObservedFailure named-not-spec'd; P15=planned PROP covenant:680) AND lab proofs flatten it (QueryResult system_error folds timeout/lost-conn; ContractResult upstream_unavailable=budget-exhaustion is unknown→failure coercion; storage commit-ack unmodeled); three orthogonal axes (Outcome=Ch12/UnknownExternalOutcome | Observation=Obs[kind,T] P13 | Estimation=~T/Uncertain P11/PROP-026 — probabilistic is SEPARATE track); Result/Option insufficient (closed-world only); KDR kind:String = sufficient v0 convention; variant Outcome[T,E] = enforced model, typecheck-expressible via PROP-044-P3/P5 (grammar blocker LIFTED at TC) but runtime-blocked (match VM unproved); blocks storage WRITE + effectful network exec (P15+P16); does NOT retroactively change Query/Rack/Sidekiq proofs (reclassified epistemically-incomplete); no impl/types/parser/runtime/PROP; next = LAB-EPISTEMIC-OUTCOME-P2 unknown-state KDR convention proof → reconciliation note → failure-taxonomy PROP on PROP-044 substrate; STAB-P4 flag: P15→PROP-035 number collision) | (PROP-044-P6: variant+match SemanticIR emitter — semantic_variant_declarations (variant_env→variant_decl array); semantic_variant_construct (typed_fields→fields rename; arm/variant/resolved_type); semantic_match_node (match_expr→match_node rename; subject/subject_type/arms/exhaustive/has_wildcard/resolved_type); semantic_match_arm (pattern/body/resolved_type); dispatch wired into semantic_expr; variant_declarations emitted at top level of semantic_ir_program; OOF-KIND1..5 programs → nil semantic_ir (emit_typed guard); 50/50 PASS; P5 75/75 + P3 50/50 + OOF-R3 33/33 regressions clean) | (LAB-QUERY-P3: QueryPlan v1 nested records + Collection[FilterPredicate] proof — 8 contracts; 7 types (QuerySource/Projection/FilterPredicate/OrderBy/QueryPlan/QueryResult/StorageDenied); Layer A+B (Ruby TC + Rust VM); chained field access plan.source.table (two-hop OP_GET_FIELD); C1 chain (map_get+or_else) on richer QueryPlan; denial-as-data kind:"denied" 8th proof; Rust typechecker array_literal gap documented; 44/44 PASS) | (PROP-044-P5: variant+match TypeChecker implementation — classifier bridge (variant_declarations() method + variant_declarations key in classified_program); @variant_shapes 3-level store (variant→arm→field→type_ir); variant_shapes() builder; find_variant_for_arm(); infer_variant_construct; infer_match_expr (full + degraded mode); unify_match_arm_types; OOF-KIND1..5 ACTIVE; variant_env propagated to typed_program; 75/75 PASS; all regressions clean 55+33+100+50) | (PROP-045-P2: intent descriptor parser + metadata propagation proof — ParsedProgram#to_h intent_text fix; keyword added to KEYWORDS; module-level + contract-level parse; classifier OOF-INTENT3; typechecker pass-through; SemanticIR intent_text emission; orthogonal to profile_binding; 53/53 PASS; 15 decisions locked) | (PROP-044-P4: variant+match TypeChecker design — @variant_shapes 3-level store; variant_shapes() builder; classifier bridge (variant_declarations() + classified_program key); infer_variant_construct pseudocode; infer_match_expr pseudocode; unify_match_arm_types; OOF-KIND1..5 formal trigger+message definitions; per-arm narrowed scopes; exhaustiveness algorithm; degraded mode; 16 design decisions locked; proof requirements 15 groups ~75-80 checks; P5 implementation requires explicit auth) | (PROP-044-P3: variant+match parser implementation — fat_arrow lexer; variant/match keywords; parse_variant_decl/parse_variant_arm/parse_variant_construct/parse_match_expr/parse_match_arm/parse_match_pattern; ParsedProgram variants field + grammar_version=variant-v0; 50/50 PASS; all prior proofs clean) | (LAB-STORAGE-CAPABILITY-P1: IO.StorageCapability boundary design — allowed_sources (fail-closed); allowed_ops (["read"] v0); row_limit clamp; allow_include_all gate; read_allowed/write_allowed split; 6-gate denial-as-data sequence; QueryExecutionReceipt shape; ExecuteQuery ESCAPE→STORAGE fragment; OOF-STORE1..5 candidates; 10 decisions locked; DB/SQL/ORM/migrations/transactions permanently closed) | (PROP-045-P1: Source-level intent descriptor — keyword `intent`; bounded plain string; module+contract placement; preserved in contract_ir as intent_text; not in behavior digest; not capability/policy/runtime; OOF-INTENT1..4 reserved; CR-003 orthogonal; P2 parser impl requires explicit auth; 20 decisions locked) | (LAB-QUERY-P2: QueryPlan pure builder proof — 6 contracts (BuildQuerySource/BuildSelectQuery/BuildFilteredQuery/QueryResultDenied/QueryMetadataReader/QueryMapper); 7 types (QuerySource/Projection/FilterPredicate/OrderBy/QueryPlan/QueryResult/StorageDenied); denial-as-data QueryResult{kind:"denied"}; C1 chain in 4th domain; all CORE fragment; 42/42 PASS) | (PROP-044-P2: variant+match grammar design — VariantDecl EBNF; MatchExpr EBNF; VariantConstruct expression; type narrowing rules; OOF-KIND1..5 formal definitions; SemanticIR shapes (variant_decl/variant_construct/match_node); parser+typechecker extension points; 15 design decisions locked; P3 parser impl requires explicit auth) | (LAB-QUERY-P1: Query/Arel-like data access pressure boundary — QueryPlan/QueryResult/FilterPredicate/OrderBy/QuerySource typed Records; ORM permanently closed; joins/aggregates deferred; StorageCapability boundary defined; denial-as-data 5-kind QueryResult; CORE fragment class for plan-building; LAB-QUERY-P2 next) | (LAB-COMPILER-LIVENESS-P6: Body-decl recovery generalised — 11 .ok() arms → parse_body_decl_with_recovery; window/loop/for deferred to P7; decreases proved always-Ok; 54/54 PASS) | (PROP-044-P1: Kind-discriminated outcome convention and sum type requirements — convention doc authored; KDR pattern defined; denial-as-data invariant stated; grammar gap enumerated (variant+match+narrowing); OOF-KIND1..4 namespace reserved; production implementation blocked; grammar proposal P2 authorized) | (LAB-COMPILER-LIVENESS-P5: Parser hang class closed — peek_type EOF fix; parse_body_decl_with_recovery; parse_type_decl field recovery; BoundedCommand timeout kill; 46/46 PASS) | (LAB-RESULT-ENVELOPE-P2: Third-domain kind-discriminant pressure — validation/form-processing domain; ValidationResult 4-kind (valid/invalid/unauthorized/system_error); no HTTP status, no job fields; denial-as-data 7th proof; Map[String,String] metadata 3rd context; kind-discriminant generalised across 3 domains; PROP-044 unblocked for proposal-authoring; 50/50 PASS) | (LAB-CONCURRENCY-P4: Minimal scheduler substrate contract design-locked; five-phase model; 9 invariants SI-1..SI-9) | (LAB-VM-MAP-P1: VM runtime map_get/map_has_key OP_CALL handlers; or_else pre-existing; Value::Record = Map runtime; compiler input field access fix; Rack P14 10/10 gap closed; 48/48 PASS) | (LAB-RESULT-ENVELOPE-P1: Governance taxonomy — 5 reusable patterns confirmed; next route = LAB-VM-MAP-P1 + LAB-RESULT-ENVELOPE-P2)
**Scope:** Cross-repo state map for igniter-lab ↔ igniter-lang

---

## Canon Boundary Rules (igniter-lang)

| Rule | Statement | Adopted |
|------|-----------|---------|
| CR-001 | Canon type opacity: IO.* types are opaque identifiers; schema is lab-only | 2026-06-07 |
| CR-002 | Lab diagnostic boundary: E-NET-* codes are lab-local; OOF promotion requires PROP+grammar review | 2026-06-07 |
| CR-003 | Profile binding is intent record only — not validated authority until PROP-040 OOF-M7/M8 active | 2026-06-07 (closed by PROP-040) |

---

## Tracks and Status

### IO.NetworkCapability

| Artifact | Repo | Status | Checks |
|---|---|---|---|
| LAB-STDLIB-NET-P2 (schema, delegation algebra) | igniter-lab | ✅ DONE | 53/53 |
| LAB-STDLIB-NET-P3 (FFI surface, stub mode) | igniter-lab | ✅ DONE | 61/61 |
| LAB-STDLIB-NET-P4 (compiler escape classification, E-NET-* codes) | igniter-lab | ✅ DONE | 42/42 |
| LAB-STDLIB-NET-P5 (hardening: glob, chains, bind-address, wildcard) | igniter-lab | ✅ DONE | 44/44 |
| LAB-STDLIB-NET-P6 (dead grant, compose bind_address) | igniter-lab | ✅ DONE | ~36/36 |
| LAB-STDLIB-NET-P6/HTTP (HTTP-client boundary — typed HttpRequest/Response records, capability policy, mocked transport, telemetry redaction, error taxonomy; Category: lang, Track: lab-network-http-client-request-response-boundary-proof-v0) | igniter-lab | ✅ DONE | 48/48 |
| LAB-STDLIB-NET-P7 (HTTP boundary Map alignment — Map[String,String] headers; map_get/or_else/has_key type rules; OOF-MAP1/2/3; redaction preserves Map shape; policy unchanged; P6 regression green; Category: lang, Track: lab-network-http-boundary-record-map-alignment-v0) | igniter-lab | ✅ DONE | 55/55 |
| LAB-STDLIB-NET-P8 (HTTP error result + retry envelope — HttpResult ok/denied/error; RetryPolicy 5xx/4xx/denial; RetrySimulatorP8 BudgetedLocalLoop analog; capability denial as data; Map headers; E-HTTP-SERVER-ERROR/CLIENT-ERROR; Category: lang, Track: lab-network-http-error-result-and-retry-envelope-proof-v0) | igniter-lab | ✅ DONE | 50/50 |
| LAB-STDLIB-NET-P9 (HTTP upstream call contract composition — ContractResult typed domain envelope; ItemRequestBuilderP9→mocked boundary→HttpResult→DomainResponseMapperP9; Rack single-call + Sidekiq retry; capability denial as typed branch; upstream_unavailable on budget exhaustion; call_contract proof-local; Category: lang, Track: lab-network-http-upstream-call-contract-composition-proof-v0) | igniter-lab | ✅ DONE | 55/55 |
| PROP-035: capability/effect_binding grammar + OOF-M2/M4/M5 | igniter-lang | ✅ experiment-pass | 64/64 |
| `lab-docs/lang/lab-igniter-lang-io-capability-grammar-v0.md` | igniter-lab | ✅ bridge doc | — |

**Boundary:** Canon grammar names IO types as opaque identifiers (CR-001). Schema, delegation
algebra, FFI, E-NET-* codes remain lab-only. Runtime injection is Phase 2.
HTTP-client boundary (P6/HTTP): typed HttpRequest/Response records + capability policy + mocked transport
+ telemetry redaction proved (48/48). Real network I/O, DNS, TLS, and accept-loop startup remain closed.
Map alignment (P7): Map[String,String] headers proved for both record shapes; map_get/or_else typechain
clean; redaction preserves Map shape; policy is header-agnostic; 55/55 PASS.
PROP-043-P5 production Map with Record/Map bridge landed 2026-06-09 (55/55); P7 uses same proof-local architecture.
Error result + retry envelope (P8): HttpResult typed envelope (ok/denied/error discriminant); RetryPolicy
5xx→retry/4xx→no retry/denial→no retry; RetrySimulatorP8 BudgetedLocalLoop analog (no scheduler/clock);
capability denial as typed data through full envelope; 50/50 PASS.
Upstream call contract composition (P9): ContractResult typed domain envelope (found/created/not_found/
upstream_error/capability_denied/upstream_unavailable); Rack single-call + Sidekiq retry scenarios;
DomainResponseMapper shields domain code from transport internals; call_contract proof-local; 55/55 PASS.

### Profile System (PROP-033 / PROP-040)

| Artifact | Repo | Status | Checks |
|---|---|---|---|
| PROP-033: `via <profile>` binding on contract declarations | igniter-lang | ✅ experiment-pass | 52/52 |
| PROP-040: module-level `profile <name> { authority: <modifier> }` declarations | igniter-lang | ✅ experiment-pass | 63/63 |
| OOF-M7 (modifier below profile authority) / OOF-M8 (unknown profile) | igniter-lang | ✅ active in classifier | — |
| CR-003 closed by PROP-040 | igniter-lang | ✅ | — |

**Profile chain:** `profile_binding` (PROP-033) + `profile_authority` (PROP-040) propagate through
all four pipeline stages (parser → classifier → typechecker → SemanticIR). Via references
to undeclared profiles now trigger OOF-M8 at classify time.

### Contract Modifiers (PROP-031 / PROP-035)

| Artifact | Repo | Status |
|---|---|---|
| PROP-031: pure/observed/effect/privileged/irreversible | igniter-lang | ✅ experiment-pass |
| PROP-035: Effect Surface (capability/effect_binding, OOF-M2/M4/M5) | igniter-lang | ✅ experiment-pass |

### Assumptions Block (PROP-032)

| Artifact | Repo | Status |
|---|---|---|
| PROP-032: `assumptions {}` + `uses assumptions NAME` | igniter-lang | ✅ experiment-pass (bounded compiler surface) |

### Text / String Core (igniter-string-core-units-and-pure-stdlib-boundary-v0)

| Artifact | Repo | Status |
|---|---|---|
| Track doc | igniter-lang | ✅ experiment-pass — compiler surface 2026-06-08 |
| `Text` canonical type | igniter-lang | ✅ TypeChecker + ch3/ch2/ch8 reconciled |
| `stdlib.text.*` (14 ops) | igniter-lang | ✅ experiment-pass — 60/60 PASS |
| `source/string_extension.ig` | igniter-lang | ✅ superseded → `TextWorkflow`; old `StringWorkflow` legacy/held |
| Lab STR-CORE Rust symmetry | igniter-lab | ✅ closed 2026-06-08 — verify_str_core.rb 29/29 PASS (P2: concat disambiguated) |
| Lab STR-CORE-P3 value-semantics proof (bounds, UTF-8, UAX #29) | igniter-lab | ✅ closed 2026-06-08 — verify_str_value_semantics.rb 33/33 PASS (compile-time; runtime-gated gaps documented) |
| LAB-STR-UNICODE-P1 Unicode policy design | igniter-lab | ✅ design-locked 2026-06-08 — UTF-8 validity, UAX #29, no normalization, bounds clamp, grapheme receipt design |
| LAB-STR-UNICODE-P2 Unicode VM runtime ops | igniter-lab | ✅ closed 2026-06-08 — 8 functional ops (rune_length, grapheme_length, byte/rune/grapheme_slice, ends_with, replace, replace_all) + qualified aliases + split/replace empty-input guards; unicode-segmentation = "1.11" (lock: 1.13.3); verify_unicode_text_runtime.rb 43/43 PASS |
| LAB-STR-UNICODE-P3 handler hygiene + receipt | igniter-lab | ✅ closed 2026-06-08 — bare `split` guard aligned (P3 hygiene, no bypass via legacy name); unicode_runtime_receipt.json emitted (lab-only-evidence); 41/41 PASS |

**Formula:** `Text` is canonical contract type for text values. `String` literal compat via v0 rule only.
`stdlib.text.*` is experiment-pass compiler surface. Runtime Unicode/value semantics proven in lab VM.
Handler-policy consistency proven (bare and qualified split/replace both fail-closed on empty input).
Stable public API and runtime-execution gate remain closed.

**v0 surface (14 ops):** `concat`, `trim`, `contains`, `starts_with`, `ends_with`, `split`, `replace`, `replace_all`,
`byte_length`, `rune_length`, `grapheme_length`, `byte_slice`, `rune_slice`, `grapheme_slice`

**SemanticIR:** `kind: "call"`, `fn: "stdlib.text.*"`; no new IR kind needed (consistent with `stdlib.integer.*`)

**Closed:** runtime execution, bounds policy, locale case folding, regex, tokenizer,
TextEngine, streaming text, method syntax forms, stable public stdlib.text API.

**Track doc:** `igniter-lang/.agents/work/tracks/string-core-units-pure-stdlib-boundary-v0.md`

### Managed Recursion and Loop Classes (PROP-039)

| Artifact | Repo | Status |
|---|---|---|
| PROP-039: loop-class vocabulary + recursion design | igniter-lang | ✅ accepted; Gates 1+3+4+5+6+7+8 closed; Gate 5 recur() closed |
| FiniteLoop / BudgetedLocalLoop / StructuralRecursion / FuelBoundedRecursion | igniter-lang | ✅ experiment-pass compiler surface |
| OOF-L1/L5/L7/L8 / OOF-R1/R2/R4/R5/R6/R7 | igniter-lang | ✅ experiment-pass — active in TypeChecker/Classifier |
| OOF-L2/L3/L4 | igniter-lang | candidates only — not yet proven |
| OOF-R3 | igniter-lang | ✅ experiment-pass — OOF-R3 gate closed 2026-06-08; oof_r3_syntactic_variant_decrease_proof 33/33 |
| OOF-R3 Lab Rust symmetry | igniter-lab | ✅ closed 2026-06-08 — classifier.rs + typechecker.rs + emitter.rs; verify_oof_r3.rb 34/34 |
| OOF-R8 (missing size_relation) / OOF-R9 (call-site mismatch) | igniter-lang | ✅ experiment-pass — PROP-041-P3 proof-local gate 2026-06-08; prop041_structural_size_relation_proof 48/48 |
| PROP-041 T2 production (structural_size_v1 SemanticIR) | igniter-lang | ✅ PROP-041-P7 production — verify_prop041_t2_production.rb 48/48; verify_oof_r3.rb 33/33 |
| LAB-TERM-T2-P1 Rust symmetry | igniter-lab | ✅ closed 2026-06-08 — parser.rs + classifier.rs + typechecker.rs + emitter.rs; verify_t2_structural_size_relation.rb 52/52 PASS |
| LAB-TERM-T2-P2 OOF-R9 edge hardening | igniter-lab | ✅ closed 2026-06-08 — IfExpr fix; multi-recur/branch/nested-arith; verify_t2_oof_r9_edge_cases.rb 21/21 PASS |
| PROP-042-P1 T3 numeric measure proposal | igniter-lang | ✅ proposal authored 2026-06-09 — grammar + builtins + OOF-R10/R11 + SemanticIR + call-site obligation + P2 fixture matrix |
| PROP-042-P2 T3 proof-local experiment | igniter-lang | ✅ CLOSED 2026-06-09 — T3Pipeline + T3TypeChecker + T3Emitter; OOF-R10/R11 candidates proven; 36/36 PASS |
| PROP-042-P3 T3 acceptance decision | igniter-lang | ✅ CLOSED 2026-06-09 — P2 accepted; OOF-R10/R11 → experiment-pass; P4 production-edit planning authorized |
| PROP-042-P4 T3 production-edit planning | igniter-lang | ✅ CLOSED 2026-06-09 — exact +112-line plan; classifier no-change; OOF-R9 confirmed production-safe; P5 authorized |
| PROP-042-P5 T3 production implementation | igniter-lang | ✅ CLOSED 2026-06-09 — parser.rb + typechecker.rb + semanticir_emitter.rb; numeric_measure_v0 live; 45/45 PASS; T1/T2/R3 regressions clean; LAB-T3-P1 unblocked |
| LAB-T3-P1 Rust T3 numeric measure symmetry | igniter-lab | ✅ CLOSED 2026-06-09 — parser.rs + typechecker.rs + emitter.rs; OOF-P1 suppression via RefCell<T3Context>; verify_t3_numeric_measure.rb 45/45; T2/R9/R3/G5 regressions clean |
| ServiceLoop | → PROP-037 exclusive | excluded from PROP-039 |
| Parser / TypeChecker / SemanticIR | igniter-lang | ✅ experiment-pass compiler surface |
| Runtime / recursive execution / termination proof / VM stack / TCO | igniter-lang | **closed** — separate authorization required |

**Boundary:** Lab/Rust implementations are conformance consumers of canon proofs, not language authority.
Runtime execution, `igc run`, `.igbin`, RuntimeSmoke, and public/stable/production remain closed.

---

### External Progression / Service Liveness (PROP-037)

| Artifact | Repo | Status |
|---|---|---|
| PROP-037: Progression, ProgressionSource, ProgressionEvent | igniter-lang | accepted; proposal-only |
| clock.every, tick.time bindings | igniter-lang | PROP-037 scope |
| OOF-SL* codes | igniter-lang | PROP-037 companion territory |

### HTTP-Types / Rack (Lab only)

| Artifact | Repo | Status | Checks |
|---|---|---|---|
| LAB-LANG-HTTP-TYPES-P1 (ContractRef, middleware compose, IgniterFailure) | igniter-lab | ✅ DONE | ~41/41 |
| LAB-RACK-P2 (HttpRequest/Response Records, RackEnvAdapter, RackTupleAdapter, HandlerContract, static middleware pipeline, typed failures, closed-surface) | igniter-lab | ✅ DONE | 46/46 |
| LAB-RACK-P3 (ContractRef VM dispatch preflight — precise gap map at each compiler/VM layer) | igniter-lab | ✅ DONE | 25/25 |
| LAB-RACK-P4 (static route dispatch — 5-route data-plane table + :id param extraction; stdlib.text.* VM gap found) | igniter-lab | ✅ DONE | 27/27 |
| LAB-RACK-P5 (VM stdlib.text.* alignment — 3 OP_CALL cases added; 5-route dispatch + param extraction execute end-to-end on VM) | igniter-lab | ✅ DONE | 20/20 |
| LAB-RACK-P6 (TypeChecker == and < alignment — idiomatic equality in route dispatch; exact match via path=="/" + method=="GET") | igniter-lab | ✅ DONE | 32/32 |
| LAB-RACK-P7 (VM named entrypoint selector — `--entry <name>` CLI flag; default contracts[0] preserved; unknown entry fails closed) | igniter-lab | ✅ DONE | 28/28 |
| LAB-RACK-P8 (ContractRef dispatch boundary preflight — design locked: explicit `call_contract` stdlib op, dispatch table, depth ≤ 8, pure-callee-only in v0) | igniter-lab | ✅ DONE — design | — |
| LAB-RACK-P9 (explicit named user-contract dispatch via `call_contract` — DispatchEntry, cycle detection, MAX_CALL_DEPTH=8, pure-callee-only, TypeChecker OOF-P1/Unknown fixes) | igniter-lab | ✅ DONE | 60/60 |
| LAB-RACK-P10 (call_contract output type verification design preflight — SemanticIR metadata confirmed, literal/dynamic distinction confirmed, module registry pattern viable, not ContractRef) | igniter-lab | ✅ DONE — design | 39/39 |
| LAB-RACK-P11 (call_contract TypeChecker literal callee resolution — build_contract_registry, two-tier policy, Tier 1 resolves output type, OOF-TY0 for unknown/effect/arity/self-recursion literal callees) | igniter-lab | ✅ DONE | 47/47 |
| LAB-RACK-P12 (typed response single-output dispatch — RackResponse type, handler RecordLiteral support, Tier 1 resolves dispatcher compute to RackResponse, Tier 2 stays Unknown) | igniter-lab | ✅ DONE | 45/45 |
| LAB-RACK-P13 (nominal record typechecking — output_type_hints pre-scan, check_record_literal_shape, field missing/extra/wrong-type OOF-TY0, Unknown → named type upgrade on success) | igniter-lab | ✅ DONE | 47/47 |
| LAB-RACK-P14 (Rack-shaped ContractResult composition — 6-branch kind→FullRackResponse mapping (found/created/not_found/capability_denied/upstream_error/upstream_unavailable); map_get→Option[String]+or_else→String; P13 record upgrade; VM-proved 9/10 contracts; map_get VM gap → closed by LAB-VM-MAP-P1) | igniter-lab | ✅ DONE | 60/60 |
| LAB-VM-MAP-P1 (VM runtime map_get/map_has_key/or_else — map_get+map_has_key OP_CALL handlers (bare + qualified aliases); or_else pre-existing; Value::Record = Map[String,String] runtime; compiler input field access fix (OP_LOAD_REF+"name"+OP_GET_FIELD("field")); Rack P14 HeadersAwareHandler 10/10 VM-executable; Sidekiq P5 MetadataReader VM gap closed; fixture: 7 contracts MapGetHit/Miss/OrElseHit/Miss/HasKeyHit/Miss/HeaderChain; 48/48 PASS) | igniter-lab | ✅ DONE | 48/48 |
| LAB-RECORD-VM-P1 (VM record construction — zero new VM/compiler code; OP_PUSH_RECORD+BTreeMap proved; RackResponse + JobReceipt end-to-end; deterministic alphabetical serialization; covers Rack P14 + Sidekiq P5; see shared section below) | igniter-lab | ✅ DONE | 43/43 |
| LAB-RECORD-VM-P2 (dispatched record field access — OP_GET_FIELD added; response.status/body + receipt.status/budget_remaining/job_class proved; field values usable in arithmetic; missing-field OOF-P1 compile-time; Tier 2 field access fail-closed) | igniter-lab | ✅ DONE | 42/42 |
| LAB-RECORD-VM-P3 (nested record field values — one compiler.rs line; envelope.headers.content_type + envelope.meta.priority proved; typechecker + VM construction unchanged; direct local Unknown-typed chain fail-closed; non-record intermediate fail-closed) | igniter-lab | ✅ DONE | 49/49 |
| LAB-RECORD-MAP-P1 (Record/Map bridge — FullRackResponse {headers: Map[String,String]} proved; SIR params preserved through field access; VM store/retrieve works; C1 confirmed active (fix in P5); map_get gap documented; OOF-MAP1/2/3 in MapPipeline) | igniter-lab | ✅ DONE | 51/51 |
| Grammar analog | igniter-lang | ❌ lab pressure only (CR-001 applies) | — |

**Alignment gap:** LAB-RACK-P2..P14 + RECORD-VM-P1..P3 + RECORD-MAP-P1 + LAB-VM-MAP-P1 → lang | VM record construction proved (P1); field access proved (P2); nested record field values proved (P3); Map[String,String] record field bridge proved (RECORD-MAP-P1, SIR params preserved). PROP-043-P5 closed: map_get(response.headers,key)→Option[String] + or_else→String end-to-end in production TypeChecker (55/55); C1 fix landed. P14 closed: 6-kind ContractResult→FullRackResponse branch mapping proved at TypeChecker + VM (9/10 contracts). LAB-VM-MAP-P1 closed: VM map_get bytecode live; HeadersAwareHandler 10/10 VM-executable (48/48 PASS). Still open: Tier 2 type resolution, three-level chained field access, multi-output callee.

**Boundary:** HTTP types may not enter canon grammar without a cross-repo PROP + governance review.
Rack/middleware vocabulary is lab-only.

### Job Processing / Sidekiq (Lab only)

| Artifact | Repo | Status | Checks |
|---|---|---|---|
| LAB-SIDEKIQ-P1 (Sidekiq reimplementation feasibility and language pressure map — job-as-contract, dispatch table, BudgetedLocalLoop retry analogy, closed surfaces) | igniter-lab | ✅ RESEARCH COMPLETE | — |
| LAB-SIDEKIQ-P2 (static job dispatch table — 3 pure job contracts + JobDispatcher, VM-backed via lab-only `call_contract`, all fail-closed cases, P9 regression green) | igniter-lab | ✅ DONE | 54/54 |
| LAB-SIDEKIQ-P3 (BudgetedLocalLoop retry policy — `RetryPolicy` arithmetic, `RetrySimulator` PROP-039 loop fuel enforcement `max_steps:5`, `RetryWithDispatch` dispatch+budget composability) | igniter-lab | ✅ DONE | 43/43 |
| LAB-SIDEKIQ-P4 (JobReceipt schema — `type JobReceipt` 5-field record, P13 nominal record typechecking, P11 Tier 1 literal callee → JobReceipt, Tier 2 dynamic → Unknown, all shape violations OOF-TY0) | igniter-lab | ✅ DONE | 46/46 |
| LAB-RECORD-VM-P1 (VM record construction — JobReceipt end-to-end in VM; see shared section above) | igniter-lab | ✅ DONE (shared) | 43/43 |
| LAB-RECORD-VM-P2 (dispatched record field access — receipt.status/budget_remaining/job_class proved; field values usable in compute; OP_GET_FIELD added; see shared section above) | igniter-lab | ✅ DONE (shared) | 42/42 |
| LAB-RECORD-VM-P3 (nested record field values — JobEnvelope with JobMeta; envelope.meta.priority + envelope.meta.queue proved; see shared section above) | igniter-lab | ✅ DONE (shared) | 49/49 |
| LAB-RECORD-MAP-P1 (Record/Map bridge — JobEnvelope {meta: Map[String,String]} proved; VM meta field store/retrieve; C1 confirmed; see shared section above) | igniter-lab | ✅ DONE (shared) | 51/51 |
| LAB-SIDEKIQ-P5 (upstream HTTP result composition — JobInput/JobReceipt/RetryEnvelope with Map[String,String] metadata; 5 contracts: MetadataReader+SuccessPath+DeniedPath+RetryablePath+ExhaustedPath; map_get(job.metadata,key)→Option[String]+or_else→String via C1 fix; next_attempt=attempt+1→Integer; BudgetedLocalLoop simulation; 4 paths proved; two-layer: Ruby TypeChecker + proof-local sim) | igniter-lab | ✅ DONE | 48/48 |
| Grammar analog | igniter-lang | ❌ lab pressure only (CR-001 applies) | — |

**Alignment gap:** LAB-SIDEKIQ-P1..P5 + RECORD-VM-P1..P3 + RECORD-MAP-P1 + LAB-VM-MAP-P1 → lang | JobReceipt record typed and VM-executed (P1/P2); nested record field values proved (P3); Map[String,String] meta field bridge proved (RECORD-MAP-P1). PROP-043-P5 closed: map_get/or_else production TypeChecker live (55/55); C1 fix landed. LAB-SIDEKIQ-P5 closed: full upstream composition — all 4 job paths (success/denied/retry/exhausted) proved with Map[String,String] metadata; BudgetedLocalLoop simulation (48/48). LAB-VM-MAP-P1 closed: MetadataReader VM gap closed; map_get(job.metadata,"queue") executes end-to-end in VM (48/48 PASS). Still open: three-level chained field access, enum/status type system, async retry, queue storage, effect-callee dispatch.

**Boundary:** Job processing vocabulary is lab-only. No Sidekiq compatibility claim. No StorageCapability, ServiceLoop, or scheduler surfaces open. `call_contract` is lab-only with no stable API.

### Concurrency / Scheduling (Lab only)

| Artifact | Repo | Status | Checks |
|---|---|---|---|
| LAB-CONCURRENCY-P1 (pure-DAG parallel scheduling boundary — wave-based concurrent eligibility; SequentialScheduler == ParallelSchedulerSimulation result identity proved; effectful nodes serialized in v0; SchedulingReceipt telemetry only; 5 inline graph fixtures: diamond, fanout, chain, mixed-effectful, impure-siblings; DagValidator cycle+dep checks; DagWaves read-isolation invariant; Category: lang, Track: lab-deterministic-pure-dag-parallel-scheduling-boundary-v0) | igniter-lab | ✅ DONE | 57/57 |
| LAB-CONCURRENCY-P2 (capability-aware effect scheduling policy boundary — PolicyEvaluator 6-gate sequence: capability_denied→no_policy→unknown_resource→resource_conflict→category_closed→eligible; EffectSpec resource_keys + effect_category + capability_id; 8 fixtures (default_effect_serialized, read_read_disjoint, write_write_same, read_write_same, net_disjoint, net_same_host_closed, unknown_resource_key, denied_capability); parity: eligible==serialized result_values; PolicySchedulingReceipt telemetry only; P1 pure-DAG regression green; Category: lang, Track: lab-capability-aware-effect-scheduling-policy-boundary-v0) | igniter-lab | ✅ DONE | 59/59 |
| LAB-CONCURRENCY-P3 (scheduling receipt determinism and replay — ReplayableReceipt with schema_version/graph_digest/policy_digest/result_digest/spec_digest fields; DigestableMixin 4 digest functions; ReceiptReplayerP3 10-gate validation: schema→graph_digest→policy_digest→node_membership→wave_assignment→same_wave_dep→spec_drift→eligibility_tamper→result_consistency→re_execution; all graph/policy/effect/result/wave tampering fails closed; consistent result tamper (values+digest both changed) caught by Gate 10 re-execution; legal intra-wave permutations are equivalent; scheduling-receipt-evidence-only-v0; Category: lang, Track: lab-scheduling-receipt-determinism-and-replay-proof-v0) | igniter-lab | ✅ DONE | 60/60 |
| LAB-CONCURRENCY-P4 (minimal scheduler substrate contract — five-phase model: PREPARE/PLAN/EXECUTE_WAVE/RECORD/FINALIZE_RECEIPT; 9 substrate invariants SI-1..SI-9 (graph-digest-fixed, policy-digest-fixed, read-isolation, write-once, topo-order, policy-gate, eligibility-recorded, denial-recorded, canonical-result-digest); substrate options matrix: single-thread OPEN, simulated-parallel OPEN, real-thread-pool HOLD pending P5, async HOLD pending separate card; failure-mode matrix: node failure/policy mismatch/partial execution/effect denial; readiness checklist per substrate tier; W1 necessary-but-not-sufficient for threading; design only — no proof runner; Category: lang, Track: lab-scheduler-substrate-readiness-and-minimal-runtime-contract-v0) | igniter-lab | ✅ DONE — design | — |

**Boundary:** Lab-only. `ReplayableReceipt`, `PolicySchedulingReceipt`, and `SchedulingReceipt` are telemetry evidence only — they do not create semantic authority over scheduling decisions and do not open runtime concurrency authority. No `Thread`/`Fiber`/async-runtime infrastructure used. Concurrent-effectful dispatch requires explicit `SchedulingPolicy` (P2); overlapping writes and unknown resource keys always fail-closed; capability denial is Gate 1. Parity invariant proved across all fixtures: `result_values` identical regardless of `concurrent_eligible` flag (P1+P2). Replay invariant proved (P3): tampered receipts fail closed across all drift categories; consistent result tampering caught by Gate 10 re-execution; legal intra-wave permutations are structurally equivalent. Minimal substrate contract named (P4): five-phase model + 9 invariants + substrate options matrix + failure-mode matrix; real threading HOLD until P5 thread-safety proof; async HOLD until separate authorization card.

### Governance (Design / Classification)

| Artifact | Repo | Status | Notes |
|---|---|---|---|
| LAB-RESULT-ENVELOPE-P1 (Contract result envelope taxonomy + promotion boundary — 5 reusable patterns confirmed; HttpResult/ContractResult/FullRackResponse/JobReceipt classified domain-local; two RetryEnvelope shapes incompatible; denial-as-data is strongest invariant (6 proofs); no canon promotion; next: LAB-VM-MAP-P1 + LAB-RESULT-ENVELOPE-P2) | igniter-lab | ✅ DONE — analysis | governance |
| LAB-RESULT-ENVELOPE-P2 (Third-domain kind-discriminant pressure — form validation domain; ValidationResult 4-kind (valid/invalid/unauthorized/system_error); no HTTP status, no job fields; denial-as-data 7th proof; Map[String,String] 3rd context; kind-discriminant confirmed cross-domain; ValidationMapper three-layer confirmed; PROP-044 unblocked for proposal-authoring; 50/50 PASS) | igniter-lab | ✅ DONE — analysis | governance |
| PROP-044-P1 (Kind-discriminated outcome convention and sum type requirements — proposal authoring; KDR pattern defined; denial-as-data invariant stated; grammar gap enumerated (variant+match+narrowing); OOF-KIND1..4 namespace reserved; production implementation blocked; grammar proposal P2 authorized) | igniter-lang | ✅ DONE — proposal authored | governance |
| PROP-044-P2 (variant+match grammar design — VariantDecl EBNF; MatchExpr EBNF; VariantConstruct expr; type narrowing rules; OOF-KIND1..5 formal defs; SemanticIR shapes; parser+typechecker extension points; 15 decisions locked; P3 parser impl requires explicit auth) | igniter-lang | ✅ DONE — grammar design authored | governance |
| PROP-044-P3 (variant+match parser implementation — fat_arrow lexer; variant/match keywords; 6 new parse methods; ParsedProgram variants field + grammar_version=variant-v0; conflict boundaries proved; TypeChecker no-crash confirmed; all prior proofs clean; 50/50 PASS) | igniter-lang | ✅ DONE — parser implemented | lang |
| PROP-044-P4 (TypeChecker design — @variant_shapes 3-level store; classifier bridge (variant_declarations() + classified_program key); infer_variant_construct; infer_match_expr; unify_match_arm_types; OOF-KIND1..5 formal defs; per-arm narrowing; exhaustiveness algorithm; degraded mode; 16 design decisions; proof requirements 15 groups ~75-80 checks; P5 implementation requires explicit auth) | igniter-lang | ✅ DONE — typechecker design authored | governance |
| PROP-044-P5 (TypeChecker implementation — classifier bridge live; @variant_shapes store; infer_variant_construct; infer_match_expr full+degraded; unify_match_arm_types; OOF-KIND1..5 ACTIVE; variant_env in typed_program; 75/75 PASS; regressions clean 55+33+100+50) | igniter-lang | ✅ DONE — TypeChecker implemented | lang |
| PROP-044-P6 (SemanticIR emitter — semantic_variant_declarations (variant_env→variant_decl[]); semantic_variant_construct (arm/variant/fields/resolved_type); semantic_match_node (match_node kind; subject/subject_type/arms/exhaustive/has_wildcard); semantic_match_arm (pattern/body/resolved_type); wired into semantic_expr dispatch; variant_declarations at top-level semantic_ir_program; OOF-KIND1..5 → nil sir; 50/50 PASS; P5+P3+OOF-R3 regressions clean) | igniter-lang | ✅ DONE — SemanticIR emitter implemented | lang |

**Confirmed reusable patterns (no promotion yet):** denial-as-data (design law — **10 proofs**, 5 domains: network + HTTP + validation + query + storage), kind-discriminant (**confirmed cross-domain** — 5 domains: HttpResult + ContractResult + ValidationResult + QueryResult + StorageQueryResult), Map[String,String] (**4 contexts**: transport headers + job metadata + form metadata + query metadata), three-layer composition (**confirmed in validation domain**), attempt+max_attempts budget (domain-local — retry-capable domains only; NOT universal).  
**Blockers for any canon proposal:** ~~VM map_get bytecode~~ → ✅ closed; ~~only 2 domains~~ → ✅ 3 domains (P2); ~~proposal-authoring~~ → ✅ PROP-044-P1 authored; ~~grammar design~~ → ✅ PROP-044-P2 authored; ~~parser implementation~~ → ✅ PROP-044-P3 PASS 50/50; ~~typechecker design~~ → ✅ PROP-044-P4 authored; ~~TypeChecker implementation~~ → ✅ PROP-044-P5 PASS 75/75; ~~SemanticIR emitter~~ → ✅ PROP-044-P6 PASS 50/50; VM variant dispatch (P7) requires explicit authorization.  
**PROP-044 status:** ~~deferred~~ → ~~PROPOSAL-AUTHORING ONLY~~ → ~~P1 AUTHORED~~ → ~~P2 GRAMMAR DESIGN AUTHORED~~ → ~~P3 PARSER LIVE~~ → ~~P4 TYPECHECKER DESIGN AUTHORED~~ → ~~P5 TYPECHECKER LIVE~~ → **P6 SEMANTICIR EMITTER LIVE** — variant_decl/variant_construct/match_node; 50/50 PASS; P7 VM variant dispatch requires explicit authorization.  
**LAB-QUERY-P1:** Query/Arel-like data access boundary defined — QueryPlan v0 types (QuerySource/Projection/FilterPredicate/OrderBy/QueryPlan/QueryResult/StorageDenied) all expressible as named Records today; ORM permanently closed; joins/aggregates deferred to v1; StorageCapability boundary modelled on PROP-035; LAB-QUERY-P2 authorized (42 checks).

### Data Access / Query (LAB-QUERY)

| Artifact | Repo | Status | Notes |
|---|---|---|---|
| LAB-QUERY-P1 (Research: Arel-like query intent as typed records — QueryPlan/QueryResult/FilterPredicate/OrderBy types; ORM permanently closed; joins/aggregates deferred; StorageCapability boundary; denial-as-data 5-kind QueryResult; LAB-QUERY-P2 authorized) | igniter-lab | ✅ DONE — research + design boundary | lang / research |
| LAB-QUERY-P2 (QueryPlan pure builder proof — 6 contracts; 7 types; BuildQuerySource+BuildSelectQuery+BuildFilteredQuery+QueryResultDenied+QueryMetadataReader+QueryMapper; denial-as-data QueryResult{kind:"denied"}; C1 chain in 4th domain (result.metadata→Map[String,String]→Option[String]); all CORE fragment; 42/42 PASS) | igniter-lab | ✅ DONE — 42/42 PASS | lang / proof |
| LAB-STORAGE-CAPABILITY-P1 (IO.StorageCapability boundary design — allowed_sources/allowed_ops/row_limit/allow_include_all/read_allowed/write_allowed schema; 6-gate denial-as-data sequence; QueryExecutionReceipt shape; ExecuteQuery effect contract form (future); ESCAPE→STORAGE fragment; OOF-STORE1..5 candidates; 10 decisions locked) | igniter-lab | ✅ DONE — design-locked | lang / design |
| LAB-QUERY-P3 (QueryPlan v1 nested records + Collection[FilterPredicate] — 8 contracts; 7 types; nested QuerySource/Projection/OrderBy/Collection[FilterPredicate]; chained field access plan.source.table (LAB-RECORD-VM-P3 two-hop OP_GET_FIELD); C1 chain on richer QueryPlan; QueryResultDenied denial-as-data 8th proof; Rust typechecker array_literal gap documented; Layer A: Ruby TC; Layer B: Rust VM; Layer C: QueryExecutorSim; 44/44 PASS) | igniter-lab | ✅ DONE — 44/44 PASS | lang / proof |
| LAB-STORAGE-CAPABILITY-P2 (IO.StorageCapability mocked execution boundary proof — 6-gate denial sequence (G1–G6); G4=row-limit clamp (not denial); G5=include_all→query_error (not denied); denial-as-data 9th proof; QueryExecutionReceipt 15-field evidence record (6 invariants); KDR 5-kind vocabulary; separation from TBackend/TEMPORAL; two-fixture architecture (exec compile-only + receipts VM-executable); 4 boundary findings (B1: passport gap/ESCAPE class; B2: effect name closed vocab; B3: `read` keyword; B4: `message` keyword); Layer A Ruby TC + Layer B Rust VM + Layer C StorageCapabilityGates; 51/51 PASS) | igniter-lab | ✅ DONE — 51/51 PASS | lang / proof |
| LAB-EXECUTE-QUERY-P1 (ExecuteQuery effect contract and StorageCapability injection proof — 57/57 PASS; Stage 2+ first executable query path; ExecuteQuery effect contract (Layer A+B compile; ESCAPE class; two-fixture architecture); 6-gate denial sequence via Layer C ExecuteQuerySim; G4 clamp ≠ denial; G5 query_error ≠ denied; QueryExecutionReceipt 15-field invariants; BuildQueryPlanInline.filters=Collection[FilterPredicate] in Rust SIR (LAB-TC-ARRAY-P2 record-field-context confirmed); denial-as-data 10th proof; 5-kind KDR; TBackend absent; write ops CLOSED in v0; 12 pure contracts VM-executable; B3: deny_reason; B4: read_file; no DB/SQL/ORM/raise/persistence) | igniter-lab | ✅ DONE — 57/57 PASS | lang / proof |
| LAB-TC-ARRAY-P1 (Rust TypeChecker array-literal-in-Collection-context proof — closes LAB-QUERY-P3 finding B1; `compute filters = [{...},{...}]` / `[f1,f2]` now type as Collection[FilterPredicate] in a declared `output x : Collection[T]` position; CONTEXTUAL (mirrors RecordLiteral LAB-RACK-P13 upgrade); impl: collection_output_hints prescan + ArrayLiteral arm in infer_expr (Unknown free-standing, no OOF-TY0) + contextual upgrade block + check_array_literal_shape helper in typechecker.rs; empty array accepted ONLY with contextual type; free-standing stays Unknown; missing/extra/wrong-typed fields + mixed element shapes fail closed (OOF-TY0); Collection[FilterPredicate] survives into SIR type_tag (compute + output port); VM round-trips inline-constructed collection + full QueryPlan with inline filters; Layer B primary + Layer A parity; no new grammar; no DB/SQL/ORM/StorageCapability execution; 27/27 PASS; regressions clean: P3 44/44, P13 47/47, VM-MAP 48/48, record-vm 42/49/43) | igniter-lab | ✅ DONE — 27/27 PASS | lang / proof |
| LAB-TC-ARRAY-P2 (Rust TypeChecker array-literal-in-record-field-context proof — closes the non-blocking gap left by P1; an intermediate `compute filters = [...]` that feeds a typed record field (`compute plan = {..., filters: filters, ...}` / `output plan : QueryPlan` where QueryPlan.filters : Collection[FilterPredicate]) now types `filters` as Collection[FilterPredicate]; impl: order-independent prescan contributing record-field hints to the SAME collection_output_hints map P1 uses — for a RecordLiteral compute with a named-record output type, each bare-Ref field declared Collection[T] feeds hint T to the referenced compute (or_insert; P1 output hints win); LOCAL single-hop syntactic lookup, NO global/HM inference, NO retroactive symbol mutation (referenced compute typed first in dependency order); empty intermediate typed from field context iff field type known; bad/mixed elements still fail closed (OOF-TY0); P1 output-context + free-standing-Unknown preserved; VM round-trips plan.filters; no new grammar; no DB/SQL/ORM/StorageCapability; 19/19 PASS; regressions clean P1 27/27 + P3 44/44 + VM-MAP 48/48 + P13 47/47 + record-vm 43/42/49) | igniter-lab | ✅ DONE — 19/19 PASS | lang / proof |
| LAB-FILTER-EVAL-P1 (Filter predicate evaluation over mocked in-memory rows — 9 pure contracts (all CORE; no effect; no capability); v0 operators: eq/neq/contains/prefix; AND-only composition (filters.all?); Layer C FilterEvalSim proof-local Ruby evaluator; 5-row deterministic dataset; empty filter list → all rows; unknown field → no match (kind:"empty"); unknown op → kind:"query_error" (NOT "denied"); count==matched_rows.length invariant; BuildQueryPlanWithFilters.filters=Collection[FilterPredicate] in Rust SIR (LAB-TC-ARRAY-P2 record-field-context mechanism, 3rd confirmation); inline empty array → Collection[FilterPredicate] from record-field context; B1: VM has no iteration opcodes (Layer C correct boundary); B2: empty array field-context confirmed; B3: unknown field ≠ unknown op; B4: G1–G6 gate sequence orthogonal to filter evaluation; no DB/SQL/ORM/StorageCapability; KDR 3-kind routing: rows/empty/query_error; 50/50 PASS) | igniter-lab | ✅ DONE — 50/50 PASS | lang / proof |

**Boundary:** QueryPlan v1 = nested typed records (QuerySource/Projection/FilterPredicate/OrderBy) + Collection[FilterPredicate] + Map[String,String] metadata; all pure CORE contracts; no grammar changes; no SQL; no DB connections. ORM/ActiveRecord permanently incompatible. `IO.StorageCapability` schema designed (follows PROP-035 model; grammar impl requires PROP-035). QueryResult follows KDR convention (PROP-044-P1). ExecuteQuery = ESCAPE → STORAGE (Stage 2+). LAB-STORAGE-CAPABILITY-P1 design-locked. Rust typechecker array_literal gap: **CLOSED by LAB-TC-ARRAY-P1 (27/27 PASS)** — array literals now type as Collection[T] in declared Collection output contexts (contextual); inline filter construction compiles + VM round-trips; the P3 `filters`-as-input workaround is no longer required. **Record-field-position follow-up CLOSED by LAB-TC-ARRAY-P2 (19/19 PASS):** an intermediate array-literal compute feeding a typed record field (e.g. QueryPlan.filters) now types as Collection[T] via a local single-hop Ref-field hint prescan (no global inference); remaining edges (inline-in-field literals, multi-hop, conflicting hints) deferred to an optional v1 collection-inference card, not required before execution. With P1+P2, filter collections are fully constructible inline — expressivity is sufficient for LAB-EXECUTE-QUERY-P1. **LAB-STORAGE-CAPABILITY-P2 CLOSED (51/51 PASS):** 6-gate denial sequence proved; G4=clamp (not denial); G5→query_error (not denied); QueryExecutionReceipt 15-field invariants; denial-as-data 9th proof (StorageCapability 5th domain); ESCAPE class enforcement confirmed (effect contract passport gap = correct behavior); Rust effect name vocabulary closed ({read_file,read_json,read,write_file,write_json,write}); two-fixture architecture established for effect+pure contract lab separation. **LAB-EXECUTE-QUERY-P1 CLOSED (57/57 PASS):** first executable Stage 2+ query path proved; ExecuteQuery effect contract (Layer A+B compile; ESCAPE boundary correct); 6-gate sequence confirmed with QueryPlan + StorageCapability hashes; G4 clamp ≠ denial; G5 query_error ≠ denied; QueryExecutionReceipt invariants VM-verified; BuildQueryPlanInline.filters typed Collection[FilterPredicate] in Rust SIR (LAB-TC-ARRAY-P2 record-field-context confirmed in EXECQ fixture); denial-as-data 10th proof; TBackend/TEMPORAL absent (orthogonality confirmed); write ops CLOSED in v0; 12 pure contracts VM-executable; two-fixture architecture reused. **LAB-FILTER-EVAL-P1 CLOSED (50/50 PASS):** QueryPlan.filters is no longer just shape — it has a v0 semantic meaning over mocked in-memory rows; eq/neq/contains/prefix operators proved; AND composition narrows correctly (3<4); empty filter list → all rows; unknown field → kind:"empty" (not query_error); unknown operator → kind:"query_error" (NOT denied); count==matched_rows.length invariant; Layer C required for row evaluation semantics (VM has no iteration opcodes, correct boundary); inline empty array → Collection[FilterPredicate] (3rd confirmation of P2 mechanism); G1–G6 gate sequence orthogonal.

### Web Framework / View Engine (Lab only)

| Artifact | Repo | Status | Checks |
|---|---|---|---|
| LAB-WEB-FRAMEWORK-P4 (LayoutEngine, fill_slot, render, inheritance) | igniter-lab | ✅ DONE | ~45/45 |
| Grammar analog | igniter-lang | ❌ lab-only for now | — |

### Dynamic Data Structures (LAB-DYNAMIC-DATA)

| Artifact | Repo | Status | Notes |
|---|---|---|---|
| LAB-DYNAMIC-DATA-P1: taxonomy + pressure map + boundary research | igniter-lab | ✅ CLOSED 2026-06-09 | Map/Record/JsonValue/Table/Unknown — research only |
| PROP-043-P1: Map[K,V] Stage 1 design lock | igniter-lang | ✅ CLOSED 2026-06-09 | 15 decisions; stdlib.map.* v0 surface; OOF-MAP1/2/3 candidates; P2 fixture matrix ≥18 checks |
| PROP-043-P2: Map[K,V] proof-local experiment | igniter-lang | ✅ CLOSED 2026-06-09 | MapPipeline + 15 fixtures + verify script; 42/42 PASS; OOF-MAP1/2/3 candidates proven; map_get/has_key/from_pairs/or_else type rules; FullRackResponse headers clean |
| PROP-043-P3: Map[K,V] acceptance decision | igniter-lang | ✅ CLOSED 2026-06-09 | P2 accepted; OOF-MAP1/2/3 → experiment-pass; Map[String,V] v0 accepted; map_empty conditional (C2); 9 P4-Q items; P4 authorized |
| PROP-043-P4: Map[K,V] production-edit planning | igniter-lang | ✅ CLOSED 2026-06-09 | 2-file scope: classifier.rb (1-line C1 fix) + typechecker.rb (+175 lines); SIR emitter + parser no change; or_else new addition; C1/C2 resolved; OOF-MAP wording locked; P5 authorized |
| PROP-043-P5: Map[K,V] production implementation + Record/Map bridge | igniter-lang | ✅ CLOSED 2026-06-09 | classifier.rb C1 fix + typechecker.rb (+180 lines); OOF-MAP1/2/3 active; map_get/has_key/from_pairs/empty + or_else; MAP-BRIDGE: map_get(response.headers,key)→Option[String] + or_else→String proved; C1 fix closes LAB-RECORD-MAP-P1 gap; verify_prop043_map_production.rb 55/55 PASS; all regressions clean |
| LAB-MAP-RUST-P1: Map[String,V] Rust lab compiler symmetry | igniter-lab | ✅ CLOSED 2026-06-09 | typechecker.rs: or_else Option[V] extraction fix; map_get/has_key/from_pairs/empty handlers; OOF-MAP1/2/3 parity; Record/Map bridge map_get(response.headers,key)→Option[String]+or_else→String; 32/32 PASS; all regressions clean; C1 not needed in Rust |

**Three-tier hierarchy (research finding):**
1. Named `Record` — known-schema data (proven: P12/P13/Sidekiq-P4)
2. `Map[K, V]` — dynamic-key homogeneous-value (✅ Stage 1 production live — PROP-043-P5; OOF-MAP1/2/3 active; map_get/has_key/from_pairs/empty + or_else + Record/Map bridge proved; Rust lab symmetry: LAB-MAP-RUST-P1)
3. `JsonValue` tagged sum (stdlib) — outermost IO boundary only; deferred

**Closed surfaces:** `Map[String, Any]` at contract boundaries; `Unknown` as user type; `Table/DataFrame` before Stage 2 OLAPPoint; `null` as a language value; runtime-only schema validation.

**Next design work:** ✅ LAB-MAP-RUST-P1 closed (32/32 PASS; Rust lab Map[String,V] symmetry proved; map_get→Option[V]; or_else→V; OOF-MAP1/2/3 parity; C1 finding: not needed in Rust). v1 expansion (keys/values/merge/size/to_pairs/map-literal) remains closed. Named Record production promotion (PROP-004 amendment). JSON boundary deferred. Table/DataFrame hold (Stage 2).

---

## Proposal Queue (igniter-lang Stage 3)

| PROP | Name | Status | Notes |
|---|---|---|---|
| PROP-031 | Contract modifiers | ✅ experiment-pass | Base modifier grammar |
| PROP-032 | Assumptions block | ✅ experiment-pass (bounded) | Compiler surface only |
| PROP-033 | via profile binding | ✅ experiment-pass | profile_binding in contract_ir |
| PROP-034 | output evidence syntax | ✅ experiment-pass | OOF-M9; evidence in IR output ports |
| PROP-035 | Effect Surface / IO.Capability | ✅ experiment-pass | OOF-M2/M4/M5 |
| PROP-036 | compiler_profile_id manifest | accepted; partial-impl | CLI B1..B9 closed |
| PROP-037 | External progression svc liveness | ✅ accepted; all OOF-PR1..9 closed | ServiceLoop auth; OOF-PR6/8 + schema ownership closed 2026-06-07 |
| PROP-038 | Compiler profile contract | accepted; partial-impl | schema + validator |
| PROP-039 | Managed local recursion/loops | ✅ accepted; proposal-only | Vocabulary only; impl closed |
| PROP-040 | Profile declarations | ✅ experiment-pass | OOF-M7/M8; closes CR-003 |
| PROP-041 | T2 structural-size relation | ✅ experiment-pass (proposal authored P5; P3 proof-local 48/48) | OOF-R8/R9 canonical; production edits → P6 |
| PROP-042 | T3 numeric measure expressions | ✅ P4 planning complete | OOF-R10/R11 experiment-pass; production implementation → P5 (authorized) |
| PROP-043 | Map[K,V] Stage 1 — production live + Rust lab symmetry | ✅ P1+P2+P3+P4+P5 complete; LAB-MAP-RUST-P1 closed | OOF-MAP1/2/3 active; map_get/has_key/from_pairs/empty + or_else live; C1 fix; Record/Map bridge: map_get(response.headers,key)→Option[String]; 55/55 PASS; Rust symmetry 32/32 PASS; all regressions clean |
| PROP-044 | Kind-discriminated outcome convention + sum type requirements | ✅ P1+P2+P3+P4+P5+P6 complete | P1: KDR convention; denial-as-data; OOF-KIND1..4 reserved. P2: VariantDecl+MatchExpr EBNF; OOF-KIND1..5; SemanticIR shapes; 15 decisions. P3: parser live; 50/50 PASS. P4: TypeChecker design; 16 decisions. P5: TypeChecker+OOF-KIND1..5 ACTIVE; 75/75 PASS. P6: SemanticIR emitter live; variant_decl/variant_construct/match_node; 50/50 PASS; P7 VM dispatch requires auth |
| PROP-045 | Source-level `intent` descriptor and queryable contract purpose | ✅ P1+P2 complete | P1: keyword `intent`; bounded plain string; module+contract placement; OOF-INTENT1..4 reserved; CR-003 orthogonal; 20 decisions locked. P2: production parser+classifier+typechecker+emitter; to_h fix; OOF-INTENT3 active; 53/53 PASS; 15 decisions locked |

**Next queue:**
1. ✅ PROP-039 gate 1: loop_class_semantics_proof — 66/66 PASS (2026-06-07)
2. ✅ PROP-039 gate 3: loop_class_parser_proof — 60/60 PASS (2026-06-07)
3. ✅ DA-005: archive pass complete — 12 dirs moved, 164 unknown intact
4. ✅ PROP-039 gate 4: loop_typechecker_proof — 49/49 PASS (2026-06-07)
   OOF-L1 (for_loop non-Collection source), OOF-R2 (recursive missing decreases),
   OOF-R4 (fuel_bounded/decreases-fuel missing max_steps)
5. ✅ PROP-039 gate 5: loop_semanticir_proof — 49/49 PASS (2026-06-07)
   loop_node IR shape: loop_class, termination evidence, source_ref, item, max_steps (budgeted);
   recursive/fuel_bounded modifier in contract_ir; OOF-blocking → nil semantic_ir;
   grammar_version="loop-v0" propagates all 4 stages; contract_ref includes loop identity
6. ✅ Lab G1: Rust compiler item-variable conformance — verify_g1_canon_loop.rb PASS (2026-06-07)
   parser.rs: `loop Name item in source` accepted; classifier/typechecker/emitter/vm compiler updated
   full slice: .ig → parse → classify → typecheck → emit → assemble → bytecode → VM exec; result=100 ✓
7. ✅ Lab G2: Rust compiler recursive/fuel_bounded conformance — verify_loops.rb PASS (2026-06-07)
   parser.rs: `recursive`/`fuel_bounded` modifiers + `Decreases`/`MaxSteps` BodyDecl variants
   conformance fixture: Factorial + LoopTester + SumList all compile; LoopTester executes correctly ✓
8. ✅ PROP-039 gate 6: OOF registry review — namespace resolved, governance shim set (2026-06-07)
   Active: OOF-L1 (typechecker), OOF-R2/R4 (classifier) → experiment-pass compiler surface
   Ch13 OOF-R2/R4 (service loop) migrated to OOF-SL* (PROP-037); conflict resolved
   Lab: G1+G2 closed, verify_loops.rb PASS, conformance fixture compiles all 3 contracts
   Tracked: igniter-lang/.agents/work/gates/PROP-039-gate6-oof-registry-review.md
9. ✅ PROP-039 gate 7: canonical conformance package — spine defined (2026-06-07)
   Grammar forms (FiniteLoop/BudgetedLocalLoop/StructuralRecursion/FuelBoundedRecursion) + OOF codes
   (OOF-L1/R2/R4) + SemanticIR shapes (loop_node) + lab consumption contract + PROP-037 boundary
   Lab G1+G2 conformance status documented; future gaps: G3 (PROP-037 split), G4 (body), G5 (recur())
   Tracked: igniter-lang/.agents/work/conformance/PROP-039-managed-repetition-conformance-package-v0.md
10. ✅ Lab G3: conformance alignment pass — all three sub-tasks closed (2026-06-08)
    G3a: OOF-R2 (recursive missing decreases) + OOF-R4 (fuel_bounded/decreases-fuel missing max_steps)
         classifier.rs — 5 diagnostic cases verified (fire/suppress)
    G3b: FiniteLoop `for Name item in source { body }` — parser.rs; vm/vm.rs fuel sentinel (u64::MAX)
         full slice: parse → classify → typecheck → emit → assemble → VM exec (5+10+15=30 ✓)
    G3c: IR shape kind="loop_node" (was "loop"); loop_class, termination, source_ref, max_steps at top level
         emitter.rs + vm/compiler.rs; BudgetedLocalLoop and FiniteLoop both verified
    verify_g3_conformance.rb: 14/14 PASS
11. ✅ Canon Gate 8: loop body semantics — `lead` keyword, lead_node+compute_node IR shape, OOF-L5/L7/L8 (2026-06-08)
    `lead name: Type = expr` loop-carried binding; body scope rules; OOF-L7 (read-only item), OOF-L8 (shadow)
    loop_body_semantics_proof: 100/100 PASS
    Tracked: igniter-lang/experiments/loop_body_semantics_proof/
12. ✅ Lab G4: Rust symmetry for Gate 8 — `lead` parser, OOF-L5/L7/L8 classifier+typechecker, two-track body (2026-06-08)
    `body=[lead_node*,compute_node*]` + `item_type` in emitter.rs; `body_nodes` VM execution field preserved
    verify_g4_body_semantics.rb: 18/18 PASS (incl. non-literal OOF-L5, clean OOF-L8 fixture)
13. ✅ Canon G5: recur() call semantics — OOF-R1/R5/R6/R7, `recur_call` sub-expr in SemanticIR (2026-06-08)
    Context validation (OOF-R1), arity (OOF-R5), type (OOF-R6), single-output (OOF-R7)
    recur_call is sub-expression only — must NOT appear as top-level node
    recursive_body_proof: 100/100 PASS
    Tracked: igniter-lang/experiments/recursive_body_proof/
14. ✅ Lab G5: Rust symmetry for G5 — OOF-R1/R5/R6/R7 in typechecker.rs, `recur_call` sub-expr in emitter.rs (2026-06-08)
    recur() context-check, arity-check, type-check, single-output-check all symmetric with canon
    verify_g5_recur.rb: 18/18 PASS
15. ✅ OOF-R3 gate: syntactic variant decrease proof — canon TypeChecker gate (2026-06-08)
    classifier.rb: decreases_variant extraction; typechecker.rb: OOF-R3 per recur() site + dotted-path fail-closed
    semanticir_emitter.rb: termination.variant_check="syntactic_v0" on clean contracts
    Whitelist: variant-N, variant.tail, variant.rest. Exempt: fuel_bounded, decreases fuel.
    verify_oof_r3.rb: 33/33 PASS
16. ✅ Lab OOF-R3: Rust symmetry — classifier.rs + typechecker.rs + emitter.rs (2026-06-08)
    decreases_variant extraction; OOF-R3 per recur() site + dotted-path fail-closed; termination.variant_check in SemanticIR
    Collection.tail/rest whitelist in FieldAccess inference; syntactic_decrease + syntactic_arg_desc free functions
    verify_oof_r3.rb: 34/34 PASS
17. ✅ Lab STR-CORE: Rust text stdlib symmetry — typechecker.rs + emitter.rs (2026-06-08)
    text_arg_compatible/check_text_stdlib_call helpers; all 14 ops; canon OOF-TY0 format; stdlib.text.* IR rewrite in emitter
    P2 (LAB-STR-CORE-P2): rewrite_concat_calls pass — concat(Text,Text)→stdlib.text.concat; concat(Collection,...)→stdlib.collection.concat
    verify_str_core.rb: 29/29 PASS
18. ✅ Lab STR-CORE-P3: Text value-semantics boundary proof (2026-06-08)
    byte/rune/grapheme unit separation proven; slice SIR shapes + resolved_type verified; OOF-TY0 index/arity enforcement
    split→Collection[Text] params shape; replace/replace_all SIR fn names; regex pattern treated as literal Text
    Declared policy (runtime-gated): bounds clamp, split("","x"), replace_all overlap, byte_slice UTF-8 boundary
    verify_str_value_semantics.rb: 33/33 PASS
19. ✅ LAB-STR-UNICODE-P1: Text Unicode policy design-lock (2026-06-08)
    UTF-8 validity: Text = valid UTF-8 (Value::String(Arc<str>)); UAX #29 = grapheme authority
    No implicit normalization; exact codepoint equality; trim = Unicode Pattern_White_Space
    slice bounds: [start,end) half-open; clamp; byte_slice invalid boundary → ""; split("") undefined v0
    grapheme backend: unicode-segmentation (UAX #29); version pin via Cargo.lock; canon receipt design
20. ✅ LAB-STR-UNICODE-P2: Unicode VM runtime ops implementation (2026-06-08)
    unicode-segmentation = "1.11" in Cargo.toml (lock: 1.13.3); UnicodeSegmentation import in vm.rs
    8 functional ops: rune_length, grapheme_length, byte_slice, rune_slice, grapheme_slice, ends_with, replace, replace_all
    Qualified aliases: stdlib.text.concat, trim, contains; stdlib.collection.concat
    empty-input guards: stdlib.text.split (empty delimiter → error); replace/replace_all (empty pattern → error)
    UAX #29 proven: rune_length("éx")=3, grapheme_length("éx")=2; NFC≠NFD no normalization
    verify_unicode_text_runtime.rb: 43/43 PASS
21. ✅ LAB-STR-UNICODE-P3: handler hygiene + Unicode runtime receipt (2026-06-08)
    bare "split" handler aligned with empty-delimiter fail-closed policy (LAB-STR-UNICODE-P3 hygiene)
    before: bare split("","") → Rust default (split at every char) — silent policy bypass possible
    after: bare split("","") → runtime operational error — no bypass via legacy handler name
    unicode_runtime_receipt.json: status=lab-only-evidence; lock=1.13.3; 4 handler guards confirmed
    verify_unicode_text_runtime.rb: 41/41 PASS (UNI-DEP/RCP/HYG/ERR/LENGTH/SLICE/REPLACE/SPLIT/ALIAS/AUTH/PATH)
22. ✅ PROP-041-P3/P4/P5/P6/P7: T2 structural-size relation — full production graduation (2026-06-08)
    P3: T2TypeChecker + T2Emitter sub-classes; 28 fixtures; verify_prop041_t2.rb 48/48 PASS (T2a–T2h)
    P4: authorization review — experiment-pass accepted; formal proposal authoring opened; production edits closed
    P5: formal proposal authored — grammar surface, STDLIB_REGISTRY, trust levels, OOF-R8/R9, SIR shape, backward compat
    P6: production-edit planning — minimal diff plan authorized; P7 dispatched
    P7: production implementation — parser.rb + classifier.rb + typechecker.rb + semanticir_emitter.rb updated
        verify_prop041_t2_production.rb 48/48 PASS; verify_oof_r3.rb 33/33 PASS (OOF-R3 scope unweakened)
        OOF-R8/R9 active in production pipeline; structural_size_v1 SemanticIR shape live
    Next: LAB-TERM-T2 Rust symmetry
23. ✅ LAB-PROOF-HYGIENE-P1: proof harness timeout + process-group cleanup (2026-06-08)
    Root cause: unbounded backtick/system() calls left igniter_compiler at ~100% CPU for hours
    tools/proof_harness/bounded_command.rb: hard timeout + process-group kill (SIGTERM → SIGKILL)
    11 proof runners updated (10 in igniter-compiler/, 1 in igniter-vm/proofs/)
    Self-test: test_bounded_command.rb 11/11 PASS
    Remaining unbounded: proofs/ subdirectory, view-engine proofs → P2 candidate
    Timeout policy: EXEC=10s, CARGO=120s, PROOF_WIDE=300s (all env-configurable)
24. ✅ LAB-COMPILER-LIVENESS-P1: compiler liveness risk map + diagnostic taxonomy (2026-06-08)
    Research/design only — no compiler code changed
    Risk map: 9 stages audited; MEDIUM risk in Rust typechecker/form-resolver/emitter (stack depth, no limit)
    Proposed E-COMPILER-BUDGET / E-COMPILER-CYCLE / E-COMPILER-NONPROGRESS / E-COMPILER-INTERNAL-INVARIANT codes
    Audit receipt shape: is_source_program_fault:false + is_compiler_internal:true (distinct from OOF)
    Four-way distinction: OOF (source) / E-COMPILER (compiler) / harness timeout / runtime max_steps
    Gates: P2 (instrumentation, non-fatal) → P3 (hard limits, E-COMPILER-BUDGET) → P4 (full guard)
    Next: LAB-COMPILER-LIVENESS-P2 (instrumentation pass — start here before P3 calibration)
25. ✅ LAB-COMPILER-LIVENESS-P2: non-fatal liveness instrumentation counters (2026-06-08)
    5 instrument points: tc.infer_expr, fr.walk_expr, em.lower_expr_for_targets, em.build_pipeline, parser.parse_import
    Thread-local RAII guards (TcInferGuard etc.) — zero call-site signature changes
    Adversarial 200-term fixture: tc_infer=200, fr_walk=200, status=ok (no behavior change)
    Canonical baselines: typical depth <10; calibration window confirmed for P3 limit selection
    Receipt injected on both ok and oof paths; stderr separation confirmed; non_fatal=true
    verify_liveness_p2.rb: 25/25 PASS
26. ✅ LAB-TERM-T2-P1: PROP-041 T2 structural-size relation — Rust symmetry proof (2026-06-08)
    parser.rs: SizeRelationDecl struct; size_relations field on SourceFile; parse_size_relation_decl(); order-independent
    classifier.rs: size_relations propagation (serde skip_if_empty)
    typechecker.rs: T2RegistryEntry/T2Context/T2Kind types; stdlib_size_registry(); NUMERIC_ACCESSORS; T2 dispatch;
        OOF-R8 (missing relation) + OOF-R9 (call-site mismatch); stateless design: t2_context as local var,
        check_t2_callsite_in_expr separate method; decreases_variant_t2 + size_relation_evidence on TypedContract
    emitter.rs: structural_size_v1 termination path — decreases, variant_check, size_relation.{accessor,trust,source}
    28 fixtures; verify_t2_structural_size_relation.rb 52/52 PASS (T2A–T2I)
    Regression: verify_oof_r3.rb 34/34 PASS; verify_g5_recur.rb 18/18 PASS
    Trust model: stdlib_certified (Collection.tail/rest, compiler_builtin) / user_assumed (source = module name)
    T2 = structural evidence with trust metadata — NOT a full termination proof; lab ≠ canon authority
    Next: LAB-COMPILER-LIVENESS-P3 (hard limits + E-COMPILER-BUDGET diagnostics; use P2 data)
26. ✅ LAB-COMPILER-LIVENESS-P3: calibrated E-COMPILER-BUDGET hard limits (2026-06-08)
    Fatal budget: tc.infer_expr limit=1000, fr.walk_expr limit=1000 (5× P2 adversarial max of 200)
    Observe-only: emitter/parser counters (insufficient calibration data — P2 measured 0)
    Budget breach → status="compiler_error" + E-COMPILER-BUDGET (is_compiler_internal=true, is_source_program_fault=false)
    1100-term breach fixture confirms fail-closed at depth 1001 > limit 1000
    200-term P2 probe still accepted (depth 200 < 1000) — no regression
    Canonical fixtures: ok, breaches=[]; OOF fixtures: still oof; stdout always valid JSON
    verify_liveness_p3.rb: 38/38 PASS; verify_liveness_p2.rb: 25/25 PASS (backward compat)
    E-COMPILER-BUDGET lab-local per CR-002; no canon OOF codes; no grammar/VM/lang changes
    Next: LAB-COMPILER-LIVENESS-P4 (calibrate emitter/parser observe-only; E-COMPILER-CYCLE candidate)
27. ✅ LAB-COMPILER-LIVENESS-P4: emitter/parser calibration + E-COMPILER-CYCLE preflight (2026-06-08)
    em_lower: calibrated to 30 (30-term form expression); mirrors tc_infer; P3 budget implicitly bounds it
    em_pipeline: calibrated to 10 (9 nested filters in if_expr); bounded by source nesting depth
    parse_import: STRUCTURAL BOUND — lexer merges uppercase-dotted paths to single Ident token;
      counter always 0 (no imports) or 1 (any import); cannot exceed 1 without lexer change
    E-COMPILER-CYCLE: risk classified LOW for all passes (finite AST, no form-calls-form, no back-edges)
    compiler_error sidecar: stdout-only is correct (unreliable record worse than no record)
    All three counters confirmed observe-only (data-justified, not assumption-based)
    New fixtures: liveness_emitter_form_lower.ig, liveness_emitter_pipeline_depth.ig, liveness_parser_import_steps.ig
    verify_liveness_p4.rb: 40/40 PASS; verify_liveness_p3.rb: 38/38 PASS; verify_liveness_p2.rb: 25/25 PASS
    Next: LAB-COMPILER-LIVENESS-P5 if: form-calls-form grammar change, production corpus data, or E-COMPILER-BUDGET PROP
28. ✅ LAB-COMPILER-LIVENESS-P5: parser non-progress and subprocess timeout hardening (2026-06-09)
    Root cause: peek_type returned false for Eof when current()=None (past EOF sentinel); all while!peek_type(Eof) loops hung
    Fix 1 (parser.rs): peek_type returns true for Eof when current()=None — single-function, zero semantic change
    Fix 2 (parser.rs): parse_body_decl_with_recovery wraps output/compute — on Err: advance, emit OOF-P1, skip to boundary
    Fix 3 (parser.rs): parse_type_decl field loop — explicit match-on-Err for name/colon/type; OOF-P1 per bad field
    BoundedCommand (verify_liveness_p5.rb): Process.spawn + killer thread (SIGTERM then SIGKILL); 15s default timeout
    Process invariant: pgrep count unchanged before/after 5 malformed compiles (P5-I)
    stdout bounded: all malformed inputs < 1KB, well-formed < 64KB cap; all valid JSON (P5-J)
    New fixtures: 5 malformed hang fixtures + 1 well-formed regression guard
    verify_liveness_p5.rb: 46/46 PASS; verify_liveness_p4.rb: 40/40 PASS (backward compat)
    No new OOF codes, no language semantics change, no canon impact, no runtime/VM change
    Next: extend parse_body_decl_with_recovery to all body-decl keywords; BoundedCommand for VM runner
29. ✅ LAB-COMPILER-LIVENESS-P6: body-declaration recovery generalisation (2026-06-09)
    Audit finding: name_token()/expect_type() ALWAYS advance unconditionally — even on error
    Migration: 11 .ok() arms → parse_body_decl_with_recovery (input, capability, effect, read, snapshot, escape, stream, fold_stream, invariant, lead, max_steps)
    Deferred to P7: window/loop/for — have inner {} blocks; skip_until_body_boundary stops at inner }, not contract }
    decreases arm: always returns Ok — .ok() is semantic no-op; documented and left unchanged
    Token-progress guarantee: all 19 arms either recover, always succeed, or fall to _ => advance
    Fixture discovery: use IntLit (42) after keywords to get independent failures without consuming next keyword
    verify_liveness_p6.rb: 54/54 PASS; verify_liveness_p5.rb: 46/46 PASS (backward compat)
    No new OOF codes; no language semantics change; no canon impact
    Next P7: skip_to_matching_brace for window/loop/for; consider peek-before-advance for expect_type
30. ✅ LAB-TERM-T2-P2: OOF-R9 branch and multi-recur edge hardening (2026-06-08)
    Root cause: check_t2_callsite_in_expr IfExpr arm only walked cond, not then/else_block bodies
    Fix: extended IfExpr arm to mirror check_recur_in_expr exactly (stmts + return_expr for both branches)
    5 new fixtures: multi_recur_both_correct, multi_recur_one_wrong, if_both_branches_correct,
      if_wrong_else_branch, nested_arith_wrong
    Proven: mixed correct/wrong fails closed; correct site does NOT suppress wrong-site OOF-R9
    OOF-R3/R8 precedence unchanged; T1 syntactic_v0 unaffected; no new OOF codes; no canon changes
    verify_t2_oof_r9_edge_cases.rb: 21/21 PASS
    Regression: verify_t2_structural_size_relation.rb 52/52; verify_oof_r3.rb 34/34; verify_g5_recur.rb 18/18
    LAB-TERM-T2 track complete (P1+P2). Next: PROP-042 T3 numeric measure proposal.
29. ✅ PROP-042-P1: T3 numeric measure expressions — formal proposal authored (2026-06-09)
    Depends on: PROP-041-T3-P1 design lock (CLOSED)
    Grammar: `decreases count(items)` function-call form; dispatch branch new (not T1/T2)
    NUMERIC_MEASURE_BUILTINS v0: count(Collection[T]) only; stdlib_numeric_certified trust; compiler_builtin source
    NUMERIC_ACCESSORS (T2) unchanged — T3 opens function-call path only, not dotted path
    OOF-R10 (unrecognized measure fn) + OOF-R11 (decrease obligation not met) — candidates until P2 gate
    SemanticIR: variant_check="numeric_measure_v0", numeric_measure.{fn, arg, trust, source}
    Call-site obligation: T2 structural coverage → numeric decrease implied (T2 registry reused)
    Backward compat: T1/T2 unchanged; T3-unaware compiler may emit OOF-R3 (conformance allowance)
    Proposal: igniter-lang/.agents/work/proposals/PROP-042-t3-numeric-measure-expressions-v0.md
    Card: igniter-lang/.agents/work/cards/lang/PROP-042-P1.md
    Deferred: Text length measures, user-defined measures, size/length aliases, count(x)-1 (T4)
    Next: PROP-042-P2 proof-local experiment gate (≥19 fixtures, T3a–T3i)
30. ✅ LAB-DYNAMIC-DATA-P1: dynamic data structure taxonomy + boundary research (2026-06-09)
    Scope: JSON / Map / Record / Collection / Table / Unknown — research only, no grammar/compiler changes
    Finding 1: Named Record covers ~80% of near-term needs (JobReceipt, RackResponse, HttpRequest proven)
    Finding 2: Map[String,String] is the most urgent unproven gap — Rack headers deferred since P12
    Finding 3: JSON stays boundary format only; JsonValue deferred until concrete IO boundary use case proven
    Finding 4: Table/DataFrame → Stage 2 OLAPPoint (PROP-024); no Stage 1 mechanism
    Finding 5: Unknown is compiler-internal state; not a dynamic type; Map[String,Any] permanently closed
    Taxonomy: Named Record > Map[K,V] > JsonValue (three tiers); all other combos closed
    Next: PROP-043 Map[K,V] design lock (immediate); Named Record production promotion; JSON boundary deferred; Table hold
    Docs: igniter-lab/lab-docs/lang/lab-dynamic-data-structures-json-map-table-research-boundary-v0.md
    Card: igniter-lang/.agents/work/cards/lang/LAB-DYNAMIC-DATA-P1.md
31. ✅ PROP-043-P1: Map[K,V] Stage 1 design lock (2026-06-09)
    Depends on: LAB-DYNAMIC-DATA-P1, LAB-RACK-P12/P13, LAB-SIDEKIQ-P4
    15 decisions locked: String-only keys (v0); no literal syntax (deferred MapLit to v1); from_pairs construction;
        Option[V] lookup always; Map≠Record design law; JSON stays closed; no new SemanticIR node kind (v0)
    v0 stdlib: stdlib.map.get → Option[V]; stdlib.map.has_key → Bool; stdlib.map.from_pairs; stdlib.map.empty
    v1 deferred: with_entry, keys, values, size, merge, to_pairs
    Diagnostics (candidates): OOF-MAP1 (K≠String), OOF-MAP2 (Map[K,Any]), OOF-MAP3 (Unknown annotation)
    P2 fixture matrix: MAP-A (annotations) + MAP-B (key restriction OOFs) + MAP-C (get/has_key) +
        MAP-D (FullRackResponse+headers) + MAP-E (SemanticIR shapes) + MAP-F (regression) = ≥18 checks
    Proposal: igniter-lang/.agents/work/proposals/PROP-043-map-kv-stage1-v0.md
    Card: igniter-lang/.agents/work/cards/lang/PROP-043-P1.md
32. ✅ PROP-043-P2: Map[K,V] proof-local experiment (2026-06-09)
    Depends on: PROP-043-P1, LAB-DYNAMIC-DATA-P1, LAB-RACK-P13, LAB-RECORD-VM-P1
    MapPipeline: MapTypeChecker < IgniterLang::TypeChecker; @output_type_hints pre-scan; no production edits
    15 fixtures: MAP-A (3 valid annotations) + MAP-B (3 OOF candidates) + MAP-C (3 stdlib lookups) +
        MAP-D (4 Rack pressure) + MAP-F (2 regression/boundary) = 15 fixture files
    Type rules proven: map_get(Map[String,V], String)→Option[V]; or_else(Option[V],V)→V; has_key→Bool;
        from_pairs(Collection[HeaderPair])→Map[String,String] via @type_shapes[elem]["value"] field
    FullRackResponse {headers: Map[String,String]}: record literal resolved correctly via output_type_hints
    OOF-MAP1/2/3 candidates proven; OOF-MAP3 output-only behavior confirmed
    JSON, Any, mutation, real TCP all remain closed; no SemanticIR kind added
    verify_prop043_map.rb: 42/42 PASS (MAP-A 7 + MAP-B 8 + MAP-C 7 + MAP-D 9 + MAP-E 5 + MAP-F 6)
    Card: igniter-lang/.agents/work/cards/lang/PROP-043-P2.md
33. ✅ PROP-043-P3: Map[K,V] acceptance decision (2026-06-09)
    Depends on: PROP-043-P2
    Decision: P2 accepted (proof-local experiment-pass); OOF-MAP1/2/3 elevated candidate→experiment-pass
    Map[String,V] v0 surface accepted: map_get/has_key/from_pairs all accepted; map_empty conditional (C2)
    5 named caveats evaluated: C1 (param strip, P4 item), C2 (map_empty usable scope, P4 item),
        C3 (short names, confirmed design), C4 (subclass arch, standard), C5 (OOF-MAP3 output-only, confirmed correct)
    P2 does NOT authorize production implementation; P4 production-edit planning authorized
    9 P4-Q items scoped: TypeChecker integration, @output_type_hints, param unification, or_else, map_empty scope,
        from_pairs fallback, SIR emitter confirm, regression matrix, OOF message wording
    Track: igniter-lang/.agents/work/tracks/prop043-map-kv-proof-local-acceptance-decision-v0.md
    Card: igniter-lang/.agents/work/cards/lang/PROP-043-P3.md
    Next: PROP-043-P4 production-edit planning (no production file edits; planning only)
35. ✅ PROP-043-P5: Map[K,V] production implementation + Record/Map bridge (2026-06-09)
    Track: map-kv-production-implementation-with-record-bridge-v0
    Depends on: PROP-043-P4, LAB-RECORD-MAP-P1
    classifier.rb: 1-line C1 fix (line 52: normalize_type → normalized_type_annotation for field annotations)
    typechecker.rb: MAP_STDLIB_FNS constant; @output_type_hints pre-scan; OOF-MAP annotation scan;
        array_literal/record_literal arms in infer_expr; MAP dispatch + or_else in infer_call;
        14 new private methods (infer_map_call, infer_map_get, infer_map_has_key, infer_map_from_pairs,
        infer_from_pairs_value_type, infer_map_empty, infer_or_else, infer_array_literal,
        infer_record_literal, check_map_annotation, param_type_name, map_type_ir, option_type_ir,
        collection_type_ir_from); 1-line type_shapes C1 fix (line 118)
    No parser/emitter/VM changes (confirmed)
    Bridge fixture: map_d_header_record_bridge.ig (ContentTypeFromResponse + HeaderPresenceCheck)
    Production verify: verify_prop043_map_production.rb 55/55 PASS
        MAP-A 7/7 (annotation acceptance + C1 param preservation)
        MAP-B 8/8 (OOF-MAP1/2/3 isolation)
        MAP-C 7/7 (map_get/or_else/has_key type rules)
        MAP-D 9/9 (FullRackResponse headers C1 end-to-end)
        MAP-E 5/5 (SemanticIR fn names + resolved_type)
        MAP-F 11/11 (regressions + closed surfaces + production-specific C1/C2/v1 checks)
        MAP-BRIDGE 8/8 (map_get(response.headers,key)→Option[String]; or_else→String; C1 closes gap)
    Record/Map bridge key finding: C1 fix makes @type_shapes["FullRackResponse"]["headers"]=Map[String,String];
        field access returns Map[String,String] (not Map no-params); map_get→Option[String] (not Option[Unknown])
    Regressions: verify_oof_r3.rb 33/33; verify_prop041_t2_production.rb 48/48;
        verify_prop042_t3_production.rb 45/45; verify_prop043_map.rb (proof-local) 42/42
    Next: Lab-Map-Rust-P1 (Rust lab Map[String,V] symmetry — unblocked by P5 graduation)
36. ✅ LAB-SIDEKIQ-P5: Sidekiq upstream HTTP result composition with Map[String,String] metadata (2026-06-09)
    Track: lab-sidekiq-upstream-http-result-retry-composition-proof-v0
    Depends on: PROP-043-P5, LAB-SIDEKIQ-P4, LAB-STDLIB-NET-P8/P9, LAB-MAP-RUST-P1, LAB-RECORD-MAP-P1
    Fixture: upstream_http_result_composition.ig — 5 types (HttpResult, ContractResult, JobInput, JobReceipt, RetryEnvelope)
    Contracts: MetadataReader, SuccessPath, DeniedPath, RetryablePath, ExhaustedPath
    Layer A (Ruby TypeChecker): map_get(job.metadata,"worker")→Option[String]; or_else→String (C1 fix end-to-end);
        record literal { ..., metadata: job.metadata, ... } → JobReceipt / RetryEnvelope via @output_type_hints;
        next_attempt = job.attempt + 1 → Integer (infer_binary field_access + literal); all 5 contracts accepted
    Layer B (UpstreamCompositionP5 simulation): BudgetedLocalLoop analog; success/denied/retry/exhausted;
        [error,error,found] → receipt.attempt=3; metadata passthrough (object identity); map_get+or_else behavioral
    SJOB5-TYPES/MAP/SUCCESS/DENIED/RETRY/EXHAUSTED/SIM/REG/CLOSED/GAP: 48/48 PASS
    Zero type_errors across all 5 fixture contracts
    No production file changes; proof-local + igniter-lang production TypeChecker used read-only
    Key finding: C1 fix chains through: @type_shapes["JobInput"]["metadata"]=Map[String,String] →
        job.metadata field_access → Map[String,String] → map_get → Option[String] (not Unknown)
    All 4 job paths with Map[String,String] metadata proved; BudgetedLocalLoop retry behavior proved

37. ✅ LAB-RESULT-ENVELOPE-P1: Contract result envelope taxonomy and promotion boundary (2026-06-09)
    Category: governance / Track: lab-contract-result-envelope-taxonomy-and-promotion-boundary-v0
    Route: DESIGN / GOVERNANCE / LAB-ONLY — analysis only; no code, no production changes
    Source: NET-P8/P9 + RACK-P14 + SIDEKIQ-P5 + RECORD-VM-P1/P2/P3 + PROP-043-P5

    Five confirmed reusable patterns (Category A):
      denial-as-data:       6-proof corpus (P6/P7/P8/P9/P14/P5) — strongest invariant; design law candidate
                            Every consumer handles capability denial as typed data; no exception/raise anywhere
      kind-discriminant:    HttpResult (3 values) + ContractResult (6 values); de facto lab convention
                            for typed unions; not yet syntax-supported (no sum types in grammar)
      budget-loop:          attempt+max_attempts in P8 RetryEnvelope + P5 RetryEnvelope + P5 JobReceipt
                            PROP-039 BudgetedLocalLoop confirmed as the right abstraction
      Map[String,String]:   PROP-043-P5 already production; headers (transport) + metadata (job) both use same shape
      three-layer:          HttpResult → ContractResult → consumer; appeared independently in P14 + P5

    Domain-local (stay classified):
      HttpResult:            NETWORK-LOCAL — 3-variant; `denied` HTTP-specific; transport internals
      ContractResult:        HTTP-DOMAIN-LOCAL — name too generic; 6-kind HTTP-bound; recommend future rename
      FullRackResponse:      RACK-LOCAL — integer HTTP status; Rack-only consumer
      JobReceipt:            SIDEKIQ-LOCAL — job_class/job_id Sidekiq-specific
      RetryEnvelope (P8/P5): INCOMPATIBLE SHAPES — P8 embeds HttpResult; P5 is re-enqueue instruction; don't unify

    No canon proposals authorized. Primary blockers: ~~VM map_get bytecode~~ → ✅ closed; ~~only 2 domains~~ → ✅ 3 domains (P2); ~~proposal-authoring~~ → ✅ PROP-044-P1 authored; ~~grammar design~~ → ✅ PROP-044-P2 authored; parser implementation (P3) requires explicit authorization
    Next authorized routes:
      ✅ immediate: LAB-VM-MAP-P1 CLOSED (48/48 PASS)
      ✅ next: LAB-RESULT-ENVELOPE-P2 CLOSED (50/50 PASS — 3rd domain; PROP-044 unblocked for authoring)
      ✅ next: PROP-044-P1 CLOSED (convention doc authored; grammar gap enumerated; OOF-KIND1..4 reserved)
      ✅ next: PROP-044-P2 CLOSED (VariantDecl+MatchExpr EBNF; OOF-KIND1..5; SemanticIR shapes; 15 decisions)
      ✅ next: PROP-044-P3 CLOSED (50/50 PASS — fat_arrow; 6 parse methods; grammar_version=variant-v0)
      ✅ next: PROP-044-P4 CLOSED (TypeChecker design — @variant_shapes; classifier bridge; OOF-KIND1..5; 16 decisions)
      ✅ next: PROP-044-P5 CLOSED (75/75 PASS — OOF-KIND1..5 ACTIVE; infer_variant_construct; infer_match_expr; regressions clean)
      ✅ next: PROP-044-P6 CLOSED (50/50 PASS — SemanticIR emitter live; variant_decl/variant_construct/match_node)
      next (explicit auth required): PROP-044-P7 VM variant dispatch

38. ✅ LAB-VM-MAP-P1: VM runtime map_get/map_has_key/or_else over Map[String,String] (2026-06-09)
    Category: lang / vm / Track: lab-vm-map-ops-runtime-proof-v0
    Route: LAB / VM / IMPLEMENTATION
    Depends on: LAB-RESULT-ENVELOPE-P1 (identified blocker), LAB-RACK-P14 (gap source), LAB-SIDEKIQ-P5,
                LAB-MAP-RUST-P1 (TypeChecker proofs), LAB-RECORD-VM-P2 (OP_GET_FIELD base)
    vm.rs: map_get("map_get"|"stdlib.map.get") handler — (Value::Record, String) → Nil|raw value
           map_has_key("map_has_key"|"stdlib.map.has_key") handler — (Value::Record, String) → Bool
           or_else was pre-existing — already handled Nil→fallback + non-Nil→identity correctly
    compiler.rs: input field access fix — OP_LOAD_REF("a.b") → OP_LOAD_REF("a")+OP_GET_FIELD("b")
                 enables MetadataReader and all contracts with nested input field access
    Map runtime: Value::Record(BTreeMap<String,Value>) — no new Value variant needed
    Option: None=Value::Nil, Some(v)=raw v — consistent with pre-existing or_else
    SIR names: bare "map_get" (emitter does not qualify map names unlike stdlib.text.*)
    Fixture: 7 contracts (MapGetHit/Miss, OrElseHit/Miss, HasKeyHit/Miss, HeaderChain)
    Rack P14: HeadersAwareHandler 9/10 → 10/10 VM-executable — LAB-RESULT-ENVELOPE-P1 blocker #2 closed
    Sidekiq P5: MetadataReader executes end-to-end in VM (queue present → value, absent → "default")
    Closed: mutation (map_set/map_delete), non-String keys, map literals, broad API (keys/values/size),
            JSON/JsonValue semantics, stable runtime API claim, canon authority
    verify_lab_vm_map_p1.rb: 48/48 PASS
      VMAP-COMPILE 4/4 | VMAP-TYPES 5/5 | VMAP-GET 6/6 | VMAP-HAS 4/4 | VMAP-OR 6/6 |
      VMAP-BRIDGE 4/4 | VMAP-RACK 4/4 | VMAP-SIDEKIQ 4/4 | VMAP-CLOSED 5/5 | VMAP-GAP 6/6

42. ✅ PROP-044-P2: variant+match grammar design (2026-06-09)
    Category: lang / Track: variant-and-exhaustive-match-design-v0
    Route: PROPOSAL / GRAMMAR DESIGN ONLY
    Depends on: PROP-044-P1, PROP-004 (ch3 type grammar), PROP-026 (parser OOF hardening)
    Grammar designed (no implementation):
      VariantDecl: new TopDecl form — "variant" Name "{" VariantArm+ "}"
        VariantArm: Name ("{" ArmField* "}")? — unit arms and record arms both supported
        Parse AST: { kind: "variant", name, arms: [{ name, fields: [{name, type_annotation}] }] }
      VariantConstruct: PascalCase-ident + "{" in parse_primary → { kind: "variant_construct", arm, fields }
      MatchExpr: new parse_primary form — "match" Expr "{" MatchArm+ "}"
        MatchArm: ArmPattern "{" Bindings "}" "=>" Expr | "_" "=>" Expr
        Parse AST: { kind: "match_expr", subject, arms: [{ pattern: {arm, bindings}, body }] }
      Type narrowing: per-arm binding scope; arm field types from variant declaration
      v0 restrictions: subject = ref or field-access only; no guards; no nested match
    OOF-KIND codes (formal definitions — candidates, not active):
      OOF-KIND1: non-exhaustive match (typechecker, error) — missing arm, no wildcard
      OOF-KIND2: arm/binding not in variant (classifier+typechecker, error)
      OOF-KIND3: unreachable arm (typechecker, warning) — wildcard before last, duplicate
      OOF-KIND4: match subject not a variant type (typechecker, error)
      OOF-KIND5: arm result types do not unify (typechecker, error) — new in P2
    SemanticIR shapes (design only): variant_decl (in variant_defs); variant_construct (expr);
      match_node (expr; exhaustive flag; per-arm bindings+resolved_types)
    Parser extension points: 4 sites identified (TopDecl dispatch; parse_primary kw branch;
      parse_primary ident/PascalCase branch; keyword table)
    Typechecker extension points: @variant_shapes store; check_variant_decl;
      infer_variant_construct; infer_match_expr
    15 design decisions locked (D1..D15)
    Closed: parser impl (P3 req. auth); typechecker (P4); emitter (P5); VM (P6);
            OOF activation; Option match; stable API
    Design doc: igniter-lang/.agents/work/proposals/PROP-044-variant-and-exhaustive-match-design-v0.md
    Card: igniter-lang/.agents/work/cards/lang/PROP-044-P2.md

44. ✅ PROP-045-P1: Source-level intent descriptor and queryable contract purpose (2026-06-09)
    Category: lang / Track: source-intent-descriptor-and-queryable-contract-purpose-v0
    Route: PROPOSAL AUTHORING ONLY
    Depends on: language-covenant.md (Axiom 1/2, Postulate 7), PROP-033, PROP-040, PROP-044-P1, LAB-RESULT-ENVELOPE-P2, LAB-QUERY-P1
    Design (no implementation):
      Keyword: `intent` — not `description` (conflicts with PROP-040 profile field); not `purpose`/`about`/`summary`
      Shape: bounded plain string (500-char advisory limit); no structured fields in v0; no interpolation
      Placement v0: module/file level (after ModuleDecl) + contract body (BodyDecl)
      Placement v1 (deferred): type decls, output/input decls, trait/impl blocks
      Required: optional in v0; mandatory deferred to later PROP
      Behavior digest: NOT included — intent is metadata only
      Source/docs digest: YES — intent_text in contract_ir and module metadata
      Behavioral compatibility: NONE — intent changes are metadata-only; not a breaking change
    CR-003 relationship: ORTHOGONAL — CR-003/PROP-040 covers profile_binding (which profile to bind);
      PROP-045 covers purpose metadata (what the contract does). Different surfaces.
    OOF-INTENT codes (candidates, not active): OOF-INTENT1 (too long), OOF-INTENT2 (secret pattern),
      OOF-INTENT3 (duplicate — error), OOF-INTENT4 (unsupported site)
    Authority: NEVER confers capability/policy/runtime authority
    P2 recommendation: parser implementation (explicit auth required); complexity: low
    20 design decisions locked
    Proposal: igniter-lang/.agents/work/proposals/PROP-045-source-intent-descriptor-and-queryable-contract-purpose-v0.md
    Card: igniter-lang/.agents/work/cards/lang/PROP-045-P1.md

44b. ✅ PROP-045-P2: Source-level intent descriptor — parser + metadata propagation proof (2026-06-10)
    Category: lang / Track: source-intent-descriptor-parser-and-metadata-proof-v0
    Route: PARSER / METADATA PROPAGATION PROOF
    Depends on: PROP-045-P1, PROP-033/040 (profile_binding precedent)
    Production changes:
      parser.rb: `intent` keyword; module-level parse (after module, before imports);
        `parse_intent_decl` method; `parse_body_decl` dispatch arm; `ParsedProgram#to_h` intent_text fix
      classifier.rb: intent body node → no symbol; OOF-INTENT3 on duplicate; contract + module intent_text propagation
      typechecker.rb: contract + module intent_text pass-through
      semanticir_emitter.rb: intent_text in typed_contract_ir + typed_semantic_ir_program
    Key fix: `ParsedProgram#to_h` was missing `intent_text` — AST had the value; to_h did not emit it
    OOF-INTENT3: NOW ACTIVE — fires in classifier; first intent kept; fragment_class → oof
    Proved: intent_text present in contract_ir when declared; absent when not; orthogonal to profile_binding;
      no fragment_class change; no type_errors; no compute node injection; no capability authority
    53/53 PASS (8+8+6+8+6+6+5+6 across 8 sections)
    Proof runner: igniter-lang/experiments/intent_descriptor_proof/intent_descriptor_proof.rb
    Card: igniter-lang/.agents/work/cards/lang/PROP-045-P2.md
    Closed: OOF-INTENT1/2/4 (not active); behavior digest inclusion; mandatory enforcement;
            type/output/field-level intent; stable query API; secret detection

45. ✅ LAB-STORAGE-CAPABILITY-P1: IO.StorageCapability query execution boundary design (2026-06-09)
    Category: lang / Track: lab-storage-capability-query-execution-boundary-design-v0
    Route: DESIGN / LAB-ONLY (no proof runner; design-locked)
    Depends on: PROP-035, LAB-QUERY-P1, LAB-QUERY-P2, LAB-CONCURRENCY-P4
    IO.StorageCapability schema (v0):
      allowed_sources: [String]   -- table names; empty = deny all (fail-closed)
      allowed_ops:     [String]   -- ["read"] in v0; "write" deferred
      row_limit:       Integer    -- clamp safety cap; 0 = deny all rows
      allow_include_all: Bool     -- false = G5 query_error on SELECT * plans
      read_allowed:    Bool       -- master read gate
      write_allowed:   Bool       -- always false in v0
      deny_reason:     String     -- surfaced in QueryResult.message
    Structural parallel to NetworkCapability: allowed_hosts→allowed_sources; connect_allowed→read_allowed; listen_allowed→write_allowed
    Denial-as-data gate sequence (6 gates, fail-closed, short-circuit):
      G1: source in allowed_sources? NO → denied
      G2: "read" in allowed_ops?    NO → denied
      G3: read_allowed==true?        NO → denied
      G4: plan.limit > row_limit?    YES → clamp (no denial); receipt records row_limit_clamped
      G5: include_all + !allow_include_all? → query_error (plan-formation error; not denial)
      G6: execute (mocked in v0) → rows/empty/system_error
    QueryExecutionReceipt: cap_id/plan_kind/source_table/op_requested/cap_checked/cap_granted/
      denial_gate/deny_reason/plan_limit/row_limit_cap/effective_limit/row_limit_clamped/
      rows_returned/result_kind/metadata — evidence only; does not re-authorize
    Future ExecuteQuery form (requires PROP-035 grammar):
      effect contract ExecuteQuery { capability storage: IO.StorageCapability; effect read_from_storage using storage; input plan:QueryPlan; output result:QueryResult }
    Fragment classification: plan-building=CORE (LAB-QUERY-P2); ExecuteQuery=ESCAPE→STORAGE (Stage 2+)
    OOF-STORE candidates (not active): OOF-STORE1 (dynamic source name — high); OOF-STORE2 (write on read-only — high); OOF-STORE3 (source not in list — medium); OOF-STORE4 (include_all on restricted cap — medium); OOF-STORE5 (row_limit:0 misconfig — low)
    10 design decisions locked (D1..D10)
    Permanently closed: real DB/SQL/ORM/ActiveRecord/migrations/transactions/persistence runtime
    Deferred: write ops (v1); JOINs/aggregates (v1); delegation algebra (v1); STORAGE fragment class (Stage 2+)
    ✅ Next: LAB-QUERY-P3 CLOSED (44/44 PASS — nested QuerySource/Projection/FilterPredicate/OrderBy; Collection[FilterPredicate]; chained field access; C1 chain; denial-as-data)
    ✅ Next: PROP-046-P1 CLOSED (proposal authored — 14 sections; 15 decisions; IO.StorageCapability boundary; ExecuteQuery ESCAPE→STORAGE; TBackend⊥StorageCapability)
    ✅ Next: LAB-STORAGE-CAPABILITY-P2 CLOSED (51/51 PASS — 6-gate denial sequence; row-limit clamp; include_all→query_error; denial-as-data 9th proof; QueryExecutionReceipt 15-field record; ESCAPE class enforcement confirmed; two-fixture architecture for effect+pure separation)
    Next authorized: LAB-EXECUTE-QUERY-P1 (Stage 2+ execution proof; capability injection); LAB-TC-ARRAY-P1 (Rust typechecker array_literal)
    Design doc: igniter-lab/lab-docs/lang/lab-storage-capability-query-execution-boundary-design-v0.md
    Card: igniter-lab/.agents/work/cards/lang/LAB-STORAGE-CAPABILITY-P1.md

46. ✅ LAB-QUERY-P3: QueryPlan v1 nested records + Collection[FilterPredicate] proof (2026-06-10)
    Category: lang / Track: lab-query-plan-nested-records-and-filter-collection-proof-v0
    Route: EXPERIMENTAL / LAB-ONLY
    Depends on: LAB-QUERY-P1, LAB-QUERY-P2, LAB-STORAGE-CAPABILITY-P1, LAB-RECORD-VM-P3, PROP-043-P5, LAB-VM-MAP-P1
    QueryPlan v1 shape (7 types):
      QuerySource { table:String, schema:String }
      Projection { fields:String, include_all:Bool }
      FilterPredicate { field:String, op:String, value:String }
      OrderBy { field:String, direction:String }
      QueryPlan { kind:String, source:QuerySource, projection:Projection, filters:Collection[FilterPredicate], order:OrderBy, limit:Integer, metadata:Map[String,String] }
      QueryResult { kind:String, count:Integer, message:String, metadata:Map[String,String] }
      StorageDenied { table:String, op:String, reason:String, kind:String }
    8 contracts: BuildFilterPredicate + BuildOrderBy + BuildProjection + BuildQuerySource + BuildRichSelectPlan + PlanNestedFieldReader + PlanMetadataReader + QueryResultDenied
    Key findings:
      B1 — Rust typechecker array_literal gap: [f1,f2] accepted Layer A (Ruby TC); blocked Layer B (Rust _ => catch-all); Collection[FilterPredicate] as input accepted both layers; candidate: LAB-TC-ARRAY-P1
      B2 — Chained field access plan.source.table: two-hop OP_GET_FIELD via LAB-RECORD-VM-P3 recursive compile_expr fix; confirmed on richer QueryPlan shape
      B3 — C1 chain portable: map_get(plan.metadata,key)+or_else on QueryPlan v1; chain is domain-shape-independent (4th domain)
      B4 — Denial-as-data 8th proof: QueryResult{kind:"denied"} constructed cleanly; no exception/raise; 4th domain
    Layer A: Ruby TypeChecker — 8/8 accepted; 0 type_errors; Collection[FilterPredicate] type env correct
    Layer B: Rust compiler + VM — 8/8 contracts compiled; all VM runs succeed; nested records preserved
    Layer C: QueryExecutorSim — 5-kind routing; denial-as-data; "empty" ≠ "denied" ≠ "query_error"
    All contracts pure CORE; no SQL; no DB; no ORM; no StorageCapability execution; no stable API
    ✅ Next: LAB-STORAGE-CAPABILITY-P2 CLOSED (51/51 PASS — 6-gate denial sequence; QueryExecutionReceipt 15 fields; denial-as-data 9th proof; ESCAPE class confirmed)
    Next authorized: LAB-TC-ARRAY-P1; LAB-EXECUTE-QUERY-P1; LAB-FILTER-EVAL-P1
    verify_lab_query_p3.rb: 44/44 PASS
      QPLAN3-COMPILE 4/4 | QPLAN3-TYPES 6/6 | QPLAN3-NESTED 5/5 | QPLAN3-BUILD 4/4 |
      QPLAN3-ARRAY 4/4 | QPLAN3-VM 8/8 | QPLAN3-CHAIN 4/4 | QPLAN3-KDR 4/4 | QPLAN3-CLOSED 5/5
    Doc: igniter-lab/lab-docs/lang/lab-query-plan-nested-records-and-filter-collection-proof-v0.md
    Card: igniter-lab/.agents/work/cards/lang/LAB-QUERY-P3.md

51. ✅ LAB-EXECUTE-QUERY-P1: ExecuteQuery effect contract and StorageCapability injection proof (2026-06-10)
    Category: lang / Track: lab-execute-query-effect-contract-and-storage-capability-injection-v0
    Route: LAB PROOF / STAGE 2+ / MOCKED STORAGE EXECUTION / NO REAL DB
    Depends on: LAB-QUERY-P3, LAB-STORAGE-CAPABILITY-P1, LAB-STORAGE-CAPABILITY-P2, LAB-TC-ARRAY-P2, PROP-035, PROP-046-P1
    Two-fixture architecture (B1 resolution — same pattern as LAB-STORAGE-CAPABILITY-P2):
      execute_query_capability.ig — effect contract + 4 pure contracts (Layer A + Layer B compile)
      execute_query_receipts.ig  — 12 pure contracts only (Layer B VM execution; Rust SIR type checks)
    Types proved: QuerySource/Projection/FilterPredicate/OrderBy/QueryPlan/QueryResult/QueryExecutionReceipt (15 fields)/StorageCapability (8 fields)
    17 contracts total: ExecuteQuery (effect, compile-only) + ReadPlanSource + ReadPlanProjection + BuildDeniedResult + ReadPlanMeta + BuildStorageCapability + BuildQueryPlanInline + ExecuteQueryRows + ExecuteQueryEmpty + ExecuteQueryDeniedSource + ExecuteQueryQueryError + ExecuteQuerySystemError + BuildAllowedReceipt + BuildDeniedGateReceipt + BuildClampedReceipt + QueryReceiptReader + QueryMetadataChain
    6-gate denial sequence proved (Layer C ExecuteQuerySim):
      G1: plan.source.table not in cap.allowed_sources → "denied"
      G2: "read" not in cap.allowed_ops → "denied"
      G3: cap.read_allowed==false → "denied"
      G4: plan.limit > cap.row_limit → CLAMP (not denial); row_limit_clamped:true; cap_granted:true
      G5: include_all + !allow_include_all → "query_error" (not "denied")
      G6: mocked execute → "rows"/"empty"/"system_error"
    QueryExecutionReceipt invariants (VM-verified): cap_granted:false iff {denied,query_error}; rows_returned:0 when denied; effective_limit==min(plan_limit,row_limit_cap); G4 clamp ≠ denial
    Rust SIR: BuildQueryPlanInline.filters types Collection[FilterPredicate] (LAB-TC-ARRAY-P2 record-field-context confirmed in EXECQ fixture)
    KDR 5 kinds: rows/empty/denied/query_error/system_error; denial-as-data 10th proof (StorageCapability 5th domain)
    5 boundary findings:
      B1: Effect contract passport gap — ExecuteQuery ESCAPE class; two-fixture architecture is correct separation
      B2: filters=Collection[FilterPredicate] in Rust SIR (LAB-TC-ARRAY-P2 record-field-context confirmed)
      B3: `deny_reason` used (not `message` — Ruby parser keyword)
      B4: `read_file` used in effect binding (not `read` — Ruby parser keyword)
      B5: TBackend/TEMPORAL absent from both fixtures — orthogonality confirmed
    Permanently closed: real DB/SQL/ORM/ActiveRecord/persistence runtime/write ops (v0)/TBackend/TEMPORAL/stable API
    verify_lab_execute_query_p1.rb: 57/57 PASS
      EXECQ-COMPILE 5/5 | EXECQ-SHAPE 8/8 | EXECQ-GATES 6/6 | EXECQ-RECEIPT 7/7 |
      EXECQ-VM 8/8 | EXECQ-MAP 4/4 | EXECQ-ARRAY 4/4 | EXECQ-COMPOSE 5/5 |
      EXECQ-CLOSED 5/5 | EXECQ-GAP 5/5
    Next authorized: Stage 2+ live execution (PROP-035 Stage 2+ auth + ch4 ExecuteQuery ESCAPE→STORAGE amendment); ✅ LAB-FILTER-EVAL-P1 CLOSED (50/50 PASS — in-memory predicate evaluation; eq/neq/contains/prefix; AND composition; FilterEvalSim; unknown op→query_error (not denied))
    Doc: igniter-lab/lab-docs/lang/lab-execute-query-effect-contract-and-storage-capability-injection-v0.md
    Card: igniter-lab/.agents/work/cards/lang/LAB-EXECUTE-QUERY-P1.md

52. ✅ LAB-FILTER-EVAL-P1: Filter predicate evaluation over mocked in-memory rows (2026-06-10)
    Category: lang / Track: lab-query-filter-predicate-evaluation-over-mocked-rows-v0
    Route: LAB PROOF / QUERY SEMANTICS / IN-MEMORY MOCKED ROWS / NO DB
    Depends on: LAB-QUERY-P3 (44/44), LAB-TC-ARRAY-P2 (19/19), LAB-EXECUTE-QUERY-P1 (57/57)
    9 pure contracts (all CORE; no effect; no capability; no IO):
      BuildFilterEq / BuildFilterNeq / BuildFilterContains / BuildFilterPrefix — 4 operator predicate shapes
      BuildQueryPlanWithFilters — QueryPlan with inline 2-filter array (LAB-TC-ARRAY-P2 mechanism, 3rd confirmation)
      FilterResultRows — QueryResult{kind:"rows", count:N}
      FilterResultEmpty — QueryResult{kind:"empty", count:0}
      FilterResultQueryError — QueryResult{kind:"query_error"} for unknown operator (≠ "denied")
      FilterResultMetadataReader — map_get(result.metadata, key) + or_else on filter output
    Layer A: Ruby TypeChecker — 9/9 accepted; 0 type_errors; FilterPredicate / QueryPlan / QueryResult shapes correct
    Layer B: Rust compiler + VM — fixture compiles; Rust SIR: BuildQueryPlanWithFilters.filters =
             Collection[FilterPredicate] (record-field-context mechanism — 3rd confirmation);
             inline empty array → Collection[FilterPredicate] from field context (confirmed);
             VM executes 6 of 9 contracts: filter shapes, plan, rows/empty/query_error, metadata chain
    Layer C: FilterEvalSim (proof-local Ruby only — NOT production runtime) — eq/neq/contains/prefix correct
             over 5-row deterministic dataset; AND composition narrows (3 < 4 each individually);
             empty filter list → all 5 rows (vacuous conjunction = true);
             unknown field in row → kind:"empty" (row fails predicate; NOT query_error);
             unknown operator → kind:"query_error" (NOT "denied")
    count==matched_rows.length invariant holds across all evaluations
    KDR 3-kind routing: rows (process) / empty (show empty state) / query_error (fix predicate before retry)
    4 boundary findings:
      B1: VM has no iteration opcodes — Layer C required for row evaluation semantics (correct boundary, not a workaround)
      B2: Empty filter array → Collection[FilterPredicate] from record-field context (3rd confirmation of P2 mechanism)
      B3: Unknown field ≠ unknown operator: field absence → kind:"empty"; bad op → kind:"query_error" — must not collapse
      B4: StorageCapability G1–G6 gate sequence orthogonal to filter evaluation
    Permanently closed: real DB/SQL/ORM/ActiveRecord/persistence runtime/write ops/FilterEvalSim as production runtime/stable API
    verify_lab_filter_eval_p1.rb: 50/50 PASS
      FEVAL-COMPILE 5/5 | FEVAL-SHAPE 7/7 | FEVAL-ARRAY 4/4 | FEVAL-SEMANTICS 7/7 |
      FEVAL-RESULT 6/6 | FEVAL-VM 8/8 | FEVAL-CLOSED 5/5 | FEVAL-GAP 8/8
    Next authorized: OR/NOT composition (explicit card + KNOWN_OPS extension); numeric operators (gt_integer/lt_integer — typed value variant card); production filter runtime (VM iteration opcodes or compiled-to-host — separate card); rows field in QueryResult (Collection[Map[String,String]] or typed Row — separate card)
    Doc: igniter-lab/lab-docs/lang/lab-query-filter-predicate-evaluation-over-mocked-rows-v0.md
    Card: igniter-lab/.agents/work/cards/lang/LAB-FILTER-EVAL-P1.md

50. ✅ LAB-STORAGE-CAPABILITY-P2: IO.StorageCapability mocked execution boundary proof (2026-06-10)
    Category: lang / Track: lab-storage-capability-policy-gates-and-query-execution-receipt-v0
    Route: LAB PROOF / NO REAL DB / NO RUNTIME STORAGE
    Depends on: LAB-QUERY-P3, LAB-STORAGE-CAPABILITY-P1, PROP-035, PROP-046-P1, STAB-P4
    Two-fixture architecture (boundary finding B1 resolution):
      storage_capability_exec.ig — effect contract + 7 pure contracts (Layer A + Layer B compile)
      storage_capability_receipts.ig — 7 pure contracts only (Layer B VM execution)
    Types proved: QuerySource/Projection/FilterPredicate/OrderBy/QueryPlan/QueryResult/QueryExecutionReceipt (15 fields)
    8 contracts: ExecuteQuery (effect, compile-only) + BuildGrantedReceipt + BuildDeniedReceipt + BuildClampedReceipt + ReadReceiptFields + DeniedResult + QueryErrorResult + RowsResult
    6-gate denial sequence proved (Layer C StorageCapabilityGates):
      G1: source not in allowed_sources → "denied"
      G2: "read" not in allowed_ops → "denied"
      G3: read_allowed==false → "denied"
      G4: plan.limit > row_limit → CLAMP (not denial); row_limit_clamped=true
      G5: include_all + !allow_include_all → "query_error" (not "denied")
      G6: mocked execute → "rows"/"empty"/"system_error"
    QueryExecutionReceipt invariants (6 proved): cap_checked always true; cap_granted==false iff {denied,query_error}; rows_returned==0 when denied; effective_limit==min(plan_limit,row_limit_cap); row_limit_clamped==true iff effective_limit<plan_limit; source_table preserved
    KDR 5 kinds: rows/empty/denied/query_error/system_error; denial-as-data 9th proof (StorageCapability 5th domain)
    4 boundary findings:
      B1: Effect contract passport gap — VM requires capability injection for all contracts in same igapp; ESCAPE class enforcement correct (two-fixture pattern established)
      B2: Rust classifier effect name vocabulary closed: {read_file,read_json,read,write_file,write_json,write}; read_from_storage rejected
      B3: `read` is Ruby parser keyword; cannot use as effect binding name (parse_effect_binding_decl: ident-only)
      B4: `message` is Ruby parser keyword; cannot use as input name; renamed to `reason`
    TBackend ⊥ StorageCapability: orthogonal tracks; no type/grammar/runtime overlap
    Permanently closed: real DB/SQL/ORM/ActiveRecord/migrations/transactions/persistence runtime/stable API/write ops (v0)/TBackend
    verify_lab_storage_capability_p2.rb: 51/51 PASS
      SCAP2-COMPILE 4/4 | SCAP2-SCHEMA 6/6 | SCAP2-G1 4/4 | SCAP2-G2 3/3 | SCAP2-G3 3/3 |
      SCAP2-G4 4/4 | SCAP2-G5 3/3 | SCAP2-G6 4/4 | SCAP2-RECEIPT 6/6 | SCAP2-KDR 4/4 |
      SCAP2-COMPOSE 5/5 | SCAP2-CLOSED 5/5
    ✅ Next: LAB-EXECUTE-QUERY-P1 CLOSED (57/57 PASS — ExecuteQuery effect contract + mocked execution boundary; 6-gate sequence confirmed; QueryExecutionReceipt invariants VM-verified; denial-as-data 10th proof; TBackend orthogonality confirmed; write ops CLOSED v0)
    Next authorized: effect vocab expansion (B2 — explicit card required); Stage 2+ live execution (PROP-035 Stage 2+ auth + ch4 ExecuteQuery ESCAPE→STORAGE amendment); LAB-FILTER-EVAL-P1 (in-memory predicate evaluation)
    Doc: igniter-lab/lab-docs/lang/lab-storage-capability-policy-gates-and-query-execution-receipt-v0.md
    Card: igniter-lab/.agents/work/cards/lang/LAB-STORAGE-CAPABILITY-P2.md

49. ✅ PROP-046-P1: IO.StorageCapability boundary proposal (2026-06-10)
    Category: lang / governance / Track: storage-capability-query-execution-boundary-proposal-v0
    Route: PROPOSAL AUTHORING ONLY
    Depends on: PROP-035, LAB-QUERY-P1, LAB-QUERY-P2, LAB-QUERY-P3, LAB-STORAGE-CAPABILITY-P1, PROP-043-P5, LAB-VM-MAP-P1, STAB-P4
    Core formula (locked):
      QueryPlan         = pure typed intent data (CORE; no capability needed)
      StorageCapability = authority to attempt bounded storage execution (ESCAPE/STORAGE)
      QueryResult       = typed outcome/denial data (5-kind KDR)
      StorageCapability ≠ database connection / ORM / SQL runtime / TBackend (orthogonal)
    15 design decisions locked (D1..D15):
      D1: IO.StorageCapability name (IO.* opaque sentinel)
      D2: allowed_sources (not allowed_tables; mirrors QueryPlan vocabulary)
      D3: allowed_sources fail-closed (empty = deny all)
      D4: allowed_ops: ["read"] in v0; write deferred (not permanently closed)
      D5: row limit clamps (not denies); effective_limit = min(plan.limit, row_limit)
      D6: include_all violation → "query_error", not "denied"
      D7: read_allowed/write_allowed = master kill-switches (Gate G3)
      D8: deny_reason surfaced in QueryResult.message
      D9: QueryExecutionReceipt = evidence-only (no re-authorization)
      D10: ExecuteQuery = ESCAPE (v0) → STORAGE (Stage 2+; ch4 amendment required)
      D11: no delegation algebra in v0
      D12: SQL text generation is not a language surface
      D13: IO.StorageCapability ⊥ TBackend (orthogonal tracks)
      D14: no new grammar needed for P2 (PROP-035 sufficient)
      D15: write ops deferred (not permanently closed)
    6-gate sequence locked; QueryExecutionReceipt 15-field schema locked
    Implementation blocked: Stage 2+ STORAGE fragment class requires ch4 amendment
    ✅ Next: LAB-STORAGE-CAPABILITY-P2 CLOSED (51/51 PASS — 6-gate proof; QueryExecutionReceipt; denial-as-data 9th proof)
    Proposal: igniter-lang/.agents/work/proposals/PROP-046-storage-capability-query-execution-boundary-v0.md
    Card: igniter-lang/.agents/work/cards/lang/PROP-046-P1.md

48. ✅ PROP-044-P6: variant + match SemanticIR emitter implementation (2026-06-10)
    Category: lang / Track: variant-match-semanticir-emitter-proof-v0
    Route: SEMANTICIR EMITTER IMPLEMENTATION / BOUNDED
    Depends on: PROP-044-P5
    semanticir_emitter.rb changes (3 edits):
      typed_semantic_ir_program(): variant_env → semantic_variant_declarations(); result["variant_declarations"]
      semantic_expr(): elsif "variant_construct" → semantic_variant_construct(expr)
        elsif "match_expr" → semantic_match_node(expr) — before recur call check
      New methods (4):
        semantic_variant_declarations(variant_env): variant_env hash → [{kind:"variant_decl",
          name:, arms:[{name:, fields:[{name:, type:}]}]}]
        semantic_variant_construct(expr): typed_fields→fields rename; arm/variant/resolved_type
        semantic_match_node(expr): match_expr kind → match_node; subject/subject_type/arms/
          exhaustive/has_wildcard/resolved_type emitted
        semantic_match_arm(arm): pattern preserved; body lowered via semantic_expr; resolved_type
    Key IR shapes:
      variant_decl: top-level in semantic_ir_program (not in contracts); unit arms have fields:[]
      variant_construct: arm/variant/fields/resolved_type; typed_fields→fields rename
      match_node: kind renamed from match_expr; subject_type string; exhaustive/has_wildcard flags
    OOF guard: emit_typed checks type_errors.empty?; all OOF-KIND* programs → nil semantic_ir
    Closed: VM runtime; stable public API; grammar expansion; match guards
    Next authorized (explicit auth required): PROP-044-P7 VM variant dispatch
    verify_prop044_p6_semanticir.rb: 50/50 PASS
      SIR-VARDECL 5/5 | SIR-UNIT-ARM 5/5 | SIR-CONSTRUCT 5/5 | SIR-MATCH-KIND 5/5 |
      SIR-MATCH-ARMS 5/5 | SIR-MATCH-FLAGS 5/5 | SIR-OOF-GUARD 5/5 | SIR-REGRESSION 5/5 |
      SIR-DEGRADED 5/5 | SIR-BOUNDARY 5/5
    Regressions clean: P5-typechecker 75/75 | P3-parser 50/50 | OOF-R3 33/33
    Card: igniter-lang/.agents/work/cards/lang/PROP-044-P6.md

47. ✅ PROP-044-P5: variant + match TypeChecker implementation (2026-06-10)
    Category: lang / Track: variant-match-typechecker-and-oof-kind-activation-v0
    Route: TYPECHECKER IMPLEMENTATION / BOUNDED
    Depends on: PROP-044-P4
    classifier.rb changes (2 edits):
      variant_declarations(parsed_program) — maps parsed_program.fetch("variants", [])
        → normalized arm+field hashes; reuses normalized_type_annotation() (PROP-043 C1)
      classify(): result["variant_declarations"] = variant_decls unless variant_decls.empty?
    typechecker.rb changes (5 edits):
      typecheck(): @variant_shapes = variant_shapes(classified_program) after @type_shapes
      typecheck() result: result["variant_env"] = @variant_shapes unless @variant_shapes.empty?
      variant_shapes(classified_program) — 3-level builder (variant→arm→field→type_ir)
        mirrors type_shapes(); variant_type?(name); variant_arms(name); find_variant_for_arm(arm)
      infer_expr: when "variant_construct" / when "match_expr" before else→OOF-TY0
      infer_variant_construct: arm search; field validation; type_ir(variant_name) on success
      infer_match_expr: subject inference; OOF-KIND4 gate; per-arm narrowing; exhaustiveness;
        OOF-KIND1/2/3 checks; result type unification; degraded mode for non-variant/Unknown
      unify_match_arm_types: all-same→concrete; all-Unknown→Unknown; mixed-concrete→OOF-KIND5
    OOF-KIND codes now ACTIVE:
      OOF-KIND1: non-exhaustive match (missing arms, no wildcard)
      OOF-KIND2: undeclared arm/binding/field in construct or match pattern
      OOF-KIND3: unreachable arm (duplicate coverage)
      OOF-KIND4: match subject is not a variant type
      OOF-KIND5: divergent arm result types (concrete–concrete only; Unknown mix excluded)
    Key behaviors:
      Degraded mode: OOF-KIND4 fires; arm bodies still walked; Unknown result propagated
      Partial binding: absent fields in binding list do NOT fire OOF-KIND2 (intentional)
      Arm isolation: arm_scope = symbol_types.merge(arm_bindings); outer scope not mutated
      Output mismatch from degraded match: standard OOF-TY0 at output check (not suppressed)
    Closed: SemanticIR emitter; VM runtime; public/stable sum-type API
    ✅ Next: PROP-044-P6 CLOSED (50/50 PASS — SemanticIR emitter live; variant_decl/variant_construct/match_node; regressions clean)
    verify_prop044_p5_typechecker.rb: 75/75 PASS
      VTCK-SHAPES 5/5 | VTCK-CONSTRUCT-OK 5/5 | VTCK-CONSTRUCT-ERR 5/5 |
      VTCK-MATCH-OK 5/5 | VTCK-KIND1 5/5 | VTCK-KIND2-ARM 5/5 |
      VTCK-KIND2-BINDING 5/5 | VTCK-KIND3 5/5 | VTCK-KIND4 5/5 | VTCK-KIND5 5/5 |
      VTCK-SCOPE 5/5 | VTCK-UNIFY 5/5 | VTCK-DEGRADED 5/5 |
      VTCK-REGRESSION 5/5 | VTCK-BOUNDARY 5/5
    Regressions clean: PROP-043-P5 55/55 | OOF-R3 33/33 | loop_body 100/100 | P3-parser 50/50
    Card: igniter-lang/.agents/work/cards/lang/PROP-044-P5.md

45. ✅ PROP-044-P4: variant + match TypeChecker design (2026-06-09)
    Category: lang / governance / Track: variant-match-typechecker-and-oof-kind-planning-v0
    Route: TYPECHECKER DESIGN / NO IMPLEMENTATION
    Depends on: PROP-044-P3
    Design: @variant_shapes 3-level store (variant_name → arm_name → field_name → type_ir)
    Classifier bridge:
      New method variant_declarations(parsed_program) — reads parsed_program.fetch("variants", [])
        mirrors type_declarations(); reuses normalized_type_annotation() for PROP-043 C1
      Wired into classify() as result["variant_declarations"] = variant_decls unless empty
      TypeChecker reads via @variant_shapes = variant_shapes(classified_program)
    TypeChecker new methods:
      variant_shapes(classified_program) — builder (mirrors type_shapes())
      variant_type?(name), variant_arms(name), variant_arm_field_type(v,a,f), find_variant_for_arm(arm)
      infer_variant_construct — resolves variant by arm search; validates fields; returns type_ir(variant_name)
      infer_match_expr — resolves subject type; OOF-KIND4 gate; per-arm narrowed scopes;
        exhaustiveness (covered_arms set vs declared_arms set); OOF-KIND1/2/3; result unification
      infer_match_expr_degraded — walks arm bodies; returns Unknown; used when OOF-KIND4 fires
      unify_match_arm_types — all-same→concrete; all-Unknown→Unknown; mixed-concrete→OOF-KIND5
    infer_expr extension: when "variant_construct" / when "match_expr" → new handlers
      (replaces else→OOF-TY0 fallthrough for these two node kinds)
    OOF-KIND codes (reserved; activated in P5):
      OOF-KIND1: non-exhaustive match (missing arms, no wildcard)
      OOF-KIND2: undeclared arm/binding/field in construct or match pattern
      OOF-KIND3: unreachable arm (duplicate coverage or after wildcard)
      OOF-KIND4: match subject is not a variant type
      OOF-KIND5: divergent arm result types (concrete–concrete only; Unknown mix excluded)
    Per-arm scope: arm_symbol_types = symbol_types.merge(arm_bindings); not mutated; isolated
    Exhaustiveness: declared_arms.keys - covered_arms.keys; has_wildcard short-circuits
    Result propagation: variant_env added to typed_program (for SemanticIR P6 readiness)
    16 design decisions locked (DD-01..DD-16)
    Proof requirements for P5: 15 check groups, ~75-80 PASS gate
      VTCK-SHAPES, VTCK-CONSTRUCT-OK/ERR, VTCK-MATCH-OK, VTCK-KIND1..5,
      VTCK-SCOPE, VTCK-UNIFY, VTCK-DEGRADED, VTCK-REGRESSION, VTCK-BOUNDARY
    Closed: TypeChecker implementation; SemanticIR emitter; VM runtime; stable API
    ✅ Next: PROP-044-P5 CLOSED (75/75 PASS — OOF-KIND1..5 ACTIVE; infer_variant_construct; infer_match_expr)
    Design doc: igniter-lang/.agents/work/proposals/PROP-044-variant-match-typechecker-and-oof-kind-planning-v0.md
    Card: igniter-lang/.agents/work/cards/lang/PROP-044-P4.md

44. ✅ PROP-044-P3: variant + match parser implementation (2026-06-09)
    Category: lang / Track: variant-and-match-parser-proof-v0
    Route: PARSER IMPLEMENTATION / PROOF-LOCAL
    Depends on: PROP-044-P2
    Parser changes (8 edits to parser.rb):
      Lexer: fat_arrow (=>) — elsif peek(1) == ">" branch in "=" case
      Keywords: "variant" and "match" added to KEYWORDS array
      parse() accumulator: "variants" => [] added to program hash
      parse() dispatch: "variant" → program["variants"] << decl
      parse_top_decl: when "variant" → parse_variant_decl
      parse_primary kw branch: when "match" → parse_match_expr
      parse_primary ident branch: PascalCase + { peek → parse_variant_construct
      ParsedProgram#to_h: "variants" field + grammar_version "variant-v0" check
    New methods: parse_variant_decl, parse_variant_arm, parse_variant_construct,
                 parse_match_expr, parse_match_arm, parse_match_pattern
    Keyword fix: binding names in parse_match_pattern accept %i[ident keyword]
      (message, label, etc. are keywords from PROP-025; fixtures must avoid them as compute names)
    AST shapes confirmed: variant{name,arms[{name,fields}]}, variant_construct{arm,fields},
      match_expr{subject,arms[{pattern:{wildcard,arm,bindings},body}]}
    Conflict boundaries proved: type/record_literal/if/lowercase-ident all unaffected
    TypeChecker: no crash (passes unknown nodes); type_errors allowed; no OOF activation
    grammar_version: "variant-v0" for sources with variant decls or match/construct exprs
    All prior proofs clean after parser changes:
      PROP-043-P5: 55/55; PROP-042-P3: 45/45; OOF-R3: 34/34; loop_body: 100/100
    verify_prop044_p3_parser.rb: 50/50 PASS
      VPRS-KEYWORDS 5/5 | VPRS-UNIT 5/5 | VPRS-RECORD 5/5 | VPRS-MIXED 5/5 |
      VPRS-CONSTRUCT 5/5 | VPRS-MATCH 5/5 | VPRS-BINDINGS 5/5 | VPRS-INTEGRATE 5/5 |
      VPRS-CONFLICT 5/5 | VPRS-BOUNDARY 5/5
    Card: igniter-lang/.agents/work/cards/lang/PROP-044-P3.md
    ✅ Next: PROP-044-P4 CLOSED (TypeChecker design — @variant_shapes; classifier bridge; OOF-KIND1..5; 16 decisions)

43. ✅ LAB-QUERY-P2: QueryPlan pure builder proof (2026-06-09)
    Category: lang / Track: lab-query-plan-record-fixture-and-pure-builder-proof-v0
    Route: EXPERIMENTAL / LAB-ONLY
    Depends on: LAB-QUERY-P1, PROP-043-P5, LAB-VM-MAP-P1, LAB-RESULT-ENVELOPE-P2
    Types proved (7 — all expressible as named Records today; no grammar changes):
      QuerySource   { table:String, schema:String }
      Projection    { fields:String, include_all:Bool }
      FilterPredicate { field:String, op:String, value:String }
      OrderBy       { field:String, direction:String }
      QueryPlan     { kind:String, source_table, filter_field, filter_op, filter_value, order_field, order_dir, limit:Integer, metadata:Map[String,String] }
      QueryResult   { kind:String, count:Integer, message:String, metadata:Map[String,String] }
      StorageDenied { table:String, op:String, reason:String, kind:String }
    Contracts proved (6 — all pure/CORE; no IO; no StorageCapability):
      BuildQuerySource: QuerySource record construction
      BuildSelectQuery: full flat QueryPlan (kind="select")
      BuildFilteredQuery: simplified eq-filter plan (filter_op="eq"; limit=100)
      QueryResultDenied: denial-as-data (QueryResult{kind:"denied"}; no exception)
      QueryMetadataReader: map_get(result.metadata,"source")+or_else (C1 chain; 4th domain)
      QueryMapper: three-layer mapper (context→QueryResult; map_get(context,"message")+or_else)
    QueryResult kind vocabulary: rows / empty / denied / query_error / system_error
    C1 chain 4th domain: result.metadata→Map[String,String]→map_get→Option[String]→or_else→String
    KDR convention 4th domain: QueryResult follows kind+message+metadata shape
    "empty" kind: domain-specific to query (zero rows != error; not in ValidationResult/ContractResult)
    Two failure fixes (40→42): split string self-references + CLOSED-05 CORE-fragment proof
    ✅ Next: LAB-STORAGE-CAPABILITY-P1 CLOSED (IO.StorageCapability design-locked)
    ✅ Next: LAB-QUERY-P3 CLOSED (44/44 PASS — nested records; Collection[FilterPredicate]; chained field access; denial-as-data 8th proof)
    Next authorized: PROP-046 (grammar proposal); LAB-TC-ARRAY-P1 (Rust typechecker array_literal); LAB-EXECUTE-QUERY-P1 (ExecuteQuery effect contract + mocked StorageCapability)
    verify_lab_query_p2.rb: 42/42 PASS
      QPLAN-COMPILE 4/4 | QPLAN-TYPES 5/5 | QPLAN-BUILD 6/6 | QPLAN-DENIED 4/4 |
      QPLAN-MAP 4/4 | QPLAN-VM 5/5 | QPLAN-ROUTE 5/5 | QPLAN-COMPARE 4/4 | QPLAN-CLOSED 5/5

41. ✅ LAB-QUERY-P1: Query/Arel-like data access pressure boundary research (2026-06-09)
    Category: lang / Track: lab-query-arel-like-data-access-pressure-boundary-v0
    Route: RESEARCH / DESIGN / LAB-ONLY
    Depends on: PROP-043-P5, LAB-RESULT-ENVELOPE-P2, LAB-STDLIB-NET-P9, LAB-RACK-P14, LAB-SIDEKIQ-P5, LAB-CONCURRENCY-P4
    Core formula: Query v0 = typed intent AST + capability boundary + mocked execution
    QueryPlan v0 types (all expressible as named Records today — no new grammar):
      QuerySource { table:String, schema:String }
      Projection  { fields:Collection[String], include_all:Bool }
      FilterPredicate { field:String, op:String, value:String }  -- op: eq/neq/gt/gte/lt/lte/is_null
      OrderBy     { field:String, direction:String }
      QueryPlan   { source, projection, filters:Collection[FilterPredicate], order:Collection[OrderBy], limit:Integer, kind:String }
      QueryResult { kind:String, rows:Collection[Map[String,String]], count:Integer, message:String, metadata:Map[String,String] }
      StorageDenied { table:String, op:String, reason:String, kind:String }
    QueryResult kind vocabulary: rows / empty / denied / query_error / system_error
    Arel/ORM classification:
      Adopt: query-as-data, delayed execution, predicate composition, explicit projection, renderer/executor separation
      Permanently closed: ORM, ActiveRecord, lazy relations, global connection, callbacks, save!, implicit transactions, dynamic columns
      Deferred to v1: joins, aggregates, write ops, OR/NOT predicates, typed Row[T]
    Fragment classification: plan-building = CORE; execution (future) = ESCAPE → STORAGE class
    Capability boundary: IO.StorageCapability (follows PROP-035 model); pure plan-building needs none
    Denial-as-data: QueryResult{kind:"denied"} — never exception; 8th domain proof opportunity
    TBackend distinction: Store[T] = temporal substrate (PROP-008); QueryPlan = relational intent — orthogonal tracks
    ✅ Next: LAB-QUERY-P2 CLOSED (42/42 PASS — 6 contracts; 7 types; denial-as-data; C1 chain 4th domain)
    ✅ Next: LAB-STORAGE-CAPABILITY-P1 CLOSED (IO.StorageCapability design-locked)
    ✅ Next: LAB-QUERY-P3 CLOSED (44/44 PASS — nested records; Collection[FilterPredicate]; chained field access; denial-as-data)
    Next authorized: PROP-046 (StorageCapability grammar proposal); LAB-TC-ARRAY-P1 (Rust typechecker array_literal); LAB-EXECUTE-QUERY-P1 (ExecuteQuery + mocked StorageCapability)
    Doc: igniter-lab/lab-docs/lang/lab-query-arel-like-data-access-pressure-boundary-v0.md
    Card: igniter-lab/.agents/work/cards/lang/LAB-QUERY-P1.md

40. ✅ PROP-044-P1: Kind-discriminated outcome convention and sum type requirements (2026-06-09)
    Category: lang / governance / Track: kind-discriminated-outcome-convention-and-sum-type-requirements-v0
    Route: PROPOSAL AUTHORING ONLY
    Depends on: LAB-RESULT-ENVELOPE-P1, LAB-RESULT-ENVELOPE-P2, LAB-RACK-P14, LAB-SIDEKIQ-P5, PROP-043-P5
    Convention (today, no grammar needed):
      KDR pattern: type + kind:String + doc-declared vocabulary + Map[String,String] metadata
      3-domain corpus: HttpResult(3-kind), ContractResult(6-kind), ValidationResult(4-kind)
      Denial-as-data invariant: 7 proofs, cross-domain, design law (proven, unenforced)
      Three-layer composition: boundary → mapper → consumer; confirmed in 3 domains
    Grammar gap (blocks enforcement, not convention):
      variant declaration: OPEN (sealed kind vocabulary)
      exhaustive match: OPEN (OOF-KIND1 impossible without it)
      type narrowing: OPEN (post-match type refinement)
      OOF-KIND1..4: namespace reserved; not active until grammar lands
    Production implementation: BLOCKED (grammar must land first)
    Domain vocabularies: do not unify — each domain's kind space has local semantics
    Next authorized: PROP-044-P2 grammar proposal (variant+match design; requires explicit auth)
    Proposal: igniter-lang/.agents/work/proposals/PROP-044-kind-discriminated-outcome-convention-and-sum-type-requirements-v0.md
    Card: igniter-lang/.agents/work/cards/lang/PROP-044-P1.md

39. ✅ LAB-RESULT-ENVELOPE-P2: Third-domain kind-discriminant pressure proof (2026-06-09)
    Category: governance / Track: lab-result-envelope-third-domain-kind-discriminant-pressure-v0
    Route: EXPERIMENTAL / GOVERNANCE / LAB-ONLY
    Domain: Form validation and submission processing (orthogonal to HTTP and Sidekiq)
    Depends on: LAB-RESULT-ENVELOPE-P1, LAB-VM-MAP-P1, LAB-RACK-P14, LAB-SIDEKIQ-P5, PROP-043-P5
    ValidationResult: 4-kind envelope (valid/invalid/unauthorized/system_error)
      No HTTP status codes. No retry budget. No job identity fields.
      metadata: Map[String,String] for field context (rule, expected, field_name, etc.)
    P1 reclassifications:
      kind-discriminant: STRENGTHENED (2→3 domains; confirmed cross-domain)
      denial-as-data:    CONFIRMED CROSS-DOMAIN (6→7 proofs; unauthorized path in validation domain)
      Map[String,String]: CONFIRMED CROSS-DOMAIN (2→3 contexts; vr.metadata C1 chain works)
      three-layer composition: CONFIRMED (ValidationMapper = domain mapper in non-HTTP domain)
      budget-loop: DOMAIN-LOCAL (not universal; validation has no retry cycle)
      ContractResult name: CONFIRMED TOO GENERIC (HTTP-domain-bound; 6-kind space is HTTP-specific)
    PROP-044 status: deferred → PROPOSAL-AUTHORING ONLY authorized (3-domain bar met; grammar gap remains)
    VM executed: 6 contracts (ValidSubmission, MetadataInspector×2, ValidationMapper×2, UnauthorizedSubmission)
    verify_lab_result_envelope_p2.rb: 50/50 PASS
      VENV-COMPILE 4/4 | VENV-TYPES 5/5 | VENV-KINDS 6/6 | VENV-DENIED 4/4 | VENV-MAP 5/5 |
      VENV-VM 6/6 | VENV-ROUTE 5/5 | VENV-COMPARE 5/5 | VENV-PROMOTE 5/5 | VENV-CLOSED 5/5

34. ✅ PROP-043-P4: Map[K,V] production-edit planning (2026-06-09)
    Depends on: PROP-043-P3, PROP-043-P2, PROP-043-P1
    Scope: 2 files only — classifier.rb (1-line C1 fix at line 52: normalize_type → normalized_type_annotation)
        + typechecker.rb (~175 additive lines: MAP_STDLIB_FNS, infer_map_get/has_key/from_pairs/empty,
        infer_or_else, infer_array_literal, infer_record_literal, check_map_annotation, helpers,
        @output_type_hints pre-scan, OOF-MAP annotation scan, 2 infer_call arms, 2 infer_expr arms,
        1-line type_shapes C1 fix)
    SIR emitter: NO CHANGE — typed_ports + semantic_expr generic path already handle Map nodes
    parser.rb: NO CHANGE — Map annotations already parse; short names parse as call nodes
    P4-Q1..Q9 all resolved: insertion points exact; or_else confirmed absent (new addition);
        map_empty accepted as-is (C2, type_name equality only); from_pairs Unknown fallback silent;
        OOF-MAP wording templates locked; regression matrix defined (≥42 + T1/T2/T3 regressions)
    C1 fix: two-file (classifier.rb:52 + typechecker.rb:118) — normalized_type_annotation already exists
    C2 resolution: map_empty → Map[String,Unknown] passes type_name equality; context inference v1
    Track: igniter-lang/.agents/work/tracks/prop043-p4-map-kv-production-edit-planning-v0.md
    Card: igniter-lang/.agents/work/cards/lang/PROP-043-P4.md
    Next: PROP-043-P5 production implementation (classifier.rb + typechecker.rb + verify script)

---

## Workspace Repo Map

| Repo | Authority | Boundary |
|---|---|---|
| `igniter-lang` | Language canon: spec, proposals, grammar, compiler proof | Language meaning only |
| `igniter-lab` | Lab frontier: experiments, proofs, prototypes | Evidence only; not canon |
| `igniter-ruby` | Ruby Framework gem umbrella | Framework impl; not language spec |
| `igniter-org` | Public site (`igniter-lang.org`) | Projects current truth from lang/lab |
| `igniter-archive` | Recovery bucket from monorepo split | Not a default dependency |

**Monorepo note:** Workspace split from the `/igniter` monorepo. `igniter-archive` is the
quarantine bucket. Nothing there is a default dependency — review explicitly before pulling.

---

## Alignment Gaps

| Gap | Description | Action |
|---|---|---|
| NET-P2..P6 → lang | Lab delegation algebra has no grammar analog beyond PROP-035 | Runtime injection — Phase 2 |
| HTTP-TYPES → lang | ContractRef not in grammar; lab pressure only | Separate PROP when HTTP track matures |
| LAB-RACK-P2..P5 → lang | Static pipeline + ContractRef gap map + 5-route dispatch proven end-to-end on VM; TypeChecker == and < still open | LAB-RACK-P6 next (TypeChecker == and < alignment) |
| Web Framework → lang | LayoutEngine is lab-only; lab pressure only | Separate PROP when view track matures |
| PROP-039 loop impl | ✅ Gates 1+3+4+5+6+7+8 closed + Lab G1+G2+G3+G4+G5 conformance + Canon G5 recur() closed | lab Rust G5 symmetry closed 2026-06-08 — verify_g5_recur.rb 18/18 PASS |
| Lab G1 | ✅ closed 2026-06-07 — Rust lab parser accepts `loop Name item in source` | — |
| Lab G2 | ✅ closed 2026-06-07 — `recursive`/`fuel_bounded` contract modifiers + `decreases`/`max_steps` body decls | — |
| Lab G3 | ✅ closed 2026-06-08 — G3a OOF-R2/R4 in classifier + G3b FiniteLoop `for Name item in source` + G3c IR shape `kind="loop_node"` | — |
| Lab G4 | ✅ closed 2026-06-08 — `lead` keyword, OOF-L5/L7/L8, canon `body=[lead_node*,compute_node*]` + `item_type`, two-track `body`/`body_nodes`; verify_g4_body_semantics.rb 18/18 PASS | — |
| Canon G5 | ✅ closed 2026-06-08 — `recur()` context validation (OOF-R1), arity (OOF-R5), type (OOF-R6), single-output (OOF-R7), SemanticIR `recur_call` sub-expr; recursive_body_proof 100/100 PASS | — |
| Lab G5 | ✅ closed 2026-06-08 — OOF-R1/R5/R6/R7 in typechecker.rs, `recur_call` sub-expr in emitter.rs; verify_g5_recur.rb 18/18 PASS | — |
| Canon String Core | ✅ closed 2026-06-08 — 14 text stdlib ops (concat/trim/contains/starts_with/ends_with/split/replace/replace_all/byte_length/rune_length/grapheme_length/byte_slice/rune_slice/grapheme_slice); TEXT_STDLIB_FNS registry in typechecker.rb; string_core_proof 60/60 PASS | — |
| Lab String Core (Rust symmetry) | ✅ closed 2026-06-08 — typechecker.rs + emitter.rs; P2 concat disambiguation; verify_str_core.rb 29/29 PASS | — |
| Lab STR-CORE-P3 value semantics | ✅ closed 2026-06-08 — compile-time unit separation + SIR shapes + OOF enforcement proven; runtime-gated gaps documented; verify_str_value_semantics.rb 33/33 PASS | — |
| LAB-STR-UNICODE-P1 Unicode policy | ✅ design-locked 2026-06-08 — UTF-8 validity, UAX #29 grapheme, no normalization, bounds policy, `unicode-segmentation` lab recommendation, receipt design | — |
| LAB-STR-UNICODE-P2 Unicode VM ops | ✅ closed 2026-06-08 — 8 functional ops + qualified aliases + empty-input guards; UAX#29 runtime proven; 43/43 PASS | — |
| LAB-STR-UNICODE-P3 handler hygiene | ✅ closed 2026-06-08 — bare split guard aligned; unicode_runtime_receipt.json; 41/41 PASS | — |
| PROP-041 T2 structural-size P3/P4/P5 | ✅ closed 2026-06-08 — proof-local gate 48/48 PASS; formal proposal authored; grammar/OOF-R8/R9/SIR/trust locked | P6: production-edit planning authorization review |
| LAB-VM-MAP-P1 VM map_get/map_has_key | ✅ closed 2026-06-09 — map_get+map_has_key OP_CALL handlers (bare + qualified); compiler input field access fix; Value::Record = Map runtime; Rack P14 10/10; Sidekiq P5 MetadataReader VM closed; 48/48 PASS | — |
| experiments/ archive | ~150 experiments, Stage 1/2 closed | DA-005: archive pass (low priority) |

---

## Delegated Cards

| ID | Task | Status |
|---|---|---|
| DA-001 | current-status.md PROP-035/PROP-040 rows | ✅ DONE |
| DA-002 | PROP-031..039 status audit + §12 renumbering | ✅ DONE |
| DA-003 | lab-docs/lang IO capability grammar doc | ✅ DONE |
| DA-004 | portfolio-index.md | ✅ DONE (this file) |
| DA-005 | experiments/ archive pass (Stage 1/2) | ✅ DONE 2026-06-07 — 5→stage1, 7→stage2, 164 unknown left, 1 error (typechecker dir absent) |

---

## Meta Notes

**MFN-001 (Portfolio Meta-Architect → Portfolio Architect Supervisor, 2026-06-07):**
- PROP-040 queued before PROP-039 → both now closed
- CR-001/002/003 firewall rules adopted in language-covenant.md
- Rack/Web/Ruby pressure stays lab-only (CR-001)
- PROP-039 accepted as vocabulary authority; parallel track confirmed; implementation closed
