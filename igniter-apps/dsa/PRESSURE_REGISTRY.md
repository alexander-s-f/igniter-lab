# DSA Pressure Registry

Updated: 2026-06-12 (APP-RECHECK-WAVE-P1)

This registry tracks app pressure from `igniter-apps/dsa`. It is evidence, not canon authority.

| ID | Status | Pressure | Evidence | Suggested route |
| --- | --- | --- | --- | --- |
| DSA-P01 | BASELINE | Full Rust multi-file compilation | Rust lab compiler emits complete `igapp`: 6 source units, 12 contracts, artifact hash `sha256:29ec2742e597236c797b1eca2a27cced4e300bcfddadc7f0fe059807e57fd8f6` — still CLEAN in wave recheck | `LAB-DSA-BASELINE-P1` |
| DSA-P02 | POSITIVE | Array literals as `Collection[T]` | `[e0, e1, e2]`, `[100, 200]`, `[edge1, edge2, edge3]` compile in Rust | collection baseline docs/tests |
| DSA-P03 | RESOLVED | Collection concat Ruby parity | `infer_concat_call` now routes by first-arg type (Collection→collection path; Text/other→text path) per LANG-STDLIB-COLLECTION-CONCAT-PROP-P3; no concat TC errors in wave recheck | `LANG-STDLIB-COLLECTION-CONCAT-PROP-P3` |
| DSA-P04 | RESOLVED | Deterministic equality | `==` now in `operator_type` via LANG-STDLIB-TEXT-EQUALITY-P3; UTF-8-stripped Ruby recheck shows 0 equality errors; no `Unsupported operator: ==` in any diagnostic | `LANG-STDLIB-TEXT-EQUALITY-P3` CLOSED |
| DSA-P05 | READY | Collection emptiness | `is_empty`/`non_empty` now available (LANG-STDLIB-IS-EMPTY-PROP-P3/P4 CLOSED); `SetInsert` workaround in sets.ig is now stale — proper set semantics (filter+is_empty branch) are implementable without language changes | App code can be updated; `LAB-STDLIB-FIND-ONE-P1` for scalar extraction |
| DSA-P06 | ACTIVE | Single-element extraction | `ArrayGet`, `CharAt`, `HasEdge` return matching collections, not scalar values | `LAB-STDLIB-FIND-ONE-P1` |
| DSA-P07 | WATCH | Indexed access complexity | `IndexedElement` workaround turns O(1) index access into O(n) scans | indexed access backlog |
| DSA-P08 | ACTIVE | Ruby call_contract parity | UTF-8-stripped recheck: 9 `Unknown function: call_contract` (arrays.ig:1 + example.ig:8); Ruby TC has no call_contract dispatch arm; cascades to 15 total diagnostics including Type mismatch | call_contract parity follow-up |
| DSA-P09 | ACTIVE | Ruby emitter UTF-8 encoding | `types.ig` contains box-drawing chars (U+2500 `──`) in comments; Ruby JSON serializer crashes with `JSON::GeneratorError: "\xE2" on US-ASCII`; masks TC diagnostic output in unstripped runs; newly surfaced because TC-level errors (DSA-P03/P04) are resolved | `LANG-EMITTER-ENCODING-P1` |

## Live Commands Used

Rust real compile:

```bash
cargo run -- compile ../igniter-apps/dsa/types.ig ../igniter-apps/dsa/arrays.ig ../igniter-apps/dsa/sets.ig ../igniter-apps/dsa/graphs.ig ../igniter-apps/dsa/strings.ig ../igniter-apps/dsa/example.ig --out /tmp/dsa-rust.igapp
```

Ruby real compile:

```bash
ruby -Ilib -e 'require "igniter_lang/compiler_orchestrator"; paths = %w[types.ig arrays.ig sets.ig graphs.ig strings.ig example.ig].map { |f| File.expand_path("../igniter-lab/igniter-apps/dsa/#{f}", __dir__) }; result = IgniterLang::CompilerOrchestrator.new.compile_sources(source_paths: paths, out_path: "/tmp/dsa-ruby.igapp"); puts JSON.pretty_generate(result)'
```

## Notes

- Treat this app as a positive Rust baseline and an algorithmic pressure map.
- `concat` is resolved in Ruby TC; Rust P4 (parity) still pending per LANG-STDLIB-COLLECTION-CONCAT-PROP-P2 implementation plan.
- `is_empty`/`non_empty` are now available; `SetInsert` comment in sets.ig is stale.
- `call_contract` parity is the dominant remaining Ruby blocker (9 calls across arrays.ig + example.ig).
- UTF-8 encoding issue in types.ig comments masks TC diagnostics; see DSA-P09.
