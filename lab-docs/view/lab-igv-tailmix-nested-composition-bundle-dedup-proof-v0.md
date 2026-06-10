# LAB-IGV-TAILMIX-P3: Nested Composition, Bundle Dedup, and Slot Values

**Track:** `lab-igv-tailmix-nested-composition-bundle-dedup-slot-values-v0`
**Status:** OPEN → CLOSED (70/70 PASS)
**Route:** LAB PROOF / VIEW RUNTIME COMPOSITION / NO TOOLCHAIN CHANGE
**Authority:** LAB-ONLY. No implementation authority. No canon claim. No stable API.
No compiler/parser/VM change. No Tauri IPC. No client-side contract execution.

---

## 0. Reading frame

LAB-IGV-TAILMIX-P2 proved the single-component model for `FileTreeRow`. P3 extends
the architecture to a **two-component composed set**: `Sidebar` + `FileTreeRow` instances.

Three new claims over P2:

1. **Bundle model:** the definition set for a static component catalogue is a
   `{ bundle_id, component_map, definitions }` registry — each component type maps to
   its content-addressed definition by hash. `bundle_id` is the SHA256 of the
   `component_map` alone (component names → def_ids).
2. **Nested render:** `render(Sidebar, props)` emits Sidebar HTML wrapping N `FileTreeRow`
   instance bindings. `def_refs` remains exactly 2 unique hashes regardless of N rows.
   Per-row state is initialized from the `FileTreeRow` definition default.
3. **Slot values:** `items` slot drives the row count; different slot values reuse the
   same definitions without mutating them.

Plus: state isolation across components (Sidebar's `search_active` and FileTreeRow's
`expanded` are disjoint), oracle/interpreter parity for the `Sidebar` component type,
and fail-closed behavior for missing/unknown component in the bundle.

---

## 1. Component set

### `FileTreeRow` (reused from P2, unchanged)
| Feature | Value |
|---------|-------|
| State | `expanded: Bool`, default `false` |
| Display rules | `row`: classes `open`/`closed`, aria-expanded |
| Events | `toggle_btn click → toggle state.expanded`; `action_btn click → dispatch file_selected` |
| def_id | `sha256:d9e2a8bb…` |

### `Sidebar` (new in P3)
| Feature | Value |
|---------|-------|
| State | `search_active: Bool`, default `false` |
| Slots | `title: String`; `items: List` |
| Display rules | `header`: classes `browse-mode`/`search-mode`, aria label |
| Events | `search_toggle click → toggle state.search_active`; `header click → dispatch sidebar_focused` |
| Children | `item_list → FileTreeRow` from slot `items` |
| def_id | `sha256:c59650b5…` |

---

## 2. What was proved (70/70 PASS)

### TAILMIX-BUNDLE (8) — bundle structure and hash integrity

The bundle `definition_bundle.json` contains:
- `bundle_id` = `sha256:` + SHA256 of canonical `component_map` JSON
- `component_map`: `{ "Sidebar": "sha256:c59650b5…", "FileTreeRow": "sha256:d9e2a8bb…" }`
- `definitions`: exactly 2 entries, keyed by their `def_id`

**BUNDLE-08:** Both definitions' `def_id` are self-consistent — the proof runner recomputes
each hash from its canonical content and verifies it matches.

### TAILMIX-SIDEBAR (6) — Sidebar definition structure
- `states.search_active.default == false`; `slots.title` + `slots.items` declared.
- `children.item_list → component:FileTreeRow, slot:items`
- `search_toggle` has the correct toggle handler.
- `def_id` matches the SHA256 of canonical Sidebar content (self-consistent).

### TAILMIX-COMPOSE (10) — nested render output
- `render_nested(inst_id, slots, bundle) → { html, def_refs }`
- HTML contains exactly 3 `FileTreeRow` bindings for 3-item input.
- All 3 row bindings reference the **same** `FTR_DEF_ID` (no per-row inlining).
- `def_refs = [SIDE_DEF_ID, FTR_DEF_ID]` — 2 unique hashes.
- **COMPOSE-07/08:** Row HTML contains no `elements`, `rules`, `op` keys — behavior is
  referenced, never repeated per instance.

### TAILMIX-SLOTS (7) — slot values drive render without touching definitions
- Different `slots` inputs → same `def_refs` (definitions unchanged).
- `items` slot drives row count: 1-item input → 1 row; empty → 0 rows.
- **SLOTS-05:** Slot values (`/src`, `Explorer`) do NOT appear in the bundle JSON —
  slots are purely runtime binding data, orthogonal to the static definition.
- Empty `items` → 0 rows but `def_refs` still == 2 (definitions always present).

### TAILMIX-DEDUP2 (5) — N instances → 2 unique def_refs
- 3-row render: `def_refs.uniq.length == 2`.
- 5-row render: `def_refs.uniq.length == 2`.
- Same sidebar rendered twice → identical `def_refs`.
- `bundle.definitions.size == 2` — one definition per type.
- **The core dedup claim at bundle level:** K component types → K definitions, regardless of
  N instances of each.

### TAILMIX-ISOLATE (6) — per-instance state isolation
- `FTR_INIT_STATE.keys ∩ SIDE_INIT_STATE.keys == ∅` (disjoint state namespaces).
- Toggling row 0 via the oracle does not change row 1 state (separate objects).
- Toggling Sidebar `search_toggle` does not affect any `FileTreeRow` state.
- Instance IDs within one render are all unique.

### TAILMIX-ORACLE2 (10) — reference applier over the bundle
The generic P2 oracle `oracle_apply(definition, state, event?)` works unchanged over
both component types:

| Triple | Oracle result |
|--------|---------------|
| `(Sidebar, {search_active:false}, nil)` | `header.classes:["browse-mode"]`, `header.aria-label:"Browse mode"` |
| `(Sidebar, {search_active:false}, search_toggle:click)` | state `{search_active:true}`, `header.classes:["search-mode"]` |
| `(Sidebar, {search_active:false}, header:click)` | `host_event:{event:"sidebar_focused"}`, state unchanged |
| `(FTR, {expanded:false}, nil)` | `row.classes:["closed"]`, `row.aria-expanded:"false"` |
| `(FTR, {expanded:false}, toggle_btn:click)` | state `{expanded:true}`, `row.classes:["open"]` |
| `(FTR, {expanded:false}, action_btn:click)` | `host_event:{event:"file_selected"}`, state unchanged |

### TAILMIX-INTERP2 (8) — interpreter matches oracle for all nested triples
The P2 interpreter `igv_tailmix_interpreter.js` (unchanged) was diff-tested against
the oracle for all 5 Sidebar and FTR triples. Full parity on `state`, `attributes`, and
`host_event` fields. No new interpreter needed for composition — the interpreter is
generic over the definition format.

### TAILMIX-FAILCLOSED2 (6) — fail-closed for nested/bundle edge cases
- Unknown op inside a nested FTR → `{ error: "unknown_op:…" }` from both oracle and
  interpreter. No host_event or state field present.
- `bundle['component_map']['NotAComponent'] == nil` — missing component lookup returns nil.
- `bundle['definitions'][nil] == nil` — missing definition lookup returns nil.
- No silent fallthrough, no partial execution after error.

### TAILMIX-IGV (4) — `.igv` sketch artifact
`sidebar.igv` illustrates the candidate syntax for both components, clearly marked
`DESIGN SKETCH ONLY. Not canon. No grammar adoption. No compiler support.`
Contains `component Sidebar`, `component FileTreeRow`, `children`, `slot` declarations.
The file is a proof artifact, not a language specification.

---

## 3. Artifacts

| Artifact | Path |
|----------|------|
| Sidebar definition | `igniter-view-engine/fixtures/igv_tailmix/sidebar_definition.json` |
| Bundle definition | `igniter-view-engine/fixtures/igv_tailmix/definition_bundle.json` |
| `.igv` sketch | `igniter-view-engine/fixtures/igv_tailmix/sidebar.igv` |
| FileTreeRow definition | `igniter-view-engine/fixtures/igv_tailmix/file_tree_row_definition.json` (unchanged from P2) |
| Interpreter | `igniter-view-engine/fixtures/igv_tailmix/igv_tailmix_interpreter.js` (unchanged from P2) |
| Proof runner | `igniter-view-engine/proofs/verify_lab_igv_tailmix_p3.rb` |
| Lab doc | `igniter-lab/lab-docs/view/lab-igv-tailmix-nested-composition-bundle-dedup-proof-v0.md` |
| Agent card | `igniter-lab/.agents/work/cards/view/LAB-IGV-TAILMIX-P3.md` |

**No compiler, parser, VM, Tauri, or public API file was touched.**

---

## 4. Bundle model summary

```
bundle_id = sha256( JSON.generate(component_map) )

component_map = {
  "Sidebar":     "sha256:c59650b539c5111a5d5b2e849c0b2212215640b4fbfb8f5fe6d40584a38b0570",
  "FileTreeRow": "sha256:d9e2a8bb5abdb4850579ba071a7b18bc7e2840e51c3b65c6305211edeebb1cf5"
}

definitions = {
  "sha256:c59650b5…": { ...Sidebar definition... },
  "sha256:d9e2a8bb…": { ...FileTreeRow definition... }
}
```

For a static build-time component set (D7, confirmed for the IDE):
- The bundle is compiled **once** at build time.
- It is loaded **once** into the client registry at window init.
- `render` returns `{ html, def_refs }` — the HTML carries only instance bindings that
  reference hashes; the definitions are never re-shipped.
- K component types → K entries in the bundle, regardless of N render calls.

---

## 5. Open questions and gaps for P4+

| # | Gap | Note |
|---|-----|------|
| OQ-1 | `.igv` → definition compiler | P3 hand-authors JSON; compiler is for P4. The sketch syntax is a candidate, not grammar. |
| OQ-2 | Slot value typing | `items: List[FileTreeRow.Props]` is illustrative; structural typing for slots is undefined. |
| OQ-3 | Nested event routing | When a child row dispatches `file_selected`, the host event needs the row's `path` slot value to identify the file. Payload mapping (slot value → dispatch payload) is unspecified. |
| OQ-4 | Bundle invalidation / cache busting | Static set = single bundle hash; dynamic updates (e.g. hot reload in IDE) need cache-busting semantics. |
| OQ-5 | Deep nesting | P3 is one level (Sidebar→FileTreeRow). Multi-level nesting (Panel→Sidebar→FileTreeRow) is untested. |

---

## 6. Closed surfaces

| Surface | Status |
|---------|--------|
| Compiler / parser / VM change | **No** — zero implementation files touched |
| Tauri IPC implementation | **No** |
| Client-side contract execution | **No** |
| JS VM / WASM / SIR→JS codegen | **No** |
| eval / new Function in interpreter | **No** — P2 CLOSED-04 preserved; interpreter unchanged |
| Capability authority in webview | **No** |
| `.igv` grammar adoption | **No** — sketch file clearly marked non-canon |
| Canon / stable / public / framework API | **No** — LAB-ONLY |

---

## 7. Next route

**`LAB-IGV-TAILMIX-P4`** — proof-local `.igv` → definition compiler:
- Parse the `sidebar.igv` candidate syntax into a definition JSON.
- Verify that the compiled output matches the hand-authored `sidebar_definition.json`.
- Prove content-addressability: same `.igv` → same `def_id`.
- Target: ~40–50 checks; no public grammar claim; proof-local parser only.

**Or, if app-state/assembly pressure arrives before a compiler is needed:**
- **`LAB-APP-STATE-P3`** — G2 fact↔holder binding under IDE pressure (open buffers)
- **`LAB-APP-ASSEMBLY-P1`** — G3 event→operation→fact wiring for the command palette

---

## 8. Boundary statement

- **No implementation authority.** Zero toolchain files touched.
- **No canon claim.** P1–P3 decisions are lab-local.
- **No stable API.** Bundle format, render API, `.igv` syntax are proof-local candidates.
- **No client-side VM.** Interpreter is a tiny inert instruction applier.
- **No Ruby runtime; no Tailmix gem.**
- **LAB-ONLY.**

---

*LAB-ONLY. Proof-local. No implementation authority. No canon claim. No stable API.*
*No compiler/parser/VM change. No contract execution. No client-side VM. No Ruby runtime.*
