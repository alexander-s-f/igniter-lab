// LAB-IGNITER-PACKAGE-LOCKFILE-CLI-P4
//
// End-to-end tests for `igc lock` / `igc verify` over the P3 `workspace_lock`/`verify_lock` API. The lock
// is written into the project root (`igniter.lock`), so every test COPIES the `workspace` fixture into a
// fresh tempdir and runs there — the version-controlled fixture tree is never written to.

use serde_json::Value;
use std::path::{Path, PathBuf};
use std::process::Command;

fn bin() -> &'static str {
    env!("CARGO_BIN_EXE_igniter_compiler")
}

/// Recursively copy a directory tree.
fn copy_tree(src: &Path, dst: &Path) {
    std::fs::create_dir_all(dst).unwrap();
    for entry in std::fs::read_dir(src).unwrap() {
        let entry = entry.unwrap();
        let from = entry.path();
        let to = dst.join(entry.file_name());
        if entry.file_type().unwrap().is_dir() {
            copy_tree(&from, &to);
        } else {
            std::fs::copy(&from, &to).unwrap();
        }
    }
}

/// Copy the `workspace` fixture (app + lib) into a unique tempdir; return the app root to run against.
fn temp_workspace(tag: &str) -> PathBuf {
    temp_fixture("workspace", tag)
}

/// Copy an arbitrary `project_mode/<fixture>` tree into a unique tempdir; return its `app` root.
fn temp_fixture(fixture: &str, tag: &str) -> PathBuf {
    let base = std::env::temp_dir().join(format!("igc_lock_{}_{}", tag, std::process::id()));
    let _ = std::fs::remove_dir_all(&base);
    copy_tree(
        Path::new(&format!("tests/fixtures/project_mode/{fixture}")),
        &base,
    );
    base.join("app")
}

/// Run `igc <cmd> --project-root <root>`; return (success, parsed-stdout-json).
fn run(cmd: &str, root: &Path) -> (bool, Value) {
    run_args(&[cmd, "--project-root", root.to_str().unwrap()])
}

/// Run `igc` with explicit args; return (success, parsed-stdout-json).
fn run_args(args: &[&str]) -> (bool, Value) {
    let output = Command::new(bin())
        .args(args)
        .output()
        .expect("run igniter_compiler");
    let stdout = String::from_utf8_lossy(&output.stdout);
    let v: Value = serde_json::from_str(&stdout).unwrap_or(Value::Null);
    (output.status.success(), v)
}

#[test]
fn cli_lock_then_verify_clean() {
    let root = temp_workspace("clean");
    let (ok, v) = run("lock", &root);
    assert!(ok, "lock exits 0");
    assert_eq!(v["written"], Value::Bool(true));
    assert_eq!(v["dependencies"], serde_json::json!(1));
    assert!(root.join("igniter.lock").exists(), "igniter.lock written");

    let (ok, v) = run("verify", &root);
    assert!(ok, "verify exits 0 on a clean workspace");
    assert_eq!(v["ok"], Value::Bool(true));
    assert!(v["drift"].as_array().unwrap().is_empty(), "no drift: {v}");
}

#[test]
fn cli_lock_is_idempotent() {
    let root = temp_workspace("idem");
    run("lock", &root);
    let a = std::fs::read(root.join("igniter.lock")).unwrap();
    run("lock", &root);
    let b = std::fs::read(root.join("igniter.lock")).unwrap();
    assert_eq!(
        a, b,
        "re-running `lock` produces a byte-identical igniter.lock"
    );
}

#[test]
fn cli_verify_detects_drift() {
    let root = temp_workspace("drift");
    run("lock", &root);
    // Mutate a dependency source file (the lock was over `../lib`'s content).
    let dep_file = root.join("../lib/src/util.ig");
    let mut content = std::fs::read_to_string(&dep_file).unwrap();
    content.push_str("\n-- drift\n");
    std::fs::write(&dep_file, content).unwrap();

    let (ok, v) = run("verify", &root);
    assert!(!ok, "verify exits non-zero on drift");
    assert_eq!(v["ok"], Value::Bool(false));
    let drift = v["drift"].as_array().unwrap();
    assert_eq!(drift.len(), 1, "one drift: {v}");
    assert_eq!(drift[0]["kind"], serde_json::json!("changed"));
    assert_eq!(drift[0]["name"], serde_json::json!("lib"));
}

#[test]
fn cli_verify_missing_lockfile_fails() {
    let root = temp_workspace("missing");
    // No `igc lock` run → no igniter.lock.
    let output = Command::new(bin())
        .args(["verify", "--project-root", root.to_str().unwrap()])
        .output()
        .expect("run igniter_compiler");
    assert!(
        !output.status.success(),
        "verify without a lockfile exits non-zero"
    );
}

/// LAB-IGNITER-PACKAGE-VERSION-PROVENANCE-P5: tampering the lock's pinned compiler version on disk makes
/// `igc verify` report a `toolchain` drift and exit non-zero.
#[test]
fn cli_verify_detects_toolchain_drift() {
    let root = temp_workspace("toolchain");
    run("lock", &root);
    // Rewrite the on-disk lock to pin a bogus compiler version.
    let lock_path = root.join("igniter.lock");
    let mut v: Value = serde_json::from_str(&std::fs::read_to_string(&lock_path).unwrap()).unwrap();
    v["toolchain"]["compiler"] = Value::String("0.0.0-bogus".to_string());
    std::fs::write(&lock_path, serde_json::to_string_pretty(&v).unwrap()).unwrap();

    let (ok, out) = run("verify", &root);
    assert!(!ok, "verify exits non-zero on toolchain drift");
    let drift = out["drift"].as_array().unwrap();
    let tc = drift
        .iter()
        .find(|d| d["kind"] == serde_json::json!("toolchain"));
    let tc = tc.unwrap_or_else(|| panic!("expected a toolchain drift: {out}"));
    assert_eq!(tc["field"], serde_json::json!("compiler"));
    assert_eq!(tc["locked"], serde_json::json!("0.0.0-bogus"));
}

/// LAB-IGNITER-PACKAGE-STDLIB-VERSION-CONSTANT-P6: `igc lock` writes `toolchain.stdlib`; tampering it on
/// disk makes `igc verify` report a `toolchain` drift with `field:"stdlib"` and exit non-zero.
#[test]
fn cli_lock_writes_stdlib_and_verify_detects_stdlib_drift() {
    let root = temp_workspace("stdlib");
    run("lock", &root);
    let lock_path = root.join("igniter.lock");
    let mut v: Value = serde_json::from_str(&std::fs::read_to_string(&lock_path).unwrap()).unwrap();
    assert!(
        v["toolchain"]["stdlib"]
            .as_str()
            .is_some_and(|s| !s.is_empty()),
        "lock writes a non-empty toolchain.stdlib: {v}"
    );
    v["toolchain"]["stdlib"] = Value::String("0.0.0-bogus-stdlib".to_string());
    std::fs::write(&lock_path, serde_json::to_string_pretty(&v).unwrap()).unwrap();

    let (ok, out) = run("verify", &root);
    assert!(!ok, "verify exits non-zero on stdlib drift");
    let drift = out["drift"].as_array().unwrap();
    let tc = drift
        .iter()
        .find(|d| {
            d["kind"] == serde_json::json!("toolchain") && d["field"] == serde_json::json!("stdlib")
        })
        .unwrap_or_else(|| panic!("expected a stdlib toolchain drift: {out}"));
    assert_eq!(tc["locked"], serde_json::json!("0.0.0-bogus-stdlib"));
}

// ── LAB-IGNITER-PACKAGE-LOCKFILE-FROZEN-CI-P8 ───────────────────────────────────────────────────────

fn root_arg(root: &Path) -> String {
    root.to_str().unwrap().to_string()
}

/// `igc lock --frozen` passes (exit 0, ok:true) when the committed lock is current, without rewriting it.
#[test]
fn cli_lock_frozen_passes_when_current() {
    let root = temp_workspace("frozen_ok");
    run("lock", &root);
    let before = std::fs::read(root.join("igniter.lock")).unwrap();
    let (ok, v) = run_args(&["lock", "--project-root", &root_arg(&root), "--frozen"]);
    assert!(ok, "frozen passes when current: {v}");
    assert_eq!(v["ok"], Value::Bool(true));
    assert_eq!(v["reason"], serde_json::json!("up-to-date"));
    assert_eq!(v["written"], Value::Bool(false));
    let after = std::fs::read(root.join("igniter.lock")).unwrap();
    assert_eq!(before, after, "frozen must not rewrite the lockfile");
}

/// `igc lock --frozen` fails (exit 1, reason missing) when there is no committed lock, and never writes one.
#[test]
fn cli_lock_frozen_fails_when_missing() {
    let root = temp_workspace("frozen_missing");
    let (ok, v) = run_args(&["lock", "--project-root", &root_arg(&root), "--frozen"]);
    assert!(!ok, "frozen fails when no lockfile");
    assert_eq!(v["reason"], serde_json::json!("missing"));
    assert!(
        !root.join("igniter.lock").exists(),
        "frozen must not create a lockfile"
    );
}

/// `igc lock --frozen` fails (reason out-of-date) when the workspace drifted, leaving the lock untouched.
#[test]
fn cli_lock_frozen_fails_when_stale() {
    let root = temp_workspace("frozen_stale");
    run("lock", &root);
    let before = std::fs::read(root.join("igniter.lock")).unwrap();
    // Drift a dependency source file.
    let dep_file = root.join("../lib/src/util.ig");
    let mut c = std::fs::read_to_string(&dep_file).unwrap();
    c.push_str("\n-- drift\n");
    std::fs::write(&dep_file, c).unwrap();

    let (ok, v) = run_args(&["lock", "--project-root", &root_arg(&root), "--frozen"]);
    assert!(!ok, "frozen fails when stale");
    assert_eq!(v["reason"], serde_json::json!("out-of-date"));
    let after = std::fs::read(root.join("igniter.lock")).unwrap();
    assert_eq!(before, after, "frozen must not rewrite a stale lockfile");
}

/// `igc verify --strict` catches a phantom import that plain `verify` (drift-only) does not — the strict
/// gate adds workspace-assembly integrity (OOF-IMP6) on top of lock drift.
#[test]
fn cli_verify_strict_catches_phantom() {
    let root = temp_fixture("workspace_phantom", "strict_phantom");
    run("lock", &root); // lock only digests deps; the phantom does not affect digests, so this succeeds

    // Plain verify: no drift → passes (it does NOT assemble the workspace).
    let (ok_plain, _) = run("verify", &root);
    assert!(
        ok_plain,
        "plain verify is drift-only and passes despite the phantom import"
    );

    // Strict verify: integrity fails on OOF-IMP6.
    let (ok_strict, v) = run_args(&["verify", "--project-root", &root_arg(&root), "--strict"]);
    assert!(!ok_strict, "strict verify fails on phantom import: {v}");
    assert_eq!(v["ok"], Value::Bool(false));
    assert_eq!(v["integrity"]["ok"], Value::Bool(false));
    assert_eq!(
        v["integrity"]["diagnostic"]["rule"],
        serde_json::json!("OOF-IMP6")
    );
}

/// `igc verify --strict` passes on a clean, current workspace (drift-clean + integrity-clean).
#[test]
fn cli_verify_strict_passes_clean() {
    let root = temp_workspace("strict_clean");
    run("lock", &root);
    let (ok, v) = run_args(&["verify", "--project-root", &root_arg(&root), "--strict"]);
    assert!(ok, "strict verify passes on a clean workspace: {v}");
    assert_eq!(v["ok"], Value::Bool(true));
    assert_eq!(v["integrity"]["ok"], Value::Bool(true));
}

// ── LAB-IGNITER-PACKAGE-MODULE-EXPORTS-P10 ──────────────────────────────────────────────────────────

/// `igc verify --strict` catches a non-exported dependency-module import (OOF-IMP7); plain `verify` is
/// drift-only and passes.
#[test]
fn cli_verify_strict_catches_non_export() {
    let root = temp_fixture("workspace_exports_private", "strict_export");
    run("lock", &root);

    let (ok_plain, _) = run("verify", &root);
    assert!(
        ok_plain,
        "plain verify is drift-only and passes despite the non-exported import"
    );

    let (ok_strict, v) = run_args(&["verify", "--project-root", &root_arg(&root), "--strict"]);
    assert!(
        !ok_strict,
        "strict verify fails on non-exported import: {v}"
    );
    assert_eq!(v["integrity"]["ok"], Value::Bool(false));
    assert_eq!(
        v["integrity"]["diagnostic"]["rule"],
        serde_json::json!("OOF-IMP7")
    );
}

/// LAB-IGNITER-PACKAGE-EXPORTS-CI-P11: the strict integrity diagnostic is **structured** — CI/agents read
/// importer/imported/package/path as fields (`rule`, `node`, `module_path`, `source_paths`), not by parsing
/// `message`.
#[test]
fn cli_verify_strict_integrity_is_structured() {
    let root = temp_fixture("workspace_exports_private", "strict_structured");
    run("lock", &root);
    let (ok, v) = run_args(&["verify", "--project-root", &root_arg(&root), "--strict"]);
    assert!(!ok, "non-exported import fails strict verify: {v}");
    let d = &v["integrity"]["diagnostic"];
    assert_eq!(d["rule"], serde_json::json!("OOF-IMP7"));
    assert_eq!(
        d["module_path"],
        serde_json::json!("App.Main"),
        "importer module as a field"
    );
    assert_eq!(
        d["node"],
        serde_json::json!("export:App.Main->Lib.Private"),
        "importer→imported edge as a field"
    );
    assert!(
        d["source_paths"].as_array().is_some_and(|a| a.len() == 1),
        "importer source path as a field: {d}"
    );
    // The human message is still present alongside the structured fields.
    assert!(
        d["message"]
            .as_str()
            .is_some_and(|m| m.contains("Lib.Private")),
        "{d}"
    );
}

// ── LAB-IGNITER-PACKAGE-ARCHIVE-PACK-VERIFY-P22 ─────────────────────────────────────────────────────

fn igpkg_path(tag: &str) -> PathBuf {
    std::env::temp_dir().join(format!("igc_p22_{}_{}.igpkg", tag, std::process::id()))
}

/// `pack` a clean workspace then `verify` it: source-only archive, digests match, integrity clean.
#[test]
fn cli_pack_then_verify_clean() {
    let out = igpkg_path("clean");
    let (ok, p) = run_args(&[
        "package",
        "pack",
        "--project-root",
        &format!("{FIX_DIR}/workspace_transitive_ok/app"),
        "--out",
        out.to_str().unwrap(),
    ]);
    assert!(ok, "pack ok: {p}");
    assert!(
        p["files"].as_u64().unwrap() >= 6,
        "all reachable packages packed: {p}"
    );
    assert!(p["digest"].as_str().unwrap().starts_with("sha256:"));

    let (vok, v) = run_args(&["package", "verify", out.to_str().unwrap()]);
    assert!(vok, "verify clean: {v}");
    assert_eq!(v["ok"], Value::Bool(true));
    assert_eq!(v["digest_ok"], Value::Bool(true));
    assert_eq!(v["integrity"]["ok"], Value::Bool(true));
    assert_eq!(
        v["digest"], p["digest"],
        "verify recomputes the same tree digest"
    );
}

/// `pack` is deterministic — two runs produce a byte-identical archive.
#[test]
fn cli_pack_is_deterministic() {
    let a = igpkg_path("det_a");
    let b = igpkg_path("det_b");
    let args = |o: &str| {
        run_args(&[
            "package",
            "pack",
            "--project-root",
            &format!("{FIX_DIR}/workspace_transitive_diamond/app"),
            "--out",
            o,
        ])
    };
    args(a.to_str().unwrap());
    args(b.to_str().unwrap());
    assert_eq!(
        std::fs::read(&a).unwrap(),
        std::fs::read(&b).unwrap(),
        "the .igpkg must be byte-identical across runs"
    );
}

/// `verify` detects a tampered archive (a flipped content byte) — digest mismatch, exit 1.
#[test]
fn cli_verify_detects_tampered_archive() {
    let out = igpkg_path("tamper");
    run_args(&[
        "package",
        "pack",
        "--project-root",
        &format!("{FIX_DIR}/workspace_transitive_ok/app"),
        "--out",
        out.to_str().unwrap(),
    ]);
    let mut bytes = std::fs::read(&out).unwrap();
    let last = bytes.len() - 1;
    bytes[last] ^= 1;
    std::fs::write(&out, &bytes).unwrap();

    let (ok, v) = run_args(&["package", "verify", out.to_str().unwrap()]);
    assert!(!ok, "tampered archive must fail verify: {v}");
    assert_eq!(v["digest_ok"], Value::Bool(false));
}

/// `verify` runs workspace integrity on the unpacked tree — a phantom-import archive fails with `OOF-IMP6`.
#[test]
fn cli_verify_detects_integrity_fault() {
    let out = igpkg_path("integ");
    run_args(&[
        "package",
        "pack",
        "--project-root",
        &format!("{FIX_DIR}/workspace_phantom/app"),
        "--out",
        out.to_str().unwrap(),
    ]);
    let (ok, v) = run_args(&["package", "verify", out.to_str().unwrap()]);
    assert!(!ok, "phantom archive fails verify: {v}");
    assert_eq!(v["integrity"]["ok"], Value::Bool(false));
    assert_eq!(
        v["integrity"]["diagnostic"]["rule"],
        serde_json::json!("OOF-IMP6")
    );
}

/// `pack` on a workspace with a missing dependency is a structured `OOF-IMP9` error, exit 1.
#[test]
fn cli_pack_missing_dep_errors() {
    let out = igpkg_path("missing");
    let (ok, p) = run_args(&[
        "package",
        "pack",
        "--project-root",
        &format!("{FIX_DIR}/workspace_missing_root_dep/app"),
        "--out",
        out.to_str().unwrap(),
    ]);
    assert!(!ok, "pack fails on a missing dependency: {p}");
    assert_eq!(p["error"]["rule"], serde_json::json!("OOF-IMP9"));
    assert!(!out.exists(), "no archive written on assembly failure");
}

/// The allowlist holds: stray non-source files (a secret, a compiled `.igapp`, a shell script) are NOT packed.
#[test]
fn cli_pack_allowlist_excludes_nonsource() {
    let root = temp_fixture("workspace_transitive_ok", "p22_allow");
    std::fs::write(root.join("secret.env"), "SECRET=topsecret\n").unwrap();
    std::fs::write(root.join("app.igapp"), "compiled-binary\n").unwrap();
    std::fs::write(root.join("build.sh"), "#!/bin/sh\nrm -rf /\n").unwrap();
    let out = igpkg_path("allow");
    let (ok, _) = run_args(&[
        "package",
        "pack",
        "--project-root",
        &root_arg(&root),
        "--out",
        out.to_str().unwrap(),
    ]);
    assert!(ok, "pack succeeds");
    let archive = String::from_utf8_lossy(&std::fs::read(&out).unwrap()).to_string();
    assert!(!archive.contains("SECRET=topsecret"), "secret not packed");
    assert!(
        !archive.contains("app.igapp"),
        "compiled artifact not packed"
    );
    assert!(!archive.contains("build.sh"), "script not packed");
}

// ── LAB-IGNITER-PACKAGE-DIAGNOSTIC-DETAILS-P19 ──────────────────────────────────────────────────────

/// `verify --strict` surfaces the OOF-IMP7 `details` block (import-explain enrichment) under
/// `integrity.diagnostic.details`.
#[test]
fn cli_verify_strict_integrity_carries_details() {
    let root = temp_fixture("workspace_exports_private", "p19_details");
    run("lock", &root);
    let (ok, v) = run_args(&["verify", "--project-root", &root_arg(&root), "--strict"]);
    assert!(!ok, "strict fails on non-exported import: {v}");
    let det = &v["integrity"]["diagnostic"]["details"];
    assert_eq!(det["kind"], serde_json::json!("import_export"));
    assert_eq!(det["provider"]["package"], serde_json::json!("lib"));
    assert!(
        det["fix"].as_str().is_some_and(|f| f.contains("[exports]")),
        "fix present: {det}"
    );
}

// ── LAB-IGNITER-PACKAGE-GRAPH-CLI-P18 (read-only `igc package graph`; runs on fixtures in place) ──────

const FIX_DIR: &str = "tests/fixtures/project_mode";

fn graph(fixture: &str) -> (bool, Value) {
    run_args(&[
        "package",
        "graph",
        "--project-root",
        &format!("{FIX_DIR}/{fixture}/app"),
    ])
}

/// `igc package graph` emits the full assembled graph: root + mid + leaf, with the `<root>→mid` and
/// `mid→leaf` edges, sorted by path, no faults.
#[test]
fn cli_package_graph_emits_full_graph() {
    let (ok, v) = graph("workspace_transitive_ok");
    assert!(ok, "graph exits 0 on a clean workspace: {v}");
    assert_eq!(v["kind"], serde_json::json!("igniter_package_graph"));
    let pkgs = v["packages"].as_array().unwrap();
    let labels: Vec<&str> = pkgs.iter().map(|p| p["label"].as_str().unwrap()).collect();
    assert_eq!(
        labels,
        vec!["<root>", "leaf", "mid"],
        "packages sorted by path: {labels:?}"
    );
    // root → mid edge
    let root_pkg = pkgs
        .iter()
        .find(|p| p["label"] == serde_json::json!("<root>"))
        .unwrap();
    assert_eq!(
        root_pkg["dependencies"][0]["label"],
        serde_json::json!("mid")
    );
    // mid → leaf edge
    let mid_pkg = pkgs
        .iter()
        .find(|p| p["label"] == serde_json::json!("mid"))
        .unwrap();
    assert_eq!(
        mid_pkg["dependencies"][0]["label"],
        serde_json::json!("leaf")
    );
    assert!(v["faults"].as_array().unwrap().is_empty());
}

/// A diamond emits the shared package exactly once (as a package node), with two parent edges.
#[test]
fn cli_package_graph_diamond_dedups() {
    let (ok, v) = graph("workspace_transitive_diamond");
    assert!(ok);
    let c_nodes = v["packages"]
        .as_array()
        .unwrap()
        .iter()
        .filter(|p| p["label"] == serde_json::json!("c"))
        .count();
    assert_eq!(c_nodes, 1, "shared package `c` is one node: {v}");
}

/// Closed-default policy is exposed at the top level.
#[test]
fn cli_package_graph_exposes_closed_default() {
    let (ok, v) = graph("workspace_closed_default");
    assert!(ok);
    assert_eq!(v["exports_default"], serde_json::json!("closed"));
}

/// Sealed (`[exports] modules = []`) and allowlist exports render with the right `mode`.
#[test]
fn cli_package_graph_renders_exports_modes() {
    // `workspace_exports_ok/lib` declares an allowlist; assert it renders as such.
    let (ok, v) = graph("workspace_exports_ok");
    assert!(ok);
    let lib = v["packages"]
        .as_array()
        .unwrap()
        .iter()
        .find(|p| p["label"] == serde_json::json!("lib"))
        .unwrap();
    assert_eq!(lib["exports"]["mode"], serde_json::json!("allowlist"));
    assert_eq!(
        lib["exports"]["modules"][0],
        serde_json::json!("Lib.Public")
    );
}

/// A cycle emits the FULL graph plus a `faults` entry with `OOF-IMP8`, and still exits 0 (graph is a view;
/// `verify --strict` is the failing gate).
#[test]
fn cli_package_graph_cycle_emits_faults_exit_zero() {
    let (ok, v) = graph("workspace_transitive_cycle");
    assert!(ok, "graph view exits 0 even with a cycle: {v}");
    assert!(
        !v["packages"].as_array().unwrap().is_empty(),
        "full graph still emitted"
    );
    let faults = v["faults"].as_array().unwrap();
    assert_eq!(faults.len(), 1, "one fault: {v}");
    assert_eq!(faults[0]["rule"], serde_json::json!("OOF-IMP8"));
}

/// A missing dependency path is a structured `OOF-IMP9` error with exit 1 (assembly cannot proceed).
#[test]
fn cli_package_graph_missing_dep_errors() {
    let (ok, v) = graph("workspace_missing_root_dep");
    assert!(!ok, "graph exits 1 on a missing dependency: {v}");
    assert_eq!(v["ok"], Value::Bool(false));
    assert_eq!(v["error"]["rule"], serde_json::json!("OOF-IMP9"));
}

/// Output is deterministic across runs.
#[test]
fn cli_package_graph_is_deterministic() {
    let (_, a) = graph("workspace_transitive_diamond");
    let (_, b) = graph("workspace_transitive_diamond");
    assert_eq!(a, b, "graph JSON must be deterministic");
}

// ── LAB-IGNITER-PACKAGE-MISSING-DEP-DIAGNOSTIC-P16 ──────────────────────────────────────────────────

/// `igc lock` fails with a structured `OOF-IMP9` when a declared dependency path is missing (the graph
/// cannot be assembled, so no lock is written).
#[test]
fn cli_lock_reports_missing_dep_structurally() {
    let root = temp_fixture("workspace_missing_root_dep", "p16_lock_missing");
    let (ok, v) = run("lock", &root);
    assert!(!ok, "lock fails on a missing dependency: {v}");
    assert_eq!(v["ok"], Value::Bool(false));
    assert_eq!(v["written"], Value::Bool(false));
    assert_eq!(v["error"]["rule"], serde_json::json!("OOF-IMP9"));
    assert!(
        !root.join("igniter.lock").exists(),
        "no lockfile written on assembly failure"
    );
}

/// `igc verify --strict` surfaces a structured `OOF-IMP9` (graph assembly fails before drift/integrity).
#[test]
fn cli_verify_strict_reports_missing_dep_structurally() {
    let root = temp_fixture("workspace_missing_transitive_dep", "p16_verify_missing");
    // No prior lock can be produced; verify reads no lockfile → still must fail clearly. Write a stub lock so
    // verify reaches the assemble step, then assert the structured OOF-IMP9 error.
    std::fs::write(
        root.join("igniter.lock"),
        "{\"version\":1,\"toolchain\":{\"compiler\":\"\",\"stdlib\":\"\"},\"dependencies\":[]}\n",
    )
    .unwrap();
    let (ok, v) = run_args(&["verify", "--project-root", &root_arg(&root), "--strict"]);
    assert!(!ok, "verify fails on a missing transitive dependency: {v}");
    assert_eq!(v["error"]["rule"], serde_json::json!("OOF-IMP9"));
    assert_eq!(
        v["error"]["node"],
        serde_json::json!("dependency:mid->ghost")
    );
}

// ── LAB-IGNITER-PACKAGE-TRANSITIVE-GRAPH-CI-P15 (regression-locking P14's CI guarantees) ─────────────

/// A transitive leaf's MANIFEST change (its `igniter.toml`, folded into the digest) is lock drift.
#[test]
fn cli_leaf_manifest_change_is_drift() {
    let root = temp_fixture("workspace_transitive_ok", "p15_leaf_manifest");
    run("lock", &root);
    let leaf_manifest = root.join("../leaf/igniter.toml");
    let edited = std::fs::read_to_string(&leaf_manifest)
        .unwrap()
        .replace("\"Leaf.Public\"", "\"Leaf.Public\", \"Leaf.Extra\"");
    std::fs::write(&leaf_manifest, edited).unwrap();
    let (ok, v) = run("verify", &root);
    assert!(!ok, "leaf manifest change must be drift: {v}");
    assert!(
        v["drift"]
            .as_array()
            .unwrap()
            .iter()
            .any(|d| d["kind"] == serde_json::json!("changed")
                && d["name"] == serde_json::json!("leaf")),
        "changed drift for the transitive leaf: {v}"
    );
}

/// `lock --frozen` catches a transitive leaf `.ig` edit without writing the lockfile.
#[test]
fn cli_frozen_catches_leaf_drift() {
    let root = temp_fixture("workspace_transitive_ok", "p15_frozen_leaf");
    run("lock", &root);
    let before = std::fs::read(root.join("igniter.lock")).unwrap();
    let leaf = root.join("../leaf/src/public.ig");
    let mut c = std::fs::read_to_string(&leaf).unwrap();
    c.push_str("\n-- drift\n");
    std::fs::write(&leaf, c).unwrap();
    let (ok, v) = run_args(&["lock", "--project-root", &root_arg(&root), "--frozen"]);
    assert!(!ok, "frozen catches transitive leaf drift: {v}");
    assert_eq!(v["reason"], serde_json::json!("out-of-date"));
    assert_eq!(
        std::fs::read(root.join("igniter.lock")).unwrap(),
        before,
        "frozen must not rewrite"
    );
}

/// `verify --strict` reports a transitive `OOF-IMP6` with structured fields (root imports an undeclared
/// transitive package).
#[test]
fn cli_verify_strict_catches_transitive_phantom() {
    let root = temp_fixture("workspace_transitive_root_phantom", "p15_tphantom");
    run("lock", &root);
    let (ok, v) = run_args(&["verify", "--project-root", &root_arg(&root), "--strict"]);
    assert!(!ok, "strict catches transitive phantom: {v}");
    let d = &v["integrity"]["diagnostic"];
    assert_eq!(d["rule"], serde_json::json!("OOF-IMP6"));
    assert_eq!(
        d["module_path"],
        serde_json::json!("App.Main"),
        "structured importer: {d}"
    );
    assert!(
        d["source_paths"].as_array().is_some_and(|a| a.len() == 1),
        "structured path: {d}"
    );
}

/// `verify --strict` reports a transitive `OOF-IMP7` (a dependency imports a non-exported module of its own
/// declared dependency).
#[test]
fn cli_verify_strict_catches_transitive_non_export() {
    let root = temp_fixture("workspace_transitive_non_export", "p15_tnonexport");
    run("lock", &root);
    let (ok, v) = run_args(&["verify", "--project-root", &root_arg(&root), "--strict"]);
    assert!(!ok, "strict catches transitive non-export: {v}");
    let d = &v["integrity"]["diagnostic"];
    assert_eq!(d["rule"], serde_json::json!("OOF-IMP7"));
    assert_eq!(
        d["module_path"],
        serde_json::json!("Mid.M"),
        "structured importer: {d}"
    );
}

/// LAB-IGNITER-PACKAGE-TRANSITIVE-GRAPH-P14: `verify --strict` catches a package-graph cycle (OOF-IMP8).
#[test]
fn cli_verify_strict_catches_cycle() {
    let root = temp_fixture("workspace_transitive_cycle", "strict_cycle");
    run("lock", &root);
    let (ok, v) = run_args(&["verify", "--project-root", &root_arg(&root), "--strict"]);
    assert!(!ok, "strict verify fails on a graph cycle: {v}");
    assert_eq!(
        v["integrity"]["diagnostic"]["rule"],
        serde_json::json!("OOF-IMP8")
    );
}

/// A transitive dependency's content drift is caught: after `lock` on `workspace_transitive_ok`, editing the
/// leaf (transitive) package's source makes `verify` report a `changed` drift for that package.
#[test]
fn cli_transitive_content_drift_detected() {
    let root = temp_fixture("workspace_transitive_ok", "tdrift");
    run("lock", &root);
    let leaf = root.join("../leaf/src/public.ig");
    let mut c = std::fs::read_to_string(&leaf).unwrap();
    c.push_str("\n-- drift\n");
    std::fs::write(&leaf, c).unwrap();

    let (ok, v) = run("verify", &root);
    assert!(!ok, "transitive content change must be drift: {v}");
    assert!(
        v["drift"]
            .as_array()
            .unwrap()
            .iter()
            .any(|d| d["kind"] == serde_json::json!("changed")),
        "changed drift for the transitive leaf: {v}"
    );
}

/// LAB-IGNITER-PACKAGE-EXPORTS-CLOSED-DEFAULT-P12: `verify --strict` under a root `[package] exports =
/// "closed"` policy fails (OOF-IMP7) when a dependency declares no exports; plain `verify` is drift-only.
#[test]
fn cli_verify_strict_closed_default_seals() {
    let root = temp_fixture("workspace_closed_default", "strict_closed");
    run("lock", &root);

    let (ok_plain, _) = run("verify", &root);
    assert!(
        ok_plain,
        "plain verify is drift-only and passes under closed policy"
    );

    let (ok_strict, v) = run_args(&["verify", "--project-root", &root_arg(&root), "--strict"]);
    assert!(
        !ok_strict,
        "strict verify seals an undeclared dependency under closed policy: {v}"
    );
    assert_eq!(
        v["integrity"]["diagnostic"]["rule"],
        serde_json::json!("OOF-IMP7")
    );
    assert!(
        v["integrity"]["diagnostic"]["message"]
            .as_str()
            .is_some_and(|m| m.contains("closed")),
        "closed-policy message: {v}"
    );
}

/// The dependency digest folds in `igniter.toml`, so editing a dependency's `[exports]` is drift: after
/// `lock`, changing `lib/igniter.toml` makes `verify` report a `changed` drift for that dependency.
#[test]
fn cli_export_change_is_lock_drift() {
    let root = temp_fixture("workspace_exports_ok", "export_drift");
    run("lock", &root);
    // Edit ONLY the dependency manifest's exports (no .ig change).
    let dep_manifest = root.join("../lib/igniter.toml");
    let edited = std::fs::read_to_string(&dep_manifest)
        .unwrap()
        .replace("\"Lib.Public\"", "\"Lib.Public\", \"Lib.Private\"");
    std::fs::write(&dep_manifest, edited).unwrap();

    let (ok, v) = run("verify", &root);
    assert!(
        !ok,
        "exports change must be drift (manifest folded into digest): {v}"
    );
    let drift = v["drift"].as_array().unwrap();
    assert!(
        drift
            .iter()
            .any(|d| d["kind"] == serde_json::json!("changed")
                && d["name"] == serde_json::json!("lib")),
        "changed drift for lib after exports edit: {v}"
    );
}
