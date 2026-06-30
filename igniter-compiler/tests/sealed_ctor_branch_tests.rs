// tests/sealed_ctor_branch_tests.rs — LAB-IGNITER-WEB-COMPOSITE-GUARD-RUNTIME-P24
// Root-cause regression: built-in sealed constructors (ok/err/some/none) used INSIDE an `if`/`match`
// branch must lower to a tagged `variant_construct` (arm "Ok"/"Err"/…), exactly like at a compute-decl
// top level — not to an untagged `{ ok: x }` record (which compiled, passed `check`, then 500'd at
// dispatch, per the P23 finding). We compile a tiny program and assert the emitted SemanticIR.

use std::process::Command;

fn bin() -> &'static str {
    env!("CARGO_BIN_EXE_igniter_compiler")
}

const BRANCH_CTOR: &str = "\
module M

variant Decision {
  Respond { status : Integer, body : String }
}

pure contract Guard {
  input flag : Bool
  input v    : Option[String]
  compute r : Result[Option[String], Decision] = if flag {
    ok(v)
  } else {
    err(Respond { status: 404, body: \"no\" })
  }
  output r : Result[Option[String], Decision]
}
";

#[test]
fn sealed_ctor_in_if_branch_lowers_to_tagged_variant() {
    let dir = std::env::temp_dir().join(format!("igc_p24_{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let src = dir.join("m.ig");
    let out = dir.join("m.igapp");
    std::fs::write(&src, BRANCH_CTOR).unwrap();

    let output = Command::new(bin())
        .args([
            "compile",
            src.to_str().unwrap(),
            "--out",
            out.to_str().unwrap(),
        ])
        .output()
        .expect("run igniter_compiler");
    let stdout = String::from_utf8_lossy(&output.stdout).to_string();
    assert!(output.status.success(), "compile must succeed.\n{stdout}");
    assert!(
        !stdout.contains("OOF-"),
        "no diagnostics expected.\n{stdout}"
    );

    // The emitted SemanticIR carries the branch constructors as TAGGED sealed variants.
    let sir = std::fs::read_to_string(out.join("semantic_ir_program.json"))
        .expect("semantic_ir_program.json");
    assert!(
        sir.contains("variant_construct"),
        "branch ctors must lower to variant_construct nodes"
    );
    assert!(
        sir.contains("\"arm\": \"Ok\""),
        "the `ok(v)` in the if-branch must carry arm \"Ok\".\n{sir}"
    );
    assert!(
        sir.contains("\"arm\": \"Err\""),
        "the `err(..)` in the else-branch must carry arm \"Err\".\n{sir}"
    );
}
