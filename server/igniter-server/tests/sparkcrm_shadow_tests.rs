//! SparkCRM shadow harness over the machine contour (SHADOW-P2). Feature `machine` only.
//!
//! Offline, deterministic, DB-free, network-free: sanitized webhook fixtures → `SparkCrmApp` →
//! `InvokeEffect` → P3 `MachineEffectHost` → local fake executor. Proves target routing, bounded_fresh
//! attempt sequencing, deterministic per-attempt codes, and `dedup_last` replay (no new effect).
#![cfg(feature = "machine")]

use igniter_machine::backend::{InMemoryBackend, TBackend};
use igniter_machine::capability::{CapabilityExecutorRegistry, CapabilityPassport};
use igniter_machine::clock::{ClockProvider, FixedClock};
use igniter_machine::coordination::{
    AgentIdentity, AgentKind, AgentStatus, CoordinationHub, DuplicatePolicy, PoolRight,
    PoolVisibility, ServiceRecipe,
};
use igniter_machine::ingress::{EffectBridgeConfig, IngressRouter};
use igniter_machine::machine::IgniterMachine;
use igniter_machine::single_flight::SingleFlight;
use igniter_machine::write::{FakeWriteExecutor, WriteBehavior};

use igniter_server::effect_host::{MachineEffectHost, serve_once_effect};

use serde_json::{Value, json};

// The SparkCRM-shaped app is a TEST FIXTURE (not part of the core server surface, P6).
#[path = "fixtures/sparkcrm_app.rs"]
mod sparkcrm_fixture;
use sparkcrm_fixture::{SparkCrmApp, payloads as fx};
use std::sync::Arc;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};

const CAP: &str = "IO.LeadStore"; // host-owned fake capability — NOT a live SparkCRM endpoint.

fn rt() -> tokio::runtime::Runtime {
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
}
fn clock() -> Arc<dyn ClockProvider> {
    Arc::new(FixedClock::new(100.0))
}
fn cpass(subject: &str, cap: &str, scopes: &[&str]) -> CapabilityPassport {
    CapabilityPassport {
        subject: subject.to_string(),
        capability_id: cap.to_string(),
        scopes: scopes.iter().map(|s| s.to_string()).collect(),
        issued_at: 0.0,
        expires_at: Some(1_000_000.0),
        revoked: false,
        evidence_digest: "sig".to_string(),
    }
}
fn vendor() -> CapabilityPassport {
    cpass(
        "vendor:acme",
        "coordination",
        &[
            "create_pool",
            "import_capsule",
            "activate_capsule",
            "grant_access",
            "accept_recipe",
            "invoke",
        ],
    )
}
async fn register(h: &mut CoordinationHub, id: &str, kind: AgentKind) {
    h.register_agent(AgentIdentity {
        agent_id: id.into(),
        kind,
        label: id.into(),
        status: AgentStatus::Active,
        registered_at: 0.0,
    })
    .await
    .unwrap();
}
async fn leadoffer_bytes() -> Vec<u8> {
    let m = IgniterMachine::new(None, "in_memory").unwrap();
    m.load_contract_source(
        "contract LeadOffer { input base: Integer  input attempt: Integer  compute code = base + attempt  output code: Integer }",
        "LeadOffer",
    )
    .unwrap();
    m.checkpoint_bytes().await.unwrap()
}
/// The recommended auction profile: bounded_fresh(5), dedup_last, GENERIC key_header.
fn auction_policy() -> DuplicatePolicy {
    DuplicatePolicy {
        mode: "bounded_fresh".into(),
        key_header: "idempotency-key".into(), // generic — the app supplies the canonical key.
        max_fresh: 5,
        after_limit: "dedup_last".into(),
        seed_field: "attempt".into(),
        variant_payload: false,
        require_key: true,
    }
}
fn recipe(digest: &str, n: u32) -> ServiceRecipe {
    ServiceRecipe {
        recipe_id: "r1".into(),
        capsule_digest: digest.into(),
        entry_contract: "LeadOffer".into(),
        input_schema_digest: None,
        capability_bindings: vec![],
        required_scopes: vec!["invoke".into()],
        receipt_policy: "audit".into(),
        retry_policy_ref: None,
        pool_sizing: n,
        created_by: "alice".into(),
        accepted_by: None,
        accepted_at: None,
        duplicate_policy: Some(auction_policy()),
    }
}
async fn prod(n: usize) -> (CoordinationHub, IngressRouter) {
    let audit: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
    let mut h = CoordinationHub::new(audit, clock());
    register(&mut h, "alice", AgentKind::Agent).await;
    register(&mut h, "dev", AgentKind::Developer).await;
    register(&mut h, "vendor:acme", AgentKind::RuntimeActor).await;
    h.create_pool(&vendor(), "svc", "candidate", PoolVisibility::Private)
        .await
        .unwrap();
    let bytes = leadoffer_bytes().await;
    let mut digest = String::new();
    for _ in 0..n {
        digest = h
            .add_capsule(&vendor(), "svc", bytes.clone(), vec![])
            .await
            .unwrap()
            .capsule_id;
    }
    h.accept_recipe(
        &cpass("dev", "coordination", &["accept_recipe"]),
        "svc",
        recipe(&digest, n as u32),
    )
    .await
    .unwrap();
    h.grant(
        &cpass("dev", "coordination", &["grant_access"]),
        "svc",
        "vendor:acme",
        PoolRight::ActivateCapsule,
    )
    .await
    .unwrap();
    let mut r = IngressRouter::new();
    r.route("/w", "svc");
    r.token("vtok", vendor());
    (h, r)
}

struct EffectState {
    exec: Arc<FakeWriteExecutor>,
    registry: CapabilityExecutorRegistry,
    receipts: Arc<dyn TBackend>,
    eclock: Arc<dyn ClockProvider>,
    ep: CapabilityPassport,
    sf: SingleFlight,
}
fn effect_state() -> EffectState {
    let exec = Arc::new(FakeWriteExecutor::new(CAP, WriteBehavior::Commit));
    let mut registry = CapabilityExecutorRegistry::new();
    registry.register(exec.clone());
    EffectState {
        exec,
        registry,
        receipts: Arc::new(InMemoryBackend::new()),
        eclock: clock(),
        ep: cpass("host", CAP, &["write"]),
        sf: SingleFlight::new(),
    }
}
fn cfg(s: &EffectState) -> EffectBridgeConfig<'_> {
    EffectBridgeConfig {
        registry: &s.registry,
        receipts: &s.receipts,
        effect_clock: &s.eclock,
        effect_passport: &s.ep,
        effect_passport_verifier: None,
        single_flight: &s.sf,
        capability_id: CAP.into(),
        operation: "register_lead".into(),
        scope: "write".into(),
    }
}
/// Host binds ALL THREE logical app targets to the one fixture machine route (infra binding).
fn effect_host<'a>(
    router: &'a IngressRouter,
    hub: &'a CoordinationHub,
    cfg: &'a EffectBridgeConfig<'a>,
) -> MachineEffectHost<'a> {
    let mut eh = MachineEffectHost::new(router, hub, cfg);
    eh.bind_target("lead-intake", "/w");
    eh.bind_target("lead-bid", "/w");
    eh.bind_target("lead-status", "/w");
    eh
}

/// One real loopback webhook POST → (status, body json). Carries bearer + auction id + correlation.
async fn webhook(
    addr: std::net::SocketAddr,
    path: &str,
    auction_id: &str,
    corr: &str,
    body: &Value,
) -> (u16, Value) {
    let mut s = TcpStream::connect(addr).await.unwrap();
    let body_s = body.to_string();
    let req = format!(
        "POST {} HTTP/1.1\r\nHost: x\r\nAuthorization: Bearer vtok\r\nX-Auction-Id: {}\r\nX-Correlation-Id: {}\r\nContent-Type: application/json\r\nContent-Length: {}\r\n\r\n{}",
        path,
        auction_id,
        corr,
        body_s.len(),
        body_s
    );
    s.write_all(req.as_bytes()).await.unwrap();
    let mut resp = Vec::new();
    s.read_to_end(&mut resp).await.unwrap();
    let text = String::from_utf8_lossy(&resp).to_string();
    let status = text
        .lines()
        .next()
        .and_then(|l| l.split_whitespace().nth(1))
        .and_then(|x| x.parse().ok())
        .unwrap_or(0);
    let body_start = text.find("\r\n\r\n").map(|i| i + 4).unwrap_or(text.len());
    let body_json: Value = serde_json::from_str(text[body_start..].trim()).unwrap_or(Value::Null);
    (status, body_json)
}

async fn receipt_field(receipts: &Arc<dyn TBackend>, key: &str, field: &str) -> Option<Value> {
    receipts
        .read_as_of("__receipts__", key, f64::MAX)
        .await
        .unwrap()
        .map(|f| f.value[field].clone())
}

// ── targets normalize + execute through the machine ──────────────────────────────────────────────
#[test]
fn test_sparkcrm_targets_execute_through_machine() {
    rt().block_on(async {
        let (h, r) = prod(3).await;
        let st = effect_state();
        let c = cfg(&st);
        let eh = effect_host(&r, &h, &c);
        let app = SparkCrmApp;
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();

        for (path, auc, body) in [
            ("/webhook/leads", "AUC-L", fx::lead_intake()),
            ("/webhook/bids", "AUC-B", fx::lead_bid()),
            ("/webhook/status", "AUC-S", fx::lead_status()),
        ] {
            let (status, body_json) = tokio::join!(
                serve_once_effect(&listener, &app, &eh),
                webhook(addr, path, auc, "corr", &body)
            )
            .1;
            assert_eq!(status, 200, "{path} committed");
            assert_eq!(body_json["status"], json!("committed"));
        }
        assert_eq!(
            st.exec.applied_count(),
            3,
            "three distinct targets → three effects"
        );
    });
}

// ── bounded_fresh: attempts 0..4 produce distinct deterministic codes ─────────────────────────────
#[test]
fn test_bounded_fresh_auction_attempts_up_to_limit() {
    rt().block_on(async {
        let (h, r) = prod(3).await;
        let st = effect_state();
        let c = cfg(&st);
        let eh = effect_host(&r, &h, &c);
        let app = SparkCrmApp;
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();

        let body = fx::lead_intake(); // identical body each send (same lead); attempt is host-injected.
        for _ in 0..5 {
            let (status, _) = tokio::join!(
                serve_once_effect(&listener, &app, &eh),
                webhook(addr, "/webhook/leads", "AUC-DUP", "auc-corr", &body)
            )
            .1;
            assert_eq!(status, 200);
        }
        assert_eq!(
            st.exec.applied_count(),
            5,
            "five accepted duplicates → five fresh effects"
        );

        // distinct effect receipts per attempt, keyed CAP:AUC-DUP:attempt.
        let mut digests = Vec::new();
        for attempt in 0..5 {
            let key = format!("{CAP}:AUC-DUP:{attempt}");
            let idem = receipt_field(&st.receipts, &key, "idempotency_key").await;
            assert_eq!(
                idem,
                Some(json!(format!("AUC-DUP:{attempt}"))),
                "attempt {attempt} receipt exists"
            );
            digests.push(
                receipt_field(&st.receipts, &key, "payload_digest")
                    .await
                    .unwrap(),
            );
        }
        // codes are deterministic in attempt (code = base + attempt) → distinct payload digests.
        for i in 0..digests.len() {
            for j in (i + 1)..digests.len() {
                assert_ne!(
                    digests[i], digests[j],
                    "attempt {i} vs {j}: distinct deterministic code"
                );
            }
        }
    });
}

// ── deterministic: identical input + attempt reproduces the same code across fresh runs ───────────
#[test]
fn test_deterministic_code_is_reproducible_across_runs() {
    rt().block_on(async {
        async fn first_digest() -> Value {
            let (h, r) = prod(3).await;
            let st = effect_state();
            let c = cfg(&st);
            let eh = effect_host(&r, &h, &c);
            let app = SparkCrmApp;
            let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
            let addr = listener.local_addr().unwrap();
            let body = fx::lead_intake();
            let _ = tokio::join!(
                serve_once_effect(&listener, &app, &eh),
                webhook(addr, "/webhook/leads", "AUC-R", "auc-corr", &body)
            );
            receipt_field(&st.receipts, &format!("{CAP}:AUC-R:0"), "payload_digest")
                .await
                .unwrap()
        }
        assert_eq!(
            first_digest().await,
            first_digest().await,
            "attempt 0 code is reproducible"
        );
    });
}

// ── after_limit = dedup_last: the 6th replays the 5th, no new effect ──────────────────────────────
#[test]
fn test_after_limit_dedup_last_replays_fifth_attempt() {
    rt().block_on(async {
        let (h, r) = prod(3).await;
        let st = effect_state();
        let c = cfg(&st);
        let eh = effect_host(&r, &h, &c);
        let app = SparkCrmApp;
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();

        let body = fx::lead_intake();
        let mut last = Value::Null;
        for _ in 0..5 {
            last = tokio::join!(
                serve_once_effect(&listener, &app, &eh),
                webhook(addr, "/webhook/leads", "AUC-DUP", "auc-corr", &body)
            )
            .1
            .1;
        }
        assert_eq!(st.exec.applied_count(), 5);

        // 6th send: past max_fresh=5 → dedup_last replays the recorded 5th response, NO new effect.
        let (status6, body6) = tokio::join!(
            serve_once_effect(&listener, &app, &eh),
            webhook(addr, "/webhook/leads", "AUC-DUP", "auc-corr", &body)
        )
        .1;
        assert_eq!(status6, 200);
        assert_eq!(
            body6, last,
            "6th request replays the 5th attempt's response"
        );
        assert_eq!(st.exec.applied_count(), 5, "no new effect past the bound");
        assert!(
            receipt_field(&st.receipts, &format!("{CAP}:AUC-DUP:5"), "state")
                .await
                .is_none(),
            "no attempt-5 receipt"
        );
    });
}

// ── keyless webhook → 400, zero effects (proven end-to-end over the socket) ───────────────────────
#[test]
fn test_keyless_webhook_is_400_zero_effects_over_socket() {
    rt().block_on(async {
        let (h, r) = prod(3).await;
        let st = effect_state();
        let c = cfg(&st);
        let eh = effect_host(&r, &h, &c);
        let app = SparkCrmApp;
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();

        // keyless body + NO x-auction-id header → SparkCrmApp answers 400 before any effect.
        let mut s = TcpStream::connect(addr).await.unwrap();
        let body = fx::lead_keyless().to_string();
        let req = format!(
            "POST /webhook/leads HTTP/1.1\r\nHost: x\r\nAuthorization: Bearer vtok\r\nContent-Type: application/json\r\nContent-Length: {}\r\n\r\n{}",
            body.len(), body
        );
        let (_srv, _) = tokio::join!(serve_once_effect(&listener, &app, &eh), async move {
            s.write_all(req.as_bytes()).await.unwrap();
            let mut resp = Vec::new();
            s.read_to_end(&mut resp).await.unwrap();
            let text = String::from_utf8_lossy(&resp).to_string();
            let status: u16 = text.lines().next().and_then(|l| l.split_whitespace().nth(1)).and_then(|x| x.parse().ok()).unwrap_or(0);
            assert_eq!(status, 400, "keyless webhook → 400 over the socket");
        });
        assert_eq!(st.exec.applied_count(), 0, "keyless webhook performed zero effects");
    });
}
