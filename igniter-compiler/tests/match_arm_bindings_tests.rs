// tests/match_arm_bindings_tests.rs — LAB-LANG-MATCH-ARM-BINDINGS-P2
// Branch-local `let` bindings now work in `if` blocks AND `match` arm blocks. Root cause fixed: a block's
// `let name = expr` binds `name` in a block-local scope (typechecker `infer_block_scope`), and a match arm
// body may be a `{ ... }` block (`Expr::Block`) that lowers like a function/if body to a `let`-chain (no
// new SIR node kind). Proven end-to-end via the real compiler binary.

use std::process::Command;

fn bin() -> &'static str {
    env!("CARGO_BIN_EXE_igniter_compiler")
}

/// Compile one `.ig` source through the real binary; return its stdout (the result JSON text).
fn compile(src: &str, tag: &str) -> String {
    let dir = std::env::temp_dir().join(format!("marm_{}_{}", tag, std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let f = dir.join("m.ig");
    std::fs::write(&f, src).unwrap();
    let out = dir.join("m.igapp");
    let output = Command::new(bin())
        .args([
            "compile",
            f.to_str().unwrap(),
            "--out",
            out.to_str().unwrap(),
        ])
        .output()
        .expect("run igniter_compiler");
    String::from_utf8_lossy(&output.stdout).to_string()
}

fn is_ok(stdout: &str) -> bool {
    stdout.contains("\"status\": \"ok\"")
}

// ── 1: block-local `let` in an if-branch binds + compiles (was OOF-P1) ────────────────────────────

#[test]
fn if_block_let_binds_and_compiles() {
    let src = "contract LetIf {
  input x : Integer
  compute r : Integer = if x == 1 { let a = x  a } else { 0 }
  output r : Integer
}";
    assert!(
        is_ok(&compile(src, "letif")),
        "if-block let must compile: {}",
        compile(src, "letif")
    );
}

// ── 2: block-local names do not leak past their block ─────────────────────────────────────────────

#[test]
fn block_local_let_does_not_leak() {
    // `a` is bound in the THEN block; the ELSE block must not see it.
    let src = "contract Leak {
  input x : Integer
  compute r : Integer = if x == 1 { let a = x  a } else { a }
  output r : Integer
}";
    let out = compile(src, "leak");
    assert!(!is_ok(&out), "leaked block-local must NOT compile");
    assert!(
        out.contains("Unresolved symbol: a"),
        "expected unresolved `a`: {out}"
    );
}

// ── 3: match arm may be a block with local lets, available to the arm's final expression ─────────

#[test]
fn match_arm_block_with_local_lets() {
    let src = "contract TwoLets {
  input r : Result[Integer, Integer]
  compute d : Integer = match r {
    Ok { value } => {
      let a = value
      let b = a
      b
    }
    Err { error } => error
  }
  output d : Integer
}";
    assert!(
        is_ok(&compile(src, "twolets")),
        "match-arm block must compile: {}",
        compile(src, "twolets")
    );
}

// ── 4: nested Result — rename outer `value` with a let so the inner match doesn't shadow it ──────

#[test]
fn nested_result_rename_avoids_shadowing() {
    let src = "contract Nest {
  input r : Result[Integer, Integer]
  compute d : Integer = match r {
    Ok { value } => {
      let outer = value
      match r {
        Ok { value } => outer
        Err { error } => error
      }
    }
    Err { error } => error
  }
  output d : Integer
}";
    assert!(
        is_ok(&compile(src, "nest")),
        "nested Result with renamed outer value must compile: {}",
        compile(src, "nest")
    );
}

// ── 5: non-web arithmetic block (let chain in an if-branch) ───────────────────────────────────────

#[test]
fn arithmetic_block_let_chain() {
    let src = "contract Calc {
  input x : Integer
  compute r : Integer = if x == 1 { let a = x  let b = a  b } else { 0 }
  output r : Integer
}";
    assert!(
        is_ok(&compile(src, "calc")),
        "arithmetic block let-chain must compile: {}",
        compile(src, "calc")
    );
}

// ── 6: a plain (non-block) match arm still works — no regression ──────────────────────────────────

#[test]
fn plain_match_arm_still_compiles() {
    let src = "contract Plain {
  input r : Result[Integer, Integer]
  compute d : Integer = match r {
    Ok { value } => value
    Err { error } => error
  }
  output d : Integer
}";
    assert!(
        is_ok(&compile(src, "plain")),
        "plain match arm must still compile: {}",
        compile(src, "plain")
    );
}

// ── 7: LAB-COMPILER-MATCH-ARM-RECORD-LITERAL-FIX-P1 — an arm body that starts with `{` is a record
//        literal, not a forced block. Was `Unexpected token in expression: Colon` (web_router Respond).
#[test]
fn match_arm_record_literal_body_compiles() {
    let src = "type Resp {
  status : Integer
  body   : String
}
contract Compose {
  input r : Result[String, String]
  compute resp : Resp = match r {
    Ok  { value } => { status: 200, body: value }
    Err { error } => { status: 500, body: error }
  }
  output resp : Resp
}";
    assert!(
        is_ok(&compile(src, "armrecord")),
        "match arm record-literal body must compile: {}",
        compile(src, "armrecord")
    );
}
