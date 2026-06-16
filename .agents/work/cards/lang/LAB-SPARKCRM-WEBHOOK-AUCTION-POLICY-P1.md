# Card: LAB-SPARKCRM-WEBHOOK-AUCTION-POLICY-P1 — vendor-webhook duplicate strategy (policy)

**Lane:** product-policy / readiness / SparkCRM-shaped · **Skill:** idd-agent-protocol
**Status: CLOSED 2026-06-16.** Policy/readiness artifact — **no code, no live vendor calls.**

> **Deliverable:** [`lab-docs/lang/lab-sparkcrm-webhook-auction-policy-p1-v0.md`](../../../../lab-docs/lang/lab-sparkcrm-webhook-auction-policy-p1-v0.md)
> Formalizes the P7 duplicate policy as an explicit business strategy: repeated vendor webhooks may
> intentionally produce **bounded fresh** attempts with distinct UPI/offer codes when configured —
> auditable, bounded, not canon default.

## Goal

Turn "some auction vendors send 5–6 identical webhooks and distinct responses raise win rate ~5–10%"
into a formal, bounded, measurable policy over the existing P7 mechanism — three profiles, a
recommended auction config, key/seed/code mechanics, a measurement plan, and risk caveats.

## Authority boundary

- **Product meaning:** SparkCRM / Alex.
- **Technical substrate:** `ServiceRecipe.duplicate_policy` (P7) + bridge effect idempotency
  (`ingress.rs::handle_effect`, effect key = `duplicate_key:attempt_index`).
- **Agent authority:** policy/readiness only — no live behaviour.
- **Closed (held):** no code, no SparkCRM prod/staging, no universal-safety claim, no canon feature.

## Verify-first evidence (2026-06-16)

Anchored on live mechanics, not card lore:
- `coordination.rs::DuplicatePolicy{ mode, key_header, max_fresh, after_limit, seed_field,
  variant_payload, require_key }`; modes `dedup_strict|treat_as_fresh|bounded_fresh|off`;
  `after_limit ∈ {dedup_last, deny}`.
- `ingress.rs::decide_duplicate` logic (variant→Conflict; fresh count → attempt_index; bounded cap →
  after_limit) and `handle_effect` effect key `format!("{dkey}:{attempt_index}")`; seed injected via
  `obj.insert(policy.seed_field, attempt_index)`.
- `sparkcrm.rs` — credential is a secret *reference* (`{{secret:sparkcrm_token}}`), `Authorization`
  redacted before the receipt fact.

## Key decisions

- idempotency = safety envelope (always on; same key + different payload → 409); duplicate_policy =
  business strategy (configurable, not canon default).
- **bounded_fresh > treat_as_fresh** for vendors (cap effects; abuse-resistant); `dedup_strict` for
  any financial/irreversible/abuse-sensitive case (§10).
- Codes are **deterministic in `attempt_index`**, generated in the capsule (replay/recovery-safe).
- The +5–10% claim is a **hypothesis to measure** (A/B by recipe), unproven until §8 runs.

## Acceptance (all met)

Idempotency-vs-policy stated · recommended auction recipe config · 3 profiles (strict / bounded /
off) · measurement plan for +5–10% · risk/compliance caveats without moralizing · `dedup_strict`
cases enumerated · no live calls, no implementation.

## Next route

Policy/readiness only. If pursued: a per-vendor recipe registry of profiles; wire the §8 metrics from
existing facts (`__ingress_dedup__` + `__receipts__`) into the operator console
(`LAB-MACHINE-OPERATOR-CONSOLE-P1`); confirm vendor-contract permission before any staging. Optional
pointer from the live-gate packet (auction policy is a business lever the gate should note).
