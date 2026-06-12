# DSA Pressure Registry

Updated: 2026-06-12

This registry tracks app pressure from `igniter-apps/dsa`. It is evidence, not canon authority.

| ID | Status | Pressure | Evidence | Suggested route |
| --- | --- | --- | --- | --- |
| DSA-P01 | BASELINE | Full Rust multi-file compilation | Rust lab compiler emits complete `igapp`: 6 source units, 12 contracts, artifact hash `sha256:29ec2742e597236c797b1eca2a27cced4e300bcfddadc7f0fe059807e57fd8f6` | `LAB-DSA-BASELINE-P1` |
| DSA-P02 | POSITIVE | Array literals as `Collection[T]` | `[e0, e1, e2]`, `[100, 200]`, `[edge1, edge2, edge3]` compile in Rust | collection baseline docs/tests |
| DSA-P03 | ACTIVE | Collection concat Ruby parity | Rust accepts `concat(Collection, Collection)`; Ruby treats `concat` as `stdlib.text.concat` | `LANG-STDLIB-COLLECTION-CONCAT-P1` |
| DSA-P04 | ACTIVE | Deterministic equality | Ruby reports `Unsupported operator: ==` for integer comparisons in filters | `LANG-STDLIB-TEXT-EQUALITY-P3` |
| DSA-P05 | ACTIVE | Collection emptiness | `SetInsert` cannot branch on filtered match collection, so it behaves like multiset insert | `LANG-STDLIB-IS-EMPTY-PROP-P2/P3` |
| DSA-P06 | ACTIVE | Single-element extraction | `ArrayGet`, `CharAt`, `HasEdge` return matching collections, not scalar values | `LAB-STDLIB-FIND-ONE-P1` |
| DSA-P07 | WATCH | Indexed access complexity | `IndexedElement` workaround turns O(1) index access into O(n) scans | indexed access backlog |
| DSA-P08 | ACTIVE | Ruby invocation parity | Ruby reports 9 `Unknown function: call_contract` diagnostics | typed refs / invocation forms / Ruby parity follow-up |

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
- `concat` must be split cleanly between text and collection semantics.
- `is_empty` should come before `find_one`; scalar extraction needs fail-closed semantics.
