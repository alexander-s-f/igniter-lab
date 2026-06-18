# lab-igniter-package-round1-opus-validation-p2-v0 — Opus validation of Gemini package round 1

**Card:** `LAB-IGNITER-PACKAGE-ROUND1-OPUS-VALIDATION-P2` · **Delegation:** `OPUS-PACKAGES-VALIDATION-A`
**Status:** VALIDATION (lab). Verifies Gemini's round-1 package-manager research against live Igniter
surfaces + primary-source ecosystem facts. **No code, no package spec, no lockfile authority, no
registry, no canon.**

## 1. Executive verdict

**The round-1 direction is sound and ACCEPTED with one REVISE.** A **local-first, workspace-driven,
content-addressed, no-install-script** package model fits Igniter's live shape better than a
registry-first manager. Of the 7 strong signals: **6 ACCEPT (1, 2, 4, 5, 6, 7), 1 REVISE (3 —
lockfile)**, 0 REJECT. The revise is timing/grounding: the lockfile is correctly deferred, and when
built it should **reuse the compiler's existing `source_hash` mechanism** rather than invent a digest,
and **drop the `version` field** in a path-only v0 (versions/tags are premature where there is no
version resolution). Recommended next slice: **exactly one** card —
`LAB-IGNITER-PACKAGE-WORKSPACE-RESOLVER-P3` (local path dependencies + module-ownership validation over
the existing `project.rs` resolver). Lockfile/provenance follows separately.

## 2. Evidence sources checked

- **Gemini round 1:** the curated `lab-igniter-package-manager-research-round1-v0.md` + the synthesis
  `lab-igniter-package-research-synthesis-gemini-p1-v0.md` (the 5 shards are summarized into both; read
  the curation + synthesis as the authoritative round-1 statements).
- **Projection-dialects contract:** `lab-igniter-projection-dialects-p0-v0.md` (authored by this lineage).
- **External ecosystem facts:** validated against established primary-source documentation knowledge
  (Cargo/Go/npm-pnpm/PyPI/Deno-JSR/RubyGems-Bundler/OCI/WASM-WIT/Terraform), **not freshly web-fetched
  this session** — version-sensitive claims are flagged in §4.

## 3. Live Igniter surface check (verified this session / prior cards)

| Surface | Finding (relevant to packages) |
|---|---|
| `igniter-compiler/src/project.rs` | `igniter.toml` has only `source_roots = [...]` (default `["."]`); modules indexed by PARSING each file's `module` decl (never directory inference); `resolve_entry` builds the transitive **non-stdlib import closure** → `multifile::compile_units`; `stdlib.*` reserved/resolved from inventory; IDE **overlay** support (P2). Diagnostics: `OOF-IMP4` (duplicate module), `OOF-IMP2` (missing import), `OOF-PROJ-ENTRY`. **No `[dependencies]`, no path-deps, no lockfile.** |
| `igniter-compiler/src/main.rs` + emitter | the compiler **already emits a content-addressed `source_hash` (`sha256:…`)** for a compiled artifact (seen in `igniter-apps/web_router/PRESSURE_REGISTRY.md` baseline). A digest/content-addressing mechanism **exists today**. |
| `igniter-compiler/src/igweb.rs`, `igniter-ui-kit/src/igv.rs` | Projection Dialects: deterministic lowering (`lower_igweb`/`lower_igv`), generated output inspectable; never runtime authority (P0). |
| `igniter-web/src/lib.rs` | `build_igweb_app`: lower → `IgniterMachine::load_program` → erased `ServerApp`. **No install hooks**; lowering + load are pure compiler/machine passes. Generated `.ig` written to a build dir, inspectable. |
| `igniter-server/src/protocol.rs` | app decisions carry **no** `capability_id`/`operation`/`scope` (proven P2–P12) — capabilities are declared, never credentialed, in the app surface. |
| `igniter-machine` (`coordination`/`ingress`) | `ServiceRecipe.capability_bindings` + `required_scopes` are **declarations**; passports, secrets, `EffectBridgeConfig` are **host-owned**; machine uses **blake3** digests internally. |
| crate layout | the repo is **standalone sibling crates with `path = "../x"` deps** (no Cargo workspace root) — i.e. a local-path dependency model is already the lived Rust-level pattern. |

**Live code corroborates** signals 2, 4, 5, 6, 7 directly, partially corroborates 1 and 3 (a digest
mechanism exists), and shows that signal-3's lockfile + signal's `[dependencies]` path-deps are **new
surfaces** (not yet in `project.rs`).

## 4. Ecosystem claim validation

(Verified = established/stable primary-source fact; ⚠ = version-sensitive, confirm before authority.)

| Claim (round 1) | Verdict | Note |
|---|---|---|
| Cargo `build.rs` runs arbitrary code at build; `Cargo.lock` pins transitive closure + checksums; workspaces | **Verified** | core, stable |
| Go modules: MVS, `go.sum` hashes, no lockfile-solver, no build hooks, import path = repo URL | **Verified** | MVS is simpler than SAT (true) |
| npm: `postinstall`/lifecycle scripts = supply-chain risk; `package-lock.json` pins + integrity; npm provenance (Sigstore/OIDC) | **Verified** | npm itself does **not** ban scripts — the *lesson* (Igniter should) is the point, not that npm bans |
| pnpm content-addressed store; restricts lifecycle scripts of non-allowlisted deps by default | **⚠ version-sensitive** | the default-blocking behavior is recent (pnpm ~v9–10); confirm exact version before citing as authority |
| Python: PEP 517 backends / `setup.py` run code; `poetry.lock`/`uv.lock`; PyPI Trusted Publishers (OIDC) | **Verified** | |
| Deno/JSR: no install scripts, permission sandbox, `deno.lock`, scoped names, provenance | **Verified** | strongest "no-hooks + sandbox" precedent |
| RubyGems: native ext (`extconf.rb`) compiles at install; Bundler `Gemfile.lock` + local `path:` overrides | **Verified** | local-path override ergonomics = the cited DX win |
| OCI: content-addressed `sha256` digests; tag mutability risk; provenance in sidecars | **Verified** | |
| WASM component model + WIT interface-first; verify imports/exports before load | **Verified** | maps to Igniter's `ServiceRecipe.entry_contract` + import-closure checks |
| Terraform: providers run binaries; `.terraform.lock.hcl` checksums | **Verified** | |

No ecosystem claim is false; the only correction is framing ("ban install scripts" is the *lesson*, not
that npm bans them) + one ⚠ (pnpm default).

## 5. Design-signal verdict table

| # | Signal | Verdict | Basis |
|---|---|---|---|
| 1 | Two-layered identity (human name + digest anchor) | **ACCEPT** | digest mechanism exists (`source_hash`); names+paths are the lived crate model. v0 needs **no version layer**. |
| 2 | Distinguish source / projection-source / generated / compiled | **ACCEPT** | exactly the live taxonomy: `.ig` / `.igweb`+`.igv` / generated `.ig`+JSON / `.igapp`; governed by Projection Dialects P0. |
| 3 | Lockfile pins content + compiler + stdlib + lowerer + generated hashes | **REVISE** | goal is right (prevents compilation drift), but **deferred** per round 1; when built: **reuse the existing `source_hash`**, **drop `version`** in path-only v0, keep engine-pinning. |
| 4 | Install scripts absent in v0 | **ACCEPT** | strongly grounded — **no install hooks exist anywhere**; lowering (`lower_igweb`/`lower_igv`) + `load_program` are pure compiler/machine passes. |
| 5 | Capabilities are declarations, not credentials | **ACCEPT** | `ServiceRecipe.capability_bindings`/`required_scopes` = declarations; passports/secrets/`EffectBridgeConfig` host-owned; app decisions carry no effect identity (P2–P12). |
| 6 | Registry is later | **ACCEPT** | no registry exists; local path-deps already the pattern. |
| 7 | Version solving later; no SAT/MVS in v0 | **ACCEPT** | no version surface exists; path-only resolution is the honest v0. |

Sub-decision (open Q1, generated committed vs cache): **NEEDS MORE EVIDENCE** — because lowering is
**deterministic** (P4/P10/`.igv`), committing generated output is **optional**, not required; a build
cache + on-demand inspectable generation is viable. Decide in the lockfile slice, not now.

## 6. Gemini mistakes / overstatements (≥3)

1. **Missed the existing digest mechanism.** The compiler already emits a content-addressed
   `source_hash` (`sha256`), and the machine uses `blake3`. The lockfile's `source_hash`/`generated_hash`
   should **reuse the compiler's existing artifact hash**, not introduce a parallel scheme; the
   "digest algorithm not yet chosen" open question understates that a mechanism is already in use.
2. **Overstated readiness of `[dependencies]` path-deps.** `project.rs` today has only `source_roots`;
   the synthesis's `[dependencies] x = { path = "..." }` is a **new config surface**, not current
   behavior. The resolver slice must ADD dependency-root resolution + ownership validation on top of
   the existing `compile_units`/`OOF-IMP4` path.
3. **Premature versions.** `igniter.lock`'s `version = "0.1.0"` + "version tags are mutable aliases used
   during resolution" inject SemVer thinking into a v0 that has **no version resolution** (path-only).
   This re-imports the exact concept signal 7 defers; v0 should pin **paths + content digests only**.
4. **Internal inconsistency on generated-output policy.** The synthesis asserts generated output is
   "committed into `generated/` folders," but the curation reopens it as a question — and since lowering
   is deterministic, committing is optional (cache+source-map suffices). State it as open, not decided.
5. **Two next cards, not one.** The synthesis proposes both a resolver **and** a lockfile card; the
   smallest safe step is the **resolver alone**. (Also a P-number collision: it labeled the resolver
   `…-P2`, which clashes with this validation card — use `…-P3`.)

## 7. Gemini strong insights to keep

- **Local-first workspace resolver before a registry** — matches the lived crate-path model exactly.
- **No install scripts / no hidden hooks** — the single most important anti-pattern (npm/Python/Ruby/
  Terraform), and Igniter is already structurally clean here; keep it a hard rule, not a default.
- **Projection dialects as pure lowering inputs, generated artifacts inspectable** — consistent with P0.
- **Capabilities declared, host binds credentials** — already true in the machine; the package manifest
  should only carry abstract `requires = [...]`, never secrets/endpoints.
- **Content-addressed pinning over mutable tags** — correct lesson from OCI/Go/VCS.
- **Direct-dependency import enforcement (no phantom transitive imports)** — a real, valuable rule;
  `project.rs` already resolves the import closure, so ownership-checking is a natural extension.

## 8. Recommended next implementation card (exactly one)

**`LAB-IGNITER-PACKAGE-WORKSPACE-RESOLVER-P3`** — local path dependencies + module-ownership validation,
built directly on `project.rs`.

*Scope:* extend `ProjectConfig`/`igniter.toml` with a tiny `[dependencies] name = { path = "..." }`
block (hand-parsed, mirroring `parse_source_roots_toml`); fold each dependency's source root into the
compile set alongside `source_roots`; keep module indexing + the existing `compile_units` pipeline;
enforce **duplicate-module ownership** (reuse `OOF-IMP4`) and optionally a **declared-vs-owned** check
(a module importable only if its owning package is a declared dependency).

*Acceptance sketch:* a 2-package workspace fixture compiles clean through project mode; a duplicate
module across packages fails with `OOF-IMP4`; a missing dependency path is a structured error; **no
lockfile, no registry, no version solver, no install hooks, no new external dependency**; existing
`project.rs` tests stay green.

**Lockfile/provenance is a SEPARATE later card** (`LAB-IGNITER-LOCKFILE-SKETCH-P*`), opened only after
the resolver shape is grounded — and it must reuse the existing `source_hash` and drop `version` for the
path-only era.

## 9. Deferred surfaces

Lockfile/provenance format; remote registry + transport + credentials; version solving (SAT **and**
MVS); dynamic code loading; the generated-committed-vs-build-cache decision; the capability-manifest
field schema (declare-only); digest-algorithm canonicalization (reuse existing `source_hash`/`blake3`
rather than choose anew). Install scripts are **forbidden**, not deferred.

---

*Validation only. Compiled 2026-06-18 against the curated round-1 + synthesis and the live `project.rs`/
`igweb.rs`/`igniter-web`/`igniter-server`/`igniter-machine` surfaces. No code; one next card recommended.*
