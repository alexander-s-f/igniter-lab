# Igniter-Lang Language Covenant

Status: governing
Date: 2026-05-10 (enforcement registry added: S3-R30-C5-P)
Author: `[Igniter-Lang Meta Expert]`
Supersedes: nothing (new document)

> The Covenant is not a spec chapter. It is the set of commitments the language
> makes to the programmer ��� the reasons why the language is the way it is.

---

## Core Axioms

### Axiom 1 ��� Honesty

> **A program is an honest account of what it does to the world.**

If a program cannot say what it does ��� to which system, with what authority,
with what consequence, and with what evidence ��� it should not compile.

### Axiom 2 ��� Accountability (V-1)

> **A program is an accountable semantic artifact.**

Every language primitive exists to make accountability legible ��� to operators,
to auditors, and to the program's own future maintainers.

A language feature that makes the programmer's life easier but hides execution
reality from audit violates this axiom. Accountability is not a constraint on
the language ��� it is the reason the language exists.

The two axioms are not alternatives. Honesty declares the commitment; accountability
declares the mechanism. A program may be honest (it says what it does) and still
fail to be accountable (no one can verify the claim). Both must hold.

---

## The 28 Postulates

### Postulate 1 ��� Contracts, Not Procedures

A contract declares what must be true, not what must be executed in order.
The body is a dependency graph, not a sequence of commands.

```igniter
-- This is not: "first compute a, then compute b"
-- This is: "b depends on a"
compute a = input_x + 1
compute b = a * 2
```

### Postulate 2 ��� Declared Dependencies

Every computation declares what it depends on. No hidden implicit state.
A node that reads from `x` must name `x` in its dependency declaration.

### Postulate 3 ��� Explicit Time

Time is a first-class parameter, not a global variable. A contract that reads
historical state must declare `as_of: DateTime` and receive it explicitly.

```igniter
pure contract RevenueAt(region: String, as_of: DateTime) -> amount: Decimal[2]
```

### Postulate 4 ��� Named Effects

Every side effect is named. There is no I/O without a declaration. A contract
that sends a notification must declare `escape notification_send` and carry the
appropriate modifier.

### Postulate 5 ��� Immutable Outputs

A contract output is a value, not a reference. Once produced, it does not change.
Temporal history is append-only ��� correction is a new fact, not a mutation.

### Postulate 6 ��� Evidence Trails

Every output carries a provenance chain. The evidence clause names the inputs
and observations from which the output was derived.

```igniter
output risk evidence [claim, evidence_bundle]
```

### Postulate 7 ��� No Hidden Consequences

A contract's effect on the world is declared in its Effect Surface. A reader
who reads only the contract header ��� not the body ��� knows the full consequence.

### Postulate 8 ��� Receipts Are Proof

A receipt is not a log entry. It is a proof that a specific operation completed
with specific inputs and produced a specific output. Receipts are immutable.

### Postulate 9 ��� Authority Is Explicit

Authority is a value, not a role in a config file. A privileged contract receives
authority as a parameter and can be audited to confirm who authorized what.

### Postulate 10 ��� Profiles Are Policy

A profile is not configuration. It is a compile-time policy that restricts and
obligates what a contract may do. Profiles cannot be bypassed at runtime.

### Postulate 11 ��� Uncertainty Is Preserved

A model output is an observation, not a fact. An estimate carries its uncertainty
as a typed field. The language does not allow uncertainty to be silently discarded.

```igniter
type PositionEstimate {
  x: Decimal[3]
  y: Decimal[3]
  uncertainty_m: Decimal[3]   -- required, not optional
  confidence: Decimal[3]
}
```

### Postulate 12 ��� Simulation Is Labeled

A simulated receipt is a different type from a real receipt. `SimulatedDispatchReceipt`
cannot be used where `DispatchReceipt` is expected. Simulation cannot masquerade
as reality.

### Postulate 13 ��� Observation Is Typed

There are three kinds of observation: real (from the world), model (from inference),
and human (from judgment). They are different types. A model observation cannot
be used as a real observation without explicit conversion.

### Postulate 14 ��� Loops Are Managed

Every repetition belongs to a loop class with a compiler-verified contract:
finite by collection size, finite by structural variant, finite by fuel,
convergent by metric, or alive by liveness (service loop). There is no general
recursion and no unbounded loop.

Managed local loop and recursion language belongs to a future PROP-039+ or later
proposal. Service-loop liveness maps through PROP-037 progression descriptors.
No source-level loop/recursion implementation or proof fixture is implied by
this Covenant wording.

### Postulate 15 ��� Timeout Is Not Failure

A timeout waiting for an external system is `UnknownExternalOutcome`, not
`ObservedFailure`. These are different types. They require different responses:
reconciliation, not retry.

### Postulate 16 ��� Idempotency Is Declared

An operation under automatic retry must declare its idempotency key. A
non-idempotent operation in a retry-enabled profile is a compile error.

### Postulate 17 ��� Compensation Is Named

An irreversible contract must name its compensation contract or explicitly
declare `no_compensation`. The decision is visible at the declaration site.

### Postulate 18 ��� Decisions Are Separable

The decision of what to do (pure, simulatable, dry-runnable) is separate from
the act of doing it (irreversible, authority-required). The compiler enforces
this separation: an irreversible contract is unreachable from a pure context.

### Postulate 19 ��� Reversibility Is a Scale

Reversible ��� Compensatable ��� Refundable ��� Append-only ��� Irreversible ��� Destructive.

A profile may declare a maximum reversibility level. Exceeding it is a compile error.

### Postulate 20 ��� Contracts Compose

A contract that calls another contract inherits its evidence obligations. Evidence
chains form a directed acyclic graph. The compiler validates that no evidence is
lost at composition boundaries.

### Postulate 21 ��� Consequence Ownership

A program owns its consequences. If it cannot name them, it cannot claim them.
If it cannot claim them, it should not act.

> Declare it. Own it. Do not outsource responsibility.

### Postulate 22 ��� Assumption Visibility

Every assumption a program relies on must be declared, typed, and carried through
its evidence chain. A system may rely on assumptions. It must not hide them.

```igniter
assumptions {
  assumption homophily {
    kind :synthetic
    statement "People with similar beliefs interact more often."
    strength 0.70
  }
}

-- Assumptions flow through evidence:
output interaction evidence [a, b, homophily]
```

Hidden assumptions are technical debt against truth. They accumulate inside weights,
prompts, thresholds, and undocumented heuristics. Igniter makes them explicit.

> An assumption is not a weakness. A hidden assumption is.

### Postulate 23 ��� Synthetic World Visibility

A synthetic world must identify itself as synthetic. Simulated state, generated
populations, and modelled societies are different from observed reality. They must
carry explicit epistemic markers that survive receipts and lineage traversal.

```igniter
receipt SimulationReceipt {
  mode: :synthetic          -- not :observed, not :inferred
  honesty_statement: String -- required for synthetic receipts
  assumption_hash: String   -- hash of the AssumptionSet used
}
```

A simulated receipt cannot be used where an observed receipt is expected.
The type system enforces the distinction at contract boundaries.

### Postulate 24 ��� Choices Are Not Simplified Away

A system may be forced to choose under uncertainty and resource constraint.
The language forbids pretending the choice was simple.

Every consequential decision must expose:
- what was known (observed inputs with confidence)
- what was assumed (declared assumption set)
- what constraints were obeyed
- what alternatives were rejected (and why)
- who authorized the choice (authority chain)
- what consequences are expected
- what cannot be compensated if it goes wrong

This applies to financial allocation, logistics strategy, medical triage, robot
dispatch, pricing, security action, and resource planning ��� not only to emergency
rescue. Wherever a system is "forced to choose", the language makes that choice
legible.

> The system may be forced to choose.
> The language forbids pretending the choice was simple.

### Postulate 25 ��� Constraints Are Declared

A constraint is a normative or operational boundary that a program must respect.
Constraints are not buried in invariant thresholds, config values, or model weights.
They are declared at the module level alongside assumptions.

```igniter
constraints {
  constraint avoid_total_abandonment {
    kind :ethical
    priority 0.95
    statement "No settlement may be completely ignored."
  }
  constraint budget_limit {
    kind :resource
    priority 1.0
    statement "Do not allocate more crews than available."
  }
}
```

A program may optimize within its constraints.
It must not hide the constraints it chose to obey.

A contract that uses a constraint set must declare it explicitly (`uses constraints NAME`).
Constraint sets enter receipts via `constraint_hash` ��� auditable, replayable, content-addressed.

### Postulate 26 ��� Audit Completes the Decision

A decision is not complete when it is executed. It is complete only when expected
outcomes can be compared to observed outcomes ��� or when the system explicitly
declares why such comparison is impossible.

The PostAudit is not an afterthought. It closes the accountability loop:

```
Observe ��� Estimate ��� Plan ��� Decide ��� Approve ��� Act ��� Audit
```

Every consequential decision receipt must either:
1. Carry a reference to its eventual audit receipt; or
2. Declare `audit: :deferred` with a reason; or
3. Declare `audit: :impossible` with a stated reason.

A decision that produces no feedback into the system's understanding is
an accountability debt.

### Postulate 27 ��� Accountability as Architecture (V-1)

Every language primitive exists to make accountability legible. There is no
primitive that exists merely for ergonomics.

| Primitive | Accountability role |
|-----------|---------------------|
| `receipt` | Execution trace ��� what ran, when, with what inputs and outputs |
| `evidence` | Claim lineage ��� what output was derived from which prior facts |
| `assumptions {}` | Epistemic provenance ��� what premises were declared and relied upon |
| `constraints {}` | Normative boundary ��� what rules were obeyed and at what priority |
| `escape` modifier | Declared I/O intent ��� which external systems were touched |
| contract modifiers | Effect character ��� with what authority, reversibility, and consequence |
| managed loops | Controlled iteration ��� no unbounded execution surface escapes audit |
| synthetic markers | Simulated world visibility ��� no simulation masquerading as observation |
| `form` constructors | Named domain constructor ��� no unnamed semantic structure |

> A feature that makes the programmer's life easier but hides execution reality
> from audit violates the Core Axiom and this postulate.

The PROP Governance Filter (below) encodes this as a mandatory acceptance criterion.

### Postulate 28 ��� No Unnamed Block May Carry Semantic Identity (V-4)

An unnamed block is invisible to audit, linkage, and replay. If a block carries
semantic identity ��� an effect, a loop policy, an assumption context, a constraint
set ��� but has no name, it cannot be referenced in a receipt, linked in evidence,
or surfaced in an observation.

```igniter
-- Forbidden: effect without a name is unauditable
{
  escape sensor_read
  read value: Integer from "sensors/{id}"
}

-- Required: named declaration, referenceable in receipt
escape sensor_read
read value: Integer from "sensors/{id}"
```

This applies to every construct with semantic consequence:

- `escape` declarations ��� named, referenced in `escape_boundaries` of receipts
- loop class declarations ��� named, referenced in managed loop contract
- `assumptions {}` blocks ��� named, carried through `evidence []` chain
- `constraints {}` blocks ��� named, carried through `constraint_hash`
- `invariant` blocks ��� named, referenced in violation observation receipts

An unnamed construct that carries semantic consequence is a compile error.
Naming is not bureaucracy ��� it is the prerequisite for accountability.

---

## Four Axes of Language Honesty

From the pressure specimens and cross-review (S3-R28), four distinct honesty axes
have emerged. Each is orthogonal. All four must hold simultaneously.

```
epistemic honesty   ��� what we know, at what certainty, with what assumptions
effect honesty      ��� what we change, with what authority, with what compensation
constraint honesty  ��� what we must respect, of what kind, at what priority
audit honesty       ��� what happened after, how expected vs actual compared
```

These axes map to the canonical execution pipeline:

| Pipeline stage | Honesty axis | Contract class |
|----------------|-------------|----------------|
| Observe | epistemic | `observed contract` |
| Estimate | epistemic | `pure contract` |
| Plan | epistemic | `pure contract` |
| Decide | constraint | `pure contract` + `uses constraints` |
| Approve | effect | `privileged contract` |
| Act | effect | `effect`/`irreversible contract` |
| Audit | audit | `audit contract` / PostAudit pattern |

---

## The Epistemic State Machine

Agent-D (cross-review S3-R28) named this: the honesty stack is not a certainty
scale ��� it is an **epistemic state machine** with typed transitions.

| State | Meaning | Example |
|-------|---------|---------|
| `observed` | Directly witnessed from the world | `drone.sensor.reading` |
| `inferred` | Derived from observations by reasoning | `survivor_zone = derive_zone(signal)` |
| `estimated` | Probabilistic quantified inference | `confidence: 0.72` |
| `assumed` | Declared premise (`kind: :empirical/:heuristic`) | `assumptions {}` block |
| `simulated` | Synthetic world state | `epistemic_kind: :synthetic` |
| `decided` | Chosen action under constraints | `StrategyDecision` |
| `executed` | External consequence receipt | `DispatchReceipt` |
| `audited` | Expected vs actual comparison | `PostAuditReceipt` |

**Critical rule ��� No Upward Coercion:**

A value may not move to a higher-certainty epistemic state without an explicit
typed conversion or human review:

```
assumed   ��� observed    FORBIDDEN without explicit review
simulated ��� executed    FORBIDDEN (type error)
estimated ��� known       FORBIDDEN (no silent certainty upgrade)
inferred  ��� fact        FORBIDDEN
```

This rule is enforced by the type system at contract boundaries.

**Open (S3-R28):** The exact mechanism for the `uses assumptions` / `uses constraints`
declaration and how it gates upward coercion is not yet specified. Requires Gap-H
and Gap-J PROPs.

---

## PROP Governance Filter (V-2)

Every PROP that proposes a language feature must answer:

> Does this feature leave the audit trail **more legible**, **neutral**, or **less legible**?

| Answer | Acceptance |
|--------|-----------|
| More legible | Preferred ��� explicitly advances Axiom 2 (Accountability) |
| Neutral | Permitted ��� does not harm audit legibility |
| Less legible | Rejected ��� must not enter core |

This filter applies at **PROP acceptance time**, before implementation. A PROP that
cannot answer the legibility question is not ready for acceptance review.

Applied across feature categories:

| Feature category | Acceptance |
|----------------|-----------|
| Deterministic pure computation | Allowed without explicit declaration |
| External access (I/O, time, randomness) | Requires explicit modifier |
| Non-deterministic or environment-dependent | Requires explicit declaration |
| Hidden state access | Forbidden |
| Unnamed block carrying semantic identity | Forbidden (Postulate 28) |
| Feature that hides execution from audit | Rejected by this filter |

The filter is not a style rule. It is a direct consequence of Axiom 2 and Postulate 27.
Any PROP accepted while failing this filter is an accountability debt against the
language's own covenant.

**Corollary for deprecation:** A feature that can be removed without harming audit
legibility may be deprecated. A feature that, if removed, would reduce audit legibility
is load-bearing and requires a replacement before removal.

---

## Three Doctrines

### Honest Computing Doctrine

> The compiler is not only a correctness checker. It is an honesty checker.

The language must not hide:

| What | How it hides | Language response |
|------|-------------|-------------------|
| Consequence | Effect buried in body | Effect Surface at declaration |
| Uncertainty | `confidence: 1.0` without proof | `uncertainty_m` required field |
| Authority | Environment variable / ambient permission | Authority as typed value |
| Simulation | Simulated receipt = real receipt | Different types |
| Mutation | Write disguised as read | `effect`/`privileged`/`irreversible` modifiers |
| Irreversibility | "Just retry" | `compensation` field or `no_compensation` |
| Ambiguity | Generic `Any` at boundary | No `Any` at contract boundaries |
| Provenance | Output with unknown source | `output ... evidence [refs]` |
| Assumptions | Premise buried in weights/config/threshold | `assumptions {}` block ��� declared, typed, hashable |
| Synthetic world | Simulation presented as observation | `:synthetic` mode + `honesty_statement` in receipt |
| Constraints | Normative boundary in config/hardcoded constant | `constraints {}` block ��� declared, typed, `constraint_hash` |
| Rejected alternatives | "We chose X" without showing what was rejected | `StrategyDecision.rejected` ��� discarded options in receipt |
| Audit gap | Decision with no outcome feedback | `audit:` field in decision receipt ��� Postulate 26 |

### Managed Recursion Doctrine

> A loop is a contract over state transition. It must be declared, not assumed.

Every loop must be:
- **Stoppable** ��� there is a signal that terminates it
- **Observable** ��� there is a signal that proves it is alive
- **Bounded** ��� either termination is proven, or each step is bounded in time

A loop that cannot make these guarantees should not be written.

### Stoicism as Architecture

The language does not prevent bad outcomes. It makes them visible, named, and
owned. A system built in Igniter-Lang fails loudly, with evidence, with a named
compensation path, and with a complete receipt trail. It does not fail silently.

> We cannot control what the network does. We can control what we declare about it.

---

## What the Language Forbids

- Hidden effects (all must be declared in modifier + Effect Surface)
- Silent type erasure (`Any` at boundaries)
- Implicit side effects in pure contracts
- `now()` anywhere ��� time must enter as explicit input or tick binding (see Ch8
  `OOF-L6`; this Covenant cross-reference does not mint a new OOF registry code)
- Non-idempotent operations under automatic retry
- Unbounded loops (every repetition has a class)
- Simulated receipts masquerading as real (separate types)
- `timeout` treated as `failure` (different types, different paths)
- Hidden assumptions (must be declared, typed, and carried through evidence)
- Hidden constraints (must be declared in `constraints {}`, not buried in thresholds)
- Unnamed DSL blocks with semantic consequence (Postulate 28 ��� named, or not compiled)
- Upward coercion without review (`assumed ��� observed` is a type error)
- Pretending a consequential choice was simple (Postulate 24 ��� rejected alternatives must appear in receipt)

---

## Cross-Reference to Spec

| Postulate | Spec chapter | PROP | Spec status | Enforcement status |
|-----------|-------------|------|-------------|-------------------|
| 1���2 | ch1 (Identity), ch2 (Grammar) | PROP-001, PROP-014 | ��� | `enforced` |
| 3 | ch9 (Temporal) | PROP-022 | ��� | `enforced` |
| 4, 7, 16, 17, 19 | ch12 (Effect Surface) | PROP-035 | pending | `planned PROP` |
| 5 | ch9 (BiHistory) | PROP-022 | ��� | `enforced` |
| 6, 20 | ch10 (Modifiers ��10.5) | PROP-031, PROP-033 | PROP-031 ��� | `planned PROP` (PROP-033) |
| 8 | ch12 (receipt field) | PROP-035 | pending | `planned PROP` |
| 9 | ch12 (authority field) | PROP-035 | pending | `planned PROP` |
| 10 | ch11 (Profile System) | PROP-034 | pending | `planned PROP` |
| 11 | ch10 (observed modifier) | PROP-031 | ��� | `planned PROP` (PROP-035 required-field enforcement) |
| 12 | ch10 (observed modifier) | PROP-031 | ��� | `planned PROP` (PROP-035 receipt type enforcement) |
| 13 | ch10 (observed modifier) | PROP-031 | ��� | `enforced` (classifier fragment class) |
| 14 | ch13 (Managed Recursion) | PROP-039+ or later; PROP-037 for service liveness | pending | `planned PROP` |
| 15 | ch12 (failure taxonomy) | PROP-035 | pending | `planned PROP` |
| 18 | ch10 (pure/irreversible separation) | PROP-031 | ��� | `enforced` |
| 21 | ch12 (Effect Surface, all fields) | PROP-035 | pending | `planned PROP` |
| 22 | Gap-H (assumptions block) | PROP-032 | open | `planned PROP` |
| 23 | Gap-H (synthetic receipt type) | TBD | open | `spec_candidate` |
| 24 | Gap-J (constraints block) + ch12 | TBD | open | `spec_candidate` |
| 25 | Gap-J (constraints block) | TBD | open | `spec_candidate` |
| 26 | Gap-N (audit contract/pattern) | TBD | open | `spec_candidate` |
| 27 | Axiom 2 (Accountability) ��� all surfaces | ��� | Covenant governing | `doctrine-only` |
| 28 | Governance: unnamed block rule | PROP-035 + PROP-039+ loop-class routing | partial | `partial` ��� see enforcement registry |

---

## Covenant Promise Enforcement Registry

Every Covenant promise must declare an enforcement path. This section assigns
a formal status to every postulate and defines the rule for new additions.

### Status Vocabulary

| Status | Meaning | Required citation |
|--------|---------|------------------|
| `enforced` | The compiler currently rejects violations at parse, classify, or type-check time | Cite the mechanism and the implementing PROP or proof anchor |
| `planned PROP` | A PROP exists or is queued that will wire compiler enforcement | Cite PROP number or named queue slot (Gap label if no PROP yet drafted) |
| `spec_candidate` | The concept is defined in the Covenant or CSM but no PROP is queued | Cite CSM row; state what evidence or design work is needed to advance to a PROP |
| `doctrine-only` | Intentionally not a compiler rule; compliance maintained by a non-compiler mechanism | Explain the enforcement mechanism (PROP filter, review gate, governance policy) |
| `partial` | Enforced for some named surfaces; pending PROP for others | Expand in a per-surface subtable |

### Rule

> Every postulate added to the Covenant must carry one of the statuses above
> before it is accepted. A postulate without a status is incomplete.
>
> - `planned PROP` requires a cited PROP number or named queue slot.
> - `spec_candidate` requires a cited CSM row.
> - `doctrine-only` requires an explicit statement of the non-compiler enforcement mechanism.
> - `partial` requires a per-surface subtable.
>
> When a PROP advances and wires enforcement, the postulate status must be
> updated to `enforced` in the same PROP card or an accompanying Meta Expert
> card. Enforcement status drift (PROP ships but Covenant table not updated)
> is a spec-lag item subject to META-EXPERT-012 lifecycle policy.

### Postulate Enforcement Status Registry

| Postulate | Promise summary | Enforcement status | Mechanism / PROP |
|-----------|----------------|-------------------|-----------------|
| P1 | Contracts are dependency graphs, not sequences | `enforced` | GraphCompiler validates DAG; DSL rejects imperative sequences |
| P2 | Every computation declares its dependencies | `enforced` | Compiler requires explicit `depends_on:`/`with:` on all compute nodes |
| P3 | Time is an explicit parameter (`as_of: DateTime`) | `enforced` | TEMPORAL fragment (PROP-022 ���); History[T] requires `as_of` input; source-level `now()` forbidden (Ch8 `OOF-L6` wording anchor) |
| P4 | Every side effect is named (`escape` modifier) | `planned PROP` | PROP-035 (Effect Surface); effect declaration not yet enforced as required field on all I/O |
| P5 | Contract outputs are immutable values | `enforced` | Frozen CompiledGraph; append-only history type; no mutation API at runtime |
| P6 | Every output carries a provenance chain (`evidence []`) | `planned PROP` | PROP-033 ��� evidence chains at composition boundaries; not yet enforced at output declaration |
| P7 | Effect Surface readable from contract header alone | `planned PROP` | PROP-035 ��� Effect Surface as separate declared block |
| P8 | Receipts are immutable proofs of specific operations | `planned PROP` | PROP-035 ��� receipt field schema with required fields |
| P9 | Authority is a typed value, not an ambient role | `planned PROP` | PROP-035 ��� `authority:` required field on privileged/irreversible contracts |
| P10 | Profiles are compile-time policy, not runtime config | `planned PROP` | PROP-034 (Profile System) |
| P11 | Uncertainty is a required typed field, not silently dropped | `planned PROP` | PROP-035 ��� required-field enforcement on observation types; PROP-031 ��� classifies modifier |
| P12 | Simulated receipts are a different type from real receipts | `planned PROP` | PROP-031 ��� classifies fragment; PROP-035 enforces type incompatibility at contract boundaries |
| P13 | Real / model / human observations are distinct types | `enforced` | PROP-031 ��� ��� classifier assigns fragment class; modifier system enforces distinction at classification |
| P14 | Every repetition belongs to a loop class with a compiler-verified contract | `planned PROP` | PROP-039+ or later for managed local recursion / loop classes; PROP-037 owns service-liveness progression descriptors |
| P15 | Timeout is `UnknownExternalOutcome`, not `ObservedFailure` | `planned PROP` | PROP-035 ��� failure taxonomy with distinct types |
| P16 | Non-idempotent operations under retry are a compile error | `planned PROP` | PROP-035 ��� idempotency key requirement on retry-enabled profiles |
| P17 | Irreversible contracts name their compensation or declare `no_compensation` | `planned PROP` | PROP-035 ��� `compensation:` required field on irreversible contracts |
| P18 | Irreversible contract unreachable from pure context | `enforced` | PROP-031 ��� ��� pure/irreversible separation enforced at classifier; TypeChecker propagates fragment class |
| P19 | Profile may declare max reversibility level; exceeding it is a compile error | `planned PROP` | PROP-035 + PROP-034 ��� reversibility scale + profile enforcement |
| P20 | Contract composition preserves evidence chains | `planned PROP` | PROP-033 ��� evidence chain DAG validation at composition boundaries |
| P21 | A program names all its consequences | `planned PROP` | PROP-035 ��� Effect Surface; all effect fields required at declaration |
| P22 | Every assumption is declared, typed, and carried through evidence | `planned PROP` | PROP-032 (Gap-H) ��� assumptions block; `uses assumptions NAME` enforced at call site. ������ Queue conflict: proposals/README.md reserves PROP-032 for `via profile binding`; CSM and agent-context assign PROP-032 to this surface. Must be resolved before authoring. See semantic-governance-heat-map.md ��GI-1. |
| P23 | Synthetic world state must carry epistemic markers that survive receipts | `spec_candidate` | CSM: `SimulationReceipt` shape defined; no PROP yet; requires Gap-H PROP + receipt type system |
| P24 | Consequential choices must expose inputs, assumptions, constraints, alternatives, authority | `spec_candidate` | CSM: `StrategyDecision` shape defined; no PROP yet; requires Gap-J PROP + ch12 effect surface |
| P25 | Constraints are declared, typed, and carried through `constraint_hash` | `spec_candidate` | CSM: `constraints {}` block defined; no PROP yet; Gap-J PROP required before implementation |
| P26 | A decision is complete only when expected outcome is compared to actual | `spec_candidate` | CSM: `PostAuditReceipt` shape defined; Gap-N PROP required; `audit:` field on decision receipts |
| P27 | Every language primitive exists to make accountability legible | `doctrine-only` | Enforced by the PROP Governance Filter at proposal acceptance time, not by compiler. P27 IS the governance axiom from which all compiler-enforced postulates derive their authority. No compiler rule needed ��� any PROP that reduces audit legibility is rejected by the filter. |
| P28 | No unnamed block may carry semantic identity | `partial` | `invariant` blocks: `enforced` (parser requires name). Other surfaces: see P28 enforcement table below. |

---

### Postulate 28 ��� Per-Surface Enforcement Table

P28 applies to five named construct families. Enforcement status differs across
surfaces because some have no compiler implementation yet.

| P28 surface | What P28 requires | Current enforcement | Enforcement path |
|------------|-------------------|---------------------|-----------------|
| `invariant` block | Must have a name; referenced in violation observation receipts | **`enforced`** ��� parser requires name; unnamed `invariant` is a parse error today | Already enforced; anchor: parser spec |
| `escape` declaration | Must be named; referenced in `escape_boundaries` of receipts | **Unknown** ��� Compiler/Grammar Expert must verify (OQ-P28-1 below) | `planned PROP` ��� PROP-035 (Effect Surface) should formalize naming requirement |
| Loop class declaration | Must be named; referenced in managed loop contract | **N/A** ��� loop classes not yet implemented | `planned PROP` ��� PROP-039+ or later; naming requirement must be explicit in the eventual managed local recursion / loop-class PROP draft |
| `assumptions {}` block | Must be named; carried through `evidence []` chain | **N/A** ��� Gap-H not yet implemented | `planned PROP` ��� PROP-032 (Gap-H); `uses assumptions NAME` syntax enforces naming |
| `constraints {}` block | Must be named; carried through `constraint_hash` | **N/A** ��� Gap-J not yet implemented | `spec_candidate` ��� `planned PROP` when Gap-J PROP is queued |

**P28 current enforcement summary:** Only `invariant` block naming is enforced by
the compiler today. All other P28 surfaces are either unimplemented or unverified.
P28 is a **governing commitment** across the full surface; current enforcement is
partial. A future card (or OQ-P28-1 response from Compiler/Grammar Expert) should
promote the `escape` declaration row from Unknown to Enforced or Planned PROP.

---

### Open Questions for Compiler/Grammar Expert (from this section)

**OQ-P28-1 ��� `escape` declaration naming enforcement**

Is an unnamed `escape` declaration currently a parse error, or is it silently
accepted? Specifically:

```igniter
-- Is this currently refused by the parser?
escape
read value: Integer from "sensors/{id}"

-- Or is escape always positional/anonymous at this stage?
escape sensor_read
read value: Integer from "sensors/{id}"
```

Expected answer: the Compiler/Grammar Expert should check the parser and classify
the `escape` row in the P28 surface table as `enforced` (parse error today) or
`planned PROP` (not yet wired). This closes the "Unknown" entry above and the
longstanding OQ-1 from `covenant-accountability-postulates-r29-v0.md`.

Deliverable: a single row update to the P28 surface table above, either in a
Compiler/Grammar Expert track doc or as an addendum to this section.

**OQ-P28-2 ��� PROP-035 Effect Surface should include a P28 enforcement clause**

When PROP-035 (Effect Surface) is drafted, it should include an explicit clause
requiring that every `escape` declaration carry a name that appears in the receipt
`escape_boundaries` field. This ensures that P28 enforcement for escape declarations
is a first-class PROP-035 acceptance criterion, not a later errata.

Question for Compiler/Grammar Expert: should PROP-035 be the home for escape naming
enforcement, or should a separate escape-naming-enforcement PROP be filed?

**OQ-P28-3 ��� PROP-039+ loop class naming**

When the future PROP-039+ Managed Recursion proposal is drafted, the loop class
naming requirement from P28 must be an explicit acceptance condition in the PROP.
No unnamed loop class may carry a managed-loop contract.

Question for Compiler/Grammar Expert: should the P28 requirement for loop class
naming be stated in the future PROP acceptance criteria or in a separate invariant
section of ch13?

**OQ-Enforcement-1 ��� enforcement status table maintenance ownership**

The Postulate Enforcement Status Registry above must be kept current as PROPs
ship. Who owns updates?

Proposed rule: the PROP card that wires new enforcement must update the registry
as part of its deliverables (or route the update to a same-round Meta Expert status
card). If the PROP ships without updating the registry, the gap is a spec-lag item
tracked by META-EXPERT-012.

Question: should this rule be added to META-EXPERT-013 ��VI acceptance criteria?

**OQ-Filter-1 ��� PROP Governance Filter source-of-truth (RESOLVED by S3-R31-C2-A)**

The PROP Governance Filter (V-2) is a Covenant section (��PROP Governance Filter above).
META-EXPERT-013 ��VI defines PROP acceptance criteria. Both govern what PROPs may contain,
but they were separate documents with no normative cross-reference. S3-R31-C2-A
resolved the precedence rule:

```text
Covenant is normative. META-EXPERT-013 cites it and defers to it.
```

Authority reference:
`docs/gates/prop-governance-authority-decision-v0.md`.

When a PROP is under review, authors must answer the Covenant audit-legibility
filter first, then satisfy the operational checklist in META-EXPERT-013.
META-EXPERT-013 may add stricter process requirements, but it may not weaken the
Covenant.

Three options:

| Option | Description |
|--------|-------------|
| A | Covenant is normative. META-EXPERT-013 ��VI cites it and defers to it. **Selected by S3-R31-C2-A.** |
| B | META-EXPERT-013 ��VI is the operational reference. Covenant ��PROP-Gov-Filter cites ��VI. |
| C | A new META-EXPERT proposal consolidates both into a single PROP lifecycle document. |

P-31 / OQ-Filter-1 is closed. This resolution does not authorize any new
language semantics or PROP-032 implementation.
