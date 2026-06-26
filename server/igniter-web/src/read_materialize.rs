//! Host-side typed row materializer + schema reconciler (LAB-IGNITER-DATA-PROJECTION-TYPED-ROW-CROSSING-P6).
//!
//! This is the small host-side reshape the P2/P3 readiness packets identified as the *only* gap between
//! the live VM value substrate and a typed `Collection[<AppRow>]` crossing. The VM already turns a JSON
//! array-of-objects into `Collection[Record]` (`from_json`, type-erased at dispatch — see
//! `lab-docs/lang/lab-igniter-data-projection-materialization-readiness-p2-v0.md` §1). What was missing is a
//! host that:
//!
//! 1. **stops stringifying** the already-typed rows (the `rows_json : String` boundary), and
//! 2. **proves, before `.ig` ever sees them, that every row is total + correctly typed** — because the VM's
//!    own missing-field / wrong-scalar behaviour is path-dependent and silent-wrong (P2 §3/§4), so the
//!    stable failure surface MUST be host-owned (P3 §1).
//!
//! Authority split (P3 §7): the **host is the schema authority** (`PostgresReadPolicy.field_kinds`); the
//! **app owns the row *type*** (`type TodoRow { … }` + `input rows : Collection[TodoRow]`). The host honors
//! the app's declared `Collection[<AppRow>]` *by proof, not by trust*:
//!
//! - [`reconcile_projection`] checks the host decode-kinds are assignable to the declared `<AppRow>` field
//!   types (the P3 §3 drift gate). A mismatch is `ProjectionSchemaDrift` — a deploy-time fact, kept off the
//!   per-request path. (v0: a stable host error string; wiring it into the runner `DiagCode` set at boot is
//!   the named P7 follow-on — see the proof doc.)
//! - [`materialize_rows`] aligns each row to the projection spec: every declared field present, each value's
//!   JSON kind matching the host decode-kind, extras dropped. A violation is a stable host error — the host
//!   broke its own promise — surfaced before continuation dispatch, never as a partial `.ig` response.
//!
//! No language / VM / compiler / `.igweb` / Postgres change. DB-free; fake-adapter only.

use igniter_machine::postgres_read::{PostgresReadPolicy, PostgresReadValueKind};
use serde_json::{json, Value};

/// One projected field + the host decode-kind it is the schema authority for. Built from the host's own
/// `PostgresReadPolicy` (the schema authority), NEVER from contract input or DB introspection.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct FieldSpec {
    pub name: String,
    pub kind: PostgresReadValueKind,
}

/// The projection spec the materializer aligns rows to: the ordered set of projected fields and their host
/// decode-kinds. Derived from `PostgresReadPolicy.field_kinds` + the plan's projection — both already held
/// host-side. This is the host's half of the typed crossing contract; the app's half is the `<AppRow>` type.
#[derive(Clone, Debug, PartialEq, Eq, Default)]
pub struct ProjectionSpec {
    pub fields: Vec<FieldSpec>,
}

impl ProjectionSpec {
    /// Build a spec from the host read policy for `source` over the plan's `projection`. An empty projection
    /// means "the whole allowed row", so it falls back to the source's full allowlisted field set (the same
    /// rule the executor's field gate uses). Each field's kind comes from `policy.field_kind` (defaulting to
    /// `Text` for an untyped field, exactly as the decode path does).
    pub fn from_policy(policy: &PostgresReadPolicy, source: &str, projection: &[String]) -> Self {
        let names: Vec<String> = if projection.is_empty() {
            policy
                .allowed_fields
                .get(source)
                .cloned()
                .unwrap_or_default()
        } else {
            projection.to_vec()
        };
        let fields = names
            .into_iter()
            .map(|name| {
                let kind = policy.field_kind(source, &name);
                FieldSpec { name, kind }
            })
            .collect();
        ProjectionSpec { fields }
    }
}

/// A stable name for a `serde_json` value's kind — used only in error text so a wrong-kind refusal names
/// what it actually saw (never the value, which could carry data).
fn json_kind_name(v: &Value) -> &'static str {
    match v {
        Value::Null => "null",
        Value::Bool(_) => "bool",
        Value::Number(n) if n.is_i64() || n.is_u64() => "integer",
        Value::Number(_) => "float",
        Value::String(_) => "string",
        Value::Array(_) => "array",
        Value::Object(_) => "object",
    }
}

/// Does a row value match the host decode-kind it is declared as? This is the totality + scalar-kind gate
/// that keeps the P2 §4 *silent-wrong* hazard (`Value::String("true") == Value::Bool(false)` is `false`)
/// out of `.ig`. v0 kinds that cross losslessly as strings on the wire (Decimal/Timestamp) require a JSON
/// string; a SQL NULL (`Value::Null`) never satisfies a non-nullable field — it is refused like a missing one.
fn value_matches_kind(v: &Value, kind: PostgresReadValueKind) -> bool {
    use PostgresReadValueKind::*;
    match kind {
        // Text, and the v0 lossless-string crossings, require a JSON string. A typed `Decimal{scale}` also
        // arrives as the exact digit STRING (P23) — never a Float; the string→{value,scale} parse (and its
        // own validity check) happens in `materialize_rows`, so a non-string here is already the wrong kind.
        Text | DecimalString | Timestamp | Decimal { .. } => v.is_string(),
        // Integer must be an integral JSON number within i64 — NOT a float, NOT a stringified int.
        Integer => v.is_i64() || v.is_u64(),
        Boolean => v.is_boolean(),
        // Json decodes to an object (a `Map[String, Unknown]`) or a lossless string (P3 §3 matrix).
        Json => v.is_object() || v.is_string(),
        // Array (v0 narrow): a JSON array.
        Array => v.is_array(),
    }
}

/// Parse a CANONICAL finite decimal string into the scaled-integer magnitude `value` for a fixed `scale`,
/// the `i64` the `{ value, scale }` Decimal shape carries (P23). Accepts only `[-]?digits[.digits]` — NO
/// exponent, `+`, whitespace, NaN/Inf, or empty. Fewer fractional digits than `scale` are zero-padded
/// (`"12.5"`@2 → 1250); MORE fractional digits than `scale` fail (no silent truncation/rounding). Overflow of
/// `i64` fails. A rounded/zero magnitude is unsigned (`-0` → `0`). This is host-side parsing — `.ig` never
/// parses money strings.
fn parse_decimal(s: &str, scale: u32) -> Result<i64, String> {
    let (neg, body) = match s.strip_prefix('-') {
        Some(rest) => (true, rest),
        None => (false, s),
    };
    let (int_part, frac_part) = body.split_once('.').unwrap_or((body, ""));
    if int_part.is_empty()
        || !int_part.bytes().all(|b| b.is_ascii_digit())
        || !frac_part.bytes().all(|b| b.is_ascii_digit())
    {
        return Err(format!("not a canonical decimal string: {s:?}"));
    }
    let frac_len = frac_part.len() as u32;
    if frac_len > scale {
        return Err(format!(
            "decimal {s:?} has {frac_len} fractional digits, more than the declared scale {scale}"
        ));
    }
    // Scaled-integer digits = int ++ frac ++ zero-pad to `scale`. Leading zeros are harmless for parse.
    let mut digits = String::with_capacity(int_part.len() + scale as usize);
    digits.push_str(int_part);
    digits.push_str(frac_part);
    for _ in 0..(scale - frac_len) {
        digits.push('0');
    }
    let mag: i64 = digits
        .parse()
        .map_err(|_| format!("decimal {s:?} overflows i64 at scale {scale}"))?;
    Ok(if neg && mag != 0 { -mag } else { mag })
}

/// Align typed read rows to the projection spec, producing a **total + typed** `serde_json` array the host
/// can cross structurally (the VM's `from_json` then materializes `Collection[Record]`). For each row:
/// keep only the projected fields (drop extras, cosmetic per P2 §4), require every declared field present,
/// and require each value's JSON kind to match its host decode-kind. Any violation is a stable `Err` — the
/// host broke its own promise — to be surfaced *before* continuation dispatch (never a partial `.ig` response).
///
/// `Ok(Value::Array(objects))` is crossed under the continuation's `rows` input; `from_json` does the rest.
pub fn materialize_rows(rows: &[Value], spec: &ProjectionSpec) -> Result<Value, String> {
    let mut out = Vec::with_capacity(rows.len());
    for (i, row) in rows.iter().enumerate() {
        let obj = row
            .as_object()
            .ok_or_else(|| format!("row {i} is not an object (got {})", json_kind_name(row)))?;
        let mut sanitized = serde_json::Map::with_capacity(spec.fields.len());
        for field in &spec.fields {
            let v = obj
                .get(&field.name)
                .ok_or_else(|| format!("row {i} missing required field `{}`", field.name))?;
            if !value_matches_kind(v, field.kind) {
                return Err(format!(
                    "row {i} field `{}` wrong kind: host decode-kind {:?} expects a typed value, got {}",
                    field.name,
                    field.kind,
                    json_kind_name(v)
                ));
            }
            // Most kinds cross verbatim; a typed `Decimal{scale}` is RESHAPED here — the exact digit string
            // (`"12.50"`) becomes the `{ value, scale }` object the VM's `from_json` turns into a real
            // `Value::Decimal` (P23). The string was already validated as a string above; a non-canonical
            // string fails the parse here, fail-closed before continuation dispatch.
            let crossed = match field.kind {
                PostgresReadValueKind::Decimal { scale } => {
                    let s = v.as_str().unwrap_or_default(); // value_matches_kind guaranteed a string
                    let value = parse_decimal(s, scale)
                        .map_err(|e| format!("row {i} field `{}`: {e}", field.name))?;
                    json!({ "value": value, "scale": scale })
                }
                _ => v.clone(),
            };
            sanitized.insert(field.name.clone(), crossed);
        }
        out.push(Value::Object(sanitized));
    }
    Ok(Value::Array(out))
}

/// The declared `<AppRow>` field type the host reconciles its decode-kind against. This mirrors the subset of
/// the Igniter type surface a relational read can land in (P3 §3 matrix). In a boot reconciler it is read
/// from the continuation's compiled IR (`compiler.rs:213` carries `inputs[].type`); for this DB-free proof it
/// is supplied by the harness, standing in for that IR-derived shape (verdict: harness-proven — see doc).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum AppFieldType {
    String,
    Text,
    Integer,
    Bool,
    /// `Decimal[scale]` — the typed exact-money landing (P23). The scale is part of the type, so a host
    /// `Decimal{scale}` is assignable only when the scales match exactly.
    Decimal(u32),
    /// `Map[String, Unknown]` — the v0 landing for a `Json` column.
    MapUnknown,
    /// `Collection[String]` — the v0 landing for an `Array` column.
    CollectionString,
}

/// Is a host decode-kind assignable to a declared `<AppRow>` field type? The P3 §3 assignability matrix,
/// mirroring the language's own `text_arg_compatible` rule (String accepted where Text is expected). A typed
/// `Decimal{scale}` host kind is assignable to an app `Decimal[N]` field ONLY when the scales are equal —
/// a scale mismatch (or a display-only `DecimalString` against a typed `Decimal[N]`) fails closed as drift.
fn kind_assignable(kind: PostgresReadValueKind, ty: AppFieldType) -> bool {
    use AppFieldType as T;
    use PostgresReadValueKind as K;
    match (kind, ty) {
        (K::Text, T::String) | (K::Text, T::Text) => true,
        (K::Integer, T::Integer) => true,
        (K::Boolean, T::Bool) => true,
        (K::DecimalString, T::String) | (K::DecimalString, T::Text) => true,
        (K::Decimal { scale }, T::Decimal(app_scale)) => scale == app_scale,
        (K::Timestamp, T::String) | (K::Timestamp, T::Text) => true,
        (K::Json, T::MapUnknown) | (K::Json, T::String) => true,
        (K::Array, T::CollectionString) => true,
        _ => false,
    }
}

/// Reconcile the host projection spec against the app's declared `<AppRow>` shape (the P3 §3 drift gate).
/// Every declared app field must be (1) covered by a projected, host-typed field, and (2) of a type the host
/// decode-kind is assignable to. A failure is `ProjectionSchemaDrift` — a structural mismatch between the
/// host schema authority and the app row type, i.e. a *deploy-time* fault. v0 surfaces it as a stable host
/// error string; wiring it into the runner `DiagCode` set so it fails the listener *before bind* (P3 §5) is
/// the named P7 boot-reconciliation follow-on. Either way it never reaches app business logic.
pub fn reconcile_projection(
    spec: &ProjectionSpec,
    approw: &[(String, AppFieldType)],
) -> Result<(), String> {
    for (name, ty) in approw {
        let field = spec.fields.iter().find(|f| &f.name == name).ok_or_else(|| {
            format!("ProjectionSchemaDrift: app row field `{name}` is not covered by the host projection")
        })?;
        if !kind_assignable(field.kind, *ty) {
            return Err(format!(
                "ProjectionSchemaDrift: host decode-kind {:?} for `{name}` is not assignable to app field type {:?}",
                field.kind, ty
            ));
        }
    }
    Ok(())
}

/// Build the `DatasetMeta { source, count, truncated }` provenance sidecar (P3 §4). It crosses as a sibling
/// continuation input beside `rows`. `truncated` is the executor's `row_limit_clamped` signal (drives a
/// "load more" UX); `effective_limit` stays host-only by design. A fixed (non-generic) record — `Dataset[T]`
/// awaits user generics.
pub fn build_dataset_meta(source: &str, count: i64, truncated: bool) -> Value {
    json!({ "source": source, "count": count, "truncated": truncated })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn typed_policy() -> PostgresReadPolicy {
        use PostgresReadValueKind::*;
        PostgresReadPolicy::new(100).allow_source_typed(
            "todos",
            &[
                ("id", Text),
                ("account_id", Text),
                ("title", Text),
                ("done", Boolean),
                ("rank", Integer),
            ],
        )
    }

    fn projection() -> Vec<String> {
        ["id", "account_id", "title", "done", "rank"]
            .iter()
            .map(|s| s.to_string())
            .collect()
    }

    fn good_row() -> Value {
        json!({"id": "todo-1", "account_id": "acct-7", "title": "Buy milk", "done": false, "rank": 10})
    }

    fn approw() -> Vec<(String, AppFieldType)> {
        vec![
            ("id".into(), AppFieldType::String),
            ("account_id".into(), AppFieldType::String),
            ("title".into(), AppFieldType::String),
            ("done".into(), AppFieldType::Bool),
            ("rank".into(), AppFieldType::Integer),
        ]
    }

    #[test]
    fn materializes_total_typed_rows_and_drops_extras() {
        let spec = ProjectionSpec::from_policy(&typed_policy(), "todos", &projection());
        let mut row = good_row();
        row.as_object_mut()
            .unwrap()
            .insert("secret".into(), json!("leak")); // extra host field
        let out = materialize_rows(&[row], &spec).unwrap();
        let arr = out.as_array().unwrap();
        assert_eq!(arr.len(), 1);
        let obj = arr[0].as_object().unwrap();
        assert_eq!(
            obj.len(),
            5,
            "exactly the 5 projected fields, extra dropped"
        );
        assert_eq!(obj["done"], json!(false), "Bool preserved as Bool");
        assert_eq!(obj["rank"], json!(10), "Integer preserved as Integer");
        assert!(!obj.contains_key("secret"));
    }

    #[test]
    fn missing_required_field_is_refused() {
        let spec = ProjectionSpec::from_policy(&typed_policy(), "todos", &projection());
        let mut row = good_row();
        row.as_object_mut().unwrap().remove("done");
        let err = materialize_rows(&[row], &spec).unwrap_err();
        assert!(err.contains("missing required field `done`"), "{err}");
    }

    #[test]
    fn wrong_scalar_kind_is_refused() {
        let spec = ProjectionSpec::from_policy(&typed_policy(), "todos", &projection());
        // `done` declared Boolean but the row carries the *string* "false" — the P2 silent-wrong hazard.
        let mut row = good_row();
        row.as_object_mut()
            .unwrap()
            .insert("done".into(), json!("false"));
        let err = materialize_rows(&[row], &spec).unwrap_err();
        assert!(err.contains("`done` wrong kind"), "{err}");

        // `rank` declared Integer but stringified — also refused (proves Integer is not a stringly field).
        let mut row2 = good_row();
        row2.as_object_mut()
            .unwrap()
            .insert("rank".into(), json!("10"));
        let err2 = materialize_rows(&[row2], &spec).unwrap_err();
        assert!(err2.contains("`rank` wrong kind"), "{err2}");
    }

    #[test]
    fn null_for_non_nullable_is_refused_like_missing() {
        let spec = ProjectionSpec::from_policy(&typed_policy(), "todos", &projection());
        let mut row = good_row();
        row.as_object_mut()
            .unwrap()
            .insert("title".into(), Value::Null);
        let err = materialize_rows(&[row], &spec).unwrap_err();
        assert!(
            err.contains("`title` wrong kind") && err.contains("null"),
            "{err}"
        );
    }

    #[test]
    fn reconcile_matches_when_kinds_assignable() {
        let spec = ProjectionSpec::from_policy(&typed_policy(), "todos", &projection());
        assert!(reconcile_projection(&spec, &approw()).is_ok());
    }

    #[test]
    fn reconcile_detects_kind_drift() {
        // Host decodes `done` as Text, but the app declares `done : Bool` — structural drift (P3 §3).
        use PostgresReadValueKind::*;
        let drift_policy = PostgresReadPolicy::new(100).allow_source_typed(
            "todos",
            &[
                ("id", Text),
                ("account_id", Text),
                ("title", Text),
                ("done", Text), // ← wrong: app wants Bool
                ("rank", Integer),
            ],
        );
        let spec = ProjectionSpec::from_policy(&drift_policy, "todos", &projection());
        let err = reconcile_projection(&spec, &approw()).unwrap_err();
        assert!(err.starts_with("ProjectionSchemaDrift"), "{err}");
        assert!(err.contains("`done`"), "{err}");
    }

    #[test]
    fn reconcile_detects_uncovered_app_field() {
        // The app declares a field the host does not project at all.
        let spec = ProjectionSpec::from_policy(&typed_policy(), "todos", &projection());
        let mut want = approw();
        want.push(("nickname".into(), AppFieldType::String));
        let err = reconcile_projection(&spec, &want).unwrap_err();
        assert!(
            err.contains("`nickname`") && err.contains("not covered"),
            "{err}"
        );
    }

    #[test]
    fn dataset_meta_shape() {
        let meta = build_dataset_meta("todos", 2, true);
        assert_eq!(meta["source"], json!("todos"));
        assert_eq!(meta["count"], json!(2));
        assert_eq!(meta["truncated"], json!(true));
    }
}
