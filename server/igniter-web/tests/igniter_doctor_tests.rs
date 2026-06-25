// igniter_doctor_tests.rs — LAB-DISTRIBUTION-DOCTOR-IMPL-P10
//
// Focused tests for the full v0 `igniter doctor` through the repo-local `bin/igniter` front door (not by
// calling functions). All checks are local + non-mutating; doctor exits 0 even on `fail` entries. A separate
// file from the serve/skeleton wrapper smoke suite to keep the doctor surface self-contained.

use std::path::PathBuf;
use std::process::Command;

fn wrapper() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../bin/igniter")
        .canonicalize()
        .expect("repo-local bin/igniter wrapper must exist")
}
fn todo_app() -> String {
    format!("{}/examples/todo_app", env!("CARGO_MANIFEST_DIR"))
}
fn igweb_serve_bin() -> &'static str {
    env!("CARGO_BIN_EXE_igweb-serve")
}

/// `igniter doctor --json` is valid-shaped JSON with ≥10 checks across env/toolchain/app scopes; exit 0.
#[test]
fn doctor_json_has_min_checks_and_scopes() {
    let out = Command::new(wrapper())
        .args(["doctor", &todo_app(), "--json"])
        .output()
        .expect("run igniter doctor --json");
    assert!(out.status.success(), "doctor exits 0: {out:?}");
    let s = String::from_utf8_lossy(&out.stdout);
    let s = s.trim();
    assert!(s.starts_with('[') && s.ends_with(']'), "looks like a JSON array:\n{s}");
    let checks = s.matches("\"severity\"").count();
    assert!(checks >= 10, "at least 10 checks, got {checks}:\n{s}");
    for scope in ["\"scope\": \"env\"", "\"scope\": \"toolchain\"", "\"scope\": \"app\""] {
        assert!(s.contains(scope), "must include {scope}:\n{s}");
    }
}

/// `igniter doctor <todo_app>` reports app-dir + manifest checks and points build at `igniter check`.
#[test]
fn doctor_app_reports_app_shape() {
    let out = Command::new(wrapper())
        .args(["doctor", &todo_app()])
        .output()
        .expect("run igniter doctor <app>");
    assert!(out.status.success());
    let s = String::from_utf8_lossy(&out.stdout);
    assert!(s.contains("app-dir"), "names app-dir: {s}");
    assert!(s.contains("igweb.toml"), "checks the manifest: {s}");
    assert!(s.contains("igniter check"), "build delegates to check: {s}");
}

/// `igniter doctor <missing_dir>` emits a `fail` entry but still exits 0 (it is a report).
#[test]
fn doctor_missing_dir_fails_entry_but_exits_zero() {
    let out = Command::new(wrapper())
        .args(["doctor", "/no/such/app/dir"])
        .output()
        .expect("run igniter doctor <missing>");
    assert!(out.status.success(), "doctor always exits 0 in v0");
    let s = String::from_utf8_lossy(&out.stdout);
    assert!(s.contains("[fail]") && s.contains("app-dir"), "fail entry for missing dir: {s}");
}

/// host.toml with an inline secret is reported by KEY NAME only — never the value.
#[test]
fn doctor_host_toml_inline_secret_named_not_valued() {
    let tmp = std::env::temp_dir().join(format!("igdoc_secret_{}", std::process::id()));
    std::fs::create_dir_all(&tmp).unwrap();
    std::fs::write(tmp.join("igweb.toml"), "[app]\nentry = \"Serve\"\n").unwrap();
    // an INLINE secret (the forbidden form) — doctor must flag the key, not echo the value
    std::fs::write(tmp.join("host.toml"), "[postgres.write]\npassword = \"hunter2_topsecret\"\n").unwrap();
    let out = Command::new(wrapper())
        .args(["doctor", tmp.to_str().unwrap()])
        .output()
        .expect("run igniter doctor <tmp>");
    let s = String::from_utf8_lossy(&out.stdout);
    let _ = std::fs::remove_dir_all(&tmp);
    assert!(out.status.success());
    assert!(s.contains("inline secret key") && s.contains("password"), "names the offending key: {s}");
    assert!(!s.contains("hunter2_topsecret"), "must NOT print the secret value:\n{s}");
}

/// Referenced env vars are reported by NAME + set/unset — never the value.
#[test]
fn doctor_env_var_reported_by_name_not_value() {
    let tmp = std::env::temp_dir().join(format!("igdoc_env_{}", std::process::id()));
    std::fs::create_dir_all(&tmp).unwrap();
    std::fs::write(tmp.join("igweb.toml"), "[app]\nentry = \"Serve\"\n").unwrap();
    std::fs::write(tmp.join("host.toml"), "[postgres.write]\ndsn_env = \"MY_TEST_DSN_VAR\"\n").unwrap();
    let out = Command::new(wrapper())
        .args(["doctor", tmp.to_str().unwrap()])
        .env("MY_TEST_DSN_VAR", "postgres://secret-value-here")
        .output()
        .expect("run igniter doctor <tmp>");
    let s = String::from_utf8_lossy(&out.stdout);
    let _ = std::fs::remove_dir_all(&tmp);
    assert!(out.status.success());
    assert!(s.contains("MY_TEST_DSN_VAR"), "names the env var: {s}");
    assert!(!s.contains("secret-value-here"), "must NOT print the env var value:\n{s}");
}

/// A staged prefix (igniter + a co-located binary, no crate tree) reports installed-prefix mode and treats
/// the missing `igniter-lang` sibling as `info`, NOT a scary source-checkout `fail`.
#[test]
fn doctor_staged_prefix_is_installed_mode_not_scary() {
    let tmp = std::env::temp_dir().join(format!("igdoc_staged_{}", std::process::id()));
    let bindir = tmp.join("bin");
    std::fs::create_dir_all(&bindir).unwrap();
    std::fs::copy(wrapper(), bindir.join("igniter")).unwrap();
    std::fs::copy(igweb_serve_bin(), bindir.join("igweb-serve")).unwrap();
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let p = bindir.join("igniter");
        let mut perm = std::fs::metadata(&p).unwrap().permissions();
        perm.set_mode(0o755);
        std::fs::set_permissions(&p, perm).unwrap();
    }
    let out = Command::new(bindir.join("igniter"))
        .arg("doctor")
        .output()
        .expect("run staged igniter doctor");
    let s = String::from_utf8_lossy(&out.stdout);
    let _ = std::fs::remove_dir_all(&tmp);
    assert!(out.status.success());
    assert!(s.contains("installed-prefix"), "reports installed-prefix mode: {s}");
    assert!(
        s.contains("not required in installed-prefix mode"),
        "igniter-lang sibling is info (not a source-checkout fail):\n{s}"
    );
    assert!(s.contains("igweb-serve") && s.contains("(staged)"), "fleet resolves co-located: {s}");
}
