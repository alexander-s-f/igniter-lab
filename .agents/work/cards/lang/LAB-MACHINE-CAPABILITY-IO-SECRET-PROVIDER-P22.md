# Card: LAB-MACHINE-CAPABILITY-IO-SECRET-PROVIDER-P22 — env/file/layered secret providers

> **Front door:** [`LAB-MACHINE-CAPABILITY-IO-MILESTONE-P1`](LAB-MACHINE-CAPABILITY-IO-MILESTONE-P1.md);
> meta focus [`…-PRODUCTION-HARDENING-P17`](LAB-MACHINE-CAPABILITY-IO-PRODUCTION-HARDENING-P17.md) (blocker #4b — closes #4 with P21).

**Status: CLOSED 2026-06-16 — secret source hardened; security blocker #4 fully closed.** 5
machine tests (`tests/capability_io_secrets_tests.rs`); default suite green (253). Design doc:
`lab-docs/lang/lab-machine-capability-io-secret-provider-p22-v0.md`.

## Gap

P10/P11 proved redaction + `{{secret:name}}` references, but the only provider was the in-process
map. P22 hardens the SOURCE.

## Fix

`secrets.rs` (impl `http::SecretProvider`): `EnvSecretProvider` (allowlist only — non-allowlisted
name → None); `FileSecretProvider` (`root/<name>`, traversal-safe: only `[A-Za-z0-9_-]`);
`LayeredSecretProvider` (first hit wins — override/layer). `SecretProvider` is the adapter point
for a future external vault — P22 does NOT fake one (no external service in the glass box).

## Invariants (proven with the real providers)

secret never in receipt/audit/result/error; inputs carry only the reference; missing → refuse
before send; Authorization/Cookie redacted.

## Proof (5)

env allowlist-only; file reads root + rejects traversal; layered override+fall-through; file
secret never in receipt (resolved value DID reach transport, not the fact); missing → refuse
before send (no transport call).

## Closed

No real prod secret, no live SparkCRM, no fake vault. Env/file/layered only.

## Security blocker #4 CLOSED

P21 (signed passport) + P22 (hardened secret source) = security hardening closed in the glass box.

## Next

#5 observability + dead-letter routing → #6 load test → (#7 human-gated live).
