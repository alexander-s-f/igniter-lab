# DSA Pressure Registry

Updated: 2026-06-12 (APP-RECHECK-WAVE-P2)

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
| DSA-P08 | ACTIVE | Ruby call_contract parity | Wave P2 unstripped recheck: 15 total diagnostics (9× `Unknown function: call_contract`, 3× `Unresolved symbol`, 3× `Output type mismatch`); Ruby TC has no call_contract dispatch arm; dominant Ruby blocker | call_contract parity follow-up |
| DSA-P09 | RESOLVED | Ruby emitter UTF-8 encoding | LANG-EMITTER-ENCODING-P2 CLOSED — 6 encoding sites fixed (compiler_orchestrator.rb:56, multifile_resolver.rb:96, cli.rb:83, experimental_igc_run.rb:136/147, experimental_igc_run_vm_candidate.rb:260); Wave P2 unstripped Ruby compile succeeds without JSON crash; 15 real diagnostics now surface | `LANG-EMITTER-ENCODING-P2` CLOSED |

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

## Notes

- Treat this app as a positive Rust baseline and an algorithmic pressure map.
- `concat`, `append`, `is_empty`/`non_empty` are all dual-toolchain; Rust Parity cards CLOSED.
- `is_empty`/`non_empty` are now available; `SetInsert` comment in sets.ig is stale (DSA-P05 READY).
- `call_contract` parity is the dominant remaining Ruby blocker (DSA-P08); 9 calls across arrays.ig + example.ig.
- UTF-8 encoding (DSA-P09) is resolved; types.ig box-drawing chars no longer crash the Ruby compiler.
