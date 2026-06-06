# Agent Handoff: LAB-TAILMIX-P1-A

Card: LAB-TAILMIX-P1-A
Agent: [Igniter-Lang Research Agent]
Role: research-agent
Track: lab-tailmix-concept-applicability-to-igniter-gui-v0
Route: EXPERIMENTAL / LAB-ONLY / RESEARCH
Status: done
Date: 2026-06-06
Complements: LAB-TAILMIX-P1.md (existing artifact from prior agent)

---

## [D] Decisions

**D1 — UIState / SlotValue Must Be Named Separately**
Tailmix unifies mutable UI state and data-driven display under a single `state` key.
Igniter must not do this. UIState (tab active, panel open) is transient and IDE-local.
SlotValue (contract_output_ref) is injected from an immutable execution receipt.
Conflating them violates Postulate 5 (outputs are immutable) and Postulate 8
(receipts are proofs). Any future GUI IR schema must declare these as distinct
primitives from the start.

**D2 — Display Rules and Interaction Rules Are Separate Arrays**
`[:style, ...]` and `[:match, ...]` rules are display-only: pure functions from
`(ui_states, slot_refs, node_params)` → class/aria patch. `[:on, event, instructions]`
are interaction rules: they trigger UIState mutations. They must be evaluated by
separate evaluators with separate permission scopes. Merging them (as Tailmix does
in `element.rules`) would allow an interaction rule to accidentally influence display
evaluation order.

**D3 — `fetch` / `dispatch` / `boot` / `watch` / `persistence` Are Rejected**
All four violate the Igniter accountability model (Postulates 4, 7, 2). `fetch`
creates unaudited I/O with no declared `escape`. `dispatch` creates implicit
cross-component dependency outside the compiler graph. `boot` implies component
lifecycle Igniter does not have. `watch` requires a running JS component.
`persistence` is not a contract presentation concern. These are not soft rejections;
any future lab prototype that includes them must justify against the Covenant explicitly.

**D4 — Mirrored Interpreter Is a Test Strategy, Not Architecture**
The Tailmix Ruby/JS mirror is valuable evidence that a rule array format can be
tested in pure Ruby without a browser. Igniter's GUI IR prototype should adopt this
as a testing practice (RSpec fixtures + evaluator) but must not build a Ruby runtime
mirror of the IDE's Svelte evaluator as a production artifact.

**D5 — `param` Per-Node Context Is Directly Applicable**
Tailmix's `param` (per-element render context: `param.id`, `param.size`) maps
directly to the need in Igniter's collection rendering: each item in a
`Collection[T]` output needs its own render context. The `node_params` scope slot
in the candidate IR sketch (§5.3 of research doc) formalizes this.

---

## [S] Shipped

- **Research document (variant A):**
  `igniter-lab/lab-docs/lab-tailmix-concept-applicability-to-igniter-gui-v0-A.md`
  Contains:
  - Six-layer Tailmix architecture breakdown (TMX-R1)
  - UIState vs. SlotValue naming decision with Covenant citations (TMX-R2)
  - Rule/effect model mapping with scope restrictions (TMX-R3)
  - Instruction opcode whitelist with safety envelope (TMX-R4)
  - Field-by-field Definition Hash comparison + candidate IR sketch (TMX-R5)
  - Mirrored interpreter as test strategy (TMX-R6)
  - Full Rails/Arbre/Tailwind rejection table (TMX-R7)
  - `fetch`/`dispatch` Covenant violation citations (TMX-R8)
  - Per-GUI-target applicability table (TMX-R9)
  - LAB-TAILMIX-P2 recommendation with hard constraints (TMX-R10)

- **This handoff card:**
  `igniter-lab/.agents/LAB-TAILMIX-P1-A.md`

---

## [T] Files Inspected

| File | Purpose |
|---|---|
| `igniter-lang/docs/language-covenant.md` | Covenant postulates governing all decisions |
| `tailmix/README.md` | Architecture overview, DSL reference |
| `tailmix/AGENTS.md` | Component development guide, layout rules |
| `tailmix/lib/tailmix/dsl.rb` | DSL entry point |
| `tailmix/lib/tailmix/ast/nodes.rb` | Full AST node type inventory |
| `tailmix/lib/tailmix/compiler/json_generator.rb` | Compiler output format (rule arrays) |
| `tailmix/lib/tailmix/dsl/action_parser.rb` | Instruction opcode definitions |
| `tailmix/app/javascript/tailmix/runtime/component.js` | JS component lifecycle + state model |
| `tailmix/app/javascript/tailmix/interpreter/action_interpreter.js` | Opcode execution + `fetch` implementation |
| `tailmix/app/javascript/tailmix/interpreter/renderer.js` | Rule evaluation → attribute accumulator |
| `tailmix/tailmix-ui/lib/tailmix_ui/components/tabs.rb` | Full component example (state + variant + event + style) |
| `igniter-lab/lab-docs/lab-igniter-lang-to-gui-research-boundary-v0.md` | Existing GUI research boundary |
| `igniter-lab/lab-docs/lab-experimental-view-tree-renderer-contract-and-typecheck-cleanup-v0.md` | VCON safety hardening |
| `igniter-lab/lab-docs/lab-experimental-view-tree-safe-policy-edgecases-and-state-slot-preflight-v0.md` | VSLOT-1 StateSlot schema |
| `igniter-lab/lab-docs/lab-tailmix-concept-applicability-to-igniter-gui-v0.md` | Prior agent P1 research (read for complement, not duplicate) |
| `igniter-lab/.agents/LAB-TAILMIX-P1.md` | Prior agent P1 handoff |

---

## [R] Risks and Recommendation

**Risks:**
- **Conflation risk (High):** If UIState and SlotValue are not explicitly separated in
  the P2 schema from day one, lab prototypes will mix them and the separation will
  require a breaking refactor later. This is the highest-priority architectural risk.
- **Opcode creep risk (Medium):** Once a `set`/`toggle` evaluator exists in the IDE,
  pressure to add `fetch` (for "just load the dropdown options") is predictable.
  Hard-coding the rejection in the schema validator (not just documentation) is necessary.
- **Scope drift risk (Medium):** The GUI IR prototype, once it works for tabs, may get
  used for form submission handling (which requires capability validation). Explicit
  authority boundary in the P2 card is needed.

**Recommendation:**
Proceed with **LAB-TAILMIX-P2: Static GUI Interaction IR — UIState/SlotValue Schema
and Safe Opcode Evaluator Prototype**.

Priority within P2 work:
1. UIState / SlotValue schema separation (formal JSON schema + TypeScript types)
2. Display rule evaluator (pure function: display_rules + ui_states + slot_refs + node_params → patch)
3. Interaction rule evaluator (UIState-target-only opcode whitelist)
4. One pilot integration in ContractFormGenerator or ViewInspector (tab navigation)
5. RSpec-style fixture tests for the rule evaluator (no browser required)

If forming bandwidth is constrained, consider partial P2: schema only (items 1),
deferring evaluator implementation to a later card after forms lowering completes.
