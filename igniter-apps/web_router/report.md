# Web Router — Pressure Report

## What This Is

`web_router` is a pure, Rack-shaped **HTTP router + response composer**, pulled from
`igniter-view-engine/fixtures/rack_core`. A request flows through one pure pipeline:

```
HttpRequest {method, path} ──► Handle ──► ContractResult (6 sealed outcomes) ──► Respond ──► HttpResponse {status, body}
        (the wire request)    (route via stdlib.text)   (the handler outcome)    (match)      (the reply)
```

Routing is pure data-plane logic (`starts_with`, `byte_length`, `==`); there is no
accept loop, no sockets, no IO.

## Why This App Exists

The lab P14 fixture (`http_result_rack_composition.ig`) carried the handler outcome
as a **stringly `kind : String`** mapped to an HTTP status via a 6-way nested `if`.
That is exactly the KDR pressure the sum-type track exists to relieve. This app does
the relief: the outcome is a **sealed `ContractResult` variant**, and composition is
a single exhaustive `match`. It is the clearest before/after for "stringly kind →
variant" in the fleet.

## Pressure 1 — KDR → variant (the relief, WR-P01)

```igniter
variant ContractResult {
  Found { body } | Created { body } | NotFound | Denied | UpstreamErr | Unavailable
}

compute resp : HttpResponse = match result {
  Found       { body } => { status: 200, body: body }
  Created     { body } => { status: 201, body: body }
  NotFound    {}       => { status: 404, body: "Not Found" }
  Denied      {}       => { status: 403, body: "Forbidden" }
  UpstreamErr {}       => { status: 502, body: "Bad Gateway" }
  Unavailable {}       => { status: 503, body: "Service Unavailable" }
}
```

`match` is exhaustive — a new outcome forces a new arm. A `kind:String` can silently
route a 404 like a 502; the variant cannot. (Bonus finding: **annotated match arms
returning record literals are dual-clean** — no factory needed inside `Respond`.)

## Pressure 2 — routing works on the data plane (WR-P02)

`Handle` routes with `starts_with(path, "/articles/")`, `byte_length(path) > 1`, and
String `==` — all dual-clean (stdlib.text). A Rack route table is a tidy nested `if`
over the request. No regex, no router DSL needed for this shape.

## Pressure 3 — the edges fray: headers + path params (WR-P03 / WR-P04)

Two honest gaps the fixture hit too:
- **Headers** are a `Map[String,String]`, but a Map literal can't be constructed in
  source (`map_empty`/`map_from_pairs` don't infer params), so the response is
  `{status, body}` and headers would be injected — a small `LANG-STDLIB-MAP` win.
- **Path params** (`/articles/:id`): `split(path, "/")` does not infer
  `Collection[String]`, and `last(...)` returns a non-matchable `Option`, so `:id`
  routes match by prefix only. Real param extraction wants both fixed.

## What We Need From IO

| Subsystem | What it needs from IO | Track |
|---|---|---|
| **Accept loop** | accept connections / pull requests, parse the wire | ServiceLoop/`PROP-037` + sockets (closed) |
| **Request envelope** | a typed `ServiceRequest` from the ingress | `LAB-IGNITER-LANG-MICROSERVICE` envelope |
| **Response sink** | write the status/headers/body back | effect surface output capability |

The pure core (`Handle`, `Respond`, `Serve`) stays CORE — exactly one request→response
function. IO is the membrane that feeds it parsed requests and writes its responses,
the same "pure core under an effect shell" as the other companions.

## Status

Dual-toolchain CLEAN (Ruby 0 / Rust ok 0). 3 files, 2 types, 1 variant (6 arms), 8
contracts, `entrypoint RunArticle`. See `PRESSURE_REGISTRY.md`.
