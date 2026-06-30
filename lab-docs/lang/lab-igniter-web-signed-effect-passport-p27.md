# LAB-IGNITER-WEB-SIGNED-EFFECT-PASSPORT-P27

Status: DONE
Date: 2026-06-27
Lane: igniter-lab / web / igniter-web / foundation-hardening / T1
Authority: lab proof only; `igniter-lang` canon unchanged.

## Scope

This slice wires the IgWeb machine/effect host path to the signed machine
passport data-plane introduced by `LAB-MACHINE-SIGNED-PASSPORT-DATAPLANE-P26`.
It does not change `.igweb` syntax, route lowering, app contracts, Postgres
executor semantics, or public bind behavior.

## Mint / Sign / Verify Path

- `server/igniter-web/src/host_binding.rs`
  - The real postgres write host now creates host-owned signing material inside
    `build_write_host_from_resolved`.
  - The coordination passports and effect passport are minted with
    `sign_passport`.
  - The returned `WriteHostComponents` carries a matching `PassportVerifier`.
- `server/igniter-web/src/bin/igweb-serve.rs`
  - The real machine-mode write bridge passes
    `effect_passport_verifier: Some(&state.effect_verifier)`.
  - The fallback no-op effect host remains unsigned and unbound; it still
    fails closed when no real write binding exists.
- `runtime/igniter-machine/src/ingress.rs`
  - `EffectBridgeConfig` now accepts an optional `PassportVerifier`.
  - When present, `IngressRouter::handle_effect` calls
    `run_write_effect_atomic_signed`; otherwise legacy proof call-sites keep
    using `run_write_effect_atomic`.

The signing key is host-owned and process-local. `.igweb` app code never sees,
chooses, serializes, or receives the key, verifier, capability id, operation,
or scope. Effect identity, correlation id, and idempotency key construction are
unchanged.

## Tests

Commands run from `igniter-lab`:

```text
cd runtime/igniter-machine && cargo test
cd server/igniter-web && cargo test --features machine --test signed_effect_passport_tests --test todo_postgres_effect_host_tests --test todo_postgres_effect_host_runner_tests --test async_machine_runner_tests --test readthen_socket_runner_tests --test igweb_serve_machine_mode_tests --test todo_igweb_serve_e2e_tests
cd server/igniter-server && cargo test --features machine --test effect_machine_tests --test sparkcrm_shadow_tests
```

Key new coverage:

- `server/igniter-web/tests/signed_effect_passport_tests.rs`
  - `forged_effect_passport_is_refused_at_web_effect_host_boundary`
  - `valid_signed_effect_passport_still_commits`

The forged test proves the executor attempt count stays `0` when the effect
passport is unsigned/forged. The valid test proves the same IgWeb effect-host
contour still commits through a fake local executor.

## Follow-Up

The production host-config shape still has no explicit durable signing-key
injection field. This slice therefore uses a smallest host-owned process-local
key seam for real write-host construction and deterministic keys only inside
tests. A future host-config card can add operator-provided signing-key material
without changing `.igweb` app authority.
