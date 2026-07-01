// igniter_json_contract_tests.rs — LAB-IGNITER-COMMAND-CENTER-JSON-CONTRACT-P4
//
// Conformance guard for the v0 command-center JSON contract (packet: lab-igniter-command-center-json-
// contract-p4-v0.md). It pins the SHAPE of every command-center `--json` surface so it cannot drift:
//   - the output is a BARE top-level JSON array (not an envelope);
//   - every record carries all five keys {scope,check,severity,detail,suggest};
//   - every `severity` is exactly one of ok/info/warn/fail;
//   - no secret / env value leaks into records.
// Hermetic: `workspace` runs with IGNITER_WORKSPACE_NO_REMOTE=1 (no SSH); `doctor` is local + non-mutating.
// A lightweight hand-rolled JSON walk (no serde dep needed) keeps this test self-contained.

use std::path::PathBuf;
use std::process::Command;

fn wrapper() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../bin/igniter")
        .canonicalize()
        .expect("repo-local bin/igniter wrapper must exist")
}

fn run_json(args: &[&str]) -> String {
    let out = Command::new(wrapper())
        .args(args)
        .env("IGNITER_WORKSPACE_NO_REMOTE", "1")
        .output()
        .unwrap_or_else(|e| panic!("run igniter {args:?}: {e}"));
    String::from_utf8_lossy(&out.stdout).to_string()
}

/// Assert the §3 record-array invariants on one `--json` payload.
fn assert_record_array(label: &str, s: &str) {
    let t = s.trim();
    assert!(
        t.starts_with('[') && t.ends_with(']'),
        "{label}: must be a BARE JSON array (not an envelope):\n{t}"
    );
    // Each record is an object with these five keys; count objects by "scope" occurrences.
    let n_records = t.matches("\"scope\":").count();
    assert!(n_records >= 1, "{label}: at least one record:\n{t}");
    for key in ["\"scope\":", "\"check\":", "\"severity\":", "\"detail\":", "\"suggest\":"] {
        let c = t.matches(key).count();
        assert_eq!(
            c, n_records,
            "{label}: every record must carry {key} ({c} vs {n_records} records):\n{t}"
        );
    }
    // Severity vocabulary is closed: ok | info | warn | fail. Extract each "severity": "X" value.
    let mut rest = t;
    while let Some(i) = rest.find("\"severity\":") {
        rest = &rest[i + "\"severity\":".len()..];
        let v = rest.trim_start();
        let v = v.strip_prefix('"').unwrap_or_else(|| panic!("{label}: severity must be a string:\n{t}"));
        let end = v.find('"').expect("closing quote");
        let sev = &v[..end];
        assert!(
            matches!(sev, "ok" | "info" | "warn" | "fail"),
            "{label}: severity '{sev}' outside the closed vocabulary ok/info/warn/fail:\n{t}"
        );
        rest = &v[end..];
    }
}

#[test]
fn doctor_json_conforms_to_record_array() {
    assert_record_array("doctor --json", &run_json(&["doctor", "--json"]));
}

#[test]
fn workspace_status_json_conforms() {
    assert_record_array("workspace status --json", &run_json(&["workspace", "status", "--json"]));
}

#[test]
fn workspace_doctor_json_conforms() {
    assert_record_array("workspace doctor --json", &run_json(&["workspace", "doctor", "--json"]));
}

/// All command-center diagnostic surfaces share ONE schema — every record is `workspace`- or a known
/// env/toolchain/app-scoped record, and the whole thing is a single array (no top-level `{...}` envelope).
#[test]
fn json_surfaces_are_arrays_not_envelopes() {
    for args in [
        vec!["doctor", "--json"],
        vec!["workspace", "status", "--json"],
        vec!["workspace", "doctor", "--json"],
    ] {
        let s = run_json(&args);
        let t = s.trim();
        assert!(!t.starts_with('{'), "{args:?}: must NOT be a top-level object envelope:\n{t}");
        assert!(t.starts_with('['), "{args:?}: must be a bare array:\n{t}");
    }
}

/// Contract safety: a referenced env var value never appears in the doctor record array (names only).
#[test]
fn doctor_json_never_leaks_env_value() {
    let tmp = std::env::temp_dir().join(format!("igjson_env_{}", std::process::id()));
    std::fs::create_dir_all(&tmp).unwrap();
    std::fs::write(tmp.join("igweb.toml"), "[app]\nentry = \"Serve\"\n").unwrap();
    std::fs::write(tmp.join("host.toml"), "[postgres.write]\ndsn_env = \"MY_CONTRACT_DSN\"\n").unwrap();
    let out = Command::new(wrapper())
        .args(["doctor", tmp.to_str().unwrap(), "--json"])
        .env("MY_CONTRACT_DSN", "postgres://leaked-secret-value")
        .output()
        .expect("run igniter doctor --json");
    let s = String::from_utf8_lossy(&out.stdout);
    let _ = std::fs::remove_dir_all(&tmp);
    assert_record_array("doctor <app> --json", &s);
    assert!(s.contains("MY_CONTRACT_DSN"), "names the env var:\n{s}");
    assert!(!s.contains("leaked-secret-value"), "must NOT print the env value:\n{s}");
}
