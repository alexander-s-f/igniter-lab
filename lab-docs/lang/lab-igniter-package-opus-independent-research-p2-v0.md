# lab-igniter-package-opus-independent-research-p2-v0 — independent competing thesis

**Card:** `LAB-IGNITER-PACKAGE-OPUS-INDEPENDENT-RESEARCH-P2` · **Delegation:** `OPUS-PACKAGES-INDEPENDENT-B`
**Status:** INDEPENDENT RESEARCH (lab). A second, adversarial Opus thesis — designed to **compete with**,
not summarize, Gemini Round 1. **No code, no package spec, no canon, no Gemini-report edits.**

> **Anchoring disclosure (honesty):** this lineage already produced the round-1 *validation*
> (`…-round1-opus-validation-p2-v0.md`), so I have read Gemini. I cannot pretend a clean-room read.
> Mitigation: §1 is written strictly from the **live Igniter surfaces** (which I know first-hand from
> the P1–P12 server/IgWeb work), and I deliberately push for the *divergent, simpler* answer rather than
> re-confirming the validation. Where I land on Gemini's conclusion, I say so and explain why it
> survived an adversarial pass.

## 1. Independent thesis (from live surfaces, before re-leaning on Gemini)

**"Package" is the wrong first abstraction for Igniter. The first problem is import ownership across
module roots — not distribution, not reproducibility, not artifacts.**

Reasoning from what actually exists:
- `project.rs` already resolves a project as **module-declaration-indexed source roots** → a transitive
  **non-stdlib import closure** → `multifile::compile_units`, with `OOF-IMP4` (duplicate module) and
  `OOF-IMP2` (missing import). `stdlib.*` is reserved.
- **What it does NOT do:** restrict *which* module may import *which*. In a multi-root build, any module
  in the closure can `import` any other, regardless of any declared dependency. There is no notion of a
  root **owning** a module namespace. So the one real, compiler-native gap is **phantom/ownership-free
  imports** — exactly the npm "phantom dependency" failure, but reachable today with zero registry.
- The compiler **already emits a content-addressed `source_hash` (`sha256`)**; the machine uses
  `blake3`. Reproducibility tooling has a substrate already; it is not a greenfield need.
- Lowering (`lower_igweb`/`lower_igv`) is **deterministic**; generated artifacts are reproducible from
  source. There is no install step, no hook, no nondeterminism to police.

Therefore my v0 thesis: ship a **workspace + import-ownership layer**, and do **not** call it a package
manager. The smallest thing that earns a name is a **module-namespace owner** (a declared root that owns
a module prefix). Reproducibility (lockfile) and distribution (registry, versions, signed bundles) are
**later, separate** problems that don't bite while inputs are local, owned, and deterministically built.

## 2. Live Igniter surface observations

| Surface | Observation bearing on packaging |
|---|---|
| `igniter-compiler/src/project.rs` | `igniter.toml` = `source_roots` only (default `["."]`); module-by-`module`-decl; transitive non-stdlib closure → `compile_units`; `stdlib.*` reserved; overlay (P2); `OOF-IMP4`/`OOF-IMP2`/`OOF-PROJ-ENTRY`. **No `[dependencies]`, no ownership, no lockfile.** |
| `igniter-compiler/src/main.rs` + emitter | content-addressed `sha256` `source_hash` already emitted per compiled artifact. |
| `igniter-compiler/src/igweb.rs`, `igniter-ui-kit/src/igv.rs` | deterministic projection-dialect lowering; generated output inspectable; pure compiler pass (P0). |
| `igniter-web/src/lib.rs` | `build_igweb_app` = lower → `load_program` → erased app; **no install hooks**; generated `.ig` to a build dir (regenerated, not authored). |
| `igniter-server/src/protocol.rs` | app decisions carry no `capability_id`/`operation`/`scope`. |
| `igniter-machine` | `ServiceRecipe.capability_bindings`/`required_scopes` = declarations; passports/secrets/`EffectBridgeConfig` host-owned; `.igapp` = compiled artifact; `ServiceRecipe` = the deployable. |
| crate layout | sibling crates via `path = "../x"`; **no Cargo workspace root** — local-path deps are the lived pattern. |

**Implication:** the missing primitive is *ownership of the import graph*, which `project.rs` is one
small step away from. Everything else (lock, registry, versions, bundles) is borrowed anxiety from
ecosystems that have remote, mutable, script-bearing dependencies — none of which Igniter has.

## 3. Alternative model comparison

| Model | What it is | Verdict | Why |
|---|---|---|---|
| **1. Workspace-only (roots + import ownership)** | declare member roots; enforce which root owns which module namespace; no "package" | **WINNER (fused with 5)** | smallest; compiler-native; closes the only real gap (phantom imports); no borrowed concepts |
| **2. Source-only package** | a named unit of `.ig`/dialect source, no generated/compiled | **runner-up / merges into 1** | fine, but "package" name + identity is premature; it IS just an owned root with a name |
| **3. Dual/triple package (source+generated+compiled)** | also ship generated `.ig`/JSON + `.igapp` | **REJECT for v0** | packaging reproducible (generated) + build-output (`.igapp`) invites drift/staleness — then a lockfile must police it = self-inflicted problem |
| **4. Lockfile-first (reproducibility ledger)** | start as a content-addressed lock | **REJECT for v0 (strongest temptation)** | local-path + deterministic lowering + existing `source_hash` = no reproducibility *gap* yet; introduces `version`/SemVer thinking prematurely |
| **5. Import-ownership-first** | start by preventing namespace/phantom imports | **WINNER (== 1's mechanism)** | this is THE first real problem; it's the *reason* model 1 exists |
| **6. Capsule/ServiceRecipe package** | package deployable service artifacts | **REJECT for v0** | conflates "author/share source" with "ship a signed deployable"; the machine already owns `ServiceRecipe`/`.igapp`; crosses the human live-gate; not an authoring concern |

**Fusion:** Models 1 and 5 are the same proposal seen from two angles — *declare members* (1) and
*enforce ownership of imports* (5). That fusion is the v0.

## 4. What Gemini got right

- **Local-first before a registry** — correct; matches the lived crate-path model.
- **No install scripts / no hidden hooks** — the most important anti-pattern; Igniter is already clean.
- **Capabilities declared, host binds credentials** — already true in the machine.
- **Projection dialects as pure lowering inputs; never runtime authority** — consistent with P0.
- **Content-addressing over mutable tags; registry + version-solving deferred** — sound.
- **Recommended next card = a workspace resolver** — we *converge* here (see §9), via a different route.

## 5. What Gemini got wrong / overfit

1. **Front-loaded lock/provenance as a co-equal v0 pillar.** Lock/provenance answers a problem Igniter
   does not yet have: with local, owned, deterministically-built sources (+ existing `source_hash`),
   there is no reproducibility *gap* to close. It's anxiety imported from npm/PyPI supply chains. **Defer
   the lockfile harder** — until a remote or mutable input exists. (My P2 validation marked signal-3
   REVISE; this thesis goes further: lock is **not** a v0 pillar at all.)
2. **Adopted "package" as the framing too early.** "Package" drags identity, versions, provenance,
   distribution. The live gap is narrower: *import ownership*. Naming it a package manager invites the
   whole ecosystem apparatus before it's needed; call it a **workspace / module-namespace owner**.
3. **Packaged generated + compiled artifacts (dual/triple model).** Generated output is reproducible
   (regenerate on demand); `.igapp` is build output. Shipping them in a package creates the staleness a
   lockfile then has to police — a self-inflicted loop. Generated-committed is at most a per-project
   diff-review convenience, never a package requirement.
4. **Missed the existing digest substrate** (`source_hash`/`blake3`) — restated from P2; the lock, when
   it comes, must reuse it, not choose a new algorithm.
5. **Two next cards (resolver + lockfile).** The honest first slice is the resolver **alone**; the
   lockfile is contingent on remote/mutable inputs that don't exist yet.

## 6. Strongest proposed v0 (rationale)

**An import-ownership workspace — NOT a package manager.**
- `igniter.toml` gains a minimal member/dependency declaration (e.g. `[dependencies] name = { path }`,
  built on the existing `source_roots`/`compile_units` path).
- Each declared member **owns a module namespace**; the compiler **rejects an import of a module not
  owned by a declared dependency** (phantom-import guard), reusing the closure it already computes +
  `OOF-IMP4` for duplicates.
- **No lockfile, no versions, no registry, no generated/compiled packaging, no install hooks, no new
  external dependency.**

Rationale: it closes the single real, compiler-native gap; it's the smallest change to `project.rs`;
it adds *zero* borrowed ecosystem machinery; and it's reversible/extensible (a lockfile or registry can
layer on later **only when** remote/mutable inputs make reproducibility a real problem).

## 7. Strongest rejected v0 (rationale)

**Lockfile-first (model 4).** It's the most tempting because every mature ecosystem *leads* with a lock,
and "reproducibility" sounds foundational. Rejected because Igniter's v0 inputs are **local, owned, and
deterministically lowered**, and the compiler **already hashes sources** — so there is no
reproducibility gap a lockfile would close. A v0 lockfile would be ceremony policing a non-problem,
and it would smuggle in `version`/SemVer semantics that the roadmap explicitly defers. (Runner-up
rejection: model 6 capsule/ServiceRecipe packaging — a deploy concern the machine already owns, gated
behind the human live-gate, not an authoring primitive.)

## 8. Risk ledger

1. **Over-strict ownership breaks existing apps.** Enforcement must preserve single-root `source_roots`
   projects, `stdlib.*` resolution, and intra-project imports unchanged (back-compat or it's a regression).
2. **Ownership rule under-specified.** Mapping member→module-prefix needs a concrete rule; too loose →
   ownership is advisory (phantom imports survive); too strict → forces a naming convention Igniter
   lacks. Pick "a module is importable iff its owning member is a declared dependency," not a prefix mandate.
3. **Deferring the lockfile risks future silent drift.** Mitigation gate: the *moment* a remote/mutable
   dependency is introduced, the lockfile becomes mandatory — don't ship remote deps without it.
4. **No committed generated artifacts loses diff-review/audit.** Deterministic regeneration covers
   correctness, but reviewers lose the generated diff; leave committing as a per-project choice.
5. **Cross-member cycles / dup modules.** `OOF-IMP4` covers duplicate modules; cross-member import
   cycles need an explicit check the resolver must add.
6. **Roadmap fork.** Two package threads (Gemini-validated + this independent) could diverge; both must
   **converge on the same first card** (§9), differing only in framing/ordering — or the lab ends up
   with two competing package designs.
7. **Anchoring (mine).** I read Gemini before this; the divergences here (lock-not-a-pillar,
   not-"package", don't-package-generated) are the parts I'd most want a third reviewer to stress-test.

## 9. Next-card recommendations

**Converge with the validation's recommendation, but reframe and reorder.** One card:

**`LAB-IGNITER-PACKAGE-WORKSPACE-RESOLVER-P3`** — implement the **import-ownership workspace** on
`project.rs`: declare member/dependency roots in `igniter.toml`; fold them into the compile set;
**enforce import ownership** (a module is importable only if its owning member is a declared dependency)
+ duplicate-module/`OOF-IMP4`; **no lockfile, no versions, no registry, no generated/compiled packaging,
no install hooks**. *Acceptance sketch:* a 2-member workspace compiles clean; a phantom import (module
whose member is undeclared) is rejected with a structured diagnostic; a duplicate module across members
→ `OOF-IMP4`; existing single-root projects unchanged; no new external dependency.

**Explicitly deferred to contingent later cards** (NOT v0): `LAB-IGNITER-LOCKFILE-*` — open **only** when
a remote/mutable input exists, reusing `source_hash`, no `version` in the local era. Registry,
version-solving (SAT/MVS), capsule/ServiceRecipe packaging, generated-artifact committing — all later.

**Naming recommendation:** call the v0 concept a **workspace member / module-namespace owner**, not a
"package," until a registry forces the word. This keeps the apparatus out until it's earned.

---

*Independent research only. Compiled 2026-06-18 from the live `project.rs`/`igweb.rs`/`igniter-web`/
`igniter-server`/`igniter-machine` surfaces + Projection Dialects P0, then compared against Gemini Round 1.
Thesis: import ownership first; "package"/lockfile/distribution later. Converges with the validation on
the first card, diverges on framing + roadmap.*
