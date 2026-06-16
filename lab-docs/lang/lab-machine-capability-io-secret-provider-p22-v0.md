# lab-machine-capability-io-secret-provider-p22-v0 — env/file/layered secret providers

**Card:** `LAB-MACHINE-CAPABILITY-IO-SECRET-PROVIDER-P22` (production-hardening blocker #4b, meta
`LAB-MACHINE-CAPABILITY-IO-PRODUCTION-HARDENING-P17`)
**Status:** CLOSED — secret SOURCE hardened; security blocker #4 fully closed (with P21). 5
machine tests (`tests/capability_io_secrets_tests.rs`); default suite green (253).
**Boundary held:** no real prod secret, no live SparkCRM; no fake "vault" (guardrail).

## The gap

P10/P11 proved that injected credentials are references (`{{secret:name}}`) and that resolved
values are redacted — but the only provider was an in-process `MapSecretProvider`. P22 hardens
where secrets actually come from, without pulling in an external service.

## Fix

`secrets.rs` (all implement the existing `http::SecretProvider` trait):
- `EnvSecretProvider` — reads secrets from process env, **allowlist only**: `allow(name, env_key)`;
  a name not on the allowlist resolves to `None`. A contract cannot pull arbitrary environment.
- `FileSecretProvider` — reads `root/<name>` (trimmed). **Path-traversal-safe**: a name with
  anything other than `[A-Za-z0-9_-]` (so no `/`, `\`, `..`, leading `.`) is rejected → a contract
  cannot read outside the root.
- `LayeredSecretProvider` — tries layers in order, first hit wins (override for tests, layer env
  over file in deployment).

**`SecretProvider` is the adapter interface a real external vault would implement** (caching its
resolved secrets); P22 deliberately does NOT fake a vault — there is no external service in the
glass box. Env/file are the local, dependency-free implementations; a vault adds as another layer.

## Invariants preserved (proven with the REAL providers)

- secret value never enters the receipt / audit / result / error body (redaction, P10/P11) —
  now proven end-to-end with a `FileSecretProvider` through `run_write_effect`;
- contract inputs carry only the `{{secret:name}}` REFERENCE, never the value;
- a missing secret → refuse before send (no transport call);
- redaction of `Authorization`/`Cookie`/… preserved.

## Proof (5 tests)

| claim | test |
|---|---|
| env provider resolves only allowlisted names; unset env → None | `env_provider_resolves_only_allowlisted` |
| file provider reads root, rejects traversal/unsafe names | `file_provider_reads_and_rejects_traversal` |
| layered provider overrides then falls through | `layered_provider_overrides_then_falls_through` |
| a file-sourced secret never lands in the receipt; inputs are reference-only; resolved value DID reach the transport | `file_secret_never_in_receipt_only_reference_in_inputs` |
| a missing secret refuses before send (transport not called) | `missing_secret_refuses_before_send` |

## Closed

No real prod secret, no live SparkCRM, no fake vault. Env/file/layered only. The `SecretProvider`
trait stays the adapter point for a future external vault.

## Security blocker #4 — CLOSED

P21 signed passport (verifiable authority) + P22 hardened secret source = the security-hardening
blocker is closed in the glass box. Authority is signed; credentials come from allowlisted/safe
sources and never leak into any fact.

## Next (P17 order)

#5 observability + dead-letter routing (metrics/tracing over the audit facts; route
`blocked`/`exhausted`/dead-letters to an operator surface) → #6 load test 2–5k rpm → (#7
human-gated live).
