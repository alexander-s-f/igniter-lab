# lab-machine-service-ingress-duplicate-policy-p7-v0 — configurable ingress duplicate policy

**Card:** `LAB-MACHINE-SERVICE-INGRESS-DUPLICATE-POLICY-P7` (front door:
`LAB-MACHINE-AGENT-COORDINATION-META-P1`)
**Status:** CLOSED — implemented + proven. 8 machine tests
(`tests/service_ingress_duplicate_policy_tests.rs`); full machine suite green. Builds on P5
(`ServiceRecipe`) + P6 (ingress). **Loopback only; one production pool; no outbound HTTP; no
SparkCRM prod; no distributed/multi-instance dedup.**

## The split (the key idea)

```text
idempotency  = safety envelope     (always enforced: same key + different payload → conflict)
duplicate policy = business strategy (configurable on the ServiceRecipe / route, NOT canon)
```

Dedup is **not** a canonical default. A vendor's "dumb webhook system" that fires 5–6 identical
requests is a **business lever**, not just a nuisance: answering each duplicate with a *distinct*
generated code (UPI / offer) raises the auction win rate. The platform must not bake morality
in — it gives the developer/business an explicit, audited knob.

## Duplicate modes

| mode | meaning | use |
|---|---|---|
| `dedup_strict` | repeat → recorded response, **no re-activation** | payments / writes / irreversible |
| `treat_as_fresh` | repeat **re-activates**; each gets a deterministic `attempt_index`; audit-linked | the auction case: same input → distinct code |
| `bounded_fresh(n)` | first `n` repeats re-activate, then `after_limit` (`dedup_last` \| `deny`) | Alex's case: `max_fresh: 6`, seed `attempt_index`, then dedup |
| `off` / `None` | no tracking, every request fresh (P6 behavior) | default |

Safety invariant kept across all modes: **same key + different payload → conflict** (409),
unless the policy explicitly sets `variant_payload`.

## Implementation

- `coordination::DuplicatePolicy { mode, key_header, max_fresh, after_limit, seed_field,
  variant_payload, require_key }` — a field on `ServiceRecipe` (so it is config, not VM
  behaviour). Serialized in the recipe fact.
- `coordination::{record_ingress_dedup, ingress_dedup_history}` — duplicate-tracking facts in
  `__ingress_dedup__`, keyed by `route:duplicate_key`.
- `ingress::{DuplicateDecision, decide_duplicate}` (pure) + `IngressRouter::apply_duplicate` —
  the ingress reads the recipe's policy, extracts the duplicate key (per `key_header`), computes
  the payload digest, reads history, decides, and either replays / conflicts / denies (no
  activation) or invokes fresh — **injecting the `attempt_index` into the recipe's `seed_field`**
  so the capsule can mint a distinct response per duplicate.

## Proof (8 tests — 9 acceptance criteria)

| # | acceptance | test |
|---|---|---|
| 1 | `dedup_strict`: repeat returns recorded response, no re-activation | `dedup_strict_replays_no_activation` |
| 2,4,5 | `treat_as_fresh`: same input → distinct code per attempt (1000/1001/1002) | `treat_as_fresh_distinct_code_per_attempt` |
| 3 | `bounded_fresh(3)`: first 3 fresh, 4th dedups to last | `bounded_fresh_then_dedup_last` |
| 3 | `bounded_fresh(2)` + `deny`: 3rd → 429 | `bounded_fresh_then_deny` |
| 6 | same key + different payload → 409 conflict | `same_key_different_payload_conflict` |
| 6 | `variant_payload=true` permits different payloads | `variant_payload_allowed_when_policy_opts_in` |
| 7 | dedup facts record `duplicate_key`, `attempt_index`, `decision` | `dedup_facts_record_key_attempt_decision` |
| 8,9 | policy lives in the recipe (round-trips); missing key + `require_key` → 400 | `policy_in_recipe_and_missing_key_required` |

The auction proof (`treat_as_fresh_distinct_code_per_attempt`): three identical webhooks
(`{base:1000}`, key `E1`) → three real activations → **1000, 1001, 1002** (the `Offer` capsule
computes `code = base + attempt`, with `attempt` injected by ingress).

## Decisions

- **Policy on the recipe, not the language/VM** — the capsule contract only ever sees a normal
  input (`attempt`); it has no knowledge of duplicate policy.
- **Conflict is the safety floor** — same key + different payload is 409 unless `variant_payload`.
- **Every duplicate is audit-linked** — `__ingress_dedup__` facts carry key, attempt, decision,
  payload digest, recorded response; the ingress audit reason carries `mode:decision`.
- **Missing-key behavior is configurable** — `require_key` (reject) implemented; allow-fresh =
  the fall-through; synthesize is a noted future option.
- **Deterministic `attempt_index`** = the count of prior fresh attempts; the service seeds its
  distinct output from it.

## Closed (held)

Loopback only. One production pool. No outbound HTTP / SparkCRM prod / credentials. No
distributed cache / multi-instance dedup (single fact log). No language/VM change. No hidden
behavior — every decision is a fact.

## Alex's auction config (now first-class, audited)

```text
duplicate_policy:
  mode: bounded_fresh
  key_header: x-vendor-event-id
  max_fresh: 6
  seed_field: attempt
  after_limit: dedup_last
```

## Next route

- multi-instance / distributed duplicate dedup (federation-adjacent; needs a shared key index).
- `synthesize` missing-key behavior; richer `dedup_response_only` (new correlation, no mutation).
- P8 `pool_sizing` / `activate_many` replica fanout — throughput scaling over the now
  correctness-protected serving path.
