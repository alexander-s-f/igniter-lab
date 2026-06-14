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
| source_hash | `sha256:4d9b5472cf043be8f1f4373351ca20426012819a756382f598d6f801a73f1039` |

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
