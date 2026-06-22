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

-- LAB-TODOAPP-VIEW-MANIFEST-P2: a tiny, domain-free structured-view envelope. `RespondView` lets a
-- handler return a typed view DESCRIPTOR whose JSON object becomes the wire body ROOT (not a string
-- inside `{\"body\": ...}`). `.ig` has no recursive types, so this is a 2-level page->items tree —
-- enough to prove the JSON-first ViewArtifact path; an arbitrary JSON body type is a later, named slice.
type ViewItem {
  key   : String
  label : String
}

type View {
  kind  : String
  title : String
  items : Collection[ViewItem]
}

-- LAB-IGNITER-WEB-VIEWARTIFACT-AUTHORING-P19: a bounded, domain-free typed descriptor matching the
-- render-html v0 `form` vocabulary. Flat HtmlNode (one record, `kind` + leaf fields, unused defaulted)
-- so the VM serializes it DIRECTLY to the renderer's kind-dispatched JSON — no variant/__arm adapter.
-- `RenderView` hands this typed value (not a JSON string); igniter-web serializes + projects it to HTML.
type HtmlNode {
  kind     : String
  id       : String
  label    : String
  text     : String
  required : Bool
  action   : String
  options  : Collection[String]
}

type ViewArtifact {
  artifact : String
  layout   : String
  title    : String
  body     : Collection[HtmlNode]
}

variant Decision {
  Respond      { status : Integer, body : String }
  InvokeEffect { target : String, input : Unknown, idempotency_key : String }
  RespondView  { status : Integer, view : View }
  Render       { status : Integer, artifact_json : String }
  RenderView   { status : Integer, view : ViewArtifact }
  ReadThen     { plan : Unknown, then : String }
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
    /// optional route-level guard (`via Guard(args) as name`); P20.
    via: Option<Via>,
    /// P26: explicit handler arg names from `-> Handler(a, b, …)` (None = legacy `req + captures`).
    handler_args: Option<Vec<String>>,
    /// P26: pre-resolved handler `call_contract(...)` expression (filled by `apply_bindings`).
    handler_call: Option<String>,
    /// P26/P27: pre-resolved guard `call_contract(...)` expressions, outer→inner. The handler is wrapped
    /// in one `match … { Ok { value } => … Err { error } => error }` per guard; with same-name
    /// accumulation (P27) each later guard receives the prior `value` and the handler sees the latest.
    guard_calls: Vec<String>,
}

/// A `let`/`guard` context binding (P26). `let` is infallible (lowers to a top-level `compute`); `guard`
/// is fallible (`Result[T, Decision]`, lowers to the P20 match). `args` are author-facing names resolved
/// to `req` / a `let` name / a path param / (for handler args) the guard's `value`.
#[derive(Clone)]
struct Binding {
    is_guard: bool,
    name: String,
    contract: String,
    args: Vec<String>,
    line: usize,
}

/// Parse `<name> = <Contract>(<arg,…>)` (the part after `let `/`guard `).
fn parse_binding(rest: &str, is_guard: bool, line: usize) -> Result<Binding, IgwebError> {
    let kw = if is_guard { "guard" } else { "let" };
    let (name, after_eq) = rest.split_once('=').ok_or(IgwebError {
        line,
        message: format!("expected `{kw} <name> = <Contract>(<args>)`"),
    })?;
    let name = name.trim().to_string();
    if name.is_empty() || name.split_whitespace().count() != 1 {
        return Err(IgwebError {
            line,
            message: format!("`{kw}` binding needs a single name before `=`"),
        });
    }
    let after_eq = after_eq.trim_start();
    let (contract, rest2) = after_eq.split_once('(').ok_or(IgwebError {
        line,
        message: format!("expected `(` after the `{kw}` contract name"),
    })?;
    let contract = contract.trim().to_string();
    if contract.is_empty() || contract.split_whitespace().count() != 1 {
        return Err(IgwebError {
            line,
            message: format!("`{kw} {name}` needs a single contract name"),
        });
    }
    let (args_str, tail) = rest2.split_once(')').ok_or(IgwebError {
        line,
        message: format!("expected `)` to close the `{kw} {name}` arguments"),
    })?;
    if !tail.trim().is_empty() {
        return Err(IgwebError {
            line,
            message: format!("unexpected tokens after `{kw} {name}(…)`"),
        });
    }
    let args: Vec<String> = if args_str.trim().is_empty() {
        Vec::new()
    } else {
        args_str.split(',').map(|a| a.trim().to_string()).collect()
    };
    for a in &args {
        if a.is_empty() || a.split_whitespace().count() != 1 {
            return Err(IgwebError {
                line,
                message: format!("`{kw} {name}` argument must be a single name"),
            });
        }
    }
    Ok(Binding {
        is_guard,
        name,
        contract,
        args,
        line,
    })
}

/// Resolve an author-facing arg name to its `.ig` expression: `req`, a `let` name (bare identifier),
/// the active guard's success payload (`value`), or a positional path capture. Unknown → line error.
fn resolve_arg(
    name: &str,
    line: usize,
    let_names: &[String],
    guard_name: Option<&str>,
    params: &[String],
    regex: &str,
) -> Result<String, IgwebError> {
    if name == "req" {
        Ok("req".to_string())
    } else if let_names.iter().any(|l| l == name) {
        Ok(name.to_string())
    } else if Some(name) == guard_name {
        Ok("value".to_string())
    } else if let Some(pos) = params.iter().position(|p| p == name) {
        Ok(capture_expr(regex, pos + 1))
    } else {
        Err(IgwebError {
            line,
            message: format!(
                "unknown arg `{}` (not `req`, a `let`, the guard, or a path param)",
                name
            ),
        })
    }
}

/// P26/P27: resolve the active `let`/`guard` bindings into the route's `guard_calls` + `handler_call`
/// expressions, with refusals. `guards` are ordered outer→inner and all share one binding name (same-name
/// accumulation, P27): the first guard cannot reference the context name; each later guard and the handler
/// resolve the shared name to the in-scope `value` (the prior / latest accumulated context). `via` and
/// P26/P27 bindings are mutually exclusive; a route with a guard or explicit handler args must list its
/// handler args explicitly (no auto-injection).
fn apply_bindings(
    route: &mut Route,
    let_names: &[String],
    guards: &[&Binding],
    line: usize,
) -> Result<(), IgwebError> {
    if route.via.is_some() {
        if !guards.is_empty() || route.handler_args.is_some() {
            return Err(IgwebError {
                line,
                message: "route-level `via` cannot be combined with `guard`/explicit handler args"
                    .into(),
            });
        }
        return Ok(()); // P20 via path, no bindings
    }
    if guards.is_empty() && route.handler_args.is_none() {
        return Ok(()); // legacy `req + captures` path
    }
    let ctx_name = guards.first().map(|g| g.name.as_str());
    // a binding name must not collide with a path param.
    for p in &route.params {
        if let_names.iter().any(|l| l == p) || ctx_name == Some(p.as_str()) {
            return Err(IgwebError {
                line,
                message: format!("binding name `{}` collides with a path param", p),
            });
        }
    }
    // each guard, outer→inner: the first cannot see the context name; later ones resolve it to `value`.
    route.guard_calls.clear();
    for (i, g) in guards.iter().enumerate() {
        let visible_ctx = if i == 0 { None } else { ctx_name };
        let resolved: Vec<String> = g
            .args
            .iter()
            .map(|a| {
                resolve_arg(
                    a,
                    g.line,
                    let_names,
                    visible_ctx,
                    &route.params,
                    &route.regex,
                )
            })
            .collect::<Result<_, _>>()?;
        route.guard_calls.push(format!(
            "call_contract(\"{}\", {})",
            g.contract,
            resolved.join(", ")
        ));
    }
    // handler args resolve the context name to the latest (innermost) `value`.
    let args = route.handler_args.as_ref().ok_or(IgwebError {
        line,
        message:
            "handler must list explicit args (e.g. `-> H(req, …)`) when a `guard`/`let` is active"
                .into(),
    })?;
    let resolved: Vec<String> = args
        .iter()
        .map(|a| resolve_arg(a, line, let_names, ctx_name, &route.params, &route.regex))
        .collect::<Result<_, _>>()?;
    route.handler_call = Some(format!(
        "call_contract(\"{}\", {})",
        route.contract,
        resolved.join(", ")
    ));
    Ok(())
}

/// A route-level guard clause `via <Contract>(<param,...>) as <name>` (P20). `arg_indices` are the
/// 1-based capture positions the named args resolve to in the composed pattern; the guard's success
/// context binds to the built-in `Result`'s fixed `Ok { value }` payload, so `as <name>` is author-
/// facing only (runtime binding stays positional).
struct Via {
    contract: String,
    arg_indices: Vec<usize>,
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

/// Is this trimmed line a complete standalone statement — a block opener (`… {`), a close (`}`), a
/// directive (`handlers`), or a binding (`let`/`guard`) — i.e. never a `->` continuation? Such lines are
/// emitted as-is and never absorbed into a multi-line `route`/action join.
fn is_block_or_directive(t: &str) -> bool {
    t == "}"
        || t.ends_with('{')
        || t.starts_with("handlers ")
        || t.starts_with("let ")
        || t.starts_with("guard ")
}

/// Fold physical lines into logical statements, dropping comments/blank lines and keeping each
/// statement's first physical line number for diagnostics. A `route`/resource-action statement may span
/// several physical lines (e.g. a multi-line `via` clause): any non-block line lacking `->` greedily
/// joins following non-block lines until `->` appears (or a block delimiter stops it). Single-line
/// statements (which already contain `->`) are returned unchanged, so P16/P17/P18 output is unaffected.
fn fold_logical_lines(src: &str) -> Vec<(usize, String)> {
    let phys: Vec<&str> = src.lines().collect();
    let mut out: Vec<(usize, String)> = Vec::new();
    let mut i = 0;
    while i < phys.len() {
        let t = phys[i].trim();
        let start = i + 1;
        if t.is_empty() || t.starts_with("--") || t.starts_with('#') {
            i += 1;
            continue;
        }
        if is_block_or_directive(t) || t.contains("->") {
            out.push((start, t.to_string()));
            i += 1;
            continue;
        }
        // Statement that still needs its `->`: join continuation lines until one provides it.
        let mut buf = t.to_string();
        i += 1;
        while i < phys.len() {
            let ct = phys[i].trim();
            if ct.is_empty() || ct.starts_with("--") || ct.starts_with('#') {
                i += 1;
                continue;
            }
            if is_block_or_directive(ct) {
                break; // do not absorb a delimiter; leave `buf` incomplete to error downstream.
            }
            buf.push(' ');
            buf.push_str(ct);
            i += 1;
            if buf.contains("->") {
                break;
            }
        }
        out.push((start, buf));
    }
    out
}

/// Parse `<METHOD> "<pattern>"` (the head of a route-body opener `route GET "/x" {`).
fn parse_method_pattern(s: &str, line: usize) -> Result<(String, String), IgwebError> {
    let (method, rest) = s.trim().split_once(char::is_whitespace).ok_or(IgwebError {
        line,
        message: "expected `<METHOD> \"<pattern>\"`".into(),
    })?;
    let rest = rest.trim_start();
    if !rest.starts_with('"') {
        return Err(IgwebError {
            line,
            message: "expected a quoted \"<pattern>\" after the method".into(),
        });
    }
    let inner = &rest[1..];
    let close = inner.find('"').ok_or(IgwebError {
        line,
        message: "unterminated route pattern string".into(),
    })?;
    if !inner[close + 1..].trim().is_empty() {
        return Err(IgwebError {
            line,
            message: "unexpected tokens after route pattern".into(),
        });
    }
    Ok((method.trim().to_string(), inner[..close].to_string()))
}

/// Record a `let`/`guard` binding: `let` resolves to a hoisted top-level `compute` (req/earlier-let only);
/// `guard` is pushed onto the active binding level. Refuses a duplicate binding name.
fn add_binding(
    is_guard: bool,
    rest: &str,
    line: usize,
    let_names: &mut Vec<String>,
    let_computes: &mut Vec<String>,
    binding_levels: &mut [Vec<Binding>],
) -> Result<(), IgwebError> {
    let b = parse_binding(rest, is_guard, line)?;
    let name_is_let = let_names.iter().any(|n| n == &b.name);
    let name_is_guard = binding_levels.iter().flatten().any(|x| x.name == b.name);
    // A `let` may not reuse any active name. A `guard` may reuse an existing GUARD name (P27 same-name
    // accumulation step), but not a `let` name.
    if (!is_guard && (name_is_let || name_is_guard)) || (is_guard && name_is_let) {
        return Err(IgwebError {
            line,
            message: format!("duplicate binding name `{}`", b.name),
        });
    }
    if is_guard {
        binding_levels
            .last_mut()
            .ok_or(IgwebError {
                line,
                message: "`guard` outside a block".into(),
            })?
            .push(b);
    } else {
        let resolved: Vec<String> = b
            .args
            .iter()
            .map(|a| resolve_arg(a, line, let_names, None, &[], ""))
            .collect::<Result<_, _>>()?;
        let_computes.push(format!(
            "compute {} = call_contract(\"{}\", {})",
            b.name,
            b.contract,
            resolved.join(", ")
        ));
        let_names.push(b.name);
    }
    Ok(())
}

/// Resolve a parsed route against the active bindings. Multiple active guards are allowed ONLY when they
/// share one binding name (P27 same-name accumulation); distinct names are refused (no ambiguous
/// multi-context environment). Then `apply_bindings` fills `guard_calls`/`handler_call`.
fn finalize_route(
    mut route: Route,
    binding_levels: &[Vec<Binding>],
    let_names: &[String],
    line: usize,
) -> Result<Route, IgwebError> {
    let guards: Vec<&Binding> = binding_levels
        .iter()
        .flatten()
        .filter(|b| b.is_guard)
        .collect();
    let mut names: Vec<&str> = guards.iter().map(|g| g.name.as_str()).collect();
    names.sort_unstable();
    names.dedup();
    if names.len() > 1 {
        return Err(IgwebError {
            line,
            message: format!(
                "distinct active `guard` names ({}); only same-name accumulation (e.g. `guard ctx` then `guard ctx`) is allowed",
                names.join(", ")
            ),
        });
    }
    apply_bindings(&mut route, let_names, &guards, line)?;
    Ok(route)
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
    // P26 context composition: hoisted `let` computes + their names; the active `guard` binding levels
    // (one Vec per open block); and an optional open route-body block.
    let mut let_computes: Vec<String> = Vec::new();
    let mut let_names: Vec<String> = Vec::new();
    let mut binding_levels: Vec<Vec<Binding>> = Vec::new();
    // (method, raw_pattern, line, handler-seen) of an open `route … { … }` body block.
    let mut in_route_body: Option<(String, String, usize, bool)> = None;

    for (line, logical) in fold_logical_lines(src) {
        let t = logical.as_str();
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
            binding_levels.push(Vec::new());
            continue;
        }
        if t == "}" {
            // `}` closes the innermost open block: route-body, else resource, else scope, else app.
            if let Some((_, _, _, done)) = in_route_body {
                if !done {
                    return Err(IgwebError {
                        line,
                        message: "route body must end with `-> Handler(...)` before `}`".into(),
                    });
                }
                in_route_body = None;
                binding_levels.pop();
                continue;
            }
            if in_resource.is_some() {
                in_resource = None;
                binding_levels.pop();
                continue;
            }
            if scope_stack.pop().is_some() {
                binding_levels.pop();
                continue;
            }
            if in_app {
                in_app = false;
                closed = true;
                binding_levels.pop();
                continue;
            }
            return Err(IgwebError {
                line,
                message: "unexpected `}` (no open `app`, `scope`, `resource`, or route block)"
                    .into(),
            });
        }
        // Inside a route body: only `let`/`guard` lines and the terminal `-> Handler(...)`.
        if let Some((method, raw_pattern, _, done)) = &in_route_body {
            if *done {
                return Err(IgwebError {
                    line,
                    message: "unexpected line after `-> Handler(...)` in route body".into(),
                });
            }
            if let Some(rest) = t.strip_prefix("let ") {
                add_binding(
                    false,
                    rest,
                    line,
                    &mut let_names,
                    &mut let_computes,
                    &mut binding_levels,
                )?;
                continue;
            }
            if let Some(rest) = t.strip_prefix("guard ") {
                add_binding(
                    true,
                    rest,
                    line,
                    &mut let_names,
                    &mut let_computes,
                    &mut binding_levels,
                )?;
                continue;
            }
            if t.starts_with("->") {
                let prefix = scope_stack
                    .last()
                    .map(String::as_str)
                    .unwrap_or("")
                    .to_string();
                let tail = format!("{} \"{}\" {}", method, raw_pattern, t);
                let r = parse_route(&tail, line, &prefix)?;
                let r = finalize_route(r, &binding_levels, &let_names, line)?;
                routes.push(r);
                if let Some(rb) = in_route_body.as_mut() {
                    rb.3 = true;
                }
                continue;
            }
            return Err(IgwebError {
                line,
                message: "route body only allows `let`/`guard`/`-> Handler(...)`".into(),
            });
        }
        // Inside a resource body, every non-`}` line is an action line (validated by the closed table).
        if let Some((base, _resource_line)) = in_resource.clone() {
            let r = parse_resource_action(t, line, &base)?;
            let r = finalize_route(r, &binding_levels, &let_names, line)?;
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
            binding_levels.push(Vec::new());
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
            binding_levels.push(Vec::new());
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
        // P26 `let`/`guard` binding at app/scope level.
        if let Some(rest) = t.strip_prefix("let ") {
            if !in_app {
                return Err(IgwebError {
                    line,
                    message: "`let` outside an `app { ... }` block".into(),
                });
            }
            add_binding(
                false,
                rest,
                line,
                &mut let_names,
                &mut let_computes,
                &mut binding_levels,
            )?;
            continue;
        }
        if let Some(rest) = t.strip_prefix("guard ") {
            if !in_app {
                return Err(IgwebError {
                    line,
                    message: "`guard` outside an `app { ... }` block".into(),
                });
            }
            add_binding(
                true,
                rest,
                line,
                &mut let_names,
                &mut let_computes,
                &mut binding_levels,
            )?;
            continue;
        }
        if let Some(rest) = t.strip_prefix("route ") {
            if !in_app {
                return Err(IgwebError {
                    line,
                    message: "`route` outside an `app { ... }` block".into(),
                });
            }
            if t.ends_with('{') {
                // route-body opener: `route GET "/x" {`
                let opener = rest.trim_end_matches('{').trim();
                let (method, raw_pattern) = parse_method_pattern(opener, line)?;
                in_route_body = Some((method, raw_pattern, line, false));
                binding_levels.push(Vec::new());
                continue;
            }
            let prefix = scope_stack.last().map(String::as_str).unwrap_or("");
            let r = parse_route(rest, line, prefix)?;
            let r = finalize_route(r, &binding_levels, &let_names, line)?;
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
    if let Some((_, _, body_line, _)) = in_route_body {
        return Err(IgwebError {
            line: body_line,
            message: "unclosed route `{ ... }` body block (missing `}`)".into(),
        });
    }
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

    Ok(generate_ig(&entry, &handlers, &routes, &let_computes))
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
    // `mid` is whatever sits between the (optional) suffix and `->` — i.e. an optional `via` clause,
    // forwarded verbatim to route parsing so resource actions reuse the same `via` lowering.
    let (suffix, mid) = if rest_head.is_empty() {
        (None, "")
    } else if rest_head.starts_with('"') {
        let inner = &rest_head[1..];
        let close = inner.find('"').ok_or(IgwebError {
            line,
            message: "unterminated resource suffix string".into(),
        })?;
        (Some(&inner[..close]), inner[close + 1..].trim())
    } else {
        // no quoted suffix; the remainder (e.g. a `via ...` clause) is forwarded to route parsing.
        (None, rest_head)
    };
    let effective = resource_action_suffix(action, method, suffix, line)?;
    let route_tail = format!(
        "{} \"{}\" {} -> {}",
        method,
        effective,
        mid,
        contract_part.trim()
    );
    parse_route(&route_tail, line, base)
}

/// `capture(req.path, "<regex>", <idx>)` — a single positional path-capture expression.
fn capture_expr(regex: &str, idx: usize) -> String {
    format!("capture(req.path, \"{}\", {})", regex, idx)
}

/// If `s` starts with the keyword `kw` followed by whitespace, return the trimmed remainder.
/// (`strip_keyword("via Load", "via") == Some("Load")`; `strip_keyword("viaduct", "via") == None`.)
fn strip_keyword<'a>(s: &'a str, kw: &str) -> Option<&'a str> {
    let rest = s.strip_prefix(kw)?;
    match rest.chars().next() {
        Some(c) if c.is_whitespace() => Some(rest.trim_start()),
        _ => None,
    }
}

/// Parse a route-level `via <Contract>(<arg,...>) as <name>` clause (text AFTER the `via ` keyword).
/// Returns `(contract, arg_names, remaining)` where `remaining` should begin with `->`. `<name>` is
/// validated but discarded (P20 binds the built-in `Ok { value }` payload; runtime stays positional).
fn parse_via_inner(s: &str, line: usize) -> Result<(String, Vec<String>, &str), IgwebError> {
    let (contract, after_name) = s.split_once('(').ok_or(IgwebError {
        line,
        message: "expected `(` after the via guard name".into(),
    })?;
    let contract = contract.trim().to_string();
    if contract.is_empty() || contract.split_whitespace().count() != 1 {
        return Err(IgwebError {
            line,
            message: "via guard name must be a single contract name".into(),
        });
    }
    let (args_str, after_paren) = after_name.split_once(')').ok_or(IgwebError {
        line,
        message: "expected `)` to close the via guard arguments".into(),
    })?;
    let args: Vec<String> = if args_str.trim().is_empty() {
        Vec::new()
    } else {
        args_str.split(',').map(|a| a.trim().to_string()).collect()
    };
    for a in &args {
        if a.is_empty() || a.split_whitespace().count() != 1 {
            return Err(IgwebError {
                line,
                message: "via guard argument must be a single path-param name".into(),
            });
        }
    }
    if let Some(dup) = first_duplicate(&args) {
        return Err(IgwebError {
            line,
            message: format!("duplicate via guard argument `{}`", dup),
        });
    }
    let after_as = strip_keyword(after_paren.trim_start(), "as").ok_or(IgwebError {
        line,
        message: "expected `as <name>` after the via guard arguments".into(),
    })?;
    let (name, remaining) = match after_as.split_once(char::is_whitespace) {
        Some((n, r)) => (n.trim(), r.trim_start()),
        None => (after_as.trim(), ""),
    };
    if name.is_empty() || name == "->" {
        return Err(IgwebError {
            line,
            message: "expected a context name after `as`".into(),
        });
    }
    Ok((contract, args, remaining))
}

/// Parse `<METHOD> "<pattern>" [via <Guard>(args) as name] -> <Contract> [requires idempotency]`
/// (the part after `route `). `prefix` is the enclosing scope's absolute path (empty at top level); the
/// route pattern is composed onto it before regex/param generation, so the lowered route is identical to
/// the hand-written flat one. The optional `via` clause lowers to a static `call_contract + match` guard.
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
    // optional route-level `via <Guard>(args) as name` before the `->` (P20).
    let mut via_parsed: Option<(String, Vec<String>)> = None;
    let rest = if let Some(after_via) = strip_keyword(rest, "via") {
        let (contract, args, remaining) = parse_via_inner(after_via, line)?;
        via_parsed = Some((contract, args));
        remaining
    } else {
        rest
    };
    // ->
    let rest = rest
        .strip_prefix("->")
        .ok_or(IgwebError {
            line,
            message: "expected `->` before the handler contract".into(),
        })?
        .trim_start();
    // Contract [(<explicit handler args>)] [requires idempotency]
    let split_at = rest
        .find(|c: char| c == '(' || c.is_whitespace())
        .unwrap_or(rest.len());
    let contract = rest[..split_at].to_string();
    if contract.is_empty() {
        return Err(IgwebError {
            line,
            message: "missing handler contract name after `->`".into(),
        });
    }
    let after_contract = rest[split_at..].trim_start();
    // optional explicit handler arg list `(a, b, …)` (P26).
    let (handler_args, after_args) = if after_contract.starts_with('(') {
        let inner = &after_contract[1..];
        let close = inner.find(')').ok_or(IgwebError {
            line,
            message: "expected `)` to close the handler argument list".into(),
        })?;
        let args_str = &inner[..close];
        let args: Vec<String> = if args_str.trim().is_empty() {
            Vec::new()
        } else {
            args_str.split(',').map(|a| a.trim().to_string()).collect()
        };
        for a in &args {
            if a.is_empty() || a.split_whitespace().count() != 1 {
                return Err(IgwebError {
                    line,
                    message: "handler argument must be a single name".into(),
                });
            }
        }
        (Some(args), inner[close + 1..].trim_start())
    } else {
        (None, after_contract)
    };
    let tail: Vec<&str> = after_args.split_whitespace().collect();
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
    // Resolve via guard arg names → positional capture indices in the composed pattern.
    let via = match via_parsed {
        None => None,
        Some((contract, args)) => {
            let mut arg_indices = Vec::with_capacity(args.len());
            for a in &args {
                let pos = params.iter().position(|p| p == a).ok_or(IgwebError {
                    line,
                    message: format!("via guard arg `{}` is not a path param of `{}`", a, pattern),
                })?;
                arg_indices.push(pos + 1);
            }
            Some(Via {
                contract,
                arg_indices,
            })
        }
    };
    Ok(Route {
        method,
        pattern,
        contract,
        requires_idem,
        params,
        regex,
        via,
        handler_args,
        handler_call: None,
        guard_calls: Vec::new(),
    })
}

/// Distinct patterns in first-seen order.
/// Distinct patterns in first-seen (authored) order, each paired with its anchored regex and the
/// source-order routes (method group) for that pattern. This is the leaf list the route tree is built
/// over — one leaf per distinct path pattern, exactly as the old linear chain grouped them.
fn route_entries(routes: &[Route]) -> Vec<(String, Vec<&Route>)> {
    let mut order: Vec<&str> = Vec::new();
    for r in routes {
        if !order.iter().any(|p| *p == r.pattern.as_str()) {
            order.push(r.pattern.as_str());
        }
    }
    order
        .iter()
        .map(|pat| {
            let group: Vec<&Route> = routes.iter().filter(|r| r.pattern == *pat).collect();
            (group[0].regex.clone(), group)
        })
        .collect()
}

/// An anchored alternation matching iff ANY entry's pattern matches — `^(inner0|inner1|…)$`, where each
/// inner is that entry's regex with its `^`/`$` anchors stripped. Used ONLY as a boolean prune at internal
/// tree nodes (the union is exact, so "left-combined matched" ⟺ "some authored-earlier route matches");
/// captures are never taken from it — leaves re-test their own single pattern.
fn combined_regex(entries: &[(String, Vec<&Route>)]) -> String {
    let inners: Vec<&str> = entries
        .iter()
        .map(|(re, _)| {
            re.strip_prefix('^')
                .and_then(|x| x.strip_suffix('$'))
                .unwrap_or(re.as_str())
        })
        .collect();
    format!("^({})$", inners.join("|"))
}

fn generate_ig(
    entry: &str,
    handlers_module: &str,
    routes: &[Route],
    let_computes: &[String],
) -> String {
    let mut out = String::new();
    out.push_str("-- GENERATED by lower_igweb (LAB-IGNITER-WEB-ROUTING-LOWERING-P4/P10). Do not edit by hand.\n");
    out.push_str("-- Routing/product meaning lives here (the app), never in igniter-server.\n");
    out.push_str("module AppRoutes\n");
    out.push_str(&format!("import {}\n", PRELUDE_MODULE));
    out.push_str(&format!("import {}\n\n", handlers_module));
    out.push_str(&format!("pure contract {} {{\n", entry));
    out.push_str("  input req : Request\n");
    // P26: hoisted `let` bindings become top-level computes (req-only / earlier-let-only), in scope for
    // every route arm's guard/handler.
    for c in let_computes {
        out.push_str(&format!("  {}\n", c));
    }
    out.push_str("  compute decision : Decision =\n");
    out.push_str(&route_tree(&route_entries(routes), 4));
    out.push_str("\n  output decision : Decision\n");
    out.push_str("}\n");
    out
}

fn pad(n: usize) -> String {
    " ".repeat(n)
}

/// Emit the route dispatch as a BALANCED BINARY TREE over the distinct-pattern leaves (in authored
/// order), instead of a route-linear nested chain. Nesting depth is therefore `O(log N)` — bounded for
/// thousands of routes — removing the ~116-route serde/typechecker depth wall (LAB-...-P2/P3), while
/// behavior is identical:
///   - LEAF (one pattern): `if matches(req.path, "<exact regex>") { <method-chain> } else { Respond 404 }`.
///     The exact re-test is the source of truth (so correctness never depends on the prune regex), keeps
///     captures + same-path 405 grouping unchanged, and is where a global no-match path returns 404.
///   - INTERNAL: `if matches(req.path, "<left-combined>") { <left> } else { <right> }`, where `left` is the
///     authored-EARLIER half. Since the combined union is exact, descending left whenever a left pattern
///     matches reproduces "first authored match wins" — including P18 static-vs-param shadowing. No
///     most-specific-wins reordering; only static `call_contract` leaves; no new `.ig` node.
fn route_tree(entries: &[(String, Vec<&Route>)], indent: usize) -> String {
    if entries.is_empty() {
        return format!(
            "{}Respond {{ status: 404, body: \"not found\" }}",
            pad(indent)
        );
    }
    if entries.len() == 1 {
        let (regex, group) = &entries[0];
        let mut s = format!("{}if matches(req.path, \"{}\") {{\n", pad(indent), regex);
        s.push_str(&method_chain(group, indent + 2));
        s.push('\n');
        s.push_str(&format!(
            "{}}} else {{\n{}Respond {{ status: 404, body: \"not found\" }}\n{}}}",
            pad(indent),
            pad(indent + 2),
            pad(indent)
        ));
        return s;
    }
    // split into authored-earlier (left) and authored-later (right) halves; left is tried first.
    let mid = entries.len() / 2;
    let (left, right) = entries.split_at(mid);
    let mut s = format!(
        "{}if matches(req.path, \"{}\") {{\n",
        pad(indent),
        combined_regex(left)
    );
    s.push_str(&route_tree(left, indent + 2));
    s.push('\n');
    s.push_str(&format!("{}}} else {{\n", pad(indent)));
    s.push_str(&route_tree(right, indent + 2));
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

/// A single route's body: an idempotency 400-guard (if `requires idempotency`) wrapping either a static
/// handler `call_contract` (regexp-captured params as `Option[String]`), or — when the route carries a
/// `via` guard — a `match call_contract("Guard", …) { Ok { value } => <handler> Err { error } => error }`.
fn handler_arm(r: &Route) -> String {
    let body = if let Some(hcall) = &r.handler_call {
        // P26/P27: `let`/`guard` bindings. Nest one match per active guard (outer→inner) around the
        // pre-resolved handler call; with no guard the handler call stands alone. Same-name accumulation
        // means each inner `value` shadows the outer intentionally — `value` is always the latest context.
        let mut inner = hcall.clone();
        for gcall in r.guard_calls.iter().rev() {
            inner = format!(
                "match {} {{ Ok {{ value }} => {} Err {{ error }} => error }}",
                gcall, inner
            );
        }
        inner
    } else if let Some(via) = &r.via {
        // guard call: req + the named args resolved to their positional captures.
        let mut guard = format!("call_contract(\"{}\", req", via.contract);
        for &idx in &via.arg_indices {
            guard.push_str(&format!(", {}", capture_expr(&r.regex, idx)));
        }
        guard.push(')');
        // handler call: req, the guard's success context `value`, then captures NOT consumed by the
        // guard, in path order.
        let mut hcall = format!("call_contract(\"{}\", req, value", r.contract);
        for idx in 1..=r.params.len() {
            if !via.arg_indices.contains(&idx) {
                hcall.push_str(&format!(", {}", capture_expr(&r.regex, idx)));
            }
        }
        hcall.push(')');
        // Built-in sealed `Result`: success arm `Ok { value }`, error arm `Err { error }` (the
        // short-circuit `Decision`). The guard passes its `value` to the handler; `Err` forwards `error`.
        format!(
            "match {} {{ Ok {{ value }} => {} Err {{ error }} => error }}",
            guard, hcall
        )
    } else {
        let mut call = format!("call_contract(\"{}\", req", r.contract);
        for (idx, _name) in r.params.iter().enumerate() {
            call.push_str(&format!(
                ", capture(req.path, \"{}\", {})",
                r.regex,
                idx + 1
            ));
        }
        call.push(')');
        call
    };
    if r.requires_idem {
        format!(
            "if req.idempotency_key == \"\" {{ Respond {{ status: 400, body: \"missing idempotency-key\" }} }} else {{ {} }}",
            body
        )
    } else {
        body
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

    // ---- P18: nested resources by composition (`scope` wraps `resource`, no new keyword) ----

    const NESTED: &str = "app X entry Serve {\n  handlers H\n  scope \"/accounts/:account_id\" {\n    resource todos \"/todos\" {\n      index      GET                  -> AccountTodosIndex\n      create     POST                 -> AccountTodoCreate requires idempotency\n      show       GET \"/:todo_id\"        -> AccountTodoShow\n      member     POST \"/:todo_id/done\"  -> AccountTodoDone requires idempotency\n      collection GET \"/overdue\"         -> AccountTodosOverdue\n    }\n  }\n}\n";

    /// Test 4 — `index` + `create` share one composed `/accounts/:account_id/todos` group (GET/POST → 405).
    #[test]
    fn nested_index_create_same_path_group() {
        let ig = lower_igweb(NESTED).unwrap();
        assert_eq!(
            ig.matches("matches(req.path, \"^/accounts/([^/]+)/todos$\")")
                .count(),
            1
        );
        assert!(ig.contains("if req.method == \"GET\""));
        assert!(ig.contains("if req.method == \"POST\""));
        assert!(ig.contains("status: 405"));
        assert!(ig.contains("status: 404"));
    }

    /// Test 3 — collection (static suffix) and member (param suffix) lower correctly under nesting.
    #[test]
    fn nested_collection_and_member_suffixes() {
        let ig = lower_igweb(NESTED).unwrap();
        assert!(ig.contains("matches(req.path, \"^/accounts/([^/]+)/todos/overdue$\")"));
        assert!(ig.contains("call_contract(\"AccountTodosOverdue\", req, capture(req.path, \"^/accounts/([^/]+)/todos/overdue$\", 1))"));
        assert!(ig.contains("matches(req.path, \"^/accounts/([^/]+)/todos/([^/]+)/done$\")"));
        assert!(ig.contains("call_contract(\"AccountTodoDone\", req, capture(req.path, \"^/accounts/([^/]+)/todos/([^/]+)/done$\", 1), capture(req.path, \"^/accounts/([^/]+)/todos/([^/]+)/done$\", 2))"));
    }

    /// Test 5 — scoped resource mutating actions keep the keyless 400 idempotency guard.
    #[test]
    fn nested_idempotency_guard_preserved() {
        let ig = lower_igweb(NESTED).unwrap();
        assert!(ig.contains("if req.idempotency_key == \"\""));
        assert!(ig.contains("status: 400"));
    }

    /// Test 6 — a duplicate param across scope + resource suffix is refused (P16/P17 path).
    #[test]
    fn nested_duplicate_param_refused() {
        let src = "app X entry Serve {\n  handlers H\n  scope \"/accounts/:id\" {\n    resource todos \"/todos\" {\n      show GET \"/:id\" -> BadShow\n    }\n  }\n}\n";
        let err = lower_igweb(src).unwrap_err();
        assert!(err.message.contains("duplicate"), "got {err:?}");
    }

    /// Test 7 — authored order decides priority; IgWeb does NOT auto-rank static vs param suffixes.
    /// collection-before-show emits the static `/overdue` arm first; show-before-collection reverses it.
    #[test]
    fn nested_authored_order_decides_priority() {
        let coll_first = "app X entry Serve {\n  handlers H\n  scope \"/accounts/:account_id\" {\n    resource todos \"/todos\" {\n      collection GET \"/overdue\" -> AccountTodosOverdue\n      show       GET \"/:todo_id\" -> AccountTodoShow\n    }\n  }\n}\n";
        let ig1 = lower_igweb(coll_first).unwrap();
        let i_overdue = ig1.find("^/accounts/([^/]+)/todos/overdue$").unwrap();
        let i_show = ig1.find("^/accounts/([^/]+)/todos/([^/]+)$").unwrap();
        assert!(
            i_overdue < i_show,
            "collection authored first → its static arm is checked first"
        );

        let show_first = "app X entry Serve {\n  handlers H\n  scope \"/accounts/:account_id\" {\n    resource todos \"/todos\" {\n      show       GET \"/:todo_id\" -> AccountTodoShow\n      collection GET \"/overdue\" -> AccountTodosOverdue\n    }\n  }\n}\n";
        let ig2 = lower_igweb(show_first).unwrap();
        let j_show = ig2.find("^/accounts/([^/]+)/todos/([^/]+)$").unwrap();
        let j_overdue = ig2.find("^/accounts/([^/]+)/todos/overdue$").unwrap();
        assert!(
            j_show < j_overdue,
            "show authored first → its param arm is checked first (shadowing /overdue)"
        );
    }

    /// Test 8 — nested resource keeps source order among sibling plain routes.
    #[test]
    fn nested_preserves_source_order_with_siblings() {
        let src = "app X entry Serve {\n  handlers H\n  route GET \"/health\" -> Health\n  scope \"/accounts/:account_id\" {\n    resource todos \"/todos\" {\n      index GET -> AccountTodosIndex\n    }\n  }\n  route GET \"/version\" -> Version\n}\n";
        let ig = lower_igweb(src).unwrap();
        let ih = ig.find("^/health$").unwrap();
        let it = ig.find("^/accounts/([^/]+)/todos$").unwrap();
        let iv = ig.find("^/version$").unwrap();
        assert!(ih < it && it < iv, "arm order must follow source order");
    }

    /// Test 11 — nested lowering is deterministic (byte-identical across two calls).
    #[test]
    fn nested_lowering_is_deterministic() {
        assert_eq!(lower_igweb(NESTED).unwrap(), lower_igweb(NESTED).unwrap());
    }

    // ---- P20: route-level single `via` guard ----

    /// Tests 1 + 2 + 7 — a route-level `via` lowers to the static `call_contract + match` shape over the
    /// built-in `Result`, with the guard arg resolved to capture 1 and the exact `Err { error } => error`
    /// passthrough.
    #[test]
    fn via_lowers_to_guard_match() {
        let src = "app X entry Serve {\n  handlers H\n  route GET \"/accounts/:account_id/todos\" via LoadAccount(account_id) as account -> AccountTodosIndex\n}\n";
        let ig = lower_igweb(src).unwrap();
        assert!(ig.contains(
            "match call_contract(\"LoadAccount\", req, capture(req.path, \"^/accounts/([^/]+)/todos$\", 1)) { Ok { value } => call_contract(\"AccountTodosIndex\", req, value) Err { error } => error }"
        ), "got:\n{ig}");
    }

    /// Test 3 — handler receives `req`, the guard context `value`, then only UNCONSUMED captures
    /// (account_id consumed by the guard, todo_id passed through as capture 2).
    #[test]
    fn via_handler_gets_value_then_unconsumed_captures() {
        let src = "app X entry Serve {\n  handlers H\n  route GET \"/accounts/:account_id/todos/:todo_id\" via LoadAccount(account_id) as account -> AccountTodoShow\n}\n";
        let ig = lower_igweb(src).unwrap();
        assert!(ig.contains(
            "Ok { value } => call_contract(\"AccountTodoShow\", req, value, capture(req.path, \"^/accounts/([^/]+)/todos/([^/]+)$\", 2))"
        ), "got:\n{ig}");
        // the consumed capture (account_id = index 1) is NOT re-passed to the handler.
        assert!(
            !ig.contains("req, value, capture(req.path, \"^/accounts/([^/]+)/todos/([^/]+)$\", 1)")
        );
    }

    /// Test 4 — an unknown guard arg name is refused, line-positioned.
    #[test]
    fn via_unknown_arg_refused() {
        let src = "app X entry Serve {\n  handlers H\n  route GET \"/accounts/:account_id/todos\" via LoadAccount(nope) as a -> H\n}\n";
        let err = lower_igweb(src).unwrap_err();
        assert!(err.message.contains("not a path param"), "got {err:?}");
        assert_eq!(err.line, 3);
    }

    /// Test 5 — bad `via` shapes are rejected (missing `as`, missing parens, missing name, `via` after
    /// `->`, and a second `via`).
    #[test]
    fn via_bad_shapes_refused() {
        let cases = [
            "route GET \"/x/:p\" via A(p) -> H",      // missing `as`
            "route GET \"/x/:p\" via A as a -> H",    // missing parens
            "route GET \"/x/:p\" via (p) as a -> H",  // missing guard name
            "route GET \"/x/:p\" via A(p) as -> H",   // missing context name
            "route GET \"/x/:p\" -> H via A(p) as a", // via after ->
            "route GET \"/x/:p\" via A(p) as a via B(p) as b -> H", // second via
        ];
        for c in cases {
            let src = format!("app X entry Serve {{\n  handlers H\n  {c}\n}}\n");
            assert!(lower_igweb(&src).is_err(), "should reject: {c}");
        }
    }

    /// Test 6 — `requires idempotency` keeps the keyless 400 guard OUTERMOST, wrapping the via match.
    #[test]
    fn via_idempotency_guard_is_outermost() {
        let src = "app X entry Serve {\n  handlers H\n  route POST \"/accounts/:account_id/todos\" via LoadAccount(account_id) as account -> AccountTodoCreate requires idempotency\n}\n";
        let ig = lower_igweb(src).unwrap();
        assert!(ig.contains(
            "if req.idempotency_key == \"\" { Respond { status: 400, body: \"missing idempotency-key\" } } else { match call_contract(\"LoadAccount\", req"
        ), "got:\n{ig}");
    }

    /// Test 8 + 9 — `via` works through a resource action, composing with scope + nesting.
    #[test]
    fn via_through_scoped_resource_action() {
        let src = "app X entry Serve {\n  handlers H\n  scope \"/accounts/:account_id\" {\n    resource todos \"/todos\" {\n      show GET \"/:todo_id\" via LoadAccount(account_id) as account -> AccountTodoShow\n    }\n  }\n}\n";
        let ig = lower_igweb(src).unwrap();
        assert!(ig.contains(
            "match call_contract(\"LoadAccount\", req, capture(req.path, \"^/accounts/([^/]+)/todos/([^/]+)$\", 1)) { Ok { value } => call_contract(\"AccountTodoShow\", req, value, capture(req.path, \"^/accounts/([^/]+)/todos/([^/]+)$\", 2)) Err { error } => error }"
        ), "got:\n{ig}");
    }

    /// The multi-line `via` authoring form folds to the same `.ig` as the single-line form.
    #[test]
    fn via_multiline_equals_single_line() {
        let single = "app X entry Serve {\n  handlers H\n  route GET \"/accounts/:account_id/todos\" via LoadAccount(account_id) as account -> AccountTodosIndex\n}\n";
        let multi = "app X entry Serve {\n  handlers H\n  route GET \"/accounts/:account_id/todos\"\n    via LoadAccount(account_id) as account\n    -> AccountTodosIndex\n}\n";
        assert_eq!(lower_igweb(single).unwrap(), lower_igweb(multi).unwrap());
    }

    /// Test 13 — via lowering is deterministic (byte-identical across two calls).
    #[test]
    fn via_lowering_is_deterministic() {
        let src = "app X entry Serve {\n  handlers H\n  route GET \"/accounts/:account_id/todos/:todo_id\" via LoadAccount(account_id) as account -> AccountTodoShow\n}\n";
        assert_eq!(lower_igweb(src).unwrap(), lower_igweb(src).unwrap());
    }

    /// A guard with no args lowers to `call_contract("Guard", req)` (req-only guard, e.g. auth).
    #[test]
    fn via_zero_arg_guard() {
        let src = "app X entry Serve {\n  handlers H\n  route GET \"/me\" via RequireAuth() as session -> Me\n}\n";
        let ig = lower_igweb(src).unwrap();
        assert!(ig.contains(
            "match call_contract(\"RequireAuth\", req) { Ok { value } => call_contract(\"Me\", req, value) Err { error } => error }"
        ), "got:\n{ig}");
    }

    // ---- P26: let/guard context composition ----

    const CTX: &str = "app ContextDemo entry Serve {\n  handlers ContextHandlers\n  let req_info = ReqInfo(req)\n  scope \"/accounts/:account_id\" {\n    guard account = LoadAccount(req, req_info, account_id)\n    resource todos \"/todos\" {\n      index GET -> TodoIndex(req, req_info, account)\n      show  GET \"/:todo_id\" -> TodoShow(req, req_info, account, todo_id)\n    }\n  }\n}\n";

    /// `let` hoists to a top-level compute; scope `guard` + explicit handler args lower to the P20 match
    /// with names resolved to `req` / let / guard `value` / path capture.
    #[test]
    fn ctx_let_guard_explicit_args_lower() {
        let ig = lower_igweb(CTX).unwrap();
        assert!(
            ig.contains("  compute req_info = call_contract(\"ReqInfo\", req)\n"),
            "let hoist:\n{ig}"
        );
        // index: account_id consumed by the guard (capture 1); handler gets req, req_info, value.
        assert!(ig.contains(
            "match call_contract(\"LoadAccount\", req, req_info, capture(req.path, \"^/accounts/([^/]+)/todos$\", 1)) { Ok { value } => call_contract(\"TodoIndex\", req, req_info, value) Err { error } => error }"
        ), "index arm:\n{ig}");
        // show: todo_id is an unconsumed param → capture 2 in the handler.
        assert!(ig.contains(
            "match call_contract(\"LoadAccount\", req, req_info, capture(req.path, \"^/accounts/([^/]+)/todos/([^/]+)$\", 1)) { Ok { value } => call_contract(\"TodoShow\", req, req_info, value, capture(req.path, \"^/accounts/([^/]+)/todos/([^/]+)$\", 2)) Err { error } => error }"
        ), "show arm:\n{ig}");
    }

    /// A route-body block `route … { let …; guard …; -> H(...) }` lowers the same way.
    #[test]
    fn ctx_route_body_block_lowers() {
        let src = "app X entry Serve {\n  handlers H\n  route GET \"/accounts/:account_id/todos/:todo_id\" {\n    let req_info = ReqInfo(req)\n    guard account = LoadAccount(req, req_info, account_id)\n    -> TodoShow(req, req_info, account, todo_id)\n  }\n}\n";
        let ig = lower_igweb(src).unwrap();
        assert!(ig.contains("compute req_info = call_contract(\"ReqInfo\", req)"));
        assert!(ig.contains(
            "match call_contract(\"LoadAccount\", req, req_info, capture(req.path, \"^/accounts/([^/]+)/todos/([^/]+)$\", 1)) { Ok { value } => call_contract(\"TodoShow\", req, req_info, value, capture(req.path, \"^/accounts/([^/]+)/todos/([^/]+)$\", 2)) Err { error } => error }"
        ), "got:\n{ig}");
    }

    /// `let` + explicit args with NO guard → a bare handler call (no match), idempotency stays outermost.
    #[test]
    fn ctx_let_only_and_idempotency_outermost() {
        let src = "app X entry Serve {\n  handlers H\n  let req_info = ReqInfo(req)\n  route POST \"/p/:id\" -> Make(req, req_info, id) requires idempotency\n}\n";
        let ig = lower_igweb(src).unwrap();
        assert!(ig.contains(
            "if req.idempotency_key == \"\" { Respond { status: 400, body: \"missing idempotency-key\" } } else { call_contract(\"Make\", req, req_info, capture(req.path, \"^/p/([^/]+)$\", 1)) }"
        ), "got:\n{ig}");
    }

    /// Refusals (all line-positioned).
    #[test]
    fn ctx_refusals() {
        // unknown handler arg
        let unknown = "app X entry Serve {\n  handlers H\n  route GET \"/x\" -> H(req, nope)\n}\n";
        assert!(lower_igweb(unknown)
            .unwrap_err()
            .message
            .contains("unknown arg"));
        // duplicate binding name
        let dup = "app X entry Serve {\n  handlers H\n  let a = F(req)\n  let a = G(req)\n  route GET \"/x\" -> H(req, a)\n}\n";
        assert!(lower_igweb(dup)
            .unwrap_err()
            .message
            .contains("duplicate binding"));
        // binding name collides with a path param
        let collide = "app X entry Serve {\n  handlers H\n  scope \"/a/:account\" {\n    guard account = LoadAccount(req)\n    route GET \"/x\" -> H(req, account)\n  }\n}\n";
        assert!(lower_igweb(collide)
            .unwrap_err()
            .message
            .contains("collides with a path param"));
        // forward reference: a let referencing a later let
        let fwd = "app X entry Serve {\n  handlers H\n  let a = F(b)\n  let b = G(req)\n  route GET \"/x\" -> H(req, a, b)\n}\n";
        assert!(lower_igweb(fwd)
            .unwrap_err()
            .message
            .contains("unknown arg"));
        // distinct active guard names (P27 only allows same-name accumulation)
        let two = "app X entry Serve {\n  handlers H\n  guard user = RequireUser(req)\n  scope \"/a/:id\" {\n    guard account = LoadAccount(req, id)\n    route GET \"/x\" -> H(req, user, account)\n  }\n}\n";
        assert!(lower_igweb(two)
            .unwrap_err()
            .message
            .contains("distinct active `guard`"));
        // via cannot mix with explicit args / guard
        let mix = "app X entry Serve {\n  handlers H\n  route GET \"/a/:id\" via G(id) as g -> H(req, g)\n}\n";
        assert!(lower_igweb(mix)
            .unwrap_err()
            .message
            .contains("cannot be combined"));
        // route-body opener rejects stray tokens after the quoted pattern
        let extra = "app X entry Serve {\n  handlers H\n  route GET \"/x\" extra {\n    -> H(req)\n  }\n}\n";
        assert!(lower_igweb(extra)
            .unwrap_err()
            .message
            .contains("unexpected tokens"));
        // unclosed route body
        let unclosed =
            "app X entry Serve {\n  handlers H\n  route GET \"/x\" {\n    let a = F(req)\n";
        assert!(lower_igweb(unclosed)
            .unwrap_err()
            .message
            .contains("unclosed route"));
    }

    /// `let`/`guard` lowering is deterministic.
    #[test]
    fn ctx_lowering_is_deterministic() {
        assert_eq!(lower_igweb(CTX).unwrap(), lower_igweb(CTX).unwrap());
    }

    // ---- P27: same-name guard accumulation ----

    const ACCUM: &str = "app TodoWeb entry Serve {\n  handlers H\n  let req_info = ReqInfo(req)\n  guard ctx = RequireUserContext(req, req_info)\n  scope \"/accounts/:account_id\" {\n    guard ctx = LoadAccountContext(req, ctx, account_id)\n    route GET \"/todos\" -> TodoIndex(req, ctx)\n  }\n}\n";

    /// Two same-name guards nest: the second receives the outer `value`, the handler receives the inner.
    #[test]
    fn accum_same_name_guards_nest() {
        let ig = lower_igweb(ACCUM).unwrap();
        assert!(ig.contains("compute req_info = call_contract(\"ReqInfo\", req)"));
        assert!(ig.contains(
            "match call_contract(\"RequireUserContext\", req, req_info) { Ok { value } => match call_contract(\"LoadAccountContext\", req, value, capture(req.path, \"^/accounts/([^/]+)/todos$\", 1)) { Ok { value } => call_contract(\"TodoIndex\", req, value) Err { error } => error } Err { error } => error }"
        ), "got:\n{ig}");
    }

    /// Distinct guard names remain refused (only same-name accumulation is allowed).
    #[test]
    fn accum_distinct_names_refused() {
        let src = "app X entry Serve {\n  handlers H\n  guard user = RequireUser(req)\n  scope \"/a/:id\" {\n    guard account = LoadAccount(req, id)\n    route GET \"/x\" -> H(req, account)\n  }\n}\n";
        assert!(lower_igweb(src)
            .unwrap_err()
            .message
            .contains("distinct active `guard`"));
    }

    /// The first guard cannot reference the context name (no prior step) → unknown arg.
    #[test]
    fn accum_first_guard_cannot_use_ctx() {
        let src = "app X entry Serve {\n  handlers H\n  guard ctx = First(req, ctx)\n  route GET \"/x\" -> H(req, ctx)\n}\n";
        assert!(lower_igweb(src)
            .unwrap_err()
            .message
            .contains("unknown arg"));
    }

    /// Idempotency stays outermost over the whole accumulation chain.
    #[test]
    fn accum_idempotency_outermost() {
        let src = "app X entry Serve {\n  handlers H\n  guard ctx = First(req)\n  scope \"/a/:id\" {\n    guard ctx = Second(req, ctx, id)\n    route POST \"/x\" -> Make(req, ctx) requires idempotency\n  }\n}\n";
        let ig = lower_igweb(src).unwrap();
        assert!(ig.contains(
            "if req.idempotency_key == \"\" { Respond { status: 400, body: \"missing idempotency-key\" } } else { match call_contract(\"First\", req)"
        ), "got:\n{ig}");
    }

    /// Accumulation lowering is deterministic.
    #[test]
    fn accum_is_deterministic() {
        assert_eq!(lower_igweb(ACCUM).unwrap(), lower_igweb(ACCUM).unwrap());
    }

    // ---- LAB-IGNITER-WEB-PREFIX-GROUPED-LOWERING-P4: the route-depth wall is removed ----

    fn synth_routes(n: usize) -> String {
        let mut s = String::from("app X entry Serve {\n  handlers H\n");
        for i in 0..n {
            s.push_str(&format!("  route GET \"/r{i}/:id\" -> Handler{i}\n"));
        }
        s.push_str("}\n");
        s
    }

    /// The balanced route tree nests `O(log N)` deep, not `O(N)`. The old linear chain made the generated
    /// `.ig` ~N levels deep, which overflowed serde's recursion limit at machine LOAD (~116 routes, P2).
    /// Here 1000 routes lower to a shallow tree — measured by max leading-space indent (2 spaces/level).
    #[test]
    fn route_tree_depth_is_bounded_for_1000_routes() {
        let ig = lower_igweb(&synth_routes(1000)).expect("1000 routes must lower");
        let max_indent = ig
            .lines()
            .map(|l| l.len() - l.trim_start().len())
            .max()
            .unwrap_or(0);
        // O(log2(1000)) ≈ 10 levels ⇒ ~20–40 spaces; a linear chain would be ~2000. Bound well under the
        // ~128 serde recursion limit that caused the old wall.
        assert!(
            max_indent < 120,
            "route-tree nesting must be O(log N); got max indent {max_indent} spaces (≈{} levels)",
            max_indent / 2
        );
        // leaves still call the right static handlers (first, middle, last).
        assert!(ig
            .contains("call_contract(\"Handler0\", req, capture(req.path, \"^/r0/([^/]+)$\", 1))"));
        assert!(ig.contains(
            "call_contract(\"Handler999\", req, capture(req.path, \"^/r999/([^/]+)$\", 1))"
        ));
        // exactly one 405-bearing method chain per pattern is preserved.
        assert!(ig.contains("status: 405"));
    }

    /// Behavior-equivalence: authored-order shadowing (P18) survives the tree restructure. A static
    /// `/r/overdue` authored BEFORE the param `/r/:id` still wins for path `/r/overdue`; reversed order
    /// flips it — exactly as the old linear chain (the tree's left = authored-earlier is the tiebreaker).
    #[test]
    fn route_tree_preserves_authored_order_shadowing() {
        let static_first = "app X entry Serve {\n  handlers H\n  route GET \"/r/overdue\" -> Overdue\n  route GET \"/r/:id\" -> Show\n}\n";
        let ig = lower_igweb(static_first).unwrap();
        // the static-leaf prune (`^/r/overdue$`) is tested before the param leaf in output order.
        let i_overdue = ig.find("^/r/overdue$").expect("overdue leaf");
        let i_show = ig.find("^/r/([^/]+)$").expect("show leaf");
        assert!(
            i_overdue < i_show,
            "static authored first must appear/branch first"
        );

        let param_first = "app X entry Serve {\n  handlers H\n  route GET \"/r/:id\" -> Show\n  route GET \"/r/overdue\" -> Overdue\n}\n";
        let ig2 = lower_igweb(param_first).unwrap();
        let j_show = ig2.find("^/r/([^/]+)$").expect("show leaf");
        let j_overdue = ig2.find("^/r/overdue$").expect("overdue leaf");
        assert!(
            j_show < j_overdue,
            "param authored first must appear/branch first"
        );
    }
}
