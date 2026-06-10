# LAB-IGV-TAILMIX-P4: Proof-local .igv → Definition JSON Compiler

**Track:** `lab-igv-tailmix-igv-compiler-proof-v0`
**Status:** OPEN → CLOSED (47/47 PASS)
**Route:** LAB PROOF / VIEW RUNTIME COMPOSITION / NO TOOLCHAIN CHANGE
**Authority:** LAB-ONLY. No implementation authority. No canon claim. No stable API.
No compiler/parser/VM change. No Tauri IPC. No client-side contract execution.

---

## 0. Reading frame

LAB-IGV-TAILMIX-P3 proved the two-component bundle model using hand-authored definition
JSON. P4 closes the loop: the `sidebar.igv` candidate syntax can be mechanically compiled
to definition JSON that reproduces the P3 hashes exactly.

Three new claims over P3:

1. **Compiler:** `IgvCompiler.compile(source)` is a pure Ruby function (proof-local,
   no external tools) that parses the `.igv` candidate syntax and emits content-addressed
   definition hashes. Same source → same hashes. Semantic change → different hash.
2. **Content-addressability:** Compiled `def_id` for Sidebar and FileTreeRow match
   the hand-authored values. Comments, blank lines, and component-block order do not
   affect individual `def_id`s. A semantic change in one component does not affect
   the other.
3. **Compatibility:** The compiled bundle is a drop-in for the hand-authored bundle.
   P3 `render_nested`, `oracle_apply`, and `interp_apply` all produce identical
   results for compiled vs hand-authored definitions.

Plus: fail-closed on 7 error categories at compile time.

---

## 1. Compiler design

### Input: `.igv` candidate syntax (P3 sketch)

```
component NAME
  slot NAME : TYPE
  state NAME : TYPE = DEFAULT
  element NAME
    style STATE_EXPR
      classes: [cls1, cls2]
      aria: { key: "value" }
    otherwise
      classes: [...]
      aria: { ... }
    on EVENT
      INSTRUCTION
  children BLOCK_NAME
    component OTHER_COMPONENT_NAME
    from SLOT_NAME
```

### Output: definition hash (insertion-order preserved Ruby Hash)

```
{
  "def_id"    => "sha256:...",
  "component" => NAME,
  "states"    => { STATE_NAME => { "default" => VALUE } },
  "slots"     => { SLOT_NAME => { "type" => T, "default" => D } },    # if any
  "elements"  => { EL_NAME => { "rules" => [...], "on" => {...} } },
  "children"  => { BLOCK_NAME => { "component" => REF, "slot" => SLOT } }  # if any
}
```

`def_id = sha256(JSON.generate(definition_without_def_id))` — same algorithm as P2/P3.

### Parsing strategy

Line-by-line recursive descent, tracking indentation:
- **Level 0**: `component NAME`
- **Level 2**: `slot`, `state`, `element NAME`, `children NAME`
- **Level 4**: `style STATE_EXPR`, `otherwise`, `on EVENT`; or `component REF`, `from SLOT`
- **Level 6**: `classes:`, `aria:` (inside style/otherwise); instruction (inside on)

Single `pos` index passed by reference through all parse helpers. No backtracking.

### Closed-op vocabulary

Same 11 ops as P2/P3 interpreter: `toggle set add_class remove_class toggle_class
set_attr set_aria show hide match dispatch`. Any other op → `CompileError`.

---

## 2. What was proved (47/47 PASS)

### COMPILE (10) — parse sidebar.igv → 2 definitions, hashes match

- `IgvCompiler.compile` is callable.
- Parsing `sidebar.igv` yields exactly 2 definitions.
- Component order preserved: Sidebar first, FileTreeRow second.
- **COMPILE-04:** Compiled Sidebar `def_id` == `sha256:c59650b5…` (hand-authored).
- **COMPILE-05:** Compiled FileTreeRow `def_id` == `sha256:d9e2a8bb…` (hand-authored).
- Compiled content (sans `def_id`) is byte-identical to hand-authored.
- Same source compiled twice → same `def_id` (deterministic).
- `def_id` is self-consistent: `canonical_hash(compiled_defn) == def_id`.

### ADDR (6) — content-addressability

| Check | Result |
|-------|--------|
| Comments-only change → same `def_id` | PASS |
| Semantic change (toggle→dispatch) → different FTR `def_id` | PASS |
| Different state default → different Sidebar `def_id` | PASS |
| Extra blank lines only → same `def_id` | PASS |
| Semantic change in Sidebar does not affect FTR `def_id` | PASS |
| Swapping component-block order in source → same individual `def_ids` | PASS |

The last check confirms that definitions are independently content-addressed: the
compiled output for each component depends only on that component's `.igv` block.

### BUNDLE (7) — build_bundle from compiled defs

- `IgvCompiler.build_bundle(definitions)` returns `{ bundle_id, component_map, definitions }`.
- Compiled `bundle_id` == `sha256:63157b42…` (matches hand-authored).
- Compiled `component_map` is byte-identical to hand-authored.
- Semantic change in source → different `bundle_id` (bundle tracks component hashes).
- `bundle_id = sha256(JSON.generate(component_map))` — bundle hash is derived from
  component names → def_ids only, not from definition bodies.

### COMPAT (10) — compiled bundle with P3 render/oracle/interpreter

The P3 `render_nested`, `oracle_apply`, and P2 `interp_apply` (unchanged) all work
identically for compiled and hand-authored bundles:

| Operation | Result |
|-----------|--------|
| `render_nested` → `def_refs.uniq.length == 2` | PASS |
| Compiled and hand-authored `def_refs` are equal | PASS |
| Oracle: Sidebar init → `browse-mode` classes | PASS |
| Oracle: FTR init → `closed` classes | PASS |
| Oracle: `search_toggle click` → `search_active = true` | PASS |
| Oracle: `header click` → `host_event: sidebar_focused` | PASS |
| Interpreter matches oracle for Sidebar toggle | PASS |
| Interpreter matches oracle for FTR toggle | PASS |
| Interpreter matches oracle for Sidebar dispatch | PASS |

### FAILCLOSED (14) — 7 error categories, 2 checks each

| Fixture | Error type | CompileError raised | Message correct |
|---------|------------|--------------------:|----------------:|
| `invalid_unknown_op.igv` | `exec_arbitrary` op | ✅ | "unknown op" |
| `invalid_duplicate_component.igv` | Two `Sidebar` blocks | ✅ | "duplicate" |
| `invalid_child_missing_component.igv` | `Ghost` not in file | ✅ | "unknown component" |
| `invalid_event_missing_state.igv` | `toggle state.nonexistent` | ✅ | "undeclared state" |
| `invalid_state_default_type.igv` | `Bool = 42` | ✅ | "invalid" |
| `invalid_malformed_block.igv` | Children missing `component` | ✅ | "missing component" |
| `invalid_missing_component_name.igv` | `component` with no name | ✅ | "missing component name" |

All errors are raised before any definition hash is computed. No partial output on error.

---

## 3. Artifacts

| Artifact | Path |
|----------|------|
| Proof runner (with compiler) | `igniter-view-engine/proofs/verify_lab_igv_tailmix_p4.rb` |
| Compiled Sidebar definition | `igniter-view-engine/fixtures/igv_tailmix/compiled_sidebar_definition.json` |
| Compiled bundle | `igniter-view-engine/fixtures/igv_tailmix/compiled_definition_bundle.json` |
| Invalid fixture: unknown op | `igniter-view-engine/fixtures/igv_tailmix/invalid_unknown_op.igv` |
| Invalid fixture: duplicate component | `igniter-view-engine/fixtures/igv_tailmix/invalid_duplicate_component.igv` |
| Invalid fixture: child missing component | `igniter-view-engine/fixtures/igv_tailmix/invalid_child_missing_component.igv` |
| Invalid fixture: event missing state | `igniter-view-engine/fixtures/igv_tailmix/invalid_event_missing_state.igv` |
| Invalid fixture: invalid state default | `igniter-view-engine/fixtures/igv_tailmix/invalid_state_default_type.igv` |
| Invalid fixture: malformed block | `igniter-view-engine/fixtures/igv_tailmix/invalid_malformed_block.igv` |
| Invalid fixture: missing name | `igniter-view-engine/fixtures/igv_tailmix/invalid_missing_component_name.igv` |
| Lab doc | `igniter-lab/lab-docs/view/lab-igv-tailmix-igv-compiler-proof-v0.md` |
| Agent card | `igniter-lab/.agents/work/cards/view/LAB-IGV-TAILMIX-P4.md` |

Reused unchanged from P2/P3:
- `igniter-view-engine/fixtures/igv_tailmix/sidebar.igv` (input to compiler)
- `igniter-view-engine/fixtures/igv_tailmix/definition_bundle.json` (canonical reference)
- `igniter-view-engine/fixtures/igv_tailmix/igv_tailmix_interpreter.js`

**No compiler, parser, VM, Tauri, or public API file was touched.**

---

## 4. Hash lineage

```
sidebar.igv (candidate syntax)
   │
   └─ IgvCompiler.compile(source)
         │
         ├─ Sidebar definition (sans def_id)
         │     └─ def_id = sha256:c59650b5... ← matches hand-authored
         │
         └─ FileTreeRow definition (sans def_id)
               └─ def_id = sha256:d9e2a8bb... ← matches hand-authored
                     │
         IgvCompiler.build_bundle([Sidebar, FTR])
               │
               └─ bundle_id = sha256:63157b42... ← matches hand-authored
```

---

## 5. Open questions and gaps for P5+

| # | Gap | Note |
|---|-----|------|
| OQ-1 | Slot value typing (`List[FileTreeRow.Props]` bracket syntax ignored) | Bracket part stripped; structural typing unspecified |
| OQ-2 | Multi-event elements (`on click` + `on hover`) | Only one `on EVENT` per element tested |
| OQ-3 | Nested event payload routing (`dispatch` with payload) | Not yet supported in compiler |
| OQ-4 | Multi-level nesting | P3/P4 prove one level; deeper nesting unspecified |
| OQ-5 | Error recovery / multi-error reporting | First error wins; no accumulation |

---

## 6. Closed surfaces

| Surface | Status |
|---------|--------|
| Compiler / parser / VM change | **No** — zero implementation files touched |
| Tauri IPC implementation | **No** |
| Client-side contract execution | **No** |
| JS VM / WASM / SIR→JS codegen | **No** |
| eval / new Function in interpreter | **No** |
| `.igv` grammar adoption | **No** — `sidebar.igv` clearly marked non-canon |
| Canon / stable / public / framework API | **No** — LAB-ONLY |

---

## 7. Boundary statement

- **No implementation authority.** Zero toolchain files touched.
- **No canon claim.** Compiler is proof-local Ruby only.
- **No stable API.** Compiler interface, `.igv` syntax, bundle format are proof-local candidates.
- **No client-side VM.** Interpreter unchanged from P2.
- **LAB-ONLY.**

---

*LAB-ONLY. Proof-local. No implementation authority. No canon claim. No stable API.*
*No compiler/parser/VM change. No contract execution. No client-side VM. No Ruby runtime.*
