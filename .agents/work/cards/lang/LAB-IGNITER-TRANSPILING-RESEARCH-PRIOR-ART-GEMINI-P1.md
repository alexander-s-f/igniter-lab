# Card: LAB-IGNITER-TRANSPILING-RESEARCH-PRIOR-ART-GEMINI-P1 — Prior art and anti-patterns for projection dialects

**Lane:** background / research  
**Status:** CLOSED (completed research)  
**Date opened:** 2026-06-18  
**Delegation-Code:** `GEMINI-20260618-TRANSPILING-D`  
**Research label:** `BACKGROUND-RESEARCH`  
**Authority:** Lab research only. No code. No canon.

## Why this card exists

Projection dialects are a known danger zone: useful sugar can become hidden semantics, framework
lock-in, or a second language. This background Gemini agent studies prior art and anti-patterns so
Igniter can borrow the useful parts without inheriting accidental complexity.

## Read first

- `.agents/work/cards/lang/LAB-IGNITER-PROJECTION-DIALECTS-P0.md`
- `lab-docs/lang/lab-igniter-projection-dialects-p0-v0.md`
- `lab-docs/lang/lab-igniter-web-routing-dx-shape-p2-v0.md` if present
- `lab-docs/lang/lab-frame-igv-binding-syntax-p1-v0.md`
- `lab-docs/lang/lab-machine-igniter-server-protocol-readiness-p1-v0.md` if present

## Goal

Produce one research packet that answers: **which transpiler/dialect patterns should Igniter borrow,
and which should it avoid?**

## Suggested prior-art lenses

Use available knowledge and, if your environment has web access, cite sources. If you cannot verify a
claim live, label it as prior-knowledge, not current fact.

- TypeScript/Babel/SWC source-to-source lowering.
- Svelte/Astro/Vue single-file component compilation.
- GraphQL codegen and schema-first workflows.
- Rails/Rack routing DSL vs server protocol boundary.
- SQL query builders/ORM migrations as generated artifacts.
- Macro hygiene lessons from Rust/Lisp/Scala-style systems.
- JSX/MDX/templating anti-patterns where syntax smuggles runtime authority.

## Questions to research

1. What patterns map well to Igniter's Projection Dialects?
2. What patterns are dangerous because they hide runtime authority?
3. How do mature ecosystems handle generated artifact inspection?
4. How do they handle source maps and IDE errors?
5. How do they prevent dialect proliferation?
6. What governance terms or promotion ladders are worth borrowing?
7. What should Igniter explicitly reject even if other ecosystems accept it?
8. What surprising idea should the main wave consider that is not already in P0?

## Output contract

Write exactly one report:

`lab-docs/lang/lab-igniter-transpiling-research-prior-art-gemini-p1-v0.md`

Then update only this card with a closing report.

## Closed surfaces

- No implementation.
- No dependency additions.
- No canon claims.
- No public docs rewrite.
- Do not edit P0/P4/P1; this is background research only.

## Acceptance

- [x] Report separates verified/current-source claims from prior-art interpretation.
- [x] Report lists borrowable patterns and rejected anti-patterns.
- [x] Report identifies at least one non-obvious insight or future card idea.
- [x] Report does not turn external frameworks into Igniter authority.
- [x] No code changed.

---

## Closing report — 2026-06-18

**Outcome:** Analyzed transpilation, templating, and code-generation prior art across TypeScript/Babel, Svelte/Astro, GraphQL, Rails, and Rust. Documented borrowable patterns (pure syntactic lowering, schema-as-contract, check-in ready artifacts) and dangerous anti-patterns to reject (JSX-style arbitrary code execution, dynamic metaprogramming/reflection, hidden runtime authority).
Suggested CI-enforced dialect verification (`igniter dialect verify`) as a non-obvious tooling insight to prevent manual drift.

**Deliverable:** `lab-docs/lang/lab-igniter-transpiling-research-prior-art-gemini-p1-v0.md` (fully written, 5 main sections answering Q1–Q8, 0 LOC changed).
