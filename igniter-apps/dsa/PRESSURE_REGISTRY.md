# DSA Pressure Registry

Updated: 2026-06-14 (APP-RECHECK-WAVE-P10 — DUAL-CLEAN)

This registry tracks app pressure from `igniter-apps/dsa`. It is evidence, not canon authority.

| ID | Status | Pressure | Evidence | Suggested route |
| --- | --- | --- | --- | --- |
| DSA-P01 | BASELINE | Full Rust multi-file compilation | Rust lab compiler emits complete `igapp`: 6 source units, 12 contracts, source_hash `sha256:94b3376fd224ea008708deb1c6cc0ed0305c1f36ce78df651b9edfb6ca8d57c5` — still CLEAN in Wave P2 recheck (hash reflects compiler-side SIR changes from concat/append/is_empty Rust parity) | `LAB-DSA-BASELINE-P1` |
| DSA-P02 | POSITIVE | Array literals as `Collection[T]` | `[e0, e1, e2]`, `[100, 200]`, `[edge1, edge2, edge3]` compile in Rust | collection baseline docs/tests |
| DSA-P03 | RESOLVED | Collection concat Ruby parity | `infer_concat_call` now routes by first-arg type (Collection→collection path; Text/other→text path) per LANG-STDLIB-COLLECTION-CONCAT-PROP-P3; no concat TC errors in wave recheck | `LANG-STDLIB-COLLECTION-CONCAT-PROP-P3` |
| DSA-P04 | RESOLVED | Deterministic equality | `==` now in `operator_type` via LANG-STDLIB-TEXT-EQUALITY-P3; UTF-8-stripped Ruby recheck shows 0 equality errors; no `Unsupported operator: ==` in any diagnostic | `LANG-STDLIB-TEXT-EQUALITY-P3` CLOSED |
| DSA-P05 | READY | Collection emptiness | `is_empty`/`non_empty` now available (LANG-STDLIB-IS-EMPTY-PROP-P3/P4 CLOSED); `SetInsert` workaround in sets.ig is now stale — proper set semantics (filter+is_empty branch) are implementable without language changes | App code can be updated; `LAB-STDLIB-FIND-ONE-P1` for scalar extraction |
| DSA-P06 | ACTIVE | Single-element extraction | `ArrayGet`, `CharAt`, `HasEdge` return matching collections, not scalar values | `LAB-STDLIB-FIND-ONE-P1` |
| DSA-P07 | WATCH | Indexed access complexity | `IndexedElement` workaround turns O(1) index access into O(n) scans | indexed access backlog |
| DSA-P08 | RESOLVED | Ruby call_contract parity | Wave P2: 15 total diagnostics (9× `Unknown function: call_contract`, 3× `Unresolved symbol`, 3× `Output type mismatch`). Wave P3: all 9 call_contract errors gone; `LAB-RUBY-CALL-CONTRACT-PARITY-P3` CLOSED; Ruby TC `when "call_contract"` arm now dispatches Tier 1 same-module callee lookup | `LAB-RUBY-CALL-CONTRACT-PARITY-P3` CLOSED |
| DSA-P09 | RESOLVED | Ruby emitter UTF-8 encoding | LANG-EMITTER-ENCODING-P2 CLOSED — 6 encoding sites fixed (compiler_orchestrator.rb:56, multifile_resolver.rb:96, cli.rb:83, experimental_igc_run.rb:136/147, experimental_igc_run_vm_candidate.rb:260); Wave P2 unstripped Ruby compile succeeds without JSON crash; 15 real diagnostics now surface | `LANG-EMITTER-ENCODING-P2` CLOSED |
| DSA-P10 | RESOLVED | Ruby record literal inference gap | Wave P3: 4 `Unresolved symbol` diags remain — `e0`, `s`, `edge1`, `c_h`. Wave P4: unchanged — LANG-TYPED-COMPUTE-BINDING-P2 had no effect. Root cause re-classified: computes use unannotated record literals (`compute e0 = { index: 0, value: 10 }`, `compute edge1 = { from_node: 0, ... }`); Ruby TC `infer_record_literal` returns Unknown when no output_type_hint is set; bind type Unknown → downstream OOF-P1. Wave P6: LANG-RUBY-RECORD-LITERAL-INFERENCE-P3 resolved all 4 symbols: `e0` → `IndexedElement`, `s` → `IntSet`, `edge1` → `Edge`, `c_h` → `Cell` | `LANG-RUBY-RECORD-LITERAL-INFERENCE-P3` CLOSED |

## Live Commands Used

Rust real compile:

```bash
cargo run -- compile ../igniter-apps/dsa/types.ig ../igniter-apps/dsa/arrays.ig ../igniter-apps/dsa/sets.ig ../igniter-apps/dsa/graphs.ig ../igniter-apps/dsa/strings.ig ../igniter-apps/dsa/example.ig --out /tmp/dsa-rust.igapp
```

Ruby real compile:

```bash
ruby -Ilib -e 'require "igniter_lang/compiler_orchestrator"; paths = %w[types.ig arrays.ig sets.ig graphs.ig strings.ig example.ig].map { |f| File.expand_path("../igniter-lab/igniter-apps/dsa/#{f}", __dir__) }; result = IgniterLang::CompilerOrchestrator.new.compile_sources(source_paths: paths, out_path: "/tmp/dsa-ruby.igapp"); puts JSON.pretty_generate(result)'
```

## Wave P2 Recheck Summary (2026-06-12)

Rust: CLEAN (status ok, 0 diagnostics, all 5 stages ok). Ruby: 15 diagnostics (9× `Unknown function: call_contract`, 3× `Unresolved symbol`, 3× `Output type mismatch`). DSA-P09 RESOLVED — LANG-EMITTER-ENCODING-P2 fixed 6 encoding sites; unstripped Ruby compile no longer crashes; actual diagnostic surface now visible. Dominant remaining Ruby blocker: call_contract parity (DSA-P08). Rust concat/append/is_empty parity complete (P4 cards CLOSED).

## Wave P6 Recheck Summary (2026-06-13)

Rust: ok / 0 diagnostics — unchanged. Ruby: **ok / 0 diagnostics — DUAL-TOOLCHAIN CLEAN** (was 4). LANG-RUBY-RECORD-LITERAL-INFERENCE-P3 resolved all 4 ACTIVE_TRUE_INTERMEDIATE symbols: `e0` → `IndexedElement`, `s` → `IntSet` (disambiguated by `Collection[Integer]` vs `Collection[IndexedElement]` via `structurally_assignable?`), `edge1` → `Edge`, `c_h` → `Cell`. DSA-P10 RESOLVED. No new pressures. No regressions. **DSA is now dual-toolchain CLEAN (first since Wave P3 when AL achieved it).**

## Wave P5 Recheck Summary (2026-06-13)

Rust: ok / 0 diagnostics — unchanged from Wave P4. Ruby: oof / 4 diagnostics — unchanged from Wave P4. LANG-RUBY-RECORD-LITERAL-INFERENCE-P2 had zero effect: DSA-P10 computes (`e0`, `s`, `edge1`, `c_h`) are unannotated record literals — P2 only activates for `compute name : Type = { ... }` annotated forms. DSA-P10 (ACTIVE_TRUE_INTERMEDIATE): 4 unannotated record literal computes still Unknown. No new pressures.

## Wave P4 Recheck Summary (2026-06-13)

Rust: CLEAN (ok / 0 diagnostics). Ruby: oof / 4 diagnostics — unchanged from Wave P3. LANG-TYPED-COMPUTE-BINDING-P2 had zero effect: affected computes are unannotated record literals (`compute e0 = { ... }`), not `compute name : Type = expr` annotated bindings; P2 only applies to annotated computes. Root cause re-classified: DSA-P10 route updated to `LANG-RUBY-RECORD-LITERAL-INFERENCE-P1`. No new pressures.

## Wave P3 Recheck Summary (2026-06-13)

Rust: CLEAN (ok / 0 diagnostics). Ruby: oof / 4 diagnostics — `Unresolved symbol: e0`, `Unresolved symbol: s`, `Unresolved symbol: edge1`, `Unresolved symbol: c_h`. Resolutions since Wave P2: DSA-P08 RESOLVED — LAB-RUBY-CALL-CONTRACT-PARITY-P3 CLOSED; Ruby TC `when "call_contract"` arm handles Tier 1 same-module callee lookup; 9 call_contract errors eliminated; 3 output mismatch cascades also cleared. Remaining blockers: 4 unresolved symbols — typed compute binding gap (DSA-P10); call_contract output variables not registered in symbol_types.

## Notes

- Treat this app as a positive Rust baseline and an algorithmic pressure map.
- `concat`, `append`, `is_empty`/`non_empty` are all dual-toolchain; Rust Parity cards CLOSED.
- `is_empty`/`non_empty` are now available; `SetInsert` comment in sets.ig is stale (DSA-P05 READY).
- `call_contract` parity (DSA-P08) is RESOLVED — LAB-RUBY-CALL-CONTRACT-PARITY-P3 CLOSED.
- UTF-8 encoding (DSA-P09) is resolved; types.ig box-drawing chars no longer crash the Ruby compiler.
- DSA-P10 RESOLVED (Wave P6: LANG-RUBY-RECORD-LITERAL-INFERENCE-P3 — e0/s/edge1/c_h all infer correct types). DSA is now DUAL-TOOLCHAIN CLEAN.

## Wave P7 Recheck Summary (2026-06-13)

Rust: ok / 0 diagnostics — unchanged. Ruby: ok / 0 diagnostics — unchanged. DUAL-TOOLCHAIN CLEAN (DSA-P10 RESOLVED in Wave P6). No pressure ID changes this wave. No new pressures.

## Wave P8 Recheck Summary (2026-06-13)

Rust: ok / 0 diagnostics — unchanged. Ruby: ok / 0 diagnostics — unchanged. DUAL-TOOLCHAIN CLEAN. LANG-STRING-TEXT-ALIAS-P2, LANG-RUBY-RECORD-LITERAL-INFERENCE-P5, LANG-STDLIB-STRING-SUBSTRING-P2, and LAB-BLOOM-FILTER-RANGE-MIGRATION-P1 had no effect on this app. No new pressures. No regressions.

## Wave P9 Recheck Summary (2026-06-13)

Rust: ok / 0 diagnostics — unchanged. Ruby: ok / 0 diagnostics — unchanged. DUAL-TOOLCHAIN CLEAN. LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P4, LAB-VE-NEW-OBJ-INFERENCE-P1, LAB-VECTOR-MATH-FIELD-ALIGNMENT-P1, LAB-HOF-LAMBDA-ERROR-PROPAGATION-P2, and LAB-PARSER-RECORD-IN-HOF-P1 had no effect on this app. No new pressures. No regressions.

## Wave P10 Recheck Summary (2026-06-14)

Rust: ok / 0 diagnostics — unchanged. Ruby: ok / 0 diagnostics — unchanged. DUAL-TOOLCHAIN CLEAN. No pressure ID changes this wave. No new pressures. No regressions.
