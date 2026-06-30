// tests/collection_comprehension_tests.rs — LAB-LANG-COLLECTION-COMPREHENSION-P2
// `[ E for x in C (if P)? ]` is pure parse-time sugar over the proven map/filter substrate:
//   [ E for x in C ]      → map(C, x -> E)
//   [ E for x in C if P ] → map(filter(C, x -> P), x -> E)
// No new SIR node kind; the comprehension's SIR is byte-identical to the explicit map/filter form.
// Diagnostics (non-collection source, non-bool predicate) are inherited from map/filter.

use std::path::PathBuf;
use std::process::Command;

fn bin() -> &'static str {
    env!("CARGO_BIN_EXE_igniter_compiler")
}

fn compile(src: &str, tag: &str) -> (String, PathBuf) {
    let dir = std::env::temp_dir().join(format!("comp_{}_{}", tag, std::process::id()));
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

fn is_ok(s: &str) -> bool {
    s.contains("\"status\": \"ok\"")
}

const TODO: &str = "type Todo { title : Text  done : Bool }\n";

// ── happy paths ───────────────────────────────────────────────────────────────────────────────────

#[test]
fn comprehension_no_filter_compiles() {
    let src = format!(
        "{TODO}contract C {{ input todos : Collection[Todo]  compute out : Collection[Text] = [ t.title for t in todos ]  output out : Collection[Text] }}"
    );
    assert!(
        is_ok(&compile(&src, "nofilter").0),
        "comprehension must compile"
    );
}

#[test]
fn comprehension_with_filter_compiles() {
    let src = format!(
        "{TODO}contract C {{ input todos : Collection[Todo]  compute out : Collection[Text] = [ t.title for t in todos if t.done == false ]  output out : Collection[Text] }}"
    );
    assert!(
        is_ok(&compile(&src, "filter").0),
        "filtered comprehension must compile"
    );
}

#[test]
fn outer_node_capture_works() {
    let src = format!(
        "{TODO}contract C {{ input todos : Collection[Todo]  input prefix : Text  compute out : Collection[Text] = [ concat(prefix, t.title) for t in todos ]  output out : Collection[Text] }}"
    );
    assert!(
        is_ok(&compile(&src, "capture").0),
        "element expr must capture outer node `prefix`"
    );
}

// ── scope ─────────────────────────────────────────────────────────────────────────────────────────

#[test]
fn item_var_does_not_leak() {
    // `t` is bound only inside the comprehension (it is the lambda param); referencing it outside fails.
    let src = format!(
        "{TODO}contract C {{ input todos : Collection[Todo]  compute out : Collection[Text] = [ t.title for t in todos ]  compute leak : Text = t.title  output out : Collection[Text]  output leak : Text }}"
    );
    let (o, _) = compile(&src, "leak");
    assert!(!is_ok(&o));
    assert!(
        o.contains("Unresolved symbol: t"),
        "item var must be comprehension-local: {o}"
    );
}

// ── inherited diagnostics ──────────────────────────────────────────────────────────────────────────

#[test]
fn non_collection_source_rejected() {
    let src = "contract C { input n : Integer  compute out : Collection[Integer] = [ x for x in n ]  output out : Collection[Integer] }";
    let (o, _) = compile(src, "noncoll");
    assert!(!is_ok(&o));
    assert!(
        o.contains("must be Collection"),
        "non-collection source must be rejected: {o}"
    );
}

#[test]
fn non_bool_predicate_rejected() {
    let src = format!(
        "{TODO}contract C {{ input todos : Collection[Todo]  compute out : Collection[Text] = [ t.title for t in todos if t.title ]  output out : Collection[Text] }}"
    );
    let (o, _) = compile(&src, "nonbool");
    assert!(!is_ok(&o));
    assert!(
        o.contains("predicate must return Bool"),
        "non-bool predicate must be rejected: {o}"
    );
}

// ── no regression on ordinary array literals ────────────────────────────────────────────────────────

#[test]
fn ordinary_array_literal_unchanged() {
    let src = "contract C { input a : Integer  compute out : Collection[Integer] = [ a, a, a ]  output out : Collection[Integer] }";
    assert!(
        is_ok(&compile(src, "arr").0),
        "ordinary array must still parse"
    );
}

#[test]
fn empty_array_literal_unchanged() {
    let src =
        "contract C { compute out : Collection[Integer] = [ ]  output out : Collection[Integer] }";
    assert!(
        is_ok(&compile(src, "empty").0),
        "empty array must still parse"
    );
}

// ── ViewArtifact-style Collection[HtmlNode] list ────────────────────────────────────────────────────
// A comprehension whose element is a record literal builds Collection[HtmlNode] directly. Note this is
// strictly MORE expressive than the explicit `map(…, t -> { … })`, whose `{` after `->` parses as a lambda
// *block* (not a record) — the comprehension forces the element into expression position, disambiguating it.

#[test]
fn viewartifact_html_node_list_compiles() {
    let src = "type Todo { title : Text  done : Bool }
type HtmlNode { tag : Text  text : Text }
contract View { input todos : Collection[Todo]  compute body : Collection[HtmlNode] = [ { tag: t.title, text: t.title } for t in todos if t.done == false ]  output body : Collection[HtmlNode] }";
    assert!(
        is_ok(&compile(src, "html").0),
        "Collection[HtmlNode] comprehension must compile"
    );
}

// ── serialization parity: comprehension SIR == explicit map/filter SIR ──────────────────────────────

fn call_nodes(dir: &PathBuf) -> String {
    let sir: serde_json::Value = serde_json::from_str(
        &std::fs::read_to_string(dir.join("semantic_ir_program.json")).unwrap(),
    )
    .unwrap();
    let mut nodes = Vec::new();
    fn walk(v: &serde_json::Value, out: &mut Vec<serde_json::Value>) {
        match v {
            serde_json::Value::Object(m) => {
                if matches!(
                    m.get("kind").and_then(|k| k.as_str()),
                    Some("call") | Some("lambda")
                ) {
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
fn comprehension_sir_identical_to_explicit_map_filter() {
    let comp = format!(
        "{TODO}contract C {{ input todos : Collection[Todo]  compute out : Collection[Text] = [ t.title for t in todos if t.done == false ]  output out : Collection[Text] }}"
    );
    let expl = format!(
        "{TODO}contract C {{ input todos : Collection[Todo]  compute out : Collection[Text] = map(filter(todos, t -> t.done == false), t -> t.title)  output out : Collection[Text] }}"
    );
    let (co, cd) = compile(&comp, "par_comp");
    let (eo, ed) = compile(&expl, "par_expl");
    assert!(is_ok(&co) && is_ok(&eo), "both must compile");
    assert_eq!(
        call_nodes(&cd),
        call_nodes(&ed),
        "comprehension map/filter/lambda SIR must equal the explicit form"
    );
}
