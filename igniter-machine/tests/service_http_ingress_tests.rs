//! LAB-MACHINE-SERVICE-HTTP-INGRESS-P6 — HTTP ingress front door for production pools.
//!
//! The inbound edge: vendor webhook → passport → route → production pool/ServiceRecipe →
//! invoke (real capsule activation) → HTTP response → audit. Local loopback only; no public
//! internet / SparkCRM creds / outbound effect / messenger in the hot path.

use igniter_machine::backend::{InMemoryBackend, TBackend};
use igniter_machine::capability::CapabilityPassport;
use igniter_machine::clock::{ClockProvider, FixedClock};
use igniter_machine::coordination::{
    AgentIdentity, AgentKind, AgentStatus, CoordinationHub, PoolRefusal, PoolRight, PoolVisibility,
    ServiceRecipe, COORD_AUDIT_STORE,
};
use igniter_machine::ingress::{map_refusal, serve_once, IngressRequest, IngressRouter};
use igniter_machine::machine::IgniterMachine;
use serde_json::{json, Value};
use std::collections::HashMap;
use std::sync::Arc;
use tokio::io::{AsyncReadExt, AsyncWriteExt};

fn rt() -> tokio::runtime::Runtime {
    tokio::runtime::Builder::new_current_thread().enable_all().build().unwrap()
}
fn clock() -> Arc<dyn ClockProvider> {
    Arc::new(FixedClock::new(100.0))
}

const SCOPES: &[&str] = &["create_pool", "import_capsule", "activate_capsule", "grant_access", "admin_pool", "accept_recipe", "invoke"];

fn passport(subject: &str) -> CapabilityPassport {
    CapabilityPassport {
        subject: subject.to_string(),
        capability_id: "coordination".to_string(),
        scopes: SCOPES.iter().map(|s| s.to_string()).collect(),
        issued_at: 0.0,
        expires_at: Some(1_000_000.0),
        revoked: false,
        evidence_digest: "sig".to_string(),
    }
}

async fn register(h: &mut CoordinationHub, id: &str, kind: AgentKind) {
    h.register_agent(AgentIdentity { agent_id: id.into(), kind, label: id.into(), status: AgentStatus::Active, registered_at: 0.0 }).await.unwrap();
}

async fn add_capsule_bytes() -> Vec<u8> {
    let m = IgniterMachine::new(None, "in_memory").unwrap();
    let src = "contract Add { input a: Integer  input b: Integer  compute sum = a + b  output sum: Integer }";
    m.load_contract_source(src, "Add").unwrap();
    m.checkpoint_bytes().await.unwrap()
}

fn recipe(digest: &str) -> ServiceRecipe {
    ServiceRecipe {
        recipe_id: "r1".into(), capsule_digest: digest.into(), entry_contract: "Add".into(),
        input_schema_digest: None, capability_bindings: vec![], required_scopes: vec!["invoke".into()],
        receipt_policy: "audit".into(), retry_policy_ref: None, pool_sizing: 1,
        created_by: "alice".into(), accepted_by: None, accepted_at: None,
    }
}

/// A hub with a live production service `svc` (real Add capsule) invokable by `vendor:acme`.
async fn prod_hub() -> (CoordinationHub, Arc<dyn TBackend>) {
    let audit: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
    let mut h = CoordinationHub::new(audit.clone(), clock());
    register(&mut h, "alice", AgentKind::Agent).await;
    register(&mut h, "dev", AgentKind::Developer).await;
    register(&mut h, "vendor:acme", AgentKind::RuntimeActor).await;
    h.create_pool(&passport("alice"), "svc", "candidate", PoolVisibility::Private).await.unwrap();
    let bytes = add_capsule_bytes().await;
    let cref = h.add_capsule(&passport("alice"), "svc", bytes, vec![]).await.unwrap();
    h.accept_recipe(&passport("dev"), "svc", recipe(&cref.capsule_id)).await.unwrap();
    h.grant(&passport("dev"), "svc", "vendor:acme", PoolRight::ActivateCapsule).await.unwrap();
    (h, audit)
}

fn router() -> IngressRouter {
    let mut r = IngressRouter::new();
    r.route("/webhook/acme", "svc");
    r.token("vendortoken", passport("vendor:acme"));
    r
}

fn req(method: &str, path: &str, token: Option<&str>, body: Value, extra: &[(&str, &str)]) -> IngressRequest {
    let mut headers = HashMap::new();
    if let Some(t) = token {
        headers.insert("authorization".to_string(), format!("Bearer {}", t));
    }
    for (k, v) in extra {
        headers.insert(k.to_string(), v.to_string());
    }
    IngressRequest { method: method.to_string(), path: path.to_string(), headers, body }
}

async fn audit_events(audit: &Arc<dyn TBackend>) -> Vec<Value> {
    audit.all_facts().await.unwrap().into_iter().filter(|f| f.store == COORD_AUDIT_STORE).map(|f| f.value).collect()
}

// 1,4,5: a webhook invokes the capsule and returns 200 + the result body
#[test]
fn webhook_invokes_capsule_returns_200() {
    rt().block_on(async {
        let (h, _a) = prod_hub().await;
        let r = router();
        let resp = r.handle(&h, &req("POST", "/webhook/acme", Some("vendortoken"), json!({"a": 2, "b": 3}), &[])).await;
        assert_eq!(resp.status, 200);
        assert_eq!(resp.body, json!(5));
    });
}

// 2,6: invalid passport → 401, refused BEFORE activation (no invoke audit)
#[test]
fn invalid_passport_refused_before_activation() {
    rt().block_on(async {
        let (h, audit) = prod_hub().await;
        let r = router();
        let resp = r.handle(&h, &req("POST", "/webhook/acme", Some("BADTOKEN"), json!({"a": 1, "b": 1}), &[])).await;
        assert_eq!(resp.status, 401);
        let evs = audit_events(&audit).await;
        assert!(!evs.iter().any(|e| e["operation"] == "invoke"), "activation must not be reached");
        assert!(evs.iter().any(|e| e["operation"] == "ingress" && e["outcome"] == "denied"));
    });
}

// 3: route selects the pool; an unknown path → 404
#[test]
fn unknown_route_404() {
    rt().block_on(async {
        let (h, _a) = prod_hub().await;
        let r = router();
        let resp = r.handle(&h, &req("POST", "/nope", Some("vendortoken"), json!({}), &[])).await;
        assert_eq!(resp.status, 404);
    });
}

// 7: a non-production pool cannot be invoked
#[test]
fn non_production_pool_refused() {
    rt().block_on(async {
        let (h, _a) = prod_hub().await;
        // a second pool that was never signed into production
        let mut h = h;
        register(&mut h, "carol", AgentKind::Agent).await;
        h.create_pool(&passport("carol"), "draft", "draft", PoolVisibility::Private).await.unwrap();
        let mut r = router();
        r.route("/webhook/draft", "draft");
        let resp = r.handle(&h, &req("POST", "/webhook/draft", Some("vendortoken"), json!({"a": 1, "b": 1}), &[])).await;
        assert_eq!(resp.status, 404); // no accepted recipe / not production
    });
}

// 8: audit facts written for both accepted and denied ingress
#[test]
fn audit_for_accepted_and_denied() {
    rt().block_on(async {
        let (h, audit) = prod_hub().await;
        let r = router();
        r.handle(&h, &req("POST", "/webhook/acme", Some("vendortoken"), json!({"a": 1, "b": 1}), &[])).await;
        r.handle(&h, &req("POST", "/webhook/acme", Some("BADTOKEN"), json!({}), &[])).await;
        let evs = audit_events(&audit).await;
        assert!(evs.iter().any(|e| e["operation"] == "ingress" && e["outcome"] == "allowed"));
        assert!(evs.iter().any(|e| e["operation"] == "ingress" && e["outcome"] == "denied"));
    });
}

// 9: messenger is not used in the hot path
#[test]
fn no_messenger_in_hot_path() {
    rt().block_on(async {
        let (h, audit) = prod_hub().await;
        let r = router();
        r.handle(&h, &req("POST", "/webhook/acme", Some("vendortoken"), json!({"a": 4, "b": 4}), &[])).await;
        let all = audit.all_facts().await.unwrap();
        assert!(all.iter().all(|f| f.store != "__messenger__"));
    });
}

// 10: capsule digest mismatch maps to 409 (mapping-level; live refusal proven in P5)
#[test]
fn capsule_digest_mismatch_maps_409() {
    let (status, _) = map_refusal(&PoolRefusal::Invalid("capsule digest mismatch".to_string()));
    assert_eq!(status, 409);
    let (status, _) = map_refusal(&PoolRefusal::NotGranted);
    assert_eq!(status, 403);
}

// 11: correlation id + idempotency key recorded on the audit fact
#[test]
fn correlation_and_idempotency_recorded() {
    rt().block_on(async {
        let (h, audit) = prod_hub().await;
        let r = router();
        r.handle(&h, &req("POST", "/webhook/acme", Some("vendortoken"), json!({"a": 1, "b": 1}),
            &[("x-correlation-id", "corr-123"), ("idempotency-key", "idem-9")])).await;
        let evs = audit_events(&audit).await;
        let ing = evs.iter().find(|e| e["operation"] == "ingress").unwrap();
        assert_eq!(ing["correlation_id"], json!("corr-123"));
        assert_eq!(ing["idempotency_key"], json!("idem-9"));
    });
}

// 1,5,12: a REAL loopback HTTP/1.1 round-trip (127.0.0.1 only)
#[test]
fn real_loopback_roundtrip() {
    rt().block_on(async {
        let (h, _a) = prod_hub().await;
        let r = router();
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();

        let server = serve_once(&listener, &r, &h);
        let client = async {
            let mut s = tokio::net::TcpStream::connect(addr).await.unwrap();
            let body = json!({"a": 20, "b": 22}).to_string();
            let request = format!(
                "POST /webhook/acme HTTP/1.1\r\nHost: localhost\r\nAuthorization: Bearer vendortoken\r\nContent-Type: application/json\r\nContent-Length: {}\r\n\r\n{}",
                body.len(), body
            );
            s.write_all(request.as_bytes()).await.unwrap();
            let mut resp = Vec::new();
            s.read_to_end(&mut resp).await.unwrap();
            String::from_utf8_lossy(&resp).to_string()
        };
        let (_srv, response) = tokio::join!(server, client);
        assert!(response.starts_with("HTTP/1.1 200 OK"), "got: {}", response);
        assert!(response.trim_end().ends_with("42"), "body should be 42, got: {}", response);
    });
}
