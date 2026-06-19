# Vector Editor Application

A domain-driven architectural prototype for a multi-layer vector editor in Igniter.

## Architecture

This application tests structural typing, optional values (`?`), multi-file dependencies, collection transforms, and pure UI command reducers.

1. **`types.ig`**: Defines canvas geometry (`Point`, `RectData`, `TextData`) and structural payloads. It uses a unified `GraphicObject` type because the source language does not yet expose a stable ADT/variant surface.
2. **`transform.ig`**: Contains deterministic coordinate translation (`TranslateObject`) over integer geometry.
3. **`document.ig`**: Handles nested layer-tree modifications. It uses `map` over layers and helper contracts for document updates.
4. **`tools.ig`**: Provides the primary command route (`HandleCanvasClick`) from document state, tool state, and click position to a new document.

## Pressure Docs

- [`report.md`](report.md) - live compiler findings and pressure analysis.
- [`PRESSURE_REGISTRY.md`](PRESSURE_REGISTRY.md) - concise pressure IDs and suggested routes.

## Current Compile Status

Real multi-file compile currently stops in both toolchains on the same first blocker:

```text
OOF-IMP2 unknown import path 'stdlib.collection' from module 'VectorDocument'
```

A temporary probe that removes only the stdlib collection import exposes downstream pressure around `append`, stringly `call_contract`, and text equality.

## Testing

Rust lab compiler:

```bash
cargo run -- compile ../igniter-apps/vector_editor/types.ig ../igniter-apps/vector_editor/transform.ig ../igniter-apps/vector_editor/document.ig ../igniter-apps/vector_editor/tools.ig --out /tmp/vector-editor-rust.igapp
```

Ruby canon compiler:

```bash
ruby -Ilib -e 'require "igniter_lang/compiler_orchestrator"; paths = %w[types.ig transform.ig document.ig tools.ig].map { |f| File.expand_path("../igniter-lab/igniter-apps/vector_editor/#{f}", __dir__) }; result = IgniterLang::CompilerOrchestrator.new.compile_sources(source_paths: paths, out_path: "/tmp/vector-editor-ruby.igapp"); puts JSON.pretty_generate(result)'
```
