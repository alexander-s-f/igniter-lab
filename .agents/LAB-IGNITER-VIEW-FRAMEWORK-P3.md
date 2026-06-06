# Agent Handoff: LAB-IGNITER-VIEW-FRAMEWORK-P3

Card: LAB-IGNITER-VIEW-FRAMEWORK-P3
Agent: [Igniter-Lang Research / Implementation Agent]
Role: research-implementation-agent
Track: lab-igniter-view-dsl-to-viewartifact-sketch-v0
Status: done
Date: 2026-06-06
P1 baseline: 37/37 PASS (regression confirmed)
P2 structural: 18/18 PASS (regression confirmed)
P2 dynamic: 15/15 PASS (regression confirmed)
P3 checks: 42/42 PASS
tabs.igv digest: sha256:ed8ab03d35487fa14bca3598402670feae7e2962c39581dcbc942ea16456c404
Digest match P1: TRUE — identical content, identical digest

---

## [D] Decisions

**D1 — `.igv` files are Ruby DSL files, not a new grammar-based format (for now).**
The lab has no parser infrastructure. The ViewArtifact expression language is small enough
to express cleanly as Ruby method calls evaluated via `instance_eval`. The boundary between
the top-level `wrapper` (provides `view`), `IgvViewBuilder` (provides `state`, `slot`,
`element`), and `IgvElementBuilder` (provides `classes`, `param`, `display`, `on`, and all
expression/instruction helpers) is enforced by Ruby's object scope, not by a grammar. This
gives DSL isolation sufficient for the lab. A formal grammar is a future decision.

**D2 — `param` and `slot` are overloaded: declaration (with type:/from:) vs expression (without).**
```ruby
# Declaration (adds to schema):
param :id, type: "string"
slot :has_warnings, type: "boolean", from: "diagnostics.has_warnings"

# Expression (returns nested array for display/interaction rules):
param(:id)          → ["param", "id"]
slot(:has_warnings) → ["slot", "has_warnings"]
```
Single keyword, context-sensitive behavior. The distinction is made by presence of named kwargs.
This is ergonomic in Ruby. A grammar-based parser would need explicit production rules for
the two uses.

**D3 — Undeclared slot references are compile-time warnings, not errors.**
Consistent with P2's warning-only philosophy (digest mismatch, param key unknown). The artifact
is produced; the developer gets a diagnostic. At runtime, P2's `filterSlotValues` guard ensures
the undeclared slot evaluates nil (falsy branch of display rule). The warning flags the likely
mistake without blocking development.

**D4 — Compiler emits zero new artifact schema fields.**
`IgvCompiler` calls `ViewArtifact.new` with the same kwargs as the P1 Ruby fixture. The
ViewArtifact schema is unchanged. The compiler is purely a frontend. Proved by digest match
(IGV-P3-2b).

**D5 — Two-fence security model for banned opcodes.**
Fence 1: `IgvElementBuilder#on` raises `IgvCompileError` on banned/unknown opcodes — DSL level.
Fence 2: `ViewArtifact#validate!` raises `ArgumentError` on banned opcodes — artifact level.
An artifact with a banned opcode cannot be produced by any path through the compiler.

---

## [S] Shipped

### New files created

| File | Description |
|---|---|
| `igniter-view-engine/lib/igv_compiler.rb` | IgvCompiler, IgvViewBuilder, IgvElementBuilder, IgvExpressions, IgvInstructions |
| `igniter-view-engine/fixtures/tabs.igv` | Primary proof fixture — identical semantics to P1/P2 tabs_artifact.rb |
| `igniter-view-engine/fixtures/static_page.igv` | Static elements only (no state, no slots) |
| `igniter-view-engine/fixtures/unsafe_opcode.igv` | Banned opcode test → compile_error |
| `igniter-view-engine/fixtures/undeclared_slot.igv` | Undeclared slot ref → warning + artifact |
| `igniter-view-engine/fixtures/malformed.igv` | NameError test → compile_error |
| `igniter-view-engine/run_ivf_proof_p3.rb` | 42-check proof runner |
| `lab-docs/lab-igniter-view-dsl-to-viewartifact-sketch-v0.md` | Design doc |
| `.agents/LAB-IGNITER-VIEW-FRAMEWORK-P3.md` | This handoff |

### Generated outputs (in `igniter-view-engine/out/`)

| File | Description |
|---|---|
| `tabs_from_igv.json` | ViewArtifact compiled from `tabs.igv` (digest matches P1) |
| `static_from_igv.json` | ViewArtifact compiled from `static_page.igv` |
| `ivf_p3_proof_summary.json` | Full P3 proof result matrix |

### Existing files untouched

- `igniter-lang/**` — not edited
- `tailmix/**` — not edited
- `igniter-view-engine/lib/view_artifact.rb` — not edited
- `igniter-view-engine/lib/ssr_renderer.rb` — not edited
- `igniter-view-engine/igniter_view_runtime.js` — not edited
- `igniter-view-engine/fixtures/tabs_artifact.rb` — not edited
- `igniter-view-engine/run_ivf_proof.rb` — not edited
- `igniter-view-engine/run_ivf_proof_p2.rb` — not edited
- `igniter-view-engine/run_ivf_dom_proof.js` — not edited

---

## [T] Proof Matrix

### P1 regression (37/37)
Confirmed passing. Compiler addition did not break P1 baseline.

### P2 structural + dynamic regression (18/18 + 15/15)
Confirmed passing. Runtime and P2 runner unaffected.

### P3 checks (42/42)

| Check | Result | What it verifies |
|---|---|---|
| IGV-P3-1a | ✅ PASS | `tabs.igv` compiles successfully |
| IGV-P3-1b | ✅ PASS | `static_page.igv` compiles (no state/slots) |
| IGV-P3-1c | ✅ PASS | Zero error-level diagnostics on `tabs.igv` |
| IGV-P3-2a | ✅ PASS | Compiled artifact has all required schema keys |
| IGV-P3-2b | ✅ PASS | **Digest matches P1 fixture** (bit-identical content) |
| IGV-P3-2c..k | ✅ (9) | view_id, UIState, slot, elements, rules, params |
| IGV-P3-3a..d | ✅ (4) | SSR renderer, display rules, determinism, static page |
| IGV-P3-4a..c | ✅ (3) | JSON structure for JS runtime hydration |
| IGV-P3-5 | ✅ PASS | P1 37/37 still pass |
| IGV-P3-6 | ✅ PASS | P2 structural 18/18 still pass |
| IGV-P3-7 | ✅ PASS | P2 DOM 15/15 still pass |
| IGV-P3-8a | ✅ PASS | `unsafe_opcode.igv` → compile_error |
| IGV-P3-8b | ✅ PASS | Error message identifies "fetch" |
| IGV-P3-8c | ✅ PASS | No artifact emitted from unsafe input |
| IGV-P3-8d | ✅ PASS | ViewArtifact build-time fence also rejects banned opcodes |
| IGV-P3-9a..c | ✅ (3) | Undeclared slot: warning + artifact; P2 filter intact |
| IGV-P3-10a..e | ✅ (5) | NameError, partial output blocked, warnings identified, inline compile |
| IGV-P3-11a..e | ✅ (5) | No eval/innerHTML/fetch/contract in compiler source |
| IGV-P3-12 | ✅ PASS | igniter-lang/** untouched |
| **Total** | **42/42** | |

---

## [R] Risks and Recommendations

**Risk 1 — `instance_eval` gives .igv source access to all Ruby.**
The `IgvViewBuilder` and `IgvElementBuilder` `instance_eval` their blocks in-process. A
malicious `.igv` file could call any Ruby method (e.g. `system("rm -rf /")` in an element
block). This is not a concern for the lab (trusted developer-authored DSL files), but would
need sandboxing (`$SAFE`, Ractors, subprocess isolation, or a custom parser) for any context
where `.igv` files come from untrusted sources.

**Risk 2 — Param/slot overloading is Ruby-idiomatic but grammar-unfriendly.**
`param(:id)` as expression vs `param :id, type: "string"` as declaration requires
context-aware disambiguation. A grammar-based parser for a canonical `.igv` format would need
explicit production rules or separate namespaces. This is a design choice to revisit before
any canonical syntax claim.

**Risk 3 — No type-checking of param/slot values against declared types.**
`node_params_schema: { "id" => "string" }` declares the expected type but the compiler
does not verify that runtime param values conform. This is consistent with P2's warning-only
approach but leaves a static type gap. Finding 4 in the design doc addresses this.

**Recommendation: IVF-P4 — Grammar Sketch.**
P3 proves the DSL semantics. The next step is separating "what `.igv` means" from "how it is
expressed in Ruby." A formal grammar (EBNF or PEG sketch) would:
- Enable non-Ruby tooling (IDE completion, standalone linter)
- Make the syntax portable and inspectable
- Prepare for Igniter-Lang spec pressure if the design proves sound

Secondary recommendation: Slot-Contract Type Linkage (Finding 4) — validate `.igv` slot
declarations against the corresponding Igniter contract's output types. This closes the
static type gap between contract outputs and view slot inputs.
