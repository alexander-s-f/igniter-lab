//! ViewArtifact `.ig` binding — proof-local fixture host (LAB-FRAME-IG-BINDING-P16).
//!
//! Implements the P15 boundary at its smallest: a ViewArtifact declares a data `source` and a submit
//! `action`; a HOST resolves them against a registry of contracts and returns data / scoped errors /
//! a receipt as view-observable state. Everything here is FIXTURE and deterministic — NO real
//! machine, NO `CoordinationHub`, NO passport, NO capability-IO receipt, NO external IO.
//!
//! The core invariant is the **double gate**: a source/action runs only if it is BOTH declared in the
//! artifact's `sources`/`actions` manifest AND registered in the host's `FixtureContractRegistry`.
//! Missing either fails BEFORE any contract executes. View-local state (selection, drafts) never
//! crosses to the host; only `submit` does. The browser/UI path holds no authority.

use crate::composition::{Workbench, WorkbenchRuntime};
use crate::view_artifact::parse_fields;
use serde_json::{json, Map, Value};
use std::collections::HashMap;
use std::fmt;

const SELECT_PLACEHOLDER: &str = "\u{2014} select \u{2014}"; // "— select —", matches the projector

/// A binding error — distinct variants so the failure is precise (the artifact is developer-facing).
#[derive(Debug, Clone, PartialEq)]
pub enum BindingError {
    Parse(String),
    MissingDeclaration(String), // a `bind`/`action` name not present in the manifest
    NotRegistered(String),      // a declared contract absent from the host registry
    Schema(String),
}

impl fmt::Display for BindingError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            BindingError::Parse(m) => write!(f, "binding parse error: {m}"),
            BindingError::MissingDeclaration(m) => write!(f, "missing binding declaration: {m}"),
            BindingError::NotRegistered(m) => write!(f, "contract not registered: {m}"),
            BindingError::Schema(m) => write!(f, "binding schema error: {m}"),
        }
    }
}
impl std::error::Error for BindingError {}

/// A FIXTURE receipt — explicitly NOT a capability-IO receipt. Content-addressed for determinism.
#[derive(Debug, Clone, PartialEq)]
pub struct BindingReceipt {
    pub contract: String,
    pub id: String,     // "fixture-receipt:<digest>"
    pub status: String, // "fixture-ok"
}

/// What a fixture contract returns.
#[derive(Debug, Clone)]
pub enum BindingResponse {
    Data(Value),               // a read source result
    Validated,                 // validation passed
    Rejected(Map<String, Value>), // scoped field diagnostics (field -> message)
    Receipt(BindingReceipt),   // a submit result
}

type Handler = fn(&Value) -> BindingResponse;

/// A registry of named fixture contracts + per-contract call counters (so tests can prove exactly
/// what crossed the host boundary). Mirrors the machine's `ContractRegistry` shape (name -> handler).
pub struct FixtureContractRegistry {
    handlers: HashMap<String, Handler>,
    calls: HashMap<String, usize>,
}

impl FixtureContractRegistry {
    pub fn new() -> Self {
        Self { handlers: HashMap::new(), calls: HashMap::new() }
    }
    pub fn register(&mut self, name: &str, handler: Handler) {
        self.handlers.insert(name.to_string(), handler);
    }
    pub fn has(&self, name: &str) -> bool {
        self.handlers.contains_key(name)
    }
    pub fn calls(&self, name: &str) -> usize {
        *self.calls.get(name).unwrap_or(&0)
    }
    fn call(&mut self, name: &str, input: &Value) -> Option<BindingResponse> {
        let h = *self.handlers.get(name)?;
        *self.calls.entry(name.to_string()).or_default() += 1;
        Some(h(input))
    }

    /// The lead-review fixture set: `ListLeads`, `ValidateLeadReview`, `SubmitLeadReview`.
    pub fn lead_review() -> Self {
        let mut r = Self::new();
        r.register("ListLeads", fixture_list_leads);
        r.register("ValidateLeadReview", fixture_validate_lead_review);
        r.register("SubmitLeadReview", fixture_submit_lead_review);
        r
    }
}

impl Default for FixtureContractRegistry {
    fn default() -> Self {
        Self::lead_review()
    }
}

fn fixture_list_leads(_input: &Value) -> BindingResponse {
    BindingResponse::Data(json!(["Ada", "Grace", "Linus"]))
}

fn fixture_validate_lead_review(input: &Value) -> BindingResponse {
    let fields = input.get("fields").cloned().unwrap_or(json!({}));
    let mut errs = Map::new();
    let priority = fields.get("priority").and_then(|v| v.as_str()).unwrap_or("");
    if priority.trim().is_empty() {
        errs.insert("priority".into(), json!("required"));
    }
    let stage = fields.get("stage").and_then(|v| v.as_str()).unwrap_or("");
    if stage.is_empty() || stage == SELECT_PLACEHOLDER {
        errs.insert("stage".into(), json!("select one"));
    }
    if errs.is_empty() {
        BindingResponse::Validated
    } else {
        BindingResponse::Rejected(errs)
    }
}

fn fixture_submit_lead_review(input: &Value) -> BindingResponse {
    // content-addressed → deterministic: same payload ⇒ same receipt id
    let digest = blake3::hash(serde_json::to_string(input).unwrap_or_default().as_bytes());
    BindingResponse::Receipt(BindingReceipt {
        contract: "SubmitLeadReview".to_string(),
        id: format!("fixture-receipt:{}", &digest.to_hex()[..10]),
        status: "fixture-ok".to_string(),
    })
}

// ── manifest ────────────────────────────────────────────────────────────────────────────────────

#[derive(Debug, Clone)]
struct SourceSpec {
    contract: String,
}
#[derive(Debug, Clone)]
struct ActionSpec {
    contract: String,
    validate: Option<String>,
}
#[derive(Debug, Clone, Default)]
struct Manifest {
    sources: HashMap<String, SourceSpec>,
    actions: HashMap<String, ActionSpec>,
}

fn parse_manifest(v: &Value) -> Manifest {
    let mut m = Manifest::default();
    if let Some(obj) = v.get("sources").and_then(|s| s.as_object()) {
        for (name, spec) in obj {
            if let Some(c) = spec.get("contract").and_then(|c| c.as_str()) {
                m.sources.insert(name.clone(), SourceSpec { contract: c.to_string() });
            }
        }
    }
    if let Some(obj) = v.get("actions").and_then(|a| a.as_object()) {
        for (name, spec) in obj {
            if let Some(c) = spec.get("contract").and_then(|c| c.as_str()) {
                m.actions.insert(
                    name.clone(),
                    ActionSpec {
                        contract: c.to_string(),
                        validate: spec.get("validate").and_then(|x| x.as_str()).map(String::from),
                    },
                );
            }
        }
    }
    m
}

// ── the host ──────────────────────────────────────────────────────────────────────────────────

/// A host that runs a workbench whose data + submit are bound to fixture contracts. The host owns
/// resolution, the registry, the domain results (scoped errors, last receipt); the workbench owns
/// only view-local state.
pub struct BoundViewHost {
    manifest: Manifest,
    registry: FixtureContractRegistry,
    workbench: WorkbenchRuntime,
    errors: HashMap<String, Map<String, Value>>, // scoped per lead (host-owned domain diagnostics)
    last_receipt: Option<BindingReceipt>,
    last_refusal: Option<String>,
}

impl BoundViewHost {
    /// Build the host: parse the manifest, resolve the `leads` data source (double gate), and build
    /// the workbench with the source-provided leads + the artifact's fields.
    pub fn from_artifact(json_str: &str, mut registry: FixtureContractRegistry) -> Result<Self, BindingError> {
        let v: Value = serde_json::from_str(json_str).map_err(|e| BindingError::Parse(e.to_string()))?;
        if v.get("artifact").and_then(|a| a.as_str()) != Some("view") {
            return Err(BindingError::Schema("not a view artifact".into()));
        }
        let manifest = parse_manifest(&v);

        // data bind: sidebar declares `bind: "leads"` → resolve sources.leads
        let bind_name = v
            .get("regions")
            .and_then(|r| r.get("sidebar"))
            .and_then(|s| s.get("bind"))
            .and_then(|b| b.as_str())
            .ok_or_else(|| BindingError::Schema("sidebar has no data bind".into()))?;
        // DOUBLE GATE (1): declared in the manifest?
        let src = manifest
            .sources
            .get(bind_name)
            .ok_or_else(|| BindingError::MissingDeclaration(format!("sources.{bind_name}")))?;
        // DOUBLE GATE (2): registered in the host?
        if !registry.has(&src.contract) {
            return Err(BindingError::NotRegistered(src.contract.clone()));
        }
        let leads = match registry.call(&src.contract, &json!({})) {
            Some(BindingResponse::Data(Value::Array(a))) => {
                a.iter().filter_map(|x| x.as_str().map(String::from)).collect::<Vec<_>>()
            }
            _ => return Err(BindingError::Schema(format!("{} did not return a lead list", src.contract))),
        };

        let fields_v = v
            .get("regions")
            .and_then(|r| r.get("main"))
            .and_then(|m| m.get("fields"))
            .ok_or_else(|| BindingError::Schema("regions.main.fields required".into()))?;
        let fields = parse_fields(fields_v).map_err(|e| BindingError::Schema(e.to_string()))?;

        let workbench = WorkbenchRuntime::new(Workbench { leads, fields });
        Ok(Self {
            manifest,
            registry,
            workbench,
            errors: HashMap::new(),
            last_receipt: None,
            last_refusal: None,
        })
    }

    // ── view-local interaction (forwarded; never calls the host) ──
    pub fn click(&mut self, cx: f64, cy: f64) -> bool {
        // intercept the submit button → route through the host; everything else is view-local
        let frame = self.workbench.frame();
        if let Some(hit) = igniter_frame::hit_test(&frame, cx.round() as i64, cy.round() as i64) {
            if hit.id == "act:submit" {
                self.submit();
                return true;
            }
        }
        self.workbench.click(cx, cy)
    }
    pub fn key(&mut self, ch: &str) -> bool {
        self.workbench.key(ch)
    }

    /// The view-local payload for the selected lead, read from the projected frame ($selection.lead +
    /// $form.values). Selection and drafts never leave the view except via this declared submit.
    fn form_snapshot(&self) -> Value {
        let frame = self.workbench.frame();
        let mut lead = String::new();
        let mut fields = Map::new();
        for n in &frame.nodes {
            if let Some(name) = n.id.strip_prefix("lead:") {
                if n.data.get("selected").and_then(|v| v.as_bool()) == Some(true) {
                    lead = name.to_string();
                }
            }
            if let Some(rest) = n.id.strip_prefix("fld:") {
                if let Some((_l, field)) = rest.split_once(':') {
                    let kind = n.data.get("kind").and_then(|v| v.as_str()).unwrap_or("");
                    let val = match kind {
                        "text" | "select" => n.data.get("value").cloned().unwrap_or(json!("")),
                        "checkbox" => json!(n.data.get("checked").and_then(|v| v.as_bool()).unwrap_or(false)),
                        _ => Value::Null,
                    };
                    fields.insert(field.to_string(), val);
                }
            }
        }
        json!({ "lead": lead, "fields": Value::Object(fields) })
    }

    /// Run the bound submit action: resolve `actions.submit_lead` (double gate), optionally validate,
    /// then submit. Validation failure → scoped errors, no receipt. Success → a fixture receipt.
    fn submit(&mut self) {
        self.last_refusal = None;
        let snapshot = self.form_snapshot();
        let lead = snapshot.get("lead").and_then(|l| l.as_str()).unwrap_or("").to_string();

        // DOUBLE GATE (1): action declared?
        let action = match self.manifest.actions.get("submit_lead") {
            Some(a) => a.clone(),
            None => {
                self.last_refusal = Some("action 'submit_lead' not declared".into());
                return;
            }
        };

        // validation (if declared) — gated like any contract
        if let Some(vc) = &action.validate {
            if !self.registry.has(vc) {
                self.last_refusal = Some(format!("validate contract '{vc}' not registered"));
                return;
            }
            match self.registry.call(vc, &snapshot) {
                Some(BindingResponse::Rejected(errs)) => {
                    self.errors.insert(lead, errs);
                    self.last_receipt = None;
                    return; // no effect on validation failure
                }
                Some(BindingResponse::Validated) => {}
                _ => {
                    self.last_refusal = Some(format!("{vc} returned an unexpected response"));
                    return;
                }
            }
        }

        // DOUBLE GATE (2): submit contract registered?
        if !self.registry.has(&action.contract) {
            self.last_refusal = Some(format!("contract '{}' not registered", action.contract));
            return;
        }
        match self.registry.call(&action.contract, &snapshot) {
            Some(BindingResponse::Receipt(r)) => {
                self.errors.remove(&lead); // success clears prior scoped errors
                self.last_receipt = Some(r);
            }
            _ => {
                self.last_refusal = Some(format!("{} returned an unexpected response", action.contract));
            }
        }
    }

    // ── observation (host-owned domain/effect state, separate from view-local) ──
    pub fn leads(&self) -> Vec<String> {
        // read back from the projected list items (proves the source populated the workbench)
        let mut out = Vec::new();
        for n in self.workbench.frame().nodes {
            if let Some(name) = n.id.strip_prefix("lead:") {
                out.push(name.to_string());
            }
        }
        out
    }
    pub fn selected_lead(&self) -> String {
        self.form_snapshot().get("lead").and_then(|l| l.as_str()).map(String::from).unwrap_or_default()
    }
    pub fn errors_for(&self, lead: &str) -> Option<&Map<String, Value>> {
        self.errors.get(lead)
    }
    pub fn last_receipt(&self) -> Option<&BindingReceipt> {
        self.last_receipt.as_ref()
    }
    pub fn last_refusal(&self) -> Option<&str> {
        self.last_refusal.as_deref()
    }
    pub fn calls(&self, contract: &str) -> usize {
        self.registry.calls(contract)
    }
    pub fn workbench_render_digest(&self) -> String {
        self.workbench.render_digest()
    }

    /// Render the workbench + a host-owned binding status overlay (receipt / scoped errors / refusal).
    pub fn render_svg(&self) -> String {
        let svg = self.workbench.render_svg();
        let overlay = if let Some(r) = &self.last_receipt {
            format!(
                "  <text x=\"500\" y=\"428\" font-family=\"monospace\" font-size=\"12\" fill=\"#3fb950\">\u{2713} {} ({})</text>\n",
                esc(&r.id), esc(&r.status)
            )
        } else if let Some(reason) = &self.last_refusal {
            format!("  <text x=\"500\" y=\"428\" font-family=\"monospace\" font-size=\"12\" fill=\"#f85149\">refused: {}</text>\n", esc(reason))
        } else if let Some(errs) = self.errors.get(&self.selected_lead()) {
            format!("  <text x=\"500\" y=\"428\" font-family=\"monospace\" font-size=\"12\" fill=\"#d29922\">validation: {} error(s)</text>\n", errs.len())
        } else {
            String::new()
        };
        if overlay.is_empty() {
            svg
        } else {
            svg.replace("</svg>", &format!("{overlay}</svg>"))
        }
    }

    pub fn frame_index(&self) -> u64 {
        self.workbench.frame_index()
    }
    pub fn lineage_json(&self) -> String {
        self.workbench.lineage_json()
    }
}

fn esc(s: &str) -> String {
    s.replace('&', "&amp;").replace('<', "&lt;").replace('>', "&gt;")
}
