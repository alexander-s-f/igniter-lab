# Data Structures & Algorithms in Igniter

A demonstration of arrays, sets, graphs, and string-like algorithms implemented in Igniter. This app is a positive Rust baseline: it compiles through `parse -> classify -> typecheck -> emit -> assemble` and produces a complete `igapp` artifact with 12 contracts.

## Implementations

### 1. Arrays (`DSAArrays`)

Igniter lacks native array indexing. Arrays are simulated by wrapping values in `IndexedElement { index, value }`.

- `ArrayGet`: O(n) search using `filter`
- `ArraySet`: O(n) update using `map`

### 2. Sets (`DSASets`)

Simulated on top of `Collection[Integer]`.

- `SetContains`: O(n) using `filter`
- `SetInsert`: appends with `concat(s.elements, [item])`

Without `is_empty`, insertion cannot check for pre-existing membership, so the current implementation behaves like a multiset insert.

### 3. Graphs (`DSAGraphs`)

Adjacency list representation: `Edge { from_node, to_node, weight }`.

- `GetAdjacent`: O(n) filtering over all edges
- `HasEdge`: O(n) filtered edge existence check

### 4. Strings (`DSAStrings`)

Strings are opaque at the current source level, so this app models a manipulable string as `Collection[IndexedElement]` holding character codes.

- `CharAt`: O(n) search using `filter`

## Pressure Docs

- [`report.md`](report.md) - live compiler findings and pressure analysis.
- [`PRESSURE_REGISTRY.md`](PRESSURE_REGISTRY.md) - concise pressure IDs and suggested routes.

## Current Compile Status

Rust lab compiler:

```text
status: ok
contracts: 12
source units: 6
artifact hash: sha256:29ec2742e597236c797b1eca2a27cced4e300bcfddadc7f0fe059807e57fd8f6
```

Ruby canon compiler currently reports `oof`, dominated by equality, collection concat parity, and `call_contract` invocation gaps.

## Testing

Rust lab compiler:

```bash
cargo run -- compile ../igniter-apps/dsa/types.ig ../igniter-apps/dsa/arrays.ig ../igniter-apps/dsa/sets.ig ../igniter-apps/dsa/graphs.ig ../igniter-apps/dsa/strings.ig ../igniter-apps/dsa/example.ig --out /tmp/dsa-rust.igapp
```

Ruby canon compiler:

```bash
ruby -Ilib -e 'require "igniter_lang/compiler_orchestrator"; paths = %w[types.ig arrays.ig sets.ig graphs.ig strings.ig example.ig].map { |f| File.expand_path("../igniter-lab/igniter-apps/dsa/#{f}", __dir__) }; result = IgniterLang::CompilerOrchestrator.new.compile_sources(source_paths: paths, out_path: "/tmp/dsa-ruby.igapp"); puts JSON.pretty_generate(result)'
```
