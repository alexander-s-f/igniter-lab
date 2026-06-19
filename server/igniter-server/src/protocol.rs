use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::BTreeMap;

pub const PROTOCOL_VERSION: &str = "igniter-server.v0";

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ServerRequest {
    pub protocol: String,
    pub method: String,
    pub path: String,
    pub headers: BTreeMap<String, String>,
    pub body: Value,
    pub correlation_id: Option<String>,
    pub idempotency_key: Option<String>,
}

impl ServerRequest {
    pub fn new(method: impl Into<String>, path: impl Into<String>, body: Value) -> Self {
        Self {
            protocol: PROTOCOL_VERSION.to_string(),
            method: method.into(),
            path: path.into(),
            headers: BTreeMap::new(),
            body,
            correlation_id: None,
            idempotency_key: None,
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ServerResponse {
    pub status: u16,
    pub headers: BTreeMap<String, String>,
    pub body: Value,
}

impl ServerResponse {
    pub fn json(status: u16, body: Value) -> Self {
        let mut headers = BTreeMap::new();
        headers.insert("content-type".to_string(), "application/json".to_string());
        Self {
            status,
            headers,
            body,
        }
    }
}

/// What the app decided. This is PROTOCOL DATA, not a host effect: the app names WHICH proven host
/// path to run and the logical `target` + `input` — never HOW an effect runs. A decision deliberately
/// carries NO `capability_id` / `operation` / `scope`: the effect identity comes from the signed
/// `ServiceRecipe` + the host effect passport at execution time (P1 readiness, delta #3). The host
/// maps `target -> pool` (infra); the recipe pins the entry contract.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum ServerDecision {
    /// App answers directly — no machine touch (health, validation, 404).
    Respond { response: ServerResponse },
    /// Host activates one capsule replica (pure, `CoordinationHub::invoke` / `select_replica`).
    Invoke {
        target: String,
        input: Value,
        correlation_id: Option<String>,
        idempotency_key: Option<String>,
    },
    /// Host runs the wire-to-effect bridge (one replica -> one atomic effect + receipt, the proven
    /// P7 `ingress::handle_effect` / `run_write_effect_atomic` path). Execution is the P3 slice.
    InvokeEffect {
        target: String,
        input: Value,
        correlation_id: Option<String>,
        idempotency_key: Option<String>,
    },
}

/// Opaque, app-supplied identity for operator/test visibility (LAB-MACHINE-IGNITER-SERVER-HOT-RELOAD-
/// P4). `digest` is whatever the app chooses (a content hash, a build id, ""); the host never mandates
/// a scheme and never treats identity as authority — it is OBSERVATION only, distinct from the signed
/// recipe / effect passport that actually gate execution.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, Default)]
pub struct AppIdentity {
    pub name: String,
    pub version: String,
    pub digest: String,
}

impl AppIdentity {
    pub fn new(
        name: impl Into<String>,
        version: impl Into<String>,
        digest: impl Into<String>,
    ) -> Self {
        Self {
            name: name.into(),
            version: version.into(),
            digest: digest.into(),
        }
    }
}

pub trait ServerApp {
    fn call(&self, request: ServerRequest) -> ServerDecision;

    /// App identity for hot-reload visibility. Default is anonymous so existing apps need no change;
    /// apps that want to be observable across a swap override it. NOT authority (see `AppIdentity`).
    fn identity(&self) -> AppIdentity {
        AppIdentity::new("anonymous", "0", "")
    }
}

/// An `Arc<A>` is itself a `ServerApp` (delegates to the inner app). This lets an erased, already-built
/// app (`Arc<dyn ServerApp + Send + Sync>` — e.g. an IgWeb package, P5/P7) be composed under wrapper
/// middleware and held by `ReloadableApp`, exactly like a concrete app. Generic ergonomic only — no
/// routing, no behavior change.
impl<A: ServerApp + ?Sized> ServerApp for std::sync::Arc<A> {
    fn call(&self, request: ServerRequest) -> ServerDecision {
        (**self).call(request)
    }
    fn identity(&self) -> AppIdentity {
        (**self).identity()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn request_round_trips_as_json() {
        let mut req = ServerRequest::new("POST", "/webhook/callrail", json!({"event": "call"}));
        req.headers
            .insert("authorization".into(), "Bearer redacted".into());
        req.correlation_id = Some("corr-1".into());
        req.idempotency_key = Some("event-1".into());

        let encoded = serde_json::to_string(&req).unwrap();
        let decoded: ServerRequest = serde_json::from_str(&encoded).unwrap();

        assert_eq!(decoded, req);
        assert_eq!(decoded.protocol, PROTOCOL_VERSION);
    }

    #[test]
    fn invoke_uses_target_not_contract_and_is_protocol_data() {
        let decision = ServerDecision::Invoke {
            target: "demo-target".into(),
            input: json!({"path": "/webhook/demo"}),
            correlation_id: Some("corr-1".into()),
            idempotency_key: Some("event-1".into()),
        };

        let encoded = serde_json::to_value(&decision).unwrap();

        assert_eq!(encoded["kind"], json!("invoke"));
        // P1 delta #1: the app names a logical `target`, never a host `contract`.
        assert_eq!(encoded["target"], json!("demo-target"));
        assert!(encoded.get("contract").is_none());
        // no server-config leak.
        assert!(encoded.get("route_table").is_none());
    }

    #[test]
    fn invoke_effect_round_trips_and_carries_no_effect_identity() {
        let decision = ServerDecision::InvokeEffect {
            target: "demo-target".into(),
            input: json!({"event": "demo"}),
            correlation_id: Some("corr-2".into()),
            idempotency_key: Some("event-2".into()),
        };

        let encoded = serde_json::to_value(&decision).unwrap();
        let decoded: ServerDecision = serde_json::from_value(encoded.clone()).unwrap();

        assert_eq!(decoded, decision);
        assert_eq!(encoded["kind"], json!("invoke_effect"));
        assert_eq!(encoded["target"], json!("demo-target"));
        // P1 delta #3: the app decision must NEVER carry the effect identity — that comes from the
        // signed recipe + host effect passport, never from app code.
        assert!(encoded.get("capability_id").is_none());
        assert!(encoded.get("operation").is_none());
        assert!(encoded.get("scope").is_none());
    }

    #[test]
    fn response_helper_sets_json_content_type() {
        let response = ServerResponse::json(202, json!({"accepted": true}));

        assert_eq!(response.status, 202);
        assert_eq!(
            response.headers.get("content-type").map(String::as_str),
            Some("application/json")
        );
    }
}
