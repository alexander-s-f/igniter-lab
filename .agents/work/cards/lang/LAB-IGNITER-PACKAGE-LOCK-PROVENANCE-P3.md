# LAB-IGNITER-PACKAGE-LOCK-PROVENANCE-P3 — per-workspace dependency lock + drift detection

Status: CLOSED
Lane: standard / lab implementation
Type: implementation-proof
Delegation code: OPUS-IGNITER-PACKAGE-LOCK-PROVENANCE-P3
Date: 2026-06-21
Skill: idd-agent-protocol

## Context

`LAB-IGNITER-PACKAGE-WORKSPACE-RESOLVER-P2` landed local path dependencies (`[dependencies]` in
`igniter.toml`, folded into the project module index, cross-package imports + `OOF-IMP4` reuse). The next
P1-recommended slice is **lock/provenance**: pin each dependency's content digest so a rebuild can detect
drift, reproducibly and offline.

## Verify-first delta (live wins over P1)

P1 recommended **blake3** for the lock digest. **Live compiler hashing uses sha256** (`main.rs:242`
`sha256:{:x}` via `sha2`; `multifile.rs` `composite_source_hash`/`sha256` — all `sha256:`-prefixed). For
**consistency within the compiler crate** the lock uses **sha256** (the established source-hash convention),
not blake3. (blake3 is used machine-side for effect receipts; unifying the two algorithms is a separate
concern, out of scope here.)

## Goal

In `project.rs` only, add a deterministic **per-dependency content digest** and a **per-workspace lock**:
- `workspace_lock(root)` → `WorkspaceLock { dependencies: [{ name, path, digest }] }`, digest = `sha256:` over
  each dependency's **sorted** source set (relative-path + content), location-independent.
- serialize/parse the lock (deterministic JSON), and **`verify_lock(root, &lock)`** → drift list
  (changed digest / missing dep / new dep). Empty = reproducible.
- two-layer identity per P1: human **name** + content **digest**.

## Closed scope

- No registry, network, version solver/ranges, transitive package graph.
- No install/build hooks; no `.igapp` packaging.
- No compiler-version / stdlib-version / lowerer-version lock fields yet (digest-only v0).
- No CLI wiring required (function API + tests; `igniter lock` command is a later DX slice).
- No `igniter-server`/`igniter-web`/`igniter-machine` change; no new crate dependency (reuse `sha2`).
- No canon claim.

## Required implementation (`project.rs`)

1. Give dependencies a **name** (extend P2's `dependencies` to carry `{ name, path }`); update parse/load/
   `build_module_index` accordingly.
2. `pub fn workspace_lock(root) -> Result<WorkspaceLock, ProjectError>` — per-dependency sha256 digest over
   its sorted source files (rel-path + content), deps sorted by name (determinism).
3. `WorkspaceLock::{to_value, from_value}` (deterministic JSON) + `pub fn verify_lock(root, &WorkspaceLock)
   -> Vec<LockDrift>` (changed/missing/new).

## Required tests

1. **deterministic** — `workspace_lock` twice → equal.
2. **pins each dependency** — one `{name,path,sha256-digest}` entry per declared dep.
3. **clean verify** — `verify_lock(root, workspace_lock(root))` → no drift.
4. **drift detected** — verify against a tampered digest → reports the changed dependency.
5. **content-addressed** — two deps with identical content → identical digest; different content → different.
6. **no-deps** → empty lock; clean verify.
7. P2 resolver tests + full `igniter-compiler` suite stay green.

## Required acceptance

- [x] `workspace_lock` deterministic; per-dependency sha256 digest (rel-path + content).
- [x] Two-layer identity: name + digest in each lock entry.
- [x] `verify_lock` reports changed/missing/new (drift); clean lock = empty.
- [x] sha256 used (verify-first delta vs P1's blake3, documented).
- [x] No registry/solver/hooks/CLI; per-workspace lock.
- [x] `igniter-compiler` full suite green (P2 resolver intact); no server/web/machine change; no new crate.
- [x] `git diff --check` clean.

---

## Closing Report (2026-06-21)

**Implementation (`project.rs` + tests only):** dependencies now carry a **name** (`Dependency{name,path}`,
P1 two-layer identity); `workspace_lock(root)` computes one **sha256** content digest per declared dependency
(over its sorted relative-path + content source set, location-independent, name-sorted); `verify_lock(root,
&lock)` returns `Changed`/`New`/`Missing` drift (empty = reproducible); `WorkspaceLock` round-trips through
deterministic JSON. Proof doc: `lab-docs/lang/lab-igniter-package-lock-provenance-p3-v0.md`.

**Verify-first delta (honest):** P1 suggested **blake3**, but live compiler hashing is **sha256** (`main.rs`,
`multifile.rs`); the lock uses sha256 for **consistency within the compiler**, reusing the present `sha2`
dep. blake3-unification with the machine side is deferred.

**Proof — all green:** `package_workspace_tests` **12 passed** (6 P2 resolver + 6 P3 lock: deterministic+
pins, clean-verify, tampered→Changed, content-addressed, no-deps-empty, JSON-roundtrip); `project_mode` 9 +
`project_overlay` 10 intact after the `Dependency` refactor; full `igniter-compiler` suite green (57 lib +
all bins, 0 failed); `git diff --check` clean. No server/web/machine change, no new crate.

**Deferred:** persisted `igniter.lock` + CLI (`igniter lock`/`verify`); compiler/stdlib/lowerer-version lock
fields; blake3-unification; strict direct-dep import scoping; registry/solver. **Next:**
`LAB-IGNITER-PACKAGE-LOCKFILE-CLI-P4` (persist the lock + commands over the `workspace_lock`/`verify_lock`
API).

## Required proof doc

`lab-docs/lang/lab-igniter-package-lock-provenance-p3-v0.md` — sha256 delta vs P1; digest definition;
lock shape; verify/drift semantics; tests/counts; deferred (compiler/stdlib/lowerer version fields, CLI,
registry, blake3-unification); next card.
