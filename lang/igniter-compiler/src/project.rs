// LAB-COMPILER-PROJECT-MODE-COMPILE-P1 / LAB-COMPILER-PROJECT-OVERLAY-P2
//
// Canonical project-root compile mode for multi-file Igniter projects.
//
// This module owns project assembly: scan source roots, build a logical
// module index (module_path -> source_path) by PARSING each file's `module`
// declaration (never by directory inference), and resolve the transitive
// import closure for an entry module. It then hands the resolved file list to
// the existing `multifile::compile_units` pipeline.
//
// P2 adds IDE overlays: an overlay maps a project source path to a temporary
// editor-buffer file. During scanning, the overlay content is read in place of
// the on-disk file, so module/import resolution AND the final compile see the
// unsaved buffer. The overlay path is what flows to compile_units, so source
// evidence honestly carries the overlay (temp) path for overlaid units.
//
// Authority boundary: igniter-lab only. This does NOT change language import
// semantics. Imports remain logical module paths. stdlib.* is reserved and is
// resolved from the stdlib inventory, not from project files.

use crate::lexer::Lexer;
use crate::parser::Parser;
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::collections::{BTreeMap, BTreeSet};
use std::fs;
use std::path::{Component, Path, PathBuf};

/// Directories never scanned for source files.
const IGNORED_DIRS: &[&str] = &[".git", "target", "build", ".idea"];

/// Minimal project configuration.
///
/// P1 keeps this intentionally small: a list of source roots relative to the
/// project root. LAB-IGNITER-PACKAGE-WORKSPACE-RESOLVER-P2 adds `dependencies`:
/// relative paths to LOCAL dependency package roots whose source roots are folded
/// into this project's module index. A richer `igniter.toml` schema (versions,
/// registry, lock) is deferred.
#[derive(Debug, Clone)]
pub struct ProjectConfig {
    pub source_roots: Vec<PathBuf>,
    /// P2: local dependency package declarations (`[dependencies]`). Direct
    /// dependencies only — a dependency's own `[dependencies]` are not pulled in
    /// v0 (no transitive package graph, no registry, no version solver).
    pub dependencies: Vec<Dependency>,
    /// LAB-IGNITER-PACKAGE-MODULE-EXPORTS-P10: a dependency's exported module surface (`[exports] modules`).
    /// `None` = no `[exports]` block ⇒ the package is **open** (every module importable, backward-compatible).
    /// `Some(list)` = restrict cross-package imports to exactly these modules; `Some([])` = a sealed package.
    /// Only meaningful for a package consumed as a dependency; a root's own exports are ignored.
    pub exports: Option<Vec<String>>,
    /// LAB-IGNITER-PACKAGE-EXPORTS-CLOSED-DEFAULT-P12: the **root** consumer policy for dependencies that
    /// declare no `[exports]` block (`[package] exports = "open" | "closed"`). `Open` (default) = P10
    /// behavior (absence = open); `Closed` = absence is treated as sealed. Only the root's policy is read.
    pub exports_default: ExportsDefault,
}

/// LAB-IGNITER-PACKAGE-EXPORTS-CLOSED-DEFAULT-P12. How the workspace root interprets a dependency that
/// declares no `[exports]` block.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum ExportsDefault {
    /// Absence of `[exports]` ⇒ the dependency is open (every module importable). Backward-compatible.
    #[default]
    Open,
    /// Absence of `[exports]` ⇒ the dependency is sealed; importing any of its modules is `OOF-IMP7`.
    Closed,
}

/// LAB-IGNITER-PACKAGE-WORKSPACE-RESOLVER-P2 / LOCK-PROVENANCE-P3.
/// A declared local path dependency: a human `name` (DX, P1 two-layer identity)
/// and the relative `path` to the dependency package root.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Dependency {
    pub name: String,
    pub path: PathBuf,
}

impl ProjectConfig {
    /// Load configuration for a project root.
    ///
    /// Behavior:
    /// - If `<root>/igniter.toml` exists, read a `source_roots = ["a", "b"]`
    ///   array (minimal hand-rolled parse; no toml crate dependency).
    /// - Otherwise default to `["."]` (scan the whole project root).
    /// - P2: also read a `[dependencies]` table of local path dependencies.
    pub fn load(root: &Path) -> Self {
        let mut source_roots = vec![PathBuf::from(".")];
        let mut dependencies = Vec::new();
        let mut exports = None;
        let mut exports_default = ExportsDefault::Open;
        let toml_path = root.join("igniter.toml");
        if let Ok(content) = fs::read_to_string(&toml_path) {
            if let Some(roots) = parse_source_roots_toml(&content) {
                if !roots.is_empty() {
                    source_roots = roots.into_iter().map(PathBuf::from).collect();
                }
            }
            dependencies = parse_dependencies_toml(&content)
                .into_iter()
                .map(|(name, path)| Dependency {
                    name,
                    path: PathBuf::from(path),
                })
                .collect();
            exports = parse_exports_toml(&content);
            exports_default = parse_package_exports_default(&content);
        }
        ProjectConfig {
            source_roots,
            dependencies,
            exports,
            exports_default,
        }
    }
}

/// A project-level diagnostic. Mirrors the shape of multifile diagnostics so it
/// renders consistently in compiler_result JSON.
#[derive(Debug, Clone)]
pub struct ProjectDiagnostic {
    pub rule: String,
    pub severity: String,
    pub message: String,
    pub node: String,
    pub entry_module: Option<String>,
    pub module_path: Option<String>,
    pub source_paths: Vec<String>,
    pub original_path: Option<String>,
    pub overlay_path: Option<String>,
}

impl ProjectDiagnostic {
    fn new(rule: &str, message: String, node: String) -> Self {
        Self {
            rule: rule.to_string(),
            severity: "error".to_string(),
            message,
            node,
            entry_module: None,
            module_path: None,
            source_paths: Vec::new(),
            original_path: None,
            overlay_path: None,
        }
    }

    pub fn to_value(&self) -> Value {
        let mut obj = serde_json::Map::new();
        obj.insert("rule".to_string(), json!(self.rule));
        obj.insert("severity".to_string(), json!(self.severity));
        obj.insert("message".to_string(), json!(self.message));
        obj.insert("node".to_string(), json!(self.node));
        if let Some(em) = &self.entry_module {
            obj.insert("entry_module".to_string(), json!(em));
        }
        if let Some(mp) = &self.module_path {
            obj.insert("module_path".to_string(), json!(mp));
        }
        if !self.source_paths.is_empty() {
            obj.insert("source_paths".to_string(), json!(self.source_paths));
        }
        if let Some(op) = &self.original_path {
            obj.insert("original_path".to_string(), json!(op));
        }
        if let Some(op) = &self.overlay_path {
            obj.insert("overlay_path".to_string(), json!(op));
        }
        Value::Object(obj)
    }
}

#[derive(Debug)]
pub enum ProjectError {
    Diagnostic(ProjectDiagnostic),
    Io(std::io::Error),
}

impl From<std::io::Error> for ProjectError {
    fn from(e: std::io::Error) -> Self {
        ProjectError::Io(e)
    }
}

/// LAB-COMPILER-PROJECT-OVERLAY-P2
/// An IDE overlay: substitute `overlay_path`'s contents for the project source
/// file at `original_path` during scanning and compilation.
#[derive(Debug, Clone)]
pub struct ProjectOverlay {
    pub original_path: PathBuf,
    pub overlay_path: PathBuf,
}

/// A validated overlay: normalized original location + the file to read instead.
#[derive(Debug, Clone)]
struct ResolvedOverlay {
    norm_original: PathBuf,
    overlay_path: PathBuf,
}

/// LAB-IGNITER-PACKAGE-IMPORT-SCOPING-P7 / TRANSITIVE-GRAPH-P14
/// Which workspace package a scanned file belongs to: the workspace root, or a local package identified by
/// its **canonical root path** (P14 — names are not unique across a transitive graph, so the path is the
/// identity; a diamond resolves to one node by path equality). Import scope follows declared graph edges.
#[derive(Debug, Clone, PartialEq, Eq)]
enum PackageId {
    Root,
    Package(PathBuf),
}

impl PackageId {
    /// The canonical root path of this package (the root's is supplied separately).
    fn canonical<'a>(&'a self, root: &'a Path) -> &'a Path {
        match self {
            PackageId::Root => root,
            PackageId::Package(p) => p,
        }
    }
}

/// LAB-IGNITER-PACKAGE-TRANSITIVE-GRAPH-P14. One node in the local package graph.
#[derive(Debug, Clone)]
struct PackageNode {
    /// Display name for diagnostics (`<root>`, or the lexicographically smallest declaring edge name).
    display: String,
    /// Canonical root paths of this package's **direct** declared dependencies (graph edges).
    deps: BTreeSet<PathBuf>,
    /// This package's `[exports]` surface (`None` = open; `Some(set)` = allowlist; `Some(empty)` = sealed).
    exports: Option<BTreeSet<String>>,
    /// Source roots to scan for this package.
    source_roots: Vec<PathBuf>,
}

/// The assembled local package graph: every reachable node keyed by canonical root path (includes the root).
#[derive(Debug)]
struct PackageGraph {
    root: PathBuf,
    nodes: BTreeMap<PathBuf, PackageNode>,
}

impl PackageGraph {
    fn label(&self, pkg: &PackageId) -> String {
        match pkg {
            PackageId::Root => "<root>".to_string(),
            PackageId::Package(p) => self
                .nodes
                .get(p)
                .map(|n| n.display.clone())
                .unwrap_or_else(|| "<unknown>".to_string()),
        }
    }
}

/// One scanned source file: its logical module path, its non-stdlib imports, and its owning package.
#[derive(Debug, Clone)]
struct ScannedFile {
    source_path: PathBuf,
    module_path: String,
    /// Non-stdlib imported module paths (logical). stdlib imports are dropped
    /// here because they are not file dependencies.
    non_stdlib_imports: Vec<String>,
    /// LAB-IGNITER-PACKAGE-IMPORT-SCOPING-P7: the package this file was scanned from.
    package: PackageId,
}

/// Module index: logical module path -> source file.
///
/// Duplicate module declarations are tracked so we can emit a deterministic,
/// actionable diagnostic instead of silently picking one file.
#[derive(Debug)]
pub struct ModuleIndex {
    by_module: BTreeMap<String, ScannedFile>,
    /// module_path -> all source paths that declared it (only modules with >1).
    duplicates: BTreeMap<String, Vec<String>>,
    /// LAB-IGNITER-PACKAGE-TRANSITIVE-GRAPH-P14: the assembled local package graph (edges + per-node
    /// exports), used by `index_integrity` for scope (OOF-IMP6), exports (OOF-IMP7) and cycles (OOF-IMP8).
    graph: PackageGraph,
    /// LAB-IGNITER-PACKAGE-EXPORTS-CLOSED-DEFAULT-P12: the root's closed-default policy (global for the graph).
    exports_default: ExportsDefault,
}

/// Resolve the transitive, non-stdlib import closure for `entry_module`.
///
/// Returns a deterministically ordered list of source paths suitable for
/// `multifile::compile_units`. Missing imported modules are intentionally NOT
/// reported here — they are left for `compile_units` to surface as OOF-IMP2,
/// preserving canonical import-diagnostic behavior.
pub fn resolve_entry(root: &Path, entry_module: &str) -> Result<Vec<PathBuf>, ProjectError> {
    resolve_entry_with_overlays(root, entry_module, &[])
}

/// LAB-COMPILER-PROJECT-OVERLAY-P2
/// Like `resolve_entry`, but each overlay substitutes its `overlay_path`'s
/// contents for the on-disk `original_path` during scanning and compilation.
/// With an empty overlay slice this is byte-for-byte the P1 behavior.
pub fn resolve_entry_with_overlays(
    root: &Path,
    entry_module: &str,
    overlays: &[ProjectOverlay],
) -> Result<Vec<PathBuf>, ProjectError> {
    let config = ProjectConfig::load(root);
    let resolved = validate_overlays(root, &config, overlays)?;
    let index = build_module_index(root, &config, &resolved)?;

    // Project-assembly integrity: duplicate module declarations (OOF-IMP4) and out-of-scope/phantom imports
    // (OOF-IMP6). Shared with `check_workspace_integrity` so the compile path and the CI gate enforce
    // exactly the same rules.
    if let Some(diag) = index_integrity(&index) {
        return Err(ProjectError::Diagnostic(diag));
    }

    if !index.by_module.contains_key(entry_module) {
        let mut diag = ProjectDiagnostic::new(
            "OOF-PROJ-ENTRY",
            format!(
                "entry module '{}' not found in project source roots",
                entry_module
            ),
            format!("entry:{}", entry_module),
        );
        diag.entry_module = Some(entry_module.to_string());
        return Err(ProjectError::Diagnostic(diag));
    }

    // Transitive closure over non-stdlib imports, deterministic traversal.
    let mut selected: BTreeMap<String, PathBuf> = BTreeMap::new();
    let mut queue: Vec<String> = vec![entry_module.to_string()];
    while let Some(module) = queue.pop() {
        if selected.contains_key(&module) {
            continue;
        }
        // A module reachable from the entry but absent from the index is a
        // missing import. Skip it here; compile_units reports OOF-IMP2 once it
        // sees the dangling import.
        let Some(file) = index.by_module.get(&module) else {
            continue;
        };
        selected.insert(module.clone(), file.source_path.clone());
        let mut deps = file.non_stdlib_imports.clone();
        deps.sort();
        deps.dedup();
        for dep in deps {
            if !selected.contains_key(&dep) {
                queue.push(dep);
            }
        }
    }

    // Deterministic order: sort by source path. (compile_units re-sorts by
    // module path anyway, so the resulting source hash is stable regardless.)
    let mut paths: Vec<PathBuf> = selected.into_values().collect();
    paths.sort();
    Ok(paths)
}

/// Project-assembly integrity over an already-built index: the first (deterministic) of a duplicate module
/// declaration (OOF-IMP4), a package-graph cycle (OOF-IMP8), an out-of-scope/phantom import (OOF-IMP6), or a
/// non-exported import (OOF-IMP7); `None` if the workspace is clean. Entry-independent — faults of the
/// *assembled workspace*. LAB-IGNITER-PACKAGE-TRANSITIVE-GRAPH-P14: scope and exports follow declared graph
/// edges (a package may import a provider iff it declares it; same-package always allowed); exports are
/// checked on every consumer→provider edge.
fn index_integrity(index: &ModuleIndex) -> Option<ProjectDiagnostic> {
    let graph = &index.graph;

    // Duplicate module declarations: the index is ambiguous. Surface deterministically with all source paths.
    if let Some((module, paths)) = index.duplicates.iter().next() {
        let mut diag = ProjectDiagnostic::new(
            "OOF-IMP4",
            format!("duplicate module declaration '{}'", module),
            format!("module:{}", module),
        );
        diag.module_path = Some(module.clone());
        diag.source_paths = paths.clone();
        return Some(diag);
    }

    // OOF-IMP8: a cycle in the local package graph is an assembly fault.
    if let Some(diag) = detect_cycle(graph) {
        return Some(diag);
    }

    // OOF-IMP6: a file may import a module only when the importer's PACKAGE declares the provider's package as
    // a direct dependency (or it is the same package). A package reaching one it never declared — a sibling,
    // a transitive package, or the root — is an out-of-scope import. Resolved imports only (dangling →
    // compile_units OOF-IMP2).
    let mut violations: Vec<(String, String)> = Vec::new();
    for (module, file) in &index.by_module {
        let importer = file.package.canonical(&graph.root);
        for imp in &file.non_stdlib_imports {
            let Some(target) = index.by_module.get(imp) else {
                continue;
            };
            let provider = target.package.canonical(&graph.root);
            if importer == provider {
                continue; // same package
            }
            let declared = graph
                .nodes
                .get(importer)
                .is_some_and(|n| n.deps.contains(provider));
            if !declared {
                violations.push((module.clone(), imp.clone()));
            }
        }
    }
    violations.sort();
    violations.dedup();
    if let Some((importer, imported)) = violations.first() {
        let importer_file = &index.by_module[importer];
        let target_file = &index.by_module[imported];
        let mut diag = ProjectDiagnostic::new(
            "OOF-IMP6",
            format!(
                "out-of-scope import: module '{}' (package {}) imports '{}' (package {}), which it does not declare as a dependency",
                importer,
                graph.label(&importer_file.package),
                imported,
                graph.label(&target_file.package)
            ),
            format!("import:{}->{}", importer, imported),
        );
        diag.module_path = Some(importer.clone());
        diag.source_paths = vec![importer_file.source_path.to_string_lossy().to_string()];
        return Some(diag);
    }

    // OOF-IMP7: on every (now declared) consumer→provider edge, reject a module the provider does not export.
    // Same-package imports bypass exports. A provider that declares `[exports]` is held to its allowlist; a
    // provider with no `[exports]` is open by default, OR sealed when the root opts into `[package] exports =
    // "closed"` (P12 policy, global across the graph). The bool marks the sealed-by-policy case.
    let closed = index.exports_default == ExportsDefault::Closed;
    let mut export_violations: Vec<(String, String, bool)> = Vec::new();
    for (module, file) in &index.by_module {
        let importer = file.package.canonical(&graph.root);
        for imp in &file.non_stdlib_imports {
            let Some(target) = index.by_module.get(imp) else {
                continue;
            };
            let provider = target.package.canonical(&graph.root);
            if importer == provider {
                continue; // same-package bypasses exports
            }
            let Some(node) = graph.nodes.get(provider) else {
                continue;
            };
            match &node.exports {
                Some(allow) if !allow.contains(imp) => {
                    export_violations.push((module.clone(), imp.clone(), false));
                }
                None if closed => {
                    export_violations.push((module.clone(), imp.clone(), true));
                }
                _ => {}
            }
        }
    }
    export_violations.sort();
    export_violations.dedup();
    if let Some((importer, imported, sealed_by_policy)) = export_violations.first() {
        let importer_file = &index.by_module[importer];
        let target_file = &index.by_module[imported];
        let dep_label = graph.label(&target_file.package);
        let message = if *sealed_by_policy {
            format!(
                "non-exported import: module '{}' imports '{}' (package {}), which declares no exports ([package] exports = \"closed\")",
                importer, imported, dep_label
            )
        } else {
            format!(
                "non-exported import: module '{}' imports '{}' (package {}), which package '{}' does not export",
                importer, imported, dep_label, dep_label
            )
        };
        let mut diag = ProjectDiagnostic::new(
            "OOF-IMP7",
            message,
            format!("export:{}->{}", importer, imported),
        );
        diag.module_path = Some(importer.clone());
        diag.source_paths = vec![importer_file.source_path.to_string_lossy().to_string()];
        return Some(diag);
    }

    None
}

/// LAB-IGNITER-PACKAGE-LOCKFILE-FROZEN-CI-P8
/// Assert the assembled workspace has integrity — no duplicate modules (OOF-IMP4), no phantom imports
/// (OOF-IMP6) — without requiring an entry module. The CI gate (`igc verify --strict`) uses this so a
/// trusted workspace is one that both matches its lock AND assembles cleanly.
pub fn check_workspace_integrity(root: &Path) -> Result<(), ProjectError> {
    let config = ProjectConfig::load(root);
    let index = build_module_index(root, &config, &[])?;
    match index_integrity(&index) {
        Some(diag) => Err(ProjectError::Diagnostic(diag)),
        None => Ok(()),
    }
}

// ── LAB-IGNITER-PACKAGE-LOCK-PROVENANCE-P3: per-workspace dependency lock ────────────────────────────

/// One locked dependency: human `name` + declared `path` + a `digest` over its sorted source set.
/// Two-layer identity (P1): the name is for DX, the digest is the reproducibility anchor.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LockedDependency {
    pub name: String,
    pub path: String,
    /// `sha256:<hex>` over the dependency's sorted (relative-path + content) source files.
    pub digest: String,
}

/// LAB-IGNITER-PACKAGE-VERSION-PROVENANCE-P5 / STDLIB-VERSION-CONSTANT-P6.
/// The toolchain that produced a lock. Two build-time constants the compiler crate authoritatively stamps:
/// the **compiler version** (`env!("CARGO_PKG_VERSION")`) and the **stdlib surface version**
/// (`crate::STDLIB_VERSION`). `grammar_version` is per-program (dynamic) and a dedicated lowerer version
/// has no constant yet — both deferred. Each field empty = unpinned for that field (a pre-P5 / pre-P6 lock).
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct Toolchain {
    /// `igniter_compiler` crate version at lock time. Empty = unpinned (a pre-P5 lock).
    pub compiler: String,
    /// stdlib contract-surface version (`crate::STDLIB_VERSION`). Empty = unpinned (a pre-P6 lock).
    pub stdlib: String,
}

/// A per-workspace lock: the producing **toolchain** + a deterministic, name-sorted list of dependency
/// digests. Pins package content (and now the compiler version) for reproducible offline rebuilds. The
/// digest algorithm is **sha256**, matching the live compiler source-hash convention (`main.rs` /
/// `multifile.rs`), not blake3 (P1's suggestion); aligning algorithms is a separate concern.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WorkspaceLock {
    pub toolchain: Toolchain,
    pub dependencies: Vec<LockedDependency>,
}

/// A detected difference between the on-disk workspace and a lock. Empty list = reproducible.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum LockDrift {
    /// content digest differs from the lock.
    Changed {
        name: String,
        locked: String,
        actual: String,
    },
    /// in the lock but no longer a workspace dependency.
    Missing { name: String },
    /// a workspace dependency absent from the lock.
    New { name: String },
    /// a pinned toolchain field differs from the current toolchain.
    Toolchain {
        field: String,
        locked: String,
        actual: String,
    },
}

/// The current toolchain identity (build-time). `env!("CARGO_PKG_VERSION")` resolves to the
/// `igniter_compiler` crate version that built this binary.
pub fn current_toolchain() -> Toolchain {
    Toolchain {
        compiler: env!("CARGO_PKG_VERSION").to_string(),
        stdlib: crate::STDLIB_VERSION.to_string(),
    }
}

impl WorkspaceLock {
    /// Deterministic JSON for the lockfile (name-sorted, stable field order).
    pub fn to_value(&self) -> Value {
        json!({
            "version": 1,
            "toolchain": { "compiler": self.toolchain.compiler, "stdlib": self.toolchain.stdlib },
            "dependencies": self
                .dependencies
                .iter()
                .map(|d| json!({ "name": d.name, "path": d.path, "digest": d.digest }))
                .collect::<Vec<_>>(),
        })
    }

    /// Parse a lock back from its JSON value (`None` if malformed). The `toolchain` block is optional: a
    /// pre-P5 lock without one parses as **unpinned** (empty compiler) → no toolchain drift.
    pub fn from_value(v: &Value) -> Option<WorkspaceLock> {
        let tc_field = |field: &str| -> String {
            v.get("toolchain")
                .and_then(|t| t.get(field))
                .and_then(|c| c.as_str())
                .unwrap_or("")
                .to_string()
        };
        let toolchain = Toolchain {
            compiler: tc_field("compiler"),
            stdlib: tc_field("stdlib"),
        };
        let arr = v.get("dependencies")?.as_array()?;
        let mut dependencies = Vec::with_capacity(arr.len());
        for e in arr {
            dependencies.push(LockedDependency {
                name: e.get("name")?.as_str()?.to_string(),
                path: e.get("path")?.as_str()?.to_string(),
                digest: e.get("digest")?.as_str()?.to_string(),
            });
        }
        Some(WorkspaceLock {
            toolchain,
            dependencies,
        })
    }
}

/// Compute the per-workspace lock: one `sha256` content digest per package in the **full reachable graph**
/// (LAB-IGNITER-PACKAGE-TRANSITIVE-GRAPH-P14), excluding the root itself. Each entry is keyed by a
/// root-relative canonical path (stable across machines); sorted by path for determinism. Each package's
/// digest is its own content (manifest + `.ig` files) — transitive child digests are NOT nested.
pub fn workspace_lock(root: &Path) -> Result<WorkspaceLock, ProjectError> {
    let graph = collect_package_graph(root)?;
    let mut locked = Vec::new();
    for (canon, node) in &graph.nodes {
        if *canon == graph.root {
            continue; // the root workspace is not a dependency entry
        }
        locked.push(LockedDependency {
            name: node.display.clone(),
            path: relative_to(&graph.root, canon).to_string_lossy().to_string(),
            digest: dependency_digest(canon)?,
        });
    }
    locked.sort_by(|a, b| (a.path.as_str(), a.name.as_str()).cmp(&(b.path.as_str(), b.name.as_str())));
    Ok(WorkspaceLock {
        toolchain: current_toolchain(),
        dependencies: locked,
    })
}

/// Recompute the workspace lock and diff it against `lock`. Returns the (possibly empty) drift list:
/// `Changed` (digest differs), `New` (on disk, not in lock), `Missing` (in lock, not on disk).
pub fn verify_lock(root: &Path, lock: &WorkspaceLock) -> Result<Vec<LockDrift>, ProjectError> {
    let current = workspace_lock(root)?;
    let mut drifts = Vec::new();
    // Toolchain drift first — per field, only when the lock actually pinned that field (an empty field is
    // an unpinned pre-P5/pre-P6 lock = "no claim", so it never reports drift).
    for (field, locked, actual) in [
        (
            "compiler",
            &lock.toolchain.compiler,
            &current.toolchain.compiler,
        ),
        ("stdlib", &lock.toolchain.stdlib, &current.toolchain.stdlib),
    ] {
        if !locked.is_empty() && locked != actual {
            drifts.push(LockDrift::Toolchain {
                field: field.to_string(),
                locked: locked.clone(),
                actual: actual.clone(),
            });
        }
    }
    // LAB-IGNITER-PACKAGE-TRANSITIVE-GRAPH-P14: match packages by `path` (the stable per-node identity) —
    // display names can collide across a transitive graph, paths cannot.
    for cur in &current.dependencies {
        match lock.dependencies.iter().find(|d| d.path == cur.path) {
            Some(locked) if locked.digest != cur.digest => drifts.push(LockDrift::Changed {
                name: cur.name.clone(),
                locked: locked.digest.clone(),
                actual: cur.digest.clone(),
            }),
            Some(_) => {}
            None => drifts.push(LockDrift::New {
                name: cur.name.clone(),
            }),
        }
    }
    for locked in &lock.dependencies {
        if !current.dependencies.iter().any(|c| c.path == locked.path) {
            drifts.push(LockDrift::Missing {
                name: locked.name.clone(),
            });
        }
    }
    Ok(drifts)
}

/// `sha256` over a dependency's sorted source files. Each file contributes its **relative** path
/// (location-independent) followed by its raw content; files are sorted so the digest is deterministic.
///
/// LAB-IGNITER-PACKAGE-MODULE-EXPORTS-P10: the dependency's `igniter.toml` (if present) is folded in as
/// well, so a manifest change — `[exports]`, `source_roots`, or `[dependencies]` — moves the digest and is
/// therefore caught by `verify` / `lock --frozen`. Without this, the digest hashed only `.ig` files and an
/// exports change would be invisible to the lock.
fn dependency_digest(dep_root: &Path) -> Result<String, ProjectError> {
    let dep_config = ProjectConfig::load(dep_root);
    let mut files: Vec<PathBuf> = Vec::new();
    let manifest = dep_root.join("igniter.toml");
    if manifest.is_file() {
        files.push(manifest);
    }
    for source_root in &dep_config.source_roots {
        let scan_root = if source_root == Path::new(".") {
            dep_root.to_path_buf()
        } else {
            dep_root.join(source_root)
        };
        collect_ig_files(&scan_root, &mut files)?;
    }
    files.sort();
    files.dedup();
    let mut hasher = Sha256::new();
    for file in &files {
        let rel = file.strip_prefix(dep_root).unwrap_or(file);
        hasher.update(rel.to_string_lossy().as_bytes());
        hasher.update([0u8]);
        let content = fs::read(file)?;
        hasher.update(&content);
        hasher.update([0u8]);
    }
    Ok(format!("sha256:{:x}", hasher.finalize()))
}

/// Recursively scan source roots and build the module index by parsing each
/// `.ig` file's `module` declaration. Directory names never define modules.
///
/// Overlays substitute their content for the matching on-disk file (matched by
/// normalized absolute path). An overlay whose original is not present on disk
/// is injected as a new source unit (the IDE "unsaved new file" case).
fn build_module_index(
    root: &Path,
    config: &ProjectConfig,
    overlays: &[ResolvedOverlay],
) -> Result<ModuleIndex, ProjectError> {
    // LAB-IGNITER-PACKAGE-TRANSITIVE-GRAPH-P14: assemble the full local package graph (root + transitive
    // closure), then scan every node's source roots, tagging each file with its owning package. The root
    // node → PackageId::Root; every other node → PackageId::Package(canonical). Each node is scanned once
    // (diamonds dedup by canonical path).
    let graph = collect_package_graph(root)?;
    let mut files: Vec<(PathBuf, PackageId)> = Vec::new();
    for (canon, node) in &graph.nodes {
        let pkg = if *canon == graph.root {
            PackageId::Root
        } else {
            PackageId::Package(canon.clone())
        };
        for source_root in &node.source_roots {
            let scan_root = if source_root == Path::new(".") {
                canon.clone()
            } else {
                canon.join(source_root)
            };
            let mut pkg_files: Vec<PathBuf> = Vec::new();
            collect_ig_files(&scan_root, &mut pkg_files)?;
            files.extend(pkg_files.into_iter().map(|p| (p, pkg.clone())));
        }
    }

    // Inject overlay originals that are not present on disk (new unsaved files). Overlays are root buffers.
    let scanned_norms: std::collections::HashSet<PathBuf> =
        files.iter().map(|(p, _)| normalize_abs(p)).collect();
    for ov in overlays {
        if !scanned_norms.contains(&ov.norm_original) {
            files.push((ov.norm_original.clone(), PackageId::Root));
        }
    }

    // Deterministic scan order independent of filesystem enumeration; dedup by path (first package wins).
    files.sort_by(|a, b| a.0.cmp(&b.0));
    files.dedup_by(|a, b| a.0 == b.0);

    let mut by_module: BTreeMap<String, ScannedFile> = BTreeMap::new();
    let mut dup_acc: BTreeMap<String, Vec<String>> = BTreeMap::new();

    for (path, package) in files {
        // If this file is overlaid, read the overlay buffer instead of disk.
        // The overlay path also becomes the effective source path handed to
        // compile_units, so source evidence honestly carries the temp path.
        let np = normalize_abs(&path);
        let read_path = overlays
            .iter()
            .find(|ov| ov.norm_original == np)
            .map(|ov| ov.overlay_path.clone())
            .unwrap_or_else(|| path.clone());

        let mut scanned = scan_file(&read_path)?;
        scanned.package = package;
        // Files without a module declaration are not addressable by entry/import
        // resolution. compile_units will reject them (OOF-IMP5) if they are ever
        // passed in; here we simply cannot index them, so skip.
        if scanned.module_path.is_empty() {
            continue;
        }
        let module = scanned.module_path.clone();
        let this_path = scanned.source_path.to_string_lossy().to_string();
        match by_module.get(&module) {
            None => {
                by_module.insert(module, scanned);
            }
            Some(existing) => {
                let entry = dup_acc
                    .entry(module.clone())
                    .or_insert_with(|| vec![existing.source_path.to_string_lossy().to_string()]);
                entry.push(this_path);
                entry.sort();
                entry.dedup();
            }
        }
    }

    Ok(ModuleIndex {
        by_module,
        duplicates: dup_acc,
        graph,
        exports_default: config.exports_default,
    })
}

/// LAB-IGNITER-PACKAGE-TRANSITIVE-GRAPH-P14
/// Assemble the local package graph: from the workspace root, recursively load each package's
/// `[dependencies]`, canonicalizing every path relative to the **declaring** package. Nodes are keyed by
/// canonical root path (a diamond resolves to one node; traversal is `visited`-bounded so a cycle cannot
/// loop here — it is reported later by `detect_cycle`). Display names are deterministic: the smallest
/// declaring edge name.
fn collect_package_graph(root: &Path) -> Result<PackageGraph, ProjectError> {
    let root_canon = normalize_abs(root);
    let mut nodes: BTreeMap<PathBuf, PackageNode> = BTreeMap::new();
    let mut names: BTreeMap<PathBuf, BTreeSet<String>> = BTreeMap::new();
    let mut queue: Vec<PathBuf> = vec![root_canon.clone()];
    while let Some(canon) = queue.pop() {
        if nodes.contains_key(&canon) {
            continue;
        }
        let config = ProjectConfig::load(&canon);
        let mut deps = BTreeSet::new();
        for dep in &config.dependencies {
            let dep_canon = normalize_abs(&canon.join(&dep.path));
            deps.insert(dep_canon.clone());
            names.entry(dep_canon.clone()).or_default().insert(dep.name.clone());
            queue.push(dep_canon);
        }
        nodes.insert(
            canon.clone(),
            PackageNode {
                display: String::new(), // assigned below
                deps,
                exports: config.exports.clone().map(|v| v.into_iter().collect()),
                source_roots: config.source_roots.clone(),
            },
        );
    }
    for (canon, node) in nodes.iter_mut() {
        node.display = if *canon == root_canon {
            "<root>".to_string()
        } else {
            names
                .get(canon)
                .and_then(|s| s.iter().next().cloned())
                .or_else(|| canon.file_name().map(|f| f.to_string_lossy().to_string()))
                .unwrap_or_default()
        };
    }
    Ok(PackageGraph {
        root: root_canon,
        nodes,
    })
}

/// DFS back-edge detection. Returns the cycle (as a node path) if `node` reaches a gray ancestor.
fn cycle_dfs<'a>(
    node: &'a PathBuf,
    graph: &'a PackageGraph,
    color: &mut BTreeMap<&'a PathBuf, u8>, // 0 white, 1 gray, 2 black
    stack: &mut Vec<&'a PathBuf>,
) -> Option<Vec<PathBuf>> {
    color.insert(node, 1);
    stack.push(node);
    if let Some(n) = graph.nodes.get(node) {
        for dep in &n.deps {
            let Some((dep_key, _)) = graph.nodes.get_key_value(dep) else {
                continue; // dep path not a known node (missing dir) — left to OOF-IMP2 on import
            };
            match color.get(dep_key).copied().unwrap_or(0) {
                1 => {
                    let pos = stack.iter().position(|s| *s == dep_key).unwrap_or(0);
                    let mut cyc: Vec<PathBuf> = stack[pos..].iter().map(|p| (*p).clone()).collect();
                    cyc.push((*dep_key).clone());
                    return Some(cyc);
                }
                0 => {
                    if let Some(c) = cycle_dfs(dep_key, graph, color, stack) {
                        return Some(c);
                    }
                }
                _ => {}
            }
        }
    }
    stack.pop();
    color.insert(node, 2);
    None
}

/// LAB-IGNITER-PACKAGE-TRANSITIVE-GRAPH-P14: a cycle in the local package graph (`OOF-IMP8`).
fn detect_cycle(graph: &PackageGraph) -> Option<ProjectDiagnostic> {
    let mut color: BTreeMap<&PathBuf, u8> = graph.nodes.keys().map(|k| (k, 0u8)).collect();
    for key in graph.nodes.keys() {
        if color.get(key).copied() == Some(0) {
            let mut stack = Vec::new();
            if let Some(cyc) = cycle_dfs(key, graph, &mut color, &mut stack) {
                let names: Vec<String> = cyc
                    .iter()
                    .map(|p| {
                        graph
                            .nodes
                            .get(p)
                            .map(|n| n.display.clone())
                            .unwrap_or_default()
                    })
                    .collect();
                let mut diag = ProjectDiagnostic::new(
                    "OOF-IMP8",
                    format!("dependency cycle in the local package graph: {}", names.join(" -> ")),
                    format!("cycle:{}", names.join("->")),
                );
                diag.source_paths = cyc.iter().map(|p| p.to_string_lossy().to_string()).collect();
                return Some(diag);
            }
        }
    }
    None
}

/// A relative path from `base` to `target` (both absolute + normalized), using `..` as needed. Stable across
/// machines (depends only on the workspace layout), so lock paths are reproducible.
fn relative_to(base: &Path, target: &Path) -> PathBuf {
    let b: Vec<Component> = base.components().collect();
    let t: Vec<Component> = target.components().collect();
    let mut i = 0;
    while i < b.len() && i < t.len() && b[i] == t[i] {
        i += 1;
    }
    let mut out = PathBuf::new();
    for _ in i..b.len() {
        out.push("..");
    }
    for c in &t[i..] {
        out.push(c.as_os_str());
    }
    if out.as_os_str().is_empty() {
        out.push(".");
    }
    out
}

fn collect_ig_files(dir: &Path, out: &mut Vec<PathBuf>) -> std::io::Result<()> {
    if !dir.is_dir() {
        return Ok(());
    }
    for entry in fs::read_dir(dir)? {
        let entry = entry?;
        let path = entry.path();
        let file_type = entry.file_type()?;
        let name = entry.file_name();
        let name = name.to_string_lossy();
        if file_type.is_dir() {
            // Ignore build/VCS/IDE dirs and any hidden directory.
            if IGNORED_DIRS.contains(&name.as_ref()) || name.starts_with('.') {
                continue;
            }
            collect_ig_files(&path, out)?;
        } else if file_type.is_file() && path.extension().and_then(|e| e.to_str()) == Some("ig") {
            out.push(path);
        }
    }
    Ok(())
}

/// Parse a single file just far enough to read its module + imports.
fn scan_file(path: &Path) -> std::io::Result<ScannedFile> {
    let source = fs::read_to_string(path)?;
    let mut lexer = Lexer::new(&source);
    let tokens = lexer.tokenize();
    let mut parser = Parser::new(tokens);
    let parsed = parser.parse();

    let module_path = parsed.module.clone().unwrap_or_default();
    let non_stdlib_imports: Vec<String> = parsed
        .imports
        .iter()
        .map(|i| i.module_path.clone())
        .filter(|m| !m.starts_with("stdlib."))
        .collect();

    Ok(ScannedFile {
        source_path: path.to_path_buf(),
        module_path,
        non_stdlib_imports,
        package: PackageId::Root, // caller overwrites with the scanning package
    })
}

/// LAB-COMPILER-PROJECT-OVERLAY-P2
/// Validate overlays and resolve them to normalized originals + readable buffers.
///
/// Deterministic: overlays are validated in sorted-by-original order, so the
/// first refusal is stable. Two refusal classes:
/// - `OOF-PROJ-OVERLAY-OUTSIDE`: original is not inside any configured source root.
/// - `OOF-PROJ-OVERLAY-MISSING`: overlay buffer file is unreadable.
fn validate_overlays(
    root: &Path,
    config: &ProjectConfig,
    overlays: &[ProjectOverlay],
) -> Result<Vec<ResolvedOverlay>, ProjectError> {
    // Absolute, normalized source roots for an inside-roots containment check.
    let abs_roots: Vec<PathBuf> = config
        .source_roots
        .iter()
        .map(|sr| {
            let joined = if sr == Path::new(".") {
                root.to_path_buf()
            } else {
                root.join(sr)
            };
            normalize_abs(&joined)
        })
        .collect();

    let mut sorted = overlays.to_vec();
    sorted.sort_by(|a, b| a.original_path.cmp(&b.original_path));

    let mut resolved = Vec::new();
    for ov in &sorted {
        let norm_original = normalize_abs(&ov.original_path);

        if !abs_roots.iter().any(|r| norm_original.starts_with(r)) {
            let mut diag = ProjectDiagnostic::new(
                "OOF-PROJ-OVERLAY-OUTSIDE",
                format!(
                    "overlay original path '{}' is not inside any project source root",
                    ov.original_path.to_string_lossy()
                ),
                "overlay".to_string(),
            );
            diag.original_path = Some(ov.original_path.to_string_lossy().to_string());
            diag.overlay_path = Some(ov.overlay_path.to_string_lossy().to_string());
            return Err(ProjectError::Diagnostic(diag));
        }

        if fs::read_to_string(&ov.overlay_path).is_err() {
            let mut diag = ProjectDiagnostic::new(
                "OOF-PROJ-OVERLAY-MISSING",
                format!(
                    "overlay buffer file '{}' could not be read",
                    ov.overlay_path.to_string_lossy()
                ),
                "overlay".to_string(),
            );
            diag.original_path = Some(ov.original_path.to_string_lossy().to_string());
            diag.overlay_path = Some(ov.overlay_path.to_string_lossy().to_string());
            return Err(ProjectError::Diagnostic(diag));
        }

        resolved.push(ResolvedOverlay {
            norm_original,
            overlay_path: ov.overlay_path.clone(),
        });
    }
    Ok(resolved)
}

/// Lexically absolutize and normalize a path (join cwd if relative; collapse
/// `.` and `..`). Does NOT touch the filesystem, so it works for not-yet-saved
/// overlay originals. Used only for overlay matching/containment, never for
/// the source evidence handed to compile_units.
fn normalize_abs(path: &Path) -> PathBuf {
    let abs = if path.is_absolute() {
        path.to_path_buf()
    } else {
        std::env::current_dir()
            .unwrap_or_else(|_| PathBuf::from("."))
            .join(path)
    };
    let mut out: Vec<std::ffi::OsString> = Vec::new();
    for comp in abs.components() {
        match comp {
            Component::ParentDir => {
                out.pop();
            }
            Component::CurDir => {}
            other => out.push(other.as_os_str().to_os_string()),
        }
    }
    out.iter().collect()
}

/// LAB-IGNITER-PACKAGE-WORKSPACE-RESOLVER-P2: extract local path dependencies from a `[dependencies]`
/// table. Each entry is `name = { path = "X" }` (canonical, future-proof for `version`/`git`) or the
/// shorthand `name = "X"`. Minimal hand-rolled parse (no toml crate); section-aware so only the
/// `[dependencies]` table is read. Returns the declared dependency paths in source order.
fn parse_dependencies_toml(content: &str) -> Vec<(String, String)> {
    let mut deps = Vec::new();
    let mut in_deps = false;
    for line in content.lines() {
        let line = line.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        if line.starts_with('[') {
            in_deps = line == "[dependencies]";
            continue;
        }
        if !in_deps {
            continue;
        }
        let Some((name, value)) = line.split_once('=') else {
            continue;
        };
        let name = name.trim().to_string();
        let value = value.trim();
        // Bare string `"X"`: take it directly. Inline table `{ path = "X" }`: anchor on the `path` key.
        // Check the bare-string case first so a path like "../pathlib" is not mistaken for a table key.
        let path = if value.starts_with('"') || value.starts_with('\'') {
            first_quoted(value)
        } else if let Some(pos) = value.find("path") {
            let after_key = &value[pos + "path".len()..];
            after_key
                .split_once('=')
                .and_then(|(_, v)| first_quoted(v))
        } else {
            None
        };
        if let Some(p) = path {
            if !p.is_empty() && !name.is_empty() {
                deps.push((name, p));
            }
        }
    }
    deps
}

/// Content of the first `"..."` (or `'...'`) quoted token in `s`, if any.
fn first_quoted(s: &str) -> Option<String> {
    let bytes = s.as_bytes();
    let start = bytes.iter().position(|&b| b == b'"' || b == b'\'')?;
    let quote = bytes[start];
    let rest = &s[start + 1..];
    let end = rest.bytes().position(|b| b == quote)?;
    Some(rest[..end].to_string())
}

/// LAB-IGNITER-PACKAGE-MODULE-EXPORTS-P10
/// Parse a dependency's `[exports] modules = ["A", "B"]` allowlist. Section-scoped, hand-rolled (no toml
/// crate), mirroring `parse_dependencies_toml`. Returns:
/// - `None` if there is **no** `[exports]` section (package is open / backward-compatible);
/// - `Some(list)` if the section is present (possibly empty `modules`, or no `modules` key ⇒ `Some([])`,
///   a deliberately sealed package). Exact module paths only — no globs.
fn parse_exports_toml(content: &str) -> Option<Vec<String>> {
    let mut in_exports = false;
    let mut seen_section = false;
    let mut modules = Vec::new();
    for line in content.lines() {
        let line = line.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        if line.starts_with('[') {
            in_exports = line == "[exports]";
            if in_exports {
                seen_section = true;
            }
            continue;
        }
        if !in_exports {
            continue;
        }
        // `modules = ["A", "B"]` — same array shape as source_roots.
        let Some(rest) = line.strip_prefix("modules") else {
            continue;
        };
        let Some(rest) = rest.trim_start().strip_prefix('=') else {
            continue;
        };
        let inner = rest.trim().trim_start_matches('[').trim_end_matches(']');
        modules = inner
            .split(',')
            .map(|s| s.trim().trim_matches('"').trim_matches('\'').to_string())
            .filter(|s| !s.is_empty())
            .collect();
    }
    if seen_section {
        Some(modules)
    } else {
        None
    }
}

/// LAB-IGNITER-PACKAGE-EXPORTS-CLOSED-DEFAULT-P12
/// Parse the root consumer policy `[package] exports = "open" | "closed"`. Section-scoped, hand-rolled.
/// Defaults to `Open` (absent section / key / unrecognized value), so existing manifests are unchanged.
fn parse_package_exports_default(content: &str) -> ExportsDefault {
    let mut in_package = false;
    for line in content.lines() {
        let line = line.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        if line.starts_with('[') {
            in_package = line == "[package]";
            continue;
        }
        if !in_package {
            continue;
        }
        let Some(rest) = line.strip_prefix("exports") else {
            continue;
        };
        let Some(rest) = rest.trim_start().strip_prefix('=') else {
            continue;
        };
        let value = rest.trim().trim_matches('"').trim_matches('\'');
        if value == "closed" {
            return ExportsDefault::Closed;
        }
    }
    ExportsDefault::Open
}

/// Minimal `source_roots = ["a", "b"]` extractor. Not a general TOML parser.
fn parse_source_roots_toml(content: &str) -> Option<Vec<String>> {
    for line in content.lines() {
        let line = line.trim();
        if line.starts_with('#') {
            continue;
        }
        let Some(rest) = line.strip_prefix("source_roots") else {
            continue;
        };
        let rest = rest.trim_start();
        let Some(rest) = rest.strip_prefix('=') else {
            continue;
        };
        let rest = rest.trim();
        let inner = rest.trim_start_matches('[').trim_end_matches(']');
        let roots: Vec<String> = inner
            .split(',')
            .map(|s| s.trim().trim_matches('"').trim_matches('\'').to_string())
            .filter(|s| !s.is_empty())
            .collect();
        return Some(roots);
    }
    None
}
