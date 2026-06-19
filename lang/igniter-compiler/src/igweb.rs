// LAB-IGNITER-WEB-ROUTING-LOWERING-P4
//
// `.igweb` — a tiny LAB-ONLY route-authoring sugar that lowers DETERMINISTICALLY to an explicit
// `.ig` `Serve(Request) -> Decision` contract. This is sugar, NOT canon `.ig` syntax and NOT a server
// route table: the generated `.ig` is the inspectable truth, compiles through the existing project
// mode, and dispatches via STATIC `call_contract("Name", ...)` arms (no dynamic dispatch). Path
// params lower to `stdlib.regexp.matches` / `capture` (P3). Mirrors the proven `.igv` → ViewArtifact
// lowering pattern (igniter-ui-kit/src/igv.rs), but emits `.ig` source text rather than JSON.
//
// P10: the generated module is `AppRoutes`; it imports the shared `IgWebPrelude` (Request + Decision,
// provided by the builder — apps no longer author `web_types.ig`) and the app's handler module, named
// by the required `handlers <Module>` directive (no hardcoded `TodoHandlers`).

/// The shared web prelude module name the lowering imports. The builder injects `PRELUDE_SOURCE` for it.
pub const PRELUDE_MODULE: &str = "IgWebPrelude";

/// The shared `Request`/`Decision` support source. Inspectable; injected once per build by the IgWeb
/// builder so every app gets the same logical surface without authoring `web_types.ig`.
pub const PRELUDE_SOURCE: &str = "\
module IgWebPrelude

type Request {
  method          : String
  path            : String
  body            : String
  correlation_id  : String
  idempotency_key : String
}

variant Decision {
  Respond      { status : Integer, body : String }
  InvokeEffect { target : String, input : String, idempotency_key : String }
}
";

/// Stable, line-positioned lowering diagnostic.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct IgwebError {
    pub line: usize,
    pub message: String,
}

struct Route {
    method: String,
    pattern: String,
    contract: String,
    requires_idem: bool,
    /// capture-group param names in path order (empty for exact routes).
    params: Vec<String>,
    /// anchored regex for the path; `:name` segments become `([^/]+)`.
    regex: String,
}

/// Compose a `scope` prefix with a child path (prefix or route pattern), joining with exactly one `/`
/// and dropping any trailing slash so the composed pattern is canonical (two spellings that mean the
/// same path produce the same `pattern` string, which keeps first-seen pattern grouping / 405 intact).
/// Both inputs start with `/`. `compose_path("/todos", "/")` → `/todos`; `compose_path("/", "/x")` → `/x`.
fn compose_path(prefix: &str, suffix: &str) -> String {
    let joined = format!(
        "{}/{}",
        prefix.trim_end_matches('/'),
        suffix.trim_start_matches('/')
    );
    let trimmed = joined.trim_end_matches('/');
    if trimmed.is_empty() {
        "/".to_string()
    } else {
        trimmed.to_string()
    }
}

/// First param name that repeats, in path order (`["a","b","a"]` → `Some("a")`). Positional capture
/// means a duplicate name is silent ambiguity for the reader, so the lowering refuses it.
fn first_duplicate(names: &[String]) -> Option<String> {
    let mut seen: Vec<&String> = Vec::new();
    for n in names {
        if seen.iter().any(|s| *s == n) {
            return Some(n.clone());
        }
        seen.push(n);
    }
    None
}

/// Convert a route pattern (`/todos/:id/done`) into an anchored regex (`^/todos/([^/]+)/done$`) plus
/// the ordered param names. v0 assumes literal segments are regex-safe (alphanumeric / `-` / `_`).
fn pattern_to_regex(pattern: &str) -> (String, Vec<String>) {
    let mut params = Vec::new();
    let mut segs: Vec<String> = Vec::new();
    for seg in pattern.split('/').filter(|s| !s.is_empty()) {
        if let Some(name) = seg.strip_prefix(':') {
            params.push(name.to_string());
            segs.push("([^/]+)".to_string());
        } else {
            segs.push(seg.to_string());
        }
    }
    let regex = format!("^/{}$", segs.join("/"));
    (regex, params)
}

/// Lower `.igweb` source into an explicit `AppRoutes` `.ig` module. Deterministic: routes keep source
/// order, patterns are grouped in first-seen order, and there is no map iteration in the output.
pub fn lower_igweb(src: &str) -> Result<String, IgwebError> {
    let mut entry: Option<String> = None;
    let mut handlers: Option<String> = None;
    let mut routes: Vec<Route> = Vec::new();
    let mut in_app = false;
    let mut closed = false;
    // Stack of absolute (already-composed) scope prefixes; the innermost is `last()`. Empty = top level.
    let mut scope_stack: Vec<String> = Vec::new();
    // When inside a `resource { ... }` block: the resource's absolute base path (scope + base composed)
    // plus the header line for line-positioned unclosed-block diagnostics.
    let mut in_resource: Option<(String, usize)> = None;

    for (i, raw) in src.lines().enumerate() {
        let line = i + 1;
        let t = raw.trim();
        if t.is_empty() || t.starts_with("--") || t.starts_with('#') {
            continue;
        }
        if let Some(rest) = t.strip_prefix("app ") {
            // app <Name> entry <Serve> {
            let rest = rest.trim_end_matches('{').trim();
            let parts: Vec<&str> = rest.split_whitespace().collect();
            if parts.len() != 3 || parts[1] != "entry" {
                return Err(IgwebError {
                    line,
                    message: "expected `app <Name> entry <ServeContract> {`".into(),
                });
            }
            entry = Some(parts[2].to_string());
            in_app = true;
            continue;
        }
        if t == "}" {
            // `}` closes the innermost open block: a resource, else a scope, else the app.
            if in_resource.is_some() {
                in_resource = None;
                continue;
            }
            if scope_stack.pop().is_some() {
                continue;
            }
            if in_app {
                in_app = false;
                closed = true;
                continue;
            }
            return Err(IgwebError {
                line,
                message: "unexpected `}` (no open `app`, `scope`, or `resource` block)".into(),
            });
        }
        // Inside a resource body, every non-`}` line is an action line (validated by the closed table).
        if let Some((base, _resource_line)) = &in_resource {
            let r = parse_resource_action(t, line, base)?;
            routes.push(r);
            continue;
        }
        if let Some(rest) = t.strip_prefix("scope ") {
            if !in_app {
                return Err(IgwebError {
                    line,
                    message: "`scope` outside an `app { ... }` block".into(),
                });
            }
            let raw_prefix = parse_scope_prefix(rest, line)?;
            let base = scope_stack.last().map(String::as_str).unwrap_or("");
            let composed = if base.is_empty() {
                raw_prefix
            } else {
                compose_path(base, &raw_prefix)
            };
            scope_stack.push(composed);
            continue;
        }
        if let Some(rest) = t.strip_prefix("resource ") {
            if !in_app {
                return Err(IgwebError {
                    line,
                    message: "`resource` outside an `app { ... }` block".into(),
                });
            }
            let scope_base = scope_stack.last().map(String::as_str).unwrap_or("");
            in_resource = Some((parse_resource_header(rest, line, scope_base)?, line));
            continue;
        }
        if let Some(rest) = t.strip_prefix("handlers ") {
            if !in_app {
                return Err(IgwebError {
                    line,
                    message: "`handlers` outside an `app { ... }` block".into(),
                });
            }
            let name = rest.trim();
            if name.is_empty() || name.split_whitespace().count() != 1 {
                return Err(IgwebError {
                    line,
                    message: "expected `handlers <ModuleName>`".into(),
                });
            }
            if handlers.is_some() {
                return Err(IgwebError {
                    line,
                    message: "duplicate `handlers` directive".into(),
                });
            }
            handlers = Some(name.to_string());
            continue;
        }
        if let Some(rest) = t.strip_prefix("route ") {
            if !in_app {
                return Err(IgwebError {
                    line,
                    message: "`route` outside an `app { ... }` block".into(),
                });
            }
            let prefix = scope_stack.last().map(String::as_str).unwrap_or("");
            let r = parse_route(rest, line, prefix)?;
            routes.push(r);
            continue;
        }
        return Err(IgwebError {
            line,
            message: format!("unrecognized line: `{}`", t),
        });
    }

    let entry = entry.ok_or(IgwebError {
        line: 0,
        message: "missing `app <Name> entry <Serve> { ... }` header".into(),
    })?;
    let handlers = handlers.ok_or(IgwebError {
        line: 0,
        message: "missing `handlers <ModuleName>` directive".into(),
    })?;
    if let Some((_base, resource_line)) = in_resource {
        return Err(IgwebError {
            line: resource_line,
            message: "unclosed `resource { ... }` block (missing `}`)".into(),
        });
    }
    if !scope_stack.is_empty() {
        return Err(IgwebError {
            line: 0,
            message: "unclosed `scope { ... }` block (missing `}`)".into(),
        });
    }
    if !closed {
        return Err(IgwebError {
            line: 0,
            message: "unclosed `app { ... }` block (missing `}`)".into(),
        });
    }
    if routes.is_empty() {
        return Err(IgwebError {
            line: 0,
            message: "no routes declared".into(),
        });
    }

    Ok(generate_ig(&entry, &handlers, &routes))
}

/// Parse `scope "<prefix>" {` (the part after `scope `) into the raw prefix string. The prefix must be
/// a quoted path starting with `/`; the line must end with the opening `{`.
fn parse_scope_prefix(rest: &str, line: usize) -> Result<String, IgwebError> {
    let rest = rest.trim_start();
    if !rest.starts_with('"') {
        return Err(IgwebError {
            line,
            message: "expected a quoted \"<prefix>\" after `scope`".into(),
        });
    }
    let after_open = &rest[1..];
    let close = after_open.find('"').ok_or(IgwebError {
        line,
        message: "unterminated scope prefix string".into(),
    })?;
    let prefix = after_open[..close].to_string();
    let tail = after_open[close + 1..].trim();
    if tail != "{" {
        return Err(IgwebError {
            line,
            message: "expected `{` after the scope prefix".into(),
        });
    }
    if prefix.is_empty() || !prefix.starts_with('/') {
        return Err(IgwebError {
            line,
            message: "scope prefix must start with `/`".into(),
        });
    }
    Ok(prefix)
}

/// Parse `resource <name> "<base>" {` (the part after `resource `) into the resource's absolute base
/// path (the `scope` prefix, if any, composed with the resource base). `<name>` is author-facing only —
/// it is never used to derive a contract name.
fn parse_resource_header(rest: &str, line: usize, scope_base: &str) -> Result<String, IgwebError> {
    let rest = rest.trim();
    let (name, rest) = rest.split_once(char::is_whitespace).ok_or(IgwebError {
        line,
        message: "expected `resource <name> \"<base>\" {`".into(),
    })?;
    if name.is_empty() {
        return Err(IgwebError {
            line,
            message: "expected a resource name before the base path".into(),
        });
    }
    let rest = rest.trim_start();
    if !rest.starts_with('"') {
        return Err(IgwebError {
            line,
            message: "expected a quoted \"<base>\" after the resource name".into(),
        });
    }
    let after_open = &rest[1..];
    let close = after_open.find('"').ok_or(IgwebError {
        line,
        message: "unterminated resource base string".into(),
    })?;
    let base = &after_open[..close];
    let tail = after_open[close + 1..].trim();
    if tail != "{" {
        return Err(IgwebError {
            line,
            message: "expected `{` after the resource base".into(),
        });
    }
    if base.is_empty() || !base.starts_with('/') {
        return Err(IgwebError {
            line,
            message: "resource base must start with `/`".into(),
        });
    }
    Ok(if scope_base.is_empty() {
        base.to_string()
    } else {
        compose_path(scope_base, base)
    })
}

/// The closed resource action table — a **validator, not a generator**. Given an action keyword and the
/// authored method + optional suffix, validate the method against the action and return the effective
/// path suffix to compose onto the resource base. It NEVER derives a contract name or method.
fn resource_action_suffix(
    action: &str,
    method: &str,
    suffix: Option<&str>,
    line: usize,
) -> Result<String, IgwebError> {
    let bad_method = |allowed: &str| IgwebError {
        line,
        message: format!("resource action `{action}` must use {allowed}, got `{method}`"),
    };
    let reject_suffix = |s: Option<&str>| -> Result<(), IgwebError> {
        if s.is_some() {
            Err(IgwebError {
                line,
                message: format!("resource action `{action}` takes no path suffix"),
            })
        } else {
            Ok(())
        }
    };
    match action {
        "index" => {
            if method != "GET" {
                return Err(bad_method("GET"));
            }
            reject_suffix(suffix)?;
            Ok("/".into())
        }
        "create" => {
            if method != "POST" {
                return Err(bad_method("POST"));
            }
            reject_suffix(suffix)?;
            Ok("/".into())
        }
        "show" => {
            if method != "GET" {
                return Err(bad_method("GET"));
            }
            Ok(suffix.unwrap_or("/:id").to_string())
        }
        "update" => {
            if method != "PATCH" && method != "PUT" {
                return Err(bad_method("PATCH or PUT"));
            }
            Ok(suffix.unwrap_or("/:id").to_string())
        }
        "delete" => {
            if method != "DELETE" {
                return Err(bad_method("DELETE"));
            }
            Ok(suffix.unwrap_or("/:id").to_string())
        }
        "member" | "collection" => suffix.map(str::to_string).ok_or(IgwebError {
            line,
            message: format!("resource action `{action}` requires an explicit quoted suffix"),
        }),
        other => Err(IgwebError {
            line,
            message: format!(
                "unknown resource action `{other}` (expected index/create/show/update/delete/member/collection)"
            ),
        }),
    }
}

/// Parse one resource action line `<action> <METHOD> ["<suffix>"] -> <Contract> [requires idempotency]`
/// against the closed table, then reuse the route grammar/lowering by synthesizing the equivalent flat
/// `route` tail on the resource `base` (so composition, duplicate-param refusal, and the idempotency
/// guard all come from the existing path — resource sugar adds no new lowering).
fn parse_resource_action(t: &str, line: usize, base: &str) -> Result<Route, IgwebError> {
    let (action, rest) = t.split_once(char::is_whitespace).ok_or(IgwebError {
        line,
        message: "expected `<action> <METHOD> [\"<suffix>\"] -> <Contract>`".into(),
    })?;
    // Split on `->` first so a missing contract is reported clearly even when no suffix is present.
    let (head, contract_part) = rest.split_once("->").ok_or(IgwebError {
        line,
        message: "missing `->` before the handler contract".into(),
    })?;
    let head = head.trim();
    let (method, rest_head) = match head.split_once(char::is_whitespace) {
        Some((m, r)) => (m, r.trim()),
        None => (head, ""),
    };
    let suffix = if rest_head.is_empty() {
        None
    } else if rest_head.starts_with('"') {
        let inner = &rest_head[1..];
        let close = inner.find('"').ok_or(IgwebError {
            line,
            message: "unterminated resource suffix string".into(),
        })?;
        if !inner[close + 1..].trim().is_empty() {
            return Err(IgwebError {
                line,
                message: "unexpected tokens after the resource suffix".into(),
            });
        }
        Some(&inner[..close])
    } else {
        return Err(IgwebError {
            line,
            message: "expected a quoted \"<suffix>\" or `->` after the method".into(),
        });
    };
    let effective = resource_action_suffix(action, method, suffix, line)?;
    let route_tail = format!("{} \"{}\" -> {}", method, effective, contract_part.trim());
    parse_route(&route_tail, line, base)
}

/// Parse `<METHOD> "<pattern>" -> <Contract> [requires idempotency]` (the part after `route `).
/// `prefix` is the enclosing scope's absolute path (empty at top level); the route pattern is composed
/// onto it before regex/param generation, so the lowered route is identical to the hand-written flat one.
fn parse_route(rest: &str, line: usize, prefix: &str) -> Result<Route, IgwebError> {
    // METHOD
    let rest = rest.trim();
    let (method, rest) = rest.split_once(char::is_whitespace).ok_or(IgwebError {
        line,
        message: "expected `route <METHOD> \"<pattern>\" -> <Contract>`".into(),
    })?;
    let method = method.trim().to_string();
    // "pattern"
    let rest = rest.trim_start();
    if !rest.starts_with('"') {
        return Err(IgwebError {
            line,
            message: "expected a quoted \"<pattern>\" after the method".into(),
        });
    }
    let after_open = &rest[1..];
    let close = after_open.find('"').ok_or(IgwebError {
        line,
        message: "unterminated route pattern string".into(),
    })?;
    let pattern = after_open[..close].to_string();
    let rest = after_open[close + 1..].trim_start();
    // ->
    let rest = rest
        .strip_prefix("->")
        .ok_or(IgwebError {
            line,
            message: "expected `->` before the handler contract".into(),
        })?
        .trim_start();
    // Contract [requires idempotency]
    let mut parts = rest.split_whitespace();
    let contract = parts
        .next()
        .ok_or(IgwebError {
            line,
            message: "missing handler contract name after `->`".into(),
        })?
        .to_string();
    let tail: Vec<&str> = parts.collect();
    let requires_idem = match tail.as_slice() {
        [] => false,
        ["requires", "idempotency"] => true,
        _ => {
            return Err(IgwebError {
                line,
                message: format!(
                    "unexpected trailing tokens: `{}` (only `requires idempotency` allowed)",
                    tail.join(" ")
                ),
            })
        }
    };
    if pattern.is_empty() || !pattern.starts_with('/') {
        return Err(IgwebError {
            line,
            message: "route pattern must start with `/`".into(),
        });
    }
    // Compose the enclosing scope prefix (if any) onto the route's own pattern, then lower as flat.
    let pattern = if prefix.is_empty() {
        pattern
    } else {
        compose_path(prefix, &pattern)
    };
    let (regex, params) = pattern_to_regex(&pattern);
    // Duplicate param names in the composed pattern are ambiguity, not data (P16). This also
    // retroactively refuses a flat `/a/:id/b/:id`.
    if let Some(dup) = first_duplicate(&params) {
        return Err(IgwebError {
            line,
            message: format!(
                "duplicate path param `:{}` in composed pattern `{}`",
                dup, pattern
            ),
        });
    }
    Ok(Route {
        method,
        pattern,
        contract,
        requires_idem,
        params,
        regex,
    })
}

/// Distinct patterns in first-seen order.
fn patterns_in_order(routes: &[Route]) -> Vec<String> {
    let mut seen = Vec::new();
    for r in routes {
        if !seen.iter().any(|p: &String| p == &r.pattern) {
            seen.push(r.pattern.clone());
        }
    }
    seen
}

fn generate_ig(entry: &str, handlers_module: &str, routes: &[Route]) -> String {
    let mut out = String::new();
    out.push_str("-- GENERATED by lower_igweb (LAB-IGNITER-WEB-ROUTING-LOWERING-P4/P10). Do not edit by hand.\n");
    out.push_str("-- Routing/product meaning lives here (the app), never in igniter-server.\n");
    out.push_str("module AppRoutes\n");
    out.push_str(&format!("import {}\n", PRELUDE_MODULE));
    out.push_str(&format!("import {}\n\n", handlers_module));
    out.push_str(&format!("pure contract {} {{\n", entry));
    out.push_str("  input req : Request\n");
    out.push_str("  compute decision : Decision =\n");
    out.push_str(&route_chain(routes, &patterns_in_order(routes), 4));
    out.push_str("\n  output decision : Decision\n");
    out.push_str("}\n");
    out
}

fn pad(n: usize) -> String {
    " ".repeat(n)
}

/// Chain of `if matches(path, "<re>") { <methods> } else { <next> }`, terminating in `Respond 404`.
fn route_chain(routes: &[Route], patterns: &[String], indent: usize) -> String {
    if patterns.is_empty() {
        return format!(
            "{}Respond {{ status: 404, body: \"not found\" }}",
            pad(indent)
        );
    }
    let pat = &patterns[0];
    // routes for this pattern keep source order.
    let group: Vec<&Route> = routes.iter().filter(|r| &r.pattern == pat).collect();
    let regex = &group[0].regex;
    let mut s = String::new();
    s.push_str(&format!(
        "{}if matches(req.path, \"{}\") {{\n",
        pad(indent),
        regex
    ));
    s.push_str(&method_chain(&group, indent + 2));
    s.push('\n');
    s.push_str(&format!("{}}} else {{\n", pad(indent)));
    s.push_str(&route_chain(routes, &patterns[1..], indent + 2));
    s.push('\n');
    s.push_str(&format!("{}}}", pad(indent)));
    s
}

/// Chain of `if req.method == "M" { <arm> } else { <next> }`, terminating in `Respond 405`.
fn method_chain(group: &[&Route], indent: usize) -> String {
    if group.is_empty() {
        return format!(
            "{}Respond {{ status: 405, body: \"method not allowed\" }}",
            pad(indent)
        );
    }
    let r = group[0];
    let mut s = String::new();
    s.push_str(&format!(
        "{}if req.method == \"{}\" {{\n",
        pad(indent),
        r.method
    ));
    s.push_str(&format!("{}{}\n", pad(indent + 2), handler_arm(r)));
    s.push_str(&format!("{}}} else {{\n", pad(indent)));
    s.push_str(&method_chain(&group[1..], indent + 2));
    s.push('\n');
    s.push_str(&format!("{}}}", pad(indent)));
    s
}

/// A single route's body: an idempotency 400-guard (if `requires idempotency`) wrapping a static
/// `call_contract` with regexp-captured params (as `Option[String]`).
fn handler_arm(r: &Route) -> String {
    let mut call = format!("call_contract(\"{}\", req", r.contract);
    for (idx, _name) in r.params.iter().enumerate() {
        call.push_str(&format!(
            ", capture(req.path, \"{}\", {})",
            r.regex,
            idx + 1
        ));
    }
    call.push(')');
    if r.requires_idem {
        format!(
            "if req.idempotency_key == \"\" {{ Respond {{ status: 400, body: \"missing idempotency-key\" }} }} else {{ {} }}",
            call
        )
    } else {
        call
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const TODO: &str = "app TodoWeb entry Serve {\n  handlers TodoHandlers\n  route GET  \"/health\"         -> Health\n  route GET  \"/todos\"          -> TodoIndex\n  route POST \"/todos\"          -> TodoCreate requires idempotency\n  route GET  \"/todos/:id\"      -> TodoShow\n  route POST \"/todos/:id/done\" -> TodoDone requires idempotency\n}\n";

    #[test]
    fn lowers_deterministically() {
        let a = lower_igweb(TODO).unwrap();
        let b = lower_igweb(TODO).unwrap();
        assert_eq!(a, b, "byte-stable");
        assert!(a.contains("pure contract Serve"));
        // P10: prelude + app-named handler module, no hardcoded WebTypes/TodoHandlers import.
        assert!(a.contains("import IgWebPrelude"));
        assert!(a.contains("import TodoHandlers"));
        assert!(!a.contains("import WebTypes"));
        assert!(a.contains(
            "call_contract(\"TodoShow\", req, capture(req.path, \"^/todos/([^/]+)$\", 1))"
        ));
        assert!(a.contains("call_contract(\"TodoIndex\", req)"));
        assert!(a.contains("matches(req.path, \"^/todos/([^/]+)/done$\")"));
        assert!(a.contains("status: 404"));
        assert!(a.contains("status: 405"));
        assert!(a.contains("status: 400")); // keyless guard
                                            // no dynamic dispatch: every call_contract is on a string literal.
        assert!(!a.contains("call_contract(req"));
    }

    #[test]
    fn missing_handlers_directive_is_rejected() {
        let no_handlers = "app X entry Serve {\n  route GET \"/health\" -> Health\n}\n";
        let err = lower_igweb(no_handlers).unwrap_err();
        assert!(err.message.contains("handlers"), "got {err:?}");
    }

    #[test]
    fn malformed_route_is_line_positioned() {
        let bad = "app X entry Serve {\n  route GET /todos -> A\n}\n"; // missing quotes
        let err = lower_igweb(bad).unwrap_err();
        assert_eq!(err.line, 2);
    }

    #[test]
    fn bad_requires_clause_rejected() {
        let bad = "app X entry Serve {\n  route POST \"/x\" -> A requires auth\n}\n";
        assert_eq!(lower_igweb(bad).unwrap_err().line, 2);
    }

    #[test]
    fn nested_middle_param_lowers() {
        let src = "app X entry Serve {\n  handlers H\n  route GET \"/accounts/:account_id/todos/:id\" -> Nested\n}\n";
        let ig = lower_igweb(src).unwrap();
        assert!(ig.contains("matches(req.path, \"^/accounts/([^/]+)/todos/([^/]+)$\")"));
        assert!(ig.contains("capture(req.path, \"^/accounts/([^/]+)/todos/([^/]+)$\", 1)"));
        assert!(ig.contains("capture(req.path, \"^/accounts/([^/]+)/todos/([^/]+)$\", 2)"));
    }

    // ---- P16: scope prefix lowering ----

    /// Test 1 — a scoped route lowers byte-identically to the equivalent hand-written flat route.
    #[test]
    fn scope_prefix_is_byte_identical_to_flat() {
        let scoped = "app X entry Serve {\n  handlers H\n  scope \"/accounts/:account_id\" {\n    route GET \"/todos\" -> AccountTodosIndex\n  }\n}\n";
        let flat = "app X entry Serve {\n  handlers H\n  route GET \"/accounts/:account_id/todos\" -> AccountTodosIndex\n}\n";
        assert_eq!(lower_igweb(scoped).unwrap(), lower_igweb(flat).unwrap());
    }

    /// Test 2 — composed regex + captures are in path order (prefix param first, route param second).
    #[test]
    fn scope_positional_param_merge() {
        let src = "app X entry Serve {\n  handlers H\n  scope \"/accounts/:account_id\" {\n    route GET \"/todos/:todo_id\" -> AccountTodoShow\n  }\n}\n";
        let ig = lower_igweb(src).unwrap();
        assert!(ig.contains("matches(req.path, \"^/accounts/([^/]+)/todos/([^/]+)$\")"));
        assert!(ig.contains("call_contract(\"AccountTodoShow\", req, capture(req.path, \"^/accounts/([^/]+)/todos/([^/]+)$\", 1), capture(req.path, \"^/accounts/([^/]+)/todos/([^/]+)$\", 2))"));
    }

    /// Test 3 — nested `scope` composes prefixes outer→inner.
    #[test]
    fn nested_scope_composes_prefixes() {
        let src = "app X entry Serve {\n  handlers H\n  scope \"/a/:x\" {\n    scope \"/b/:y\" {\n      route GET \"/c\" -> Deep\n    }\n  }\n}\n";
        let ig = lower_igweb(src).unwrap();
        assert!(ig.contains("matches(req.path, \"^/a/([^/]+)/b/([^/]+)/c$\")"));
        assert!(ig.contains("call_contract(\"Deep\", req, capture(req.path, \"^/a/([^/]+)/b/([^/]+)/c$\", 1), capture(req.path, \"^/a/([^/]+)/b/([^/]+)/c$\", 2))"));
    }

    /// Test 4 — duplicate param name across scope+route is refused, line-positioned.
    #[test]
    fn scope_duplicate_param_is_refused() {
        let src = "app X entry Serve {\n  handlers H\n  scope \"/x/:id\" {\n    route GET \"/y/:id\" -> Dup\n  }\n}\n";
        let err = lower_igweb(src).unwrap_err();
        assert!(err.message.contains("duplicate"), "got {err:?}");
        assert_eq!(err.line, 4); // the route line carries the composed-pattern ambiguity
    }

    /// Test 4b — the same refusal retroactively covers a flat duplicate (no scope).
    #[test]
    fn flat_duplicate_param_is_refused() {
        let src = "app X entry Serve {\n  handlers H\n  route GET \"/a/:id/b/:id\" -> Dup\n}\n";
        let err = lower_igweb(src).unwrap_err();
        assert!(err.message.contains("duplicate"), "got {err:?}");
        assert_eq!(err.line, 3);
    }

    /// Test 5 — interleaved plain/scope/plain routes preserve authored arm order.
    #[test]
    fn scope_preserves_source_order() {
        let src = "app X entry Serve {\n  handlers H\n  route GET \"/a\" -> A\n  scope \"/s\" {\n    route GET \"/b\" -> B\n  }\n  route GET \"/c\" -> C\n}\n";
        let ig = lower_igweb(src).unwrap();
        let ia = ig.find("^/a$").expect("a");
        let ib = ig.find("^/s/b$").expect("s/b");
        let ic = ig.find("^/c$").expect("c");
        assert!(ia < ib && ib < ic, "arm order must follow source order");
    }

    /// Test 6 — a scoped GET-only path still yields method-mismatch 405 and unmatched-path 404.
    #[test]
    fn scope_preserves_404_405() {
        let src = "app X entry Serve {\n  handlers H\n  scope \"/s\" {\n    route GET \"/todos\" -> Idx\n  }\n}\n";
        let ig = lower_igweb(src).unwrap();
        assert!(ig.contains("matches(req.path, \"^/s/todos$\")"));
        assert!(ig.contains("if req.method == \"GET\""));
        assert!(ig.contains("status: 405")); // method mismatch inside the matched pattern
        assert!(ig.contains("status: 404")); // trailing no-pattern-matched arm
    }

    /// Test 7 — a scoped mutating route still emits the keyless idempotency 400 guard.
    #[test]
    fn scope_preserves_idempotency_guard() {
        let src = "app X entry Serve {\n  handlers H\n  scope \"/s\" {\n    route POST \"/x\" -> Do requires idempotency\n  }\n}\n";
        let ig = lower_igweb(src).unwrap();
        assert!(ig.contains("matches(req.path, \"^/s/x$\")"));
        assert!(ig.contains("status: 400")); // keyless guard before the call
        assert!(ig.contains("if req.idempotency_key == \"\""));
    }

    /// Test 10 — same `.igweb` lowers to byte-identical `.ig` across two calls (with scopes).
    #[test]
    fn scope_lowering_is_deterministic() {
        let src = "app X entry Serve {\n  handlers H\n  scope \"/a/:x\" {\n    route GET \"/todos\" -> Idx\n    route POST \"/todos\" -> Make requires idempotency\n  }\n}\n";
        assert_eq!(lower_igweb(src).unwrap(), lower_igweb(src).unwrap());
    }

    /// Malformed scope line (no quotes) is line-positioned.
    #[test]
    fn malformed_scope_line_is_line_positioned() {
        let src =
            "app X entry Serve {\n  handlers H\n  scope /s {\n    route GET \"/x\" -> A\n  }\n}\n";
        let err = lower_igweb(src).unwrap_err();
        assert_eq!(err.line, 3);
    }

    /// Unclosed scope is reported (missing `}`).
    #[test]
    fn unclosed_scope_is_reported() {
        let src =
            "app X entry Serve {\n  handlers H\n  scope \"/s\" {\n    route GET \"/x\" -> A\n";
        let err = lower_igweb(src).unwrap_err();
        assert!(err.message.contains("unclosed"), "got {err:?}");
    }

    // ---- P17: resource sugar ----

    const RESOURCE_TODO: &str = "app X entry Serve {\n  handlers H\n  resource todos \"/todos\" {\n    index  GET            -> TodoIndex\n    create POST           -> TodoCreate requires idempotency\n    show   GET    \"/:id\"  -> TodoShow\n    member POST \"/:id/done\" -> TodoDone requires idempotency\n  }\n}\n";

    const FLAT_TODO: &str = "app X entry Serve {\n  handlers H\n  route GET  \"/todos\"          -> TodoIndex\n  route POST \"/todos\"          -> TodoCreate requires idempotency\n  route GET  \"/todos/:id\"      -> TodoShow\n  route POST \"/todos/:id/done\" -> TodoDone requires idempotency\n}\n";

    /// Test 1 — a resource lowers byte-identically to the equivalent flat routes.
    #[test]
    fn resource_is_byte_identical_to_flat() {
        assert_eq!(
            lower_igweb(RESOURCE_TODO).unwrap(),
            lower_igweb(FLAT_TODO).unwrap()
        );
    }

    /// Test 2 — a missing `-> Contract` is rejected, line-positioned (no auto-naming).
    #[test]
    fn resource_requires_explicit_contract() {
        let src = "app X entry Serve {\n  handlers H\n  resource todos \"/todos\" {\n    index GET\n  }\n}\n";
        let err = lower_igweb(src).unwrap_err();
        assert!(err.message.contains("->"), "got {err:?}");
        assert_eq!(err.line, 4);
    }

    /// Test 3 — the action table validates methods: `index POST` and `create GET` are refused.
    #[test]
    fn resource_action_method_is_validated() {
        let bad_index = "app X entry Serve {\n  handlers H\n  resource todos \"/todos\" {\n    index POST -> X\n  }\n}\n";
        let e1 = lower_igweb(bad_index).unwrap_err();
        assert!(e1.message.contains("must use GET"), "got {e1:?}");
        assert_eq!(e1.line, 4);

        let bad_create = "app X entry Serve {\n  handlers H\n  resource todos \"/todos\" {\n    create GET -> X\n  }\n}\n";
        let e2 = lower_igweb(bad_create).unwrap_err();
        assert!(e2.message.contains("must use POST"), "got {e2:?}");
    }

    /// Test 4 — `show`/`update`/`delete` with no suffix default to `/:id`.
    #[test]
    fn resource_default_member_suffix_is_id() {
        let src = "app X entry Serve {\n  handlers H\n  resource todos \"/todos\" {\n    show   GET    -> S\n    update PATCH  -> U\n    delete DELETE -> D\n  }\n}\n";
        let ig = lower_igweb(src).unwrap();
        assert!(ig.contains("matches(req.path, \"^/todos/([^/]+)$\")"));
        assert!(
            ig.contains("call_contract(\"S\", req, capture(req.path, \"^/todos/([^/]+)$\", 1))")
        );
        // show/update/delete share the same `/todos/:id` pattern group (one matches arm).
        assert_eq!(
            ig.matches("matches(req.path, \"^/todos/([^/]+)$\")")
                .count(),
            1
        );
    }

    /// Test 5 — custom suffixes lower as written (`show "/:slug"`, `member "/:id/done"`).
    #[test]
    fn resource_custom_suffixes_lower() {
        let src = "app X entry Serve {\n  handlers H\n  resource todos \"/todos\" {\n    show   GET  \"/:slug\"    -> S\n    member POST \"/:id/done\" -> M requires idempotency\n  }\n}\n";
        let ig = lower_igweb(src).unwrap();
        assert!(ig.contains("matches(req.path, \"^/todos/([^/]+)$\")")); // /:slug
        assert!(
            ig.contains("call_contract(\"S\", req, capture(req.path, \"^/todos/([^/]+)$\", 1))")
        );
        assert!(ig.contains("matches(req.path, \"^/todos/([^/]+)/done$\")"));
        assert!(ig.contains("status: 400")); // member is mutating + requires idempotency
    }

    /// Test 6 — `index` + `create` share one pattern group, so DELETE on the base is 405 not 404.
    #[test]
    fn resource_same_path_grouping_405() {
        let ig = lower_igweb(RESOURCE_TODO).unwrap();
        // exactly one matches arm for the base `/todos` (index GET + create POST grouped).
        assert_eq!(ig.matches("matches(req.path, \"^/todos$\")").count(), 1);
        assert!(ig.contains("if req.method == \"GET\""));
        assert!(ig.contains("if req.method == \"POST\""));
        assert!(ig.contains("status: 405"));
        assert!(ig.contains("status: 404"));
    }

    /// Test 7 — a mutating resource action with `requires idempotency` emits the keyless 400 guard.
    #[test]
    fn resource_idempotency_guard() {
        let ig = lower_igweb(RESOURCE_TODO).unwrap();
        assert!(ig.contains("if req.idempotency_key == \"\""));
        assert!(ig.contains("status: 400"));
    }

    /// Test 8 — resource composes with a P16 scope prefix.
    #[test]
    fn resource_composes_with_scope() {
        let src = "app X entry Serve {\n  handlers H\n  scope \"/accounts/:account_id\" {\n    resource todos \"/todos\" {\n      index GET            -> AccountTodosIndex\n      show  GET \"/:todo_id\" -> AccountTodoShow\n    }\n  }\n}\n";
        let ig = lower_igweb(src).unwrap();
        assert!(ig.contains("matches(req.path, \"^/accounts/([^/]+)/todos$\")"));
        assert!(ig.contains("call_contract(\"AccountTodosIndex\", req, capture(req.path, \"^/accounts/([^/]+)/todos$\", 1))"));
        assert!(ig.contains("call_contract(\"AccountTodoShow\", req, capture(req.path, \"^/accounts/([^/]+)/todos/([^/]+)$\", 1), capture(req.path, \"^/accounts/([^/]+)/todos/([^/]+)$\", 2))"));
    }

    /// Test 9 — duplicate param across scope + resource suffix is refused (P16 rule still applies).
    #[test]
    fn resource_duplicate_param_refused() {
        let src = "app X entry Serve {\n  handlers H\n  scope \"/todos/:id\" {\n    resource comments \"/comments\" {\n      show GET \"/:id\" -> CommentShow\n    }\n  }\n}\n";
        let err = lower_igweb(src).unwrap_err();
        assert!(err.message.contains("duplicate"), "got {err:?}");
    }

    /// Test 10 — interleaved plain route / resource / scope keep authored arm order.
    #[test]
    fn resource_preserves_source_order() {
        let src = "app X entry Serve {\n  handlers H\n  route GET \"/health\" -> Health\n  resource todos \"/todos\" {\n    index GET -> TodoIndex\n  }\n  scope \"/s\" {\n    route GET \"/z\" -> Z\n  }\n}\n";
        let ig = lower_igweb(src).unwrap();
        let ih = ig.find("^/health$").expect("health");
        let it = ig.find("^/todos$").expect("todos");
        let iz = ig.find("^/s/z$").expect("s/z");
        assert!(ih < it && it < iz, "arm order must follow source order");
    }

    /// Test 13 — resource lowering is deterministic (byte-identical across two calls).
    #[test]
    fn resource_lowering_is_deterministic() {
        assert_eq!(
            lower_igweb(RESOURCE_TODO).unwrap(),
            lower_igweb(RESOURCE_TODO).unwrap()
        );
    }

    /// member/collection require an explicit suffix; unknown actions are refused.
    #[test]
    fn resource_member_needs_suffix_and_unknown_refused() {
        let no_suffix = "app X entry Serve {\n  handlers H\n  resource todos \"/todos\" {\n    member POST -> M\n  }\n}\n";
        assert!(lower_igweb(no_suffix)
            .unwrap_err()
            .message
            .contains("requires an explicit"));

        let unknown = "app X entry Serve {\n  handlers H\n  resource todos \"/todos\" {\n    frobnicate GET -> X\n  }\n}\n";
        assert!(lower_igweb(unknown)
            .unwrap_err()
            .message
            .contains("unknown resource action"));
    }

    /// Unclosed resource is reported (missing `}`).
    #[test]
    fn unclosed_resource_is_reported() {
        let src = "app X entry Serve {\n  handlers H\n  resource todos \"/todos\" {\n    index GET -> I\n";
        let err = lower_igweb(src).unwrap_err();
        assert!(err.message.contains("unclosed `resource"), "got {err:?}");
        assert_eq!(err.line, 3);
    }
}
