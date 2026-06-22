// tests/record_spread_tests.rs — LAB-LANG-RECORD-SPREAD-P2
// Record spread/update `{ ...base, field: value }` is pure sugar: the typechecker expands it to an explicit
// field-by-field `record_literal` once the target record type is known (copying the fields the TARGET
// declares AND the SOURCE has; explicit fields override), then the emitter lowers it via the normal
// record path — byte-identical to writing the explicit literal. No optional fields, no defaults, no
// runtime reflection. Proven end-to-end via the real compiler binary.

use std::path::PathBuf;
use std::process::Command;

fn bin() -> &'static str {
    env!("CARGO_BIN_EXE_igniter_compiler")
}

/// Compile one `.ig` source; return (stdout, output_dir).
fn compile(src: &str, tag: &str) -> (String, PathBuf) {
    let dir = std::env::temp_dir().join(format!("spread_{}_{}", tag, std::process::id()));
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
    (String::from_utf8_lossy(&output.stdout).to_string(), out)
}

fn is_ok(stdout: &str) -> bool {
    stdout.contains("\"status\": \"ok\"")
}

const COUNTER: &str = "type Counter { count : Integer  label : Text }\n";
const CTX: &str = "type Ctx { user : Text }\ntype Ctx2 { user : Text  todo_id : Integer }\n";

// ── happy paths ───────────────────────────────────────────────────────────────────────────────────

#[test]
fn same_type_update_compiles() {
    let src = format!(
        "{COUNTER}contract Bump {{ input counter : Counter  compute bumped : Counter = {{ ...counter, count: counter.count + 1 }}  output bumped : Counter }}"
    );
    assert!(
        is_ok(&compile(&src, "same").0),
        "same-type update must compile"
    );
}

#[test]
fn accumulation_source_subset_of_target_compiles() {
    let src = format!(
        "{CTX}contract Enrich {{ input ctx : Ctx  input todo_id : Integer  compute enriched : Ctx2 = {{ ...ctx, todo_id: todo_id }}  output enriched : Ctx2 }}"
    );
    assert!(
        is_ok(&compile(&src, "accum").0),
        "accumulation must compile"
    );
}

#[test]
fn explicit_field_override_compiles() {
    let src = format!(
        "{COUNTER}contract Ov {{ input counter : Counter  compute r : Counter = {{ ...counter, count: 99 }}  output r : Counter }}"
    );
    assert!(
        is_ok(&compile(&src, "ov").0),
        "explicit override must compile"
    );
}

// ── rejections ──────────────────────────────────────────────────────────────────────────────────

#[test]
fn duplicate_explicit_field_rejected() {
    let src = format!(
        "{COUNTER}contract Dup {{ input counter : Counter  compute r : Counter = {{ ...counter, count: 1, count: 2 }}  output r : Counter }}"
    );
    let (out, _) = compile(&src, "dup");
    assert!(!is_ok(&out));
    assert!(
        out.contains("duplicate field"),
        "expected duplicate-field error: {out}"
    );
}

#[test]
fn non_record_source_rejected() {
    let src = format!(
        "{COUNTER}contract Bad {{ input n : Integer  compute r : Counter = {{ ...n, count: 1, label: \"x\" }}  output r : Counter }}"
    );
    let (out, _) = compile(&src, "nonrec");
    assert!(!is_ok(&out));
    assert!(
        out.contains("record spread source must be a known record type"),
        "got: {out}"
    );
}

#[test]
fn extra_explicit_field_rejected() {
    let src = format!(
        "{COUNTER}contract Extra {{ input counter : Counter  compute r : Counter = {{ ...counter, nope: 1 }}  output r : Counter }}"
    );
    assert!(
        !is_ok(&compile(&src, "extra").0),
        "extra field must be rejected by shape checker"
    );
}

#[test]
fn missing_required_field_rejected() {
    // target Ctx2 needs todo_id; source Ctx lacks it and it is not supplied explicitly.
    let src = format!(
        "{CTX}contract Miss {{ input ctx : Ctx  compute r : Ctx2 = {{ ...ctx, user: ctx.user }}  output r : Ctx2 }}"
    );
    assert!(
        !is_ok(&compile(&src, "miss").0),
        "missing required field must be rejected"
    );
}

#[test]
fn nested_spread_rejected() {
    let src = format!(
        "{COUNTER}contract Nest {{ input counter : Counter  compute r : Collection[Counter] = [ {{ ...counter, count: 1 }} ]  output r : Collection[Counter] }}"
    );
    let (out, _) = compile(&src, "nested");
    assert!(!is_ok(&out));
    assert!(
        out.contains("only supported at the top level"),
        "got: {out}"
    );
}

// ── serialization parity: spread desugars to exactly the explicit record literal ─────────────────

fn record_literal_nodes(dir: &PathBuf) -> String {
    let sir: serde_json::Value = serde_json::from_str(
        &std::fs::read_to_string(dir.join("semantic_ir_program.json")).unwrap(),
    )
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
fn spread_serializes_identically_to_explicit_literal() {
    let spread = format!(
        "{COUNTER}contract S {{ input counter : Counter  compute bumped : Counter = {{ ...counter, count: counter.count + 1 }}  output bumped : Counter }}"
    );
    let explicit = format!(
        "{COUNTER}contract S {{ input counter : Counter  compute bumped : Counter = {{ count: counter.count + 1, label: counter.label }}  output bumped : Counter }}"
    );
    let (so, sd) = compile(&spread, "par_spread");
    let (eo, ed) = compile(&explicit, "par_explicit");
    assert!(is_ok(&so) && is_ok(&eo), "both must compile");
    // the emitted record VALUE is byte-identical (spread is pure sugar)
    assert_eq!(
        record_literal_nodes(&sd),
        record_literal_nodes(&ed),
        "spread record SIR must equal the explicit literal SIR"
    );
    // and the spread leaves NO record_spread node in the emitted SIR (fully expanded)
    let sir = std::fs::read_to_string(sd.join("semantic_ir_program.json")).unwrap();
    assert!(
        !sir.contains("record_spread"),
        "SIR must contain no record_spread (expanded)"
    );
}
