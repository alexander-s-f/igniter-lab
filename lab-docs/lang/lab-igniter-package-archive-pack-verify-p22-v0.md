# lab-igniter-package-archive-pack-verify-p22-v0 — `.igpkg` pack + verify

**Card:** `LAB-IGNITER-PACKAGE-ARCHIVE-PACK-VERIFY-P22` · **Delegation:** `OPUS-IGNITER-PACKAGE-ARCHIVE-PACK-VERIFY-P22`
**Status:** CLOSED (lab implementation-proof) — `igc package pack` + `igc package verify` produce and check a
portable, content-addressed **source** `.igpkg`. Deterministic, source-only (forbidden-by-allowlist), verified
by reusing the proven content digest + `verify --strict` engine. **`project.rs` + `main.rs` + tests — no new
crate, no compression, no registry/signing/install-hooks, no compiled/generated/binary content.**

## What changed (`project.rs` + `main.rs`)

- **`pub fn pack_archive(root) -> Result<(Vec<u8>, Value), ProjectError>`** — assemble the graph (`OOF-IMP9` →
  Err); collect the allowlisted files across **all reachable packages** (`igniter.toml`, `*.ig`, `*.igweb`) +
  the root `igniter.lock`; re-root at the **common ancestor** of all package roots (archive paths are
  forward-only); whole-tree `sha256` digest (sorted `archive_path \0 bytes \0`, the `dependency_digest`
  scheme) + per-file digest in `files.json`; emit a hand-rolled deterministic container.
- **`pub fn verify_archive(path) -> Result<Value, ProjectError>`** — parse → recompute per-file + whole-tree
  digests vs the manifest → unpack to a temp dir → `check_workspace_integrity(temp/<entry>)` → clean up.
- **`main.rs`**: `igc package pack --project-root <dir> --out <file>` and `igc package verify <file>` under the
  existing `package` dispatch (alongside `graph`).

## Container & manifest (live)

```
IGPKG\n                       # magic
v0\n                          # version
{ "manifest": {...}, "files": [{path,size,sha256}, …] }\n   # one-line header
<concatenated file bytes, in sorted files order>            # binary blob (no compression, no mtimes/perms)
```
```json
"manifest": {
  "format": "igniter.package.archive.v0", "kind": "source-package", "name": "app",
  "compiler_version": "0.1.0", "stdlib_version": "0.1.x",
  "entry": "app", "lockfile": "igniter.lock",
  "digest": "sha256:…",                                     // whole-tree content digest
  "closed_surfaces": ["no_install_hooks","no_secrets","no_capability_grants"],
  "signature": null                                         // reserved slot, unimplemented
}
"files": ["app/igniter.lock","app/igniter.toml","app/src/main.ig",
          "leaf/igniter.toml","leaf/src/public.ig","mid/igniter.toml","mid/src/public.ig"]
```
All reachable packages are re-rooted at the common ancestor (here the workspace dir); `entry` points at the
root package (`app`). `igniter.toml` + `igniter.lock` are files in the set → manifest-in-digest +
lock-in-digest fall out for free. The digest is over the **logical tree** (sorted path + bytes), independent
of container encoding → location- and machine-independent.

## Determinism & trust

- **Deterministic:** sorted entries, no mtimes/permissions stored, no compression → byte-identical archive
  across runs (proven: `cli_pack_is_deterministic`).
- **Content addressing decides trust:** `name`/version are metadata; the `digest` is the anchor. `signature`
  is a reserved manifest slot, explicitly unimplemented (no signing in this card).
- **Forbidden by construction:** `pack` includes only the source/metadata allowlist (`igniter.toml`, `*.ig`,
  `*.igweb`, root `igniter.lock`). A stray `secret.env` / `app.igapp` / `build.sh` is **not** packed (proven:
  `cli_pack_allowlist_excludes_nonsource`) — a denylist would leak; an allowlist is closed.

## `verify` reuses existing truth

```text
igc package verify file.igpkg
  parse → recompute each files[].sha256 + the whole-tree digest (≠ manifest.digest ⇒ digest_ok:false)
        → unpack to a temp dir → check_workspace_integrity(temp/<entry>)   (OOF-IMP4/6/7/8/9 — verify --strict engine)
        → ok = digest_ok && integrity.ok ; exit 0 clean / exit 1 otherwise
```
No new verification logic. Live: a one-byte flip → `digest_ok:false`, exit 1; a phantom-import archive →
`integrity.diagnostic.rule = OOF-IMP6`, exit 1.

## Live behavior (smoke)

| Action | Result |
|---|---|
| `pack workspace_transitive_ok` | `{ok:true, digest:sha256:…, entry:"app", files:7}` (incl. lock); deterministic |
| `verify` of that archive | `{ok:true, digest_ok:true, integrity.ok:true}`, exit 0 |
| flip one byte → `verify` | `{ok:false, digest_ok:false}`, exit 1 |
| `pack workspace_phantom` then `verify` | pack exit 0; verify `integrity.diagnostic.rule:OOF-IMP6`, exit 1 |
| `pack workspace_missing_root_dep` | `{ok:false, error.rule:OOF-IMP9}`, exit 1, no archive written |
| stray secret/`.igapp`/`.sh` in tree | not present in the archive bytes |

## Tests & commands — exact counts

```text
$ cd lang/igniter-compiler && cargo test --test package_lockfile_cli_tests   → 37 passed (31 + 6 NEW P22)
$ cd lang/igniter-compiler && cargo test --test package_workspace_tests      → green (P1–P20 intact)
$ cd lang/igniter-compiler && cargo test                                     → full suite green (0 failed)
$ git diff --check                                                           → clean
```

New P22 tests (6): `cli_pack_then_verify_clean`, `cli_pack_is_deterministic`,
`cli_verify_detects_tampered_archive`, `cli_verify_detects_integrity_fault` (OOF-IMP6),
`cli_pack_missing_dep_errors` (OOF-IMP9), `cli_pack_allowlist_excludes_nonsource`.

## Acceptance — mapping

- [x] `pack` produces a source-only `.igpkg` over the full reachable graph; allowlist enforced.
- [x] Deterministic (byte-identical archive); `manifest.digest` = whole-tree content digest.
- [x] `verify` clean → exit 0; tamper → digest mismatch exit 1; tree fault → integrity error exit 1.
- [x] `pack` on a missing dependency → structured `OOF-IMP9`, exit 1.
- [x] No generated/compiled/secret/binary content; no new crate; content-addressed trust.
- [x] Existing P1–P20 package tests green; full `igniter-compiler` suite green; `git diff --check` clean.

## Files changed

- `lang/igniter-compiler/src/project.rs` (`pack_archive`/`verify_archive` + `parse_archive`,
  `collect_archive_files`, `is_archive_file`, `common_ancestor`).
- `lang/igniter-compiler/src/main.rs` (`package pack`/`verify` dispatch + handlers).
- `lang/igniter-compiler/tests/package_lockfile_cli_tests.rs` (+6 P22 tests).

## Deferred (explicit)

- `igc package unpack --to <dir>` (verify already unpacks to temp); a local cache (registry-era).
- Generated/compiled inclusion; `.igbundle` deploy bundle (home-lab); **signing** (reserved manifest slot);
  registry/remote/publish/solver.
- `tar`-based container (only if external tooling interop demands it).

## Next

`.igbundle` is home-lab/deploy (`LAB-HOMELAB-IGNITER-RELEASE-BUNDLE-P14` pressure); the registry/solver wave;
or optional `igc package unpack` / `explain-import`. The local package model now also has a **portable,
offline-verifiable distribution artifact**.

---

*Lab implementation-proof. Compiled 2026-06-21; `package_lockfile_cli_tests` 37 green, full `igniter-compiler`
suite green, `git diff --check` clean. `igc package pack`/`verify` produce a deterministic, content-addressed,
source-only `.igpkg`, verified offline by recomputing the tree digest + running the `verify --strict` integrity
engine — no registry, no signing, no install hooks, no binary authority.*
