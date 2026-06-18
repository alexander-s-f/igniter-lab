# lab-machine-sparkcrm-server-app-readiness-p1-v0 — SparkCRM ServerApp Readiness

**Delegation-Code:** `GEMINI-20260618-SERVER-WAVE-B`  
**Card Reference:** `.agents/work/cards/lang/LAB-MACHINE-SPARKCRM-SERVER-APP-READINESS-P1.md`  
**Status:** READINESS PACKET (v0 / Recommended)  
**Scope:** Design and product-shape analysis for a SparkCRM-shaped `ServerApp` running on the loopback server protocol. **No live DB, no live SparkCRM, no credentials, and no public network listeners.**

---

## 1. Candidate Targets (Inbound vs. Outbound Split)

The application protocol isolates the incoming HTTP request path from the host's write capability definitions. The `ServerApp` translates inbound vendor-like webhook payloads to logical, symbolic target names.

### Logical Inbound Targets
We propose the following candidate target names for a SparkCRM-shaped app:
* **`lead-intake`**: Triggered by vendor POST requests when a new lead is proposed. Maps to an effect that registers the lead.
* **`lead-bid`**: Triggered by webhook updates during active auctions to submit bid iterations.
* **`lead-status`**: Triggered by status updates (such as conversions, dropouts, or vendor receipts).

### Outbound Capabilities
These logical targets must remain strictly distinct from host-owned outbound capability/executor
labels such as:
* `SparkCRM.LeadAPI` (an example host capability ID for HTTP API actions)
* `SparkCRM.Storage` (an example host capability ID for local storage/repository actions)

### Privilege Separation Rule
The `ServerDecision` returned by the application MUST NOT carry `capability_id`, `operation`, or `scope` fields. The app only names the logical `target` (e.g. `"lead-intake"`). The host maps this target to its physical routes and configures the `EffectBridgeConfig` under the host's own passport authority. This prevents an application from escalating privileges or requesting arbitrary writes.

---

## 2. Request Normalization & Duplicate Key Precedence

Raw webhook requests from external lead/auction providers vary in format and require normalization inside `ServerApp::call` to yield a stable, local JSON input shape for capsule ingestion.

### Normalized Input Shape (Local Fixture Example)
Raw payloads are parsed and normalized into a clean, reproducible JSON object:
```json
{
  "lead_id": "lead_9982",
  "bid_amount_cents": 1500,
  "attempt": 0
}
```

### Duplicate Key Extraction Precedence
To ensure that duplicate checks map to the same logical event, the `ServerApp` extracts a duplicate key from the request with the following priority order:
1. **Vendor Event/Auction ID**: Extract directly from the vendor's header or body fields (e.g. `X-Auction-ID` or `body["auction_id"]`) if a stable identifier is provided per logical auction event.
2. **Deterministic Composite Key**: If the vendor provides no stable event ID, derive a composite key deterministically from payload fields (e.g., a hash of `phone + email + campaign` concatenated with a coarse-grained hourly bucket).
3. **Idempotency Header Backup**: Fall back to the default `idempotency-key` HTTP header.

### Keyless Request Policy
If no duplicate key can be resolved (e.g., the webhook is missing headers and does not contain identifying body parameters), the `ServerApp` must immediately return `ServerDecision::Respond` with a `400 Bad Request` payload. Keyless requests MUST NOT be assigned randomized keys or treated as silently fresh.

---

## 3. Duplicate and Auction Policy Mechanics

To ensure auction optimization does not compromise transactional safety, we maintain a clear separation between transport idempotency and business-level duplicate policy.

```
Idempotency (Safety Envelope)  ──► Replay prevention. Same key + different payload = 409 Conflict.
Duplicate Policy (Product Strat) ──► Business strategy. Maps repeated webhooks to fresh attempts.
```

### Bounded Fresh Attempts & Seed Generation
For competitive auction providers who intentionally re-send the same lead details to solicit fresh bids, the recipe is configured with the `bounded_fresh(n)` policy (where `n` is matching the vendor's typical retry range, e.g. `max_fresh = 5`).
* For each accepted duplicate webhook up to `max_fresh`, the host increments the `attempt_index` (from `0` to `n-1`).
* The host injects this index into the designated `seed_field` (e.g., `"attempt"`) of the capsule input before execution.
* The capsule computes the unique proposal/UPI code as a deterministic, pure function of the inputs *including* the `attempt_index`. No random numbers or clock values are used, ensuring replayability and recovery determinism.

### Bounding Limit Policy (`after_limit = dedup_last`)
We recommend `after_limit = dedup_last` as a targeted auction profile:
* Once the repeated request count exceeds `max_fresh`, the host stops executing new effects.
* Instead, it returns the cached response of the last successful attempt (`n-1`).
* This ensures that the vendor receives a consistent, valid response without causing runaway resource usage or triggering unauthorized database mutations.

---

## 4. Authority and Human Live Gate Boundaries

This readiness packet serves as evidence for design shape only. It does not grant authority to connect to live services.

### Gated Under the Human Live Gate
The following boundaries remain closed and are not authorized for agent execution:
* **Public Network Listeners**: Live TCP/HTTP servers listening on public IP interfaces.
* **Real Upstreams**: Calling any real SparkCRM API or vendor server.
* **Credentials**: Actual client secrets, bearer tokens, or database credentials.
* **Live Mutating Actions**: Generating side effects on active staging/production tenants.
* **Production Deployments**: Transitioning local fixtures to canonical deployments.

To prevent architectural drift, the next steps must not propose connecting to a live database or integrating with live SparkCRM.

---

## 5. Shadow Path & Next Local Step

To validate this design safely without network IO, we propose a local shadow harness as the next step.

### Suggested Card: `LAB-MACHINE-SPARKCRM-SERVER-APP-SHADOW-P2`
* **Goal**: Implement a local, fixture-only `ServerApp` that consumes recorded offline webhook payloads (mocked vendor requests).
* **Execution**: Route the normalized payloads to produce `InvokeEffect` decisions.
* **Verification**: Run these decisions through local fake executors (simulated machine instances) to confirm that:
  1. Input normalization is correct.
  2. Duplicate keys are extracted reliably.
  3. Bounded attempt indices match the expected sequence.
  4. Response formats match the legacy outcome data (for side-by-side offline comparison of mock conversion rates).
* **Safety**: Performs zero external requests and runs entirely in a disconnected local test environment.
