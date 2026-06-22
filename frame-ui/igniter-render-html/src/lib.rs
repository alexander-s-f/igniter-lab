//! LAB-IGNITER-RENDER-HTML-P3 — pure ViewArtifact JSON → deterministic, escaped HTML.
//!
//! This is a **projector / render target**, not a language feature and not server authority. It is the
//! HTML analogue of the frame `RenderHost` impls (SVG/wireframe/GUI): a ViewArtifact tree projected to
//! a different surface. It is **standalone** — it depends only on `serde_json`, mirrors the canonical
//! ViewArtifact schema (`frame-ui/igniter-ui-kit/src/view_artifact.rs`), and touches **no**
//! `igniter-server` / `igniter-web` protocol. `RAW-RESPONSE` is NOT opened by this crate.
//!
//! Safety: the input is a **structured** ViewArtifact (a closed node vocabulary), never a template
//! string, so user data only ever lands in escaped leaf positions — there is no markup-injection
//! surface. All text and attribute values are HTML-escaped; URL values (when a URL-bearing node exists)
//! must route through [`safe_url`], which fails closed on non-`http(s)`/relative schemes. v0 supports
//! **no** raw-HTML node; unknown node shapes fail closed.

use serde_json::Value;
use std::fmt;

/// Non-panicking render error. Messages carry the offending node *kind/key*, never the raw artifact body.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum RenderHtmlError {
    /// Not valid JSON, not a `"view"` artifact, unknown/missing `layout`, or a missing required field.
    InvalidArtifact(String),
    /// A component/field `kind` outside the supported vocabulary (fail closed; no raw HTML).
    UnsupportedNode(String),
    /// A URL value whose scheme is not on the allowlist (relative / `http` / `https`).
    UnsafeUrl(String),
    /// Catch-all render failure.
    Render(String),
}

impl fmt::Display for RenderHtmlError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            RenderHtmlError::InvalidArtifact(m) => write!(f, "invalid view artifact: {m}"),
            RenderHtmlError::UnsupportedNode(m) => write!(f, "unsupported node: {m}"),
            RenderHtmlError::UnsafeUrl(m) => write!(f, "unsafe url: {m}"),
            RenderHtmlError::Render(m) => write!(f, "render error: {m}"),
        }
    }
}

impl std::error::Error for RenderHtmlError {}

/// Render a ViewArtifact JSON into a full, escaped HTML **document**.
pub fn render_html(artifact_json: &str) -> Result<String, RenderHtmlError> {
    let (body, title) = render_screen(artifact_json)?;
    Ok(document(&body, &title))
}

/// Render a ViewArtifact JSON into an escaped HTML **fragment** (the body markup only — no `<!DOCTYPE>`/
/// `<html>` wrapper). Useful for embedding into an existing shell.
pub fn render_html_fragment(artifact_json: &str) -> Result<String, RenderHtmlError> {
    Ok(render_screen(artifact_json)?.0)
}

/// HTML-escape a text/attribute value. `&` first; covers the five HTML-significant characters so the
/// result is safe in both element-text and double-quoted-attribute contexts.
pub fn escape(s: &str) -> String {
    let mut out = String::with_capacity(s.len() + 8);
    for c in s.chars() {
        match c {
            '&' => out.push_str("&amp;"),
            '<' => out.push_str("&lt;"),
            '>' => out.push_str("&gt;"),
            '"' => out.push_str("&quot;"),
            '\'' => out.push_str("&#x27;"),
            _ => out.push(c),
        }
    }
    out
}

/// Validate a URL value against the allowlist and return it escaped. Allowed: a relative reference (no
/// scheme), or an `http`/`https` URL. Any other explicit scheme (`javascript:`, `data:`, `mailto:`, …)
/// fails closed with [`RenderHtmlError::UnsafeUrl`]. Provided + tested for the first URL-bearing node;
/// the v0 ViewArtifact vocabulary has none yet, so no URL is emitted today.
pub fn safe_url(url: &str) -> Result<String, RenderHtmlError> {
    let t = url.trim();
    if let Some(colon) = t.find(':') {
        let before = &t[..colon];
        // a scheme is `alpha *( alpha | digit | + | - | . )` with no `/` before the `:`.
        let is_scheme = !before.is_empty()
            && !before.contains('/')
            && before
                .chars()
                .next()
                .is_some_and(|c| c.is_ascii_alphabetic())
            && before
                .chars()
                .all(|c| c.is_ascii_alphanumeric() || matches!(c, '+' | '-' | '.'));
        if is_scheme {
            let scheme = before.to_ascii_lowercase();
            if scheme != "http" && scheme != "https" {
                return Err(RenderHtmlError::UnsafeUrl(format!(
                    "disallowed URL scheme '{scheme}:'"
                )));
            }
        }
        // else: the ':' is not a scheme delimiter (e.g. a relative path "a:b/c") → treat as relative.
    }
    Ok(escape(t))
}

// ── internals ────────────────────────────────────────────────────────────────────────────────────

fn render_screen(artifact_json: &str) -> Result<(String, String), RenderHtmlError> {
    let v: Value = serde_json::from_str(artifact_json)
        // serde's message carries position, not the artifact body.
        .map_err(|e| RenderHtmlError::InvalidArtifact(format!("not valid JSON ({e})")))?;
    if v.get("artifact").and_then(|a| a.as_str()) != Some("view") {
        return Err(RenderHtmlError::InvalidArtifact(
            "\"artifact\" must be \"view\"".into(),
        ));
    }
    match v.get("layout").and_then(|l| l.as_str()) {
        Some("form") => render_form(&v),
        Some("workbench") => render_workbench(&v),
        other => Err(RenderHtmlError::InvalidArtifact(format!(
            "unknown layout: {other:?} (expected \"form\" or \"workbench\")"
        ))),
    }
}

fn document(body: &str, title: &str) -> String {
    format!(
        "<!DOCTYPE html>\n<html lang=\"en\">\n<head><meta charset=\"utf-8\"><title>{}</title></head>\n<body>{}</body>\n</html>\n",
        escape(title),
        body
    )
}

fn req<'a>(v: &'a Value, key: &str, ctx: &str) -> Result<&'a str, RenderHtmlError> {
    v.get(key).and_then(|x| x.as_str()).ok_or_else(|| {
        RenderHtmlError::InvalidArtifact(format!("{ctx}: missing string field '{key}'"))
    })
}

fn bool_field(v: &Value, key: &str) -> bool {
    v.get(key).and_then(|b| b.as_bool()).unwrap_or(false)
}

fn req_mark(required: bool) -> &'static str {
    if required {
        " *"
    } else {
        ""
    }
}

fn req_attr(required: bool) -> &'static str {
    if required {
        " required"
    } else {
        ""
    }
}

/// Render a `form`-layout artifact: `{ title?, body: [component...] }`.
fn render_form(v: &Value) -> Result<(String, String), RenderHtmlError> {
    let title = v
        .get("title")
        .and_then(|t| t.as_str())
        .unwrap_or("")
        .to_string();
    let body = v
        .get("body")
        .and_then(|b| b.as_array())
        .ok_or_else(|| RenderHtmlError::InvalidArtifact("form: \"body\" array required".into()))?;
    if body.is_empty() {
        return Err(RenderHtmlError::InvalidArtifact(
            "form: \"body\" must not be empty".into(),
        ));
    }
    let mut inner = String::from("<form class=\"ig-form\">");
    if !title.is_empty() {
        inner.push_str(&format!("<h1>{}</h1>", escape(&title)));
    }
    for c in body {
        inner.push_str(&render_component(c)?);
    }
    inner.push_str("</form>");
    let doc_title = if title.is_empty() {
        "Form".to_string()
    } else {
        title
    };
    Ok((inner, doc_title))
}

/// Render a `workbench`-layout artifact's parsed subset: `data.leads` + `regions.main.fields` (the same
/// subset the canonical `view_artifact::workbench_from_value` reads; richer region hints are ignored).
fn render_workbench(v: &Value) -> Result<(String, String), RenderHtmlError> {
    let leads = v
        .get("data")
        .and_then(|d| d.get("leads"))
        .and_then(|l| l.as_array())
        .ok_or_else(|| {
            RenderHtmlError::InvalidArtifact("workbench: \"data.leads\" array required".into())
        })?;
    let fields = v
        .get("regions")
        .and_then(|r| r.get("main"))
        .and_then(|m| m.get("fields"))
        .and_then(|f| f.as_array())
        .ok_or_else(|| {
            RenderHtmlError::InvalidArtifact(
                "workbench: \"regions.main.fields\" array required".into(),
            )
        })?;
    if fields.is_empty() {
        return Err(RenderHtmlError::InvalidArtifact(
            "workbench: at least one field required".into(),
        ));
    }
    let mut inner = String::from("<section class=\"ig-workbench\"><aside class=\"ig-leads\"><ul>");
    for l in leads {
        let s = l.as_str().ok_or_else(|| {
            RenderHtmlError::InvalidArtifact("workbench: lead is not a string".into())
        })?;
        inner.push_str(&format!("<li>{}</li>", escape(s)));
    }
    inner.push_str("</ul></aside><form class=\"ig-form\">");
    for f in fields {
        let kind = req(f, "kind", "field")?;
        inner.push_str(&render_input(f, kind, "field")?);
    }
    inner.push_str("</form></section>");
    let title = v
        .get("screen")
        .and_then(|s| s.as_str())
        .filter(|s| !s.is_empty())
        .unwrap_or("Workbench")
        .to_string();
    Ok((inner, title))
}

/// Render one form component `{ kind, ... }`.
fn render_component(cv: &Value) -> Result<String, RenderHtmlError> {
    let kind = req(cv, "kind", "component")?;
    match kind {
        "label" => Ok(format!(
            "<p class=\"ig-label\">{}</p>",
            escape(req(cv, "text", "label component")?)
        )),
        "button" => Ok(format!(
            "<button type=\"submit\" id=\"{}\" data-action=\"{}\">{}</button>",
            escape(req(cv, "id", "button component")?),
            escape(req(cv, "action", "button component")?),
            escape(req(cv, "label", "button component")?),
        )),
        "text" | "select" | "checkbox" => render_input(cv, kind, "component"),
        other => Err(RenderHtmlError::UnsupportedNode(format!(
            "unknown component kind '{other}'"
        ))),
    }
}

/// Render an input-bearing node (`text` / `select` / `checkbox`). Shared by form components and
/// workbench fields, which carry the same `{ id, label, required, (options) }` shape.
fn render_input(v: &Value, kind: &str, ctx: &str) -> Result<String, RenderHtmlError> {
    let id = req(v, "id", ctx)?;
    let label = req(v, "label", ctx)?;
    let required = bool_field(v, "required");
    match kind {
        "text" => Ok(format!(
            "<label class=\"ig-field\"><span>{}{}</span><input type=\"text\" name=\"{}\"{}></label>",
            escape(label),
            req_mark(required),
            escape(id),
            req_attr(required),
        )),
        "checkbox" => Ok(format!(
            "<label class=\"ig-field ig-checkbox\"><input type=\"checkbox\" name=\"{}\"><span>{}</span></label>",
            escape(id),
            escape(label),
        )),
        "select" => {
            let opts = v.get("options").and_then(|o| o.as_array()).ok_or_else(|| {
                RenderHtmlError::InvalidArtifact(format!("select '{id}': missing 'options' array"))
            })?;
            let mut options_html = String::new();
            for o in opts {
                let s = o.as_str().ok_or_else(|| {
                    RenderHtmlError::InvalidArtifact(format!("select '{id}': option is not a string"))
                })?;
                options_html.push_str(&format!(
                    "<option value=\"{}\">{}</option>",
                    escape(s),
                    escape(s)
                ));
            }
            Ok(format!(
                "<label class=\"ig-field\"><span>{}{}</span><select name=\"{}\"{}>{}</select></label>",
                escape(label),
                req_mark(required),
                escape(id),
                req_attr(required),
                options_html,
            ))
        }
        other => Err(RenderHtmlError::UnsupportedNode(format!(
            "unknown {ctx} kind '{other}' for '{id}'"
        ))),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn escape_covers_all_significant_chars() {
        assert_eq!(escape("a&b<c>d\"e'f"), "a&amp;b&lt;c&gt;d&quot;e&#x27;f");
    }

    #[test]
    fn safe_url_allows_relative_and_http_s() {
        assert_eq!(safe_url("/todos/1").unwrap(), "/todos/1");
        assert_eq!(
            safe_url("https://example.com/x").unwrap(),
            "https://example.com/x"
        );
        assert_eq!(safe_url("./a").unwrap(), "./a");
        assert_eq!(safe_url("a/b:c").unwrap(), "a/b:c"); // ':' after '/' is not a scheme
    }

    #[test]
    fn safe_url_rejects_dangerous_schemes() {
        assert!(matches!(
            safe_url("javascript:alert(1)"),
            Err(RenderHtmlError::UnsafeUrl(_))
        ));
        assert!(matches!(
            safe_url("data:text/html;base64,xxx"),
            Err(RenderHtmlError::UnsafeUrl(_))
        ));
        assert!(matches!(
            safe_url("mailto:x@y.z"),
            Err(RenderHtmlError::UnsafeUrl(_))
        ));
    }
}
