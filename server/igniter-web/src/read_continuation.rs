//! Read-continuation shape classification + app-row-shape recovery (LAB-IGNITER-DATA-PROJECTION-BOOT-
//! RECONCILIATION-P7).
//!
//! The P6 typed-row crossing was harness-driven: a test supplied the app row shape and called
//! `StagedReadHost::execute_typed` directly. P7 lifts it into the normal `ReadThen` runner contour by having
//! the host **read the continuation's declared inputs from compiled metadata** and choose the crossing:
//!
//! - a continuation taking `rows_json : String` → the legacy stringly path (unchanged);
//! - a continuation taking `rows : Collection[<AppRow>]` (+ `meta : DatasetMeta`) → the typed path, with the
//!   `<AppRow>` field shape recovered from the registry so the host can reconcile it against its read policy
//!   before dispatch.
//!
//! **Metadata source (verify-first).** Both reads come from the *compiled* program, never from authored
//! `.ig` source:
//! - continuation inputs: the assembled contract JSON's `input_ports` (each `{ name, type_tag }`, where
//!   `type_tag` is the assembler's stringified type, e.g. `"String"`, `"Collection[TodoRow]"`,
//!   `"DatasetMeta"` — `assembler.rs:513-520`), held in `machine.registry`;
//! - the `<AppRow>` field shape: the typechecker's `type_env` (`{ field: { "name", "params" } }`), persisted
//!   into `ContractRegistry.type_defs` at load (P7 machine accessor). No regex, no source parsing, no schema
//!   sidecar, no name-based guessing.

use crate::read_materialize::AppFieldType;
use crate::runner_diag::{DiagCode, RunnerDiagnostic};
use igniter_machine::machine::IgniterMachine;
use serde_json::Value;

/// How the host should cross a staged read's rows into a given continuation, decided from its compiled inputs.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ReadContinuationShape {
    /// Takes `rows_json : String` — the pre-P6 stringly boundary. Crossed as `{ req, rows_json, carry }`.
    LegacyRowsJson,
    /// Takes `rows : Collection[<row_type>]` (and, when declared, `meta : DatasetMeta`). Crossed as
    /// `{ req, rows, meta, carry }` after materialization + reconciliation.
    TypedRows {
        /// The element type name parsed from the `Collection[...]` tag (e.g. `"TodoRow"`).
        row_type: String,
        /// Whether the continuation also declares `meta : DatasetMeta` (the host crosses `meta` regardless;
        /// this is recorded only for honest diagnostics).
        declares_meta: bool,
    },
    /// Ambiguous or unsupported input shape — the host fails closed rather than guess.
    Invalid(String),
}

/// Read a continuation contract's declared inputs from the registry and classify its read-crossing shape.
/// A missing contract, or a shape that declares neither `rows_json : String` nor `rows : Collection[...]`,
/// or one that declares BOTH, is `Invalid` (fail-closed). Pure metadata read — no dispatch, no source parse.
pub fn classify_continuation(machine: &IgniterMachine, then: &str) -> ReadContinuationShape {
    let contract = match machine.registry.read().get(then).cloned() {
        Some(c) => c,
        None => return ReadContinuationShape::Invalid(format!("continuation `{then}` not found")),
    };
    let ports = match contract.get("input_ports").and_then(|v| v.as_array()) {
        Some(p) => p.clone(),
        None => {
            return ReadContinuationShape::Invalid(format!(
                "continuation `{then}` has no input_ports metadata"
            ))
        }
    };

    let mut rows_json = false;
    let mut rows_tag: Option<String> = None;
    let mut declares_meta = false;
    for port in &ports {
        let name = port.get("name").and_then(|v| v.as_str()).unwrap_or("");
        let tag = port.get("type_tag").and_then(|v| v.as_str()).unwrap_or("");
        match name {
            "rows_json" if tag == "String" => rows_json = true,
            "rows" => rows_tag = Some(tag.to_string()),
            "meta" if tag == "DatasetMeta" => declares_meta = true,
            _ => {}
        }
    }

    match (rows_json, rows_tag) {
        (true, Some(_)) => ReadContinuationShape::Invalid(format!(
            "continuation `{then}` declares BOTH `rows_json` and `rows` — ambiguous"
        )),
        (true, None) => ReadContinuationShape::LegacyRowsJson,
        (false, Some(tag)) => match collection_element(&tag) {
            Some(elem) if is_record_like(&elem) => ReadContinuationShape::TypedRows {
                row_type: elem,
                declares_meta,
            },
            Some(elem) => ReadContinuationShape::Invalid(format!(
                "continuation `{then}` declares `rows : Collection[{elem}]` — element must be a record type, not a scalar"
            )),
            None => ReadContinuationShape::Invalid(format!(
                "continuation `{then}` declares `rows : {tag}` — expected `Collection[<Record>]`"
            )),
        },
        // Declares NEITHER `rows_json` nor `rows`: default to the legacy crossing (the host always crossed
        // `rows_json`, which such a continuation simply ignores). This preserves the exact pre-P7 behaviour —
        // e.g. a continuation that only re-issues a `ReadThen` from `req` (the staged-read bound test).
        (false, None) => ReadContinuationShape::LegacyRowsJson,
    }
}

/// Parse the element type out of a `Collection[Elem]` tag. Returns `None` for any other shape.
fn collection_element(tag: &str) -> Option<String> {
    let inner = tag.strip_prefix("Collection[")?.strip_suffix(']')?;
    if inner.is_empty() {
        None
    } else {
        Some(inner.to_string())
    }
}

/// Is a type name a user record (not a built-in scalar / generic)? A scalar element (`Collection[String]`)
/// is NOT a product-row boundary in v0 (card boundary). Anything that is not a known scalar is treated as a
/// candidate record and validated by `app_row_shape` against the registry's type defs.
fn is_record_like(name: &str) -> bool {
    !matches!(
        name,
        "String" | "Text" | "Integer" | "Bool" | "Boolean" | "Float" | "Decimal" | "Unknown"
    )
}

/// Recover a continuation's `<AppRow>` field shape from the registry's persisted type defs (P7 machine
/// accessor) — `[(field_name, AppFieldType)]`, the input `reconcile_projection` checks against the host read
/// policy. `Err` if the type is unknown (not in `type_defs`) or carries a field type with no v0 projection
/// landing (so an un-reconcilable row type fails closed rather than crossing blind).
pub fn app_row_shape(
    machine: &IgniterMachine,
    row_type: &str,
) -> Result<Vec<(String, AppFieldType)>, String> {
    let fields = machine
        .registry
        .read()
        .type_def(row_type)
        .cloned()
        .ok_or_else(|| format!("unknown row type `{row_type}` (no compiled type def)"))?;
    let obj = fields
        .as_object()
        .ok_or_else(|| format!("row type `{row_type}` has a malformed type def"))?;

    let mut out = Vec::with_capacity(obj.len());
    for (field, type_ir) in obj {
        let ty = app_field_type(type_ir).ok_or_else(|| {
            format!(
                "row type `{row_type}` field `{field}` has type `{}` with no v0 projection landing",
                type_ir_name(type_ir)
            )
        })?;
        out.push((field.clone(), ty));
    }
    // Deterministic order (BTreeMap-style) so diagnostics + reconciliation are stable across runs.
    out.sort_by(|a, b| a.0.cmp(&b.0));
    Ok(out)
}

/// Structurally validate every loaded contract as a candidate read continuation (P8 boot/check subset).
/// Scans the registry, classifies each contract by its compiled inputs, and emits one diagnostic per
/// continuation whose read-crossing shape is invalid **independent of any DB source**:
///
/// - `Invalid` shape (declares both `rows_json` and `rows`; a scalar / non-collection `rows`);
/// - `TypedRows` whose `<AppRow>` type is unrecoverable from `type_defs` or has a field with no v0
///   projection landing (so it could never be a projection target, regardless of which source feeds it).
///
/// A `LegacyRowsJson` shape (incl. a contract declaring neither `rows` nor `rows_json`) is sound. This is
/// the source-INDEPENDENT subset; the host-kind ⇎ row-type drift that needs a runtime `plan.source` stays a
/// first-dispatch guard in `dispatch_with_read`. Contracts are scanned in name order for stable output.
pub fn validate_read_continuations(machine: &IgniterMachine) -> Vec<RunnerDiagnostic> {
    let mut names: Vec<String> = {
        let reg = machine.registry.read();
        reg.all().map(|(k, _)| k.clone()).collect()
    };
    names.sort();

    let mut diags = Vec::new();
    for name in &names {
        let reason = match classify_continuation(machine, name) {
            ReadContinuationShape::Invalid(reason) => Some(reason),
            ReadContinuationShape::TypedRows { row_type, .. } => {
                app_row_shape(machine, &row_type).err()
            }
            ReadContinuationShape::LegacyRowsJson => None,
        };
        if let Some(reason) = reason {
            diags.push(RunnerDiagnostic::new(
                DiagCode::ProjectionSchemaInvalid,
                format!("read continuation `{name}`: {reason}"),
            ));
        }
    }
    diags
}

/// The leaf type name of a `type_ir` value (`{ "name": "...", "params": [...] }`), or `"Unknown"`.
fn type_ir_name(type_ir: &Value) -> String {
    type_ir
        .get("name")
        .and_then(|v| v.as_str())
        .unwrap_or("Unknown")
        .to_string()
}

/// Map a `type_ir` to the projection-landing `AppFieldType` (the P3 §3 matrix's app side). v0 scalar landings
/// plus `Map[String, Unknown]` (Json) and `Collection[String]` (Array). Anything else → `None` (fail closed).
fn app_field_type(type_ir: &Value) -> Option<AppFieldType> {
    let name = type_ir.get("name").and_then(|v| v.as_str())?;
    match name {
        "String" => Some(AppFieldType::String),
        "Text" => Some(AppFieldType::Text),
        "Integer" => Some(AppFieldType::Integer),
        "Bool" | "Boolean" => Some(AppFieldType::Bool),
        // P23: `Decimal[N]` — the scale `N` is the first type param. In the persisted type_env a
        // `Decimal[2]` annotation is `{name:"Decimal", params:["2"]}` (the param is a bare string); accept
        // an object `{name:"2"}` form too for robustness. A missing/unparseable scale → `None` (fail closed).
        "Decimal" => type_ir
            .get("params")
            .and_then(|p| p.as_array())
            .and_then(|a| a.first())
            .and_then(|p| p.as_str().or_else(|| p.get("name").and_then(|n| n.as_str())))
            .and_then(|s| s.parse::<u32>().ok())
            .map(AppFieldType::Decimal),
        "Map" => Some(AppFieldType::MapUnknown),
        "Collection" => {
            // Only Collection[String] lands in v0 (the Array kind).
            let elem = type_ir
                .get("params")
                .and_then(|p| p.as_array())
                .and_then(|a| a.first())
                .map(type_ir_name);
            match elem.as_deref() {
                Some("String") => Some(AppFieldType::CollectionString),
                _ => None,
            }
        }
        _ => None,
    }
}
