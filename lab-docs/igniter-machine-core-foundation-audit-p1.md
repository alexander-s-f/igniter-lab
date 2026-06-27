# IGNITER-MACHINE-CORE-FOUNDATION-AUDIT-P1 - fresh verify-first audit of the production data-plane

Status: OPEN - findings (no code changed)
Lane: igniter-lab / runtime / igniter-machine / foundation-hardening
Type: audit / fresh verify-first (security-focused)
Date: 2026-06-26
Skill: idd-agent-protocol

> Refresh note 2026-06-27: this remains a 2026-06-26 audit snapshot. Some
> findings below have since closed; route current work through
> `lab-docs/igniter-foundation-hardening-roadmap-p1.md` and
> `lab-docs/lang/lab-audit-foundation-status-refresh-p2-v0.md`, not the
> `Status: OPEN` line alone.

## Onboarding

Lab/frontier evidence, not authority. Code-first verify-first SECURITY audit of
`igniter_machine` (Rust, ~13.2k LOC src) — the production data-plane (capability-IO,
passport, durable store, Postgres/SparkCRM executors, HTTP ingress, MCP server). 6
parallel subsystem audits + reads of `IMPLEMENTED_SURFACE.md` and `secrets.rs`. Do
NOT lean on PROP-042; the code is truth. Classify BLOCKER / PROBLEM / INSIGHT.

## Executive Decision

```text
decision=AUDIT - the machine ships PROVEN security/durability primitives but the production data-plane calls the UNSAFE variant of each; the boundary is mature, the wiring is not
severity=high: 11 BLOCKERS across security(forgeable authority + no-auth MCP + arbitrary write), transport(plaintext + unbounded + untimed inbound), durability(no fsync, silent truncation, in-process-only CAS), coordination(dedup TOCTOU)
good_news=GENUINELY STRONG: SQL injection CLEAN (typed plans, bound params, host-bound identifiers); outbound TLS verification intact (no dangerous()); crypto primitive correct (keyed-MAC, constant-time); idempotency two-layered + no-blind-retry; ingress auth-gated before activation; serving concurrency structurally safe; factstore P3 hardened (atomic+fsync+corruption-refused)
root_cause=5th audit, sharpest form - the SAFE primitive EXISTS and is tested (signed passport P21, atomic single-flight P18, durable recovery P19, secret providers P22) but production authenticates/serializes/persists through the UNSAFE variant. Integration gap, not a design gap. "Same forgeability outcome as the VM, different cause: VM=no primitive; MACHINE=unused primitive"
keystone=wire the proven primitives onto the data-plane (verify_passport_signed at 4 call sites; prepared-as-CAS; inbound timeout+body-cap; MCP passport gate) + treat "bind non-loopback" as a security gate
next=IGNITER-MACHINE-WIRE-SIGNED-PASSPORT-P2 + IGNITER-MACHINE-INBOUND-HARDENING-P2 + IGNITER-MACHINE-DURABLE-CAS-P2 + IGNITER-MACHINE-MCP-AUTH-P2
architectural_decision_needed=yes - the loopback invariant is load-bearing for ~6 blockers; the "human-gated live" step (#7) is exactly where they all activate
```

## GOOD NEWS — verified strong (this crate earns it)

- **SQL injection: CLEAN.** Contracts emit a typed `QueryPlan`/`PostgresWriteIntent`,
  never SQL. Values are always bound params (`$1..$n`, `= ANY($n)`); identifiers are
  allowlisted **and** quoted (`postgres_real.rs:36`); on the **write** path table/columns
  are host-bound at `connect()` — the contract cannot even name an identifier
  (`postgres_real.rs:436`). Raw-SQL keys are refused structurally. A genuinely strong boundary.
- **Outbound TLS verification intact** — `with_safe_defaults()`, no `dangerous()`/
  accept-invalid anywhere; self-signed → `CertInvalid` (fails closed) (`http.rs:665`).
- **The crypto primitive itself is correct** — `sign_passport`/`is_authentic` use
  `blake3::keyed_hash` (a real keyed MAC) compared via constant-time `Hash==`
  (`capability.rs:225/277`). No homegrown crypto.
- **Idempotency is sound and two-layered** — machine receipt (payload-digest-bound) +
  PG-side `effect_receipts` in ONE atomic writable-CTE; no-blind-retry; fresh-key-per-attempt;
  reconcile-before-reissue. The **logic** layer is well-designed.
- **Ingress is auth-gated before activation** — no unauthenticated→effect path on the HTTP
  front door (`ingress.rs:214/383`); host effect-passport distinct from vendor passport.
- **Serving concurrency is structurally safe** — `FuturesUnordered` polled by one task, no
  `tokio::spawn`, no `&mut hub` during serve, no lock-across-await.
- **Factstore P3 hardened** — atomic temp→fsync→rename, corruption observable+refused (no
  silent `unwrap_or_default` loss). `FileSecretProvider` traversal-safe; request-side
  secrets never logged/serialized.

## Root cause (one; 5th audit running, sharpest form)

**The machine ships PROVEN security/durability primitives but the production data-plane
calls the UNSAFE variant of each.** `verify_passport_signed` (P21), `run_write_effect_atomic`
(P18), `recover_dangling_writes` (P19), the secret providers (P22) all exist and pass tests
— yet production authenticates with the forgeable `verify_passport`, the durable store has no
CAS, the inbound edge has no TLS/caps, and the MCP edge has no auth at all. The safe path sits
*next to* the unsafe one production uses. This is an **integration gap, the most fixable kind**
— same "declared/model right, enforcement not wired" pattern as the TBackend, compiler, stdlib,
and VM audits, here at the highest maturity.

## BLOCKERS

### A. Security — authority is forgeable / unenforced on the production path

**B-A1. Signed-passport (P21) is dead code; production authenticates with the FORGEABLE
`verify_passport`.** All production callers — `coordination.rs:304` (`guard`), `:625`
(`authed`), `write.rs:232`, `service_loop.rs:213` — call `verify_passport` (`capability.rs:197`),
which checks only `capability_id`/`revoked`/`expires_at`/scope and **never** the signature;
`evidence_digest` is folded into `authority_digest` via a *keyless* `blake3::hash` (identity
fingerprint, not a MAC). Zero `src/` callers of `verify_passport_signed` (grep-confirmed). A
caller hand-builds `{subject:"developer", scopes:["grant_access"], revoked:false,
expires_at:1e18, evidence_digest:"anything"}` and passes. **Same forgeability as the VM,
different cause (unused primitive).**

**B-A2. Self-elevation to Developer → full ACL bypass.** `pool_authorized` grants if
`owner || is_developer || granted` (`coordination.rs:282`); `is_developer` is keyed on the
unauthenticated `passport.subject` (`:357`); `register_agent` is **un-passported** (no `guard`,
`:395`). So forge/self-register a `Developer` subject → bypass the ACL on every pool. The ACL
is structurally sound but sits behind a forgeable identity. `revoked` is likewise self-attested
(a field the caller presents; never checked against host revocation state).

**B-A3. The MCP server is entirely UNAUTHENTICATED — any client gets full machine control.**
`bin/mcp.rs` has no passport/token/gate; `tools/call` (`mcp.rs:922`) dispatches straight to
handlers. Any process speaking JSON-RPC on stdio can load/dispatch contracts, write/query/
time-travel arbitrary facts, snapshot/fork state, and checkpoint to disk. It bypasses the entire
capability model that `ingress.rs:214` enforces.

**B-A4. `igniter_checkpoint` is an arbitrary-filesystem-write primitive.** Client-supplied
`path` passed unvalidated to `std::fs::write(path, bytes)` (`mcp.rs:601` → `machine.rs:436`) —
no allowlist/sandbox/traversal check. With B-A3 (no auth) = arbitrary write to any path the
process can reach (`~/.zshrc`, cron, ssh config), with attacker-influenced content.

### B. Transport — the inbound front door is plaintext + unbounded + untimed

**B-B1. Unbounded request-body read → OOM DoS.** `read_one_request` (`ingress.rs:1053`) loops
`while buf.len() < need` where `need` derives from the attacker-controlled `Content-Length`,
with **no max-body ceiling**. (Outbound has `max_body_bytes=1<<20`; inbound has none.) A single
client OOMs the data-plane.

**B-B2. No read timeout → slowloris.** Zero `tokio::time::timeout` on inbound socket reads. One
slow client blocks all serving (sequential) or holds a `max_in_flight` slot forever (concurrent).

**B-B3. Inbound TLS does NOT exist — the front door is plaintext TCP.** All rustls usage is the
**outbound client**; there is no `TlsAcceptor`/`ServerConfig` anywhere (grep-confirmed).
`serve_once` reads/writes cleartext — bearer tokens + webhook bodies cross the inbound wire
unencrypted. Acceptable **only** under the loopback invariant; zero confidentiality the moment it
binds non-loopback.

### C. Durability — the substrate floor under the (good) logic layer

**B-C1. WAL acks on `flush()` only — no `fsync`; power-loss loses acked facts.**
`WALWriter::append` flushes the `BufWriter` to the OS and returns Ok (`wal.rs:39`); `write_fact`
acks the caller (`machine.rs:367`). Survives a process crash, **not** a power loss. The struct is
named "WAL." (Same TBackend pattern.)

**B-C2. WAL silently truncates on a mid-log torn/corrupt record.** Replay `break`s unconditionally
on the first short/CRC-bad record (`wal.rs:62`) → discards every valid record **after** it,
returned as `Ok` with no signal. Defensible for the tail, silent data loss mid-log.

**B-C3. `single_flight` is in-process only; the durable store has no CAS on `prepared` → multi-
process double-execute.** `single_flight.rs:28` is a `HashMap<tokio::Mutex>` in ONE process
(doc concedes multi-process needs a distributed lock). In `write.rs` the read-receipt check
(`:253`) and the `prepared` write (`:304`) are two separate calls with no atomic guard;
`MpkFileBackend::write_fact` is an unconditional append (`backend.rs:308`), never a conditional
insert. Two processes/replicas both read "no receipt" → both prepare → both execute. The
data-plane is explicitly "replica fanout," so multi-process-on-one-key is the normal case.

### D. Coordination — dedup TOCTOU

**B-D1. The duplicate-policy decision is TOCTOU.** `ingress.rs:486` reads `ingress_dedup_history`
and decides; the recording fact isn't written until `:688`. Two concurrent same-key requests both
read empty history → both decide `Fresh{attempt_index:0}`. `SingleFlight` collapses *identical*
keys to one effect (good), BUT for `bounded_fresh`/`treat_as_fresh` both pick the **same**
`attempt_index`, so the bound is under-counted — `bounded_fresh(1)` can let 2+ "fresh" effects
through. The "ONE effect" milestone is conditional on serialization the concurrent decision layer
removed.

## PROBLEMS

- **Response bodies stored verbatim in receipts** (`http.rs:293` → `write.rs:197`) — redaction
  covers the request side only; an upstream API's response body (a created lead's PII, a returned
  token) lands UNREDACTED in the durable fact store, reachable via `igniter_query_facts` with no
  auth (B-A3). Asymmetric redaction.
- **Reconcile digest-exact read-back is brittle → can authorize double-execute.** "Did our value
  land" = `blake3(serde_json::to_string(value))` exact match (`reconcile.rs:105`). Any substrate
  canonicalization / added field / float reformat → digest miss → mis-classify as
  `permanent_failure` → retry authorizes a fresh re-issue (`retry.rs:107`) → **double-execute**.
  The whole no-blind-retry invariant rests on digest-exact read-back.
- **Secret redaction is a 5-name header allowlist** — a secret in a non-allowlisted header name
  (`x-custom-token`) escapes the `redacted_headers` record and enters the digest material
  (`http.rs:111/131`); `{{secret:}}` resolution is **headers-only** (a ref in the body passes
  through literally).
- **`RemoteTcpBackend::all_facts()` returns empty unconditionally** (`backend.rs:482`) → recovery
  (`recovery.rs:38`) and retry-queue drain (`retry_queue.rs:209`) are silent no-ops over a remote
  receipts store.
- **Receipt finalize tie-breaks on coarse `f64` wall-clock** (`latest_for` `max_by` ties →
  insertion order; `FixedClock` makes `prepared`/terminal identical) → "latest terminal wins" holds
  by lucky append order, no monotonic seq.
- **Retry-queue `Blocked` has no exit / no DLQ** (`retry_queue.rs:312`) → permanently stuck items
  accumulate invisibly (compounded by the remote `all_facts` no-op).
- **MpkFileBackend rewrites the entire per-key file on every append** (`backend.rs:287`) →
  O(n) write-amp on hot receipt keys; one decode failure kills the whole key history.
- **Bearer token compare is `HashMap::get` (not constant-time); tokens cleartext at rest.** HTTP
  method parsed but never authorized. Duplicate-header last-wins → latent smuggling if keep-alive
  is ever added.
- **SparkCRM `correlation_id` raw-interpolated into the URL query** (`sparkcrm.rs:180`), no
  percent-encoding → parameter smuggling (bounded: allowlisted host).
- **Postgres:** `eq null` binds as `= ''` not `IS NULL` (read/write inconsistency); "test DB only"
  is a **convention, not a runtime gate** (no DSN/db-name check); `NoTls` both adapters; reads fully
  materialize rows (no streaming/byte-budget → wide-column OOM).
- **Signed passports (even when wired) have no not-before/nonce/jti** → a leaked valid passport
  replays until expiry; `expires_at:None` never expires.
- **MCP robustness:** `&id[..8]` byte-slice panics on short/non-ASCII fact ids (`mcp.rs:531/589`);
  `SystemTime…unwrap()` panics if clock < 1970 (`mcp.rs:460`); a client can write reserved stores
  (`__orchestrator_audit__`, `RECEIPTS_STORE`) → **forge receipts/audit, poisoning observability +
  orchestrator recovery**; unbounded line read (OOM).

## INSIGHTS

- **I1. The primitives are excellent and tested; the blockers are wiring.** "Promote the proven
  slice to the data-plane" — swap call sites, don't redesign. The most fixable kind of finding.
- **I2. The LOGIC layer (write gate, no-blind-retry, reconcile, compensation, SQL boundary) is
  genuinely well-designed; the weak parts are the DURABILITY SUBSTRATE below** (fsync, CAS, remote
  `all_facts`) **and the AUTHORITY WIRING above** (unsigned passport, MCP no-auth).
- **I3. The loopback invariant is load-bearing for ~6 blockers** (plaintext ingress, cleartext
  tokens, NoTls Postgres, no-auth MCP, no body cap/timeout). The whole security posture hinges on
  never binding non-loopback. **`IMPLEMENTED_SURFACE.md` says "only #7 human-gated live remains" —
  and #7 is exactly where every transport/auth blocker activates simultaneously.** This is the
  single most important strategic framing.
- **I4. MCP determinism leak:** the MCP binary reaches around the clean `ClockProvider` seam to
  raw `SystemTime` (`mcp.rs:460`) → MCP-written facts are non-reproducible, breaking the replay
  invariant the library otherwise preserves (clock injected everywhere else).
- **I5. The crypto is right, the redaction philosophy is right, the SQL boundary is right** — this
  crate clears the bar the others reach for, which is exactly why the unwired enforcement is the
  story, not absence.

## SUPER-COOL (high-leverage)

- **S1. One-line-of-wiring closes the #1 security hole.** Thread a `PassportVerifier` into
  `CoordinationHub`/ServiceLoop and swap the 4 production sites (`coordination.rs:304/625`,
  `write.rs:232`, `service_loop.rs:213`) `verify_passport` → `verify_passport_signed`. Primitive,
  tests, and `AuthRefusal::Untrusted` already exist. + a NEGATIVE test (forged `evidence_digest`
  must be REFUSED) makes it un-regressable — today such a passport is *accepted* everywhere.
- **S2. Promote `prepared` to a durable CAS → delete `single_flight`, get multi-process
  exactly-once for free.** `pure_core.rs:188` already exposes `push_once(before_append)` — a
  compare-and-set. Wire `MpkFileBackend` (and `RemoteTcpBackend`) onto it and the gate is correct
  across processes. The hard part exists one crate over.
- **S3. Monotonic per-receipt sequence → deterministic replay + tie-free.** `(transaction_time,
  seq)` with `seq` tie-break makes "latest terminal wins" a proof not an accident, and turns the
  WAL into a replay-to-a-point log — feeding the emergence "time-travel-via-replay" line.
- **S4. Wrap the MCP edge in the passport model that already exists** (ingress already does
  verified-passport-before-activation) → per-tool authz (read-only agents get `query_facts` but not
  `write_fact`/`checkpoint`) + a reserved-store firewall + response-body redaction as one "fact
  hygiene" layer. Closes B-A3/B-A4 and the receipt-leak/store-poison problems together.
- **S5. Inbound hardening in ~6 lines + symmetric TLS.** `tokio::time::timeout` + a
  `MAX_REQUEST_BYTES` check (mirror the outbound `max_body_bytes`) closes B-B1/B-B2. A
  `TlsAcceptor` variant of `serve_once` (the rustls dep is already pinned behind `tls`) gives
  inbound HTTPS + optional **mTLS** — turning the cleartext bearer token into a second factor
  behind a verified client cert (B-B3).
- **S6. Typed `CorrelationId` newtype with a charset invariant** closes the URL-injection edge
  structurally (same philosophy as the raw-SQL refusal) and guards every URL/log/receipt
  interpolation for free. Pair with reference-aware redaction (track values resolved from
  `{{secret:}}`).
- **S7 (keystone). Make "bind non-loopback" an explicit SECURITY GATE.** The human-gated-live step
  (#7) must depend on a checklist — {signed passport wired, inbound TLS, body cap+timeout, MCP
  auth, Postgres TLS, response-body redaction} — not just a deploy. Most of the transport/auth
  blockers are dormant-on-loopback and live-on-bind; gating the bind on the checklist converts ~6
  blockers into one decision.

## Keystone recommendation

- **IGNITER-MACHINE-WIRE-SIGNED-PASSPORT-P2** — S1 (+ negative test). Closes B-A1/B-A2.
- **IGNITER-MACHINE-MCP-AUTH-P2** — S4. Closes B-A3/B-A4 + receipt-leak/store-poison.
- **IGNITER-MACHINE-INBOUND-HARDENING-P2** — S5. Closes B-B1/B-B2/B-B3.
- **IGNITER-MACHINE-DURABLE-CAS-P2** — S2 (+ fsync on the WAL, non-silent recovery). Closes
  B-C1/B-C3 (+ B-C2).

The boundary is mature; the work is **connecting the proven primitives to the production path and
gating the loopback→live transition on a security checklist** — not a redesign.

## Boundary / not covered

Lab evidence only; no code changed. This audit completes the 5-crate series (TBackend → compiler →
stdlib → VM → machine; sibling docs in `lab-docs/`). The Postgres `postgres`/`tls` features and the
SparkCRM executor were read as source; the real-DB/real-TLS integration tests are DSN/feature-gated
and were not executed here.
