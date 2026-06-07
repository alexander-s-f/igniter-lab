# Agent Handoff: LAB-IGNITER-VIEW-FRAMEWORK-P4

Card: LAB-IGNITER-VIEW-FRAMEWORK-P4
Agent: [Igniter-Lang Research / Implementation Agent]
Role: research-design-agent
Track: lab-igniter-view-dsl-grammar-and-portability-boundary-v0
Status: done
Date: 2026-06-06
Type: research / design — no code implementation, no runtime changes
IGV-G1..G9: all VERIFIED by analysis

---

## [D] Decisions

**D1 — Grammar resolves param/slot overloading via production context, not keyword split.**
`param_decl` (statement position, has `type:`) and `param_expr` (expression position, no `type:`)
are distinct grammar productions. Same surface keyword, unambiguous via LL(2) lookahead.
Same approach applies to `slot_decl` vs `slot_expr`. No new keywords needed.

**D2 — Undeclared slot: dual policy, explicitly documented.**
- Grammar-based parser route: WF-6 MUST-error. Artifact not produced. Hard early failure.
- Ruby DSL route (existing P3): warning only. Artifact produced. P2 `filterSlotValues` safety net.
Both are correct for their context. Not a contradiction.

**D3 — Ruby DSL remains the authoring frontend. No grammar-based parser required for P5.**
The `instance_eval` prototype is a valid and sufficient lab implementation. A grammar-based
parser (Tier 1+) would be required for: public syntax claim, IDE tooling, cross-language
compilation, or CI linting.

**D4 — ViewArtifact schema unchanged. Grammar targets existing format exactly.**
The grammar→artifact mapping table in the design doc shows a lossless mechanical mapping.
Zero new artifact JSON fields. Confirmed by P3 digest bit-identity.

**D5 — Banned opcode set extended in grammar to include `ajax`, `xhr`.**
These were implicit (subsumed by `fetch` gate) in P1–P3 runtime. Grammar names them explicitly.
SHOULD update `BANNED_OPCODES` arrays in future runtime pass (non-blocking for P5).

**D6 — Source map hooks are aspirational. Not required for P5.**
Grammar annotation model documented. P3 compiler does not emit source maps. A future
grammar-based parser SHOULD emit source maps from the start.

---

## [S] Shipped

### New files created

| File | Description |
|---|---|
| `igniter-view-engine/docs/igv-grammar-sketch-v0.ebnf` | Full ISO/IEC 14977 EBNF grammar (~25 productions, WF-1..8, WW-1..3, banned opcode list, source map annotation) |
| `lab-docs/lab-igniter-view-dsl-grammar-and-portability-boundary-v0.md` | Design doc: grammar walkthrough, all design decisions, portability tiers, grammar→artifact mapping, diagnostics model, P3 findings evaluation, IGV-G1..G9 proof matrix, P5 recommendation |
| `.agents/LAB-IGNITER-VIEW-FRAMEWORK-P4.md` | This handoff |

### Existing files untouched

- `igniter-lang/**` — not edited
- `tailmix/**` — not edited
- `igniter-view-engine/**` code files — not edited
- `igniter-view-engine/lib/` — not edited
- `igniter-view-engine/fixtures/` — not edited
- All proof runners — not edited
- All generated `out/` artifacts — not modified (P4 is design-only)

---

## [T] Proof Matrix

*Verification method: analysis and cross-reference to P1/P2/P3 artifacts. No executable runner — P4 is a research/design card.*

| Check | Result | What it verifies |
|---|---|---|
| IGV-G1 | ✅ VERIFIED | Grammar covers all `tabs.igv` constructs (`view_decl`, `state_decl`, `slot_decl`, `element_def`, `classes_stmt`, `param_decl`, `display_stmt`, `binary_expr`, `ui_state_expr`, `param_expr`, `slot_expr`, `on_stmt`, `set_instr`) |
| IGV-G2 | ✅ VERIFIED | Grammar covers `static_page.igv` (view with no state/slots/rules; `element_body` items are all optional) |
| IGV-G3 | ✅ VERIFIED | `param_decl` vs `param_expr` and `slot_decl` vs `slot_expr` are unambiguous by production context; LL(2) lookahead resolves both without new keywords |
| IGV-G4 | ✅ VERIFIED | Grammar → ViewArtifact JSON mapping is lossless; no new schema fields; P3 digest bit-identity proves compiler already implements this mapping correctly |
| IGV-G5 | ✅ VERIFIED | `instruction` production is closed: only `set_instr | toggle_instr | clear_instr` allowed; any other identifier = MUST-error; grammar extends banned set to include `ajax`, `xhr` |
| IGV-G6 | ✅ VERIFIED | All P3 diagnostic types have grammar constraint equivalents; three new SHOULD-warnings added: `undeclared_param_reference`, `undeclared_state_reference`, `missing_static_classes` |
| IGV-G7 | ✅ VERIFIED | Runtime, SSRRenderer, ViewArtifact schema all unchanged; grammar is source-language design only |
| IGV-G8 | ✅ VERIFIED | Grammar carries `DESIGN SKETCH — experimental · lab-only · no-canon · no-public-api`; no changes to `igniter-lang/**`; artifact `non_claims` preserves `"no-stable-syntax"` |
| IGV-G9 | ✅ VERIFIED | P5 recommendation provided with rationale and evaluation matrix |

---

## [R] Risks and Recommendations

**Risk 1 — Grammar portability claim is aspirational.**
The EBNF sketch is a design artifact, not a tested grammar. It has not been fed to a parser
generator. Production/precedence issues may exist. A Tier 1 parser prototype would be needed
to validate the grammar mechanically.

**Risk 2 — Dual policy for undeclared slot is a split-brain model.**
The grammar says MUST-error; the Ruby DSL says warning. Developers who read the grammar may
expect hard errors and be surprised by the DSL behavior. Design doc is explicit about this
but future implementations should converge on one policy (grammar route preferred).

**Risk 3 — `ajax`/`xhr` extension to banned opcode set not yet reflected in runtime.**
The grammar names them; the P1–P3 runtime does not. This is non-blocking (the runtime's
`ALLOWED_OPCODES` gate blocks all unlisted opcodes anyway), but consistency requires a future
runtime pass to add `ajax` and `xhr` to `BANNED_OPCODES`.

**Risk 4 — Slot-contract type linkage (Finding 4 from P3) remains open.**
The grammar treats `from: "contract.path"` as an opaque string. No validation of path
existence or type compatibility. This is the most significant static type gap. Closing it
requires Igniter contract schema introspection at compile time — out of scope for P4/P5.

---

## P5 Recommendation

**Recommended: Option A — Collection Rendering**

Extend `.igv` DSL with a `collection` keyword for repeated element instances. This would:
- Prove DSL ergonomics for lists/tables/grids
- Require the first (small) `ViewArtifact` schema extension (`collections` key)
- Feed back grammar pressure: does the grammar need a `:repeat` display rule kind?
- Keep lab momentum on the primary DSL track

Alternative candidates:
- Option B (Slot-Contract Type Linkage): valuable, but blocked on contract introspection API
- Option C (Grammar-based Parser Tier 1): validates this grammar, but significant effort
  relative to incremental semantic value at this stage
- Option D (Hold): conserves effort, loses momentum

Candidate new grammar productions for P5 (sketch only, not authoritative):
```ebnf
view_stmt    += collection_def ;
collection_def = 'collection' , symbol , 'do' , collection_body , 'end' ;
collection_body = { classes_stmt | each_def | display_stmt } ;
each_def     = 'each' , symbol , 'do' , element_body , 'end' ;
```

---

## Baseline Carried Forward

P1: 37/37 PASS
P2 structural: 18/18 PASS
P2 dynamic (Node.js DOM): 15/15 PASS
P3: 42/42 PASS
tabs.igv digest: sha256:ed8ab03d35487fa14bca3598402670feae7e2962c39581dcbc942ea16456c404
ViewArtifact schema: unchanged from P1
Runtime JS: unchanged from P2
SSRRenderer: unchanged from P1
igniter-lang/**: untouched throughout P1–P4
