# LAB-IGNITER-WEB-ROUTING-PACKAGING-P6 — IgWeb app packaging seam

Status: CLOSED (readiness packet)  
Lane: standard / readiness-design  
Opened: 2026-06-18  
Closed: 2026-06-18  
Delegate label: OPUS-IGWEB-PACKAGING-F  
Skill: idd-agent-protocol  

## Why This Card

P5 proved the hard thing:

```text
.igweb -> lower_igweb -> generated .ig -> IgniterMachine::load_program -> dispatch("Serve")
       -> ServerApp adapter -> real loopback HTTP
```

But P5 is intentionally a test seam. It hand-assembles:

- `.igweb` source,
- support `.ig` modules (`Request`, `Decision`, handlers),
- temp generated `routes.ig`,
- `IgniterMachine::load_program([...], "Serve")`,
- `ServerDecision` mapping.

Before moving any of that into public API or `igniter-server/src`, define the packaging contract.

This card answers: **what does an IgWeb app package look like, who owns each file, how is it built/loaded/cached, and what API should the server see?**

## Authority

This is a lab readiness/design card. It may write one packet and update this card. It should not implement a public adapter.

Allowed:
- Read live code and docs.
- Propose app package shape, manifest fields, build/load stages, cache semantics, error taxonomy, and next implementation card.
- Add thin pointers only if genuinely useful.

Not allowed:
- No code changes to `igniter-server/src`.
- No new compiler/server API.
- No dialect registry implementation.
- No canon claim for `.igweb`.
- No live network beyond local proof context.
- No SparkCRM/domain app hardcoding.
- No route table in server.

## Verify First

Read current truth before writing the packet:

- `lab-docs/lang/lab-igniter-projection-dialects-p0-v0.md`
- `lab-docs/lang/lab-igniter-web-routing-lowering-p4-v0.md`
- `lab-docs/lang/lab-igniter-web-routing-adapter-p5-v0.md`
- `.agents/work/cards/lang/LAB-IGNITER-WEB-ROUTING-ADAPTER-P5.md`
- `igniter-compiler/src/igweb.rs`
- `igniter-server/tests/igweb_adapter_tests.rs`
- `igniter-server/src/protocol.rs`
- `igniter-server/src/host.rs`
- `igniter-server/src/reload.rs`
- `igniter-server/src/serving_loop.rs`
- `igniter-server/examples/server_app_runner.rs`

Live code beats old docs. If any "next route" is already implemented, state that and route around it.

## Core Questions

Answer these directly.

1. **Package unit:** Is an IgWeb app package a directory, manifest, Rust builder input, generated artifact set, or all of these? What is the smallest v0?
2. **File roles:** Which files are authored (`routes.igweb`, handlers `.ig`, types `.ig`) and which are generated (`routes.generated.ig`, maybe source map)?
3. **Manifest shape:** Do we need an `igweb.toml` now, or can v0 use an explicit Rust builder/config struct? If manifest, what minimal fields?
4. **Build stages:** Exact pipeline from package root to loaded app:
   ```text
   collect sources -> lower .igweb -> write/hold generated .ig -> compile/load -> ServerApp
   ```
5. **Cache key:** What should invalidate a loaded app? Source hashes? generated `.ig` hash? compiler version? stdlib version? machine runtime id?
6. **Diagnostics:** How do `.igweb` lowering errors, generated `.ig` compiler errors, and runtime dispatch errors map back to app developer output?
7. **Source map:** What is required now vs later? Is line-level `.igweb -> generated .ig` mapping mandatory before public API?
8. **Server boundary:** What exact type should `igniter-server` consume? `Arc<dyn ServerApp>` only? A builder returning it? A `ReloadableApp` snapshot?
9. **Reload:** How does this package interact with P4/P5/P8/P10 server reload/serving loop? What is atomic: source set, generated artifact, loaded machine, middleware stack?
10. **Effects:** How does `InvokeEffect target` remain logical and host-bound? Where does `target -> EffectBridgeConfig` live?
11. **Default deps:** How do we preserve `igniter-server` default serde-only build while enabling IgWeb packages?
12. **DX:** What should the developer type/run locally? Example command or Rust builder call. Keep it honest and minimal.

## Design Constraints

Keep the shape boring and composable.

Preferred direction:

```text
app package / builder
  owns .igweb + handlers/types
  produces Arc<dyn ServerApp + Send + Sync>
  can be wrapped by middleware / ReloadableApp
  emits only ServerDecision
server host
  owns socket, concurrency, serving loop, reload handoff
effect host
  owns target binding, passports, receipts, secrets
```

Server core must not learn:

- route patterns,
- path params,
- domain handlers,
- SparkCRM vocabulary,
- effect capability identity.

## Deliverable

Write:

- `lab-docs/lang/lab-igniter-web-routing-packaging-p6-v0.md`
- closing report in this card

Optional thin pointers:

- Add one "next route" pointer from the P5 proof doc if it helps discoverability.

Do not update broad indexes unless the packet creates an actually durable route.

## Acceptance

1. Packet answers all 12 core questions.
2. Packet clearly distinguishes authored source, generated source, compiled/loaded runtime, and server runtime.
3. Packet proposes one minimal v0 package shape and rejects at least two tempting-but-wrong alternatives.
4. Packet preserves `igniter-server` default small dependency boundary.
5. Packet states whether v0 needs a manifest file or a Rust builder first, and why.
6. Packet defines cache invalidation inputs.
7. Packet defines diagnostic/source-map expectations and what is deferred.
8. Packet states exact relationship to `ReloadableApp` and middleware.
9. Packet keeps effect authority in host config, not `.igweb`.
10. Packet names the next implementation card with precise scope.

## Suggested Next Card

If the readiness packet confirms the expected shape, the likely next implementation is:

```text
LAB-IGNITER-WEB-ROUTING-PACKAGE-BUILDER-P7
```

Narrow scope: a lab builder/test helper that takes explicit paths (`routes.igweb`, support `.ig` modules, entry `"Serve"`), lowers/loads once, returns `Arc<dyn ServerApp + Send + Sync>`, and proves reload compatibility. No manifest yet unless P6 proves it is necessary.

---

## Closing report — 2026-06-18

**Chosen v0 package shape:** a **directory of authored sources + a Rust builder** — NOT a manifest.
`build_igweb_app(paths, entry) -> Arc<dyn ServerApp + Send + Sync>` IS the v0 contract (P5 already
proved the inputs are `(paths, entry)`). Four distinct tiers: AUTHORED (`routes.igweb` + handlers/types
`.ig`) → GENERATED (`routes.generated.ig` via `lower_igweb`, inspectable) → COMPILED/LOADED
(`IgniterMachine::load_program(..., "Serve")`) → SERVER RUNTIME (`Arc<dyn ServerApp>`).

**Why it is not server routing:** the server consumes ONLY `Arc<dyn ServerApp + Send + Sync>`; it never
sees `.igweb`, the machine, the lowering, route patterns, params, or `EffectBridgeConfig`. Routing lives
in the generated `Serve` capsule; effect identity (`target → EffectBridgeConfig`) lives in host config.

**Exact dependency boundary:** the builder depends on `igniter_compiler` (lower) + `igniter_machine`
(load/dispatch); it stays OUT of `igniter-server/src`. v0 = a test/example helper (P5's shape:
`igniter_compiler` dev-dep, machine feature) or a future small `igniter-web` lab crate. Default
`igniter-server` lib stays **serde-only** (verified in P5).

**Cache key:** hash(authored sources `.igweb`+handlers+types) + `lower_igweb` output + compiler version
+ stdlib version + entry name. The compiler's merged `source_hash` is the natural compiled-artifact key;
machine/process id is NOT part of the key.

**Diagnostics/source-map stance:** three layers each surfaced at origin — `IgwebError{line}` (`.igweb`),
generated-`.ig` compiler OOF (line in the inspectable generated file), runtime → 500. Full
`.igweb→generated.ig` line source-map = **deferred (SHOULD)**, not required before the builder; generated
`.ig` is committed/inspectable so errors are traceable today.

**Rejected:** (1) adapter/builder in `igniter-server/src` (pulls compiler+machine into the server
surface); (2) `igweb.toml` manifest as v0 unit (config surface, no consumer — builder first); (3)
runtime dynamic route registration (contradicts P2 static-lowering / no dynamic dispatch).

**Reload/middleware:** the whole built `Arc<dyn ServerApp>` (owning the loaded machine) is the atomic
swap unit; middleware wraps it, then `ReloadableApp` wraps the outer stack (P0/P8 rule); serving loop
(P5) unchanged.

**Next implementation card:** `LAB-IGNITER-WEB-ROUTING-PACKAGE-BUILDER-P7` — a lab builder
`build_igweb_app(paths, entry) -> Result<Arc<dyn ServerApp + Send + Sync>, IgWebBuildError>` (extract
P5's hand-assembly), prove reload compatibility (swap two built apps), keep default server serde-only.
No manifest/source-map yet. **Deferred:** manifest, source map, CLI/dialect registry, real
`InvokeEffect` execution wiring (proven P3), promotion to a public `igniter-web` crate.

**Acceptance:** all 12 core questions answered; four tiers distinguished; one v0 shape chosen + 3
alternatives rejected; default dep boundary preserved; builder-before-manifest decided with rationale;
cache key + diagnostic/source-map stance + `ReloadableApp`/middleware relationship + host-owned effect
authority all stated; next card named with precise scope. Thin pointer added from the P5 proof doc.

## Closing Report Template

Report:

- chosen v0 package shape;
- why it is not server routing;
- exact dependency boundary;
- exact cache key proposal;
- exact diagnostic/source-map stance;
- next implementation card and what remains deferred.

