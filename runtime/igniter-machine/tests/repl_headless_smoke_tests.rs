// repl_headless_smoke_tests.rs — LAB-DISTRIBUTION-REPL-HEADLESS-SMOKE-P20
//
// Proves `igniter-repl --script <file>` exercises REAL REPL functionality non-interactively (no TUI):
// write a machine fact → checkpoint → resume from that checkpoint → re-read the fact and confirm it survived
// the round-trip. This is the P17 gate for future fleet inclusion.
//
// The whole file is gated behind `--features repl` (the binary itself is `required-features = ["repl"]`), so
// `cargo test --no-default-features` does NOT compile it and the default test run is unaffected. Run with:
//   cargo test --features repl --test repl_headless_smoke_tests
#![cfg(feature = "repl")]

use std::fs;
use std::path::PathBuf;
use std::process::Command;

fn repl_bin() -> &'static str {
    env!("CARGO_BIN_EXE_igniter-repl")
}

fn tmp(tag: &str) -> PathBuf {
    let d = std::env::temp_dir().join(format!("replsmoke_{}_{}", tag, std::process::id()));
    fs::create_dir_all(&d).unwrap();
    d
}

/// The headless smoke must exercise more than startup: a machine write, a checkpoint, a resume, and a
/// post-resume read that proves the state survived — exit 0 with a grep-friendly success marker.
#[test]
fn script_exercises_write_checkpoint_resume_roundtrip() {
    let dir = tmp("ok");
    let ckpt = dir.join("smoke.igm");
    let script = dir.join("smoke.script");
    fs::write(
        &script,
        format!(
            "# headless smoke\n\
             write demo k1 {{\"v\":42}}\n\
             facts demo k1\n\
             checkpoint {ckpt}\n\
             resume {ckpt}\n\
             facts demo k1\n",
            ckpt = ckpt.display()
        ),
    )
    .unwrap();

    let out = Command::new(repl_bin())
        .args(["--script", script.to_str().unwrap()])
        .output()
        .expect("run igniter-repl --script");

    let stdout = String::from_utf8_lossy(&out.stdout);
    assert!(
        out.status.success(),
        "headless smoke must exit 0:\nSTDOUT:{stdout}\nSTDERR:{}",
        String::from_utf8_lossy(&out.stderr)
    );
    assert!(
        stdout.contains("igniter-repl: SCRIPT OK"),
        "success marker:\n{stdout}"
    );
    // real semantic operations ran (not just startup):
    assert!(
        stdout.contains("Wrote fact to 'demo/k1'"),
        "write happened:\n{stdout}"
    );
    assert!(
        stdout.contains("Checkpoint saved"),
        "checkpoint happened:\n{stdout}"
    );
    assert!(
        stdout.contains("Resumed machine"),
        "resume happened:\n{stdout}"
    );
    // the fact value survived the checkpoint→resume round-trip (it appears AFTER the resume line):
    let after_resume = stdout.split("Resumed machine").nth(1).unwrap_or("");
    assert!(
        after_resume.contains("\"v\": 42") || after_resume.contains("\"v\":42"),
        "the written fact must survive resume:\n{stdout}"
    );
    // the checkpoint file was actually produced
    assert!(
        ckpt.exists(),
        "checkpoint file must exist at {}",
        ckpt.display()
    );
    // headless: no TUI escape codes leaked to stdout
    assert!(
        !stdout.contains("\u{1b}[?1049h"),
        "must not enter the alternate screen:\n{stdout}"
    );
}

/// Failure path: a bad command makes the script exit non-zero with a clear marker (no silent success).
#[test]
fn script_with_bad_command_fails_nonzero() {
    let dir = tmp("bad");
    let script = dir.join("bad.script");
    fs::write(&script, "frobnicate nope\n").unwrap();

    let out = Command::new(repl_bin())
        .args(["--script", script.to_str().unwrap()])
        .output()
        .expect("run igniter-repl --script (bad)");
    let stdout = String::from_utf8_lossy(&out.stdout);
    assert!(
        !out.status.success(),
        "a bad command must fail non-zero:\n{stdout}"
    );
    assert!(
        stdout.contains("igniter-repl: SCRIPT FAILED"),
        "failure marker:\n{stdout}"
    );
    assert!(
        stdout.contains("Unknown command"),
        "names the bad command:\n{stdout}"
    );
}

// ─── --run one-shot tests (P2) ───────────────────────────────────────────────

/// Happy path: `--run <source.ig> <Contract> <json>` prints ONLY the JSON result and exits 0.
#[test]
fn run_oneshot_prints_result_and_exits_zero() {
    let dir = tmp("run_ok");
    let source = dir.join("add.ig");
    fs::write(
        &source,
        "module Lang.Examples.Add\ncontract Add {\n  input a: Integer\n  input b: Integer\n  compute sum = a + b\n  output sum: Integer\n}\n",
    )
    .unwrap();

    let out = Command::new(repl_bin())
        .args([
            "--run",
            source.to_str().unwrap(),
            "Add",
            r#"{"a":19,"b":23}"#,
        ])
        .output()
        .expect("run igniter-repl --run");

    let stdout = String::from_utf8_lossy(&out.stdout);
    let stderr = String::from_utf8_lossy(&out.stderr);
    assert!(
        out.status.success(),
        "one-shot must exit 0:\nSTDOUT:{stdout}\nSTDERR:{stderr}"
    );
    // stdout must contain the result JSON — only the result, no REPL banners
    assert!(stdout.contains("42"), "result must contain 42:\n{stdout}");
    assert!(
        !stdout.contains("igniter-repl:"),
        "no REPL markers in one-shot stdout:\n{stdout}"
    );
    assert!(
        !stdout.contains("SCRIPT"),
        "no SCRIPT markers in one-shot stdout:\n{stdout}"
    );
}

/// Multi-contract source: pick the right contract by name.
#[test]
fn run_oneshot_selects_contract_by_name() {
    let dir = tmp("run_multi");
    let source = dir.join("multi.ig");
    fs::write(
        &source,
        "module Lang.Examples.Multi\n\
         contract Double {\n  input x: Integer\n  compute r = x * 2\n  output r: Integer\n}\n\
         contract Triple {\n  input x: Integer\n  compute r = x * 3\n  output r: Integer\n}\n",
    )
    .unwrap();

    let out = Command::new(repl_bin())
        .args(["--run", source.to_str().unwrap(), "Triple", r#"{"x":7}"#])
        .output()
        .expect("run igniter-repl --run (multi)");

    let stdout = String::from_utf8_lossy(&out.stdout);
    assert!(
        out.status.success(),
        "one-shot multi must exit 0:\n{stdout}\n{}",
        String::from_utf8_lossy(&out.stderr)
    );
    assert!(stdout.contains("21"), "Triple(7)=21:\n{stdout}");
}

/// Input JSON from a file (@file).
#[test]
fn run_oneshot_accepts_at_file_input() {
    let dir = tmp("run_atfile");
    let source = dir.join("add.ig");
    fs::write(
        &source,
        "module Lang.Examples.Add\ncontract Add {\n  input a: Integer\n  input b: Integer\n  compute sum = a + b\n  output sum: Integer\n}\n",
    )
    .unwrap();
    let input_file = dir.join("inputs.json");
    fs::write(&input_file, r#"{"a":100,"b":1}"#).unwrap();

    let at_arg = format!("@{}", input_file.display());
    let out = Command::new(repl_bin())
        .args(["--run", source.to_str().unwrap(), "Add", &at_arg])
        .output()
        .expect("run igniter-repl --run @file");

    let stdout = String::from_utf8_lossy(&out.stdout);
    assert!(
        out.status.success(),
        "one-shot @file must exit 0:\n{stdout}\n{}",
        String::from_utf8_lossy(&out.stderr)
    );
    assert!(stdout.contains("101"), "Add(100,1)=101:\n{stdout}");
}

/// Bad JSON input fails non-zero with a diagnostic naming the input problem.
#[test]
fn run_oneshot_bad_json_fails_nonzero() {
    let dir = tmp("run_badjson");
    let source = dir.join("add.ig");
    fs::write(
        &source,
        "module Lang.Examples.Add\ncontract Add {\n  input a: Integer\n  input b: Integer\n  compute sum = a + b\n  output sum: Integer\n}\n",
    )
    .unwrap();

    let out = Command::new(repl_bin())
        .args(["--run", source.to_str().unwrap(), "Add", "not-json{"])
        .output()
        .expect("run igniter-repl --run bad json");

    assert!(!out.status.success(), "bad JSON must fail non-zero");
    let stderr = String::from_utf8_lossy(&out.stderr);
    assert!(
        stderr.contains("input JSON"),
        "stderr must name the input problem:\n{stderr}"
    );
}

/// Bad source (parse/compile error) fails non-zero with a diagnostic.
#[test]
fn run_oneshot_bad_source_fails_nonzero() {
    let dir = tmp("run_badsrc");
    let source = dir.join("broken.ig");
    fs::write(&source, "this is not valid igniter source !!!").unwrap();

    let out = Command::new(repl_bin())
        .args(["--run", source.to_str().unwrap(), "Broken", "{}"])
        .output()
        .expect("run igniter-repl --run bad source");

    assert!(!out.status.success(), "bad source must fail non-zero");
    let stderr = String::from_utf8_lossy(&out.stderr);
    assert!(
        stderr.contains("compile") || stderr.contains("classify") || stderr.contains("error"),
        "stderr must name the compile problem:\n{stderr}"
    );
}

/// Unknown contract name fails non-zero.
#[test]
fn run_oneshot_unknown_contract_fails_nonzero() {
    let dir = tmp("run_unknown");
    let source = dir.join("add.ig");
    fs::write(
        &source,
        "module Lang.Examples.Add\ncontract Add {\n  input a: Integer\n  input b: Integer\n  compute sum = a + b\n  output sum: Integer\n}\n",
    )
    .unwrap();

    let out = Command::new(repl_bin())
        .args(["--run", source.to_str().unwrap(), "DoesNotExist", "{}"])
        .output()
        .expect("run igniter-repl --run unknown");

    assert!(!out.status.success(), "unknown contract must fail non-zero");
    let stderr = String::from_utf8_lossy(&out.stderr);
    assert!(
        stderr.contains("error"),
        "stderr must name the problem:\n{stderr}"
    );
}

/// Failure path: a bad checkpoint/resume path also fails non-zero (proves resume errors are surfaced).
#[test]
fn script_with_bad_resume_path_fails_nonzero() {
    let dir = tmp("badresume");
    let script = dir.join("badresume.script");
    fs::write(&script, "resume /nonexistent/does-not-exist.igm\n").unwrap();

    let out = Command::new(repl_bin())
        .args(["--script", script.to_str().unwrap()])
        .output()
        .expect("run igniter-repl --script (bad resume)");
    let stdout = String::from_utf8_lossy(&out.stdout);
    assert!(
        !out.status.success(),
        "a bad resume must fail non-zero:\n{stdout}"
    );
    assert!(
        stdout.contains("igniter-repl: SCRIPT FAILED"),
        "failure marker:\n{stdout}"
    );
}
