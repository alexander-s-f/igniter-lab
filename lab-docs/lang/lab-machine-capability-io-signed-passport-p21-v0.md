# lab-machine-capability-io-signed-passport-p21-v0 — verifiable passport signatures

**Card:** `LAB-MACHINE-CAPABILITY-IO-SIGNED-PASSPORT-P21` (production-hardening blocker #4a, meta
`LAB-MACHINE-CAPABILITY-IO-PRODUCTION-HARDENING-P17`)
**Status:** CLOSED — passport authority is now verifiable. 5 machine tests
(`tests/capability_io_signed_passport_tests.rs`); default suite green (242).
**Boundary held:** local keyed-hash MAC only — no OAuth/JWT/asymmetric PKI; no secret plumbing
(that is P22); no live network.

## The gap

P5 gave a typed `CapabilityPassport`, but `evidence_digest` was **opaque** — never verified. The
host could fabricate any passport (any subject, any scopes). The trust model was "the host wired
it correctly." That is the weakest part of the security story.

## Fix — signed passports

`capability.rs`:
- `sign_passport(issuer_key, passport) -> String` — a blake3 **keyed-hash MAC** over the
  passport's canonical material: `subject | capability_id | sorted-scopes | issued_at |
  expires_at`. The signed material binds the identity AND the validity window — the scope set
  cannot be widened after signing. (NOT `revoked` — revocation is host-side runtime state; NOT
  the signature itself.) The hex goes in `evidence_digest`.
- `PassportVerifier { trusted_keys }` — `is_authentic(passport)` returns true iff the signature
  verifies under some trusted issuer key (constant-time `blake3::Hash` compare; invalid-hex →
  false).
- `verify_passport_signed(verifier, passport, capability_id, required_scope, clock)` —
  authenticate first (`Untrusted` if not), THEN the P5 validity checks (capability / scope /
  expiry / revoked). Returns the authority digest.
- `run_effect_with_verified_passport(...)` — the effect entrypoint that requires a signed
  passport; refusal happens before the executor, no receipt.

`AuthRefusal::Untrusted` added.

**Opt-in, zero churn**: the presence-only (`run_effect_with_passport`) and verified paths
coexist (the P5 pattern). Existing tests' bogus `evidence_digest: "sig"` is simply not authentic
under the verified path; the presence-only path is unchanged.

## Why a local MAC (not PKI yet)

A blake3 keyed hash is a real symmetric MAC — it proves the passport was issued by a holder of a
trusted key, with zero new dependencies. Asymmetric signatures (ed25519) / OAuth / JWT issuer
discovery are a deliberate later slice (same discipline as the deferred TLS dep). The point of
P21 is the *shape*: authority is verified, not assumed.

## Proof (5 tests)

| claim | test |
|---|---|
| a valid signed passport authorizes + writes a receipt | `valid_signed_passport_authorizes` |
| untrusted issuer / bogus signature → refused before executor, no receipt | `untrusted_signature_refused` |
| tampering (adding a scope after signing) breaks authenticity → no escalation | `tampered_passport_cannot_escalate_scope` |
| signed but expired / revoked / wrong-scope still refused (P5 checks remain) | `signed_but_expired_revoked_or_wrong_scope_still_refused` |
| `verify_passport_signed` refusal taxonomy (Untrusted / WrongCapability / MissingScope / Ok) | `verify_passport_signed_unit` |

`replay requires same authority digest` is automatically strengthened: `authority_digest`
includes `evidence_digest` (now the signature), so replaying requires the SAME signed passport.

## Closed

Local keyed-hash MAC only. No asymmetric PKI / OAuth / JWT / issuer discovery. No secret
provider change (P22). No live network. The presence-only path is untouched (opt-in).

## Next

#4b **`LAB-MACHINE-CAPABILITY-IO-SECRET-PROVIDER-P22`** — replace the map-only secret provider
with an env/file/vault-like interface (secrets never enter contract inputs; missing → refuse
before send; redaction preserved). Then #5 observability → #6 load test → (#7 human-gated live).
