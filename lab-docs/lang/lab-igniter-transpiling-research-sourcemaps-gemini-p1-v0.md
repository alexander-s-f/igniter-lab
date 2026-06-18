# lab-igniter-transpiling-research-sourcemaps-gemini-p1-v0 — Source maps, diagnostics, and debug traces for projection dialects

**Delegation-Code:** `GEMINI-20260618-TRANSPILING-B`  
**Card Reference:** `.agents/work/cards/lang/LAB-IGNITER-TRANSPILING-RESEARCH-SOURCEMAPS-GEMINI-P1.md`  
**Status:** RESEARCH REPORT (v0; recommendations are backlog ideas, not authority)  
**Scope:** Research and design of source-mapping, diagnostic remapping, and debug trace formats for Projection Dialects (`.igv`, `.igweb`). **No implementation, no compiler edits, no IDE/plugin edits.**  
**Authority:** Lab research only. Grounded in `project.rs`, `multifile.rs`, `main.rs`, and the `Projection Dialects (P0)` boundary.

---

## 1. Executive Summary

Projection Dialects like `.igv` (UI sugar → ViewArtifact JSON) and `.igweb` (routing sugar → generated `.ig` source) are key authoring tools in `igniter-lab`. However, their developer experience (DX) relies entirely on maintaining a clear, stable connection between generated targets and source files. When compilation or validation fails downstream, pointing developers directly to generated artifacts collapses usability.

This report defines the diagnostic and source-mapping architecture for Projection Dialects:
1.  **Lowerer parsing diagnostics** are tracked using line-positioned error structures.
2.  **Downstream compiler errors** in generated `.ig` files are mapped back to `.igweb` using a companion **Line Map** sidecar format.
3.  **Downstream view validation errors** in generated JSON are mapped back to `.igv` using a **JSON-Path-to-Line Map** sidecar.
4.  **Debug sidecar artifacts** are formalized with integrity checks (file hashes) to prevent stale maps.
5.  **IDE Handoffs** are designed around a two-stage overlay compiler pipeline for real-time editor feedback.

---

## 2. Current Diagnostic Shape & Downstream Failures (Q1 & Q2)

### Current Diagnostic Shape
Currently, both dialects implement simple, line-positioned syntax/parsing diagnostics before code generation:
*   **`.igv` (View Dialect)**: Uses `IgvError { line: usize, msg: String }` (defined in `igv.rs`).
*   **`.igweb` (Routing Dialect)**: Uses `IgwebError { line: usize, message: String }` (defined in `igweb.rs`).
These error types are sufficient for catching syntax errors *inside* the dialect file itself during the initial lowering pass.

### Downstream Failures
The primary DX gap occurs when the lowered target compiles or validates incorrectly:
*   **For `.igweb`**: The generated `.ig` (e.g. `gen/routes.ig`) goes to the project compiler. If the generated file contains a type mismatch or references an unknown handler contract, the compiler generates a diagnostic (e.g. `OOF-P1` or `OOF-TY0`) pointing at the generated `.ig line numbers. The developer must manually open the read-only generated file and backtrack to their `.igweb` source.
*   **For `.igv`**: The generated `ViewArtifact` JSON is validated at runtime. If it contains invalid contract references, the validation library throws an error referencing a JSON path or token offset, leaving the developer to search their `.igv` file manually.

---

## 3. Minimal v0 Source-Map Model (Q3)

We evaluate four source-map complexities for v0:
1.  **Full VLQ-style (Source Map v3)**: Maps exact character offsets. Too complex, expensive to generate, and unnecessary for simple declarative dialects.
2.  **Segment Map / Span Map**: Maps tokens to token spans. Useful but introduces heavy AST overhead in the lowerers.
3.  **Line Map (Recommended for `.ig` targets)**: A flat array mapping `generated_line -> source_line` (or `(source_path, source_line)`). Since `.igweb` lowers line-by-line in a deterministic order, a Line Map is lightweight, human-readable, and fully sufficient.
4.  **JSON-Path-to-Line Map (Recommended for JSON targets)**: Maps structured JSON paths (e.g., `regions.main.fields[2].kind`) directly to the original `.igv` line number. This is highly effective for declarative structured files like `.igv`.

---

## 4. Remapping Generated `.ig` Diagnostics (Q4)

To keep generated `.ig` files fully inspectable while remapping compilation errors back to the `.igweb` source, we leverage the existing `source_line_map` architecture in `multifile.rs`.

```text
 [routes.igweb] ──lower_igweb──► [gen/routes.ig] + [gen/routes.ig.map.json]
                                         │
                                         ▼ (compiler compiles gen/routes.ig)
                                  [Compile Error]
                                         │
                                         ▼ (compiler reads routes.ig.map.json)
                         [Enriched Diagnostic Output JSON]
                          - source_path: "routes.igweb"
                          - original_line: 12
                          - line: 45 (inspectable gen/routes.ig line)
```

### Remapping Flow:
1.  The `.igweb` lowerer writes the generated file `gen/routes.ig` and a companion sidecar file `gen/routes.ig.map.json`.
2.  The generated `.ig` is committed and inspectable.
3.  When `igc` compiles `gen/routes.ig` in project mode, it checks for the presence of the `.map.json` sidecar.
4.  If found, `igc` loads the mapping into memory.
5.  If a typecheck or parse error occurs, `igc` enriches the JSON diagnostic output by translating the generated line number to the original `source_path` and `original_line` coordinates of the `.igweb` file, while keeping the generated `line` coordinate intact for inspection.

---

## 5. Mapping ViewArtifact JSON Validation Errors (Q5)

Because JSON artifacts do not have stable code lines, validation errors are path-oriented. We map them back to `.igv` using JSON Path strings.

### The JSON-Path Map Sidecar (`gen/views.json.map.json`)
The lowerer outputs a simple JSON map mapping paths to lines:
```json
{
  "screen": 18,
  "layout": 18,
  "sources.my_source": 19,
  "regions.main.fields[0]": 20,
  "actions.my_action": 21,
  "actions.my_action.contract": 21
}
```

### Remapping Flow:
1.  The layout engine or view runtime validates the `ViewArtifact` JSON.
2.  On validation failure (e.g., `actions.my_action.contract` references an unimported contract), the runtime queries the map with the error path.
3.  The runtime prints the error pointing directly to the `.igv` source:
    `views.igv error (line 21): action contract 'MyAction' is not declared in sources`.

---

## 6. Debug Sidecar Artifact Schema (Q6)

To ensure map integrity and prevent mismatched maps from pointing to stale source files, the map sidecar (e.g. `routes.ig.map.json`) must contain the following metadata:

```json
{
  "dialect_path": "source/routes.igweb",
  "dialect_hash": "sha256:d8a2...3f9e",
  "target_path": "source/generated/routes.ig",
  "target_hash": "sha256:4a9c...8b2d",
  "lowerer_version": "0.1.0",
  "target_kind": "ig",
  "mappings": {
    "4": 2,
    "5": 3,
    "12": 6,
    "15": 8
  }
}
```
*   **`dialect_hash`**: Verifies that the `.igweb` source has not been modified since the map was generated. If the file hash mismatch occurs, mapping is disabled or warning emitted.
*   **`target_hash`**: Verifies that the generated `.ig` has not been hand-edited.

---

## 7. IDE Handoff & Overlay Integration (Q7)

To support real-time IDE compiler diagnostics (JetBrains) on unsaved dialect buffers without introducing dialect-specific parser code to the compiler, we recommend a **two-stage overlay process**:

```
[Unsaved Editor Tab: routes.igweb]
   │
   ├─► 1. IDE writes unsaved buffer to: /tmp/buffer.igweb
   ├─► 2. IDE runs lowerer: igniter-web-lower /tmp/buffer.igweb -o /tmp/buffer_lowered.ig
   │      (and generates /tmp/buffer_lowered.ig.map.json)
   │
   └─► 3. IDE invokes compiler:
          igc compile --project-root . --entry App.Main \
            --overlay source/generated/routes.ig=/tmp/buffer_lowered.ig \
            --out target/app.igapp
```

### Compiler Diagnostics Ingestion:
1.  The compiler (`igc`) reads `/tmp/buffer_lowered.ig` instead of the on-disk file, loading the companion `/tmp/buffer_lowered.ig.map.json` automatically.
2.  The compiler outputs diagnostics pointing back to `source/routes.igweb` with the original lines.
3.  The JetBrains language server parses the compiler's JSON diagnostics and draws the red squiggly error line in the editor tab for `routes.igweb`.
4.  The developer gets instant feedback on unsaved dialect files without the compiler ever holding dialect syntax in memory.

---

## 8. Verification & Test Obligations (Q8)

To verify the source map implementation, the following tests must be established:

1.  **Lowerer Position Integrity Tests**: Assert that syntax errors in the lowerer (`igv.rs` / `igweb.rs`) report the exact 1-based source line.
2.  **Enrichment Parity Tests**: Compile a generated `.ig` file containing a type error. Assert that the compiler output contains `original_line` and `source_path` pointing back to the original `.igweb` file, matching the line map.
3.  **Staleness Assertion Tests**: Modify a dialect source file (`.igweb`) without updating the generated map. Verify that the compiler detects the hash mismatch and either refuses to enrich or raises a compilation warning.
4.  **Overlay Handoff Tests**: Run a mock IDE compilation passing an overlaid `.igweb` buffer. Verify that compiler diagnostics successfully attribute the error back to the overlaid dialect file path and line.
