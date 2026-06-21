// tests/fallible_binding_tests.rs — LAB-LANG-FALLIBLE-BINDING-P2
// Result-only postfix `?`. `let name = expr?` inside an output-producing block desugars (in the parser) to
// a nested `match expr { Ok { value } => { let name = value  <rest…> }  Err { error } => error }`, reusing
// MATCH-ARM-BINDINGS-P2. The `Err` payload becomes the contract output, so the existing match arm-type
// unification enforces `E == O`. Pure sugar — no new SIR node kind; the `?` SIR is byte-identical to the
// hand-written match. Proven end-to-end via the real compiler binary.

use std::path::PathBuf;
use std::process::Command;

fn bin() -> &'static str {
    env!("CARGO_BIN_EXE_igniter_compiler")
}

fn compile(src: &str, tag: &str) -> (String, PathBuf) {
    let dir = std::env::temp_dir().join(format!("fb_{}_{}", tag, std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let f = dir.join("m.ig");
    std::fs::write(&f, src).unwrap();
    let out = dir.join("out");
    let output = Command::new(bin())
        .args(["compile", f.to_str().unwrap(), "--out", out.to_str().unwrap()])
        .output()
        .expect("run igniter_compiler");
    (String::from_utf8_lossy(&output.stdout).to_string(), out)
}

fn is_ok(s: &str) -> bool {
    s.contains("\"status\": \"ok\"")
}

const TYPES: &str = "type Decision { code : Integer }\ntype Acct { id : Integer }\ntype Todo { title : Integer }\n";

#[test]
fn single_question_binds_and_compiles() {
    let src = format!(
        "{TYPES}contract H {{ input r : Result[Acct, Decision]  compute d : Decision = {{ let account = r?  {{ code: account.id }} }}  output d : Decision }}"
    );
    assert!(is_ok(&compile(&src, "single").0), "single ? must compile");
}

#[test]
fn chained_two_questions_no_shadowing() {
    let src = format!(
        "{TYPES}contract H {{ input r : Result[Acct, Decision]  input r2 : Result[Todo, Decision]  compute d : Decision = {{ let account = r?  let todo = r2?  {{ code: todo.title }} }}  output d : Decision }}"
    );
    assert!(is_ok(&compile(&src, "chain").0), "chained ? must compile");
}

#[test]
fn igweb_style_guard_chain_compiles() {
    // Result[T, Decision] guard shape: each `?` short-circuits to the Decision output.
    let src = format!(
        "{TYPES}contract Guard {{ input load_account : Result[Acct, Decision]  input load_todo : Result[Todo, Decision]  compute d : Decision = {{ let account = load_account?  let todo = load_todo?  {{ code: todo.title }} }}  output d : Decision }}"
    );
    assert!(is_ok(&compile(&src, "guard").0), "IgWeb-style guard chain must compile");
}

#[test]
fn pure_contract_with_question_stays_pure() {
    let src = format!(
        "{TYPES}pure contract H {{ input r : Result[Acct, Decision]  compute d : Decision = {{ let account = r?  {{ code: account.id }} }}  output d : Decision }}"
    );
    assert!(is_ok(&compile(&src, "pure").0), "pure contract with ? must compile");
}

#[test]
fn question_on_non_result_rejected() {
    let src = format!(
        "{TYPES}contract H {{ input n : Integer  compute d : Decision = {{ let x = n?  {{ code: x }} }}  output d : Decision }}"
    );
    let (out, _) = compile(&src, "nonres");
    assert!(!is_ok(&out));
    assert!(out.contains("? applies only to Result"), "expected OOF-Q1: {out}");
}

#[test]
fn question_on_option_rejected_v0() {
    let src = format!(
        "{TYPES}contract H {{ input o : Option[Integer]  compute d : Decision = {{ let x = o?  {{ code: x }} }}  output d : Decision }}"
    );
    let (out, _) = compile(&src, "opt");
    assert!(!is_ok(&out));
    assert!(out.contains("not supported on Option in v0"), "expected Option-v0 OOF-Q1: {out}");
}

#[test]
fn err_type_incompatible_with_output_rejected() {
    let src = format!(
        "{TYPES}type Other {{ z : Integer }}\ncontract H {{ input r : Result[Acct, Other]  compute d : Decision = {{ let account = r?  {{ code: account.id }} }}  output d : Decision }}"
    );
    assert!(!is_ok(&compile(&src, "eo").0), "E != O must be rejected");
}

#[test]
fn question_outside_binding_rejected() {
    let src = format!(
        "{TYPES}contract H {{ input r : Result[Acct, Decision]  compute d : Decision = r?  output d : Decision }}"
    );
    let (out, _) = compile(&src, "misplaced");
    assert!(!is_ok(&out));
    assert!(out.contains("OOF-Q3") || out.contains("only allowed as a `let` binding"), "expected OOF-Q3: {out}");
}

#[test]
fn handwritten_result_match_still_compiles() {
    // regression: the OOF-Q1 branding must not affect a real Result match.
    let src = "contract H { input r : Result[Integer, Integer]  compute d : Integer = match r { Ok { value } => value  Err { error } => error }  output d : Integer }";
    assert!(is_ok(&compile(src, "handok").0), "hand-written Result match must still compile");
}

// ── SIR parity: `?` desugars to exactly the hand-written nested match ─────────────────────────────

fn match_nodes(dir: &PathBuf) -> String {
    let sir: serde_json::Value =
        serde_json::from_str(&std::fs::read_to_string(dir.join("semantic_ir_program.json")).unwrap())
            .unwrap();
    let mut nodes = Vec::new();
    fn walk(v: &serde_json::Value, out: &mut Vec<serde_json::Value>) {
        match v {
            serde_json::Value::Object(m) => {
                if m.get("kind").and_then(|k| k.as_str()) == Some("match_node") {
                    out.push(v.clone());
                }
                for x in m.values() {
                    walk(x, out);
                }
            }
            serde_json::Value::Array(a) => {
                for x in a {
                    walk(x, out);
                }
            }
            _ => {}
        }
    }
    walk(&sir, &mut nodes);
    serde_json::to_string(&nodes).unwrap()
}

#[test]
fn question_sir_identical_to_handwritten_match() {
    let sugar = format!(
        "{TYPES}contract H {{ input r : Result[Acct, Decision]  compute d : Decision = {{ let account = r?  {{ code: account.id }} }}  output d : Decision }}"
    );
    let hand = format!(
        "{TYPES}contract H {{ input r : Result[Acct, Decision]  compute d : Decision = match r {{ Ok {{ value }} => {{ let account = value  {{ code: account.id }} }} Err {{ error }} => error }}  output d : Decision }}"
    );
    let (so, sd) = compile(&sugar, "par_sugar");
    let (ho, hd) = compile(&hand, "par_hand");
    assert!(is_ok(&so) && is_ok(&ho), "both must compile");
    assert_eq!(
        match_nodes(&sd),
        match_nodes(&hd),
        "? SIR must be byte-identical to the hand-written nested match"
    );
    // and no `try` node survives into the SIR
    let sir = std::fs::read_to_string(sd.join("semantic_ir_program.json")).unwrap();
    assert!(!sir.contains("\"kind\": \"try\""), "no `try` node may reach the SIR");
}
