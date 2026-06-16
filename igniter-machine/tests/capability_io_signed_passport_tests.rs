//! LAB-MACHINE-CAPABILITY-IO-SIGNED-PASSPORT-P21 — verifiable passport signatures.
//!
//! P5 gave a typed passport, but `evidence_digest` was opaque — the host could fabricate any
//! passport. P21 makes it a verifiable keyed-hash signature over the passport's identity+validity
//! material, checked against trusted issuer keys at the boundary BEFORE the executor. The P5
//! validity checks (capability / scope / expiry / revoked) remain, on top of authenticity.
//! Local MAC only — no OAuth/JWT/asymmetric PKI.

use igniter_machine::backend::{InMemoryBackend, TBackend};
use igniter_machine::capability::{
    run_effect_with_verified_passport, sign_passport, verify_passport_signed, AuthRefusal,
    CapabilityExecutorRegistry, CapabilityPassport, EchoCapabilityExecutor, EffectRequest, OutcomeKind,
    PassportVerifier, RunMode, RECEIPTS_STORE,
};
use igniter_machine::clock::{ClockProvider, FixedClock};
use serde_json::json;
use std::sync::Arc;

const CAP: &str = "IO.SignedCapability";
const ISSUER: [u8; 32] = [7u8; 32];
const OTHER_ISSUER: [u8; 32] = [9u8; 32];

fn rt() -> tokio::runtime::Runtime {
    tokio::runtime::Builder::new_current_thread().enable_all().build().unwrap()
}
fn clock_at(t: f64) -> Arc<dyn ClockProvider> {
    Arc::new(FixedClock::new(t))
}
fn verifier() -> PassportVerifier {
    PassportVerifier::new().trust(ISSUER)
}

/// A passport signed by `key`. Signing uses identity+validity material (NOT evidence_digest), so
/// setting evidence_digest to the signature afterwards is well-defined.
fn signed(key: &[u8; 32], subject: &str, scopes: &[&str], expires: Option<f64>) -> CapabilityPassport {
    let mut p = CapabilityPassport {
        subject: subject.into(), capability_id: CAP.into(),
        scopes: scopes.iter().map(|s| s.to_string()).collect(),
        issued_at: 0.0, expires_at: expires, revoked: false, evidence_digest: String::new(),
    };
    p.evidence_digest = sign_passport(key, &p);
    p
}
fn req(key: &str) -> EffectRequest {
    EffectRequest { capability_id: CAP.into(), idempotency_key: key.into(), authority_ref: None, args: json!({}) }
}
fn registry() -> (CapabilityExecutorRegistry, Arc<EchoCapabilityExecutor>) {
    let echo = Arc::new(EchoCapabilityExecutor::new(CAP));
    let mut reg = CapabilityExecutorRegistry::new();
    reg.register(echo.clone());
    (reg, echo)
}
fn receipts() -> Arc<dyn TBackend> {
    Arc::new(InMemoryBackend::new())
}

// ── valid signed passport authorizes + writes a receipt ────────────────────────

#[test]
fn valid_signed_passport_authorizes() {
    rt().block_on(async {
        let (reg, echo) = registry();
        let store = receipts();
        let p = signed(&ISSUER, "svc", &["read"], Some(1_000_000.0));
        let out = run_effect_with_verified_passport(&reg, &store, &clock_at(10.0), &verifier(), &p, "read", &req("k1"), RunMode::Live).await.unwrap();
        assert_eq!(out.kind, OutcomeKind::Succeeded);
        assert_eq!(echo.call_count(), 1);
        assert!(store.read_as_of(RECEIPTS_STORE, "IO.SignedCapability:k1", f64::MAX).await.unwrap().is_some());
    });
}

// ── a passport from an untrusted issuer (or with a bogus signature) is refused ─

#[test]
fn untrusted_signature_refused() {
    rt().block_on(async {
        let (reg, echo) = registry();
        let store = receipts();

        // signed by an issuer the verifier does NOT trust
        let foreign = signed(&OTHER_ISSUER, "svc", &["read"], Some(1_000_000.0));
        let out = run_effect_with_verified_passport(&reg, &store, &clock_at(10.0), &verifier(), &foreign, "read", &req("u1"), RunMode::Live).await.unwrap();
        assert_eq!(out.kind, OutcomeKind::Denied);

        // a passport with a non-signature evidence (the old presence-only style) is not authentic
        let mut bogus = signed(&ISSUER, "svc", &["read"], Some(1_000_000.0));
        bogus.evidence_digest = "sig".into();
        let out2 = run_effect_with_verified_passport(&reg, &store, &clock_at(10.0), &verifier(), &bogus, "read", &req("u2"), RunMode::Live).await.unwrap();
        assert_eq!(out2.kind, OutcomeKind::Denied);

        assert_eq!(echo.call_count(), 0, "no executor reached for an unauthentic passport");
        assert!(store.read_as_of(RECEIPTS_STORE, "IO.SignedCapability:u1", f64::MAX).await.unwrap().is_none());
    });
}

// ── tampering (adding a scope after signing) breaks authenticity ───────────────

#[test]
fn tampered_passport_cannot_escalate_scope() {
    rt().block_on(async {
        let (reg, echo) = registry();
        let store = receipts();
        // signed with only "read"; attacker adds "write" after signing
        let mut p = signed(&ISSUER, "svc", &["read"], Some(1_000_000.0));
        p.scopes.push("write".into());
        let out = run_effect_with_verified_passport(&reg, &store, &clock_at(10.0), &verifier(), &p, "write", &req("t1"), RunMode::Live).await.unwrap();
        assert_eq!(out.kind, OutcomeKind::Denied, "the signature binds the scope set — no escalation");
        assert_eq!(echo.call_count(), 0);
    });
}

// ── the P5 validity checks remain ON TOP of authenticity ───────────────────────

#[test]
fn signed_but_expired_revoked_or_wrong_scope_still_refused() {
    rt().block_on(async {
        let (reg, _echo) = registry();
        let store = receipts();

        // authentically signed, but expired (clock past expiry)
        let exp = signed(&ISSUER, "svc", &["read"], Some(100.0));
        let r = run_effect_with_verified_passport(&reg, &store, &clock_at(200.0), &verifier(), &exp, "read", &req("e1"), RunMode::Live).await.unwrap();
        assert_eq!(r.kind, OutcomeKind::Denied, "expired");

        // authentically signed, but revoked (revoked is host-side, not part of the signature)
        let mut rev = signed(&ISSUER, "svc", &["read"], Some(1_000_000.0));
        rev.revoked = true;
        let r = run_effect_with_verified_passport(&reg, &store, &clock_at(10.0), &verifier(), &rev, "read", &req("r1"), RunMode::Live).await.unwrap();
        assert_eq!(r.kind, OutcomeKind::Denied, "revoked");

        // authentically signed, but missing the required scope
        let ws = signed(&ISSUER, "svc", &["read"], Some(1_000_000.0));
        let r = run_effect_with_verified_passport(&reg, &store, &clock_at(10.0), &verifier(), &ws, "write", &req("w1"), RunMode::Live).await.unwrap();
        assert_eq!(r.kind, OutcomeKind::Denied, "wrong scope");
    });
}

// ── unit: verify_passport_signed refusal taxonomy ──────────────────────────────

#[test]
fn verify_passport_signed_unit() {
    let c = clock_at(10.0);
    let v = verifier();
    let good = signed(&ISSUER, "svc", &["read"], Some(1_000_000.0));
    assert!(verify_passport_signed(&v, &good, CAP, "read", &c).is_ok());

    let foreign = signed(&OTHER_ISSUER, "svc", &["read"], Some(1_000_000.0));
    assert_eq!(verify_passport_signed(&v, &foreign, CAP, "read", &c).unwrap_err(), AuthRefusal::Untrusted);

    // authentic but wrong capability / scope
    assert_eq!(verify_passport_signed(&v, &good, "other-cap", "read", &c).unwrap_err(), AuthRefusal::WrongCapability);
    assert_eq!(verify_passport_signed(&v, &good, CAP, "write", &c).unwrap_err(), AuthRefusal::MissingScope);
}
