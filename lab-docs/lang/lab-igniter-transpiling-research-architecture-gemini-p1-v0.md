# lab-igniter-transpiling-research-architecture-gemini-p1-v0 — Projection dialect transpiling architecture survey

**Delegation-Code:** `GEMINI-20260618-TRANSPILING-A`  
**Card Reference:** `.agents/work/cards/lang/LAB-IGNITER-TRANSPILING-RESEARCH-ARCHITECTURE-GEMINI-P1.md`  
**Status:** RESEARCH REPORT (v0; recommendations are backlog ideas, not authority)  
**Scope:** Architecture survey for projection dialect lowerers (`.ig*`). **No code changes, no CLI tooling implementation, and no canon specifications.**

---

## 1. Executive Summary

This report surveys the architecture of **Projection Dialects** in the Igniter ecosystem, building on
the governance boundaries established in `lab-docs/lang/lab-igniter-projection-dialects-p0-v0.md`.

A Projection Dialect is an authoring syntax (e.g., `.igv`, `.igweb`) that lowers deterministically into a canonical, inspectable Igniter artifact without introducing new runtime authority. This survey analyzes the live lowerer implementations in `igniter-lab`, defines a common compiler pipeline, evaluates target artifacts, and outlines recommended future design paths for shared dialect tooling.

---

## 2. Survey of Existing Lowerers (Architecture Facts)

We analyze the two active dialect lowerers currently implemented in `igniter-lab`:

### The `.igv` Lowerer (View Dialect)
* **Location:** `igniter-ui-kit/src/igv.rs`
* **Target:** `ViewArtifact` JSON (consumed by `FrameRuntime` and UI bindings).
* **Shape:** A line-oriented parser that tokenizes inputs (using custom string and list delimiters), compiles components into a temporary `ActionBuilder` map, and serializes them into a `serde_json::Value` object.
* **Invariants:** Pure, machine-free execution. Determinism is achieved by relying on `serde_json` default map sorting (keys alphabetical, arrays ordered).

### The `.igweb` Lowerer (Routing Dialect)
* **Location:** `igniter-compiler/src/igweb.rs`
* **Target:** Generated `.ig` source code (module `AppRoutes`, exposing `Serve(Request) -> Decision`).
* **Shape:** A line-oriented parser that extracts HTTP routes, maps parameters to regex capture groups, and generates a nested `if-else` matching tree that utilizes the static `call_contract` primitive.
* **Invariants:** Outputs pure string text representation of `.ig` code. Determinism is achieved by preserving source-ordering during compilation (no map key iterations in the generator).

---

## 3. Recommended Common Lowerer Pipeline (Architecture Recommendations)

To prevent dialects from writing custom parsing hacks, a unified compiler pipeline model is recommended for all `.ig*` lowerers:

```text
 [Source Dialect Text]
         │
         ▼
 ┌───────────────┐
 │ Lexer / Token │  ──► Splits tokens, keeping track of line numbers and delimiters
 └───────────────┘
         │
         ▼
 ┌───────────────┐
 │  Dialect AST  │  ──► Validates structure, performs semantic and naming audits
 └───────────────┘
         │
         ▼
 ┌───────────────┐
 │ Transformation│  ──► Performs optimizations and maps dialect nodes to target formats
 └───────────────┘
         │
         ▼
 ┌───────────────┐
 │ Target Emit   │  ──► Serializes deterministic output (sorted JSON, formatted .ig)
 └───────────────┘
```

1. **Lexing & Parsing (Shared):** Clean comment removal, whitespace tokenization, and matching brackets/quotes.
2. **Intermediate Dialect AST (Dialect-Local):** Rather than emitting strings or JSON directly from raw tokens, lowerers should parse into a structured, intermediate Dialect AST (e.g. `Route` struct in `.igweb`). This allows sorting, grouping, and duplicate-key verification before rendering.
3. **Line-Positioned Diagnostics (Shared):** Errors must map directly to the original dialect line number using a standard error container (`line: usize, message: String`).
4. **Target Compilation & Verification (Shared):** Output must be compiled (`.ig`) or schema-validated (`JSON`) through the real Igniter pipeline before completion, proving target compatibility.

---

## 4. Legitimate Target Artifacts & Generated Code Policy

### Legitimate Target Kinds (v0)
Only canonical, inspectable artifacts already understood by the Igniter runtime are valid targets:
* **`.ig` source text**: For executable route trees, validation contracts, and logic pipelines.
* **`ViewArtifact` JSON**: For layout composition and bindings.
* **`Manifest / ServiceRecipe` JSON**: For deployment and duplicate policies.

### Generated Artifact Policy
To ensure project transparency and support manual audits:
* **Committed generated files (Recommended default)**: Generated files must be written directly to the project directories and checked into source control (marked with a warning comment, e.g. `-- GENERATED, DO NOT EDIT`). This allows developers to track mutations in code reviews.
* **Build-Cache / Ephemeral compilation**: Permitted only in development servers (hot-reload test fixtures) where intermediate file writing incurs unacceptable I/O latency.

---

## 5. Determinism & Byte-Stability

Lowerers must guarantee that identical inputs generate bit-for-bit identical outputs:
* **Map Serialization**: JSON maps must enforce sorted keys (e.g. alphabetical `BTreeMap` sorting).
* **Array Ordering**: Iterating over lists (such as routes or fields) must preserve source declaration order. Hash maps and non-ordered collections must not be iterated during output generation.
* **No Side-Effects**: Generators must remain pure, forbidding any usage of system clocks, random number generators, or network resources.

---

## 6. Shared vs. Dialect-Local Boundaries (Future Crate Design)

If a future `igniter-dialect` crate is implemented, it should divide responsibilities as follows:

| Shared in `igniter-dialect` | Local to Dialect Crate |
|---|---|
| **Tokenizer helpers** (delimiter-aware splits) | **Grammar & Lexing rules** (specific keywords) |
| **Diagnostic formatter** (IDE-friendly error strings) | **Dialect AST definitions** (e.g. `ActionBuilder`) |
| **Deterministic JSON serializer** (alphabetical key output) | **Semantic validation checks** (e.g. select field checks) |
| **Line-to-Line Source Map structures** | **Code generation formatting templates** |

---

## 7. Concrete Future Card Ideas (Recommended Backlog)

### Idea 1: `LAB-IGNITER-DIALECT-CRATE-P1` (Shared Library)
* **Goal**: Implement a minimal `igniter-dialect` library in `igniter-lab` that exports shared tokenizers, the `Lowerer` trait, and line-position error structures to eliminate parser duplication in `igv.rs` and `igweb.rs`.

### Idea 2: `LAB-IGNITER-TRANSPILER-SOURCE-MAP-P2` (Positional Mapping)
* **Goal**: Define and implement a line-mapping structure. When a generated `.ig` file (produced by `.igweb`) fails compilation, the compiler should read the source map and point the error trace back to the original line in the `.igweb` source file.

### Idea 3: `LAB-IGNITER-DIALECT-PROJECT-CLI-P3` (Workspace Integration)
* **Goal**: Extend the workspace config (`igniter.toml`) to support declarative compilation targets for dialects. Allow compiling all dialects concurrently using a single CLI trigger: `igniter dialect check`.
