# LAB-WEB-ROUTER-BASELINE-v0

**Status:** CLOSED - PROVED 173/173 PASS  
**Route:** lab / app baseline / web_router  
**Date:** 2026-06-15  
**Authority:** evidence baseline only; no implementation

---

## Executive Summary

`web_router` is a pure Rack-shaped HTTP router and response composer. It models
one typed request flowing through `Handle -> ContractResult -> Respond ->
HttpResponse`, using stdlib text routing plus a sealed outcome variant. It does
not claim sockets, an accept loop, Rack compatibility, header maps, path-param
parsing, dynamic route dispatch, middleware, streaming, or chunked bodies.

This baseline classifies `web_router` as a positive dual-toolchain baseline and
pressure source, not a blocker.

---

## Baseline Verification

The full 3-file app compiles cleanly in both toolchains using the proof-runner
subprocess path (`Open3.capture3` plus `Dir.mktmpdir`) and fresh `--out` paths.

| Metric | Value |
|---|---|
| Ruby | `ok` / 0 diagnostics |
| Rust | `ok` / 0 diagnostics |
| source files | 3 |
| types | 2 |
| variants | 1 (`ContractResult` with 6 outcomes) |
| contracts | 8 |
| `call_contract` sites | 10, all Tier-1 PascalCase string literals |
| registry `match` metric | 2 |
| executable `match` expressions | 1 (`Respond`) |
| entrypoint | `RunArticle` |
| source_hash | `sha256:15cc6c7d4ba22f29aa02878f58b8507ce4c7cbc53f3c39d1a228004f0b57c3ce` |

### Hash Correction

Earlier registry metadata recorded
`sha256:4d9b5472cf043be8f1f4373351ca20426012819a756382f598d6f801a73f1039`.
The current live proof-runner baseline is
`sha256:15cc6c7d4ba22f29aa02878f58b8507ce4c7cbc53f3c39d1a228004f0b57c3ce`.
No app source edits were made for this closure; the evidence artifacts now carry
the live compiler result.

---

## Positive Evidence

### KDR to sealed variant

`ContractResult { Found | Created | NotFound | Denied | UpstreamErr |
Unavailable }` replaces the fixture's stringly `kind:String` outcome. `Respond`
uses one exhaustive `match`, so the response composer cannot silently confuse
404, 403, 502, and 503 outcomes.

### Annotated match-arm record literals

`Respond` returns `HttpResponse` record literals directly inside annotated
`match` arms. This is dual-clean and needs no response factory contract.

### stdlib.text routing

`Handle` routes through `starts_with`, `byte_length`, and String `==`. That
keeps the route table in the pure data plane without regex, router DSL, sockets,
or Rack env parsing.

### Entrypoint

`entrypoint RunArticle` is present in source, reflected in the manifest as
`default_entrypoint`, and reflected in SemanticIR as `entrypoint_decl`.

---

## Pressures Preserved

| ID | Pressure | Route |
|---|---|---|
| WR-P01 | KDR to sealed variant relief | regression evidence for `LANG-SUMTYPE-CONSTRUCT-MATCH` |
| WR-P02 | stdlib.text routing works | positive baseline |
| WR-P03 | no header `Map` construction | `LANG-STDLIB-MAP` construction |
| WR-P04 | no path-param parser | `split`/`Collection[String]` typing plus matchable `Option` |
| WR-P05 | no accept loop | ServiceLoop / `PROP-037` plus sockets, still closed |
| WR-P06 | `MakeReq` record-literal factory still needed | record-literal inference tracks |

---

## Boundary Position

`web_router` sits under the Rack / HTTP contract-algebra evidence lane, but this
baseline does not authorize a web runtime. The pure core may be fed by a future
microservice envelope or HTTP substrate, but that substrate remains outside this
app and outside this card's authority.

Closed surfaces:

- No sockets / accept loop / wire parsing / Rack compatibility.
- No header `Map` construction.
- No path-param parser.
- No dynamic route dispatch.
- No middleware / streaming / chunked bodies.
- No app source migration.

---

## Proof

```text
runner: igniter-view-engine/proofs/verify_lab_web_router_baseline_p1.rb
target: at least 90 checks
result: 173/173 PASS
```

The proof compiles the full app twice in Rust and twice in Ruby, verifies
manifest/SemanticIR metadata, source hash stability, counts, Tier-1 dispatch,
variant evidence, entrypoint metadata, WR-P01..WR-P06 routes, Rack/microservice
authority boundaries, closed surfaces, and closure artifacts.
