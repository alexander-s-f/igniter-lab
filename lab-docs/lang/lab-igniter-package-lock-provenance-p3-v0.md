# lab-igniter-package-lock-provenance-p3-v0 — per-workspace dependency lock + drift detection

**Card:** `LAB-IGNITER-PACKAGE-LOCK-PROVENANCE-P3` · **Delegation:** `OPUS-IGNITER-PACKAGE-LOCK-PROVENANCE-P3`
**Status:** CLOSED (lab implementation-proof) — a workspace can be **locked**: each local path dependency
(P2) gets a deterministic **sha256 content digest** (two-layer identity: human name + digest), and
**`verify_lock`** reports drift (changed / new / missing) for reproducible, offline rebuilds. **`project.rs`
+ tests only — no registry, no version solver, no install hooks, no CLI, no server/web/machine change, no new
crate dependency.**

## Verify-first delta vs P1 (live wins)

P1 recommended **blake3** for the lock digest. **Live compiler hashing uses sha256** — `main.rs:242`
(`sha256:{:x}` via `sha2 = "0.10"`), `multifile.rs` `composite_source_hash`/`sha256`, all `sha256:`-prefixed.
For **consistency within the compiler crate**, the lock uses **sha256** (the established source-hash
convention), reusing the already-present `sha2` dep. (blake3 is used machine-side for effect receipts;
unifying the two algorithms is a separate, deliberate concern — not done here.)

## What changed (`project.rs` only)

1. **Dependencies carry a name (P1 two-layer identity).** P2's `dependencies: Vec<PathBuf>` →
   `Vec<Dependency { name, path }>`; `parse_dependencies_toml` now returns `(name, path)`; `load` +
   `build_module_index` updated. Resolver behavior is unchanged (still scans `dep.path`).
2. **Lock types + functions:**
   - `WorkspaceLock { dependencies: Vec<LockedDependency { name, path, digest }> }` with deterministic
     `to_value`/`from_value` (JSON, name-sorted, stable fields).
   - `workspace_lock(root) -> Result<WorkspaceLock, ProjectError>` — one **sha256** digest per declared
     dependency, deps name-sorted.
   - `verify_lock(root, &lock) -> Vec<LockDrift>` — `Changed` (digest differs) / `New` (on disk, not in
     lock) / `Missing` (in lock, not on disk); empty = reproducible.
   - `dependency_digest(dep_root)` — sha256 over the dependency's **sorted** source files, each contributing
     its **relative** path (location-independent) + raw content.

## Design properties (proven)

- **Deterministic:** same workspace → byte-equal lock (name-sorted deps, sorted files, stable JSON).
- **Two-layer identity:** every entry is `{ name (DX), path, digest (reproducibility anchor) }`.
- **Content-addressed:** the digest tracks **content** — two deps both named `lib` but with different
  source produce different digests (test `digest_is_content_addressed`).
- **Location-independent:** the digest hashes **relative** paths + content, so moving a package on disk
  (same content) keeps the digest stable.
- **Direct-only (P2 carry-over):** a dependency's own `[dependencies]` are not digested (no transitive
  package graph).

## Tests & commands — exact counts

```text
$ cd lang/igniter-compiler && cargo test --test package_workspace_tests
  → 12 passed; 0 failed   (6 P2 resolver + 6 NEW P3 lock)
$ cd lang/igniter-compiler && cargo test --test project_mode_tests     → 9 passed (resolver path intact after Dependency refactor)
$ cd lang/igniter-compiler && cargo test --test project_overlay_tests  → 10 passed
$ cd lang/igniter-compiler && cargo test                               → full suite green (57 lib + all bins, 0 failed)
$ git diff --check                                                     → clean
```

New P3 lock tests (6): `lock_is_deterministic_and_pins_each_dependency`, `clean_verify_has_no_drift`,
`tampered_digest_is_changed_drift`, `digest_is_content_addressed`, `no_dependencies_empty_lock`,
`lock_json_roundtrips`.

## Acceptance — mapping

- [x] `workspace_lock` deterministic; per-dependency **sha256** digest (rel-path + content).
- [x] Two-layer identity: name + digest in each lock entry.
- [x] `verify_lock` reports `Changed`/`Missing`/`New`; clean lock = empty.
- [x] sha256 used (verify-first delta vs P1's blake3, documented).
- [x] No registry/solver/hooks/CLI; per-workspace lock.
- [x] `igniter-compiler` full suite green (P2 resolver intact); no server/web/machine change; no new crate.
- [x] `git diff --check` clean.

## Files changed

- `lang/igniter-compiler/src/project.rs` (`Dependency{name,path}`; lock types + `workspace_lock`/
  `verify_lock`/`dependency_digest`; `sha2` import).
- `lang/igniter-compiler/tests/package_workspace_tests.rs` (+6 lock tests, reusing the P2 fixtures).

## Deferred (explicit)

- A persisted **lockfile artifact** (`igniter.lock` on disk) + a **CLI** (`igniter lock` / `igniter
  verify`) — the function API is the v0 substrate; file/CLI wiring is a later DX slice.
- **compiler / stdlib / lowerer-version** lock fields (digest-only v0).
- **blake3 unification** between compiler (sha256) and machine (blake3) digests.
- Strict **direct-dep-only import enforcement**, transitive package graph, registry, version solver.

## Next

1. `LAB-IGNITER-PACKAGE-LOCKFILE-CLI-P4` — persist `igniter.lock` + `igniter lock`/`verify` commands over
   the `workspace_lock`/`verify_lock` API.
2. Then: version-field lock provenance (compiler/stdlib/lowerer), strict import scoping, and — much later —
   registry/solver.

---

*Lab implementation-proof. Compiled 2026-06-21; `package_workspace_tests` 12 green (6 resolver + 6 lock),
`project_mode`/`project_overlay` intact, full `igniter-compiler` suite green, `git diff --check` clean. A
workspace's local path dependencies are now content-addressed (sha256, two-layer identity) with drift
detection — the smallest deterministic lock, no registry/solver/hooks/CLI.*
