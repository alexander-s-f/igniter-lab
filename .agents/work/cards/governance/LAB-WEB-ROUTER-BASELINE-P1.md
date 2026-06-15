# LAB-WEB-ROUTER-BASELINE-P1

**Status:** CLOSED - PROVED (173/173 PASS)  
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

---

## Closure Summary (2026-06-15)

**Status:** CLOSED - PROVED 173/173.  
**Result:** `verify_lab_web_router_baseline_p1.rb` passes the full baseline
guard.

### Compiler baseline

| Toolchain | Status | Diagnostics |
|---|---|---|
| Ruby | `ok` | 0 |
| Rust | `ok` | 0 |

The live proof-runner source hash is stable in both toolchains:

`sha256:15cc6c7d4ba22f29aa02878f58b8507ce4c7cbc53f3c39d1a228004f0b57c3ce`

The older registry hash
`sha256:4d9b5472cf043be8f1f4373351ca20426012819a756382f598d6f801a73f1039`
was stale metadata. No app source edits were made.

### Counts frozen

3 files, 2 types, 1 variant (`ContractResult`), 8 contracts, 10 Tier-1
literal `call_contract` sites, registry metric 2 `match` sites, and one
executable `Respond` match expression.

### Positive evidence

- `ContractResult` + `Respond` proves the KDR-to-sealed-variant route.
- `Respond` proves annotated `match` arms returning `HttpResponse` record
  literals are dual-clean.
- `Handle` proves stdlib.text routing through `starts_with`, `byte_length`, and
  String equality.
- `entrypoint RunArticle` is present and reflected in manifest/SemanticIR.

### Pressure routes preserved

WR-P01..WR-P06 are preserved and routed. Header `Map` construction, path-param
parsing, sockets, Rack env compatibility, accept loop, dynamic route dispatch,
middleware, streaming, and chunked bodies remain closed.

### Deliverables

| Artefact | Path | Status |
|---|---|---|
| Proof runner | `igniter-view-engine/proofs/verify_lab_web_router_baseline_p1.rb` | **173/173 PASS** |
| Lab doc | `lab-docs/governance/lab-web-router-baseline-v0.md` | Written |
| Pressure registry | `igniter-apps/web_router/PRESSURE_REGISTRY.md` | Updated |
| This card | `.agents/work/cards/governance/LAB-WEB-ROUTER-BASELINE-P1.md` | CLOSED |
| Portfolio index | `.agents/portfolio-index.md` | Updated |
