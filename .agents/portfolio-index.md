# igniter-lab: Portfolio Index

**Maintained by:** Portfolio Architect Supervisor
**Last updated:** 2026-06-09 (LAB-RACK-P11: call_contract TypeChecker literal callee resolution — 47/47 PASS)
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
| PROP-035: capability/effect_binding grammar + OOF-M2/M4/M5 | igniter-lang | ✅ experiment-pass | 64/64 |
| `lab-docs/lang/lab-igniter-lang-io-capability-grammar-v0.md` | igniter-lab | ✅ bridge doc | — |

**Boundary:** Canon grammar names IO types as opaque identifiers (CR-001). Schema, delegation
algebra, FFI, E-NET-* codes remain lab-only. Runtime injection is Phase 2.

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
| Grammar analog | igniter-lang | ❌ lab pressure only (CR-001 applies) | — |

**Alignment gap:** LAB-RACK-P2..P11 → lang | Static pipeline + ContractRef gap map + 5-route dispatch + TypeChecker == and < + VM entrypoint selector + explicit `call_contract` dispatch + literal callee type resolution implemented. Still open: multi-output callee (deferred), cross-contract cycle detection at compile time, ContractRef type semantics.

**Boundary:** HTTP types may not enter canon grammar without a cross-repo PROP + governance review.
Rack/middleware vocabulary is lab-only.

### Job Processing / Sidekiq (Lab only)

| Artifact | Repo | Status | Checks |
|---|---|---|---|
| LAB-SIDEKIQ-P1 (Sidekiq reimplementation feasibility and language pressure map — job-as-contract, dispatch table, BudgetedLocalLoop retry analogy, closed surfaces) | igniter-lab | ✅ RESEARCH COMPLETE | — |
| LAB-SIDEKIQ-P2 (static job dispatch table — 3 pure job contracts + JobDispatcher, VM-backed via lab-only `call_contract`, all fail-closed cases, P9 regression green) | igniter-lab | ✅ DONE | 54/54 |
| Grammar analog | igniter-lang | ❌ lab pressure only (CR-001 applies) | — |

**Alignment gap:** LAB-SIDEKIQ-P1..P2 → lang | Static job dispatch table proved using LAB-RACK-P9 `call_contract` with zero VM/compiler changes. P3 candidates: JobReceipt schema (P3a) or BudgetedLocalLoop retry policy (P3b). Effect-callee dispatch deferred until P10/P11 clarify `call_contract` output typing. Still open: async execution, queue storage, retry policy, non-uniform arity dispatch.

**Boundary:** Job processing vocabulary is lab-only. No Sidekiq compatibility claim. No StorageCapability, ServiceLoop, or scheduler surfaces open. `call_contract` is lab-only with no stable API.

### Web Framework / View Engine (Lab only)

| Artifact | Repo | Status | Checks |
|---|---|---|---|
| LAB-WEB-FRAMEWORK-P4 (LayoutEngine, fill_slot, render, inheritance) | igniter-lab | ✅ DONE | ~45/45 |
| Grammar analog | igniter-lang | ❌ lab-only for now | — |

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
28. ✅ LAB-TERM-T2-P2: OOF-R9 branch and multi-recur edge hardening (2026-06-08)
    Root cause: check_t2_callsite_in_expr IfExpr arm only walked cond, not then/else_block bodies
    Fix: extended IfExpr arm to mirror check_recur_in_expr exactly (stmts + return_expr for both branches)
    5 new fixtures: multi_recur_both_correct, multi_recur_one_wrong, if_both_branches_correct,
      if_wrong_else_branch, nested_arith_wrong
    Proven: mixed correct/wrong fails closed; correct site does NOT suppress wrong-site OOF-R9
    OOF-R3/R8 precedence unchanged; T1 syntactic_v0 unaffected; no new OOF codes; no canon changes
    verify_t2_oof_r9_edge_cases.rb: 21/21 PASS
    Regression: verify_t2_structural_size_relation.rb 52/52; verify_oof_r3.rb 34/34; verify_g5_recur.rb 18/18
    LAB-TERM-T2 track complete (P1+P2). Next: PROP-041 T3 (numeric measures) when authorized.

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
