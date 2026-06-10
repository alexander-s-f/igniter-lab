# LAB-IGV-TAILMIX-P2: Tailmix-on-Igniter — Definition, Render, and Diff-Oracle Proof

**Track:** `lab-igv-tailmix-definition-render-diff-oracle-proof-v0`
**Status:** OPEN → CLOSED (56/56 PASS)
**Route:** LAB PROOF / VIEW RUNTIME BOUNDARY / NO TOOLCHAIN CHANGE
**Authority:** LAB-ONLY. No implementation authority. No canon claim. No stable API.
No compiler/parser/VM change. No Tauri IPC. No client-side contract execution.

---

## 0. Reading frame

LAB-IGV-TAILMIX-P1 locked the architecture (D1–D10). This proof-local card takes that
architecture down to one tiny component — `FileTreeRow` — and verifies the four claims
that must hold before the IDE can use this model:

1. **Content-addressed definition (D6):** a per-type, inert artifact whose `def_id` is
   the SHA256 of its canonical content.
2. **`render → { html, def_refs }` (D7):** render emits per-instance binding only; no
   behavior inlined per render.
3. **N instances → 1 definition (D6/D7 dedup):** N renders of the same component type
   all reference the same definition hash.
4. **Bounded parity via diff-oracle (D10):** a reference applier oracle defines "correct"
   over the closed instruction vocabulary; the proof-local interpreter is tested against
   it for every `(definition, state, event)` triple.

Plus: fail-closed behavior for unknown ops (D8), dispatch as the single seam to
contracts (D5), and the definition carrying no VM/SIR/capability surface (D9).

---

## 1. Component under proof: `FileTreeRow`

Minimal but representative for the IDE's file-tree:

| Feature | Present |
|---------|---------|
| Local state | `expanded: Bool`, default `false` |
| Display rules | `style/otherwise`: classes (`open`/`closed`), aria-expanded (`true`/`false`) |
| Event handler: toggle | `toggle_btn on:click → op:toggle → state.expanded` |
| Event handler: dispatch | `action_btn on:click → op:dispatch → event:"file_selected"` |
| VM/SIR bytecode | **absent** |
| Capability/passport | **absent** |
| Contract execution | **absent** |

This is the smallest component that exercises all three non-trivial paths: attribute
rules, state mutation, and the `dispatch` seam.

---

## 2. What was proved (56/56 PASS)

### TAILMIX-DEF (8) — definition structure and content-addressing
- Definition file parses as valid JSON.
- `def_id` field present, `sha256:` prefix, 64-hex-char hash.
- `component`, `states`, `elements` structure correct.
- **DEF-08:** `def_id` is the correct SHA256 of canonical content (hash self-consistency
  verified programmatically by the proof runner).

### TAILMIX-RENDER (8) — render output: `{ html, def_refs }`
- Render returns exactly `{ html, def_refs }`.
- `def_refs[0]` == `DEFINITION['def_id']`.
- HTML contains `data-igv-def`, `data-igv-state` (initial state, not current state).
- **RENDER-07/08:** HTML does NOT inline definition content (no `elements`, `rules`, `op`
  keys in the per-instance HTML). Behavior is referenced, not repeated.

### TAILMIX-DEDUP (5) — N instances → 1 definition
- 3 renders of `FileTreeRow` produce 3 distinct `data-igv-instance` values.
- All 3 `def_refs[0]` == same hash.
- Unique def_refs across all renders == 1. **The core dedup claim.**
- Per-instance state initialized independently (not shared).

### TAILMIX-ORACLE (10) — reference applier oracle
The oracle is a pure Ruby function `(definition, state, event?) → result` that
implements the canonical semantics of the closed vocabulary:

| Triple | Oracle result |
|--------|---------------|
| `(def, {expanded:false}, nil)` | state unchanged · classes:["closed"] · aria-expanded:"false" · no host_event |
| `(def, {expanded:false}, toggle_btn:click)` | state:{expanded:true} · classes:["open"] · aria-expanded:"true" |
| `(def, {expanded:true}, toggle_btn:click)` | state:{expanded:false} · classes:["closed"] · aria-expanded:"false" |
| `(def, {expanded:false}, nil)` | no host_event field |

### TAILMIX-INTERP (8) — interpreter ↔ oracle parity
The proof-local JS interpreter (`igv_tailmix_interpreter.js`) was diff-tested against
the oracle for all four triples above. Results match on:
- `state` hash (boolean values, correct types)
- `attributes` hash (`row.classes`, `row.aria-expanded`)
- Absence of `host_event` for non-dispatch triples

**Bounded parity (D10) is satisfied** for the `FileTreeRow` component and the closed
P2 vocabulary.

### TAILMIX-DISPATCH (6) — dispatch seam
- `action_btn on:click` produces `host_event: { event: "file_selected" }`.
- State is **unchanged** after dispatch (dispatch ≠ state mutation).
- Oracle and interpreter agree on both claims.
- `dispatch` is the **only** path out of the `:local` tier (D5).

### TAILMIX-FAILCLOSED (6) — fail-closed on unknown op
- Oracle and interpreter both return `{ error: "unknown_op:<op>" }` for `"exec_arbitrary"`.
- Neither produces a `host_event` on unknown op.
- Neither includes a `state` field on error (no partial execution).
- **Fail-closed (D8) is verified.**

### TAILMIX-CLOSED (5) — definition carries no VM/SIR/capability
- No `bytecode`, `instructions`, `SIR` keys in definition JSON.
- No `capability`, `passport` fields.
- No `contract`, `effect`, `observed` fields.
- Interpreter source: no `eval(`, `new Function(`, `Function(` — no dynamic code execution.

---

## 3. Artifacts

| Artifact | Path |
|----------|------|
| Definition JSON | `igniter-view-engine/fixtures/igv_tailmix/file_tree_row_definition.json` |
| Proof-local interpreter | `igniter-view-engine/fixtures/igv_tailmix/igv_tailmix_interpreter.js` |
| Proof runner | `igniter-view-engine/proofs/verify_lab_igv_tailmix_p2.rb` |
| Lab doc | `igniter-lab/lab-docs/view/lab-igv-tailmix-definition-render-diff-oracle-proof-v0.md` |
| Agent card | `igniter-lab/.agents/work/cards/view/LAB-IGV-TAILMIX-P2.md` |

**No compiler, parser, VM, Tauri, or public API file was touched.**

---

## 4. The content-addressed definition

```
def_id = sha256:d9e2a8bb5abdb4850579ba071a7b18bc7e2840e51c3b65c6305211edeebb1cf5
```

Computed as `SHA256(JSON.generate(definition_without_def_id))`. The canonical JSON
key order is: `component → states → elements → (row → toggle_btn → action_btn)`.
This order is preserved by Ruby's `JSON.generate` from a parsed Hash, making the hash
deterministic across platforms.

```json
{
  "def_id": "sha256:d9e2a8bb5abdb4850579ba071a7b18bc7e2840e51c3b65c6305211edeebb1cf5",
  "component": "FileTreeRow",
  "states": { "expanded": { "default": false } },
  "elements": {
    "row": { "rules": [{ "when": "state.expanded", "classes": ["open"], "aria": {"expanded":"true"},
                         "else": { "classes": ["closed"], "aria": {"expanded":"false"} } }] },
    "toggle_btn": { "on": { "click": [{ "op": "toggle", "target": "state.expanded" }] } },
    "action_btn":  { "on": { "click": [{ "op": "dispatch", "event": "file_selected" }] } }
  }
}
```

---

## 5. The render API (D7)

```
render(component_name, props) → { html, def_refs }
```

**`html`** — per-instance binding only:
```html
<div data-igv="FileTreeRow"
     data-igv-def="sha256:d9e2a…"
     data-igv-instance="inst-001"
     data-igv-state='{"expanded":false}'>…</div>
```

**`def_refs`** — list of definition hashes needed to render this instance:
```json
["sha256:d9e2a8bb5abdb4850579ba071a7b18bc7e2840e51c3b65c6305211edeebb1cf5"]
```

The definition is NEVER embedded in the `html`. The client registry is pre-loaded
from the build-time definition bundle (D7). Per-instance HTML is therefore tiny:
binding attributes + static slot values only.

---

## 6. The oracle

The reference applier is the canonical side of the D10 bounded parity obligation.
It is a pure function (no DOM, no JS runtime): `(definition, state, event?) → result`.

The oracle implements these rules for the closed vocabulary:

| op | Effect |
|----|--------|
| `toggle` | `state[key] = !state[key]` |
| `set` | `state[key] = value` |
| `dispatch` | `host_event = { event, payload }` (state unchanged) |
| Rule: `style/otherwise` | Conditional: pick `when`-branch if truthy, else `else`-branch |
| Unknown op | `{ error: "unknown_op:<op>" }` — immediate return, no partial execution |

The closed vocabulary (D8) is frozen. The oracle enforces it. Anything not in the
vocabulary fails closed.

---

## 7. Bounded parity (D10)

The parity obligation for P2 is: for every `(definition, state, event)` triple over the
`FileTreeRow` component and the four proof triples, the interpreter must return the same
`{ state, attributes, host_event? }` as the oracle.

This was verified for:
- Initial render (no event)
- Toggle expand
- Toggle collapse (round-trip)
- Dispatch host event
- Unknown op (both return `{ error }`)

**Bounded, not open-ended.** The oracle is the "diff-oracle" of D10. The interpreter
is tested against it, not against an independent runtime.

---

## 8. Gaps and open questions

These are not blocking for P2 but inform P3:

| # | Gap | Note |
|---|-----|------|
| OQ-1 | Slot values in render | P2 has no slot values (label/path are static). How slots arrive from contracts is for P3. |
| OQ-2 | Multiple components / composition | P2 is single-component. Composition (a panel containing a list of FileTreeRows) needs a dedup registry, not a single definition. |
| OQ-3 | Definition bundle format | P2 uses single-file JSON. Bundle indexing (hash→file or single index) is for P3. |
| OQ-4 | `.igv` DSL compilation path | P2 hand-authors the definition JSON. The `.igv`→definition compiler is for P3+. |
| OQ-5 | `dispatch` event schema | `file_selected` has no typed payload in P2. Typing at the seam is for a later card. |

---

## 9. Closed surfaces

| Surface | Status |
|---------|--------|
| Compiler / parser / VM change | **No** — zero implementation files touched |
| Tauri IPC implementation | **No** — IPC is out of scope for the proof |
| Client-side contract execution | **No** — definition carries no contract bytecode |
| JS VM / WASM / SIR→JS codegen | **No** — interpreter is a tiny instruction applier, not a VM |
| eval / new Function in interpreter | **No** — CLOSED-04 verified |
| Capability authority in webview | **No** — no capability or passport fields |
| Canon / stable / public / framework API | **No** — LAB-ONLY |

---

## 10. Next route

**`LAB-IGV-TAILMIX-P3`** — small component set / nested composition:
- Add a second component type (e.g. `Sidebar`) that contains a list of `FileTreeRow`s.
- Prove definition bundle = 2 definitions (one per type) regardless of N instances.
- Introduce slot values (list items arriving from contracts via the dispatch seam).
- Prove the client registry dedup works at the bundle level.
- Begin the `.igv` DSL sketch for the two components (still no compiler — hand-authored
  definitions acceptable until P4+).
- Target ~50–60 checks.

OR, if app-state gaps dominate before view runtime:
- **`LAB-APP-STATE-P3`** — G2 fact↔holder binding under IDE pressure
- **`LAB-APP-ASSEMBLY-P1`** — G3 event→op→fact wiring for the command palette

---

## 11. Boundary statement

- **No implementation authority.** Zero compiler/parser/VM/runtime files touched.
- **No canon claim.** P1–P2 decisions are lab-local.
- **No stable API.** Definition JSON format, render API shape, and interpreter are all
  proof-local candidates — nothing is committed as a public surface.
- **No client-side VM.** The interpreter reads a JSON instruction set; it does not parse
  or execute arbitrary code. `eval`/`Function()` are absent.
- **No Ruby runtime; no Tailmix gem.** The idea is proved natively.
- **LAB-ONLY.**

---

*LAB-ONLY. Proof-local. No implementation authority. No canon claim. No stable API.*
*No compiler/parser/VM change. No contract execution in the view runtime.*
*No client-side VM. No Ruby runtime.*
