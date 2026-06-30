// tests/variant_field_generic_param_tests.rs — LAB-IGNITER-COMPILER-TYPE-IR-ENUM-P5
//
// Before this slice, variant_construct field checking compared only the OUTER
// type name (`actual_name != expected_name`), so a field declared
// `Collection[Text]` accepted a `Collection[Integer]` value — both are just
// "Collection" by name. The typed `IgType` model now checks type parameters
// structurally, so that name-only mismatch fails closed with `OOF-KIND2`.
//
// We compile tiny programs through the real CLI and assert on the emitted
// diagnostics, exactly like the sibling diagnostic test families.

use std::process::Command;

fn bin() -> &'static str {
    env!("CARGO_BIN_EXE_igniter_compiler")
}

fn compile(src: &str, tag: &str) -> String {
    let dir = std::env::temp_dir().join(format!("igtypeenum_{}_{}", tag, std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let f = dir.join("m.ig");
    std::fs::write(&f, src).unwrap();
    let out = dir.join("out");
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

fn is_ok(s: &str) -> bool {
    s.contains("\"status\": \"ok\"")
}

const MISMATCH: &str = "\
module M

variant Bag {
  Hold { items : Collection[Text] }
}

pure contract C {
  input xs : Collection[Integer]
  compute r : Bag = Hold { items: xs }
  output r : Bag
}
";

const MATCH: &str = "\
module M

variant Bag {
  Hold { items : Collection[Text] }
}

pure contract C {
  input xs : Collection[Text]
  compute r : Bag = Hold { items: xs }
  output r : Bag
}
";

#[test]
fn variant_field_generic_param_mismatch_fails_closed() {
    // The exact name-only mistake this slice closes: `Collection[Integer]` into a
    // `Collection[Text]` field. Previously accepted (outer name "Collection"
    // matched); now rejected by the typed structural check.
    let o = compile(MISMATCH, "mismatch");
    assert!(
        o.contains("OOF-KIND2"),
        "Collection[Integer] into Collection[Text] field must raise OOF-KIND2:\n{o}"
    );
    assert!(
        o.contains("Bag::Hold field 'items': expected Collection[Text], got Collection[Integer]"),
        "diagnostic must name the structural type mismatch with generic params:\n{o}"
    );
}

#[test]
fn variant_field_matching_generic_param_stays_clean() {
    // Control: the same outer name AND matching parameter is still accepted, so
    // the new check did not over-tighten the path.
    let o = compile(MATCH, "match");
    assert!(
        is_ok(&o) && !o.contains("OOF-KIND2"),
        "Collection[Text] into Collection[Text] field must stay clean:\n{o}"
    );
}
