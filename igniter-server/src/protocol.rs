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
        Self { status, headers, body }
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum ServerDecision {
    Respond {
        response: ServerResponse,
    },
    Invoke {
        contract: String,
        input: Value,
        correlation_id: Option<String>,
        idempotency_key: Option<String>,
    },
}

pub trait ServerApp {
    fn call(&self, request: ServerRequest) -> ServerDecision;
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn request_round_trips_as_json() {
        let mut req = ServerRequest::new("POST", "/webhook/callrail", json!({"event": "call"}));
        req.headers.insert("authorization".into(), "Bearer redacted".into());
        req.correlation_id = Some("corr-1".into());
        req.idempotency_key = Some("event-1".into());

        let encoded = serde_json::to_string(&req).unwrap();
        let decoded: ServerRequest = serde_json::from_str(&encoded).unwrap();

        assert_eq!(decoded, req);
        assert_eq!(decoded.protocol, PROTOCOL_VERSION);
    }

    #[test]
    fn app_decision_is_protocol_data_not_server_config() {
        let decision = ServerDecision::Invoke {
            contract: "HandleWebhook".into(),
            input: json!({"path": "/webhook/callrail"}),
            correlation_id: Some("corr-1".into()),
            idempotency_key: Some("event-1".into()),
        };

        let encoded = serde_json::to_value(&decision).unwrap();

        assert_eq!(encoded["kind"], json!("invoke"));
        assert_eq!(encoded["contract"], json!("HandleWebhook"));
        assert!(encoded.get("route_table").is_none());
    }

    #[test]
    fn response_helper_sets_json_content_type() {
        let response = ServerResponse::json(202, json!({"accepted": true}));

        assert_eq!(response.status, 202);
        assert_eq!(response.headers.get("content-type").map(String::as_str), Some("application/json"));
    }
}
