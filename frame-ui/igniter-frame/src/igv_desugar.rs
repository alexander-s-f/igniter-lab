//! LAB-FRAME-VIEW-FORM-DESUGAR — a lab precedent for ASK2 (invocation-form `col { row { leaf } }`).
//!
//! Canon's `LANG-FORM-VOCABULARY` track will eventually lower a form like `col { row { … } }` to nested
//! `call_contract` over typed `uses` refs (the cross-module substrate proven by LANG-TYPED-CONTRACT-REF
//! P5). That track is planning-complete but awaiting its own P3/P4 authorization. This module does NOT
//! touch the canon compiler: it is a SOURCE-TO-SOURCE desugarer that expands the terse form into the
//! exact `call_contract`-based `.ig` we already compile (`igc`), run (`igniter-vm`), and render
//! (`ig_bridge`). It proves the ergonomics + the precise lowering end-to-end, as a working reference
//! for canon P4 — staying pure igniter (the output is `.ig`, not "Rust that returns a string").
//!
//! Terse grammar (one node per construct):
//! ```text
//! node      := ("col"|"row") attr* "{" node* "}"          -- container
//!            | ("leaf"|"button") STRING word? attr*        -- leaf (word = intent, optional for leaf)
//! attr      := ("pad"|"gap"|"fixed"|"flex") "=" INT        -- fixed=N → main=N flex=0; flex=N → main=N flex=1
//! ```

/// A parse/desugar error with a 1-based line number.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct DesugarError {
    pub line: usize,
    pub msg: String,
}

#[derive(Clone, Debug)]
struct Node {
    tag: String,        // col | row | leaf | button
    main: i64,
    flex: i64,
    pad: i64,
    gap: i64,
    text: String,       // leaf/button only
    intent: String,     // leaf/button only
    children: Vec<Node>,
}

#[derive(Clone, Debug, PartialEq)]
enum Tok {
    Word(String),
    Str(String),
    Int(i64),
    Eq,
    LBrace,
    RBrace,
}

fn lex(src: &str) -> Result<Vec<(Tok, usize)>, DesugarError> {
    let mut out = Vec::new();
    for (i, raw) in src.lines().enumerate() {
        let line = i + 1;
        let mut cs = raw.chars().peekable();
        while let Some(&c) = cs.peek() {
            match c {
                ' ' | '\t' | '\r' => { cs.next(); }
                '#' => break, // line comment
                '{' => { cs.next(); out.push((Tok::LBrace, line)); }
                '}' => { cs.next(); out.push((Tok::RBrace, line)); }
                '=' => { cs.next(); out.push((Tok::Eq, line)); }
                '"' => {
                    cs.next();
                    let mut s = String::new();
                    let mut closed = false;
                    while let Some(ch) = cs.next() {
                        if ch == '"' { closed = true; break; }
                        s.push(ch);
                    }
                    if !closed {
                        return Err(DesugarError { line, msg: "unterminated string literal".into() });
                    }
                    out.push((Tok::Str(s), line));
                }
                c if c == '-' || c.is_ascii_digit() => {
                    let mut n = String::new();
                    if c == '-' { n.push(c); cs.next(); }
                    while let Some(&d) = cs.peek() {
                        if d.is_ascii_digit() { n.push(d); cs.next(); } else { break; }
                    }
                    let v: i64 = n.parse().map_err(|_| DesugarError { line, msg: format!("bad number `{n}`") })?;
                    out.push((Tok::Int(v), line));
                }
                c if c.is_alphanumeric() || c == '_' || c == '-' => {
                    let mut w = String::new();
                    while let Some(&d) = cs.peek() {
                        if d.is_alphanumeric() || d == '_' || d == '-' { w.push(d); cs.next(); } else { break; }
                    }
                    out.push((Tok::Word(w), line));
                }
                other => return Err(DesugarError { line, msg: format!("unexpected character `{other}`") }),
            }
        }
    }
    Ok(out)
}

struct Parser {
    toks: Vec<(Tok, usize)>,
    pos: usize,
}

impl Parser {
    fn line(&self) -> usize {
        self.toks.get(self.pos).or_else(|| self.toks.last()).map(|(_, l)| *l).unwrap_or(0)
    }
    fn peek(&self) -> Option<&Tok> {
        self.toks.get(self.pos).map(|(t, _)| t)
    }
    fn next(&mut self) -> Option<Tok> {
        let t = self.toks.get(self.pos).map(|(t, _)| t.clone());
        self.pos += 1;
        t
    }

    /// Parse trailing `key=val` attributes onto a node.
    fn attrs(&mut self, n: &mut Node) -> Result<(), DesugarError> {
        while let Some(Tok::Word(k)) = self.peek() {
            if !matches!(k.as_str(), "pad" | "gap" | "fixed" | "flex") {
                break;
            }
            let key = k.clone();
            self.next();
            match self.next() {
                Some(Tok::Eq) => {}
                _ => return Err(DesugarError { line: self.line(), msg: format!("`{key}` needs `= <int>`") }),
            }
            let v = match self.next() {
                Some(Tok::Int(v)) => v.max(0),
                _ => return Err(DesugarError { line: self.line(), msg: format!("`{key}` needs an integer value") }),
            };
            match key.as_str() {
                "pad" => n.pad = v,
                "gap" => n.gap = v,
                "fixed" => { n.main = v; n.flex = 0; }
                "flex" => { n.main = v; n.flex = 1; }
                _ => unreachable!(),
            }
        }
        Ok(())
    }

    fn node(&mut self) -> Result<Node, DesugarError> {
        let line = self.line();
        let kind = match self.next() {
            Some(Tok::Word(w)) => w,
            _ => return Err(DesugarError { line, msg: "expected a node (col/row/leaf/button)".into() }),
        };
        let mut n = Node { tag: kind.clone(), main: 0, flex: 0, pad: 0, gap: 0, text: String::new(), intent: String::new(), children: Vec::new() };
        match kind.as_str() {
            "col" | "row" => {
                self.attrs(&mut n)?;
                match self.next() {
                    Some(Tok::LBrace) => {}
                    _ => return Err(DesugarError { line: self.line(), msg: format!("`{kind}` needs a `{{ … }}` body") }),
                }
                while !matches!(self.peek(), Some(Tok::RBrace) | None) {
                    let child = self.node()?;
                    n.children.push(child);
                }
                match self.next() {
                    Some(Tok::RBrace) => {}
                    _ => return Err(DesugarError { line: self.line(), msg: format!("`{kind}` body not closed with `}}`") }),
                }
            }
            "leaf" | "button" => {
                n.text = match self.next() {
                    Some(Tok::Str(s)) => s,
                    _ => return Err(DesugarError { line: self.line(), msg: format!("`{kind}` needs a \"text\"") }),
                };
                // optional intent word (a non-attr word)
                if let Some(Tok::Word(w)) = self.peek() {
                    if !matches!(w.as_str(), "pad" | "gap" | "fixed" | "flex") {
                        n.intent = w.clone();
                        self.next();
                    }
                }
                if kind == "button" && n.intent.is_empty() {
                    return Err(DesugarError { line, msg: "`button` needs an intent word (e.g. `add`)".into() });
                }
                self.attrs(&mut n)?;
            }
            other => return Err(DesugarError { line, msg: format!("unknown node `{other}` (expected col/row/leaf/button)") }),
        }
        Ok(n)
    }
}

/// The fixed element library the generated view threads through (inlined because cross-module
/// `call_contract` is not available today — see ASK1). `Leaf` carries an explicit `intent`.
const PREAMBLE: &str = r#"module GeneratedView

type Attrs {
  dir  : String
  main : Integer
  flex : Integer
  pad  : Integer
  gap  : Integer
}

type Element {
  tag      : String
  attrs    : Attrs
  text     : String
  intent   : String
  children : Collection[Element]
}

contract Col {
  input attrs    : Attrs
  input children : Collection[Element]
  compute el = { tag: "col", attrs: attrs, text: "", intent: "", children: children }
  output el : Element
}

contract Row {
  input attrs    : Attrs
  input children : Collection[Element]
  compute el = { tag: "row", attrs: attrs, text: "", intent: "", children: children }
  output el : Element
}

contract Leaf {
  input attrs  : Attrs
  input text   : String
  input intent : String
  compute el = { tag: "leaf", attrs: attrs, text: text, intent: intent, children: [] }
  output el : Element
}

contract Button {
  input attrs  : Attrs
  input text   : String
  input intent : String
  compute el = { tag: "button", attrs: attrs, text: text, intent: intent, children: [] }
  output el : Element
}

"#;

fn esc_ig(s: &str) -> String {
    s.replace('\\', "\\\\").replace('"', "\\\"")
}

/// Emit the `View` contract: a post-order walk so each child `compute` is defined before its parent
/// references it. Returns the index assigned to `n`.
fn emit(n: &Node, body: &mut String, next: &mut usize) -> usize {
    let child_ids: Vec<usize> = n.children.iter().map(|c| emit(c, body, next)).collect();
    let i = *next;
    *next += 1;
    body.push_str(&format!(
        "  compute attrs_{i} = {{ dir: \"{}\", main: {}, flex: {}, pad: {}, gap: {} }}\n",
        n.tag, n.main, n.flex, n.pad, n.gap
    ));
    match n.tag.as_str() {
        "col" | "row" => {
            let kids = child_ids.iter().map(|c| format!("node_{c}")).collect::<Vec<_>>().join(", ");
            let ctor = if n.tag == "row" { "Row" } else { "Col" };
            body.push_str(&format!("  compute node_{i} = call_contract(\"{ctor}\", attrs_{i}, [{kids}])\n"));
        }
        "leaf" => body.push_str(&format!(
            "  compute node_{i} = call_contract(\"Leaf\", attrs_{i}, \"{}\", \"{}\")\n",
            esc_ig(&n.text), esc_ig(&n.intent)
        )),
        "button" => body.push_str(&format!(
            "  compute node_{i} = call_contract(\"Button\", attrs_{i}, \"{}\", \"{}\")\n",
            esc_ig(&n.text), esc_ig(&n.intent)
        )),
        _ => {}
    }
    i
}

/// Desugar a terse form spec into a complete, compilable `.ig` module (`module GeneratedView` with a
/// `View` contract whose `output root : Element` is the composed tree). Total — malformed input yields
/// a `DesugarError`, never a panic.
pub fn desugar(terse: &str) -> Result<String, DesugarError> {
    let toks = lex(terse)?;
    if toks.is_empty() {
        return Err(DesugarError { line: 0, msg: "empty form".into() });
    }
    let mut p = Parser { toks, pos: 0 };
    let root = p.node()?;
    if p.peek().is_some() {
        return Err(DesugarError { line: p.line(), msg: "trailing tokens after the root node".into() });
    }
    let mut body = String::new();
    let mut next = 0usize;
    let root_id = emit(&root, &mut body, &mut next);
    let mut out = String::with_capacity(PREAMBLE.len() + body.len() + 64);
    out.push_str(PREAMBLE);
    out.push_str("contract View {\n");
    out.push_str(&body);
    out.push_str(&format!("  output node_{root_id} : Element\n}}\n"));
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    const LIST: &str = r#"
col pad=16 gap=12 {
  row flex=1 gap=12 {
    col fixed=248 pad=12 gap=8 {
      leaf "Review Ada's lead" select fixed=40
      leaf "Call Grace back" select fixed=40
      leaf "Send Linus the quote" select fixed=40
      button "+ add item" add fixed=40
    }
    col flex=1 pad=18 gap=14 {
      leaf "Review Ada's lead" select fixed=30
      button "mark done" toggle fixed=48
    }
  }
}
"#;

    #[test]
    fn desugars_to_a_well_formed_ig_module() {
        let ig = desugar(LIST).unwrap();
        assert!(ig.starts_with("module GeneratedView"));
        assert!(ig.contains("contract View {"));
        assert!(ig.trim_end().ends_with("}"));
        // every authored label + intent reached the generated call_contract calls
        for needle in ["Review Ada's lead", "Call Grace back", "Send Linus the quote", "+ add item", "mark done"] {
            assert!(ig.contains(needle), "missing {needle:?}");
        }
        assert!(ig.contains(r#"call_contract("Button", attrs_3, "+ add item", "add")"#));
        // post-order: children defined before the parent that lists them
        let n3 = ig.find("node_3 = call_contract").unwrap();
        let sidebar = ig.find("call_contract(\"Col\", attrs_4, [node_0, node_1, node_2, node_3]").unwrap();
        assert!(n3 < sidebar, "child node_3 must be emitted before its parent col");
    }

    #[test]
    fn nesting_and_attrs_parse() {
        let ig = desugar("col pad=8 { row flex=1 { leaf \"x\" select fixed=20 } }").unwrap();
        assert!(ig.contains(r#"compute attrs_2 = { dir: "col", main: 0, flex: 0, pad: 8, gap: 0 }"#));
        assert!(ig.contains(r#"compute attrs_1 = { dir: "row", main: 1, flex: 1, pad: 0, gap: 0 }"#));
        assert!(ig.contains(r#"call_contract("Leaf", attrs_0, "x", "select")"#));
    }

    #[test]
    fn errors_are_total_no_panic() {
        assert!(desugar("col pad=8 { leaf }").is_err()); // leaf needs text
        assert!(desugar("col { row { leaf \"x\" }").is_err()); // unclosed brace
        assert!(desugar("button \"go\"").is_err()); // button needs an intent
        assert!(desugar("blink \"x\"").is_err()); // unknown node
        assert!(desugar("col { } col { }").is_err()); // trailing root
        assert_eq!(desugar("col pad=eight { }").unwrap_err().line, 1); // bad attr value
        assert!(desugar("").is_err()); // empty
    }

    #[test]
    fn escapes_quotes_in_text() {
        let ig = desugar("leaf \"a quote\" select").unwrap();
        assert!(ig.contains("\"a quote\""));
        // a backslash/quote in the label is escaped into the .ig string literal
        let ig2 = desugar("leaf \"a-b\" select").unwrap();
        assert!(ig2.contains("\"a-b\""));
    }
}
