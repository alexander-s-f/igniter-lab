# LAB-IGNITER-WEB-TEMPLATE-DIALECT-READINESS-P25

Status: CLOSED (readiness packet delivered 2026-06-25)
Route: standard / dialect readiness
Skill: idd-agent-protocol

## Closing report (2026-06-25)

Packet: `lab-docs/lang/lab-igniter-web-template-dialect-readiness-p25-v0.md`.

**Stance on `.ig.html`: HOLD / defer.** The projection-dialect slot is **already filled** by `.igv` — a live
declarative screen DSL lowering deterministically to ViewArtifact JSON, no runtime (`igv.rs:15-30`; "SUGAR
over the artifact… does not touch `.ig`" `:1-12`). Canonical schema states the ordering: artifact is data,
"the reason it comes before a text DSL" (`view_artifact.rs:6-7`). So `.ig.html` would add **HTML-shaped
ergonomics, not capability**; its ceiling = ViewArtifact vocab (P26); building it ahead of that vocab is
premature.

**Lowering target (if ever):** a pure `.ig` contract returning `ViewArtifact` (the `.igweb`→`.ig` / `.igv`→JSON
discipline) — byte-identical, deterministic. NOT host template AST / HTML string / runtime / untyped locals.
Inputs by contract signature; loops/conditionals → `.ig` HOF/comprehension; escaping stays projector-owned;
no raw HTML by default.

**The fork located precisely (Meta-Architect stop condition honored):** `.ig.html` is a clean dialect iff its
expressiveness ⊆ descriptor. interpolation/`for`/`if`/flat-form lower fine; **arbitrary nesting/sections,
slots/partials, stateful/hydrated components do NOT** → that's a ViewArtifact vocab evolution (P26) or a
hidden runtime (reject), never a dialect. Rule: if `.ig.html` is wanted to *escape* the descriptor's limits,
it's a runtime-in-disguise — stop and surface the fork.

**External inspiration:** borrow compile-time lowering + default-escaping + typed inputs (HEEx/Temple);
reject string-targeting (Slim/Haml) + client runtime/hydration (Svelte/Astro). Igniter-native = HTML-as-data
lowering to the descriptor.

**Next/hold:** HOLD; route to **P26** (evolve the vocab first). Future proof (held):
`LAB-IGNITER-WEB-IGHTML-DIALECT-LOWERING-PROOF` — byte-identical fragment lowering, returns the fork if it
can't lower.

**Boundary honored.** No code/parser/extension/template-lib/canon. Docs only. `git diff --check` clean; grep
→ `/tmp/igniter-template-dialect-grep.txt` (4608 hits).

## Goal

Investigate whether Igniter should eventually have a template dialect (`.ig.html` or equivalent), and if
so what it must lower to.

This is research only. It must not implement a parser/template engine and must not assume templates are
the next step.

## Current Authority

- Projection Dialects P0.
- Existing `.igweb` lowering discipline.
- Current ViewArtifact / RenderView / render-html surface.
- Data Projection P1-P5.
- Any notes/cards mentioning Temple, `.ig.html`, `.igv`, or templating.

## Research Prompt

Use Temple/Haml/Slim/Rails/HEEx/Svelte/Astro ideas as inspiration only. The result must be Igniter-native,
not a borrowed runtime model.

The core question:

> If we add a template dialect, is it a front-end syntax for ViewArtifact / typed Html tree / pure `.ig`
> contracts, or does it smuggle a new runtime/template authority?

## Questions To Answer

1. What would `.ig.html` lower to?
   - pure `.ig` contracts returning `ViewArtifact`;
   - pure `.ig` contracts returning `HtmlNode` tree;
   - host-side template AST;
   - direct HTML string;
   - another target.
2. How are data inputs declared?
   - function/contract signature;
   - implicit locals;
   - slot/context object;
   - ViewModel record.
3. How are loops/conditionals expressed?
   - reuse `.ig` HOF/comprehension;
   - template syntax;
   - lower to explicit pure `.ig`.
4. How is escaping/XSS handled?
   - default escaped text;
   - raw HTML opt-in;
   - typed `Html` vs `String`;
   - attributes/URLs/actions.
5. How does it compose with Data Projection?
6. What would make `.ig.html` worth adding instead of helper contracts / ViewArtifact records?
7. What is the smallest proof if we ever do it?

## Design Bias

- A template dialect is acceptable only if it is a **projection dialect**: deterministic lowering to existing
  Igniter values or pure contracts.
- No hidden runtime engine.
- No raw string concatenation as primary model.
- No untyped implicit locals.
- No raw HTML by default.
- Do not make this the next implementation unless evidence is overwhelming.

## Boundary

Allowed:

- Write a readiness packet.
- Include small syntax sketches.
- Compare external systems.

Closed:

- No code changes.
- No parser.
- No new file extension implementation.
- No dependency on Temple or any template library.
- No canon claim.

## Required Packet

Create:

`lab-docs/lang/lab-igniter-web-template-dialect-readiness-p25-v0.md`

Must include:

- external inspiration summary (short, not a literature review);
- target-lowering decision;
- safety/XSS model;
- why/when `.ig.html` is justified;
- why it may be deferred;
- smallest future proof card.

## Verification

Run:

```bash
rg -n "Projection Dialect|\\.igv|\\.ig.html|template|Temple|ViewArtifact|HtmlNode|escape|raw" \
  lab-docs .agents server lang frame-ui \
  > /tmp/igniter-template-dialect-grep.txt

git diff --check
```

## Acceptance

- [x] Packet exists.
- [x] It does not recommend hidden template runtime authority.
- [x] It states a deterministic lowering target.
- [x] It names escaping/raw-HTML policy.
- [x] It explains why this should or should not be near-term.
- [x] No code changed.
- [x] `git diff --check` clean.

## Reporting

Close with:

- recommended stance on `.ig.html`;
- lowering target;
- safety model;
- next/hold decision.
