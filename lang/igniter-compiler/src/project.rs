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
use std::collections::BTreeMap;
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
        }
        ProjectConfig {
            source_roots,
            dependencies,
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

/// One scanned source file: its logical module path and its non-stdlib imports.
#[derive(Debug, Clone)]
struct ScannedFile {
    source_path: PathBuf,
    module_path: String,
    /// Non-stdlib imported module paths (logical). stdlib imports are dropped
    /// here because they are not file dependencies.
    non_stdlib_imports: Vec<String>,
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

    // Duplicate module declarations are a project-assembly fault: the index is
    // ambiguous. Surface deterministically (OOF-IMP4) with all source paths.
    if let Some((module, paths)) = index.duplicates.iter().next() {
        let mut diag = ProjectDiagnostic::new(
            "OOF-IMP4",
            format!("duplicate module declaration '{}'", module),
            format!("module:{}", module),
        );
        diag.module_path = Some(module.clone());
        diag.source_paths = paths.clone();
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

/// LAB-IGNITER-PACKAGE-VERSION-PROVENANCE-P5.
/// The toolchain that produced a lock. v0 pins the compiler version (`env!("CARGO_PKG_VERSION")`).
/// `stdlib` and lowerer versions are deferred because the compiler has no authoritative constants for them yet.
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct Toolchain {
    /// `igniter_compiler` crate version at lock time. Empty = unpinned (a pre-P5 lock).
    pub compiler: String,
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
    }
}

impl WorkspaceLock {
    /// Deterministic JSON for the lockfile (name-sorted, stable field order).
    pub fn to_value(&self) -> Value {
        json!({
            "version": 1,
            "toolchain": { "compiler": self.toolchain.compiler },
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
        let toolchain = Toolchain {
            compiler: v
                .get("toolchain")
                .and_then(|t| t.get("compiler"))
                .and_then(|c| c.as_str())
                .unwrap_or("")
                .to_string(),
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

/// Compute the per-workspace lock: one `sha256` content digest per declared dependency, name-sorted for
/// determinism. Direct dependencies only (a dependency's own `[dependencies]` are not digested here).
pub fn workspace_lock(root: &Path) -> Result<WorkspaceLock, ProjectError> {
    let config = ProjectConfig::load(root);
    let mut deps: Vec<&Dependency> = config.dependencies.iter().collect();
    deps.sort_by(|a, b| a.name.cmp(&b.name));
    let mut locked = Vec::with_capacity(deps.len());
    for dep in deps {
        let dep_root = root.join(&dep.path);
        locked.push(LockedDependency {
            name: dep.name.clone(),
            path: dep.path.to_string_lossy().to_string(),
            digest: dependency_digest(&dep_root)?,
        });
    }
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
    // Toolchain drift first — only when the lock actually pinned the compiler (empty compiler is an
    // unpinned pre-P5 lock = "no claim", so it never reports drift).
    if !lock.toolchain.compiler.is_empty() && lock.toolchain.compiler != current.toolchain.compiler {
        drifts.push(LockDrift::Toolchain {
            field: "compiler".to_string(),
            locked: lock.toolchain.compiler.clone(),
            actual: current.toolchain.compiler.clone(),
        });
    }
    for cur in &current.dependencies {
        match lock.dependencies.iter().find(|d| d.name == cur.name) {
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
        if !current.dependencies.iter().any(|c| c.name == locked.name) {
            drifts.push(LockDrift::Missing {
                name: locked.name.clone(),
            });
        }
    }
    Ok(drifts)
}

/// `sha256` over a dependency's sorted source files. Each file contributes its **relative** path
/// (location-independent) followed by its raw content; files are sorted so the digest is deterministic.
fn dependency_digest(dep_root: &Path) -> Result<String, ProjectError> {
    let dep_config = ProjectConfig::load(dep_root);
    let mut files: Vec<PathBuf> = Vec::new();
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
    let mut files: Vec<PathBuf> = Vec::new();
    for source_root in &config.source_roots {
        // Avoid a spurious "./" segment when the source root is the project root.
        let scan_root = if source_root == Path::new(".") {
            root.to_path_buf()
        } else {
            root.join(source_root)
        };
        collect_ig_files(&scan_root, &mut files)?;
    }

    // LAB-IGNITER-PACKAGE-WORKSPACE-RESOLVER-P2: fold each declared LOCAL path dependency's source roots
    // into the SAME file set, so cross-package `import Foo.Bar` resolves and duplicate module ownership
    // across packages is caught by the existing OOF-IMP4 check below. Direct dependencies only — a
    // dependency's own `[dependencies]` are NOT traversed in v0 (no transitive package graph).
    for dep in &config.dependencies {
        let dep_root = root.join(&dep.path);
        let dep_config = ProjectConfig::load(&dep_root);
        for source_root in &dep_config.source_roots {
            let scan_root = if source_root == Path::new(".") {
                dep_root.clone()
            } else {
                dep_root.join(source_root)
            };
            collect_ig_files(&scan_root, &mut files)?;
        }
    }

    // Inject overlay originals that are not present on disk (new unsaved files).
    let scanned_norms: std::collections::HashSet<PathBuf> =
        files.iter().map(|p| normalize_abs(p)).collect();
    for ov in overlays {
        if !scanned_norms.contains(&ov.norm_original) {
            files.push(ov.norm_original.clone());
        }
    }

    // Deterministic scan order independent of filesystem enumeration.
    files.sort();
    files.dedup();

    let mut by_module: BTreeMap<String, ScannedFile> = BTreeMap::new();
    let mut dup_acc: BTreeMap<String, Vec<String>> = BTreeMap::new();

    for path in files {
        // If this file is overlaid, read the overlay buffer instead of disk.
        // The overlay path also becomes the effective source path handed to
        // compile_units, so source evidence honestly carries the temp path.
        let np = normalize_abs(&path);
        let read_path = overlays
            .iter()
            .find(|ov| ov.norm_original == np)
            .map(|ov| ov.overlay_path.clone())
            .unwrap_or_else(|| path.clone());

        let scanned = scan_file(&read_path)?;
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
    })
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
