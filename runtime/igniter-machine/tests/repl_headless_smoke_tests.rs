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
