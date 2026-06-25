// igniter_serve_wrapper_smoke_tests.rs — LAB-DISTRIBUTION-RAILS-SERVE-DX-P2
//
// Proves the Rails-`s`-style DX contour through the repo-local `bin/igniter` wrapper (shape decided by
// LAB-DISTRIBUTION-ECOSYSTEM-READINESS-P1 §5, wrapper "C"):
//
//   * `igniter serve <app> --addr 127.0.0.1:0 --max-requests 1`  → serve a real app over loopback,
//     issue ONE HTTP request, get a 200 response — NO live DB, NO machine feature (sync path).
//   * `igniter serve --check <app>`                              → dry build, opens NO socket.
//   * `igniter serve <app> --addr 0.0.0.0:PORT`                  → public bind REFUSED end-to-end
//     (the safety gate lives in igweb-serve and is preserved through the wrapper).
//
// The wrapper is told which binary to run via IGNITER_IGWEB_SERVE_BIN = CARGO_BIN_EXE_igweb-serve, so the
// test never shells out to a nested cargo build. App: examples/todo_app (the sync, DB-free example).

use std::io::{BufRead, BufReader, Read, Write};
use std::net::TcpStream;
use std::path::PathBuf;
use std::process::{Command, Stdio};
use std::time::Duration;

fn wrapper() -> PathBuf {
    // CARGO_MANIFEST_DIR = .../server/igniter-web ; the wrapper lives at the repo root `bin/igniter`.
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../bin/igniter")
        .canonicalize()
        .expect("repo-local bin/igniter wrapper must exist")
}

fn app_dir() -> String {
    format!("{}/examples/todo_app", env!("CARGO_MANIFEST_DIR"))
}

fn igweb_serve_bin() -> &'static str {
    env!("CARGO_BIN_EXE_igweb-serve")
}

/// `igniter serve <app> --addr 127.0.0.1:0 --max-requests 1` → real loopback serve → GET /health → 200.
#[test]
fn igniter_serve_app_returns_health_200_no_db() {
    let mut child = Command::new(wrapper())
        .args(["serve", &app_dir(), "--addr", "127.0.0.1:0", "--max-requests", "1"])
        .env("IGNITER_IGWEB_SERVE_BIN", igweb_serve_bin())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .expect("spawn igniter serve");

    // Read stdout until the machine-readable `listening http://127.0.0.1:PORT …` line, then parse the addr.
    let stdout = child.stdout.take().expect("child stdout");
    let mut reader = BufReader::new(stdout);
    let mut captured = String::new();
    let addr = loop {
        let mut line = String::new();
        let n = reader.read_line(&mut line).expect("read stdout");
        if n == 0 {
            panic!("igniter serve exited before listening; stdout so far:\n{captured}");
        }
        captured.push_str(&line);
        if let Some(rest) = line.split("listening http://").nth(1) {
            break rest.split_whitespace().next().unwrap_or("").to_string();
        }
    };
    assert!(
        addr.starts_with("127.0.0.1:"),
        "must bind loopback, got `{addr}` from:\n{captured}"
    );

    // One real HTTP/1.1 request on the parsed socket; the runner is bounded to this single request.
    let mut stream = TcpStream::connect(&addr).expect("connect to served app");
    stream
        .set_read_timeout(Some(Duration::from_secs(10)))
        .unwrap();
    stream
        .write_all(b"GET /health HTTP/1.1\r\nHost: x\r\ncontent-length: 0\r\n\r\n")
        .expect("send GET /health");
    let mut resp = String::new();
    stream.read_to_string(&mut resp).expect("read response");
    assert!(
        resp.starts_with("HTTP/1.1 200"),
        "GET /health must be 200, got:\n{resp}"
    );

    let status = child.wait().expect("wait child");
    assert!(status.success(), "igniter serve must exit cleanly after its bounded run");
}

/// `igniter serve --check <app>` → dry build, no socket opened.
#[test]
fn igniter_serve_check_opens_no_socket() {
    let out = Command::new(wrapper())
        .args(["serve", "--check", &app_dir()])
        .env("IGNITER_IGWEB_SERVE_BIN", igweb_serve_bin())
        .output()
        .expect("run igniter serve --check");
    assert!(out.status.success(), "check must succeed: {out:?}");
    let stdout = String::from_utf8_lossy(&out.stdout);
    assert!(stdout.contains("check ok"), "check ok line: {stdout}");
    assert!(stdout.contains("(no socket opened)"), "must not bind: {stdout}");
}

/// `igniter serve <app> --addr 0.0.0.0:PORT` → public bind REFUSED end-to-end (gate preserved by wrapper).
#[test]
fn igniter_serve_refuses_public_bind() {
    let out = Command::new(wrapper())
        .args(["serve", &app_dir(), "--addr", "0.0.0.0:8080"])
        .env("IGNITER_IGWEB_SERVE_BIN", igweb_serve_bin())
        .output()
        .expect("run igniter serve --addr public");
    assert!(!out.status.success(), "public bind must fail");
    let stderr = String::from_utf8_lossy(&out.stderr);
    assert!(
        stderr.contains("loopback-only"),
        "must refuse non-loopback bind: {stderr}"
    );
}

/// `igniter serve --help` prints the serve-specific usage naming app dir, bind default, --host-config, safety.
#[test]
fn igniter_serve_help_names_contract() {
    let out = Command::new(wrapper())
        .args(["serve", "--help"])
        .output()
        .expect("run igniter serve --help");
    assert!(out.status.success());
    let help = String::from_utf8_lossy(&out.stdout);
    for needle in ["<app_dir>", "127.0.0.1:0", "--host-config", "loopback-only", "--check"] {
        assert!(help.contains(needle), "help must name `{needle}`:\n{help}");
    }
}

// ── P7 control-center skeleton ──────────────────────────────────────────────────────────────────────

/// `igniter check <app>` (top-level) delegates to `igweb-serve check` and opens no socket.
#[test]
fn igniter_check_top_level_opens_no_socket() {
    let out = Command::new(wrapper())
        .args(["check", &app_dir()])
        .env("IGNITER_IGWEB_SERVE_BIN", igweb_serve_bin())
        .output()
        .expect("run igniter check");
    assert!(out.status.success(), "check must succeed: {out:?}");
    let stdout = String::from_utf8_lossy(&out.stdout);
    assert!(stdout.contains("check ok"), "check ok line: {stdout}");
    assert!(stdout.contains("(no socket opened)"), "must not bind: {stdout}");
}

/// `igniter doctor` runs non-mutating (no network/DB/build), exits 0, prints actionable local status.
#[test]
fn igniter_doctor_reports_local_status() {
    let out = Command::new(wrapper())
        .arg("doctor")
        .output()
        .expect("run igniter doctor");
    assert!(out.status.success(), "doctor exits 0 (it is a report): {out:?}");
    let s = String::from_utf8_lossy(&out.stdout);
    assert!(s.contains("repo_root:"), "names repo root: {s}");
    assert!(s.contains("igniter-lang sibling"), "checks the build prereq: {s}");
    assert!(s.contains("rustc"), "checks rustc: {s}");
    assert!(s.contains("igweb-serve"), "lists the fleet: {s}");
}

/// `igniter toolchain list` names the 5 green binaries and marks igniter-repl as unavailable.
#[test]
fn igniter_toolchain_list_names_fleet_and_marks_repl() {
    let out = Command::new(wrapper())
        .args(["toolchain", "list"])
        .output()
        .expect("run igniter toolchain list");
    assert!(out.status.success());
    let s = String::from_utf8_lossy(&out.stdout);
    for bin in ["igc", "igniter-vm", "igweb-serve", "igniter-mcp", "tbackend"] {
        assert!(s.contains(bin), "fleet must name `{bin}`:\n{s}");
    }
    assert!(s.contains("igniter-repl"), "must mention repl: {s}");
    assert!(s.contains("[blocked]"), "must mark repl unavailable: {s}");
}

/// Unimplemented commands fail non-zero and point at the intended next step — never silent success.
/// NOTE (P11): `toolchain install` is no longer a placeholder — it now delegates to bin/igniter-install,
/// so it is exercised by the dedicated toolchain tests below, not here. `app bundle` stays fail-closed.
#[test]
fn igniter_placeholders_fail_closed() {
    for args in [&["app", "bundle"][..]] {
        let out = Command::new(wrapper()).args(args).output().expect("run placeholder");
        assert!(
            !out.status.success(),
            "`igniter {}` must NOT pretend success",
            args.join(" ")
        );
        // `--help` for these families must still exit 0 (help is allowed).
    }
    let help = Command::new(wrapper())
        .args(["app", "--help"])
        .output()
        .expect("app --help");
    assert!(help.status.success(), "app --help exits 0");
}

/// Top-level `igniter --help` shows the P6 command family; unknown commands fail non-zero.
#[test]
fn igniter_help_shows_family_and_unknown_fails() {
    let help = Command::new(wrapper()).arg("--help").output().expect("igniter --help");
    assert!(help.status.success());
    let s = String::from_utf8_lossy(&help.stdout);
    for verb in ["serve", "check", "doctor", "toolchain", "package", "app"] {
        assert!(s.contains(verb), "family help must name `{verb}`:\n{s}");
    }
    let unknown = Command::new(wrapper()).arg("frobnicate").output().expect("unknown");
    assert!(!unknown.status.success(), "unknown command must fail non-zero");
}

/// P8 staged-prefix contract: a `bin/igniter` co-located with `igweb-serve` (as `igniter-install` stages it)
/// resolves the sibling binary — no env override, no repo target, no rebuild. Proven without nested cargo by
/// copying the wrapper + `CARGO_BIN_EXE_igweb-serve` into a temp prefix bin dir.
#[test]
fn igniter_resolves_co_located_igweb_serve_in_staged_prefix() {
    let tmp = std::env::temp_dir().join(format!("igniter_staged_{}", std::process::id()));
    let bindir = tmp.join("bin");
    std::fs::create_dir_all(&bindir).unwrap();
    std::fs::copy(wrapper(), bindir.join("igniter")).unwrap();
    std::fs::copy(igweb_serve_bin(), bindir.join("igweb-serve")).unwrap();
    // make the staged wrapper executable
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let p = bindir.join("igniter");
        let mut perm = std::fs::metadata(&p).unwrap().permissions();
        perm.set_mode(0o755);
        std::fs::set_permissions(&p, perm).unwrap();
    }
    // No IGNITER_IGWEB_SERVE_BIN, cwd elsewhere: the only way `check` can work is the co-located sibling.
    let out = Command::new(bindir.join("igniter"))
        .args(["check", &app_dir()])
        .env_remove("IGNITER_IGWEB_SERVE_BIN")
        .current_dir(&tmp)
        .output()
        .expect("run staged igniter check");
    let _ = std::fs::remove_dir_all(&tmp);
    assert!(out.status.success(), "staged igniter check must succeed via co-located igweb-serve: {out:?}");
    let stdout = String::from_utf8_lossy(&out.stdout);
    assert!(stdout.contains("(no socket opened)"), "co-located check, no socket: {stdout}");
}

// ── P11: `igniter toolchain install|update` delegate to bin/igniter-install ──────────────────────────
//
// These are HERMETIC: they copy the real `bin/igniter` into a temp `bin/` next to a FAKE `igniter-install`
// that only records its argv. This proves the delegation contract + the source-required / manifest guards
// WITHOUT a nested cargo build (the full real build path is proven by the card's manual e2e: a
// `toolchain install --prefix <tmp>` stages byte-identically to `bin/igniter-install --prefix <tmp>`).

#[cfg(unix)]
fn make_executable(p: &std::path::Path) {
    use std::os::unix::fs::PermissionsExt;
    let mut perm = std::fs::metadata(p).unwrap().permissions();
    perm.set_mode(0o755);
    std::fs::set_permissions(p, perm).unwrap();
}

/// Stage `<tmp>/bin/igniter` (the real front door) + a fake `igniter-install` that writes its argv to
/// `<tmp>/install-argv.txt` and exits 0. Returns (tmp_root, staged_igniter_path, argv_capture_path).
fn stage_with_fake_installer(tag: &str) -> (PathBuf, PathBuf, PathBuf) {
    let tmp = std::env::temp_dir().join(format!("igtc_{}_{}", tag, std::process::id()));
    let _ = std::fs::remove_dir_all(&tmp);
    let bindir = tmp.join("bin");
    std::fs::create_dir_all(&bindir).unwrap();
    let igniter = bindir.join("igniter");
    std::fs::copy(wrapper(), &igniter).unwrap();
    let capture = tmp.join("install-argv.txt");
    let fake = format!("#!/usr/bin/env bash\nprintf '%s\\n' \"$@\" > {:?}\nexit 0\n", capture);
    let fake_path = bindir.join("igniter-install");
    std::fs::write(&fake_path, fake).unwrap();
    make_executable(&igniter);
    make_executable(&fake_path);
    (tmp, igniter, capture)
}

/// `toolchain install --prefix P` delegates to the co-located installer, forwarding `--prefix P`.
#[test]
fn igniter_toolchain_install_delegates_prefix_to_installer() {
    let (tmp, igniter, capture) = stage_with_fake_installer("install_prefix");
    let target = tmp.join("dest");
    let out = Command::new(&igniter)
        .args(["toolchain", "install", "--prefix"])
        .arg(&target)
        .output()
        .expect("run toolchain install");
    assert!(out.status.success(), "install must delegate+succeed: {out:?}");
    let argv = std::fs::read_to_string(&capture).expect("installer must have been called");
    assert!(argv.contains("--prefix"), "installer got --prefix: {argv:?}");
    assert!(argv.contains(target.to_str().unwrap()), "installer got the prefix path: {argv:?}");
    let _ = std::fs::remove_dir_all(&tmp);
}

/// `toolchain install` with no `--prefix` delegates with NO args (the installer owns the default prefix).
#[test]
fn igniter_toolchain_install_no_prefix_passes_no_args() {
    let (tmp, igniter, capture) = stage_with_fake_installer("install_noprefix");
    let out = Command::new(&igniter)
        .args(["toolchain", "install"])
        .output()
        .expect("run toolchain install");
    assert!(out.status.success(), "install must delegate+succeed: {out:?}");
    let argv = std::fs::read_to_string(&capture).expect("installer must have been called");
    assert!(
        !argv.contains("--prefix"),
        "no --prefix must be forwarded (installer owns the default): {argv:?}"
    );
    let _ = std::fs::remove_dir_all(&tmp);
}

/// `toolchain update --prefix P` fails closed when P has no prior install (no manifest), and does NOT
/// invoke the installer.
#[test]
fn igniter_toolchain_update_requires_prior_manifest() {
    let (tmp, igniter, capture) = stage_with_fake_installer("update_nomanifest");
    let target = tmp.join("dest"); // fresh — no igniter-manifest.json
    let out = Command::new(&igniter)
        .args(["toolchain", "update", "--prefix"])
        .arg(&target)
        .output()
        .expect("run toolchain update");
    assert!(!out.status.success(), "update without a prior install must fail closed");
    let stderr = String::from_utf8_lossy(&out.stderr);
    assert!(
        stderr.contains("no prior install") || stderr.contains("igniter-manifest.json"),
        "must explain the missing manifest: {stderr}"
    );
    assert!(!capture.exists(), "installer must NOT be invoked on a failed precondition");
    let _ = std::fs::remove_dir_all(&tmp);
}

/// `toolchain update --prefix P` delegates when P already carries an install manifest.
#[test]
fn igniter_toolchain_update_delegates_when_manifest_present() {
    let (tmp, igniter, capture) = stage_with_fake_installer("update_manifest");
    let target = tmp.join("dest");
    std::fs::create_dir_all(&target).unwrap();
    std::fs::write(target.join("igniter-manifest.json"), "{}").unwrap();
    let out = Command::new(&igniter)
        .args(["toolchain", "update", "--prefix"])
        .arg(&target)
        .output()
        .expect("run toolchain update");
    assert!(out.status.success(), "update with a prior install must delegate: {out:?}");
    let argv = std::fs::read_to_string(&capture).expect("installer must have been called");
    assert!(argv.contains(target.to_str().unwrap()), "installer got the prefix: {argv:?}");
    let _ = std::fs::remove_dir_all(&tmp);
}

/// A STAGED igniter (front door only, no co-located installer) fails install with a clear source-required
/// message rather than pretending success or crashing.
#[test]
fn igniter_toolchain_install_staged_prefix_is_source_required() {
    let tmp = std::env::temp_dir().join(format!("igtc_staged_{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&tmp);
    let bindir = tmp.join("bin");
    std::fs::create_dir_all(&bindir).unwrap();
    let igniter = bindir.join("igniter");
    std::fs::copy(wrapper(), &igniter).unwrap();
    make_executable(&igniter);
    // No igniter-install staged next to it — mirrors what bin/igniter-install actually stages (front door only).
    let out = Command::new(&igniter)
        .args(["toolchain", "install", "--prefix"])
        .arg(tmp.join("dest"))
        .output()
        .expect("run staged toolchain install");
    assert!(!out.status.success(), "staged install must fail (no source checkout)");
    let stderr = String::from_utf8_lossy(&out.stderr);
    assert!(
        stderr.contains("STAGED") || stderr.contains("source checkout"),
        "must say source is required: {stderr}"
    );
    let _ = std::fs::remove_dir_all(&tmp);
}

/// install/update `--help` state local-source-only and the explicit no-remote/no-registry boundary.
#[test]
fn igniter_toolchain_install_help_states_local_source_only() {
    let out = Command::new(wrapper())
        .args(["toolchain", "install", "--help"])
        .output()
        .expect("run toolchain install --help");
    assert!(out.status.success(), "install --help exits 0");
    let h = String::from_utf8_lossy(&out.stdout);
    for needle in ["LOCAL SOURCE ONLY", "NO remote download", "NO registry", "NO signed artifacts"] {
        assert!(h.contains(needle), "install help must state `{needle}`:\n{h}");
    }
    let outu = Command::new(wrapper())
        .args(["toolchain", "update", "--help"])
        .output()
        .expect("run toolchain update --help");
    assert!(outu.status.success(), "update --help exits 0");
    let hu = String::from_utf8_lossy(&outu.stdout);
    assert!(hu.contains("igniter-manifest.json"), "update help names the manifest precondition:\n{hu}");
    assert!(hu.contains("LOCAL SOURCE ONLY"), "update help states local-source-only:\n{hu}");
}
