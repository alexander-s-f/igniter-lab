# Vector Math Library for Igniter

A mathematical vector library written in Igniter, providing Vec2, Vec3, Mat3, AABB, and geometric utilities. This app is currently a positive baseline: the Rust lab compiler compiles all six files through `parse -> classify -> typecheck -> emit -> assemble` and produces a complete `igapp` artifact.

## Architecture

```text
types.ig     -> Vec2, Vec3, Vec4, Mat3, Ray, AABB, ScalarResult
vec2.ig      -> Vec2 operations: add, sub, scale, dot, length squared, etc.
vec3.ig      -> Vec3 operations: add, sub, scale, cross, reflect, min/max, etc.
mat3.ig      -> 3x3 matrix operations: identity, transpose, mul vec, determinant, transforms
geometry.ig  -> AABB, overlap, distance, midpoint utilities
example.ig   -> simulation, transform, triangle, and collision examples
```

## Milli-Unit Convention

Since the current language surface does not yet have mature Float/Decimal operator semantics, all values use an Integer milli-unit convention:

- `1000` = 1.0
- `500` = 0.5
- `707` is approximately `cos(45deg)` / `sin(45deg)`

This keeps the app deterministic and compile-ready, while preserving pressure for a future fixed-point or scale-aware numeric model.

## Pressure Docs

- [`report.md`](report.md) - live compiler findings and pressure analysis.
- [`PRESSURE_REGISTRY.md`](PRESSURE_REGISTRY.md) - concise pressure IDs and suggested routes.

## Current Compile Status

Rust lab compiler:

```text
status: ok
contracts: 37
source units: 6
artifact hash: sha256:289a586aeb172ccc35a55e23f5f400194d14cf8cbb246120881c205bb3ea3d9a
```

Ruby canon compiler currently reports `oof`, dominated by missing `call_contract` support and numeric comparison parity.

## Testing

Rust lab compiler:

```bash
cargo run -- compile ../igniter-apps/vector_math/types.ig ../igniter-apps/vector_math/vec2.ig ../igniter-apps/vector_math/vec3.ig ../igniter-apps/vector_math/mat3.ig ../igniter-apps/vector_math/geometry.ig ../igniter-apps/vector_math/example.ig --out /tmp/vector-math-rust.igapp
```

Ruby canon compiler:

```bash
ruby -Ilib -e 'require "igniter_lang/compiler_orchestrator"; paths = %w[types.ig vec2.ig vec3.ig mat3.ig geometry.ig example.ig].map { |f| File.expand_path("../igniter-lab/igniter-apps/vector_math/#{f}", __dir__) }; result = IgniterLang::CompilerOrchestrator.new.compile_sources(source_paths: paths, out_path: "/tmp/vector-math-ruby.igapp"); puts JSON.pretty_generate(result)'
```
