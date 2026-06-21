# lab-igniter-package-archive-readiness-p21-v0 — portable package archive (`.igpkg`)

**Card:** `LAB-IGNITER-PACKAGE-ARCHIVE-READINESS-P21` · **Delegation:** `OPUS-IGNITER-PACKAGE-ARCHIVE-READINESS-P21`
**Status:** READINESS / DESIGN (v0) — designs the first Igniter package archive and recommends **GO** for a
small `.igpkg` source-package with `pack` + `verify`. **No production code. No format canon claim. No
registry/solver/signing/install-hooks.**

---

## 1. Executive summary — **GO (small)**

Distribution is the genuine next pressure, and a **`.igpkg`** is a *thin, deterministic wrapper over already-
proven primitives* (the per-package content digest, the full-graph lock, `verify --strict`). It is therefore
both justified **and** small. Recommendation:

- **`.igpkg`** = a portable, content-addressed **source** package (authored `.ig` + projection dialects +
  each package's `igniter.toml` + the root `igniter.lock` + a manifest + a per-file `files.json`). **No
  runner binary, no compiled `.igapp`, no generated output, no host config, no auto-run.**
- **`pack` + `verify` first** (no `unpack`-install, no cache) — `verify` reuses existing truth: *unpack to a
  temp dir → recompute the content digest → compare to the manifest → run workspace integrity
  (`check_workspace_integrity`, the `verify --strict` engine)*.
- **`.igbundle`** (deploy bundle: runner + service metadata, host/arch-specific) is **deferred to the
  home-lab** — it is exactly the already-CLOSED `LAB-HOMELAB-IGNITER-RELEASE-BUNDLE-P14` pressure (§9), not
  compiler-core.
- **Forbidden by construction**, not by a denylist: `pack` includes only a fixed **allowlist** of source +
  metadata file types, so secrets / binaries / hooks cannot enter.

Recommended next card: **`LAB-IGNITER-PACKAGE-ARCHIVE-PACK-VERIFY-P22`** (§10).

## 2. Verify-first findings (live code/docs > stale)

| Fact | Evidence | Consequence |
|---|---|---|
| No archive concept exists yet in the compiler | `rg igpkg\|archive\|pack` over `src` → none | clean slate; `.igpkg` is new |
| Per-package content digest already exists | `dependency_digest` — sha256 over sorted (rel-path + content), manifest folded (P10) | the archive digest reuses **this exact algorithm**, over the whole package tree |
| Full-graph lock already exists | `workspace_lock` — every reachable package, root-relative paths, toolchain block (P5/P6/P14) | the archive carries `igniter.lock` as-is; lock owns provenance |
| Integrity gate already exists, entry-free | `check_workspace_integrity` (OOF-IMP4/6/7/8/9) — the `verify --strict` engine (P8/P14/P16) | `verify <file>` runs this on the unpacked tree — **no second rule impl** |
| Graph/exports are inspectable | `workspace_graph_value` (P18) | manifest can embed an exports summary without new computation |
| Ruby/Rails research already concluded | `…-research-ruby-rails-gemini-p1-v0.md` | adopt Bundler path+lockfile; **reject** gem install-hooks + Rails engine globals/migrations/boot side-effects |

**RubyGems/Bundler lesson (re-read, §research doc):** *adopt* — local `path:` ergonomics (already P2) +
`Gemfile.lock` strict pinning (already P3/P14). *reject* — "package managers must never compile arbitrary
binaries; native deps belong at the host layer"; "extensions must remain static; never inject migrations or
global routes." → `.igpkg` is **source + metadata only**, zero executable authority. Native/runner = host
layer (`.igbundle`).

## 3. Archive-model comparison (≥4)

| Model | Contents | Verdict |
|---|---|---|
| **A. source-only `.igpkg`** | authored `.ig` + dialects + per-package `igniter.toml` + root `igniter.lock` + manifest + files.json | **SELECTED (v0)** — smallest, fully reproducible (regenerate/compile on the far side), no binary authority |
| B. source + generated | A + `generated/` | rejected v0 — generated is **never authoritative** (regenerable); inflates the artifact + invites drift. Include later only as inspectable, digest-excluded |
| C. source + compiled `.igapp` | A + compiled app | rejected for `.igpkg` — a compiled app is a **deploy** artifact (arch/runtime-bound), belongs in `.igbundle` |
| D. deploy bundle `.igbundle` | runner binary + app dir + checks + service/systemd metadata, host/arch-specific | **deferred to home-lab** (§9) — not compiler-core |

## 4. The `.igpkg` boundary (Q2/Q3/Q4/Q6/Q7)

**Inside (allowlist — forbidden-by-construction):**
- `package/manifest.json` (§6), `package/files.json` (sorted `[{path, size, digest}]`).
- every package's `igniter.toml`; the root `igniter.lock`.
- authored `*.ig`; projection dialect sources (`*.igweb`).

**Explicitly outside:**
- **generated/** (Q6) — regenerated from source on the far side; **not** in v0 (regenerable, non-authoritative).
- **compiled `.igapp`** (Q7) — a deploy artifact → `.igbundle`, not `.igpkg`.
- install hooks, shell/auto-run scripts, host secrets/DSNs, `.env`, runtime capability grants, DB migrations
  with authority, native build products. These can't enter because `pack` includes only the allowlist above
  (a denylist would be a leak waiting to happen; an allowlist is closed by construction).

`manifest.closed_surfaces` *declares* the absences (`no_install_hooks`, `no_secrets`, `no_capability_grants`)
as machine-checkable evidence — but the guarantee comes from the allowlist, not the label.

## 5. Determinism (Q5)

The archive **digest is content-addressed over the logical tree, independent of the container encoding** —
reusing `dependency_digest`'s proven scheme extended to the whole package set:
- collect the allowlisted files; **sort by relative path**;
- digest = `sha256` over, for each file in order, `rel_path \0 file_bytes \0`;
- `files.json` records each file's own `sha256` for inspectability; `manifest.digest` = the whole-tree digest.
- the container stores files in sorted order with **normalized/zeroed mtimes and fixed permissions**; **no
  compression in v0** (compression is a determinism + dependency hazard; the digest is over uncompressed
  content regardless). `igniter.toml` + `igniter.lock` are files in the set → **manifest-in-digest** and
  **lock-in-digest** fall out for free.

**Container, no new crate:** a hand-rolled, inspectable format — `IGPKG\0` magic + version, then the
length-prefixed `files.json`, then each file's raw bytes in `files.json` order. Fully deterministic, no `tar`/
`zip`/compression crate needed. (A `tar`-based container is a later option if tooling interop demands it.)

## 6. Manifest (refined strawman)

```json
{
  "format": "igniter.package.archive.v0",
  "kind": "source-package",
  "name": "todo",
  "compiler_version": "0.1.0",
  "stdlib_version": "0.1.0",
  "root_manifest": "igniter.toml",
  "lockfile": "igniter.lock",
  "digest": "sha256:…",                     // whole-tree content digest (§5)
  "packages": [ { "label": "<root>", "path": ".", "exports": { "mode": "open" } }, … ],  // from workspace_graph_value
  "closed_surfaces": ["no_install_hooks", "no_secrets", "no_capability_grants"],
  "signature": null                          // future slot ONLY — not implemented (closed scope)
}
```
`compiler_version`/`stdlib_version` mirror the lock's toolchain block (provenance, not trust gating — content
addressing decides trust). `signature` is a reserved slot, explicitly unimplemented.

## 7. `verify` reuses existing truth (Q8)

```text
igc package verify example.igpkg
  1. read manifest + files.json
  2. unpack into a temp dir
  3. recompute the whole-tree content digest → must equal manifest.digest (and each files.json per-file digest)
  4. run check_workspace_integrity on the unpacked tree (OOF-IMP4/6/7/8/9 — the verify --strict engine)
  5. (lock parity) optionally recompute workspace_lock and compare to the packed igniter.lock
  exit 0 iff digest matches AND integrity clean; else structured error + exit 1
```
No new verification logic — steps 3–5 are existing primitives. This is the bias's
`archive → unpack → verify --strict → compare digest` flow.

## 8. Command scope (Q9/Q10/Q11) & exit codes

**v0 = `pack` + `verify`** (bias: before `unpack`/install):
- `igc package pack --project-root <dir> --out <file.igpkg>` → deterministic `.igpkg`; exit 1 on assembly
  fault (reuses graph assembly — `OOF-IMP9` etc.).
- `igc package verify <file.igpkg>` → §7; exit 0 clean / exit 1 on digest mismatch or integrity fault
  (structured `{ kind:"igniter_package_verify", ok:false, error }`).
- **`unpack --to <dir>`** (Q9) — **deferred**: `verify` already unpacks to temp; an explicit extract is a thin
  follow-on, low priority.
- **Local cache** (Q10) — **NO** in v0 (a cache is a registry-era concern; no registry yet).

## 9. Relationship to home-lab release bundle P14 (Q13)

`LAB-HOMELAB-IGNITER-RELEASE-BUNDLE-P14` (CLOSED) turns a `mesh-status` IgWeb proof on an ARM64 Pi node into a
**repeatable release bundle** — runner + app dir + service metadata for a specific host/arch. That is the
**`.igbundle` / deploy** layer, owned by the home-lab, not the compiler. The two compose without leaking ops:

```text
.igpkg  (compiler core)         portable SOURCE: copy across the mesh, verify offline (content digest + integrity)
   │  a node receives + verifies an .igpkg
   ▼
.igbundle  (home-lab/deploy)    per-arch DEPLOY: compile + wrap with runner + service files for that host
```
`.igpkg` carries **no** host config, service files, or runner — so it never encodes home-lab secrets/topology.
The home-lab's deploy step consumes a verified `.igpkg` and produces the host-specific `.igbundle`. (No home-lab
secrets, DSNs, or host details are copied here — only the public layering.)

## 10. Proposed implementation card — `LAB-IGNITER-PACKAGE-ARCHIVE-PACK-VERIFY-P22`

**Implementation (`project.rs` + `main.rs`, no new crate):**
- `pub fn pack_archive(root, out) -> Result<Value, ProjectError>` — assemble the graph (fail on OOF-IMP9),
  collect the allowlisted file set across all reachable packages, compute the whole-tree digest, write the
  hand-rolled `.igpkg` container + manifest + files.json; return a summary `Value`.
- `pub fn verify_archive(path) -> Result<Value, ProjectError>` — §7 (unpack temp, digest compare,
  `check_workspace_integrity`).
- `main.rs`: `igc package pack --project-root --out` and `igc package verify <file>` under the existing
  `package` dispatch.

**Acceptance matrix:**
- [ ] `pack` on `workspace_transitive_ok` produces a `.igpkg` containing all reachable packages' `.ig` +
      `igniter.toml` + the root `igniter.lock` + manifest + files.json; **no** generated/compiled/binary.
- [ ] `pack` is **deterministic** — byte-identical archive across runs (sorted, zeroed mtimes/perms, no
      compression).
- [ ] `manifest.digest` = the whole-tree content digest; equals each files.json per-file digest aggregate.
- [ ] `verify` on a freshly packed archive → `ok:true`, exit 0.
- [ ] `verify` after tampering one byte of a packed file → digest mismatch, exit 1.
- [ ] `verify` on an archive whose unpacked tree has a scope/export fault → `OOF-IMP6`/`OOF-IMP7` integrity
      error, exit 1.
- [ ] `pack` on a missing-dependency workspace → structured `OOF-IMP9`, exit 1.
- [ ] Allowlist holds: a stray `secret.env` / `app.igapp` / `build.sh` in the tree is **not** packed.
- [ ] Existing P1–P20 package tests green; full `igniter-compiler` suite green; `git diff --check` clean.

## 11. Boundaries restated (closed scope)

No registry, remote fetch, publish, install, version solver. No signing (reserved manifest slot only). No
install hooks / auto-run checks. No capability grants / secrets / DSNs / migrations / host config in the
archive. No `.igbundle` (home-lab). No server/web/machine change. Content addressing — **not** name/version —
decides trust in v0.

## 12. Acceptance — mapping (this readiness)

- [x] Live P1–P20 package surface verified; code outranked stale docs (§2).
- [x] RubyGems/Bundler lesson re-read: copy archive ergonomics, reject hooks (§2).
- [x] ≥4 archive models compared (§3: source-only / +generated / +compiled / deploy-bundle).
- [x] `.igpkg` vs `.igbundle` boundary decided (§1/§9).
- [x] Deterministic archive rules drafted (§5).
- [x] Manifest/digest relationship drafted (§5/§6).
- [x] `pack`/`verify`/`unpack` scope recommended (§8: pack+verify; unpack deferred).
- [x] Generated/compiled artifact authority stated (§4: excluded, regenerable/deploy).
- [x] Registry/solver/signing/install-hook boundaries stated (§11).
- [x] Home-lab release-bundle pressure connected without leaking ops (§9).
- [x] No production code changes.

---

*Lab readiness packet. Verify-first: `.igpkg` is a thin deterministic wrapper over the proven content digest +
full-graph lock + `verify --strict` engine — justified by distribution pressure and small by construction.
Recommendation: **GO** — source-only `.igpkg`, `pack` + `verify`, hand-rolled deterministic container (no new
crate, no compression), forbidden-by-allowlist; defer `.igbundle` to the home-lab and registry/solver/signing
to later. Next card `…-ARCHIVE-PACK-VERIFY-P22` with a 9-point acceptance matrix.*
