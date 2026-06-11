# LAB-PACKAGE-MODEL-P1 (a2) — Package Identity / Distribution Boundary Research

**Track:** package-identity-distribution-and-authority-boundary-v0
**Route:** RESEARCH / DESIGN BOUNDARY / NO IMPLEMENTATION
**Branch:** a2 (parallel to a1; independent design, comparison deferred to close)
**Date:** 2026-06-11
**Status:** CLOSED / OPEN-with-SPLIT (see §14)
**Authority:** research doc + card + portfolio update only. No package manager, registry,
lockfile, import, parser, compiler, VM, or runtime implementation. No public package API.
No stdlib promotion. No capability/profile granting through dependencies.

---

## 1. Problem Statement

Igniter has crossed the threshold where packages stop being hypothetical:

- Multi-file compilation units are live in Ruby canon (PROP-IMPORT-RESOLUTION-P5, 99/99).
- Module identity and SHA256 hash discipline are unified (LANG-MODULE-IDENTITY-P2, C24 closed).
- Cross-module typed contract references are live (LANG-TYPED-CONTRACT-REF-P5, 71/71) —
  code in one module can now reference contracts in another with full attribution evidence.
- Form vocabularies (LAB-FORM-VOCABULARY-P1) imply reusable, importable declaration sets.
- RES-001/002/003 independently converge on "library reuse begins at multi-file" — which shipped.

The danger is that the next step gets taken *by default*, in the npm shape, because that
shape is what every engineer carries in their head. The npm/node_modules model has three
properties that are each individually incompatible with the Igniter covenant:

1. **Ambient authority.** An npm dependency executes at install time (postinstall) and at
   import time (module top-level), with the full authority of the host process. In Igniter
   terms this violates P10 (profiles cannot be bypassed at runtime), P21 (a program names
   all its consequences — a dependency that can do unnamed things makes the consumer's
   account false), and P22 (assumptions must be declared, not hidden).

2. **Mutable dependency truth.** npm tags and version ranges are mutable name→content
   bindings. `left-pad@latest` is a different artifact on Tuesday than on Monday. Igniter's
   entire identity spine (source_hash / contract_ref / artifact_hash / compiler_profile_id)
   is content-addressed and immutable; a packaging layer with mutable truth would be the
   one layer where the honesty discipline silently breaks.

3. **Hidden transitive behavior.** The npm dependency tree is invisible at the point of
   consumption; effect surface and authority requirements of transitive dependencies never
   appear in the consumer's own account. This is the composition-boundary failure P20
   exists to prevent: evidence (here: authority evidence) lost at composition.

**Core principle under test:** *an Igniter package is a sealed claim artifact, not a
dependency dump.* A package makes declarations available for verification. It must not
silently grant authority. This document tests that principle against the current substrate
and answers the identity / distribution / lockfile / registry / transitive questions far
enough to route P2.

---

## 2. Current Substrate Inventory

What exists today, with exact shapes (all verified against live code/docs, not from memory):

| Surface | Shape / Formula | Status | Package relevance |
|---|---|---|---|
| `module Dotted.Path` | logical name, no filesystem inference | canon Ch2 | module = unit of attribution |
| `import Mod.{a,b}` | compile-time name resolution only; `OOF-IMP1` circular / `OOF-IMP2` unknown / `OOF-IMP3` missing name / `OOF-IMP4` dup module / `OOF-IMP5` missing decl | canon, P5 proved | the *only* consumption mechanism a package needs |
| `source_hash` (single) | `sha256(file_bytes)`, `^sha256:[a-f0-9]{64}$` | canon | leaf identity |
| `source_hash` (multi) | `sha256(canonical_json([{module, source_path, source_hash, source}...] sorted by module, then path))` | canon (IMPORT-P5) | **this is already a package digest** — order-independence proved (IMPORT-P5; re-confirmed in TYPED-REF-P5 check I-02) |
| `contract_ref` | `contract/<Name>/sha256:<24hex>` from contract body | canon | per-declaration API fingerprint |
| `artifact_hash` | sha256 over canonical artifact material (semantic_ir_program, contracts, compilation_report, requirements, diagnostics, classified_ast, compatibility_metadata, ±entrypoint, ±source_units, ±compiler_profile_id) | canon | per-compilation identity; depends on compiler |
| `program_id` | SHA256, unified Ruby/Rust (MODULE-IDENTITY-P2, 42/42) | canon | C24 closed — identity claims now toolchain-stable |
| `compiler_profile_id` | `compiler_profile_unified/sha256:<…>` | PROP-036 partial | pins *which compiler contract* verified a claim |
| `source_units` | `[{module, source_path, source_hash, types[], contracts[]}]` in manifest + SIR | canon (IMPORT-P5) | the package "bill of materials" already exists as evidence |
| `entrypoint` | `{kind, declared_target, resolved_contract, contract_ref, contract_path, source_span}`; zero-or-one | canon (ENTRYPOINT-P3/P4) | packages are entrypoint-free libraries by default |
| `dependency_edges` | `[{from, to, kind: "typed_contract_ref", execution_dependency: false, resolution, from_module, to_module, resolution_kind}]` | canon (TYPED-REF-P5, 71/71) | **cross-module reference graph with attribution is live evidence** |
| `contract_refs` (SIR) | per-contract resolved refs with `resolution_kind: local/qualified/imported/unresolved`, `module_name`, modifier, arity | canon (TYPED-REF-P5) | the mechanism by which consumer code references package contracts |
| `fragment_summary` / `contract_index` | per-artifact census | canon | effect-surface census input |
| capability/effect declarations | PROP-031/033/035/040 (modifiers, `via`, capability grammar) | experiment-pass | the authority layer packages must NOT touch |
| `compiler_profile_contract` | slot schema; **dynamic pack loading explicitly forbidden (PROP-038 §16)** | accepted | hard floor under "no install-time execution" |

**Gap found during TYPED-REF-P5 implementation (new substrate fact, empirical):**
the merged-universe architecture enforces **global uniqueness of contract names** across
the entire compilation unit (`OOF-DECL-DUP-CONTRACT`). Two modules — and therefore two
*packages* — exporting a contract with the same name cannot coexist in one universe today.
This was hit directly: P5 ambiguity fixtures (two modules both declaring `Validator`)
could not be compiled via `compile_sources` and had to be tested by direct TypeChecker
invocation. The resolution machinery is already attribution-aware (`per_contract_module`,
PATH 2a/2b, `resolution_kind`), but the *declaration* layer is not. **Contract-name
global namespace is the single most package-hostile property of the current substrate.**
See §9 and §15.

What is missing entirely: package grouping above module; any fetch/acquisition story;
exports boundary; lockfile; registry. All correctly absent — nothing has pre-empted design.

---

## 3. Package Definition Candidates

| | Candidate | What ships | Verdict |
|---|---|---|---|
| A | **Source bundle** | `.ig` files + nothing | Honest (recompute-everything) but claim-free: consumer learns nothing without full compile; no API boundary; no identity beyond a directory hash. Insufficient alone. |
| B | **`.igapp` artifact** | compiled SemanticIR + manifest | Sealed, but wrong unit: `.igapp` is *per-compilation-universe* (consumer-specific merge), depends on `compiler_profile_id`, and SemanticIR-only distribution freezes the compiler contract (RES-002 [Q]) and hides source from recomputation. An `.igapp` is what a *consumer* builds, not what a *producer* ships. |
| C | **Manifest-only** | claims + fetch pointers | Weakest: truth lives elsewhere; pure trust-me. Rejected as a package; useful only as a *registry index entry*. |
| D | **Proof/receipt bundle** | receipts without code | Cannot be consumed; receipts are package *cargo*, not the package. |
| E | **Layered: source + manifest + optional receipts** | A as ground truth, C as index, D as optional cargo | **v0 candidate.** |

**Decision: E**, governed by one rule that keeps it honest:

> **Source is the truth. The manifest is an index of claims. Recomputation is the check.**

A consumer toolchain MUST be able to recompute every manifest claim (digests, exports,
fragment/effect census, dependency requirements) from the shipped source and refuse on
mismatch. Build-time summaries exist so resolvers can *plan* without compiling; they never
*settle* anything. This is RES-002's "recompute-always" answer adopted as a hard rule, and
it is the packaging analogue of the existing OOF discipline: check, not trust.

No HOLD needed: every field the v0 manifest requires (§12) has a live canon source.

---

## 4. Authority Boundary

Explicit answers, each with its enforcing mechanism (not aspiration):

| Question | Answer | Mechanism |
|---|---|---|
| Can a dependency bring capability? | **No.** | Capability binding is consumer-side (PROP-033/035 pattern; PROP-040 cross-module profile question answered as consumer-side binding per RES-002 §2.2). The package manifest grammar (§12) **has no capability-grant field** — smuggling is a schema violation, not a policy violation. |
| Can a dependency bind a profile? | **No.** | PROP-040 v0 is same-module-only by design; any future cross-module profile flows consumer→dependency (`via` at the consumption site), never exporter→consumer. |
| Can a dependency create a runtime effect? | **No.** | A package contributes *declarations* into a merged compile-time universe. There is no package-runtime; effect execution is gated by fragments/profiles/capabilities exactly as for local code. |
| Can a dependency execute at install/import time? | **No.** | Import is compile-time name resolution only (IMPORT-P1 §7); there is no install hook surface, and dynamic pack loading is already explicitly forbidden (PROP-038 §16). Acquisition (§5 layer 0) is byte transfer + digest verification — content-neutral. |
| Can a dependency expose effect contracts? | **Yes — as declarations only.** | Fragment classification derives from declaration content, not import presence. An imported `effect` contract is inert: the pure-callee gate and modifier discipline apply to the consumer's call sites unchanged (IMPORT-P1: "name availability ≠ authority to execute"). |
| Who grants capability? | **The app/host/consumer**, at the composition root. | RES-003's A4 application manifest is the natural home of the authority census: the application, not any library, declares the full effect/capability budget. |

One sentence version: **authority is granted downward from the composition root, never
upward from a dependency.** A package widens the consumer's *option space* (more
declarations available) and never the consumer's *authority surface*.

Corollary worth stating because npm trained everyone otherwise: a malicious Igniter
package can lie in its manifest (caught by recompute), squat a name (§11), or declare
unpleasant effect contracts (visible in its census, inert until bound) — but it has **no
write path** to capability, profile, runtime, or install-time execution. The attack
surface is reduced to *claims*, and claims are checkable.

---

## 5. Import vs Package — Layer Separation

Four layers, strictly ordered, no layer reaching into another:

```text
Layer 0  PACKAGE ACQUISITION   fetch bytes, verify package_digest, materialize on disk
         (outside the compiler; the compiler never sees a registry, URL, or version)
Layer 1  MODULE IMPORT          import Mod.{a,b} — compile-time name resolution over
         the merged universe; OOF-IMP1..5 unchanged   [canon, IMPORT-P5]
Layer 2  TYPED CONTRACT REFS    uses Mod.Contract — resolution_kind + dependency_edges
         evidence with module attribution              [canon, TYPED-REF-P5]
Layer 3  RUNTIME INVOCATION     call_contract / future invocation — gated by fragment,
         modifier, profile, capability                 [unchanged; mostly closed]
```

The package layer's *entire* contract with the compiler: it delivers a set of source
units into the multifile resolver's input list. `compile_sources(source_paths:)` is
already the correct seam — packages change *where the paths come from*, nothing about
what happens after. Import stays compile-time name resolution; acquiring a package does
not import it; importing a module does not invoke anything; referencing a contract does
not execute it. Each arrow between layers is explicit consumer action.

This also settles the resolver/compiler trust split: a compromised Layer-0 tool can at
worst deliver wrong bytes, which the digest check catches; it cannot influence Layers 1–3
because they only consume verified source units.

---

## 6. Identity Model

**Content-addressed identity is primary; names are mutable human labels (petnames) bound
to digests by *claims*, never by identity.**

Candidate field set:

| Field | Definition | Source discipline |
|---|---|---|
| `package_name` | dotted label, e.g. `Lab.Query` — display + resolution request key, NOT identity | new (label only) |
| `package_digest` | `sha256(canonical_json([{module, source_path, source_hash, source}...] sorted by module, then path))` over the package's own source units | **verbatim reuse of the multi-file composite source_hash rule** (IMPORT-P5); order-independence already proved |
| `module_set_digest` | sha256 over sorted `[module_path, source_hash]` pairs — cheap membership check without full source | derived from the above; index-only |
| `source_units` | exact canon shape `{module, source_path, source_hash, types[], contracts[]}` | canon reuse |
| `exports_digest` | sha256 over canonical export index: exported modules → their `contract_ref`s + type names + modifiers + arities | new; built from canon `contract_ref` + (future) PROP-017 fingerprints |
| `artifact_hashes` | optional map `compiler_profile_id → artifact_hash` — "this source, compiled under that profile, yields this artifact" | claim; recomputable |
| `compiler_profile_id` | profile(s) the producer's claims were computed under | PROP-036 |
| `language_version` / `grammar_version` | declared compatibility floor | canon manifest fields |
| `dependency_graph_digest` | sha256 over sorted `package_digest`s of all (flattened, §9) dependencies | new; makes the full graph a single checkable fact |

Key consequences:

- **Two packages with identical sources are the same package**, regardless of name. Name
  disputes (typosquatting, confusion) become disputes about *claims in a catalog*, never
  about *what code is*.
- **`package_digest` vs `exports_digest` separation does real work**: a comment-only change
  shifts `package_digest` (raw-source identity, consistent with canon's deliberate choice)
  but not `exports_digest`. Resolvers compare exports_digests to answer "did the API
  change?" — the computed-compatibility direction of RES-002 §2.3 (CompatibilityReport as
  ground truth, semver as human-facing label only).
- **Versions are labels on digests.** `1.2.0` is a producer claim attached to a digest in
  a catalog; the lockfile records the digest. There is no range-resolution against mutable
  truth anywhere in the model.
- The open name-authority question (RES-002 [Q]: global module namespace politics) is
  *defused rather than solved* by content addressing: collisions of `module` paths across
  packages remain a merge-time `OOF-IMP4` fact, deterministic and visible, whatever the
  catalog says. (Contract-name collisions are sharper — §9, §15.)

---

## 7. Lockfile = Resolution Receipt

The lockfile is not configuration; it is **evidence of a resolution event** — the same
move the compilation_report makes for compile events. Design shape (design-only):

```jsonc
{
  "kind": "package_resolution_receipt",
  "format_version": "...",
  "resolver_id": "igniter-resolver/<impl>/<digest>",
  "resolved_at": "<timestamp>",
  "compiler_profile_id": "compiler_profile_unified/sha256:…",   // profile used for verification
  "requests": [
    { "name": "Lab.Query", "constraint": "<label or digest pin>" }
  ],
  "resolved": [
    {
      "name": "Lab.Query",
      "package_digest": "sha256:…",
      "exports_digest": "sha256:…",
      "origin": { "kind": "local_path | catalog | git", "ref": "…" },
      "verification": {
        "status": "recomputed | claim_only",     // recomputed = manifest claims re-derived from source
        "checked": ["package_digest", "exports_digest", "fragment_summary"],
        "mismatches": []
      },
      "fragment_summary": { "...": "census copied as evidence" },
      "capability_requirements": [ "...declared, NOT granted..." ]
    }
  ],
  "rejected": [ { "name": "…", "package_digest": "…", "reason": "…" } ],   // optional, audit
  "graph_digest": "sha256:…"        // = dependency_graph_digest over `resolved`
}
```

Properties that make it a receipt and not an npm lockfile:

1. **No authority fields exist in the schema.** `capability_requirements` is a *census of
   declarations* (what the package would need bound to run its effect contracts), copied
   as evidence for the consumer's composition-root decision. Nothing in the lockfile is
   read by any authority mechanism.
2. **`verification.status` is first-class.** `claim_only` entries are legal (offline,
   fast-path) but visibly weaker; CI/gates can require `recomputed`. Honesty about *how
   much was checked* beats pretending everything always is.
3. **Stale-detection is structural**: receipt pins `compiler_profile_id` + digests; any
   drift in either invalidates the specific claims, not the whole file.
4. **Deterministic**: same requests + same catalog state ⇒ identical receipt (timestamps
   excluded from any receipt digest). Sorted ordering rules inherited from canon.

---

## 8. Registry Model

| | Model | Tradeoff | Verdict |
|---|---|---|---|
| A | Trusted central registry | npm/crates shape; reintroduces trust-not-check at the root; single compromise point; governance weight | **Rejected as design center** |
| B | Untrusted content-addressed catalog | registry = dumb CAS + a *claims index* (name→digest, version labels, producer signatures); client verifies everything; registry compromise degrades to availability + first-resolution confusion | **Design center, post-v0** |
| C | Local path workspace | already implicitly live (`compile_sources` over paths); zero infra; no naming problem | **v0** |
| D | Git/source archive | a fetch *transport* for B/C, not a registry model; mutable refs forbidden as identity (commit/tree hash ≈ digest, acceptable as origin evidence) | transport only |
| E | Private signed index | a signature layer over B's claims index; design-only per card | compatible, deferred |

**v0 = C; the model is designed so B is reachable without changing a single identity or
lockfile field** — only `origin.kind` gains a value. The registry's role collapses to
"a place that makes claims"; since every claim is client-verifiable, the registry needs
*availability* trust only, not *integrity* trust. That is the structural difference from
npm, where the registry is the root of truth.

---

## 9. Transitive Dependencies

Decision: **allow, but flatten into the lockfile with a full census** (option b+d of the
card), with one structural sharpening:

- Every transitive package appears as a first-class `resolved` entry in the receipt —
  there is no nesting, no deduplication magic, no hidden node. `graph_digest` commits to
  the full flattened set.
- The consumer's own effect/capability census **includes the transitive census** — P20's
  "no evidence lost at composition" applied to authority requirements. A dependency three
  levels down declaring an `irreversible` contract is visible at the application manifest.
- "Explicit consumer approval" (option c) is achieved structurally, not interactively:
  approval = committing the receipt. Gates can diff receipts.
- v0 (local-path) makes transitivity trivially visible anyway — it is workspace topology.

**Hard constraint to surface now (empirical, from TYPED-REF-P5):** the merged universe
enforces `OOF-DECL-DUP-CONTRACT` — contract names are global across the universe. At
package scale this guarantees collisions (every ecosystem grows two `Validator`s; the P5
fixtures already could not co-compile two of them). The resolution layer is ready —
`per_contract_module` attribution, qualified refs, `resolution_kind` — but the
*declaration* layer still treats contract names as one flat namespace. Routing options:

- (i) narrow duplicate-contract uniqueness to **per-module** once all reference paths are
  attribution-aware (P5 did typed refs; `call_contract` string callees and any remaining
  name-keyed maps must follow);
- (ii) keep global uniqueness and accept ecosystem-scale collision OOFs (not viable);
- (iii) qualified-only references across package boundaries plus per-module declaration
  uniqueness (strictest, friendly to forms/vocabulary ownership rules).

This is a **prerequisite study, not a packaging feature** — it must be settled before any
P2 proof compiles two realistic packages together. See §15.

---

## 10. Stdlib vs Package vs App-Local

One mechanism, five trust positions — the *kind* does not change, only who pins it and how:

| Kind | Identity | Pinned by | Notes |
|---|---|---|---|
| stdlib | the same package identity (`package_digest`), pinned as RES-001's inventory hash | the compiler / `compiler_profile_id` | stdlib is "the package the compiler vouches for"; first dogfooding target once self-hosted |
| app-local modules | none — same universe, no package boundary | n/a | today's normal state; zero ceremony preserved |
| workspace modules | local-path packages (origin: `local_path`) | the workspace receipt | v0 target |
| third-party | fetched sealed claims (origin: catalog/git) | consumer lockfile | post-v0 |
| proof-local lab fixtures | **never packaged** | n/a | lab fixtures stay proof-local by rule; packaging one is a category error |

The distinction "stdlib vs package" is therefore *governance*, not *mechanism* — exactly
the property that lets stdlib be the first real package without a special-case code path.

---

## 11. Security / Honesty Risk Map

| npm-world failure | Igniter guardrail | Residual risk |
|---|---|---|
| Dependency confusion (internal name shadowed publicly) | identity is digest; name→digest binding is a catalog claim checked against the lockfile pin | first-ever resolution of a new name (no pin yet) — mitigate with origin allowlists; UX problem, not identity problem |
| Mutable tags / republished versions | digests immutable; versions are labels on digests; receipt pins digests | none at identity layer |
| Hidden effect surface | recompute-always: fragment/effect census re-derived from source; mismatch with manifest claim ⇒ refusal | census quality bounded by PROP-035 coverage (improves as effect surface matures) |
| Capability smuggling | **schema-impossible**: no grant fields exist in manifest or receipt grammar; consumer-side binding is the only path | none by construction; watch for future fields eroding this |
| Install-time execution | no hook surface exists; PROP-038 §16 forbids dynamic loading; acquisition is byte transfer | none |
| Artifact/source mismatch | source is the truth; `artifact_hashes` are claims keyed by `compiler_profile_id`, recomputable | none if recompute gate enforced |
| Stale receipts | receipts pin `compiler_profile_id` + digests; drift is detectable per-claim | process discipline to actually re-verify |
| Typosquatting | digests don't help UX — this is a petname/claims problem | real; needs catalog-side claims policy + receipt review; explicitly design-only here |
| Transitive graph explosion | flattened receipt makes size/census visible; `graph_digest` commits to the whole set | social: large graphs remain large; visibility ≠ smallness |
| Registry compromise | registry holds claims, not truth; compromise degrades to availability + confusion-on-first-resolution | availability; first-resolution window |
| **Contract-name collision at scale** (Igniter-specific) | none today — `OOF-DECL-DUP-CONTRACT` is global | **blocking; routed as prerequisite study (§9, §15)** |

---

## 12. Candidate v0 Package Manifest (DESIGN-ONLY — no schema authority claimed)

```jsonc
// igpack.json — v0 sketch, design-only
{
  "kind": "igpack_manifest",
  "format_version": "igpack-design-v0",

  // — identity (§6) —
  "package_name": "Lab.Query",                    // label, not identity
  "package_digest": "sha256:…",                   // composite source_hash rule, verbatim
  "module_set_digest": "sha256:…",
  "exports_digest": "sha256:…",
  "language_version": "…",
  "grammar_version": "igniter-v0",
  "compiler_constraints": {
    "verified_under": ["compiler_profile_unified/sha256:…"]
  },

  // — contents (canon shapes, reused verbatim) —
  "source_units": [
    { "module": "Lab.Query", "source_path": "src/query.ig",
      "source_hash": "sha256:…", "types": [], "contracts": ["Validator", "Scorer"] }
  ],

  // — API boundary (RES-002 §3.2: per-module, not per-declaration) —
  "exports": ["Lab.Query"],                       // module list; unlisted modules are internal

  // — computed claims (index only; recompute is the check) —
  "fragment_summary": { "…": "census" },
  "capability_requirements": [                    // declared needs; NEVER grants
    { "contract": "Lab.Query.Persist", "modifier": "effect", "capabilities": ["IO.Storage…"] }
  ],
  "internal_dependency_edges": [                  // canon dependency_edges shape, package-internal
    { "from": "Scorer", "to": "Validator", "kind": "typed_contract_ref",
      "execution_dependency": false, "resolution": "resolved",
      "from_module": "Lab.Query", "to_module": "Lab.Query", "resolution_kind": "local" }
  ],

  // — requirements on other packages —
  "dependencies": [
    { "name": "Lab.Core", "package_digest": "sha256:…" }   // digest-pinned; labels optional
  ],

  // — optional cargo (§3 layer D) —
  "receipts": {
    "artifact_hashes": { "compiler_profile_unified/sha256:…": "sha256:…" },
    "proofs": [ { "kind": "…", "ref": "…" } ]
  }
}
```

Every non-new field reuses a live canon shape (`source_units`, `dependency_edges`,
`fragment_summary`, hash formats). The genuinely new surface is exactly four ideas:
`package_digest` (formula reuse), `exports` (module list), `exports_digest`,
digest-pinned `dependencies`. Deliberately boring.

## 13. Non-Goals (closed by this research)

No install command. No registry protocol. No semver policy (versions = labels on digests;
compatibility = computed, PROP-017 direction). No binary distribution. No runtime plugins
(PROP-038 §16 stands). No package-level visibility beyond the `exports` module list (no
per-declaration keywords — Ch2 stance preserved). No package signing beyond the design
note in §8/E. **No automatic capability grants — closed permanently, not deferred:** the
schema has no field for it, and adding one would be a covenant-level change, not a
packaging change.

---

## 14. Recommendation

**OPEN — with SPLIT.** The substrate is sufficient; nothing requires HOLD:

- identity primitive: live (composite source_hash, order-independent, toolchain-unified)
- bill of materials: live (`source_units`)
- cross-boundary reference evidence: live (`dependency_edges` + `resolution_kind`, P5)
- authority non-flow: established pattern (consumer-side binding) + forbidden surfaces (PROP-038 §16)

Split, in dependency order:

1. **Contract-name namespace prerequisite study** — settle §9 (per-module uniqueness vs
   global; what must become attribution-aware beyond typed refs). Small, blocking for any
   two-package proof. This is *language* work surfaced by packaging, not packaging work.
2. **Proof-local package manifest + lock receipt** — two local packages through the real
   Ruby canon `compile_sources`, manifests + receipt generated and re-verified
   (LAB-PACKAGE-MODEL-P2 below).
3. **Identity/lockfile proposal authoring** — after P2 evidence, route to canon proposal.

Registry (B) stays design-only until 2–3 are closed.

## 15. Next Route

**LAB-PACKAGE-MODEL-P2 — proof-local package manifest + lock receipt over two local packages.**

Proof-local (no canon changes), exercising the real pipeline:

- Fixture: `pkg_core/` (e.g. `Lab.Core` with `Validator`) and `pkg_app/` (`Lab.App`
  importing it, `uses Lab.Core.Validator`) as two local-path packages.
- Build `igpack.json` for each (proof-local generator): `package_digest` via the canon
  composite rule; `source_units` from the real MultifileResolver; census from real manifest.
- Resolve: produce a `package_resolution_receipt`; verify `recomputed` status by
  re-deriving every claim; tamper one byte → verification mismatch (negative check).
- Compile the union through real `compile_sources`; assert cross-package
  `dependency_edges` carry `resolution_kind: "qualified"/"imported"` with correct
  `to_module` (direct reuse of TYPED-REF-P5 substrate as the cross-boundary evidence).
- Authority checks: assert no capability/profile/grant field anywhere in manifest or
  receipt; assert imported effect contract remains inert for a pure consumer.
- Determinism: same inputs ⇒ identical receipt; package file order independence.

Parallel small card: **LANG-CONTRACT-NAMESPACE-P1** — the §9 prerequisite study (research
route, no implementation): inventory every name-keyed surface (dup-contract rule,
`call_contract` string callees, same_module_registry, manifest `contracts` list…), decide
per-module vs global uniqueness, route the implementation card.

Alternative routes considered: PROP-PACKAGE-MODEL-P1 (proposal authoring now) — premature
before P2 evidence; LANG-PACKAGE-LOCK-P1 (lockfile design alone) — receipt shape is
cheap to carry inside P2, doesn't need its own clock yet.

---

## Acceptance Bar Check

- Package boundary separated from import/runtime/capability: §4, §5 (four layers, mechanisms named) ✓
- v0 package candidate defined: §3 (layered E) + §12 (manifest sketch) ✓
- npm failure modes mapped to guardrails: §1, §11 (incl. one Igniter-specific blocker found) ✓
- Identity/lockfile/registry answered enough to route P2: §6, §7, §8 ✓
- Next route concrete: §15 (P2 fixture plan + prerequisite card) ✓

**Verdict: CLOSED / OPEN-with-SPLIT.**

---

## Sources

Canon/proposals: PROP-IMPORT-RESOLUTION P1/P2/P2A/P4/P5; PROP-ENTRYPOINT P1–P4;
LANG-TYPED-CONTRACT-REF P1–P5 (P5: 71/71, this session); PROP-031/033/035/036/038/040;
PROP-017 direction. Research: RES-001, RES-002 (primary predecessor), RES-003.
Lab: LANG-MODULE-IDENTITY-P1/P2; LAB-FORM-VOCABULARY-P1; `multifile.rs` SourceUnit/
MergedProgram. Code verified live: `igniter-lang/lib/igniter_lang/assembler.rb`
(manifest fields + artifact material), `multifile_resolver.rb`, `out/add.igapp/manifest.json`.
Covenant: P10, P20, P21, P22 (wording verified against `docs/language-covenant.md`).
Parallel branch a1 (`lab-package-identity-distribution-boundary-v0-a1.md`) deliberately
NOT read before this document was written; comparison is reported separately at close.
