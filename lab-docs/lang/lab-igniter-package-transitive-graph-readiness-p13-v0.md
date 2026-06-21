# lab-igniter-package-transitive-graph-readiness-p13-v0 — local transitive dependency graph

**Card:** `LAB-IGNITER-PACKAGE-TRANSITIVE-GRAPH-READINESS-P13` · **Delegation:** `OPUS-IGNITER-PACKAGE-TRANSITIVE-GRAPH-READINESS-P13`
**Status:** READINESS / DESIGN (v0) — chooses the v0 local transitive-graph model and fully specifies P14.
**No code.** Authority: lab readiness, grounded in live `project.rs` (P2/P7/P10/P12).

---

## 1. Executive summary

Lift the **direct-only** limitation: a local package may depend on another local package and have the graph
assembled **transitively**, by **explicit local path edges only** — no registry/semver/solver/network. The
package node identity becomes the **canonical package root path** (display name from the edge); the import
scope rule becomes **graph-edge-aware** (P may import Q iff P *declares* Q); **root may import only its direct
dependencies** (transitive packages must be re-declared if root wants them). Exports are checked on **every**
consumer→provider edge; the **root's `[package] exports` policy stays global** (per-consumer policy deferred).
A **cycle** is a new `OOF-IMP8`; the lock records the **full reachable package set** (each package's own
content digest, flat). Recommended next card: **`LAB-IGNITER-PACKAGE-TRANSITIVE-GRAPH-P14`** (§9).

## 2. Verify-first findings (live `project.rs`)

| Fact | Evidence | Consequence |
|---|---|---|
| `PackageId { Root, Dependency(String) }` — String = the dependency **name** (toml key) at the **root** edge | `enum PackageId` | Name is not globally unique across a graph → **identity must become canonical path**; name = display only. |
| `package_in_scope`: `Root → Dependency(name) if root_deps.contains(name)`; `Dependency(_) → false` | `fn package_in_scope` | A dependency can import **nothing** cross-package today → must become **per-package edge** (P may import its own declared deps). |
| `build_module_index` folds **only `config.dependencies`** (one loop, direct) | dep-scan loop | Needs a **recursive closure** over each package's `[dependencies]`. |
| `dep_exports` keyed by dependency **name** | build loop | Must re-key by **package identity** (names collide across the graph). |
| `workspace_lock` iterates `config.dependencies` (direct) only; entry = `{name, path-rel-root, digest}` | `fn workspace_lock` | Lock must record the **full reachable set**; transitive paths are relative to *their parent* → record a **root-relative canonical path**. |
| `dependency_digest` = manifest + own `.ig` files (P10) | `fn dependency_digest` | Keep **per-package own content**; do **not** nest child digests (the lock lists every node). |
| `normalize_abs` exists | `fn normalize_abs:912` | Reuse for canonical-path identity + cycle/diamond dedup. |
| Diagnostics `OOF-IMP1..7` used | `rg OOF-IMP[0-9]+` | **`OOF-IMP8`** (cycle), **`OOF-IMP9`** (missing dep path) are free. |
| `workspace_direct` fixture: `app→mid`, `mid→deep`; `direct_dependencies_only` test asserts `deep` is **NOT** pulled | fixture + test | **Migration:** under transitive, `mid`'s declared `deep` **is** folded → that test's assertion inverts. **P14 must repurpose the fixture / rewrite the test** (see §8). |

## 3. Decision matrix — package identity

| Alternative | Pros | Cons | Verdict |
|---|---|---|---|
| **Canonical root path (display name from edge)** | globally unique; diamond/same-package dedup is path-equality; names may collide harmlessly | path is machine-specific (handle by storing root-relative in the lock) | **SELECTED** |
| Dependency name only | simple | collides across parents; can't dedup a diamond | rejected |
| Module namespace | aligns with imports | a package owns many modules; not 1:1 | rejected |
| name + path tuple | disambiguates | redundant once path is canonical | rejected (path suffices; name is display) |

## 4. Decision matrix — traversal & root-transitive policy

- **Traversal:** recursive closure over each package's `[dependencies]`; each package's dep paths are relative
  to **its own** root; canonicalize via `normalize_abs`. Deterministic: sort the node set by canonical path;
  a `visited` set dedups diamonds and bounds cycles.
- **Root → transitive import:** **NO** (Q7). Root may import only its **direct** declared deps; a package may
  import only **its own** direct declared deps. Reaching an undeclared package (sibling or transitive) =
  `OOF-IMP6`. Rationale: dependency hygiene — every edge a package relies on is one it declared.

| Root-import policy | Verdict |
|---|---|
| Root may import any reachable transitive package | rejected — hides undeclared coupling |
| **Root may import only direct deps; each package only its own direct deps** | **SELECTED** |

## 5. Decision matrix — exports across transitive edges & closed-default

- **Exports:** every **consumer→provider** edge checks the provider's export surface (not just root→dep).
  Same-package bypasses. Keyed by provider **canonical path**.
- **Closed-default policy:** the **root's** `[package] exports` policy is **global** for the whole workspace
  (extends P12's "root consumer policy" to every edge). A provider with no `[exports]` is open by default, or
  sealed for **all** consumers under root `closed`.

| Closed-default scope | Pros | Cons | Verdict |
|---|---|---|---|
| **Root policy global** | one workspace-wide hygiene bar; simplest; matches P12 | a non-root consumer can't choose its own bar | **SELECTED (v0)** |
| Each consumer package's own `[package] exports` | per-package autonomy | more complex; ambiguous when paths diverge | deferred |

## 6. Diagnostic taxonomy

| Code | Meaning | Status |
|---|---|---|
| `OOF-IMP4` | duplicate module declaration (whole index) | unchanged |
| `OOF-IMP6` | out-of-scope package edge — importer did not **declare** the provider | **generalized** to per-package declared edges |
| `OOF-IMP7` | in-scope edge, module not exported by provider (+ closed-default seal) | unchanged (keyed by canonical path) |
| `OOF-IMP8` | **cycle** in the local package graph | **new** |
| `OOF-IMP9` | a declared `[dependencies]` path does not exist | **new (recommended)**; else falls to OOF-IMP2 on first missing import |
| duplicate package identity | two edges → same canonical path = **one node** (dedup), not a fault | — |

## 7. Lock / provenance decision

- The lock records the **full reachable package set** (every node), sorted by **root-relative canonical
  path**; entry = `{ name (display), path (root-relative), digest }`. Direct-vs-transitive is not encoded —
  the set is the closure.
- `dependency_digest` stays **per-package own content** (manifest + `.ig` files, P10); **no nested child
  digests**. A transitive package's change surfaces as **its own** lock entry's digest changing.
- `verify`/`lock --frozen` therefore cover the whole graph; `verify --strict` runs the same `index_integrity`
  (scope/exports/cycle) the compile path runs, with P11 **structured** `integrity.diagnostic` for graph faults.

## 8. Card questions — explicit answers

1. **Identity:** canonical package root path; display name from the edge.
2. **Traversal:** recursive `[dependencies]` closure, paths relative to each package root, canonicalized,
   sorted by canonical path, `visited`-bounded.
3. **Duplicate names from different parents:** allowed (name = display); distinct paths = distinct nodes.
4. **Same physical package via two paths:** canonicalize → one node (diamond dedup, no version solving).
5. **Graph diagnostics:** `OOF-IMP8` cycle; `OOF-IMP9` missing dep path (recommended); duplicate module stays
   `OOF-IMP4`; duplicate identity = dedup (not a fault).
6. **OOF-IMP6:** generalized — P may import Q iff P declares Q (per-package edges), not index presence.
7. **Root import transitive?** **No** — direct only; re-declare to use.
8. **Exports transitively:** every consumer→provider edge; same-package bypasses; closed-default = root-global
   (per-consumer deferred).
9. **Lock:** full reachable set (root-relative canonical path), flat per-package digest.
10. **digest content:** manifest + own `.ig` only; no nested transitive digests.
11. **strict reporting:** shared `index_integrity` → P11 structured `integrity.diagnostic` (incl. OOF-IMP8).
12. **fixtures:** §9.

## 9. Exact P14 acceptance tests (implement without rediscovery)

New fixtures under `tests/fixtures/project_mode/`:
- `workspace_tgraph_ok` — `app→a`, `a→b` (a declares b); `App.Main import A.X`; `A.X import B.Y` (a declares b
  → in scope); b open/exports `B.Y`. Resolves: main + a + b folded.
- `workspace_tgraph_root_undeclared` — `app→a`, `a→b`; `App.Main import B.Y` (root did NOT declare b) →
  `OOF-IMP6` (root may not import a transitive package directly).
- `workspace_tgraph_phantom` — `a→b`, `a→c` exist but `a` imports `C.Z` while declaring only `b` →
  `OOF-IMP6`.
- `workspace_tgraph_cycle` — `a→b`, `b→a` → `OOF-IMP8`.
- `workspace_tgraph_diamond` — `app→a`, `app→b`, `a→c`, `b→c` (same canonical `c`) → one node, resolves clean.
- `workspace_tgraph_exports` — `a→b`, `b` declares `[exports]`, `A.X` imports a non-exported `b` module →
  `OOF-IMP7`.

Tests (`package_workspace_tests.rs`):
1. `transitive_declared_edge_resolves` (tgraph_ok closure = main + a + b).
2. `root_cannot_import_transitive_dep` (tgraph_root_undeclared → OOF-IMP6).
3. `package_cannot_import_undeclared_sibling` (tgraph_phantom → OOF-IMP6).
4. `package_graph_cycle_is_oof_imp8` (tgraph_cycle → OOF-IMP8).
5. `diamond_same_package_dedups` (tgraph_diamond resolves; provider folded once).
6. `transitive_export_violation_is_oof_imp7` (tgraph_exports → OOF-IMP7).
7. `check_workspace_integrity` flags OOF-IMP8/IMP6 entry-free.
8. **Migration:** rewrite `direct_dependencies_only` → `transitive_dependencies_are_pulled` (the
   `workspace_direct` `mid→deep` edge is now folded); update its proof-doc reference.
9. Lock: `transitive_lock_records_full_graph` (lock for tgraph_ok lists a **and** b); CLI
   `cli_verify_strict_catches_cycle` (OOF-IMP8 structured).
10. Full `igniter-compiler` suite green; `git diff --check` clean.

## 10. Closed scope (honored)

No registry/semver/solver/lockfile package versions/remote/publishing; no module glob exports; no `.ig`
syntax; no server/web/machine/typechecker/VM; no global Cargo workspace restructuring; **no code in P13**;
P14 not implemented here.

---

*Lab readiness packet. Grounded in live `project.rs` (PackageId, package_in_scope, build_module_index,
dep_exports keying, workspace_lock, dependency_digest, normalize_abs, free codes OOF-IMP8/9). Selected v0:
canonical-path identity, recursive explicit-path closure, graph-edge-aware OOF-IMP6, root-direct-only imports,
per-edge exports with root-global closed-default, full-graph flat lock, cycle = OOF-IMP8. P14 acceptance tests
+ the `direct_dependencies_only` migration fully enumerated.*
