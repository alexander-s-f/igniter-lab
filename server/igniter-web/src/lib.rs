//! `igniter-web` — lab home for the IgWeb package builder (LAB-IGNITER-WEB-CRATE-P8).
//!
//! Extracted from the P5/P7 test seam. `build_igweb_app` is the IgWeb packaging contract:
//!
//! ```text
//! explicit sources (.igweb + support .ig) + entry
//!   → lower_igweb (igniter_compiler)                 → generated .ig
//!   → IgniterMachine::load_program(..., entry)       → loaded capsule
//!   → Arc<dyn igniter_server::protocol::ServerApp + Send + Sync>   (the only thing the host sees)
//! ```
//!
//! This crate carries the compiler + machine dependency weight so `igniter-server` stays serde-only by
//! default. It owns NO route table, NO effect authority (`InvokeEffect` names a logical `target` only;
//! `target → EffectBridgeConfig` is host config), and NO serving loop / sockets. Not canon; lab-only.

use igniter_compiler::igweb::lower_igweb;
use igniter_machine::machine::IgniterMachine;
use igniter_server::protocol::{ServerApp, ServerDecision, ServerRequest, ServerResponse};
use serde_json::{json, Value};
use std::path::PathBuf;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Arc;

pub mod host_binding;
pub mod host_config;
#[cfg(feature = "machine")]
pub mod machine_runner;
#[cfg(feature = "machine")]
pub mod read_continuation;
#[cfg(feature = "machine")]
pub mod read_dispatch;
#[cfg(feature = "machine")]
pub mod read_materialize;
pub mod runner_diag;

static NEXT_BUILD_ID: AtomicUsize = AtomicUsize::new(0);

/// Explicit package inputs (the P6 v0 shape — paths + entry, never a manifest).
pub struct IgWebBuildInput {
    /// authored sources: support `.ig` modules + one (or more) `.igweb` route files.
    pub sources: Vec<PathBuf>,
    /// the route-entry contract name (e.g. "Serve").
    pub entry: String,
}

/// Core async IgWeb dispatch (P2): holds a loaded `IgniterMachine` and dispatches async without
/// any `block_on`. The sync compatibility adapter `IgWebServerApp` wraps this via `Arc`.
pub struct IgWebLoadedApp {
    machine: IgniterMachine,
    entry: String,
}

impl IgWebLoadedApp {
    /// Dispatch the entry contract through the loaded machine. Pure async — never calls `block_on`.
    /// Safe to await inside a tokio runtime without nesting hazards.
    pub async fn dispatch(&self, req: ServerRequest) -> ServerDecision {
        let input = build_request_input(&req);
        match self.machine.dispatch(&self.entry, input).await {
            Ok(val) => map_decision(&val, req.correlation_id),
            Err(e) => ServerDecision::Respond {
                response: ServerResponse::json(500, json!({ "error": format!("{e:?}") })),
            },
        }
    }

    /// Dispatch with staged-read support (LAB-IGNITER-WEB-READTHEN-DISPATCH-P11; sequential/nested
    /// `ReadThen` LAB-TODOAPP-API-ACCOUNT-EXISTENCE-P38).
    ///
    /// If a contract returns `ReadThen { plan, then, carry }` the host executes the read through
    /// `read_host`, then re-dispatches `then` with `{ req, rows_json, carry }`. The continuation may
    /// itself return another `ReadThen` (e.g. "prove the account exists, then list its todos") — the host
    /// loops, executing each staged read in turn, until a non-`ReadThen` decision is reached. `carry` is
    /// an OPAQUE string the host threads from a `ReadThen` to its continuation (e.g. a route capture the
    /// continuation needs to build the next plan); the host never interprets it.
    ///
    /// The loop is **bounded** by `MAX_READ_HOPS` so a buggy continuation chain can never spin forever:
    /// exceeding the bound fails closed to a host 500. Never calls `block_on` — all awaits are explicit.
    #[cfg(feature = "machine")]
    pub async fn dispatch_with_read(
        &self,
        req: ServerRequest,
        read_host: &read_dispatch::StagedReadHost,
    ) -> ServerDecision {
        /// Upper bound on chained staged reads per request (generic safety rail, not a product limit).
        const MAX_READ_HOPS: usize = 8;

        // First dispatch is the route entry; subsequent ones are named continuations.
        let mut entry = self.entry.clone();
        let mut input = build_request_input(&req);

        for _hop in 0..MAX_READ_HOPS {
            let raw = match self.machine.dispatch(&entry, input).await {
                Ok(v) => v,
                Err(e) => {
                    return ServerDecision::Respond {
                        response: ServerResponse::json(500, json!({ "error": format!("{e:?}") })),
                    }
                }
            };

            // Intercept ReadThen before map_decision (which is synchronous). Anything else is terminal.
            let (plan, then, carry) = match variant_of(&raw) {
                Some((tag, fields)) if tag == "ReadThen" => {
                    let plan = fields.get("plan").cloned().unwrap_or(Value::Null);
                    let then = fields
                        .get("then")
                        .and_then(|v| v.as_str())
                        .unwrap_or("")
                        .to_string();
                    let carry = fields
                        .get("carry")
                        .and_then(|v| v.as_str())
                        .unwrap_or("")
                        .to_string();
                    (plan, then, carry)
                }
                _ => return map_decision(&raw, req.correlation_id),
            };

            // Choose the row crossing from the continuation's COMPILED inputs (P7): the legacy stringly
            // `rows_json : String`, or the typed `rows : Collection[<AppRow>]` (+ `meta : DatasetMeta`).
            // Metadata read only — never a parse of authored `.ig` source.
            match read_continuation::classify_continuation(&self.machine, &then) {
                read_continuation::ReadContinuationShape::LegacyRowsJson => {
                    match read_host.execute(&plan, &req).await {
                        read_dispatch::StagedReadResult::Rows(rows_json) => {
                            // Re-dispatch: original req + this read's rows (as a string) + the carried value.
                            input = json!({
                                "req": build_request_input(&req)["req"],
                                "rows_json": rows_json,
                                "carry": carry,
                            });
                            entry = then;
                            // loop: the continuation may emit another ReadThen (sequential staged reads).
                        }
                        read_dispatch::StagedReadResult::Denied(reason) => {
                            return respond_json(403, json!({ "error": reason }))
                        }
                        read_dispatch::StagedReadResult::HostError(msg) => {
                            return respond_json(503, json!({ "error": msg }))
                        }
                    }
                }
                read_continuation::ReadContinuationShape::TypedRows { row_type, .. } => {
                    // Derive the projection spec from the host read policy + this plan (schema authority).
                    let spec = match read_host.projection_spec_for(&plan) {
                        Some(s) => s,
                        None => {
                            return respond_json(
                                500,
                                json!({ "error": { "code": "typed_read_unconfigured",
                                    "message": "typed continuation requires a host read policy (none attached)" }}),
                            )
                        }
                    };
                    // RECONCILE structural drift before the read — but ONLY for a source the host actually
                    // types. An unknown/denied source is the executor's 403 to make (in `execute_typed`),
                    // not a drift false-positive from default-`Text` kinds.
                    if read_host.source_allowlisted(&plan) {
                        let approw = match read_continuation::app_row_shape(
                            &self.machine,
                            &row_type,
                        ) {
                            Ok(a) => a,
                            Err(e) => {
                                return respond_json(
                                    500,
                                    json!({ "error": { "code": "projection_schema_unrecoverable", "message": e }}),
                                )
                            }
                        };
                        if let Err(drift) = read_materialize::reconcile_projection(&spec, &approw) {
                            // Host-schema ⇎ app-row-type drift — a deploy fault discovered at first dispatch
                            // (NOT boot: ReadThen plans are built dynamically, P3 §3). Fail closed, no dispatch.
                            return respond_json(
                                500,
                                json!({ "error": { "code": "projection_schema_drift", "message": drift }}),
                            );
                        }
                    }
                    match read_host.execute_typed(&plan, &req, &spec).await {
                        read_dispatch::TypedReadResult::Rows { rows, meta } => {
                            // Re-dispatch: original req + typed rows (records) + DatasetMeta + carry.
                            input = json!({
                                "req": build_request_input(&req)["req"],
                                "rows": rows,
                                "meta": meta,
                                "carry": carry,
                            });
                            entry = then;
                        }
                        read_dispatch::TypedReadResult::SchemaMismatch(msg) => {
                            // Host fetched rows it could not honor as the typed projection → gateway fault.
                            return respond_json(
                                502,
                                json!({ "error": { "code": "projection_row_mismatch", "message": msg }}),
                            );
                        }
                        read_dispatch::TypedReadResult::Denied(reason) => {
                            return respond_json(403, json!({ "error": reason }))
                        }
                        read_dispatch::TypedReadResult::HostError(msg) => {
                            return respond_json(503, json!({ "error": msg }))
                        }
                    }
                }
                read_continuation::ReadContinuationShape::Invalid(reason) => {
                    return respond_json(
                        500,
                        json!({ "error": { "code": "invalid_read_continuation", "message": reason }}),
                    );
                }
            }
        }

        // Exceeded the staged-read bound — a continuation chain that never terminates. Fail closed.
        ServerDecision::Respond {
            response: ServerResponse::json(
                500,
                json!({ "error": "staged read exceeded maximum hops" }),
            ),
        }
    }
}

/// Structured, developer-facing build failure (never a panic).
#[derive(Debug)]
pub enum IgWebBuildError {
    Io(String),
    /// `.igweb` lowering failure — carries the `.igweb` source line.
    Lower {
        line: usize,
        message: String,
    },
    /// generated/support `.ig` compile/load failure.
    Load(String),
}

/// Lower and load an IgWeb app from explicit authored paths. Returns `IgWebLoadedApp` — the core
/// async dispatch unit. Does NOT create a tokio runtime; safe to call before any runtime exists.
pub fn build_igweb_loaded_app(
    input: IgWebBuildInput,
) -> Result<Arc<IgWebLoadedApp>, IgWebBuildError> {
    let build_id = NEXT_BUILD_ID.fetch_add(1, Ordering::Relaxed);
    let build_dir = std::env::temp_dir().join(format!(
        "igweb_build_{}_{}_{}",
        std::process::id(),
        input.entry,
        build_id
    ));
    std::fs::create_dir_all(&build_dir).map_err(|e| IgWebBuildError::Io(e.to_string()))?;

    let mut ig_paths: Vec<String> = Vec::new();
    for (idx, src) in input.sources.iter().enumerate() {
        if src.extension().and_then(|e| e.to_str()) == Some("igweb") {
            let text =
                std::fs::read_to_string(src).map_err(|e| IgWebBuildError::Io(e.to_string()))?;
            let generated = lower_igweb(&text).map_err(|e| IgWebBuildError::Lower {
                line: e.line,
                message: e.message,
            })?;
            let stem = src.file_stem().and_then(|s| s.to_str()).unwrap_or("routes");
            let gen_path = build_dir.join(format!("{idx}_{stem}.generated.ig"));
            std::fs::write(&gen_path, &generated)
                .map_err(|e| IgWebBuildError::Io(e.to_string()))?;
            ig_paths.push(gen_path.to_string_lossy().to_string());
        } else {
            ig_paths.push(src.to_string_lossy().to_string());
        }
    }

    // P10: inject the shared IgWeb prelude (Request/Decision) so apps no longer author `web_types.ig`.
    let prelude_path = build_dir.join("igweb_prelude.ig");
    std::fs::write(&prelude_path, igniter_compiler::igweb::PRELUDE_SOURCE)
        .map_err(|e| IgWebBuildError::Io(e.to_string()))?;
    ig_paths.push(prelude_path.to_string_lossy().to_string());

    let machine = IgniterMachine::new(None, "in_memory")
        .map_err(|e| IgWebBuildError::Load(format!("{e:?}")))?;
    machine
        .load_program(&ig_paths, &input.entry)
        .map_err(|e| IgWebBuildError::Load(format!("{e:?}")))?;

    Ok(Arc::new(IgWebLoadedApp {
        machine,
        entry: input.entry,
    }))
}

/// Build an IgWeb app from explicit authored paths. Returns an erased `ServerApp` (sync compat
/// adapter wrapping `IgWebLoadedApp`). Use `build_igweb_loaded_app` when an async runner is needed.
pub fn build_igweb_app(
    input: IgWebBuildInput,
) -> Result<Arc<dyn ServerApp + Send + Sync>, IgWebBuildError> {
    let loaded = build_igweb_loaded_app(input)?;
    let rt = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .map_err(|e| IgWebBuildError::Io(e.to_string()))?;
    Ok(Arc::new(IgWebServerApp { inner: loaded, rt }))
}

/// Sync compatibility adapter wrapping `IgWebLoadedApp`. Implements `ServerApp` by running the
/// async dispatch on a private current-thread runtime. Safe only when called from outside any
/// tokio context — the async runner (`machine_runner`) calls `IgWebLoadedApp::dispatch` directly.
struct IgWebServerApp {
    inner: Arc<IgWebLoadedApp>,
    rt: tokio::runtime::Runtime,
}

impl ServerApp for IgWebServerApp {
    fn call(&self, req: ServerRequest) -> ServerDecision {
        self.rt.block_on(self.inner.dispatch(req))
    }
}

/// Host-minted Todo surrogate id recipe (LAB-TODOAPP-API-HOST-SURROGATE-ID-P36).
///
/// A deterministic, replay-safe, opaque digest of the request's *identity* — `(method, path,
/// idempotency_key)` — used by `.ig` to mint a Todo resource id that is DECOUPLED from the
/// idempotency key. The id-minting recipe is HOST policy (it owns request/effect identity), so it
/// lives here rather than in generic machine code or in `.ig` (which has no hash builtin); `.ig`
/// only consumes the crossed `req.surrogate_id` and adds the product `"todo_"` prefix.
///
/// Properties (all required by the card): deterministic across replay (pure function, no clock /
/// randomness); leaks no body values or secrets (the title and any bearer token are NOT inputs, and
/// blake3 is one-way so the idempotency key is not recoverable from the id); namespaced — the same
/// idempotency key on a different account/route mints a different id (the account scope and resource
/// live in `path`). An empty idempotency key yields an empty surrogate (a keyless mutating request is
/// already refused by the route-level idempotency guard before it reaches intent construction).
pub fn surrogate_id(method: &str, path: &str, idempotency_key: &str) -> String {
    if idempotency_key.is_empty() {
        return String::new();
    }
    // Unit-separator (0x1f) framing so distinct field tuples can never collide via concatenation.
    let mut h = blake3::Hasher::new();
    h.update(method.as_bytes());
    h.update(&[0x1f]);
    h.update(path.as_bytes());
    h.update(&[0x1f]);
    h.update(idempotency_key.as_bytes());
    // 128 bits (32 hex chars) — ample collision resistance for a resource id, half the full digest.
    h.finalize().to_hex()[..32].to_string()
}

/// Build the `{ "req": { ... } }` input value from a `ServerRequest`. Shared between the async
/// dispatch path and the sync compat adapter — one source of truth for the input shape.
fn build_request_input(req: &ServerRequest) -> Value {
    // `req.body` is a parsed JSON Value. The prelude `Request.body` is a String, so we cross it as text:
    // a JSON-string body (e.g. `"Buy milk"`) crosses as its INNER string (`Buy milk`, not re-quoted);
    // null/absent → ""; any other shape (object/number) crosses as its compact JSON text.
    //
    // `body_kind` (LAB-TODOAPP-API-BODY-CONTRACT-HARDENING-P18) is the host-computed JSON SHAPE of the
    // body — the only place that distinction survives (`host::parse_request` collapses malformed JSON to
    // `Null`, so malformed and absent both read as "empty" here). `.ig` cannot tell a string body from
    // compact object text once `body` is a String, so a route that requires a string body guards on this
    // signal instead of parsing JSON in `.ig`. Shapes: non-empty string → "string"; empty string / null /
    // absent / malformed → "empty"; otherwise the JSON shape name.
    let (body, body_kind) = match &req.body {
        Value::String(s) if !s.is_empty() => (s.clone(), "string"),
        Value::String(_) => (String::new(), "empty"),
        Value::Null => (String::new(), "empty"),
        Value::Object(_) => (req.body.to_string(), "object"),
        Value::Array(_) => (req.body.to_string(), "array"),
        Value::Number(_) => (req.body.to_string(), "number"),
        Value::Bool(_) => (req.body.to_string(), "bool"),
    };
    // `surrogate_id` (LAB-TODOAPP-API-HOST-SURROGATE-ID-P36) is the host-minted opaque resource-id
    // digest crossed to `.ig` — the SAME host-computed-signal pattern as `body_kind`. `.ig` uses it as
    // the Todo business key (prefixed `todo_`), so the resource id is decoupled from the idempotency
    // key while receipts/dedup keep keying on the idempotency key itself. Empty for keyless requests.
    let idem = req.idempotency_key.clone().unwrap_or_default();
    let surrogate = surrogate_id(&req.method, &req.path, &idem);
    // `body_json` (LAB-TODOAPP-API-CREATE-OBJECT-BODY-P35) is GENERIC transport parsing: a JSON OBJECT
    // body crosses as a `Map[String, Unknown]` so `.ig` can read typed fields via `map_get_string`. Any
    // non-object body crosses as an explicit EMPTY map — the shape distinction stays in `body_kind`, and
    // a handler keys on `body_kind` before reading fields. The host parses transport ONLY; it never
    // interprets a field's product meaning (e.g. `title`) — that authority stays in `.ig`.
    let body_json = match &req.body {
        Value::Object(_) => req.body.clone(),
        _ => json!({}),
    };
    // `query` (LAB-TODOAPP-API-PAGINATION-KEYSET-P47): parsed `?k=v` params crossed as a generic
    // `Map[String, Unknown]` (string values), exactly like `body_json`. The app reads typed keys via
    // `map_get_string` (e.g. the keyset `after` cursor); the host parses transport only, no product meaning.
    let query: serde_json::Map<String, Value> = req
        .query
        .iter()
        .map(|(k, v)| (k.clone(), Value::String(v.clone())))
        .collect();
    json!({ "req": {
        "method": req.method,
        "path": req.path,
        "body": body,
        "body_kind": body_kind,
        "correlation_id": req.correlation_id.clone().unwrap_or_default(),
        "idempotency_key": idem,
        "surrogate_id": surrogate,
        "body_json": body_json,
        "query": Value::Object(query),
    }})
}

/// A terminal JSON `Respond` decision at `status` — the host-owned read/error envelope used by the staged
/// read contour (P7). Keeps the `dispatch_with_read` branches terse and uniform.
#[cfg(feature = "machine")]
fn respond_json(status: u16, body: Value) -> ServerDecision {
    ServerDecision::Respond {
        response: ServerResponse::json(status, body),
    }
}

/// The VM encodes a variant value as an internally-tagged object:
/// `{ "__arm": "Respond", "__variant": "Decision", <fields...> }`.
fn variant_of(v: &Value) -> Option<(String, Value)> {
    let obj = v.as_object()?;
    for key in ["__arm", "kind", "variant", "tag"] {
        if let Some(t) = obj.get(key).and_then(|x| x.as_str()) {
            return Some((t.to_string(), v.clone()));
        }
    }
    if obj.len() == 1 {
        let (k, inner) = obj.iter().next().unwrap();
        return Some((k.clone(), inner.clone()));
    }
    None
}

fn map_decision(decision: &Value, correlation_id: Option<String>) -> ServerDecision {
    let (tag, fields) = match variant_of(decision) {
        Some(t) => t,
        None => {
            return ServerDecision::Respond {
                response: ServerResponse::json(
                    500,
                    json!({ "error": "unmapped decision", "raw": decision }),
                ),
            }
        }
    };
    let get_str = |k: &str| {
        fields
            .get(k)
            .and_then(|x| x.as_str())
            .unwrap_or("")
            .to_string()
    };
    let get_i = |k: &str| fields.get(k).and_then(|x| x.as_i64()).unwrap_or(0);
    match tag.as_str() {
        "Respond" => ServerDecision::Respond {
            response: ServerResponse::json(
                get_i("status") as u16,
                json!({ "body": get_str("body") }),
            ),
        },
        // LAB-TODOAPP-VIEW-MANIFEST-P2: the typed `view` descriptor IS the JSON body root — no string
        // wrapping, no double-parse. The VM-encoded record carries internal `__arm`/`__variant` keys
        // only on variant values; the plain `View`/`ViewItem` records serialize as clean objects.
        "RespondView" => ServerDecision::Respond {
            response: ServerResponse::json(
                get_i("status") as u16,
                fields.get("view").cloned().unwrap_or(Value::Null),
            ),
        },
        // LAB-TODOAPP-API-ERROR-ENVELOPE-IMPL-P43: app-authored typed error. The `error` field is a plain
        // `ApiError` record (no `__arm`/`__variant` discriminants), so the VM serialized it to a clean
        // `{"code","message"}` object; wrap it as `{"error": …}` — the app-side error envelope. Host-owned
        // error shapes (ingress/read/effect) are produced elsewhere and are unchanged.
        "RespondError" => ServerDecision::Respond {
            response: ServerResponse::json(
                get_i("status") as u16,
                json!({ "error": fields.get("error").cloned().unwrap_or(Value::Null) }),
            ),
        },
        // LAB-IGNITER-WEB-STRUCTURED-EFFECT-INPUT-P7: `input` is a typed `.ig` record (prelude field
        // `input : Unknown`, the open structured-payload position). The VM serialized it to a clean JSON
        // object; pass it through verbatim as `serde_json::Value` — no string wrap, no double-parse — the
        // SAME record-pass-through the `RespondView` arm uses for `view`. Plain records carry no
        // `__arm`/`__variant` discriminants, so the host receives the structured write intent directly.
        "InvokeEffect" => ServerDecision::InvokeEffect {
            target: get_str("target"),
            input: fields.get("input").cloned().unwrap_or(Value::Null),
            correlation_id,
            idempotency_key: {
                let k = get_str("idempotency_key");
                if k.is_empty() {
                    None
                } else {
                    Some(k)
                }
            },
        },
        // LAB-IGNITER-WEB-RENDER-DECISION-P16: the handler hands a ViewArtifact JSON STRING; igniter-web
        // projects it to escaped HTML (P3 renderer) and ships it as verbatim bytes through the P15 raw
        // seam. The renderer validates structure + escapes; bad/unsafe artifacts fail closed to a JSON 500
        // carrying only the error kind/message (never the raw artifact body). igniter-server stays
        // renderer-free — the dependency lives here.
        "Render" => render_to_decision(get_i("status") as u16, &get_str("artifact_json")),
        // LAB-IGNITER-WEB-VIEWARTIFACT-AUTHORING-P19: the handler authored a typed `ViewArtifact` RECORD
        // in `.ig` (no JSON string); the VM serialized it to a clean nested JSON `view` value. Serialize
        // it and feed the SAME render path as `Render`. `ViewArtifact`/`HtmlNode` are records, so the
        // value carries no `__arm`/`__variant` discriminants — it matches the renderer's kind-dispatched
        // schema directly.
        "RenderView" => render_to_decision(
            get_i("status") as u16,
            &fields
                .get("view")
                .cloned()
                .unwrap_or(Value::Null)
                .to_string(),
        ),
        other => ServerDecision::Respond {
            response: ServerResponse::json(
                500,
                json!({ "error": format!("unknown decision tag: {other}"), "raw": decision }),
            ),
        },
    }
}

/// Project a ViewArtifact JSON string to HTML and wrap it as a `Respond`. Shared by the `Render`
/// (P16, JSON-string source) and `RenderView` (P19, typed-record source) decision arms: success → a raw
/// `text/html` response (P15 seam); failure → a JSON 500 carrying only the error kind/message (no artifact
/// body leak). igniter-server stays renderer-free — the dependency lives here.
fn render_to_decision(status: u16, artifact_json: &str) -> ServerDecision {
    match igniter_render_html::render_html(artifact_json) {
        Ok(html) => ServerDecision::Respond {
            response: ServerResponse::raw(status, html.into_bytes(), "text/html; charset=utf-8"),
        },
        Err(e) => ServerDecision::Respond {
            response: ServerResponse::json(
                500,
                json!({ "error": "render failed", "kind": render_error_kind(&e), "message": e.to_string() }),
            ),
        },
    }
}

/// Stable kind string for a render failure (the `message` carries detail; neither leaks the artifact body).
fn render_error_kind(e: &igniter_render_html::RenderHtmlError) -> &'static str {
    use igniter_render_html::RenderHtmlError::*;
    match e {
        InvalidArtifact(_) => "invalid_artifact",
        UnsupportedNode(_) => "unsupported_node",
        UnsafeUrl(_) => "unsafe_url",
        Render(_) => "render",
    }
}

/// Generic lab runner (LAB-IGNITER-WEB-RUNNER-P12): a `config.ru`-analogue. Reads a tiny `igweb.toml`
/// from an app directory, builds the IgWeb app via `build_igweb_app`, and composes P8 middleware from
/// the manifest. The server still owns transport/loop/reload; the manifest names only app entry/sources
/// + host policy (no routes, bind, secrets, or effect identity). Lab v0 — NOT a stable CLI/canon.
pub mod runner {
    use super::{build_igweb_app, IgWebBuildError, IgWebBuildInput};
    use igniter_server::middleware::{AuthTokenApp, BodyLimitApp, TraceApp};
    use igniter_server::protocol::ServerApp;
    use std::net::SocketAddr;
    use std::path::{Path, PathBuf};
    use std::sync::Arc;

    /// Parsed `igweb.toml`. `[app]` is author-owned; `[server]`/`[middleware]` are host policy.
    #[derive(Debug, Clone, Default)]
    pub struct IgwebManifest {
        pub entry: String,
        pub sources: Option<Vec<String>>,
        pub server_mode: Option<String>,
        pub max_requests: Option<usize>,
        pub trace: bool,
        pub body_limit_bytes: Option<usize>,
        pub auth_token_env: Option<String>,
    }

    #[derive(Debug)]
    pub enum RunnerError {
        Io(String),
        /// malformed/forbidden manifest content.
        Manifest(String),
        /// malformed/forbidden runner CLI argument.
        Cli(String),
        Build(IgWebBuildError),
    }

    impl std::fmt::Display for RunnerError {
        fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
            match self {
                RunnerError::Io(m) => write!(f, "igweb runner io error: {m}"),
                RunnerError::Manifest(m) => write!(f, "igweb.toml error: {m}"),
                RunnerError::Cli(m) => write!(f, "igweb-serve argument error: {m}"),
                RunnerError::Build(e) => write!(f, "igweb build error: {e:?}"),
            }
        }
    }
    impl std::error::Error for RunnerError {}

    #[derive(Debug, Clone, PartialEq, Eq)]
    pub struct RunnerCliOptions {
        pub app_dir: PathBuf,
        pub addr: SocketAddr,
        pub max_requests: Option<usize>,
        /// Path to `host.toml`; presence enables the async machine-mode runner.
        pub host_config_path: Option<PathBuf>,
    }

    #[derive(Debug, Clone, PartialEq, Eq)]
    pub struct RunnerCheckOptions {
        pub app_dir: PathBuf,
    }

    #[derive(Debug, Clone, PartialEq, Eq)]
    pub enum RunnerCliCommand {
        Help(String),
        Run(RunnerCliOptions),
        Check(RunnerCheckOptions),
    }

    pub const DEFAULT_ADDR: &str = "127.0.0.1:0";

    pub fn usage() -> &'static str {
        "usage: igweb-serve run [--addr 127.0.0.1:PORT] [--max-requests N] [--host-config PATH] <app_dir>\n\
         usage: igweb-serve [--addr 127.0.0.1:PORT] [--max-requests N] [--host-config PATH] <app_dir>\n\
         usage: igweb-serve check <app_dir>\n\
         \n\
         Commands:\n\
           run     build the app and serve a bounded loopback listener\n\
           check   build the app without opening a socket\n\
         \n\
         Options for run:\n\
           --addr HOST:PORT       loopback-only bind address (default 127.0.0.1:0)\n\
           --max-requests N       override [server].max_requests for this run\n\
           --host-config PATH     host.toml for machine-mode runner (resolves env vars before bind)\n\
         \n\
         Lab IgWeb runner. Loopback only; app routing lives in .igweb; effect binding stays host-side.\n\
         --host-config requires --features machine. Not a stable CLI surface."
    }

    pub fn parse_cli_args<I, S>(args: I) -> Result<RunnerCliCommand, RunnerError>
    where
        I: IntoIterator<Item = S>,
        S: Into<String>,
    {
        let args: Vec<String> = args.into_iter().map(Into::into).collect();
        match args.first().map(String::as_str) {
            Some("-h" | "--help") => return Ok(RunnerCliCommand::Help(usage().to_string())),
            Some("check") => return parse_check_args(args.into_iter().skip(1)),
            Some("run") => return parse_run_args(args.into_iter().skip(1)),
            _ => {}
        }
        parse_run_args(args)
    }

    fn parse_check_args<I>(args: I) -> Result<RunnerCliCommand, RunnerError>
    where
        I: IntoIterator<Item = String>,
    {
        let mut iter = args.into_iter();
        let app_dir = iter
            .next()
            .ok_or_else(|| RunnerError::Cli("check requires <app_dir>".into()))?;
        if app_dir == "-h" || app_dir == "--help" {
            return Ok(RunnerCliCommand::Help(usage().to_string()));
        }
        if let Some(extra) = iter.next() {
            return Err(RunnerError::Cli(format!(
                "unexpected extra argument `{extra}`"
            )));
        }
        Ok(RunnerCliCommand::Check(RunnerCheckOptions {
            app_dir: PathBuf::from(app_dir),
        }))
    }

    fn parse_run_args<I>(args: I) -> Result<RunnerCliCommand, RunnerError>
    where
        I: IntoIterator<Item = String>,
    {
        let mut addr = parse_loopback_addr(DEFAULT_ADDR)?;
        let mut max_requests = None;
        let mut app_dir = None;
        let mut host_config_path = None;
        let mut iter = args.into_iter();
        while let Some(arg) = iter.next() {
            match arg.as_str() {
                "-h" | "--help" => return Ok(RunnerCliCommand::Help(usage().to_string())),
                "--addr" => {
                    let value = iter
                        .next()
                        .ok_or_else(|| RunnerError::Cli("--addr requires a value".into()))?;
                    addr = parse_loopback_addr(&value)?;
                }
                "--max-requests" => {
                    let value = iter.next().ok_or_else(|| {
                        RunnerError::Cli("--max-requests requires a value".into())
                    })?;
                    let parsed = value.parse::<usize>().map_err(|_| {
                        RunnerError::Cli(format!(
                            "--max-requests expects an integer, got `{value}`"
                        ))
                    })?;
                    if parsed == 0 {
                        return Err(RunnerError::Cli(
                            "--max-requests must be greater than zero".into(),
                        ));
                    }
                    max_requests = Some(parsed);
                }
                "--host-config" => {
                    let value = iter
                        .next()
                        .ok_or_else(|| RunnerError::Cli("--host-config requires a value".into()))?;
                    host_config_path = Some(PathBuf::from(value));
                }
                value if value.starts_with('-') => {
                    return Err(RunnerError::Cli(format!("unknown option `{value}`")))
                }
                value => {
                    if app_dir.is_some() {
                        return Err(RunnerError::Cli(format!(
                            "unexpected extra app_dir `{value}`"
                        )));
                    }
                    app_dir = Some(PathBuf::from(value));
                }
            }
        }
        let app_dir = app_dir.ok_or_else(|| RunnerError::Cli("missing <app_dir>".into()))?;
        Ok(RunnerCliCommand::Run(RunnerCliOptions {
            app_dir,
            addr,
            max_requests,
            host_config_path,
        }))
    }

    fn parse_loopback_addr(raw: &str) -> Result<SocketAddr, RunnerError> {
        let addr = raw
            .parse::<SocketAddr>()
            .map_err(|_| RunnerError::Cli(format!("--addr expects HOST:PORT, got `{raw}`")))?;
        if !addr.ip().is_loopback() {
            return Err(RunnerError::Cli(format!(
                "--addr must be loopback-only, got `{raw}`"
            )));
        }
        Ok(addr)
    }

    /// Hand-rolled tiny `igweb.toml` parse (no toml crate; mirrors `project.rs::parse_source_roots_toml`).
    /// Supports only the documented v0 subset; unsupported sections/keys are rejected with a clear error.
    pub fn parse_manifest(text: &str) -> Result<IgwebManifest, RunnerError> {
        let mut m = IgwebManifest::default();
        let mut section = String::new();
        for raw in text.lines() {
            let line = raw.trim();
            if line.is_empty() || line.starts_with('#') {
                continue;
            }
            if let Some(s) = line.strip_prefix('[').and_then(|s| s.strip_suffix(']')) {
                section = s.trim().to_string();
                if section == "effects" {
                    return Err(RunnerError::Manifest("[effects] is unsupported in v0 (effect target binding is host-side, not the manifest)".into()));
                }
                continue;
            }
            let (key, val) = line.split_once('=').ok_or_else(|| {
                RunnerError::Manifest(format!("expected `key = value`, got `{line}`"))
            })?;
            let key = key.trim();
            let val = val.trim();
            match (section.as_str(), key) {
                ("app", "entry") => m.entry = parse_str(val)?,
                ("app", "sources") => m.sources = Some(parse_str_array(val)?),
                ("server", "mode") => m.server_mode = Some(parse_str(val)?),
                ("server", "max_requests") => m.max_requests = Some(parse_int(val)?),
                ("middleware", "trace") => m.trace = parse_bool(val)?,
                ("middleware", "body_limit_bytes") => m.body_limit_bytes = Some(parse_int(val)?),
                ("middleware", "auth_token_env") => m.auth_token_env = Some(parse_str(val)?),
                ("middleware", "auth_token") => {
                    return Err(RunnerError::Manifest("inline `auth_token` is forbidden — use `auth_token_env = \"VAR\"` (secret read from the environment)".into()))
                }
                (sec, k) => return Err(RunnerError::Manifest(format!("unknown key `{k}` in section `[{sec}]`"))),
            }
        }
        if m.entry.is_empty() {
            return Err(RunnerError::Manifest(
                "missing required `[app] entry`".into(),
            ));
        }
        if let Some(mode) = &m.server_mode {
            if mode != "loopback" {
                return Err(RunnerError::Manifest(format!(
                    "[server] mode `{mode}` unsupported in v0 (only `loopback`)"
                )));
            }
        }
        Ok(m)
    }

    fn parse_str(v: &str) -> Result<String, RunnerError> {
        let v = v.trim();
        if v.len() >= 2 && v.starts_with('"') && v.ends_with('"') {
            Ok(v[1..v.len() - 1].to_string())
        } else {
            Err(RunnerError::Manifest(format!(
                "expected a quoted string, got `{v}`"
            )))
        }
    }
    fn parse_str_array(v: &str) -> Result<Vec<String>, RunnerError> {
        let inner = v
            .trim()
            .strip_prefix('[')
            .and_then(|s| s.strip_suffix(']'))
            .ok_or_else(|| RunnerError::Manifest(format!("expected `[...]` array, got `{v}`")))?;
        inner
            .split(',')
            .map(|s| s.trim())
            .filter(|s| !s.is_empty())
            .map(parse_str)
            .collect()
    }
    fn parse_bool(v: &str) -> Result<bool, RunnerError> {
        match v.trim() {
            "true" => Ok(true),
            "false" => Ok(false),
            other => Err(RunnerError::Manifest(format!(
                "expected true/false, got `{other}`"
            ))),
        }
    }
    fn parse_int(v: &str) -> Result<usize, RunnerError> {
        v.trim()
            .parse()
            .map_err(|_| RunnerError::Manifest(format!("expected an integer, got `{}`", v.trim())))
    }

    /// Load `<app_dir>/igweb.toml`.
    pub fn load_manifest(app_dir: &Path) -> Result<IgwebManifest, RunnerError> {
        let path = app_dir.join("igweb.toml");
        let text = std::fs::read_to_string(&path)
            .map_err(|e| RunnerError::Io(format!("{}: {e}", path.display())))?;
        parse_manifest(&text)
    }

    /// Resolve sources relative to the app dir: explicit `[app] sources`, else all `*.ig` + `*.igweb`
    /// directly in the dir, sorted deterministically.
    pub fn resolve_sources(
        app_dir: &Path,
        manifest: &IgwebManifest,
    ) -> Result<Vec<PathBuf>, RunnerError> {
        if let Some(list) = &manifest.sources {
            return Ok(list.iter().map(|s| app_dir.join(s)).collect());
        }
        let mut out = Vec::new();
        for entry in std::fs::read_dir(app_dir).map_err(|e| RunnerError::Io(e.to_string()))? {
            let p = entry.map_err(|e| RunnerError::Io(e.to_string()))?.path();
            if p.is_file() {
                match p.extension().and_then(|e| e.to_str()) {
                    Some("ig") | Some("igweb") => out.push(p),
                    _ => {}
                }
            }
        }
        out.sort();
        if out.is_empty() {
            return Err(RunnerError::Manifest(format!(
                "no `.ig`/`.igweb` sources found in {}",
                app_dir.display()
            )));
        }
        Ok(out)
    }

    /// Compose the P8 wrapper stack from the manifest: `BodyLimit -> Auth -> Trace -> app` (only the
    /// configured layers). Auth token is read from `auth_token_env` (env var), never from the manifest.
    fn compose(
        mut app: Arc<dyn ServerApp + Send + Sync>,
        manifest: &IgwebManifest,
    ) -> Arc<dyn ServerApp + Send + Sync> {
        if manifest.trace {
            app = Arc::new(TraceApp::new(app));
        }
        if let Some(env_name) = &manifest.auth_token_env {
            let token = std::env::var(env_name).unwrap_or_default();
            app = Arc::new(AuthTokenApp::new(app, token));
        }
        if let Some(n) = manifest.body_limit_bytes {
            app = Arc::new(BodyLimitApp::new(app, n));
        }
        app
    }

    /// The runner primitive: load the manifest, build the IgWeb app, compose middleware. Returns the
    /// composed (erased) app + the manifest. The server host (loop/listener/reload) is the caller's.
    pub fn build_app_from_dir(
        app_dir: &Path,
    ) -> Result<(Arc<dyn ServerApp + Send + Sync>, IgwebManifest), RunnerError> {
        let manifest = load_manifest(app_dir)?;
        let sources = resolve_sources(app_dir, &manifest)?;
        let built = build_igweb_app(IgWebBuildInput {
            sources,
            entry: manifest.entry.clone(),
        })
        .map_err(RunnerError::Build)?;
        Ok((compose(built, &manifest), manifest))
    }

    /// Async-runner variant: load and lower the app, return `IgWebLoadedApp` directly (no middleware,
    /// no sync runtime). For use with `machine_runner::serve_once_loaded` / `serve_loop_loaded`.
    pub fn build_loaded_app_from_dir(
        app_dir: &Path,
    ) -> Result<(Arc<crate::IgWebLoadedApp>, IgwebManifest), RunnerError> {
        let manifest = load_manifest(app_dir)?;
        let sources = resolve_sources(app_dir, &manifest)?;
        let loaded = crate::build_igweb_loaded_app(IgWebBuildInput {
            sources,
            entry: manifest.entry.clone(),
        })
        .map_err(RunnerError::Build)?;
        Ok((loaded, manifest))
    }

    #[derive(Debug, Clone, PartialEq, Eq)]
    pub struct RunnerCheckReport {
        pub entry: String,
        pub source_count: usize,
    }

    /// Dry-build an app directory without opening a socket or composing runtime loop state.
    pub fn check_app_dir(app_dir: &Path) -> Result<RunnerCheckReport, RunnerError> {
        let manifest = load_manifest(app_dir)?;
        let sources = resolve_sources(app_dir, &manifest)?;
        let source_count = sources.len();
        build_igweb_app(IgWebBuildInput {
            sources,
            entry: manifest.entry.clone(),
        })
        .map_err(RunnerError::Build)?;
        Ok(RunnerCheckReport {
            entry: manifest.entry,
            source_count,
        })
    }
}

/// Test fixtures + loopback helpers shared by `igniter-web` and `igniter-server` proofs. Lab/test only.
pub mod testkit {
    use super::*;
    use igniter_server::host;
    use std::io::{Read, Write};
    use std::net::{TcpListener, TcpStream};
    use std::thread;

    pub const HANDLERS: &str = "\
module TodoHandlers
import IgWebPrelude
pure contract Health {
  input req : Request
  compute d : Decision = Respond { status: 200, body: \"ok\" }
  output d : Decision
}
pure contract TodoIndex {
  input req : Request
  compute d : Decision = Respond { status: 200, body: \"[]\" }
  output d : Decision
}
pure contract TodoCreate {
  input req : Request
  compute d : Decision = InvokeEffect { target: \"todo-create\", input: req.body, idempotency_key: req.idempotency_key }
  output d : Decision
}
pure contract TodoShow {
  input req : Request
  input id : Option[String]
  compute d : Decision = Respond { status: 200, body: or_else(id, \"none\") }
  output d : Decision
}
pure contract TodoDone {
  input req : Request
  input id : Option[String]
  compute d : Decision = InvokeEffect { target: \"todo-done\", input: or_else(id, \"none\"), idempotency_key: req.idempotency_key }
  output d : Decision
}
";

    pub const IGWEB: &str = "\
app TodoWeb entry Serve {
  handlers TodoHandlers
  route GET  \"/health\"          -> Health
  route GET  \"/todos\"           -> TodoIndex
  route POST \"/todos\"           -> TodoCreate requires idempotency
  route GET  \"/todos/:id\"       -> TodoShow
  route POST \"/todos/:id/done\"  -> TodoDone requires idempotency
}
";

    /// Write the canonical Todo fixture sources into a fresh dir; return their paths. P10: no
    /// `web_types.ig` — the builder injects the shared `IgWebPrelude`.
    pub fn write_todo_fixtures(tag: &str) -> Vec<PathBuf> {
        let dir = std::env::temp_dir().join(format!("igweb_fix_{}_{}", std::process::id(), tag));
        std::fs::create_dir_all(&dir).unwrap();
        let hd = dir.join("handlers.ig");
        let rt = dir.join("routes.igweb");
        std::fs::write(&hd, HANDLERS).unwrap();
        std::fs::write(&rt, IGWEB).unwrap();
        vec![hd, rt]
    }

    /// Build the canonical Todo app via the builder (no hand-assembly).
    pub fn build_todo_app(tag: &str) -> Arc<dyn ServerApp + Send + Sync> {
        build_igweb_app(IgWebBuildInput {
            sources: write_todo_fixtures(tag),
            entry: "Serve".into(),
        })
        .expect("build todo app")
    }

    /// One raw loopback HTTP request through `host::serve_once(&listener, app)` → (status, body json).
    pub fn roundtrip(
        app: &dyn ServerApp,
        method: &str,
        path: &str,
        headers: &[(&str, &str)],
        body: &str,
    ) -> (u16, Value) {
        let listener = TcpListener::bind(("127.0.0.1", 0)).unwrap();
        let addr = listener.local_addr().unwrap().to_string();
        let (m, p, b) = (method.to_string(), path.to_string(), body.to_string());
        let hs: Vec<(String, String)> = headers
            .iter()
            .map(|(k, v)| (k.to_string(), v.to_string()))
            .collect();
        let client = thread::spawn(move || {
            let mut s = TcpStream::connect(&addr).unwrap();
            let mut req = format!("{m} {p} HTTP/1.1\r\nHost: x\r\n");
            for (k, v) in &hs {
                req.push_str(&format!("{k}: {v}\r\n"));
            }
            req.push_str(&format!("Content-Length: {}\r\n\r\n{}", b.len(), b));
            s.write_all(req.as_bytes()).unwrap();
            s.flush().unwrap();
            let mut raw = Vec::new();
            s.read_to_end(&mut raw).unwrap();
            let text = String::from_utf8_lossy(&raw).to_string();
            let status: u16 = text
                .split_whitespace()
                .nth(1)
                .and_then(|x| x.parse().ok())
                .unwrap_or(0);
            let bs = text.find("\r\n\r\n").map(|i| i + 4).unwrap_or(text.len());
            let bj: Value = serde_json::from_str(text[bs..].trim()).unwrap_or(Value::Null);
            (status, bj)
        });
        host::serve_once(&listener, app).unwrap();
        client.join().unwrap()
    }

    /// Like `roundtrip`, but returns the RAW response text (head + body) so non-JSON bodies — HTML from a
    /// `Render` decision, etc. — can be inspected verbatim (content-type header, body bytes).
    pub fn roundtrip_raw(
        app: &dyn ServerApp,
        method: &str,
        path: &str,
        headers: &[(&str, &str)],
        body: &str,
    ) -> (u16, String) {
        let listener = TcpListener::bind(("127.0.0.1", 0)).unwrap();
        let addr = listener.local_addr().unwrap().to_string();
        let (m, p, b) = (method.to_string(), path.to_string(), body.to_string());
        let hs: Vec<(String, String)> = headers
            .iter()
            .map(|(k, v)| (k.to_string(), v.to_string()))
            .collect();
        let client = thread::spawn(move || {
            let mut s = TcpStream::connect(&addr).unwrap();
            let mut req = format!("{m} {p} HTTP/1.1\r\nHost: x\r\n");
            for (k, v) in &hs {
                req.push_str(&format!("{k}: {v}\r\n"));
            }
            req.push_str(&format!("Content-Length: {}\r\n\r\n{}", b.len(), b));
            s.write_all(req.as_bytes()).unwrap();
            s.flush().unwrap();
            let mut raw = Vec::new();
            s.read_to_end(&mut raw).unwrap();
            let text = String::from_utf8_lossy(&raw).to_string();
            let status: u16 = text
                .split_whitespace()
                .nth(1)
                .and_then(|x| x.parse().ok())
                .unwrap_or(0);
            (status, text)
        });
        host::serve_once(&listener, app).unwrap();
        client.join().unwrap()
    }

    /// Minimal loopback GET → status (for reload proofs).
    pub fn http_get(addr: &str, path: &str) -> u16 {
        let mut s = TcpStream::connect(addr).unwrap();
        s.write_all(
            format!("GET {path} HTTP/1.1\r\nHost: x\r\nContent-Length: 0\r\n\r\n").as_bytes(),
        )
        .unwrap();
        s.flush().unwrap();
        let mut raw = Vec::new();
        s.read_to_end(&mut raw).unwrap();
        String::from_utf8_lossy(&raw)
            .split_whitespace()
            .nth(1)
            .and_then(|x| x.parse().ok())
            .unwrap_or(0)
    }
}

// ── Host surrogate-id recipe (LAB-TODOAPP-API-HOST-SURROGATE-ID-P36) ─────────────────────────────
#[cfg(test)]
mod surrogate_id_tests {
    use super::surrogate_id;

    #[test]
    fn empty_key_yields_empty_surrogate() {
        // A keyless mutating request is refused by the route guard before intent construction; no id.
        assert_eq!(surrogate_id("POST", "/accounts/7/todos", ""), "");
    }

    #[test]
    fn deterministic_across_replay() {
        // Same (method, path, key) → same id, every time (replay-safe; no clock/randomness inputs).
        let a = surrogate_id("POST", "/accounts/7/todos", "evt-1");
        let b = surrogate_id("POST", "/accounts/7/todos", "evt-1");
        assert_eq!(a, b);
        assert_eq!(a.len(), 32, "128-bit hex digest");
        assert!(
            a.chars().all(|c| c.is_ascii_hexdigit()),
            "opaque hex, leaks nothing: {a}"
        );
    }

    #[test]
    fn namespaced_by_account_route_and_key() {
        let base = surrogate_id("POST", "/accounts/7/todos", "evt-1");
        // Different account (in the path) → different id, even with the same idempotency key.
        assert_ne!(base, surrogate_id("POST", "/accounts/8/todos", "evt-1"));
        // Different idempotency key → different id.
        assert_ne!(base, surrogate_id("POST", "/accounts/7/todos", "evt-2"));
        // Different method → different id (the unit-separator framing prevents concat collisions).
        assert_ne!(base, surrogate_id("PUT", "/accounts/7/todos", "evt-1"));
    }

    #[test]
    fn does_not_embed_the_idempotency_key() {
        // The id must not be the raw key (or trivially contain it) — blake3 is one-way.
        let id = surrogate_id("POST", "/accounts/7/todos", "secret-correlation-evt-1");
        assert!(!id.contains("secret-correlation-evt-1"));
        assert_ne!(id, "secret-correlation-evt-1");
    }
}
