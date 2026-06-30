//! LAB-MACHINE-SERVICE-INGRESS-DUPLICATE-POLICY-P7 — configurable business duplicate policy.
//!
//! Duplicate handling is a BUSINESS strategy on the `ServiceRecipe`/route, NOT a canon default.
//! `idempotency = safety envelope` (same key + different payload → conflict) is always enforced;
//! the duplicate POLICY decides what a repeat MEANS: `dedup_strict` (replay, no re-activation),
//! `treat_as_fresh` (re-activate, audit-linked — the vendor-auction case: same input, distinct
//! generated code per attempt), `bounded_fresh(n)` (first n fresh, then dedup/deny). The policy
//! lives in the recipe, never in the language/VM.

use igniter_machine::backend::{InMemoryBackend, TBackend};
use igniter_machine::capability::CapabilityPassport;
use igniter_machine::clock::{ClockProvider, FixedClock};
use igniter_machine::coordination::{
    AgentIdentity, AgentKind, AgentStatus, CoordinationHub, DuplicatePolicy, PoolRight,
    PoolVisibility, ServiceRecipe,
};
use igniter_machine::ingress::{IngressRequest, IngressRouter};
use igniter_machine::machine::IgniterMachine;
use serde_json::json;
use std::collections::HashMap;
use std::sync::Arc;

fn rt() -> tokio::runtime::Runtime {
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
}
fn clock() -> Arc<dyn ClockProvider> {
    Arc::new(FixedClock::new(100.0))
}

const SCOPES: &[&str] = &[
    "create_pool",
    "import_capsule",
    "activate_capsule",
    "grant_access",
    "accept_recipe",
    "invoke",
];

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

/// A capsule whose entry contract mints a distinct `code = base + attempt` — so a repeated
/// webhook with the same `base` produces a distinct response per injected `attempt` index.
async fn offer_capsule_bytes() -> Vec<u8> {
    let m = IgniterMachine::new(None, "in_memory").unwrap();
    let src = "contract Offer { input base: Integer  input attempt: Integer  compute code = base + attempt  output code: Integer }";
    m.load_contract_source(src, "Offer").unwrap();
    m.checkpoint_bytes().await.unwrap()
}

fn policy(
    mode: &str,
    max_fresh: u32,
    after_limit: &str,
    variant: bool,
    require_key: bool,
) -> DuplicatePolicy {
    DuplicatePolicy {
        mode: mode.into(),
        key_header: "x-vendor-event-id".into(),
        max_fresh,
        after_limit: after_limit.into(),
        seed_field: "attempt".into(),
        variant_payload: variant,
        require_key,
    }
}

fn recipe(digest: &str, dp: Option<DuplicatePolicy>) -> ServiceRecipe {
    ServiceRecipe {
        recipe_id: "r1".into(),
        capsule_digest: digest.into(),
        entry_contract: "Offer".into(),
        input_schema_digest: None,
        capability_bindings: vec![],
        required_scopes: vec!["invoke".into()],
        receipt_policy: "audit".into(),
        retry_policy_ref: None,
        pool_sizing: 1,
        created_by: "alice".into(),
        accepted_by: None,
        accepted_at: None,
        duplicate_policy: dp,
    }
}

/// A live production "svc" serving the Offer capsule under the given duplicate policy.
async fn prod_hub(dp: Option<DuplicatePolicy>) -> (CoordinationHub, Arc<dyn TBackend>) {
    let audit: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
    let mut h = CoordinationHub::new(audit.clone(), clock());
    register(&mut h, "alice", AgentKind::Agent).await;
    register(&mut h, "dev", AgentKind::Developer).await;
    register(&mut h, "vendor:acme", AgentKind::RuntimeActor).await;
    h.create_pool(
        &passport("alice"),
        "svc",
        "candidate",
        PoolVisibility::Private,
    )
    .await
    .unwrap();
    let bytes = offer_capsule_bytes().await;
    let cref = h
        .add_capsule(&passport("alice"), "svc", bytes, vec![])
        .await
        .unwrap();
    h.accept_recipe(&passport("dev"), "svc", recipe(&cref.capsule_id, dp))
        .await
        .unwrap();
    h.grant(
        &passport("dev"),
        "svc",
        "vendor:acme",
        PoolRight::ActivateCapsule,
    )
    .await
    .unwrap();
    (h, audit)
}

fn router() -> IngressRouter {
    let mut r = IngressRouter::new();
    r.route("/webhook/acme", "svc");
    r.token("vendortoken", passport("vendor:acme"));
    r
}

fn req(key: &str, base: i64) -> IngressRequest {
    let mut headers = HashMap::new();
    headers.insert(
        "authorization".to_string(),
        "Bearer vendortoken".to_string(),
    );
    headers.insert("x-vendor-event-id".to_string(), key.to_string());
    headers.insert("x-correlation-id".to_string(), format!("corr-{}", base));
    IngressRequest {
        method: "POST".to_string(),
        path: "/webhook/acme".to_string(),
        headers,
        body: json!({"base": base}),
    }
}

// 1: dedup_strict — repeat returns the recorded response, no re-activation
#[test]
fn dedup_strict_replays_no_activation() {
    rt().block_on(async {
        let (h, _a) = prod_hub(Some(policy("dedup_strict", 0, "dedup_last", false, true))).await;
        let r = router();
        let a = r.handle(&h, &req("E1", 1000)).await;
        let b = r.handle(&h, &req("E1", 1000)).await;
        assert_eq!(a.body, json!(1000)); // base + attempt(0)
        assert_eq!(b.body, json!(1000)); // replayed, same response
        let hist = h.ingress_dedup_history("/webhook/acme", "E1").await;
        assert_eq!(hist[0]["decision"], json!("accepted"));
        assert_eq!(hist[1]["decision"], json!("replayed")); // no second activation
    });
}

// 2,4,5: treat_as_fresh — the auction case: same input, DISTINCT generated code per attempt
#[test]
fn treat_as_fresh_distinct_code_per_attempt() {
    rt().block_on(async {
        let (h, _a) = prod_hub(Some(policy("treat_as_fresh", 0, "dedup_last", false, true))).await;
        let r = router();
        let a = r.handle(&h, &req("E1", 1000)).await;
        let b = r.handle(&h, &req("E1", 1000)).await;
        let c = r.handle(&h, &req("E1", 1000)).await;
        // same vendor input, three activations, three distinct codes (1000 + attempt_index)
        assert_eq!(a.body, json!(1000));
        assert_eq!(b.body, json!(1001));
        assert_eq!(c.body, json!(1002));
        let hist = h.ingress_dedup_history("/webhook/acme", "E1").await;
        assert_eq!(
            hist.iter()
                .filter(|x| x["decision"] == json!("accepted")
                    || x["decision"] == json!("fresh_duplicate"))
                .count(),
            3
        );
    });
}

// 3: bounded_fresh(3) — first 3 fresh, 4th dedups to the last recorded response
#[test]
fn bounded_fresh_then_dedup_last() {
    rt().block_on(async {
        let (h, _a) = prod_hub(Some(policy("bounded_fresh", 3, "dedup_last", false, true))).await;
        let r = router();
        let outs: Vec<_> = {
            let mut v = vec![];
            for _ in 0..4 {
                v.push(r.handle(&h, &req("E1", 1000)).await.body);
            }
            v
        };
        assert_eq!(
            outs,
            vec![json!(1000), json!(1001), json!(1002), json!(1002)]
        ); // 4th = dedup last
        let hist = h.ingress_dedup_history("/webhook/acme", "E1").await;
        assert_eq!(hist.last().unwrap()["decision"], json!("replayed"));
    });
}

// 3 variant: bounded_fresh with after_limit deny
#[test]
fn bounded_fresh_then_deny() {
    rt().block_on(async {
        let (h, _a) = prod_hub(Some(policy("bounded_fresh", 2, "deny", false, true))).await;
        let r = router();
        assert_eq!(r.handle(&h, &req("E1", 1000)).await.status, 200);
        assert_eq!(r.handle(&h, &req("E1", 1000)).await.status, 200);
        let third = r.handle(&h, &req("E1", 1000)).await;
        assert_eq!(third.status, 429); // duplicate limit reached
    });
}

// 6: same duplicate key, different payload → conflict (safety invariant)
#[test]
fn same_key_different_payload_conflict() {
    rt().block_on(async {
        let (h, _a) = prod_hub(Some(policy("dedup_strict", 0, "dedup_last", false, true))).await;
        let r = router();
        assert_eq!(r.handle(&h, &req("E1", 1000)).await.status, 200);
        let conflict = r.handle(&h, &req("E1", 2000)).await; // different payload, same key
        assert_eq!(conflict.status, 409);
    });
}

// 6 explicit-allow: variant_payload=true permits different payloads under one key
#[test]
fn variant_payload_allowed_when_policy_opts_in() {
    rt().block_on(async {
        let (h, _a) = prod_hub(Some(policy("treat_as_fresh", 0, "dedup_last", true, true))).await;
        let r = router();
        assert_eq!(r.handle(&h, &req("E1", 1000)).await.body, json!(1000));
        assert_eq!(r.handle(&h, &req("E1", 5000)).await.body, json!(5001)); // fresh, different payload OK
    });
}

// 7: audit/dedup facts record duplicate_key, attempt_index, decision
#[test]
fn dedup_facts_record_key_attempt_decision() {
    rt().block_on(async {
        let (h, _a) = prod_hub(Some(policy("treat_as_fresh", 0, "dedup_last", false, true))).await;
        let r = router();
        r.handle(&h, &req("E1", 1000)).await;
        r.handle(&h, &req("E1", 1000)).await;
        let hist = h.ingress_dedup_history("/webhook/acme", "E1").await;
        assert_eq!(hist[0]["duplicate_key"], json!("E1"));
        assert_eq!(hist[0]["attempt_index"], json!(0));
        assert_eq!(hist[1]["attempt_index"], json!(1));
        assert!(hist.iter().all(|x| x.get("decision").is_some()));
    });
}

// 8 + 9: policy lives in the recipe (round-trips); missing key with require → 400
#[test]
fn policy_in_recipe_and_missing_key_required() {
    rt().block_on(async {
        let (h, _a) = prod_hub(Some(policy("dedup_strict", 0, "dedup_last", false, true))).await;
        // the policy is config on the recipe, not the VM
        let r = h.read_recipe("svc").await.unwrap();
        assert_eq!(r.duplicate_policy.as_ref().unwrap().mode, "dedup_strict");

        // a request with NO duplicate key, under require_key → 400 (before activation)
        let router = router();
        let mut headers = HashMap::new();
        headers.insert(
            "authorization".to_string(),
            "Bearer vendortoken".to_string(),
        );
        let no_key = IngressRequest {
            method: "POST".into(),
            path: "/webhook/acme".into(),
            headers,
            body: json!({"base": 1000}),
        };
        assert_eq!(router.handle(&h, &no_key).await.status, 400);
    });
}
