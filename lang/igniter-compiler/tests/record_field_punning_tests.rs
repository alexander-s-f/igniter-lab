// tests/record_field_punning_tests.rs — LAB-LANG-RECORD-FIELD-PUNNING-P2
// `{ name }` is pure parse-time sugar for `{ name: name }` (a `Ref`). It composes with explicit fields and
// with record spread (`{ ...base, name }`). No new node kind — the record literal/spread sees the canonical
// `{ name: <ref> }`, so the SIR is byte-identical to writing it out. Missing/extra fields fall through the
// normal unknown-symbol / record-shape paths.

use std::path::PathBuf;
use std::process::Command;

fn bin() -> &'static str {
    env!("CARGO_BIN_EXE_igniter_compiler")
}

fn compile(src: &str, tag: &str) -> (String, PathBuf) {
    let dir = std::env::temp_dir().join(format!("pun_{}_{}", tag, std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let f = dir.join("m.ig");
    std::fs::write(&f, src).unwrap();
    let out = dir.join("out");
    let o = Command::new(bin())
        .args(["compile", f.to_str().unwrap(), "--out", out.to_str().unwrap()])
        .output()
        .expect("run igniter_compiler");
    (String::from_utf8_lossy(&o.stdout).to_string(), out)
}

fn ok(s: &str) -> bool {
    s.contains("\"status\": \"ok\"")
}

const WV: &str = "type WV { account_id : String  title : String  done : String }\n";

// ── happy paths ───────────────────────────────────────────────────────────────────────────────────

#[test]
fn pure_punning_compiles() {
    let src = format!(
        "{WV}pure contract C {{ input account_id : String  input title : String  input done : String  compute v : WV = {{ account_id, title, done }}  output v : WV }}"
    );
    assert!(ok(&compile(&src, "pure").0), "punned record must compile");
}

#[test]
fn mixed_punned_and_explicit_compiles() {
    let src = "type QF { field : String  op : String  value : String }
pure contract C { input value : String  compute f : QF = { field: \"account_id\", op: \"eq\", value }  output f : QF }";
    assert!(ok(&compile(src, "mixed").0), "mixed punned + explicit must compile");
}

#[test]
fn spread_with_punning_compiles() {
    let src = "type Ctx { account_id : String  todo_id : String }
pure contract C { input ctx : Ctx  input todo_id : String  compute next : Ctx = { ...ctx, todo_id }  output next : Ctx }";
    assert!(ok(&compile(src, "spread").0), "spread + punning must compile");
}

// ── failures fall through normal paths ───────────────────────────────────────────────────────────

#[test]
fn missing_symbol_punned_rejected() {
    let src = "type WV { account_id : String }
pure contract C { compute v : WV = { account_id }  output v : WV }";
    let (o, _) = compile(src, "missing");
    assert!(!ok(&o));
    assert!(o.contains("Unresolved symbol: account_id"), "missing punned symbol path: {o}");
}

#[test]
fn unexpected_punned_field_rejected() {
    let src = "type WV { account_id : String }
pure contract C { input account_id : String  input nope : String  compute v : WV = { account_id, nope }  output v : WV }";
    let (o, _) = compile(src, "extra");
    assert!(!ok(&o));
    assert!(o.contains("unexpected field"), "extra punned field shape path: {o}");
}

#[test]
fn dotted_punning_is_a_parse_error() {
    let src = "type WV { id : String }
pure contract C { input account : String  compute v : WV = { account.id }  output v : WV }";
    assert!(!ok(&compile(src, "dotted").0), "dotted punning must not compile");
}

// ── Todo-shaped app-pressure fixture (WriteValues with punning) ──────────────────────────────────────

#[test]
fn todo_writevalues_punning_compiles() {
    // Mirrors todo_handlers.ig MakeWriteValues, written with punning.
    let src = "type WriteValues { account_id : String  title : String  done : String }
pure contract MakeWriteValues { input account_id : String  input title : String  input done : String  compute v : WriteValues = { account_id, title, done }  output v : WriteValues }";
    assert!(ok(&compile(src, "todo").0), "Todo WriteValues punning must compile");
}

// ── serialization parity: punned == explicit ────────────────────────────────────────────────────────

fn record_nodes(dir: &PathBuf) -> String {
    let sir: serde_json::Value =
        serde_json::from_str(&std::fs::read_to_string(dir.join("semantic_ir_program.json")).unwrap())
            .unwrap();
    let mut nodes = Vec::new();
    fn walk(v: &serde_json::Value, out: &mut Vec<serde_json::Value>) {
        match v {
            serde_json::Value::Object(m) => {
                if m.get("kind").and_then(|k| k.as_str()) == Some("record_literal") {
                    out.push(v.clone());
                }
                for x in m.values() {
                    walk(x, out);
                }
            }
            serde_json::Value::Array(a) => a.iter().for_each(|x| walk(x, out)),
            _ => {}
        }
    }
    walk(&sir, &mut nodes);
    serde_json::to_string(&nodes).unwrap()
}

#[test]
fn punned_record_sir_identical_to_explicit() {
    let punned = format!(
        "{WV}pure contract C {{ input account_id : String  input title : String  input done : String  compute v : WV = {{ account_id, title, done }}  output v : WV }}"
    );
    let explicit = format!(
        "{WV}pure contract C {{ input account_id : String  input title : String  input done : String  compute v : WV = {{ account_id: account_id, title: title, done: done }}  output v : WV }}"
    );
    let (po, pd) = compile(&punned, "par_pun");
    let (eo, ed) = compile(&explicit, "par_exp");
    assert!(ok(&po) && ok(&eo), "both must compile");
    assert_eq!(record_nodes(&pd), record_nodes(&ed), "punned record SIR must equal explicit");
}
