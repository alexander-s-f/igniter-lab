# LAB-IGNITER-PACKAGE-ARCHIVE-PACK-VERIFY-P22 — `.igpkg` pack + verify

Status: CLOSED
Lane: standard / package distribution
Type: implementation proof
Delegation code: OPUS-IGNITER-PACKAGE-ARCHIVE-PACK-VERIFY-P22
Date: 2026-06-21
Skill: idd-agent-protocol

## Context

Depends on `LAB-IGNITER-PACKAGE-ARCHIVE-READINESS-P21` (GO: small source-only `.igpkg`, pack + verify, thin
deterministic wrapper over the proven content digest + full-graph lock + `verify --strict` engine).

## Goal

Implement `igc package pack` + `igc package verify` for a portable, content-addressed `.igpkg` **source**
package — no registry, no signing, no install hooks, no compiled/generated/binary content.

## Required implementation (`project.rs` + `main.rs`, no new crate)

1. `pub fn pack_archive(root) -> Result<(Vec<u8>, Value), ProjectError>`:
   - assemble the graph (`OOF-IMP9` → Err); collect the allowlisted file set across **all reachable
     packages** (each package's `igniter.toml`, `*.ig`, `*.igweb`) + the root `igniter.lock` (if present);
   - re-root at the **common ancestor** of all package roots (so archive paths are forward-only, no `..`);
   - whole-tree content digest (`sha256` over sorted `archive_path \0 bytes \0`, reusing the
     `dependency_digest` scheme); per-file `sha256` in `files.json`;
   - hand-rolled deterministic container: `IGPKG\n` + `v0\n` + a one-line `{manifest, files}` header + the
     concatenated file bytes (in sorted `files` order). No compression, no mtimes/perms.
2. `pub fn verify_archive(path) -> Result<Value, ProjectError>`: parse → recompute per-file + whole-tree
   digest (mismatch → `ok:false`) → unpack to a temp dir → `check_workspace_integrity(temp/<entry>)` → clean
   up. Malformed archive → Err.
3. `main.rs` under the `package` dispatch: `igc package pack --project-root <dir> --out <file>` and
   `igc package verify <file>`.

## Constraints (closed scope, from P21)

- Source + metadata **allowlist** only (`igniter.toml`, `*.ig`, `*.igweb`, root `igniter.lock`) — no
  generated, no compiled `.igapp`, no secrets/binaries/hooks (forbidden by construction).
- Content addressing decides trust; `name`/version are metadata. `signature` = reserved manifest slot, unimplemented.
- No registry/remote/publish/install/solver; no `unpack` command; no cache; no `.igbundle`.
- No new crate; deterministic (byte-identical archive across runs).

## Required tests / fixtures (reuse existing `project_mode` fixtures)

API + CLI:
- pack `workspace_transitive_ok` → archive contains all reachable packages' `.ig` + `igniter.toml`; no
  generated/compiled/binary.
- pack is **deterministic** (byte-identical across two runs).
- `manifest.digest` = whole-tree digest.
- `verify` on a fresh archive → `ok:true`, exit 0.
- `verify` after flipping one content byte → digest mismatch, exit 1.
- `verify` on an archive whose tree has a scope/export fault → `OOF-IMP6`/`OOF-IMP7` integrity error, exit 1.
- `pack` on `workspace_missing_root_dep` → structured `OOF-IMP9`, exit 1.
- allowlist: a stray `secret.env` / `app.igapp` / `build.sh` in the tree is **not** packed.

## Acceptance

- [x] `pack` produces a source-only `.igpkg` over the full reachable graph; allowlist enforced.
- [x] Deterministic (byte-identical archive); `manifest.digest` = whole-tree content digest.
- [x] `verify` clean → exit 0; tamper → digest mismatch exit 1; tree fault → integrity error exit 1.
- [x] `pack` on a missing dependency → structured `OOF-IMP9`, exit 1.
- [x] No generated/compiled/secret/binary content; no new crate; content-addressed trust.
- [x] Existing P1–P20 package tests green; full `igniter-compiler` suite green; `git diff --check` clean.

## Required deliverable

- Proof doc: `lab-docs/lang/lab-igniter-package-archive-pack-verify-p22-v0.md`
- Closing report in this card.

---

## Closing Report (2026-06-21)

**Implementation (`project.rs` + `main.rs`, no new crate):** `pack_archive(root)` — graph assembly (OOF-IMP9→Err),
allowlisted source/metadata across all reachable packages + root `igniter.lock`, re-rooted at the common
ancestor (forward-only paths), whole-tree sha256 (reusing `dependency_digest`'s scheme) + per-file digest,
hand-rolled deterministic container (`IGPKG\n`+`v0\n`+`{manifest,files}`-line+blob; no compression/mtimes/perms).
`verify_archive(path)` — recompute per-file + tree digest vs manifest, unpack to temp, `check_workspace_integrity`
on `<entry>`. `main.rs` `package pack`/`verify` handlers. Proof doc:
`lab-docs/lang/lab-igniter-package-archive-pack-verify-p22-v0.md`.

**Live smoke (all ✓):** pack transitive_ok → `{ok:true, files:7, digest:sha256:…, entry:"app"}`, deterministic
(byte-identical); verify clean → `ok:true` exit 0; flip one byte → `digest_ok:false` exit 1; pack phantom then
verify → `integrity.rule:OOF-IMP6` exit 1; pack missing-dep → `OOF-IMP9` exit 1, no file written; stray
secret/`.igapp`/`.sh` NOT in archive (allowlist holds).

**Proof — all green:** `package_lockfile_cli_tests` **37** (31 + 6 P22), `package_workspace_tests` intact, full
`igniter-compiler` suite green (0 failed), `git diff --check` clean. Content addressing decides trust; signing =
reserved manifest slot, unimplemented. No registry/install-hooks/binary.

**Deferred:** `igc package unpack`; local cache; generated/compiled inclusion; **`.igbundle`** (home-lab deploy,
LAB-HOMELAB-RELEASE-BUNDLE-P14); signing; registry/remote/publish/solver; tar container. **Next:** registry wave
OR home-lab `.igbundle` OR optional unpack/explain-import.
