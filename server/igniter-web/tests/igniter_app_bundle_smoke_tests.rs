// igniter_app_bundle_smoke_tests.rs — LAB-DISTRIBUTION-APP-BUNDLE-IMPL-P14
//
// Proves `igniter app bundle <app_dir> --out <dir> --version <stamp>` assembles a versioned, self-contained
// IgWeb app bundle per the P13 contract — ASSEMBLY ONLY. The wrapper is told which runner to copy via
// IGNITER_IGWEB_SERVE_BIN = CARGO_BIN_EXE_igweb-serve, so the test never shells out to a nested cargo build.
//
// Covered: happy-path layout + manifest (runner sha256 matches the copied binary, app sources hashed), the
// emitted checks/check.sh passes, and the fail-closed refusals — real host.toml, inline secret (value never
// printed), missing --version — each leaving NO partial bundle, plus help naming host-owned surfaces.

use std::fs;
use std::io::{BufRead, BufReader, Read, Write};
use std::net::TcpStream;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::Duration;

fn wrapper() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../bin/igniter")
        .canonicalize()
        .expect("repo-local bin/igniter wrapper must exist")
}

fn todo_app() -> String {
    format!("{}/examples/todo_app", env!("CARGO_MANIFEST_DIR"))
}

fn todo_postgres_app() -> String {
    format!("{}/examples/todo_postgres_app", env!("CARGO_MANIFEST_DIR"))
}

fn igweb_serve_bin() -> &'static str {
    env!("CARGO_BIN_EXE_igweb-serve")
}

fn tmp(tag: &str) -> PathBuf {
    let d = std::env::temp_dir().join(format!("appbundle_{}_{}", tag, std::process::id()));
    fs::create_dir_all(&d).unwrap();
    d
}

/// Run `bin/igniter app bundle <args...>` with the runner pinned; returns (stdout, stderr, exit_code).
fn run_bundle(args: &[&str]) -> (String, String, i32) {
    let out = Command::new(wrapper())
        .arg("app")
        .arg("bundle")
        .args(args)
        .env("IGNITER_IGWEB_SERVE_BIN", igweb_serve_bin())
        .output()
        .expect("run igniter app bundle");
    (
        String::from_utf8_lossy(&out.stdout).to_string(),
        String::from_utf8_lossy(&out.stderr).to_string(),
        out.status.code().unwrap_or(-1),
    )
}

fn sha256_hex(p: &Path) -> String {
    let out = Command::new("shasum")
        .args(["-a", "256"])
        .arg(p)
        .output()
        .expect("shasum");
    String::from_utf8_lossy(&out.stdout)
        .split_whitespace()
        .next()
        .unwrap_or("")
        .to_string()
}

/// Copy todo_app into a writable temp app dir so a test can add an offending file (host.toml / secret).
fn writable_app_copy(tag: &str, name: &str) -> PathBuf {
    let app = tmp(tag).join(name);
    fs::create_dir_all(&app).unwrap();
    for entry in fs::read_dir(todo_app()).unwrap() {
        let p = entry.unwrap().path();
        if p.is_file() {
            fs::copy(&p, app.join(p.file_name().unwrap())).unwrap();
        }
    }
    app
}

// ── happy path: layout + manifest + runner sha + emitted check ──────────────────────────────────────────

#[test]
fn bundle_todo_app_produces_valid_layout_and_manifest() {
    let out = tmp("happy");
    let (stdout, stderr, code) = run_bundle(&[
        &todo_app(),
        "--out",
        out.to_str().unwrap(),
        "--version",
        "V1",
    ]);
    assert_eq!(code, 0, "bundle must succeed: {stdout}{stderr}");

    let b = out.join("todo_app-V1");
    for rel in [
        "bin/igweb-serve",
        "app/todo_app/igweb.toml",
        "run/run-todo_app.sh",
        "checks/check.sh",
        "systemd/todo_app.service.example",
        "manifest.json",
    ] {
        assert!(b.join(rel).exists(), "missing bundle file: {rel}");
    }

    let manifest = fs::read_to_string(b.join("manifest.json")).unwrap();
    // runner sha256 in the manifest must match the actually-copied binary
    let copied_sha = sha256_hex(&b.join("bin/igweb-serve"));
    assert!(!copied_sha.is_empty());
    assert!(
        manifest.contains(&copied_sha),
        "manifest runner sha256 must match copied binary:\n{manifest}"
    );
    // provenance shape
    for needle in [
        "\"bind_policy\": \"loopback\"",
        "\"public_release\": false",
        "\"app_sources\"",
        "\"entry\": \"Serve\"",
    ] {
        assert!(
            manifest.contains(needle),
            "manifest missing `{needle}`:\n{manifest}"
        );
    }
    // every app source is hashed
    assert!(
        manifest.contains("app/todo_app/igweb.toml"),
        "igweb.toml hashed: {manifest}"
    );
    assert!(
        manifest.contains("app/todo_app/routes.igweb"),
        "routes.igweb hashed: {manifest}"
    );

    // emitted check.sh passes on the produced bundle
    let chk = Command::new("bash")
        .arg(b.join("checks/check.sh"))
        .output()
        .expect("run check.sh");
    assert!(
        chk.status.success(),
        "emitted check.sh must pass: {:?}",
        chk
    );
    // run script defaults to loopback
    let run = fs::read_to_string(b.join("run/run-todo_app.sh")).unwrap();
    assert!(
        run.contains("127.0.0.1:"),
        "run script binds loopback: {run}"
    );
}

// ── fail-closed: real host.toml is refused, no partial bundle ────────────────────────────────────────────

#[test]
fn bundle_refuses_real_host_toml_no_partial() {
    let app = writable_app_copy("realhost", "myapp");
    fs::write(app.join("host.toml"), "[host]\nmode=\"loopback\"\n").unwrap();
    let out = tmp("realhost_out");
    let (_o, err, code) = run_bundle(&[
        app.to_str().unwrap(),
        "--out",
        out.to_str().unwrap(),
        "--version",
        "V1",
    ]);
    assert_ne!(code, 0, "real host.toml must be refused");
    assert!(err.contains("host.toml"), "names the offending file: {err}");
    assert!(
        !out.join("myapp-V1").exists(),
        "no partial bundle may be left behind"
    );
}

// ── fail-closed: inline secret is refused, the value is NEVER printed ────────────────────────────────────

#[test]
fn bundle_refuses_inline_secret_without_printing_value() {
    let app = writable_app_copy("secret", "secapp");
    fs::write(
        app.join("host.example.toml"),
        "[host]\nmode=\"loopback\"\n[postgres.read]\ndsn = \"host=db password=SUPERSECRET123\"\n",
    )
    .unwrap();
    let out = tmp("secret_out");
    let (stdout, stderr, code) = run_bundle(&[
        app.to_str().unwrap(),
        "--out",
        out.to_str().unwrap(),
        "--version",
        "V1",
    ]);
    assert_ne!(code, 0, "inline secret must be refused");
    assert!(
        stderr.contains("inline secret"),
        "explains the refusal: {stderr}"
    );
    assert!(
        !stdout.contains("SUPERSECRET123") && !stderr.contains("SUPERSECRET123"),
        "the secret value must NEVER be printed:\nSTDOUT:{stdout}\nSTDERR:{stderr}"
    );
    assert!(!out.join("secapp-V1").exists(), "no partial bundle");
}

// ── fail-closed: --version is mandatory (no clock in the tool) ───────────────────────────────────────────

#[test]
fn bundle_requires_version_stamp() {
    let out = tmp("nover");
    let (_o, err, code) = run_bundle(&[&todo_app(), "--out", out.to_str().unwrap()]);
    assert_ne!(code, 0, "missing --version must be refused");
    assert!(err.contains("--version"), "names the missing flag: {err}");
}

// ── help names the host-owned surfaces ──────────────────────────────────────────────────────────────────

#[test]
fn app_help_names_host_owned_surfaces() {
    let out = Command::new(wrapper())
        .args(["app", "--help"])
        .output()
        .expect("app --help");
    assert!(out.status.success(), "app --help exits 0");
    let h = String::from_utf8_lossy(&out.stdout);
    assert!(
        h.contains("ASSEMBLY ONLY") || h.to_lowercase().contains("assembly only"),
        "states assembly-only: {h}"
    );
    for needle in ["systemd", "TLS", "secrets"] {
        assert!(
            h.contains(needle),
            "help must name host-owned surface `{needle}`:\n{h}"
        );
    }
}

// ── run smoke: the emitted run/run-<app>.sh actually serves a request from inside the bundle (P16) ──────

/// Bundle todo_app, then run the EMITTED `run/run-todo_app.sh` (which execs the BUNDLED `bin/igweb-serve`
/// against `bundle/app/todo_app`) on a loopback OS-chosen port, bounded to one request, and prove it answers
/// `GET /health` with 200 — then exits cleanly with no orphan. Loads from the bundle, not the source path.
#[test]
fn emitted_run_script_serves_from_bundle_on_loopback() {
    let out = tmp("runsmoke");
    let (stdout, stderr, code) = run_bundle(&[
        &todo_app(),
        "--out",
        out.to_str().unwrap(),
        "--version",
        "RUNV1",
    ]);
    assert_eq!(code, 0, "bundle must succeed: {stdout}{stderr}");
    let bundle = out.join("todo_app-RUNV1");
    let run_script = bundle.join("run/run-todo_app.sh");
    assert!(run_script.exists(), "emitted run script must exist");

    // PORT=0 → igweb-serve binds an OS-chosen free port (no collisions); MAX_REQUESTS=1 → bounded run.
    // The run script reads exactly these env names and execs the BUNDLED bin/igweb-serve (not the repo target).
    let mut child = Command::new("bash")
        .arg(&run_script)
        .env("IGNITER_TODO_APP_PORT", "0")
        .env("IGNITER_TODO_APP_MAX_REQUESTS", "1")
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .expect("spawn emitted run script");

    // Non-blind readiness: read stdout until the machine-readable `listening http://127.0.0.1:PORT` line.
    let child_stdout = child.stdout.take().expect("child stdout");
    let mut reader = BufReader::new(child_stdout);
    let mut captured = String::new();
    let addr = loop {
        let mut line = String::new();
        let n = reader.read_line(&mut line).expect("read stdout");
        if n == 0 {
            let _ = child.kill();
            panic!("bundled runner exited before listening; stdout so far:\n{captured}");
        }
        captured.push_str(&line);
        if let Some(rest) = line.split("listening http://").nth(1) {
            break rest.split_whitespace().next().unwrap_or("").to_string();
        }
    };

    // Loopback-only enforced by igweb-serve; and the app dir echoed must be the BUNDLE's, not the source path.
    assert!(
        addr.starts_with("127.0.0.1:"),
        "must bind loopback, got `{addr}`:\n{captured}"
    );
    assert!(
        captured.contains("todo_app-RUNV1/app/todo_app") || captured.contains("todo_app-RUNV1"),
        "must serve the app from inside the bundle (versioned dir), not a source path:\n{captured}"
    );

    // One real request on the parsed socket; the runner is bounded to this single request.
    let result = (|| -> std::io::Result<String> {
        let mut stream = TcpStream::connect(&addr)?;
        stream.set_read_timeout(Some(Duration::from_secs(10)))?;
        stream.write_all(b"GET /health HTTP/1.1\r\nHost: x\r\ncontent-length: 0\r\n\r\n")?;
        let mut resp = String::new();
        stream.read_to_string(&mut resp)?;
        Ok(resp)
    })();

    match result {
        Ok(resp) => assert!(
            resp.starts_with("HTTP/1.1 200"),
            "GET /health must be 200, got:\n{resp}"
        ),
        Err(e) => {
            let _ = child.kill();
            panic!("request to bundled runner failed: {e}\nserver stdout:\n{captured}");
        }
    }

    // Bounded run must exit on its own (no daemon/orphan); clean up defensively if it lingers.
    let status = child.wait().expect("wait bundled runner");
    assert!(
        status.success(),
        "bundled runner must exit cleanly after its bounded run"
    );
}

// ── machine-mode (P29): todo_postgres_app bundle is host-config ready, still assembly-only ──────────────

/// Bundling a machine-mode app (ships `host.example.toml`) emits a host-config-aware run script + systemd
/// example, keeps `requires_machine:true`, and stays secret-free / DB-free. Assembly only — no DB, no real
/// host.toml, no live machine run.
#[test]
fn bundle_todo_postgres_app_is_machine_mode_ready() {
    let out = tmp("pg");
    let (stdout, stderr, code) = run_bundle(&[
        &todo_postgres_app(),
        "--out",
        out.to_str().unwrap(),
        "--version",
        "V1",
    ]);
    assert_eq!(
        code, 0,
        "machine-mode bundle must succeed: {stdout}{stderr}"
    );
    let b = out.join("todo_postgres_app-V1");

    // host.toml.example is copied; the real host.toml is NEVER bundled.
    assert!(
        b.join("host.toml.example").exists(),
        "host.toml.example copied"
    );
    assert!(
        !b.join("host.toml").exists(),
        "a real host.toml must NEVER be bundled"
    );

    // manifest: requires_machine + loopback, and NO secret material.
    let manifest = fs::read_to_string(b.join("manifest.json")).unwrap();
    assert!(
        manifest.contains("\"requires_machine\": true"),
        "requires_machine true: {manifest}"
    );
    assert!(
        manifest.contains("\"bind_policy\": \"loopback\""),
        "bind_policy loopback: {manifest}"
    );
    for secret in ["password", "\"dsn\"", "passport", "bearer"] {
        assert!(
            !manifest.to_lowercase().contains(secret),
            "manifest carries no secret `{secret}`: {manifest}"
        );
    }

    // run script: host-config precedence env-override → bundle host.toml → none; never passes host.toml.example.
    let run = fs::read_to_string(b.join("run/run-todo_postgres_app.sh")).unwrap();
    assert!(
        run.contains("IGNITER_TODO_POSTGRES_APP_HOST_CONFIG"),
        "env override branch: {run}"
    );
    assert!(
        run.contains("-f \"$here/host.toml\""),
        "bundle host.toml branch: {run}"
    );
    assert!(
        run.contains("machine-mode config not active"),
        "no-config note branch: {run}"
    );
    assert!(
        !run.contains("--host-config \"$here/host.toml.example\""),
        "must NOT pass host.toml.example as config: {run}"
    );

    // systemd example names the HOST_CONFIG env var but carries no secret values.
    let unit = fs::read_to_string(b.join("systemd/todo_postgres_app.service.example")).unwrap();
    assert!(
        unit.contains("IGNITER_TODO_POSTGRES_APP_HOST_CONFIG"),
        "unit names HOST_CONFIG env: {unit}"
    );
    assert!(
        !unit.to_lowercase().contains("password") && !unit.contains("dsn="),
        "unit has no secret values: {unit}"
    );

    // checks/check.sh passes WITHOUT any DB env vars / real host.toml (opens no socket/DB).
    let chk = std::process::Command::new("bash")
        .arg(b.join("checks/check.sh"))
        .env_remove("IGNITER_TODO_PG_DSN")
        .output()
        .expect("run check.sh");
    assert!(
        chk.status.success(),
        "machine-mode check.sh must pass with no DB env: {chk:?}"
    );
}

// ── app admit (P35): validate + copy a bundle into a release root; never touches `current` ──────────────

/// Run `igniter app admit <bundle> --release-root <root>`; returns (stdout, stderr, exit_code).
fn run_admit(bundle: &Path, root: &Path) -> (String, String, i32) {
    let out = Command::new(wrapper())
        .args(["app", "admit"])
        .arg(bundle)
        .arg("--release-root")
        .arg(root)
        .output()
        .expect("run igniter app admit");
    (
        String::from_utf8_lossy(&out.stdout).to_string(),
        String::from_utf8_lossy(&out.stderr).to_string(),
        out.status.code().unwrap_or(-1),
    )
}

/// Recursively copy a directory (src → a NEW dst) via `cp -R`.
fn copy_dir(src: &Path, dst: &Path) {
    let ok = Command::new("cp")
        .arg("-R")
        .arg(src)
        .arg(dst)
        .status()
        .expect("cp -R")
        .success();
    assert!(ok, "cp -R {src:?} {dst:?} failed");
}

/// Bundle an example app at version `V1`; returns the produced bundle dir.
fn bundle_v1(app_dir: &str, tag: &str) -> PathBuf {
    let out = tmp(tag);
    let (so, se, code) = run_bundle(&[app_dir, "--out", out.to_str().unwrap(), "--version", "V1"]);
    assert_eq!(code, 0, "bundle must succeed: {so}{se}");
    let name = Path::new(app_dir).file_name().unwrap().to_str().unwrap();
    out.join(format!("{name}-V1"))
}

#[test]
fn admit_pure_todo_app_into_release_root() {
    let bundle = bundle_v1(&todo_app(), "admit_pure");
    let root = tmp("admit_pure_root");
    let (so, se, code) = run_admit(&bundle, &root);
    assert_eq!(code, 0, "admit must succeed: {so}{se}");

    // destination layout: <root>/releases/todo_app/V1/<copied bundle>
    let dest = root.join("releases/todo_app/V1");
    for rel in [
        "bin/igweb-serve",
        "app/todo_app/igweb.toml",
        "checks/check.sh",
        "manifest.json",
    ] {
        assert!(dest.join(rel).exists(), "admitted release missing {rel}");
    }
    assert!(
        so.contains("admitted_path") && so.contains("todo_app"),
        "receipt names the path: {so}"
    );
    // source bundle stays intact; NO `current` symlink is created
    assert!(
        bundle.join("manifest.json").exists(),
        "source bundle must remain intact"
    );
    assert!(
        !root.join("current").exists(),
        "admit must NOT create a `current` symlink"
    );
}

#[test]
fn admit_refuses_tampered_runner_and_source_leaving_no_partial() {
    let bundle = bundle_v1(&todo_app(), "admit_tamper_src");

    // tamper the runner → gate 5
    let t1 = tmp("tamper_runner").join("b");
    copy_dir(&bundle, &t1);
    fs::OpenOptions::new()
        .append(true)
        .open(t1.join("bin/igweb-serve"))
        .unwrap()
        .write_all(b"TAMPER")
        .unwrap();
    let root1 = tmp("tamper_runner_root");
    let (_o, e1, c1) = run_admit(&t1, &root1);
    assert_ne!(c1, 0, "tampered runner must be refused");
    assert!(e1.contains("gate 5"), "names gate 5: {e1}");
    assert!(
        !root1.join("releases/todo_app/V1").exists(),
        "no partial release after refusal"
    );

    // tamper an app source → gate 6
    let t2 = tmp("tamper_src2").join("b");
    copy_dir(&bundle, &t2);
    fs::OpenOptions::new()
        .append(true)
        .open(t2.join("app/todo_app/igweb.toml"))
        .unwrap()
        .write_all(b"\n# tampered\n")
        .unwrap();
    let root2 = tmp("tamper_src2_root");
    let (_o, e2, c2) = run_admit(&t2, &root2);
    assert_ne!(c2, 0, "tampered source must be refused");
    assert!(e2.contains("gate 6"), "names gate 6: {e2}");
    assert!(
        !root2.join("releases/todo_app/V1").exists(),
        "no partial release after refusal"
    );
}

#[test]
fn admit_refuses_real_host_toml() {
    let bundle = bundle_v1(&todo_app(), "admit_hosttoml");
    let t = tmp("admit_hosttoml_copy").join("b");
    copy_dir(&bundle, &t);
    fs::write(t.join("host.toml"), "[host]\nmode=\"loopback\"\n").unwrap();
    let root = tmp("admit_hosttoml_root");
    let (_o, e, c) = run_admit(&t, &root);
    assert_ne!(c, 0, "a real host.toml in the bundle must be refused");
    assert!(
        e.contains("gate 8") && e.contains("host.toml"),
        "names gate 8: {e}"
    );
    assert!(
        !root.join("releases/todo_app/V1").exists(),
        "no partial release"
    );
}

#[test]
fn admit_duplicate_release_is_refused() {
    let bundle = bundle_v1(&todo_app(), "admit_dup");
    let root = tmp("admit_dup_root");
    let (_o, _e, c1) = run_admit(&bundle, &root);
    assert_eq!(c1, 0, "first admit succeeds");
    let (_o2, e2, c2) = run_admit(&bundle, &root);
    assert_ne!(c2, 0, "duplicate admit must be refused (no --force in v0)");
    assert!(
        e2.contains("gate 10") && e2.contains("already admitted"),
        "names gate 10: {e2}"
    );
}

#[test]
fn admit_machine_mode_todo_postgres_app() {
    let bundle = bundle_v1(&todo_postgres_app(), "admit_pg");
    let root = tmp("admit_pg_root");
    let (so, se, code) = run_admit(&bundle, &root);
    assert_eq!(code, 0, "machine-mode admit must succeed: {so}{se}");
    assert!(
        so.contains("requires_machine: true"),
        "receipt notes requires_machine: {so}"
    );
    let dest = root.join("releases/todo_postgres_app/V1");
    assert!(
        dest.join("host.toml.example").exists(),
        "admitted machine bundle keeps host.toml.example"
    );
    assert!(
        !dest.join("host.toml").exists(),
        "no real host.toml in the admitted release"
    );
}
