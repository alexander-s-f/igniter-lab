//! LAB-MACHINE-SERVICE-WIRE-EFFECT-P11 — real loopback HTTP × handle_effect.
//!
//! The last in-lab wire: a real `127.0.0.1` HTTP POST drives the full contour —
//! ```text
//! HTTP POST → ingress parser → duplicate policy → replica selection → capsule intent
//!          → effect executor → receipt → real HTTP response
//! ```
//! Local loopback only; fake effect executor; no live SparkCRM.

use igniter_machine::backend::{InMemoryBackend, TBackend};
use igniter_machine::capability::{CapabilityExecutorRegistry, CapabilityPassport};
use igniter_machine::clock::{ClockProvider, FixedClock};
use igniter_machine::coordination::{
    AgentIdentity, AgentKind, AgentStatus, CoordinationHub, DuplicatePolicy, PoolRight,
    PoolVisibility, ServiceRecipe, COORD_AUDIT_STORE,
};
use igniter_machine::ingress::{serve_once_effect, EffectBridgeConfig, IngressRouter};
use igniter_machine::machine::IgniterMachine;
use igniter_machine::write::{FakeWriteExecutor, WriteBehavior};
use serde_json::{json, Value};
use std::sync::Arc;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};

const CAP: &str = "IO.SparkCRM";

fn rt() -> tokio::runtime::Runtime {
    tokio::runtime::Builder::new_current_thread().enable_all().build().unwrap()
}
fn clock() -> Arc<dyn ClockProvider> {
    Arc::new(FixedClock::new(100.0))
}

fn cpass(subject: &str, cap: &str, scopes: &[&str]) -> CapabilityPassport {
    CapabilityPassport {
        subject: subject.to_string(), capability_id: cap.to_string(),
        scopes: scopes.iter().map(|s| s.to_string()).collect(),
        issued_at: 0.0, expires_at: Some(1_000_000.0), revoked: false, evidence_digest: "sig".to_string(),
    }
}
fn vendor() -> CapabilityPassport {
    cpass("vendor:acme", "coordination", &["create_pool", "import_capsule", "activate_capsule", "grant_access", "accept_recipe", "invoke"])
}

async fn register(h: &mut CoordinationHub, id: &str, kind: AgentKind) {
    h.register_agent(AgentIdentity { agent_id: id.into(), kind, label: id.into(), status: AgentStatus::Active, registered_at: 0.0 }).await.unwrap();
}
async fn offer_bytes() -> Vec<u8> {
    let m = IgniterMachine::new(None, "in_memory").unwrap();
    m.load_contract_source("contract Offer { input base: Integer  input attempt: Integer  compute code = base + attempt  output code: Integer }", "Offer").unwrap();
    m.checkpoint_bytes().await.unwrap()
}
fn policy(mode: &str, max_fresh: u32) -> DuplicatePolicy {
    DuplicatePolicy { mode: mode.into(), key_header: "x-vendor-event-id".into(), max_fresh, after_limit: "dedup_last".into(), seed_field: "attempt".into(), variant_payload: false, require_key: true }
}
fn recipe(digest: &str, n: u32, dp: DuplicatePolicy) -> ServiceRecipe {
    ServiceRecipe {
        recipe_id: "r1".into(), capsule_digest: digest.into(), entry_contract: "Offer".into(),
        input_schema_digest: None, capability_bindings: vec![], required_scopes: vec!["invoke".into()],
        receipt_policy: "audit".into(), retry_policy_ref: None, pool_sizing: n,
        created_by: "alice".into(), accepted_by: None, accepted_at: None, duplicate_policy: Some(dp),
    }
}

async fn prod(n: usize, dp: DuplicatePolicy) -> (CoordinationHub, Arc<dyn TBackend>, IngressRouter) {
    let audit: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
    let mut h = CoordinationHub::new(audit.clone(), clock());
    register(&mut h, "alice", AgentKind::Agent).await;
    register(&mut h, "dev", AgentKind::Developer).await;
    register(&mut h, "vendor:acme", AgentKind::RuntimeActor).await;
    h.create_pool(&vendor(), "svc", "candidate", PoolVisibility::Private).await.unwrap();
    let bytes = offer_bytes().await;
    let mut digest = String::new();
    for _ in 0..n {
        digest = h.add_capsule(&vendor(), "svc", bytes.clone(), vec![]).await.unwrap().capsule_id;
    }
    h.accept_recipe(&cpass("dev", "coordination", &["accept_recipe"]), "svc", recipe(&digest, n as u32, dp)).await.unwrap();
    h.grant(&cpass("dev", "coordination", &["grant_access"]), "svc", "vendor:acme", PoolRight::ActivateCapsule).await.unwrap();
    let mut r = IngressRouter::new();
    r.route("/w", "svc");
    r.token("vtok", vendor());
    (h, audit, r)
}

/// One real HTTP/1.1 POST → status + raw response text.
async fn http_post(addr: std::net::SocketAddr, key: &str, base: i64, corr: &str) -> (u16, String) {
    let mut s = TcpStream::connect(addr).await.unwrap();
    let body = json!({ "base": base }).to_string();
    let req = format!(
        "POST /w HTTP/1.1\r\nHost: x\r\nAuthorization: Bearer vtok\r\nX-Vendor-Event-Id: {}\r\nX-Correlation-Id: {}\r\nContent-Type: application/json\r\nContent-Length: {}\r\n\r\n{}",
        key, corr, body.len(), body
    );
    s.write_all(req.as_bytes()).await.unwrap();
    let mut resp = Vec::new();
    s.read_to_end(&mut resp).await.unwrap();
    let text = String::from_utf8_lossy(&resp).to_string();
    let status = text.lines().next().and_then(|l| l.split_whitespace().nth(1)).and_then(|x| x.parse().ok()).unwrap_or(0);
    (status, text)
}

fn cfg<'a>(registry: &'a CapabilityExecutorRegistry, receipts: &'a Arc<dyn TBackend>, eclock: &'a Arc<dyn ClockProvider>, ep: &'a CapabilityPassport) -> EffectBridgeConfig<'a> {
    EffectBridgeConfig { registry, receipts, effect_clock: eclock, effect_passport: ep, capability_id: CAP.into(), operation: "create_lead".into(), scope: "write".into() }
}

async fn bridge_facts(audit: &Arc<dyn TBackend>) -> Vec<Value> {
    audit.all_facts().await.unwrap().into_iter()
        .filter(|f| f.store == COORD_AUDIT_STORE && f.value["operation"] == json!("bridge_effect"))
        .map(|f| f.value).collect()
}

// 1: a real HTTP POST reaches handle_effect → committed effect → 200
#[test]
fn wire_to_effect_committed() {
    rt().block_on(async {
        let (h, _a, r) = prod(3, policy("dedup_strict", 0)).await;
        let exec = Arc::new(FakeWriteExecutor::new(CAP, WriteBehavior::Commit));
        let mut registry = CapabilityExecutorRegistry::new(); registry.register(exec.clone());
        let receipts: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
        let eclock = clock(); let ep = cpass("host", CAP, &["write"]);
        let c = cfg(&registry, &receipts, &eclock, &ep);
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();

        let (_srv, (status, text)) = tokio::join!(
            serve_once_effect(&listener, &r, &h, &c),
            http_post(addr, "E1", 1000, "c1"),
        );
        assert_eq!(status, 200);
        assert!(text.contains("committed"), "got: {}", text);
        assert_eq!(exec.attempts(), 1);
    });
}

// 2: dedup_strict replay over the wire → NO second effect
#[test]
fn wire_dedup_strict_no_second_effect() {
    rt().block_on(async {
        let (h, _a, r) = prod(3, policy("dedup_strict", 0)).await;
        let exec = Arc::new(FakeWriteExecutor::new(CAP, WriteBehavior::Commit));
        let mut registry = CapabilityExecutorRegistry::new(); registry.register(exec.clone());
        let receipts: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
        let eclock = clock(); let ep = cpass("host", CAP, &["write"]);
        let c = cfg(&registry, &receipts, &eclock, &ep);
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();

        let (_s1, (st1, _)) = tokio::join!(serve_once_effect(&listener, &r, &h, &c), http_post(addr, "E1", 1000, "c1"));
        let (_s2, (st2, _)) = tokio::join!(serve_once_effect(&listener, &r, &h, &c), http_post(addr, "E1", 1000, "c2"));
        assert_eq!(st1, 200);
        assert_eq!(st2, 200);
        assert_eq!(exec.attempts(), 1, "wire replay performs no second effect");
    });
}

// 3: bounded_fresh over repeated HTTP requests → attempts 0..n distinct effects
#[test]
fn wire_bounded_fresh_attempts() {
    rt().block_on(async {
        let (h, _a, r) = prod(3, policy("bounded_fresh", 6)).await;
        let exec = Arc::new(FakeWriteExecutor::new(CAP, WriteBehavior::Commit));
        let mut registry = CapabilityExecutorRegistry::new(); registry.register(exec.clone());
        let receipts: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
        let eclock = clock(); let ep = cpass("host", CAP, &["write"]);
        let c = cfg(&registry, &receipts, &eclock, &ep);
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();

        for i in 0..3 {
            let corr = format!("c{}", i);
            let (_s, _resp) = tokio::join!(serve_once_effect(&listener, &r, &h, &c), http_post(addr, "E1", 1000, &corr));
        }
        assert_eq!(exec.applied_count(), 3, "three HTTP requests → three distinct effects");
        assert!(receipts.read_as_of("__receipts__", "IO.SparkCRM:E1:0", f64::MAX).await.unwrap().is_some());
        assert!(receipts.read_as_of("__receipts__", "IO.SparkCRM:E1:2", f64::MAX).await.unwrap().is_some());
    });
}

// 4: status mapping over the wire — unknown effect → 202; denied effect → 403
#[test]
fn wire_status_mapping() {
    rt().block_on(async {
        // unknown
        {
            let (h, _a, r) = prod(2, policy("dedup_strict", 0)).await;
            let exec = Arc::new(FakeWriteExecutor::new(CAP, WriteBehavior::Timeout));
            let mut registry = CapabilityExecutorRegistry::new(); registry.register(exec.clone());
            let receipts: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
            let eclock = clock(); let ep = cpass("host", CAP, &["write"]);
            let c = cfg(&registry, &receipts, &eclock, &ep);
            let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
            let addr = listener.local_addr().unwrap();
            let (_s, (status, _)) = tokio::join!(serve_once_effect(&listener, &r, &h, &c), http_post(addr, "E1", 1000, "c1"));
            assert_eq!(status, 202, "unknown effect → 202 Accepted");
        }
        // denied
        {
            let (h, _a, r) = prod(2, policy("dedup_strict", 0)).await;
            let exec = Arc::new(FakeWriteExecutor::new(CAP, WriteBehavior::Deny));
            let mut registry = CapabilityExecutorRegistry::new(); registry.register(exec.clone());
            let receipts: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
            let eclock = clock(); let ep = cpass("host", CAP, &["write"]);
            let c = cfg(&registry, &receipts, &eclock, &ep);
            let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
            let addr = listener.local_addr().unwrap();
            let (_s, (status, _)) = tokio::join!(serve_once_effect(&listener, &r, &h, &c), http_post(addr, "E2", 1000, "c2"));
            assert_eq!(status, 403, "denied effect → 403 Forbidden");
        }
    });
}

// 5: the bridge audit links correlation / attempt / replica / effect_receipt_id over the wire
#[test]
fn wire_receipt_links() {
    rt().block_on(async {
        let (h, audit, r) = prod(2, policy("dedup_strict", 0)).await;
        let exec = Arc::new(FakeWriteExecutor::new(CAP, WriteBehavior::Commit));
        let mut registry = CapabilityExecutorRegistry::new(); registry.register(exec.clone());
        let receipts: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
        let eclock = clock(); let ep = cpass("host", CAP, &["write"]);
        let c = cfg(&registry, &receipts, &eclock, &ep);
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();

        let (_s, _resp) = tokio::join!(serve_once_effect(&listener, &r, &h, &c), http_post(addr, "E1", 1000, "corr-wire"));
        let bf = &bridge_facts(&audit).await[0];
        assert_eq!(bf["correlation_id"], json!("corr-wire"));
        assert_eq!(bf["attempt_index"], json!(0));
        assert!(bf["replica_index"].is_number());
        assert_eq!(bf["effect_receipt_id"], json!("IO.SparkCRM:E1:0"));
    });
}
