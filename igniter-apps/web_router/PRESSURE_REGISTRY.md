# Web Router Pressure Registry

Created: 2026-06-14 (off-track app — pulled from `igniter-view-engine/fixtures/rack_core`)

`web_router` is a pure, Rack-shaped **HTTP router + response composer**. A request
`{method, path}` is routed by pure data-plane logic (stdlib.text `starts_with` /
`byte_length` / `==`) to a handler **outcome**, which is composed into an
`HttpResponse {status, body}`. No accept loop, no sockets, no IO.

## Baseline

Dual-toolchain CLEAN (Open3 / MultifileResolver subprocess route).

```bash
cd igniter-compiler
cargo run -- compile \
  ../igniter-apps/web_router/types.ig ../igniter-apps/web_router/serve.ig \
  ../igniter-apps/web_router/example.ig --out /tmp/web_router.igapp
```

| Metric | Value |
|---|---|
| Ruby | ok / 0 diagnostics |
| Rust | ok / 0 diagnostics |
| source files | 3 |
| types | 2 |
| variants | 1 (`ContractResult` — 6 Rack outcomes) |
| contracts | 8 |
| call_contract / match | 10 / 2 |
| entrypoint | `RunArticle` |
| source_hash | `sha256:15cc6c7d4ba22f29aa02878f58b8507ce4c7cbc53f3c39d1a228004f0b57c3ce` |

## Provenance (fixture → app)

| Fixture | web_router model |
|---|---|
| `rack_core/route_dispatch.ig` (method+path → status via starts_with/byte_length) | `serve.ig` Handle |
| `rack_core/http_result_rack_composition.ig` (ContractResult kind → FullRackResponse, 6 branches) | `Respond` — but a **sealed variant + match**, not `kind:String` |
| `rack_core/path_param_extract.ig` (split/last → Option) | NOT modeled — `split` doesn't infer Collection[String] (WR-P04) |

## Pressures

| ID | Name | Evidence | Status | Route |
|---|---|---|---|---|
| WR-P01 | **KDR → sealed variant (relief)** | the P14 fixture carried the handler outcome as `kind:String` + a 6-way nested-if mapper; here `ContractResult` is a sealed variant and `Respond` is one exhaustive `match`. Forbids confusing 404 with 502. | POSITIVE — capability | regression evidence for `LANG-SUMTYPE-CONSTRUCT-MATCH` |
| WR-P02 | **routing via stdlib.text (works)** | `starts_with` / `byte_length` (stdlib.text) + String `==` are dual-clean; route + method dispatch is pure data plane. | POSITIVE | — |
| WR-P03 | **no header map** | `HttpResponse` is `{status, body}` — a `Map[String,String]` headers field can't be constructed in source (Map construction gap), so headers would be injected. | ACTIVE — stdlib gap | `LANG-STDLIB-MAP` construction |
| WR-P04 | **no path-param parser** | `:id` routes match by PREFIX only; `split(path,"/")` does not infer `Collection[String]` (`OOF-TY1`) and `last(...)` returns a non-matchable `Option`. | ACTIVE | `split`/`Collection[String]` typing + `LANG-SUMTYPE-CONSTRUCT-MATCH` (Option) |
| WR-P05 | **no accept loop** | a real server accepts connections and parses the wire request; the pure core is one request→response function with no loop or sockets. | DOCUMENTED — behind | ServiceLoop/`PROP-037` + `LAB-IGNITER-LANG-MICROSERVICE` envelope + sockets (closed) |
| WR-P06 | **record-literal factory** | `MakeReq` exists only to pin `HttpRequest` (inline literals infer to Unknown in Rust). Annotated `match` arms returning record literals DO work (`Respond`). | ACTIVE | `LANG-RUBY-RECORD-LITERAL-INFERENCE` |

## Capability Discovery (positive)

Two clean wins: (1) **annotated `match` arms returning record literals** are
dual-clean — `compute resp : HttpResponse = match result { Found { body } => { status: 200, body: body } … }`
needs no factory. (2) stdlib.text routing (`starts_with`/`byte_length`/`==`) +
variant response composition makes a Rack handler a tidy pure pipeline. This app is
the cleanest demonstration that the fixture's `kind:String` KDR should be a variant.

## Safety Interpretation

Proves the language can model HTTP routing + response composition as a pure,
exhaustive, fail-closed core. It does NOT claim: any sockets/IO, an accept loop,
a wire parser, header maps, path-param parsing, or Rack compatibility.

## Non-Goals

- No sockets / accept loop / wire parsing / Rack compat.
- No header `Map` (response is status+body).
- No `:id` path-param parsing (prefix match only).
- No dynamic route dispatch (static, name-based).
- No middleware / streaming / chunked bodies.

## Recommended Route

1. Keep as **regression evidence** for `LANG-SUMTYPE-CONSTRUCT-MATCH` (WR-P01).
2. `LANG-STDLIB-MAP` construction (WR-P03) + `split`/`Collection[String]` typing (WR-P04).
3. ServiceLoop/`PROP-037` + microservice envelope for the serve loop (WR-P05).

## Baseline Closure (2026-06-15)

`LAB-WEB-ROUTER-BASELINE-P1` closed this registry as a positive
dual-toolchain baseline and pressure source. Proof runner:
`igniter-view-engine/proofs/verify_lab_web_router_baseline_p1.rb`
(`173/173 PASS`).

Closure facts:

- Ruby: `ok` / 0 diagnostics.
- Rust: `ok` / 0 diagnostics.
- Absolute proof-runner source hash:
  `sha256:15cc6c7d4ba22f29aa02878f58b8507ce4c7cbc53f3c39d1a228004f0b57c3ce`.
- Counts preserved: 3 files, 2 types, 1 variant, 8 contracts, 10
  `call_contract` sites, registry metric 2 `match` sites, executable
  `Respond` match expression.
- WR-P01..WR-P06 preserved and routed.
- `entrypoint RunArticle` verified in manifest and SemanticIR.
- The prior registry hash
  `sha256:4d9b5472cf043be8f1f4373351ca20426012819a756382f598d6f801a73f1039`
  was stale metadata; no app source edits were made for this closure.
- No sockets, accept loop, Rack env, header `Map`, path-param parser,
  middleware, streaming, or runtime authority opened.

## Wave P12 Recheck Summary (2026-06-15)

Rust: ok / 0 diagnostics. Ruby: ok / 0 diagnostics. DUAL-TOOLCHAIN CLEAN.

Integrated into the 20-app fleet as a new companion app. Its pressure routes remain evidence-only: sealed variant/`match` response composition, `LANG-STDLIB-MAP` header construction, split/`Collection[String]` plus Option typing, and ServiceLoop/microservice envelope surfaces. No source edits. No new pressures. No regressions.

## Wave P13 Recheck Summary (2026-06-15)

Ruby: ok/0. Rust: ok/0. DUAL-CLEAN. Source files: 3. Source hash: `sha256:15cc6c7d4ba22f29aa02878f58b8507ce4c7cbc53f3c39d1a228004f0b57c3ce`. Entrypoint: `RunArticle`. unchanged clean companion app.
No source changes in this wave. No new pressures. No regressions.
