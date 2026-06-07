# Agent Handoff: LAB-TAILMIX-P1

Card: LAB-TAILMIX-P1
Agent: [Igniter-Lang Research Agent]
Role: research-agent
Track: lab-tailmix-concept-applicability-to-igniter-gui-v0
Status: done

## [D] Decisions
- **Decouple from Framework Implementations:** Rejected direct imports, Rails engines, Arbre SSR wrappers, and Tailwind-specific components to protect Igniter-Lang's syntax and runtime integrity.
- **Adopt Serializable Action IR for UI Interactions:** Approved exploring a restricted declarative opcode schema (like `set` and `toggle` arrays) to represent interactive events in the View DSL, rather than allowing inline JS or complex framework runtimes.
- **State Separation:** Classified state-slots into "immutable execution receipts" (core compiler runtime outputs) and "local UI interaction states" (transient loading/toggle states).

## [S] Shipped / Signals
- **Research Document:** Created [lab-tailmix-concept-applicability-to-igniter-gui-v0.md](../../../../lab-docs/gui/lab-tailmix-concept-applicability-to-igniter-gui-v0.md) detailing:
  - Tailmix architecture, concepts, and mappings to Igniter analogues.
  - Rejection matrix for Rails, Arbre, and Tailwind integrations.
  - Detailed security boundaries including sandbox execution and IO Capability Passport interception.
- **Handoff Card:** Created this card at [LAB-TAILMIX-P1.md](LAB-TAILMIX-P1.md).

## [T] Tests / Proofs
- Evaluated against Svelte renderer logic in [ViewNodeRenderer.svelte](../../../../igniter-ide/src/lib/components/ViewNodeRenderer.svelte) and safety parameters in [safe_renderer_policy.ts](../../../../igniter-ide/src/lib/safe_renderer_policy.ts).
- Audited Tailmix's Ruby AST compilation ([json_generator.rb](../../tailmix/lib/tailmix/compiler/json_generator.rb)) and browser component runtime ([component.js](../../tailmix/app/javascript/tailmix/runtime/component.js)) for structural mappings.

## [R] Risks / Recommendations
- **Risks:**
  - Overcomplicating client-side behavior by reinventing a full state management framework.
  - Bypassing the compiler's strict type-safety checks via local, dynamically evaluated state attributes.
- **Recommendations:** Keep all UI state-slot rules passive, declarative, and inspectable inside the IDE dashboard panel before considering any runtime lowerings.

## [Next] Suggested next slice
- **LAB-TAILMIX-P2: Static GUI Interaction IR Design & State-Slot Rule Prototype**
  - Design a JSON schema for `interaction_rules.json` representing simple form input changes and tab switches using a safe opcode array.
  - Implement a basic Svelte-side evaluator in [safe_renderer_policy.ts](../../../../igniter-ide/src/lib/safe_renderer_policy.ts) to execute local UI toggle state switches on state-slots.
  - Mock a preview tab switch inside the IDE component inspector using this evaluation model.
