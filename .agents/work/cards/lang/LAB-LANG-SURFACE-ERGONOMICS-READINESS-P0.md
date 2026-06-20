# LAB-LANG-SURFACE-ERGONOMICS-READINESS-P0 - Focus the application-pressure language polish lane

Status: CLOSED
Lane: parallel / surface-ergonomics
Type: readiness / prioritization
Delegation code: OPUS-LANG-SURFACE-ERGONOMICS-P0
Date: 2026-06-20
Skill: idd-agent-protocol

## Context

IgWeb/Todo/View/Postgres proofs have pushed `.ig` from substrate proofs into application authoring. The
result is encouraging: contracts, records, variants, `Result`/`Option`, `match`, `map`, `filter`, lambdas,
and helper contracts can express real app shapes.

The pressure is now surface ergonomics, not a rejection of the graph foundation:

- string literals cannot express common escapes, which forced request-sourced JSON in render proofs;
- `match` arms / result branches make multi-guard and accumulation verbose because rebinding is too narrow;
- flat records can be correct but visually noisy for ViewArtifact and relational intents;
- pipeline readability is emerging, but is less urgent than the above.

This card creates the discipline for a parallel language-polish lane: **sugar must lower to the existing
graph / SIR shape and must not introduce runtime authority**.

## Goal

Produce a focused readiness packet that answers:

```text
Which small language-surface fixes should run in parallel with app work,
and which should remain in capability / runtime / projection-dialect lanes?
```

The output should be a prioritized plan with the first implementation card(s), not a broad language redesign.

## Verify First

Read live pressure and proposal surfaces before writing:

- latest IgWeb/Todo proof docs:
  - `lab-docs/lang/lab-igniter-web-viewartifact-authoring-p18-v0.md`
  - `lab-docs/lang/lab-igniter-web-viewartifact-authoring-p19-v0.md`
  - `lab-docs/lang/lab-igniter-web-viewartifact-helper-contracts-p20-v0.md`
  - `lab-docs/lang/lab-igniter-web-viewartifact-list-authoring-p21-v0.md`
  - `lab-docs/lang/lab-igniter-web-viewartifact-conditional-lists-p22-v0.md`
  - `lab-docs/lang/lab-igniter-web-routing-via-chain-readiness-p21-v0.md`
  - `lab-docs/lang/lab-igniter-web-context-composition-readiness-p25-v0.md`
- live language surfaces:
  - `lang/igniter-compiler/src/lexer.rs`
  - `lang/igniter-compiler/src/parser.rs`
  - `lang/igniter-compiler/src/typechecker.rs`
  - `lang/igniter-compiler/tests/fixtures`
  - `lang/igniter-stdlib/stdlib`
- canon/proposal surfaces if present:
  - `../igniter-lang/.agents/work/proposals`
  - `../igniter-lang/.agents/work/meta-proposals`
  - any syntax-pressure / monotony / abstraction-layering notes

Confirm or correct:

- which pain points are live code facts vs stale docs;
- whether string escapes are already tracked in proposals;
- whether match-arm bindings / `where` / `let` have an existing proposal;
- whether record spread / optional fields / partial records have existing proposals;
- whether pipe syntax is already proposed and where it belongs in priority;
- which changes are pure surface sugar and which are capability/runtime semantics.

Live code and current proposal files win over this card.

## Required Analysis

Answer these questions directly:

1. What exact application-pressure events motivate this lane?
2. Which are **paper cuts** (small fixes), **expressiveness gaps**, and **readability sugar**?
3. Which pending proposals already cover the gaps?
4. Which pressure points are missing from proposal tracking?
5. What is the rule for accepting sugar without weakening determinism/replay/receipts?
6. What must stay out of this lane (effects, DB, streaming, package manager, projections)?
7. What is the first implementation slice and why?
8. What is the second slice if the first lands cleanly?
9. What evidence would prove this lane is helping rather than adding syntax noise?
10. What should be deferred until two applications repeat the same pain?

## Expected Priority Shape

Start from this hypothesis, but verify it:

1. `LAB-LANG-STRING-ESCAPES-P1` — low risk, high unblock.
2. `LAB-LANG-MATCH-ARM-BINDINGS-READINESS-P1` — removes the real multi-guard / accumulation ceiling.
3. `LAB-LANG-RECORD-ERGONOMICS-READINESS-P1` — optional fields / spread / partial records.
4. `LANG-PIPE-SYNTAX-READINESS-P*` — later readability sugar, not first-wave critical path.

If live proposals show a better order, explain and adjust.

## Required Deliverable

Create:

```text
lab-docs/lang/lab-lang-surface-ergonomics-readiness-p0-v0.md
```

It must include:

- current pressure table with evidence;
- proposal crosswalk;
- prioritized card list;
- closed-scope list;
- rule: surface sugar lowers to existing graph/SIR and adds no authority;
- recommended first implementation card.

Update this card with a closing report.

## Closed Scope

- No code changes.
- No parser / compiler / VM edits.
- No new syntax.
- No canon claim.
- No DB/effect/storage/streaming capability design.
- No `.igweb` / `.igv` / `.ig.html` design beyond saying when projections are out-of-scope.
- No package manager / workspace resolver work.

## Suggested Next

If P0 lands cleanly, run `LAB-LANG-STRING-ESCAPES-P1` first unless P0 finds a live blocker or a better
already-open card.

---

## Closing Report (2026-06-20)

**Deliverable:** `lab-docs/lang/lab-lang-surface-ergonomics-readiness-p0-v0.md` — readiness/prioritization
packet, **no code**. Answers Q1–Q10 with a pressure table, proposal crosswalk, the acceptance rule, and a
prioritized card list.

**Verify-first crosswalk (igniter-lang proposals):**
- **string escapes — UNTRACKED gap** (all string proposals are stdlib fns: contains/substring/surface/alias;
  nothing about lexer escapes). The single highest-leverage fix has no card → `LAB-LANG-STRING-ESCAPES-P1`.
- **match-arm bindings — partially tracked** (`LANG-MATCH-ARM-PARAM-UNIFICATION-P1/P2` +
  `LANG-TYPED-COMPUTE-BINDING-P1`) → the readiness card *reconciles* these with lab multi-guard pressure.
- **record optional/partial — tracked** (`LANG-OPTIONAL-FIELD-PARTIAL-RECORD-P1/P2`); **record spread —
  pressure-only** (registry, no PROP) → folded into `…-RECORD-ERGONOMICS-READINESS-P1`.
- **pipe / `section` grouping — pressure-only** → deferred.

**The lane's governance rule (load-bearing):** a surface-sugar change is admissible only if it **desugars to
canonical `.ig`, produces a byte-identical SemanticIR (parity-tested like `.igweb`/`.igv`), adds no runtime
authority, adds no new SIR node kind, and keeps source-positioned diagnostics.** If it can't meet that, it's
not sugar — it belongs in the capability/runtime lane.

**Prioritized lane (verified, matches hypothesis):**
1. `LAB-LANG-STRING-ESCAPES-P1` — lowest risk (lexer-only), highest unblock (retires the P17–P22 inline-JSON
   detour class), untracked gap.
2. `LAB-LANG-MATCH-ARM-BINDINGS-READINESS-P1` — removes the one graph-purity ceiling (P20 multi-`via`
   shadowing / accumulation); reconciles two existing proposals; readiness first (design weight).
3. `LAB-LANG-RECORD-ERGONOMICS-READINESS-P1` — optional fields (proposal exists) + spread (pressure-only);
   kills the all-fields-required noise (P19 6-field nodes, P23 `OOF-TY0` `options: []` backfill).
4. pipe / `section` grouping — **deferred** until a 2nd app repeats the pain.

**Evidence-of-help metric:** a previously-detoured app-authoring card re-authored directly + SIR-parity tests
green + no growth in SIR node kinds.

**Recommended first implementation card:** `LAB-LANG-STRING-ESCAPES-P1`.
