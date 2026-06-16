# Card: LAB-MACHINE-CAPABILITY-IO-SIGNED-PASSPORT-P21 — verifiable passport signatures

> **Front door:** [`LAB-MACHINE-CAPABILITY-IO-MILESTONE-P1`](LAB-MACHINE-CAPABILITY-IO-MILESTONE-P1.md);
> meta focus [`…-PRODUCTION-HARDENING-P17`](LAB-MACHINE-CAPABILITY-IO-PRODUCTION-HARDENING-P17.md) (blocker #4a).

**Status: CLOSED 2026-06-16 — passport authority is verifiable.** 5 machine tests
(`tests/capability_io_signed_passport_tests.rs`); default suite green (242). Design doc:
`lab-docs/lang/lab-machine-capability-io-signed-passport-p21-v0.md`.

## Gap

P5's `evidence_digest` was opaque — the host could fabricate any passport. The trust model was
"assume the host wired it." P21 makes authority verifiable.

## Fix

`capability.rs`: `sign_passport(issuer_key, passport)` (blake3 keyed-hash MAC over
`subject|capability_id|sorted-scopes|issued_at|expires_at` — binds identity + validity; NOT
revoked, NOT the sig); `PassportVerifier{trusted_keys}.is_authentic` (constant-time `Hash` compare);
`verify_passport_signed` (authenticate → then P5 checks); `run_effect_with_verified_passport`
(refuse before executor). `AuthRefusal::Untrusted`. Opt-in — presence-only path untouched, zero
churn (existing `"sig"` evidence is simply unauthentic on the verified path).

Local symmetric MAC only — no asymmetric PKI / OAuth / JWT (later slice), like the deferred TLS dep.

## Proof (5)

valid signed → authorizes + receipt; untrusted/bogus sig → refused (no executor/receipt);
tampered (added scope) → no escalation; signed-but-expired/revoked/wrong-scope still refused;
unit refusal taxonomy. `authority_digest` now includes the signature → replay requires the SAME
signed passport.

## Closed

Local keyed-hash MAC only. No asymmetric PKI/OAuth/JWT. No secret-provider change (P22). No live
network. Presence-only path untouched.

## Next

#4b `LAB-MACHINE-CAPABILITY-IO-SECRET-PROVIDER-P22` (env/file/vault-like secret interface) → #5
observability → #6 load test → (#7 human-gated live).
