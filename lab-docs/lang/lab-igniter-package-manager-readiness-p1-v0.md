# lab-igniter-package-manager-readiness-p1-v0 — package-manager research + Opus validation

**Card:** `LAB-IGNITER-PACKAGE-MANAGER-READINESS-P1` · **Delegation:** `GEMINI-IGNITER-PACKAGES-OVERNIGHT-A`
(+ Opus validation pass) · **Status:** READINESS / RESEARCH (v0) — comparative packet + validation of the
Gemini round-1 direction against **live Igniter surfaces**. **No code, no package format, no registry, no
resolver, no CLI, no canon claim.**
**Authority:** Lab research. Live `project.rs`/`igweb.rs`/`protocol.rs`/P0 win over cards; other ecosystems
are *lessons*, not authority.

## 0. The decisive validation finding — Igniter already has the substrate

A package manager is usually a greenfield build. For Igniter it is a **small, deterministic extension of
what already exists** (verified live):

| Live capability | Evidence | Package-manager consequence |
|---|---|---|
| project config with `source_roots` | `project.rs:44-59` (`igniter.toml` → `source_roots = ["a","b"]`) | the manifest seed; add `[dependencies]` path roots beside it |
| **logical-module-path imports** (`import Foo.Bar`) | `project.rs:18,152-171` (module index: path → file; `stdlib.*` reserved) | packages contribute modules to one logical namespace; no filesystem-path coupling |
| **deterministic multifile source-hash** | `project.rs:241-242` ("sorted by module path … source hash stable") + `compile_units` | content-addressing is **free** — the compiler already produces a stable hash |
| source vs compiled split | `.ig` source → `.igapp` compiled artifact (machine `load_program`) | the package can carry source; `.igapp` is build-output, not identity |
| **projection dialects lower to inspectable `.ig`** | P0 `lab-igniter-projection-dialects-p0-v0.md`; `igweb.rs` lower_igweb | `.igweb`/`.igv` ship as **source**; generated `.ig` is derived, never authority |
| app manifest already exists | `igniter-web` `igweb.toml` (`[app] entry`, `[server]`, `[middleware]`) — names **no** routes/secrets/capability ids | the precedent: manifests declare *intent*, never credentials |
| capability = logical target, host binds authority | `protocol.rs` `ServerDecision` carries a `target`, **never** `capability_id`/secret; effect host binds the recipe/passport | a package declares `Postgres.Read`; the **host** binds the secret — no smuggling |
| content digests already use **blake3** | effect-receipt work (`fixture-receipt:<blake3[:10]>`) | reuse blake3 for the lock digest — don't introduce SHA-256 |

**Conclusion:** the round-1 "local workspace resolver + content-addressed lock + no install scripts +
host-owned capabilities" is not just philosophically right — it is the **minimal delta** over live
`project.rs`. The v0 slice is genuinely small.

## 1. Validation of round-1's strong signals (accept / revise / reject)

| # | Round-1 signal | Verdict | Grounding |
|---|---|---|---|
| 1 | two-layer identity: human name + content digest | **ACCEPT** | digest is free (`compile_units` source-hash); name is DX. Matches the project's receipt/content-addressed philosophy. |
| 2 | distinguish source / projection-source / generated / compiled | **ACCEPT** | P0 already mandates it; `.igweb`/`.igv`→generated `.ig`→`.igapp` is the live pipeline. |
| 3 | lockfile pins deps + compiler + stdlib + lowerer + artifact hashes | **ACCEPT, but PHASE** | v0 lock = **dependency content digests only**; compiler/stdlib/lowerer-version pinning is a *later* slice — don't build the full lock before the resolver exists. |
| 4 | **no install scripts** in v0 | **ACCEPT (strongly)** | THE anti-npm decision. Any build is a *known compiler/tool step*, never package-provided code — mirrors "host runs only proven paths, no arbitrary execution." |
| 5 | capabilities are **declarations, not credentials** | **ACCEPT** | exactly the live `target`-vs-`capability_id` boundary (`protocol.rs`). A package declares `Postgres.Read`; the host binds DSN/passport. |
| 6 | registry later | **ACCEPT** | `source_roots` already supports local path roots; local-first needs no registry. |
| 7 | version solver (MVS/SAT) later | **ACCEPT (revise round-1's early MVS lean)** | local **path** deps need **no solver at all** — there are no version ranges to resolve. Defer MVS to a remote/versioned-package card. |

**Net:** all seven accepted; two phased/revised (lock granularity #3, solver #7). The direction is sound and
live-grounded.

## 2. Comparative table (lessons, not authority)

| Ecosystem | Package identity | Locking | Build hooks | Namespace / imports | Trust / provenance | Strength | Failure mode | Igniter lesson |
|---|---|---|---|---|---|---|---|---|
| Cargo/crates.io | name+semver (+ registry) | `Cargo.lock` (version+hash) | `build.rs` (arbitrary) | crate = root namespace; `use` paths | crates.io + checksums | features, workspaces, reproducible | `build.rs` = arbitrary code; feature-combo explosion | keep lock+workspace; **drop arbitrary build.rs** |
| npm/pnpm/yarn | name+semver range | lockfile (resolved tree) | **postinstall (arbitrary)** | flat/nested `node_modules` | registry (weak) | huge reach, scripts | **postinstall supply-chain**, range drift, dep sprawl | **no install scripts, ever**; pin digests not ranges |
| RubyGems/Bundler | name+version | `Gemfile.lock` | gem extensions/native build | global require namespace | rubygems.org | groups, Rails engines | native-build fragility; global namespace clashes | groups useful; **avoid global namespace soup** |
| Go modules | **module path = identity** | `go.sum` (content hashes) | none (no hooks) | module path → import path | **sumdb** (transparency) | MVS, no hooks, sumdb | MVS surprises; replace-directive misuse | **module-path identity + content sums + no hooks = closest fit** |
| Python (pip/pyproject) | name+version | weak (varies) | `setup.py` (arbitrary) | flat `site-packages` | PyPI | extras, wheels | virtualenv hell, arbitrary setup, env coupling | avoid env-state coupling; deterministic over flexible |
| Deno/JSR | URL / scoped name | `deno.lock` | none | URL/module imports | JSR + permissions | **permissions model**, no hooks | URL sprawl; transitive URL trust | **capability/permission gating** is a strong idea |
| OCI artifacts | **digest** (tag = convenience) | digest *is* the lock | none | n/a (blobs) | signatures/provenance (cosign) | content-addressed, signable | tag mutability illusion | **digest = identity, name = convenience** (round-1 #1) |
| WASM component / WIT | **interface-first** package | — | none | WIT interfaces | capability-typed | capability boundaries, portable | early/complex tooling | interface+capability typing fits Igniter contracts |
| Terraform | source addr + version | `.terraform.lock.hcl` | provider plugins (authority) | module addressing | registry + checksums | declarative | provider authority creep | **provider authority must stay host-owned** |
| Rails engines | gem | Gemfile.lock | initializers/migrations | mounted routes/assets | rubygems | app extension | **engine mutates app silently** (migrations/assets) | **packages must not silently mutate the host app** |

## 3. ≥5 concrete failure modes to avoid (named)

1. **npm postinstall / Cargo `build.rs` arbitrary code** → supply-chain RCE on install. **Igniter: no
   install/build scripts; all generation is a known compiler/lowerer step.**
2. **Semver-range solving (npm/Bundler)** → drift, "works on my machine", SAT blowups. **Igniter: pin
   content digests; local path deps have no ranges; defer any solver.**
3. **Phantom transitive imports (npm flat `node_modules`)** → a package imports a dep it never declared.
   **Igniter: resolve a package's imports only against its *declared* deps (strict ownership) — flagged as
   a later slice, since live `compile_units` is flat.**
4. **Global-namespace clashes (RubyGems require)** → two packages define the same name. **Igniter: validate
   no two packages own the same logical module path; `stdlib.*` reserved.**
5. **Silent host mutation (Rails engines)** → installing a package runs migrations / injects routes/assets.
   **Igniter: a package is inert source; it cannot mutate the host app, run effects, or add routes by
   install — the app composes it explicitly.**
6. **Python virtualenv/env-state coupling** → build result depends on ambient environment. **Igniter: the
   deterministic source-hash + pure compile make build reproducibility the default.**

## 4. Answers to the 12 research questions (live-grounded)

1. **What is a package?** Primarily **authored source** — `.ig` + projection-dialect source (`.igweb`/
   `.igv`) + a small manifest. `.igapp` (compiled) is **build output / release artifact**, not the package
   identity (Q6). stdlib is a special canon package; an app/recipe is just a package whose entry is an app.
2. **Dependency identity?** **Two-layer:** human scoped name for DX; **blake3 content digest** (over the
   package's sorted source set — the existing deterministic hash) as the reproducibility anchor in the lock.
3. **Unit of trust?** The **source package by content digest**. Generated `.ig`/`.igapp` are *derived* and
   re-derivable, so they are evidence, not the trust root. (A future registry adds signing over the digest.)
4. **Unit of execution?** Unchanged by packaging: the **app entry** (a `.ig` contract / `Serve` capsule)
   the host loads. A package adds modules to the compile unit; it does not introduce a new run unit.
5. **How do projection dialects participate?** Packages ship **authored `.igweb`/`.igv` source**; the
   generated `.ig` is produced deterministically at build by the *known* lowerer (no package code). The
   dialect lowerer version is a future lock field (#3). `.igweb`/`.igv` never become runtime authority (P0).
6. **Lockfile?** v0: **per-workspace lock** pinning each dependency's **content digest** (blake3). Phase 2:
   add compiler/stdlib/lowerer versions + generated-artifact hashes. (Open Q2 → *per-workspace*, not
   per-package, in v0.)
7. **Import resolution?** Packages contribute **logical module paths** to one namespace (live model);
   `import Foo.Bar` resolves across declared dependency roots; `stdlib.*` reserved; **duplicate module
   ownership across packages is an error**. Strict direct-dep-only resolution (no phantom transitive) is a
   later slice (flat `compile_units` allows it today — Q3 anti-pattern).
8. **npm-style script risk?** **No install/build hooks.** Generation is a known compiler/tool step the
   *user/host* invokes (`igniter build`), never package-provided executables. This is non-negotiable.
9. **Features/options?** **Not in v0.** Cargo-style feature flags explode complexity; defer until a real
   need. v0 = whole-package deps only.
10. **Host capabilities?** A package **declares abstract needs** (e.g. `Postgres.Read`, `Http.Outbound`) in
    its manifest — a list of logical capability *targets*, never DSNs/secrets/endpoints. The **host** binds
    the real capability/passport at run time (live `target`-vs-authority boundary). This is the same model
    as the IgWeb `Decision`/effect-host split.
11. **App/domain vs stdlib/canon packages?** stdlib/canon = curated, namespace-reserved (`stdlib.*`),
    promotion-gated (P0 ladder). App/domain = **app-local by default** (path dep in the workspace), never
    canon by being popular. Dialect packages (a `.igweb`/`.igv` lowerer) are tooling, distinct from runtime
    packages.
12. **Smallest v0 slice?** A **local workspace resolver** (§6) — parse `[dependencies]` path entries, add
    their roots to `compile_units`, validate no duplicate module ownership. **No** registry, solver, lock,
    or hooks yet. The lock/provenance slice follows once the resolver is grounded.

### Round-1 open questions (Opus answers)

- **Q1 generated-artifacts policy:** a deterministic **build cache + source map** is enough; do **not**
  commit generated `.ig` by default (it is re-derivable; committing it invites drift). Make it
  inspectable on demand.
- **Q2 lock granularity:** **per-workspace** lock in v0.
- **Q3 digest:** **reuse the existing blake3** helper (already in the receipt path) — not SHA-256.
- **Q4 namespace mapping:** **validate** declared modules against ownership; do **not** force a name→prefix
  rule (Igniter imports are logical paths, not package-scoped). Soft convention, hard collision-check.
- **Q5 phantom transitive:** requires per-package import scoping — **deferred** (flat `compile_units`
  can't enforce it yet); name it as the first hardening after the resolver.
- **Q6 `.igapp`:** **build cache / release artifact**, NOT part of the package identity.
- **Q7 dialect cycles:** lower dialects in a fixed, acyclic order (source `.igweb`/`.igv` → `.ig`; no
  dialect output feeds another dialect's input in v0) — enforce no nested/generated-dialect chains.
- **Q8 capability manifest:** minimal field set = `{ capability: "<Logical.Target>", mode?: "read|write" }`
  per entry — **no** endpoint, DSN, credential, or deployment topology. Host-bound.

## 5. Candidate models scored (A–F)

| Model | det. build | inspectable | content-addr | src/gen/compiled split | no authority escalation | local-first | solo-simple | Verdict |
|---|---|---|---|---|---|---|---|---|
| A source-only | ✓ | ✓ | ✓ | partial | ✓ | ✓ | ✓ | good base |
| B compiled-artifact | ✓ | ✗ (opaque) | ✓ | ✗ | ✓ | ✓ | ✗ | reject as identity |
| C dual (src+gen+compiled+lock) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✗ (heavy) | **end-state, not v0** |
| **D app-local workspace resolver** | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | **RECOMMEND v0** |
| E registry-first | ✓ | ✓ | ✓ | ✓ | risk | ✗ | ✗ | defer |
| F OCI/content-store | ✓ | ✗ | ✓✓ | ✗ | ✓ | ✗ | ✗ | borrow *digest=identity* only |

**Recommendation: D (app-local workspace) for v0**, carrying A's source-package shape + F's
digest-as-identity in the lock, growing toward C (dual + full provenance) later. Reject B (compiled-as-
identity) and defer E (registry).

## 6. Smallest v0 implementation slice (named, not implemented)

`LAB-IGNITER-PACKAGE-WORKSPACE-RESOLVER-P2` — a **local workspace resolver only**:
- extend `igniter.toml` with `[dependencies]` **path** entries (`foo = { path = "../foo" }`);
- add each dependency's `source_roots` to the `compile_units` source set (reuse `project.rs::resolve_entry`);
- **validate no duplicate logical-module ownership** across packages (collision = error; `stdlib.*` reserved);
- **no** registry, **no** version solver, **no** lockfile, **no** install/build hooks, **no** `.igapp` in
  the package.
Acceptance sketch: a 2-package workspace compiles cross-package `import Foo.Bar`; a duplicate-module
collision is a clean diagnostic; deterministic source-hash is stable across runs; `igniter-server`/web
untouched.

Then `…-PACKAGE-LOCK-PROVENANCE-P3` (blake3 per-workspace lock over dependency source sets) → later
strict-direct-dep enforcement, dialect-version pinning, and only much later a registry/solver.

## 7. Deferred (explicit)

Registry; version ranges + MVS/SAT solver; install/build hooks; Cargo-style features; signing/provenance
chain; strict phantom-transitive enforcement; dialect-lowerer-version + compiler-version lock fields;
`.igapp` distribution; remote/network sources; credentials of any kind.

## Acceptance — mapping

- [x] Research/readiness only; no code.
- [x] Comparative table (§2, 10 ecosystems, required columns).
- [x] ≥5 concrete failure modes to avoid (§3, 6 named).
- [x] Distinguishes source / generated / compiled / deployed (§0, §4 Q1/Q5/Q6).
- [x] Candidate identity models defined (§4 Q2 two-layer; §5 A–F).
- [x] Lockfile/provenance direction (§4 Q6, blake3 per-workspace, phased).
- [x] Projection dialects' participation explained (§4 Q5; P0-grounded).
- [x] Capabilities-not-credentials explained (§4 Q10; live `target` boundary).
- [x] One smallest v0 slice recommended (§6 workspace resolver).
- [x] Deferred items stated (§7).

---

## Closing report

**Sources/ecosystems reviewed:** Cargo/Go/npm-pnpm-yarn/RubyGems-Bundler/Python/Deno-JSR/OCI/WASM-WIT/
Terraform/Rails-engines (§2), plus the six Gemini round-1 shard+synthesis reports and live Igniter surfaces
(`project.rs`, `igweb.rs`, `protocol.rs`, P0, blake3 receipts).
**Comparative table:** §2. **Recommended v0 model:** **D — app-local workspace resolver** (source packages
+ blake3 digest-as-lock-identity), growing toward dual+provenance; reject compiled-as-identity, defer
registry/solver.
**Top-5 anti-patterns:** install scripts (npm/`build.rs`); semver-range solving; phantom transitive imports;
global-namespace clashes; silent host mutation (Rails engines). [+ env-state coupling.]
**Fit with Igniter philosophy:** the substrate already exists (`source_roots`, logical-module imports,
deterministic source-hash, `target`-vs-authority capability split, blake3) — so the package manager is a
**small deterministic extension**, contracts-first, authority-explicit, source/projection separated, lab
evidence before canon.
**Next card:** `LAB-IGNITER-PACKAGE-WORKSPACE-RESOLVER-P2` (path-dep roots + module-ownership validation; no
registry/solver/lock/hooks) → `…-PACKAGE-LOCK-PROVENANCE-P3`. **No code; no canon claim.**

*Readiness/research only. Compiled 2026-06-21; validated round-1 against live `project.rs`/`igweb.rs`/
`protocol.rs`/P0. All 7 round-1 signals accepted (2 phased); recommends an app-local workspace resolver as
the smallest v0.*
