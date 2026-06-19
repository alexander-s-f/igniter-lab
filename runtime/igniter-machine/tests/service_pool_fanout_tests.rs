//! LAB-MACHINE-SERVICE-POOL-FANOUT-P8 — homogeneous production pool serving (replica fanout).
//!
//! A production pool of N capsule refs sharing one content_digest = a homogeneous stateless
//! replica set over an immutable service image. Deterministic single-replica selection for
//! serving; `invoke_fanout` runs the same request across all replicas to prove identical output
//! with per-replica failure isolation. Content-addressed (no byte copy). Local in-process only.

use igniter_machine::backend::{InMemoryBackend, TBackend};
use igniter_machine::capability::CapabilityPassport;
use igniter_machine::clock::{ClockProvider, FixedClock};
use igniter_machine::coordination::{
    select_replica, AgentIdentity, AgentKind, AgentStatus, CoordinationHub, PoolRight,
    PoolVisibility, ServiceRecipe, COORD_AUDIT_STORE,
};
use igniter_machine::machine::IgniterMachine;
use serde_json::{json, Value};
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
fn hub() -> (CoordinationHub, Arc<dyn TBackend>) {
    let audit: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
    (CoordinationHub::new(audit.clone(), clock()), audit)
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

async fn capsule_bytes(src: &str, name: &str) -> Vec<u8> {
    let m = IgniterMachine::new(None, "in_memory").unwrap();
    m.load_contract_source(src, name).unwrap();
    m.checkpoint_bytes().await.unwrap()
}
async fn add_bytes() -> Vec<u8> {
    capsule_bytes("contract Add { input a: Integer  input b: Integer  compute sum = a + b  output sum: Integer }", "Add").await
}

fn recipe(digest: &str, pool_sizing: u32) -> ServiceRecipe {
    ServiceRecipe {
        recipe_id: "r1".into(),
        capsule_digest: digest.into(),
        entry_contract: "Add".into(),
        input_schema_digest: None,
        capability_bindings: vec![],
        required_scopes: vec!["invoke".into()],
        receipt_policy: "audit".into(),
        retry_policy_ref: None,
        pool_sizing,
        created_by: "alice".into(),
        accepted_by: None,
        accepted_at: None,
        duplicate_policy: None,
    }
}

/// Build a production pool `svc` with `n` homogeneous Add replicas; the last gets `last_labels`.
async fn setup(h: &mut CoordinationHub, n: usize, last_labels: Vec<String>) -> String {
    register(h, "alice", AgentKind::Agent).await;
    register(h, "dev", AgentKind::Developer).await;
    register(h, "vendor:acme", AgentKind::RuntimeActor).await;
    h.create_pool(
        &passport("alice"),
        "svc",
        "candidate",
        PoolVisibility::Private,
    )
    .await
    .unwrap();
    let bytes = add_bytes().await;
    let mut digest = String::new();
    for i in 0..n {
        let labels = if i == n - 1 {
            last_labels.clone()
        } else {
            vec![]
        };
        let cref = h
            .add_capsule(&passport("alice"), "svc", bytes.clone(), labels)
            .await
            .unwrap();
        digest = cref.capsule_id;
    }
    h.accept_recipe(&passport("dev"), "svc", recipe(&digest, n as u32))
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
    digest
}

async fn audit_events(audit: &Arc<dyn TBackend>) -> Vec<Value> {
    audit
        .all_facts()
        .await
        .unwrap()
        .into_iter()
        .filter(|f| f.store == COORD_AUDIT_STORE)
        .map(|f| f.value)
        .collect()
}

// 1 + 9: a production recipe with pool_sizing=N accepts N homogeneous refs (one stored image)
#[test]
fn n_homogeneous_replicas_one_image() {
    rt().block_on(async {
        let (mut h, _a) = hub();
        setup(&mut h, 3, vec![]).await;
        assert_eq!(h.replica_count("svc").await, 3);
        assert_eq!(
            h.content_count(),
            1,
            "N refs share ONE stored byte image (no copy)"
        );
    });
}

// 2: a different-digest ref in the pool is excluded from the replica set
#[test]
fn different_digest_excluded() {
    rt().block_on(async {
        let (mut h, _a) = hub();
        register(&mut h, "alice", AgentKind::Agent).await;
        register(&mut h, "dev", AgentKind::Developer).await;
        register(&mut h, "vendor:acme", AgentKind::RuntimeActor).await;
        h.create_pool(&passport("alice"), "svc", "c", PoolVisibility::Private).await.unwrap();
        let add = add_bytes().await;
        let r1 = h.add_capsule(&passport("alice"), "svc", add.clone(), vec![]).await.unwrap();
        h.add_capsule(&passport("alice"), "svc", add.clone(), vec![]).await.unwrap();
        // a different image (different contract → different digest)
        let mul = capsule_bytes("contract Mul { input a: Integer  input b: Integer  compute p = a * b  output p: Integer }", "Mul").await;
        h.add_capsule(&passport("alice"), "svc", mul, vec![]).await.unwrap();
        h.accept_recipe(&passport("dev"), "svc", recipe(&r1.capsule_id, 2)).await.unwrap();

        assert_eq!(h.replica_count("svc").await, 2, "the different-digest ref is excluded");
    });
}

// 3: deterministic selection (no random) — pure
#[test]
fn deterministic_selection() {
    assert_eq!(
        select_replica("hash_key", 3, "E1"),
        select_replica("hash_key", 3, "E1")
    );
    assert!(select_replica("hash_key", 3, "E1") < 3);
    assert_eq!(select_replica("round_robin", 3, "0"), 0);
    assert_eq!(select_replica("round_robin", 3, "1"), 1);
    assert_eq!(select_replica("round_robin", 3, "3"), 0); // wraps
}

// 3 (live) + 5/6: invoke a selected replica; selection is output-invariant (homogeneous)
#[test]
fn invoke_replica_output_invariant() {
    rt().block_on(async {
        let (mut h, _a) = hub();
        setup(&mut h, 3, vec![]).await;
        let r0 = h
            .invoke_replica(&passport("vendor:acme"), "svc", json!({"a": 2, "b": 3}), 0)
            .await
            .unwrap();
        let r1 = h
            .invoke_replica(&passport("vendor:acme"), "svc", json!({"a": 2, "b": 3}), 1)
            .await
            .unwrap();
        let r2 = h
            .invoke_replica(&passport("vendor:acme"), "svc", json!({"a": 2, "b": 3}), 7)
            .await
            .unwrap(); // 7 % 3 = 1
        assert_eq!(r0, json!(5));
        assert_eq!(r1, json!(5));
        assert_eq!(r2, json!(5)); // selecting a different replica never changes the output
    });
}

// 4: activate_many across all replicas → identical output
#[test]
fn fanout_identical_output() {
    rt().block_on(async {
        let (mut h, _a) = hub();
        setup(&mut h, 3, vec![]).await;
        let results = h
            .invoke_fanout(&passport("vendor:acme"), "svc", json!({"a": 10, "b": 7}))
            .await
            .unwrap();
        assert_eq!(results.len(), 3);
        assert!(
            results
                .iter()
                .all(|(_, r)| r.as_ref().unwrap() == &json!(17)),
            "all replicas give the same output"
        );
    });
}

// 7: audit records the selected replica / fanout set
#[test]
fn audit_records_replica_and_fanout() {
    rt().block_on(async {
        let (mut h, audit) = hub();
        setup(&mut h, 2, vec![]).await;
        h.invoke_replica(&passport("vendor:acme"), "svc", json!({"a": 1, "b": 1}), 0)
            .await
            .unwrap();
        h.invoke_fanout(&passport("vendor:acme"), "svc", json!({"a": 1, "b": 1}))
            .await
            .unwrap();
        let evs = audit_events(&audit).await;
        assert!(evs.iter().any(|e| e["operation"] == "invoke"
            && e["reason"]
                .as_str()
                .map(|s| s.starts_with("replica:"))
                .unwrap_or(false)));
        assert!(evs
            .iter()
            .any(|e| e["operation"] == "invoke_fanout" && e["reason"] == json!("fanout:2")));
    });
}

// 8: a non-production pool cannot fanout
#[test]
fn non_production_cannot_fanout() {
    rt().block_on(async {
        let (mut h, _a) = hub();
        register(&mut h, "alice", AgentKind::Agent).await;
        register(&mut h, "vendor:acme", AgentKind::RuntimeActor).await;
        h.create_pool(&passport("alice"), "draft", "d", PoolVisibility::Private)
            .await
            .unwrap();
        let bytes = add_bytes().await;
        h.add_capsule(&passport("alice"), "draft", bytes, vec![])
            .await
            .unwrap();
        // never signed into production → fanout refused
        assert!(h
            .invoke_fanout(&passport("vendor:acme"), "draft", json!({"a": 1, "b": 1}))
            .await
            .is_err());
    });
}

// 10: one replica disabled → isolated and reported, others succeed
#[test]
fn failure_isolation_in_fanout() {
    rt().block_on(async {
        let (mut h, _a) = hub();
        setup(&mut h, 3, vec!["disabled".to_string()]).await; // 3rd replica disabled
        let results = h
            .invoke_fanout(&passport("vendor:acme"), "svc", json!({"a": 4, "b": 4}))
            .await
            .unwrap();
        assert_eq!(results.len(), 3);
        assert_eq!(results[0].1.as_ref().unwrap(), &json!(8));
        assert_eq!(results[1].1.as_ref().unwrap(), &json!(8));
        assert!(
            results[2].1.is_err(),
            "the disabled replica is isolated + reported, others succeed"
        );
    });
}
