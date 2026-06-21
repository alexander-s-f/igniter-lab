# LAB-IGNITER-PACKAGE-ARCHIVE-READINESS-P21 - portable package archive readiness

Status: CLOSED
Lane: standard / package distribution
Type: readiness / design
Delegation code: OPUS-IGNITER-PACKAGE-ARCHIVE-READINESS-P21
Date: 2026-06-21
Skill: idd-agent-protocol

## Context

The package wave has already proven the local trust substrate:

- P1/P2: local-first package direction and workspace path dependencies.
- P3-P5: content digest, lockfile, and toolchain provenance.
- P7/P8: direct-dependency import scoping and `verify --strict`.
- P9-P12: explicit `[exports] modules` and closed export surface.
- P14/P15: transitive local package graph and CI hardening.
- P17-P20: package graph/introspection and import diagnostics/explain readiness.

The next pressure is distribution. The user proposed a RubyGems-like archive:
one portable package artifact that can be copied, cached, verified, and later
served by a registry or home-lab node. This card evaluates that idea only.

Keep the distinction sharp:

- **Workspace resolver** answers local import ownership.
- **Package archive** answers portable distribution and offline verification.
- **Registry / version solver / publishing** remain later layers.

## Goal

Design the first Igniter package archive model: a deterministic, content-addressed
artifact inspired by `.gem`, but without install hooks, hidden runtime authority,
global namespaces, or build-time code execution.

Decide whether the next implementation should be an archive pack/verify command,
or whether the existing workspace/lock layer needs another step first.

## Verify first

Read live docs/code before designing:

- `lab-docs/lang/lab-igniter-package-manager-readiness-p1-v0.md`
- `lab-docs/lang/lab-igniter-package-workspace-resolver-p2-v0.md`
- `lab-docs/lang/lab-igniter-package-lock-provenance-p3-v0.md`
- `lab-docs/lang/lab-igniter-package-lockfile-cli-p4-v0.md`
- `lab-docs/lang/lab-igniter-package-lockfile-frozen-ci-p8-v0.md`
- `lab-docs/lang/lab-igniter-package-module-exports-p10-v0.md`
- `lab-docs/lang/lab-igniter-package-transitive-graph-p14-v0.md`
- `lab-docs/lang/lab-igniter-package-graph-cli-p18-v0.md`
- `lab-docs/lang/lab-igniter-package-research-ruby-rails-gemini-p1-v0.md`
- current `igniter-compiler/src/project.rs`
- current `igniter-compiler/src/main.rs`

Also inspect private home-lab pressure if available, without copying secrets:

- `igniter-home-lab/cards/LAB-HOMELAB-IGNITER-RELEASE-BUNDLE-P14.md`
- `igniter-home-lab/deploy/igniter-stack-deployment-models.md`

## Questions to answer

1. Is a package archive justified now, or should `explain-import`/registry work
   come first?
2. What is the artifact boundary?
   - source/library package only (`.igpkg`);
   - deploy bundle (`.igbundle`);
   - both, with separate semantics?
3. What must be inside the archive?
   - `igniter.toml`;
   - `igniter.lock`;
   - authored `.ig` / projection dialect sources;
   - generated artifacts;
   - compiled `.igapp`;
   - checks;
   - provenance;
   - signatures later.
4. What is explicitly forbidden inside the archive?
   - install hooks;
   - shell scripts that run automatically;
   - host secrets;
   - runtime capability grants;
   - DB migrations with authority;
   - native build products unless in a separate deploy bundle.
5. How should archive determinism be defined?
   - sorted entries;
   - normalized mtimes/permissions;
   - manifest-in-digest;
   - lock-in-digest;
   - compression choice;
   - stable hash output.
6. Should generated `.ig` be included or regenerated?
7. Should compiled `.igapp` be included, or is it a separate deploy artifact?
8. How does `igc verify --strict` apply to an unpacked archive?
9. Should v0 support `pack` only, or `pack` + `verify` + `unpack`?
10. Should a local package cache exist in v0?
11. What is the exact command shape?
    - `igc package pack --project-root <dir> --out <file>`;
    - `igc package verify <file>`;
    - `igc package unpack <file> --to <dir>`;
    - another shape?
12. How does the archive avoid becoming a registry, solver, installer, or
    package-script system?
13. How does this connect to home-lab release bundles and future mesh nodes?

## Bias

Prefer a split model:

- **`.igpkg`**: portable source package/archive. Contains authored sources,
  package manifest, lock/provenance, export metadata, and checksums. No binary
  runner, no auto-start, no host-specific service files.
- **`.igbundle`**: later deploy bundle. May contain a runner binary, app
  directory, checks, wrapper, and systemd/service metadata. This belongs closer
  to home-lab/deploy pressure, not the compiler package core.

Prefer `pack` + `verify` before `unpack/install`.

Prefer content-addressing over names/versions for v0. Versions may be metadata,
but they must not decide trust.

Prefer archive verification that reuses existing truth:

```text
archive manifest -> unpack temp dir -> igc verify --strict -> compare digest
```

Do not add registry, semver solving, remote fetching, install hooks, or signing
in this card. Signing can be specified as a future slot only.

## Seed archive sketch

This is a strawman, not the decision:

```text
example.igpkg
  package/manifest.json
  package/files.json
  igniter.toml
  igniter.lock
  src/**/*.ig
  dialects/**/*.igweb
  generated/              # optional, inspectable, never authoritative
  checks/                 # optional manual checks, never auto-run on install
  provenance/
```

Possible manifest fields:

```json
{
  "format": "igniter.package.archive.v0",
  "name": "todo",
  "kind": "source-package",
  "created_by": "igc",
  "compiler_version": "0.1.0",
  "root_manifest": "igniter.toml",
  "lockfile": "igniter.lock",
  "digest": "sha256:...",
  "entrypoints": [],
  "exports": {},
  "closed_surfaces": [
    "no_install_hooks",
    "no_secrets",
    "no_capability_grants"
  ]
}
```

## Required deliverable

- Readiness packet:
  `lab-docs/lang/lab-igniter-package-archive-readiness-p21-v0.md`
- Closing report in this card.
- Clear recommendation:
  - GO / NO-GO / WAIT;
  - if GO, exact implementation card name and acceptance matrix.
- Explicit relationship to home-lab release bundle P14.

## Acceptance

- [x] Live P1-P20 package surface verified; stale docs do not outrank code.
- [x] RubyGems/Bundler lesson re-read: copy archive ergonomics, reject hooks.
- [x] At least four archive models compared:
      source-only archive, source+generated, source+compiled, deploy bundle.
- [x] `.igpkg` vs `.igbundle` boundary decided or explicitly deferred.
- [x] Deterministic archive rules drafted.
- [x] Manifest/digest relationship drafted.
- [x] `pack` / `verify` / `unpack` command scope recommended.
- [x] Generated and compiled artifact authority clearly stated.
- [x] Registry/solver/signing/install-hook boundaries stated.
- [x] Home-lab release bundle pressure connected without leaking private ops.
- [x] No production code changes.

---

## Closing Report (2026-06-21)

**Deliverable:** `lab-docs/lang/lab-igniter-package-archive-readiness-p21-v0.md` — readiness packet, no
production code (`git diff --check` clean).

**Recommendation: GO (small).** A `.igpkg` is a thin deterministic wrapper over already-proven primitives —
the per-package content digest (`dependency_digest`), the full-graph lock (`workspace_lock`), and the
`verify --strict` engine (`check_workspace_integrity`) — so it is both justified (distribution pressure) and
small (no new rule logic).

**Design:** **`.igpkg`** = portable **source** package (authored `.ig` + `.igweb` dialects + each package's
`igniter.toml` + root `igniter.lock` + manifest + files.json). **Forbidden-by-construction** via a fixed
source/metadata **allowlist** (secrets/binaries/hooks cannot enter). **No** generated (regenerable), **no**
compiled `.igapp` (deploy artifact). Digest = content-addressed over the sorted logical tree (reuses
`dependency_digest`'s scheme), container = hand-rolled deterministic format (**no new crate, no compression**).
`verify` = unpack-temp → digest compare → `check_workspace_integrity`. v0 = **`pack` + `verify`** (unpack/cache
deferred). **`.igbundle`** (runner + service, host/arch) deferred to the home-lab — it IS the CLOSED
`LAB-HOMELAB-IGNITER-RELEASE-BUNDLE-P14` deploy pressure; `.igpkg` (compiler core) feeds it, carrying no host
config/secrets. RubyGems lesson: adopt Bundler path+lockfile, reject install-hooks/engine-globals. Content
addressing — not name/version — decides trust.

**Next:** `LAB-IGNITER-PACKAGE-ARCHIVE-PACK-VERIFY-P22` (impl `pack`+`verify`) — 9-point acceptance matrix in
§10. Registry/solver/signing remain far later; `explain-import-cli` (P20) remains an optional parallel slice.

## Closed scope

- No implementation.
- No archive format canon claim.
- No registry, remote fetch, publish, install, or version solver.
- No signing implementation.
- No install hooks or auto-executed checks.
- No capability grants, secrets, DSNs, migrations, or host config in packages.
- No server/web/machine behavior changes.
