//! LAB-IGNITER-COMPILER-TYPE-IR-ENUM-P5
//!
//! A narrow, strongly-typed internal model for compiler type IR.
//!
//! Historically the typechecker carried semantic type facts as raw
//! `serde_json::Value` (`{"name": ..., "params": [...]}`). That representation
//! let invalid states exist: a non-string `name`, a `params` that is not an
//! array, or any object that merely happened to contain a `name` key. Those
//! could silently degrade to `Unknown` or pass through unvalidated
//! (readiness packet risk #4), and generic parameters were easy to erase to a
//! name-only comparison (risk #2).
//!
//! `IgType` makes those invalid states unrepresentable: a parsed type always
//! has a `String` name and a real `Vec` of parameters. The JSON `{name, params}`
//! shape remains the public SIR boundary — `from_json_lossy` / `to_json` are the
//! only seam, so SIR output is preserved while the *interpretation* of a type
//! lives in one typed place.
//!
//! Scope of this slice (see card `LAB-IGNITER-COMPILER-TYPE-IR-ENUM-P5`):
//! the typechecker helper boundary (`type_ir`, `get_param`, `type_name`,
//! `decimal_scale`, `structurally_assignable`, `unknown_or_unknown_bearing`,
//! `type_display`) and the variant-field construction comparison route through
//! this enum. Parser `TypeRef`, the stored `serde_json::Value` SIR schema, the
//! emitter, and the VM are intentionally untouched.

use serde_json::Value;

/// Sentinel name for an unknown/absent type. Kept as a `&str` constant so the
/// "Unknown accepts any" (D3) and "actual Unknown rejected" (D2) rules read the
/// same here as in the legacy string comparisons.
pub(crate) const UNKNOWN: &str = "Unknown";

/// Strongly-typed internal type representation.
///
/// This is *internal* to the typechecker. Conversions to/from
/// `serde_json::Value` preserve the existing `{name, params}` JSON shape so SIR
/// consumers, the emitter, and the VM see no change.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum IgType {
    /// Unknown / absent type. Serializes as `{"name": "Unknown", "params": []}`.
    Unknown,
    /// A concrete type with no type parameters, e.g. `Integer`, `Text`.
    Named(String),
    /// A concrete type carrying one or more type parameters, e.g.
    /// `Collection[Integer]`, `Decimal[2]`.
    Generic { name: String, params: Vec<IgType> },
}

impl IgType {
    /// Normalize an arbitrary type-IR JSON value into a typed `IgType`.
    ///
    /// This mirrors the legacy `type_ir` helper exactly for the inputs that
    /// occur in practice, and fails closed on the malformed inputs the legacy
    /// helper let slip through:
    /// - a bare JSON string `"Integer"` becomes `Named("Integer")`;
    /// - an object with a string `name` becomes `Named`/`Generic`, recursing
    ///   into `params`;
    /// - an object whose `name` is missing or not a string, or any other JSON
    ///   value, becomes `Unknown`;
    /// - a `params` value that is not an array is treated as no parameters.
    pub(crate) fn from_json_lossy(value: &Value) -> IgType {
        if let Some(obj) = value.as_object() {
            let name = match obj.get("name").and_then(|n| n.as_str()) {
                Some(name) => name,
                None => return IgType::Unknown,
            };
            let params: Vec<IgType> = obj
                .get("params")
                .and_then(|p| p.as_array())
                .map(|arr| arr.iter().map(IgType::from_json_lossy).collect())
                .unwrap_or_default();
            return IgType::with_params(name, params);
        }
        if let Some(s) = value.as_str() {
            return IgType::with_params(s, Vec::new());
        }
        IgType::Unknown
    }

    /// Build the most specific variant for a `(name, params)` pair.
    fn with_params(name: &str, params: Vec<IgType>) -> IgType {
        if name == UNKNOWN && params.is_empty() {
            IgType::Unknown
        } else if params.is_empty() {
            IgType::Named(name.to_string())
        } else {
            IgType::Generic {
                name: name.to_string(),
                params,
            }
        }
    }

    /// Render back to the public `{name, params}` JSON shape.
    pub(crate) fn to_json(&self) -> Value {
        let mut map = serde_json::Map::new();
        map.insert("name".to_string(), Value::String(self.name().to_string()));
        let params: Vec<Value> = self.params().iter().map(IgType::to_json).collect();
        map.insert("params".to_string(), Value::Array(params));
        Value::Object(map)
    }

    /// The outer type name. `Unknown` reports `"Unknown"`.
    pub(crate) fn name(&self) -> &str {
        match self {
            IgType::Unknown => UNKNOWN,
            IgType::Named(name) => name,
            IgType::Generic { name, .. } => name,
        }
    }

    /// The type parameters (empty for `Unknown` and `Named`).
    pub(crate) fn params(&self) -> &[IgType] {
        match self {
            IgType::Generic { params, .. } => params,
            _ => &[],
        }
    }

    /// True when this is the unknown sentinel (by variant or by name).
    pub(crate) fn is_unknown(&self) -> bool {
        self.name() == UNKNOWN
    }

    /// True when this type is `Unknown` or contains `Unknown` at any param
    /// depth. Mirrors the legacy `unknown_or_unknown_bearing` helper.
    pub(crate) fn is_unknown_bearing(&self) -> bool {
        self.is_unknown() || self.params().iter().any(IgType::is_unknown_bearing)
    }

    /// Decimal scale recovered from the first type parameter, e.g. `Decimal[2]`
    /// yields `"2"`. Bare `Decimal` (or an unknown scale param) yields `"0"`.
    /// Mirrors the legacy `decimal_scale` helper.
    pub(crate) fn decimal_scale(&self) -> String {
        self.params()
            .first()
            .map(|p| p.name().to_string())
            .filter(|name| name != UNKNOWN)
            .unwrap_or_else(|| "0".to_string())
    }

    /// Human-readable display form, e.g. `Collection[Integer]`. Mirrors the
    /// legacy `type_display` helper (comma-joined, no spaces).
    pub(crate) fn display(&self) -> String {
        let params = self.params();
        if params.is_empty() {
            return self.name().to_string();
        }
        let rendered: Vec<String> = params.iter().map(IgType::display).collect();
        format!("{}[{}]", self.name(), rendered.join(","))
    }

    /// Structural assignability: is `actual` assignable to `expected`?
    ///
    /// Preserves the established rules:
    /// - D3: `expected` Unknown accepts any actual;
    /// - D2: `actual` Unknown is rejected (unless expected is Unknown);
    /// - outer names must match;
    /// - parameter arity must match and every parameter must be assignable.
    pub(crate) fn structurally_assignable(actual: &IgType, expected: &IgType) -> bool {
        if expected.is_unknown() {
            return true; // D3: expected Unknown accepts any
        }
        if actual.is_unknown() {
            return false; // D2: actual Unknown always rejected
        }
        if canonical_scalar_name(actual.name()) != canonical_scalar_name(expected.name()) {
            return false;
        }
        let actual_params = actual.params();
        let expected_params = expected.params();
        if actual_params.len() != expected_params.len() {
            return false;
        }
        actual_params
            .iter()
            .zip(expected_params.iter())
            .all(|(a, e)| IgType::structurally_assignable(a, e))
    }
}

/// Canonical scalar name for assignability. `String` and `Text` are the SAME scalar in Igniter —
/// string literals infer the tag `String`, while declarations (`input id : Text`) use `Text`, and
/// the typechecker already treats the two literal tags interchangeably. So a string-literal argument
/// (`String`) is assignable to a `Text` input. Without this, the per-argument structural checks
/// (`call_contract` P8, user-`def` P6, record-literal field P7) would falsely reject every literal
/// passed to a `Text` parameter. Only this one alias pair is canonicalized; other scalar names
/// (`Integer`, `Bool`, `Float`, …) match literal tags exactly and need no aliasing.
fn canonical_scalar_name(name: &str) -> &str {
    match name {
        "String" => "Text",
        other => other,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn ig(value: serde_json::Value) -> IgType {
        IgType::from_json_lossy(&value)
    }

    #[test]
    fn collection_integer_not_assignable_to_collection_text() {
        // The name-only mistake this slice closes: both are `Collection`, so a
        // name-only comparison would accept the assignment. The typed model
        // checks the element parameter and rejects it.
        let actual =
            ig(json!({"name": "Collection", "params": [{"name": "Integer", "params": []}]}));
        let expected =
            ig(json!({"name": "Collection", "params": [{"name": "Text", "params": []}]}));
        assert_eq!(
            actual.name(),
            expected.name(),
            "outer names match by design"
        );
        assert!(
            !IgType::structurally_assignable(&actual, &expected),
            "Collection[Integer] must not be assignable to Collection[Text]"
        );
    }

    #[test]
    fn same_generic_is_assignable() {
        let a = ig(json!({"name": "Collection", "params": [{"name": "Integer", "params": []}]}));
        let b = ig(json!({"name": "Collection", "params": [{"name": "Integer", "params": []}]}));
        assert!(IgType::structurally_assignable(&a, &b));
    }

    #[test]
    fn unknown_rules_preserved() {
        let unknown = IgType::Unknown;
        let concrete = ig(json!({"name": "Integer", "params": []}));
        // D3: expected Unknown accepts any.
        assert!(IgType::structurally_assignable(&concrete, &unknown));
        // D2: actual Unknown is rejected against a concrete expected.
        assert!(!IgType::structurally_assignable(&unknown, &concrete));
        // Unknown against Unknown is accepted (D3 fires first).
        assert!(IgType::structurally_assignable(&unknown, &unknown));
    }

    #[test]
    fn param_arity_mismatch_rejected() {
        let bare = ig(json!({"name": "Collection", "params": []}));
        let one = ig(json!({"name": "Collection", "params": [{"name": "Integer", "params": []}]}));
        assert!(!IgType::structurally_assignable(&one, &bare));
        assert!(!IgType::structurally_assignable(&bare, &one));
    }

    #[test]
    fn decimal_scale_round_trips_through_json_and_display() {
        let d2 = ig(json!({"name": "Decimal", "params": [{"name": "2", "params": []}]}));
        assert_eq!(d2.decimal_scale(), "2");
        assert_eq!(d2.display(), "Decimal[2]");
        // Round-trip preserves the public JSON shape.
        assert_eq!(
            d2.to_json(),
            json!({"name": "Decimal", "params": [{"name": "2", "params": []}]})
        );
        // Bare Decimal has scale "0".
        let bare = ig(json!({"name": "Decimal", "params": []}));
        assert_eq!(bare.decimal_scale(), "0");
    }

    #[test]
    fn malformed_json_normalizes_to_unknown() {
        // Non-object, non-string JSON.
        assert_eq!(ig(json!(42)), IgType::Unknown);
        assert_eq!(ig(json!(null)), IgType::Unknown);
        assert_eq!(ig(json!([1, 2, 3])), IgType::Unknown);
        // Object without a string `name`.
        assert_eq!(ig(json!({"name": 7})), IgType::Unknown);
        assert_eq!(ig(json!({"not_name": "Integer"})), IgType::Unknown);
        // Unknown serializes to the canonical sentinel shape.
        assert_eq!(
            IgType::Unknown.to_json(),
            json!({"name": "Unknown", "params": []})
        );
    }

    #[test]
    fn malformed_params_treated_as_no_params() {
        // `params` that is not an array degrades to no parameters rather than
        // silently carrying a malformed value into structural comparison.
        let t = ig(json!({"name": "Collection", "params": "Integer"}));
        assert_eq!(t.params().len(), 0);
        assert_eq!(t.name(), "Collection");
    }

    #[test]
    fn bare_string_wraps_like_legacy_type_ir() {
        // Legacy `type_ir("Integer")` produced `{name:Integer, params:[]}`.
        assert_eq!(ig(json!("Integer")), IgType::Named("Integer".to_string()));
        assert_eq!(
            ig(json!("Integer")).to_json(),
            json!({"name": "Integer", "params": []})
        );
    }

    #[test]
    fn generic_json_shape_is_preserved_round_trip() {
        let value = json!({
            "name": "Collection",
            "params": [{"name": "Decimal", "params": [{"name": "2", "params": []}]}]
        });
        // from_json_lossy -> to_json is the SIR boundary; it must be stable.
        assert_eq!(ig(value.clone()).to_json(), value);
    }

    #[test]
    fn unknown_bearing_detects_nested_unknown() {
        let nested =
            ig(json!({"name": "Collection", "params": [{"name": "Unknown", "params": []}]}));
        assert!(nested.is_unknown_bearing());
        let concrete =
            ig(json!({"name": "Collection", "params": [{"name": "Integer", "params": []}]}));
        assert!(!concrete.is_unknown_bearing());
    }
}
