# lab-machine-service-recipe-p5-v0 — dev→prod handoff + agentless serving

**Card:** `LAB-MACHINE-SERVICE-RECIPE-P5` (front door:
`LAB-MACHINE-AGENT-COORDINATION-META-P1`)
**Status:** CLOSED — the bridge is built + proven. 7 machine tests
(`tests/coordination_recipe_tests.rs`); full machine suite green. Builds on P2 (pools/ACL),
P4 (transfer + `recipe_digest`). **Same machine; no external HTTP server, no messenger hot path,
no federation.**

## The bridge (the original vision, now real)

```text
agent-built candidate capsule           (P2 pool; P4 transfer carried a recipe_digest)
  -> developer SIGNS a ServiceRecipe     (root-of-trust; capsule_digest + entry + scopes)
  -> the pool becomes `production`, owned by the developer/system
  -> a vendor / runtime-actor passport INVOKES the entry contract
  -> invocation = REAL capsule activation (resume bytes + dispatch), NOT a message
  -> an audit/receipt fact is written
```

A dozen agents build a service, hand the candidate + recipe to the developer, he signs and
deploys, and a dumb production mode serves vendor webhooks — all on the same audited substrate.

## Implementation (in `coordination.rs`)

- `ServiceRecipe { recipe_id, capsule_digest, entry_contract, input_schema_digest,
  capability_bindings, required_scopes, receipt_policy, retry_policy_ref, pool_sizing,
  created_by, accepted_by, accepted_at }` — the deploy descriptor; the capsule is the immutable
  image, the recipe is "how to run it". Stored as a fact in `__recipes__` (keyed by pool).
- `accept_recipe(dev, pool, recipe)` — developer-only (root-of-trust) sign-off: the recipe's
  `capsule_digest` must be present in the pool; the pool is promoted to `Production` and owned by
  the developer; the recipe fact records `accepted_by`/`accepted_at`. Audited.
- `invoke(passport, pool, inputs)` — runtime-actor serving: validates an accepted recipe + a
  `Production` pool + the caller's passport carries the recipe's `required_scopes` + an invoke
  grant (`ActivateCapsule`) + the pool's capsule digest matches the recipe; then **activates the
  capsule** (`IgniterMachine::resume_bytes` + `dispatch(entry_contract, inputs)`) and writes an
  audit fact. Returns the typed result.

The invocation is a real activation: the test capsule is a genuine `.igm` image (a machine with
the `Add` contract, checkpointed); `invoke` resumes it and dispatches → `5` / `42`.

## Proof (7 tests — 10 acceptance criteria)

| # | acceptance | test |
|---|---|---|
| 2,3 | developer signs the recipe; pool → production, owned by developer | `dev_signs_recipe_promotes_to_production` |
| 4,6,7 | vendor passport invokes via real activation; audited | `vendor_can_invoke_production_service` |
| 5 | agent without an invoke grant cannot invoke | `agent_without_invoke_grant_refused` |
| 8 | N replicas sharing one content_digest = homogeneous service image (one stored image) | `homogeneous_replicas_same_digest` |
| 9 | recipe whose capsule digest isn't in the pool is refused | `capsule_digest_mismatch_refused` |
| 6,10 | invocation is activation (real dispatch), not messenger; no IO receipts | `invocation_is_activation_not_messenger` |
| 1,e2e | full bridge: transfer (recipe_digest) → accept → sign → invoke → `42` | `full_handoff_via_transfer_then_invoke` |

## Decisions

- **Developer = production sign-off** (root-of-trust): only a `Developer`-kind agent can
  `accept_recipe`; the pool then becomes developer-owned `Production`.
- **Invocation = capsule activation**, never a message: `resume_bytes` + `dispatch`. The
  dispatched contract body does no IO (the VM path has no executor registry) and there is no MCP
  hot path — it is an in-process host call.
- **Homogeneous = content-addressed**: replicas share one `content_digest` (one stored image);
  `invoke` picks by digest, so "which replica" is moot.
- **Digest match enforced** at both sign (recipe digest must be in the pool) and invoke (pool's
  capsule must match the signed recipe) — a mismatched image is refused.
- **`required_scopes`** ties the recipe to the caller: the invoking passport must carry them.

## Closed (held)

Same machine. No external HTTP server / network ingress (invocation is in-process; a real HTTP
front door is a later card, and would reuse the P10/P11 HTTP executor as INGRESS). No messenger
in the hot path. No federation. No autonomous scheduler. No language/VM change (serving runs the
existing pure `dispatch`). No MCP hot path. No crypto signatures (the developer's acceptance is
an audited fact, not a cryptographic signature yet).

## Next route

- a real **HTTP ingress front door** for production pools (vendor webhook → passport → `invoke`),
  reusing the capability-IO HTTP work as the inbound edge; ties the two tracks fully together.
- `pool_sizing`-driven replica activation / load spreading (the pool already proves homogeneity;
  `activate_many` is the concurrency primitive).
- P-votes (agents organize proposals internally) — the deferred social layer.
- later: federation (multi-machine), cryptographic recipe signatures.
