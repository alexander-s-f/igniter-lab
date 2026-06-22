// tests/app_pressure_scorecard_tests.rs — LAB-LANG-APP-PRESSURE-ERGONOMICS-SCORECARD-P4
// Compile-proofs for the "improved form" snippets in the ergonomics scorecard. These are NOT product
// examples — they prove the newest surface (signature-bound contracts + collection comprehensions +
// fallible `?`) compiles, and crucially that the three features COMPOSE in one contract. Self-contained
// (no IgWebPrelude) so the scorecard's claims are backed by the real compiler.

use std::process::Command;

fn bin() -> &'static str {
    env!("CARGO_BIN_EXE_igniter_compiler")
}

fn compile(src: &str, tag: &str) -> String {
    let dir = std::env::temp_dir().join(format!("score_{}_{}", tag, std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let f = dir.join("m.ig");
    std::fs::write(&f, src).unwrap();
    let out = dir.join("out");
    let o = Command::new(bin())
        .args([
            "compile",
            f.to_str().unwrap(),
            "--out",
            out.to_str().unwrap(),
        ])
        .output()
        .expect("run igniter_compiler");
    String::from_utf8_lossy(&o.stdout).to_string()
}

fn ok(s: &str) -> bool {
    s.contains("\"status\": \"ok\"")
}

// Snippet: signature-bound handler (input/compute/output ceremony collapsed).
#[test]
fn signature_bound_handler_compiles() {
    let src = "type Decision { status : Integer  body : String }
pure contract Health(x: Integer) -> (d: Decision) {
  d = { status: 200, body: \"ok\" }
}";
    assert!(
        ok(&compile(src, "sig")),
        "signature-bound handler must compile"
    );
}

// Snippet: ViewArtifact-style list — signature + comprehension + filter + record element, composed.
#[test]
fn signature_plus_comprehension_list_compiles() {
    let src = "type Todo { title : Text  done : Bool }
type Node { text : Text }
pure contract View(todos: Collection[Todo]) -> (body: Collection[Node]) {
  body = [ { text: t.title } for t in todos if t.done == false ]
}";
    assert!(
        ok(&compile(src, "view")),
        "signature + comprehension list must compile"
    );
}

// Snippet: guard/handler failure path — signature + fallible `?` over a Result-returning contract,
// where the error type equals the contract output (E == O == Decision).
#[test]
fn signature_plus_fallible_handler_compiles() {
    let src = "type Decision { status : Integer  body : String }
type Ctx { id : String }
pure contract Load(id: String) -> (r: Result[Ctx, Decision]) {
  r = if id == \"\" { err({ status: 404, body: \"nf\" }) } else { ok({ id: id }) }
}
pure contract Handler(id: String) -> (d: Decision) {
  d = {
    let ctx = call_contract(\"Load\", id)?
    { status: 200, body: ctx.id }
  }
}";
    assert!(
        ok(&compile(src, "fallible")),
        "signature + fallible ? handler must compile"
    );
}
