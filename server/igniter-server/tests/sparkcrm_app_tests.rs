//! Offline SparkCRM ServerApp normalization + key-extraction proofs (SHADOW-P2). Machine-free.
//!
//! These exercise `SparkCrmApp::call` directly (no socket, no machine): path→target mapping, input
//! normalization, duplicate-key extraction precedence, keyless 400, and the no-privileged-identity
//! invariant on decisions.

use igniter_server::protocol::{ServerApp, ServerDecision};
use serde_json::{json, Value};

// The SparkCRM-shaped app is a TEST FIXTURE (not part of the core server surface, P6).
#[path = "fixtures/sparkcrm_app.rs"]
mod sparkcrm_fixture;
use sparkcrm_fixture::{payloads as fx, SparkCrmApp};

fn req(path: &str, headers: &[(&str, &str)], body: Value) -> igniter_server::protocol::ServerRequest {
    let mut r = igniter_server::protocol::ServerRequest::new("POST", path, body);
    for (k, v) in headers {
        r.headers.insert(k.to_string(), v.to_string());
    }
    // mirror the parser: correlation_id/idempotency_key are promoted from headers.
    r.correlation_id = r.headers.get("x-correlation-id").cloned();
    r.idempotency_key = r.headers.get("idempotency-key").cloned();
    r
}

/// Pull `(target, input, idempotency_key)` out of an `InvokeEffect`, or panic with the decision.
fn invoke_effect(d: &ServerDecision) -> (&str, &Value, &Option<String>) {
    match d {
        ServerDecision::InvokeEffect { target, input, idempotency_key, .. } => (target.as_str(), input, idempotency_key),
        other => panic!("expected InvokeEffect, got {other:?}"),
    }
}

#[test]
fn test_sparkcrm_lead_intake_normalization() {
    let d = SparkCrmApp.call(req("/webhook/leads", &[], fx::lead_intake()));
    let (target, input, key) = invoke_effect(&d);
    assert_eq!(target, "lead-intake");
    assert_eq!(input["lead_id"], json!("lead_9982"));
    assert_eq!(input["base"], json!(1500), "base derived from value_cents");
    assert_eq!(key.as_deref(), Some("AUC-LEAD-1001"), "body auction_id is the canonical key");
}

#[test]
fn test_target_mapping_bids_and_status() {
    let (t_bid, in_bid, _) = {
        let d = SparkCrmApp.call(req("/webhook/bids", &[], fx::lead_bid()));
        let (t, i, k) = invoke_effect(&d);
        (t.to_string(), i.clone(), k.clone())
    };
    assert_eq!(t_bid, "lead-bid");
    assert_eq!(in_bid["bid_amount_cents"], json!(4200));
    assert_eq!(in_bid["base"], json!(4200), "bid base = bid_amount_cents");

    let d = SparkCrmApp.call(req("/webhook/status", &[], fx::lead_status()));
    let (t_stat, in_stat, _) = invoke_effect(&d);
    assert_eq!(t_stat, "lead-status");
    assert_eq!(in_stat["status"], json!("converted"));

    // unknown path → 404 (routing lives in the app).
    let d = SparkCrmApp.call(req("/webhook/unknown", &[], json!({})));
    assert!(matches!(d, ServerDecision::Respond { .. }));
}

#[test]
fn test_duplicate_key_extraction_precedence() {
    // 1. x-auction-id header WINS over body auction_id.
    let d = SparkCrmApp.call(req("/webhook/leads", &[("x-auction-id", "HDR-AUC")], fx::lead_intake()));
    assert_eq!(invoke_effect(&d).2.as_deref(), Some("HDR-AUC"));

    // 2. body auction_id when no header.
    let d = SparkCrmApp.call(req("/webhook/leads", &[], fx::lead_intake()));
    assert_eq!(invoke_effect(&d).2.as_deref(), Some("AUC-LEAD-1001"));

    // 3. deterministic composite when no auction id at all.
    let d1 = SparkCrmApp.call(req("/webhook/leads", &[], fx::lead_composite_only()));
    let d2 = SparkCrmApp.call(req("/webhook/leads", &[], fx::lead_composite_only()));
    let k1 = invoke_effect(&d1).2.clone().unwrap();
    let k2 = invoke_effect(&d2).2.clone().unwrap();
    assert!(k1.starts_with("comp-"), "composite key used, got {k1}");
    assert_eq!(k1, k2, "composite key is deterministic for identical stable fields");

    // 4. idempotency-key fallback when nothing else resolves.
    let d = SparkCrmApp.call(req("/webhook/leads", &[("idempotency-key", "IDEM-9")], fx::lead_keyless()));
    assert_eq!(invoke_effect(&d).2.as_deref(), Some("IDEM-9"));
}

#[test]
fn test_keyless_webhook_refusal_is_400() {
    let d = SparkCrmApp.call(req("/webhook/leads", &[], fx::lead_keyless()));
    match d {
        ServerDecision::Respond { response } => {
            assert_eq!(response.status, 400, "keyless webhook → 400");
            assert_eq!(response.body["error"], json!("missing duplicate key"));
        }
        other => panic!("expected Respond 400, got {other:?}"),
    }
}

#[test]
fn test_decisions_carry_no_privileged_effect_identity() {
    for (path, body) in [
        ("/webhook/leads", fx::lead_intake()),
        ("/webhook/bids", fx::lead_bid()),
        ("/webhook/status", fx::lead_status()),
    ] {
        let d = SparkCrmApp.call(req(path, &[], body));
        let encoded = serde_json::to_value(&d).unwrap();
        assert_eq!(encoded["kind"], json!("invoke_effect"));
        assert!(encoded.get("capability_id").is_none(), "no capability_id in {path}");
        assert!(encoded.get("operation").is_none(), "no operation in {path}");
        assert!(encoded.get("scope").is_none(), "no scope in {path}");
        // the canonical key is present; the target is a logical inbound name.
        assert!(encoded["idempotency_key"].is_string());
        assert!(encoded["target"].as_str().unwrap().starts_with("lead-"));
    }
}
