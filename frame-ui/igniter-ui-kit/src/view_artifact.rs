//! ViewArtifact JSON → kit component tree (LAB-FRAME-VIEWARTIFACT-P12). The first PORTABLE
//! app-authoring layer from the P11 model: a structured, inspectable, diffable JSON screen
//! description that COMPILES to the proven Rust kit (`Form` / `Workbench`), which then runs on
//! `FrameRuntime` unchanged. No `.ig`, no DSL, no parser beyond serde_json; machine-free.
//!
//! The artifact is data, so it is generated/validated/diffed easily — the reason it comes before a
//! text DSL (`.igv`). The compile is a deterministic lowering: the same JSON yields the same kit
//! tree yields byte-identical frames to the hand-written constructor.

use crate::composition::{FieldKind, FieldSpec, Workbench};
use crate::{button, checkbox, label, select, text, Component, Form};
use serde_json::Value;
use std::fmt;

/// A compile error with a human-readable reason (the artifact is a developer-facing authoring layer).
#[derive(Debug, Clone, PartialEq)]
pub enum ViewError {
    Parse(String),
    Schema(String),
}

impl fmt::Display for ViewError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            ViewError::Parse(m) => write!(f, "view artifact parse error: {m}"),
            ViewError::Schema(m) => write!(f, "view artifact schema error: {m}"),
        }
    }
}

impl std::error::Error for ViewError {}

/// A compiled screen — one of the kit's top-level authoring shapes.
#[derive(Debug)]
pub enum Screen {
    Workbench(Workbench),
    Form(Form),
}

fn req_str(v: &Value, key: &str, ctx: &str) -> Result<String, ViewError> {
    v.get(key)
        .and_then(|x| x.as_str())
        .map(|s| s.to_string())
        .ok_or_else(|| ViewError::Schema(format!("{ctx}: missing string field '{key}'")))
}

fn req_options(v: &Value, id: &str) -> Result<Vec<String>, ViewError> {
    let arr = v
        .get("options")
        .and_then(|o| o.as_array())
        .ok_or_else(|| ViewError::Schema(format!("select '{id}': missing 'options' array")))?;
    arr.iter()
        .map(|o| {
            o.as_str()
                .map(|s| s.to_string())
                .ok_or_else(|| ViewError::Schema(format!("select '{id}': option is not a string")))
        })
        .collect()
}

/// Parse + validate a ViewArtifact JSON, dispatching on `layout`.
pub fn compile(json: &str) -> Result<Screen, ViewError> {
    let v: Value = serde_json::from_str(json).map_err(|e| ViewError::Parse(e.to_string()))?;
    if v.get("artifact").and_then(|a| a.as_str()) != Some("view") {
        return Err(ViewError::Schema(
            "not a view artifact (\"artifact\" must be \"view\")".into(),
        ));
    }
    match v.get("layout").and_then(|l| l.as_str()) {
        Some("workbench") => Ok(Screen::Workbench(workbench_from_value(&v)?)),
        Some("form") => Ok(Screen::Form(form_from_value(&v)?)),
        other => Err(ViewError::Schema(format!(
            "unknown layout: {other:?} (expected \"workbench\" or \"form\")"
        ))),
    }
}

/// Compile a `workbench`-layout artifact to a `Workbench`.
pub fn compile_workbench(json: &str) -> Result<Workbench, ViewError> {
    match compile(json)? {
        Screen::Workbench(wb) => Ok(wb),
        Screen::Form(_) => Err(ViewError::Schema(
            "expected a workbench layout, got a form".into(),
        )),
    }
}

/// Compile a `form`-layout artifact to a `Form`.
pub fn compile_form(json: &str) -> Result<Form, ViewError> {
    match compile(json)? {
        Screen::Form(f) => Ok(f),
        Screen::Workbench(_) => Err(ViewError::Schema(
            "expected a form layout, got a workbench".into(),
        )),
    }
}

/// Parse a `fields` array Value into `FieldSpec`s — shared by the workbench compiler and the
/// binding host (which builds a workbench from a bound artifact's `regions.main.fields`).
pub fn parse_fields(fields_value: &Value) -> Result<Vec<FieldSpec>, ViewError> {
    let arr = fields_value
        .as_array()
        .ok_or_else(|| ViewError::Schema("\"fields\" must be an array".into()))?;
    arr.iter().map(field_from_value).collect()
}

fn field_from_value(fv: &Value) -> Result<FieldSpec, ViewError> {
    let id = req_str(fv, "id", "field")?;
    let label = req_str(fv, "label", "field")?;
    let required = fv
        .get("required")
        .and_then(|b| b.as_bool())
        .unwrap_or(false);
    let kind = match req_str(fv, "kind", "field")?.as_str() {
        "text" => FieldKind::Text,
        "checkbox" => FieldKind::Checkbox,
        "select" => FieldKind::Select(req_options(fv, &id)?),
        other => {
            return Err(ViewError::Schema(format!(
                "unknown field kind '{other}' for '{id}'"
            )))
        }
    };
    Ok(FieldSpec {
        id,
        label,
        kind,
        required,
    })
}

fn workbench_from_value(v: &Value) -> Result<Workbench, ViewError> {
    let leads_v = v
        .get("data")
        .and_then(|d| d.get("leads"))
        .and_then(|l| l.as_array())
        .ok_or_else(|| ViewError::Schema("workbench: \"data.leads\" array required".into()))?;
    let leads = leads_v
        .iter()
        .map(|l| {
            l.as_str()
                .map(|s| s.to_string())
                .ok_or_else(|| ViewError::Schema("lead is not a string".into()))
        })
        .collect::<Result<Vec<_>, _>>()?;

    let fields_v = v
        .get("regions")
        .and_then(|r| r.get("main"))
        .and_then(|m| m.get("fields"))
        .and_then(|f| f.as_array())
        .ok_or_else(|| {
            ViewError::Schema("workbench: \"regions.main.fields\" array required".into())
        })?;
    let fields = fields_v
        .iter()
        .map(field_from_value)
        .collect::<Result<Vec<_>, _>>()?;

    if fields.is_empty() {
        return Err(ViewError::Schema(
            "workbench: at least one field required".into(),
        ));
    }
    Ok(Workbench { leads, fields })
}

fn component_from_value(cv: &Value) -> Result<Component, ViewError> {
    match req_str(cv, "kind", "component")?.as_str() {
        "label" => Ok(label(&req_str(cv, "text", "label component")?)),
        "text" => Ok(text(
            &req_str(cv, "id", "text component")?,
            &req_str(cv, "label", "text component")?,
            cv.get("required")
                .and_then(|b| b.as_bool())
                .unwrap_or(false),
        )),
        "select" => {
            let id = req_str(cv, "id", "select component")?;
            let opts = req_options(cv, &id)?;
            let refs: Vec<&str> = opts.iter().map(|s| s.as_str()).collect();
            Ok(select(
                &id,
                &req_str(cv, "label", "select component")?,
                &refs,
                cv.get("required")
                    .and_then(|b| b.as_bool())
                    .unwrap_or(false),
            ))
        }
        "checkbox" => Ok(checkbox(
            &req_str(cv, "id", "checkbox component")?,
            &req_str(cv, "label", "checkbox component")?,
        )),
        "button" => Ok(button(
            &req_str(cv, "id", "button component")?,
            &req_str(cv, "label", "button component")?,
            &req_str(cv, "action", "button component")?,
        )),
        other => Err(ViewError::Schema(format!(
            "unknown component kind '{other}'"
        ))),
    }
}

fn form_from_value(v: &Value) -> Result<Form, ViewError> {
    let body_v = v
        .get("body")
        .and_then(|b| b.as_array())
        .ok_or_else(|| ViewError::Schema("form: \"body\" array required".into()))?;
    let title = v
        .get("title")
        .and_then(|t| t.as_str())
        .unwrap_or("")
        .to_string();
    let body = body_v
        .iter()
        .map(component_from_value)
        .collect::<Result<Vec<_>, _>>()?;
    if body.is_empty() {
        return Err(ViewError::Schema("form: \"body\" must not be empty".into()));
    }
    Ok(Form { title, body })
}
