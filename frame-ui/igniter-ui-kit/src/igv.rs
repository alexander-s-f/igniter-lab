//! `.igv` — a tiny lab-only text authoring syntax that LOWERS to the proven ViewArtifact JSON
//! (LAB-FRAME-IGV-BINDING-SYNTAX-P1).
//!
//! `.igv` is SUGAR over the artifact, nothing more:
//!
//! ```text
//! .igv text  ──lower_igv──►  ViewArtifact JSON (serde_json::Value)  ──►  existing view_artifact /
//!                                                                          binding / bridge consumers
//! ```
//!
//! It is NOT Igniter language canon and does not touch `.ig`. The lowering is deterministic
//! (serde_json's default Map = sorted keys; arrays keep order), so the same `.igv` always yields
//! byte-identical JSON. Machine-free.
//!
//! Grammar (line-oriented; `//` comments + blank lines ignored):
//!
//! ```text
//! view <screen> <layout> {
//!   source <name> = <Contract>                       // → sources.<name> = {contract, mode:"read"}
//!   field <id> <kind> "<label>" [a, b, c] required   // → regions.main.fields[]
//!   action <name> = <Contract> {                     // → actions.<name>
//!     input <key> = <expr>                            //   actions.<name>.input.<key>
//!     validate <Contract>                             //   actions.<name>.validate (optional)
//!     effect <capability_id> <operation> <scope>      //   actions.<name>.effect{capability_id,…}
//!   }
//!   sidebar list <source> on_select <action>          // → regions.sidebar
//!   inspector keyvalue <bind>                          // → regions.inspector
//!   submit <action>                                    // → regions.main.submit
//! }
//! ```

use serde_json::{json, Map, Value};

/// A lowering error with a 1-based source line and a stable message.
#[derive(Debug, Clone, PartialEq)]
pub struct IgvError {
    pub line: usize,
    pub msg: String,
}

impl std::fmt::Display for IgvError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, ".igv error (line {}): {}", self.line, self.msg)
    }
}
impl std::error::Error for IgvError {}

fn err(line: usize, msg: impl Into<String>) -> IgvError {
    IgvError {
        line,
        msg: msg.into(),
    }
}

/// Split a logical line into tokens: bare words, a `"quoted label"` (one token, unquoted), and a
/// `[a, b, c]` option list (one token, kept with brackets).
fn tokenize(s: &str) -> Vec<String> {
    let mut out = Vec::new();
    let mut cur = String::new();
    let mut chars = s.chars().peekable();
    let flush = |cur: &mut String, out: &mut Vec<String>| {
        if !cur.is_empty() {
            out.push(std::mem::take(cur));
        }
    };
    while let Some(c) = chars.next() {
        match c {
            '"' => {
                flush(&mut cur, &mut out);
                let mut lit = String::new();
                for n in chars.by_ref() {
                    if n == '"' {
                        break;
                    }
                    lit.push(n);
                }
                out.push(lit);
            }
            '[' => {
                flush(&mut cur, &mut out);
                let mut lst = String::from("[");
                for n in chars.by_ref() {
                    lst.push(n);
                    if n == ']' {
                        break;
                    }
                }
                out.push(lst);
            }
            c if c.is_whitespace() => flush(&mut cur, &mut out),
            _ => cur.push(c),
        }
    }
    flush(&mut cur, &mut out);
    out
}

fn parse_options(tok: &str) -> Vec<String> {
    tok.trim_start_matches('[')
        .trim_end_matches(']')
        .split(',')
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
        .collect()
}

struct ActionBuilder {
    name: String,
    contract: String,
    input: Map<String, Value>,
    validate: Option<String>,
    effect: Option<Value>,
}

/// Lower `.igv` source text into a ViewArtifact JSON `Value`. Deterministic.
pub fn lower_igv(src: &str) -> Result<Value, IgvError> {
    let mut screen: Option<String> = None;
    let mut layout: Option<String> = None;
    let mut sources = Map::new();
    let mut actions = Map::new();
    let mut fields: Vec<Value> = Vec::new();
    let mut sidebar: Option<Value> = None;
    let mut inspector: Option<Value> = None;
    let mut submit: Option<Value> = None;
    let mut cur: Option<ActionBuilder> = None;

    for (idx, raw) in src.lines().enumerate() {
        let line_no = idx + 1;
        // strip `//` comments
        let line = match raw.split_once("//") {
            Some((before, _)) => before,
            None => raw,
        }
        .trim();
        if line.is_empty() {
            continue;
        }
        let t = tokenize(line);
        let kw = t[0].as_str();

        // inside an action block?
        if let Some(act) = cur.as_mut() {
            match kw {
                "input" => {
                    if t.len() < 4 || t[2] != "=" {
                        return Err(err(line_no, "expected: input <key> = <expr>"));
                    }
                    act.input.insert(t[1].clone(), Value::String(t[3].clone()));
                }
                "validate" => {
                    if t.len() < 2 {
                        return Err(err(line_no, "expected: validate <Contract>"));
                    }
                    act.validate = Some(t[1].clone());
                }
                "effect" => {
                    if t.len() < 4 {
                        return Err(err(
                            line_no,
                            "expected: effect <capability_id> <operation> <scope>",
                        ));
                    }
                    act.effect =
                        Some(json!({ "capability_id": t[1], "operation": t[2], "scope": t[3] }));
                }
                "}" => {
                    let act = cur.take().unwrap();
                    let mut a = Map::new();
                    a.insert("contract".into(), Value::String(act.contract));
                    a.insert("input".into(), Value::Object(act.input));
                    if let Some(v) = act.validate {
                        a.insert("validate".into(), Value::String(v));
                    }
                    if let Some(e) = act.effect {
                        a.insert("effect".into(), e);
                    }
                    actions.insert(act.name, Value::Object(a));
                }
                other => {
                    return Err(err(
                        line_no,
                        format!("unknown statement in action block: '{other}'"),
                    ))
                }
            }
            continue;
        }

        match kw {
            "view" => {
                if t.len() < 4 || t[3] != "{" {
                    return Err(err(line_no, "expected: view <screen> <layout> {"));
                }
                screen = Some(t[1].clone());
                layout = Some(t[2].clone());
            }
            "source" => {
                if t.len() < 4 || t[2] != "=" {
                    return Err(err(line_no, "expected: source <name> = <Contract>"));
                }
                sources.insert(t[1].clone(), json!({ "contract": t[3], "mode": "read" }));
            }
            "field" => {
                if t.len() < 4 {
                    return Err(err(
                        line_no,
                        "expected: field <id> <kind> \"<label>\" [options] [required]",
                    ));
                }
                let id = &t[1];
                let kind = &t[2];
                let label = &t[3];
                let mut f = Map::new();
                f.insert("id".into(), Value::String(id.clone()));
                f.insert("kind".into(), Value::String(kind.clone()));
                f.insert("label".into(), Value::String(label.clone()));
                let mut required = false;
                for tok in &t[4..] {
                    if tok.starts_with('[') {
                        f.insert("options".into(), json!(parse_options(tok)));
                    } else if tok == "required" {
                        required = true;
                    } else {
                        return Err(err(line_no, format!("unexpected field modifier: '{tok}'")));
                    }
                }
                if kind == "select" && !f.contains_key("options") {
                    return Err(err(line_no, "a select field needs [options]"));
                }
                f.insert("required".into(), Value::Bool(required));
                fields.push(Value::Object(f));
            }
            "action" => {
                if t.len() < 5 || t[2] != "=" || t[4] != "{" {
                    return Err(err(line_no, "expected: action <name> = <Contract> {"));
                }
                cur = Some(ActionBuilder {
                    name: t[1].clone(),
                    contract: t[3].clone(),
                    input: Map::new(),
                    validate: None,
                    effect: None,
                });
            }
            "sidebar" => {
                if t.len() < 5 || t[1] != "list" || t[3] != "on_select" {
                    return Err(err(
                        line_no,
                        "expected: sidebar list <source> on_select <action>",
                    ));
                }
                sidebar = Some(json!({ "component": "List", "bind": t[2], "on_select": t[4] }));
            }
            "inspector" => {
                if t.len() < 3 || t[1] != "keyvalue" {
                    return Err(err(line_no, "expected: inspector keyvalue <bind>"));
                }
                inspector = Some(json!({ "component": "KeyValuePanel", "bind": t[2] }));
            }
            "submit" => {
                if t.len() < 2 {
                    return Err(err(line_no, "expected: submit <action>"));
                }
                submit = Some(json!({ "label": "Submit", "action": t[1] }));
            }
            "}" => {} // end of the view block
            other => return Err(err(line_no, format!("unknown statement: '{other}'"))),
        }
    }

    if cur.is_some() {
        return Err(err(
            src.lines().count(),
            "unterminated action block (missing '}')",
        ));
    }
    let screen = screen.ok_or_else(|| err(1, "missing `view <screen> <layout> {`"))?;
    let layout = layout.unwrap();
    if fields.is_empty() {
        return Err(err(1, "a workbench needs at least one `field`"));
    }
    let submit = submit.ok_or_else(|| err(1, "missing `submit <action>`"))?;

    let mut main = Map::new();
    main.insert("component".into(), Value::String("Form".into()));
    main.insert("fields".into(), Value::Array(fields));
    main.insert("submit".into(), submit);

    let mut regions = Map::new();
    if let Some(s) = sidebar {
        regions.insert("sidebar".into(), s);
    }
    regions.insert("main".into(), Value::Object(main));
    if let Some(i) = inspector {
        regions.insert("inspector".into(), i);
    }

    Ok(json!({
        "artifact": "view",
        "version": 0,
        "screen": screen,
        "layout": layout,
        "sources": Value::Object(sources),
        "actions": Value::Object(actions),
        "regions": Value::Object(regions),
    }))
}

/// Convenience: lower `.igv` directly to a JSON string (deterministic; feeds `from_artifact`).
pub fn lower_igv_to_string(src: &str) -> Result<String, IgvError> {
    Ok(lower_igv(src)?.to_string())
}
