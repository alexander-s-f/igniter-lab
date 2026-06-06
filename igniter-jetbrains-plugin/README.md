# Igniter JetBrains Plugin Lab Prototype

This package contains an experimental JetBrains IDE plugin for Igniter Lang lab workflows.

It is a lab-only tooling prototype inside `igniter-lab`. It is not a Marketplace release, supported public IDE product, stable plugin API, production distribution, canonical language authority, or release artifact. The plugin exists to explore editor support for `.ig` files, compiler diagnostics, SemanticIR/artifact inspection, structure views, completion, references, and tool-window workflows.

## Current Surface

- `.ig` file type registration and syntax highlighting.
- Basic lexer/parser/structure-view integration.
- Completion and reference experiments.
- Compiler service and external annotator hooks for OOF diagnostics.
- Actions for compiling current files and opening SemanticIR artifacts.
- Tool window and settings panel prototypes.

## Lab Boundaries

- `.gradle/`, `.idea/`, `build/`, local caches, logs, and packaged plugin artifacts stay out of git.
- This package may cite lab evidence, but it must not present lab behavior as canonical language support.
- Publishing, signing, Marketplace upload, release/version claims, and public support claims require a separate review.

## Useful Commands

```bash
./gradlew check
./gradlew buildPlugin
```

`buildPlugin` creates local artifacts under `build/`; those outputs are intentionally ignored.
