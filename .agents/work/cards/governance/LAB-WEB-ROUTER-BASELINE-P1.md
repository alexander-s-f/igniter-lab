# LAB-WEB-ROUTER-BASELINE-P1

**Status:** OPEN  
**Route:** lab / app baseline / web_router  
**Date:** 2026-06-15  
**Authority:** evidence baseline only; no implementation

## Goal

Freeze `web_router` as a positive dual-toolchain baseline and pressure source.

`web_router` models a pure Rack-shaped HTTP router and response composer. It uses
stdlib text routing plus a sealed outcome variant; it does not claim sockets,
accept loop, Rack compatibility, path-param parsing, or header maps.

## Required Reads

- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/web_router/PRESSURE_REGISTRY.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/web_router/types.ig`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/web_router/serve.ig`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/web_router/example.ig`
- `LANG-SUMTYPE-CONSTRUCT-MATCH-P1/P2/P3` if P3 has landed.
- Map construction / split / Option cards if available.
- Microservice / ServiceLoop docs for boundary context.

## Proof Questions

1. Does the full app compile cleanly in Ruby and Rust?
2. Are the registry metrics stable: 3 files, 2 types, 1 variant, 8 contracts, 10 `call_contract`, 2 `match`, `entrypoint RunArticle`?
3. Is source hash stable under the project-standard Open3/mktmpdir compile route?
4. Does `ContractResult` + `match` remain a positive KDR-to-variant witness?
5. Does stdlib.text routing (`starts_with`, `byte_length`, String `==`) remain dual-clean?
6. Are WR-P01..WR-P06 preserved and routed accurately?
7. Does the doc clearly keep sockets, accept loop, Rack env, headers, path params, and streaming closed?

## Deliverables

- Proof runner: `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-view-engine/proofs/verify_lab_web_router_baseline_p1.rb`, target at least 90 checks.
- Lab doc: `/Users/alex/dev/projects/igniter-workspace/igniter-lab/lab-docs/governance/lab-web-router-baseline-v0.md`.
- Update `web_router/PRESSURE_REGISTRY.md` with closure summary.
- Update this card with closure summary.
- Portfolio index update after closure.

## Acceptance

- Ruby compile is `ok` / 0 diagnostics.
- Rust compile is `ok` / 0 diagnostics.
- Source hash and app metrics are frozen.
- WR-P01..WR-P06 remain documented and routed.
- No app source edits.

## Closed Surfaces

- No sockets / accept loop / wire parsing / Rack compatibility.
- No header `Map` construction.
- No path-param parser.
- No dynamic route dispatch.
- No middleware / streaming / chunked bodies.

## Agent Recommendation

Give this to **Gemini** or **Sonnet 4.6**. It is a clean baseline proof with good
positive evidence for the Sumtype wave.
