# LAB-LANG-APP-SCIENCE-PRESSURE-MAP-P2 - rank language work from app and science pressure

Status: DRAFT
Lane: language surface / app pressure / science pressure
Type: readiness + prioritization packet
Date: 2026-06-24
Skill: idd-agent-protocol

## Context

Igniter is now being pulled by two real engines:

- **Business/app pressure:** IgWeb, TodoApp API, request bodies, host-config, ReadThen, EffectHost, package trust.
- **Science pressure:** Kuramoto, chimera, SIRS, N-body, deterministic math, random distributions, HOF/eval.

We should not add language syntax because it is elegant in isolation. The next language work should be pulled
by a concrete blocked or ugly app/science surface.

## Goal

Create a pressure-ranked map of the next language-surface candidates, grounded in live examples.

## Candidates To Compare

Include at least:

1. signature-bound contract surface;
2. `=` pure vs `<-` external/read/effect boundary;
3. typed row destructuring / JSON row decoding;
4. effect/read syntax over `ReadThen`;
5. collection comprehensions / loops;
6. record/collection ergonomics in HOF bodies;
7. package import/export DX;
8. numeric/science stdlib gaps that require language support rather than library code.

## Verify First

Read live code/proofs from both sides:

- TodoApp API routes/contracts;
- IgWeb implemented surface;
- recent language cards for signature surface / record lambda / HOF recovery;
- stdlib random/math/statistics/linalg cards;
- emergence SIRS readiness and chimera/Kuramoto kernels;
- current `IMPLEMENTED_SURFACE.md` or equivalent status docs.

## Required Output

Write `lab-docs/lang/lab-lang-app-science-pressure-map-p2-v0.md` with:

- app-pressure examples;
- science-pressure examples;
- candidate ranking table;
- "do now / do later / reject for now" split;
- exact next 1-3 cards.

## Acceptance

- [ ] Uses at least 3 app examples and 3 science examples.
- [ ] Separates syntax pressure from stdlib/library pressure.
- [ ] Does not claim a feature is missing without live grep/source evidence.
- [ ] Names one strongest next language card and why.
- [ ] No production code changes.
- [ ] `git diff --check` clean.

## Closed Surfaces

- No parser/compiler changes.
- No canon promotion.
- No broad language roadmap rewrite.
- No speculative syntax without an app/science example.
