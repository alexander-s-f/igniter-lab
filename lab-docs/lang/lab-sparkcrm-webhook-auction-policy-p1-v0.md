# SparkCRM vendor-webhook auction policy — design / readiness (P1, v0)

**Card:** `LAB-SPARKCRM-WEBHOOK-AUCTION-POLICY-P1` · **Lane:** product-policy / readiness / SparkCRM-shaped
**Scope:** **policy/readiness only.** No code, no SparkCRM prod/staging, no live vendor calls, no canon feature.

> **Authority.** Product meaning = **SparkCRM / Alex**. Technical substrate = the **P7**
> `ServiceRecipe.duplicate_policy` + the bridge effect-idempotency path (verified in
> `coordination.rs` / `ingress.rs`). This doc formalizes a *business* policy over an existing,
> tested mechanism — it adds no primitive. Whole-wave context:
> [`lab-machine-io-wave-digest-p1-v0.md`](lab-machine-io-wave-digest-p1-v0.md).

---

## 0. The load-bearing distinction

```
Idempotency      = SAFETY ENVELOPE.   Always on. Not configurable.
                   identity = duplicate_key + payload_digest.
                   Same key + different payload → 409 Conflict (variant_payload=false).
                   One effect per (key, attempt_index). Replay never re-performs an effect.

duplicate_policy = BUSINESS STRATEGY. Configurable per recipe/route. NOT a canon default.
                   Decides what a *repeated vendor webhook* MEANS: replay it, or mint a new
                   bounded attempt with a distinct UPI/offer code.
```

A repeated webhook is **not** automatically a duplicate to suppress. For some auction vendors it is
a *fresh competitive opportunity*. The policy makes that choice **explicit, bounded, and audited** —
never an accident, never silent.

---

## 1. Which vendor behaviours justify `bounded_fresh`?

`bounded_fresh` is justified **only** when *all* hold:

- the vendor **intentionally re-sends** the same logical event N times (observed: ~5–6 identical
  auction webhooks) as part of a competitive/auction protocol, **not** as accidental retries;
- responding with a **distinct offer/UPI code per send is allowed by the vendor contract** and
  improves outcome (win rate), i.e. the vendor evaluates each response independently;
- the action is **economically idempotent enough** that N bounded attempts are acceptable (lead/offer
  generation), **not** a financial write where N attempts = N charges.

If repeats are accidental retries, or the vendor treats multiple responses as abuse, or the
downstream effect is a money movement → **`dedup_strict`** (§10).

---

## 2. Exact duplicate-key source

The key is the **duplicate identity** for the auction event. Recommended precedence:

1. **Vendor-provided event/auction id** (header or body field) when the vendor sends a stable id per
   logical auction — *preferred* (precise, vendor-authoritative).
2. **Composite** `{lead_natural_key + auction_window}` when no stable id exists (e.g. phone/email +
   campaign + coarse time bucket) — derive deterministically, document the recipe.
3. **`idempotency-key` header** as the transport default (`key_header`, default `idempotency-key`)
   when the vendor sets one.
4. **Correlation id** is the *effect-side* join (receipt ↔ reconcile/lookup), **not** the duplicate
   key — keep them distinct.

`require_key=true` for any auction recipe: a missing duplicate key → **400** (never silently treat a
keyless webhook as fresh). `variant_payload` stays **false** — same key + changed payload is a
**409 Conflict**, the safety invariant.

---

## 3. Attempt seed field

The deterministic `attempt_index` (0,1,2,…) is injected into the recipe's **`seed_field`** (default
`"attempt"`) of the capsule input *before activation* (verified: `ingress.rs` injects
`obj.insert(policy.seed_field, attempt_index)`). The capsule mints its offer/UPI code as a pure
function of its inputs **including** the seed — so attempt N is deterministic and reproducible.

- Pick a `seed_field` the capsule actually consumes (e.g. `"attempt"` or `"offer_seed"`).
- The seed is an **index, not randomness** — replay/recovery reproduce the same code.

## 4. UPI / offer code generation from `attempt_index`

- Code = `f(stable_lead_fields, attempt_index)` — **deterministic, pure, in the capsule** (never an
  ambient counter, never wall-clock, never RNG → preserves replay/recovery).
- attempt_index = 0 is the first/primary code; 1..n are the bounded fresh variants.
- The generation function lives in the **capsule (product logic)**, not the substrate. The substrate
  only guarantees a distinct, deterministic `attempt_index` per accepted duplicate and **one effect
  per `(duplicate_key, attempt_index)`**.

---

## 5. `max_fresh` per vendor

- A **per-vendor** value on the recipe (`max_fresh`), matched to the vendor's observed re-send count
  and contract. Observed auction range ~5–6 → a typical `max_fresh` of **5–6**, not unbounded.
- `treat_as_fresh` (unbounded) is **discouraged** for vendors — it lets a misbehaving/abusive sender
  multiply effects without limit. Prefer `bounded_fresh` with an explicit cap.
- Tune from data (§8), not by guess; lower the cap if marginal attempts stop converting.

## 6. After the limit: `after_limit`

`after_limit ∈ { "dedup_last", "deny" }` (verified):

- **`dedup_last`** (recommended for auctions): past `max_fresh`, replay the *last* recorded response —
  no new effect, vendor still gets a coherent answer.
- **`deny`**: past `max_fresh`, return **Denied** (429-style) — use when extra sends past the cap
  should be actively rejected (stricter, e.g. abuse suspicion).
- Default in code if unspecified is `dedup_last`. State it explicitly in the recipe regardless.

---

## 7. How effect idempotency derives from duplicate key + attempt

Verified mechanism (`ingress.rs::handle_effect`): the effect idempotency key is

```
effect_idem = format!("{duplicate_key}:{attempt_index}")
```

so the duplicate policy **directly bounds effect count**:

- `dedup_strict` → exactly **one** effect ever (every repeat replays the recorded response, no 2nd effect);
- `bounded_fresh(n)` → **up to n** distinct-keyed effects (the auction leads), each with its own receipt;
- a **single replica** serves each request → **≤ 1 effect** per accepted attempt; **fanout never
  performs effects** (diagnostic only). Unknown effect → **202** + correlation.

This is the safety hinge: business "freshness" can only ever produce as many effects as the
*explicit, bounded* attempt count — and each is individually receipted, correlated, and auditable.

---

## 8. Measurement plan for the +5–10% claim

The "+5–10% win rate" is a **hypothesis to measure**, not an established fact. Minimum instrumentation
(all derivable from existing facts: `__ingress_dedup__` + `__receipts__`):

| Metric | Source | Use |
|---|---|---|
| duplicate count per auction key | `__ingress_dedup__` history length | confirm vendor really re-sends N |
| attempts per key + decision | dedup facts (`attempt_index`, `decision`) | bounded-fresh actually firing |
| **win / vendor-accept rate** by attempt_index | join effect outcome ↔ vendor result feed | does attempt 1..n convert? |
| response latency per attempt | receipt timestamps | freshness not bought with latency |
| effect count vs cap | receipts per key | confirm ≤ `max_fresh`, no runaway |

**Method:** A/B by recipe — `dedup_strict` (control) vs `bounded_fresh(n)` (treatment) on comparable
auction traffic; compare win rate with a significance test; watch for vendor-side penalty (accept-rate
drop, throttling). Promote the cap only if the lift is real and the vendor doesn't penalize. Treat the
+5–10% as **unproven until this runs**.

---

## 9. Three profiles (recipe config)

| Profile | `mode` | `max_fresh` | `after_limit` | `variant_payload` | `require_key` | Use |
|---|---|---|---|---|---|---|
| **Strict (financial/write)** | `dedup_strict` | — | — | `false` | `true` | money movement, ledger, any non-multiplicable write. One effect ever; repeats replay. |
| **Bounded auction** | `bounded_fresh` | per-vendor (e.g. 5) | `dedup_last` | `false` | `true` | auction vendors that re-send and reward distinct offers. n distinct codes, then replay. |
| **Diagnostic / off** | `off` | — | — | n/a | n/a | lab/observation only; **never production** — no dedup tracking, every request fresh. Use to study a vendor's send pattern, then choose a real profile. |

Recommended **auction default**: `bounded_fresh`, `max_fresh=5`, `after_limit=dedup_last`,
`seed_field="attempt"`, `variant_payload=false`, `require_key=true` — tune `max_fresh` from §8.

---

## 10. Cases that MUST use `dedup_strict`

- Any **financial / ledger / payment** write (N attempts = N charges — never).
- Any effect with **irreversible or costly** external side effects not designed for multiplication.
- Vendors whose contract treats **multiple responses as abuse / fraud**, or that **dedupe on their
  side** (extra attempts wasted or penalized).
- **Accidental** retries (network, vendor at-least-once delivery) where repeats carry the *same*
  intent — replay, never re-issue.
- When in doubt → `dedup_strict`. Freshness is opt-in, per vendor, with evidence.

---

## 11. Risk / compliance / partner notes (factual, non-moralizing)

- **Contractual:** minting distinct offers per re-send must be **permitted by the vendor agreement**.
  If the vendor expects one canonical response per event, bounded_fresh may breach the integration
  contract — confirm before enabling.
- **Abuse symmetry:** the same mechanism that boosts win rate can look like response-spam to a vendor;
  monitor accept-rate and throttling (§8) and keep `max_fresh` bounded.
- **Auditability:** every attempt is a fact (`__ingress_dedup__` + receipt) with key/attempt/decision/
  correlation — the policy is **fully reconstructable** for a partner or compliance review.
- **Determinism:** codes are deterministic in `attempt_index` → reproducible under replay/recovery,
  so an audit can re-derive exactly what was sent and why.
- **No universal-safety claim:** this policy is **not** safe for all effects or all vendors. It is a
  per-recipe, per-vendor, bounded, measured choice. Default stays conservative (`dedup_strict`).

---

## Boundary recap

- idempotency = safety envelope (always on); duplicate_policy = business strategy (configurable, not canon).
- Recommended auction recipe config provided (§9); three profiles defined.
- Measurement plan defined for the +5–10% claim (§8) — claim treated as unproven until measured.
- Risk/compliance caveats stated without moralizing (§11); `dedup_strict` cases enumerated (§10).
- No code, no live vendor calls, no prod/staging change, no canon feature, no universal-safety claim.

*Policy/readiness only. Product authority = SparkCRM/Alex. Compiled 2026-06-16.*
