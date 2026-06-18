//! Sanitized, in-memory SparkCRM-shaped webhook fixtures (LAB-MACHINE-SPARKCRM-SERVER-APP-SHADOW-P2).
//!
//! Strictly local: no file loading, no network, no real vendor data. Every value is fabricated for
//! the shadow harness. These mimic the *shape* of vendor auction webhooks (lead / bid / status) so
//! `SparkCrmApp` normalization + duplicate-key extraction can be exercised offline.

use serde_json::{json, Value};

/// A new-lead webhook carrying a vendor auction id in the body (no `x-auction-id` header). Stable
/// identifying fields are present so the composite-key path is also exercisable.
pub fn lead_intake() -> Value {
    json!({
        "auction_id": "AUC-LEAD-1001",
        "lead": { "external_id": "lead_9982" },
        "phone": "+1-555-0100",
        "email": "ada@example.test",
        "campaign": "spring-auctions",
        "value_cents": 1500
    })
}

/// A bid webhook for an active auction. Carries a bid amount that becomes the capsule `base`.
pub fn lead_bid() -> Value {
    json!({
        "auction_id": "AUC-BID-2002",
        "lead": { "external_id": "lead_9982" },
        "bid_amount_cents": 4200,
        "campaign": "spring-auctions"
    })
}

/// A status-update webhook (conversion / dropout / vendor receipt).
pub fn lead_status() -> Value {
    json!({
        "auction_id": "AUC-STAT-3003",
        "lead": { "external_id": "lead_9982" },
        "status": "converted",
        "value_cents": 9000
    })
}

/// A lead with NO auction id and NO idempotency-key, but with stable identifying fields — exercises
/// the deterministic composite-key path.
pub fn lead_composite_only() -> Value {
    json!({
        "lead": { "external_id": "lead_7777" },
        "phone": "+1-555-0199",
        "email": "grace@example.test",
        "campaign": "fall-auctions",
        "value_cents": 800
    })
}

/// A webhook with no auction id, no stable identifying fields, and no idempotency-key — keyless.
pub fn lead_keyless() -> Value {
    json!({
        "lead": { "external_id": "lead_0000" },
        "note": "no identifying fields"
    })
}
