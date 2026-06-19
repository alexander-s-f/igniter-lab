# Reconciler Pressure Registry

Created: 2026-06-14 (off-track app — pulled from `igniter-view-engine/fixtures`:
epistemic_outcome / outcome_variant / failure_taxonomy)

`reconciler` is a pure **epistemic reconciliation service**: an external request
(e.g. a payment charge) is dispatched, and its reply may be acked-2xx (real),
2xx-but-model-only (inferred), 5xx (failed), or **LOST** (silent). Under the
"unknown external state" doctrine (**Covenant P15**), a timeout is not a failure
and a lost confirmation is not a success. The core classifies the raw signal into
an epistemic `Outcome` and routes it to a safe action — retrying only when safe,
reconciling while budget remains, and never upgrading model evidence to real.

## Baseline

Dual-toolchain CLEAN (verified via the Open3/multifile-resolver subprocess route).

```bash
cd igniter-compiler
cargo run -- compile \
  ../igniter-apps/reconciler/types.ig ../igniter-apps/reconciler/classify.ig \
  ../igniter-apps/reconciler/route.ig ../igniter-apps/reconciler/engine.ig \
  ../igniter-apps/reconciler/example.ig --out /tmp/reconciler.igapp
```

| Metric | Value |
|---|---|
| Ruby | ok / 0 diagnostics |
| Rust | ok / 0 diagnostics |
| source files | 5 |
| types | 3 |
| variants | 1 (`Outcome` — **7 epistemic arms**) |
| contracts | 20 |
| match sites | 6 (routing + payload extraction, all over the variant) |
| call_contract sites | 31 (Tier-1 literals — static dispatch) |
| entrypoint | `RunReconcileLoop` |
| source_hash | `sha256:429edba0bb16849cb9a124d64b490ff7b3a867311d5c9054429cdf43b2018210` |

> NOTE: verify Rust via the clean subprocess route (Open3 + mktmpdir); the package
> writer can emit a spurious "Internal compiler error" under rapid/redirected
> stdout. Ruby cross-module uses `MultifileResolver#resolve` → classify → typecheck.

## Provenance (fixture → app)

| Fixture | reconciler model |
|---|---|
| `outcome_variant/outcome_variant_rich.ig` (rich payload variant + match) | `variant Outcome` + the `Route*`/`Outcome*` match contracts |
| `failure_taxonomy/network_timeout_unknown_state.ig` (dispatch/ack honesty) | `classify.ig` ClassifyOutcome (P15 5-branch logic) |
| `epistemic_outcome/*` (7-kind outcome vocabulary, budget routing) | `Outcome` arms + budget-aware UnknownWithBudget/NoBudget |
| `stdlib_outcome/*` (kind:String + or_else/map_get) | `OutcomeKind` log label + `or_else(map_get(meta,…))` |

## Pressures

| ID | Name | Evidence | Status | Route |
|---|---|---|---|---|
| RC-P01 | **variant/match is load-bearing** | the 7 `Outcome` arms (Real/Model/FailedRetryable/UnknownWithBudget/UnknownNoBudget/UpstreamUnavailable/Denied) CANNOT be a stringly `kind`; each has distinct routing + payload. `match` is mandatory. | POSITIVE — capability | regression evidence for `LANG-SUMTYPE-CONSTRUCT-MATCH` |
| RC-P02 | **no-upward-coercion (epistemic honesty)** | `SucceededModel ≠ SucceededReal`: model evidence routes to `needs_human_review`, never `accept`. Encodes Covenant P15 in the type, not a convention. | POSITIVE | keep as canon-pressure evidence (epistemic-outcome canon-vs-lab gap) |
| RC-P03 | **idempotency gate (Covenant P16)** | `ApplyIdempotencyGate` downgrades retry/reconcile to `hold` when no idempotency key — a stringly post-hoc guard; a typed capability would be cleaner. | ACTIVE — design | idempotency-as-capability / typed action variant |
| RC-P04 | **fold-over-state / ServiceLoop (manual unroll)** | `Reconcile3` hand-unrolls 3 attempts because state-threaded `fold` and a managed reconcile/poll loop are unavailable; wants `clock.every` probe spacing. | ACTIVE | `LANG-FOLD-STRUCT-ACCUMULATOR` + ServiceLoop/`PROP-037` |
| RC-P05 | **Map construction not ergonomic** | a `Map[String,String]` literal can't be built in source (`map_from_pairs`/`map_empty` → `OOF-TY1`, param types not inferred); metadata must be INJECTED. | ACTIVE — stdlib gap | `LANG-STDLIB-MAP` construction (typed `map_from_pairs`/literal) |
| RC-P06 | **Option/Map read is the one dual-clean path** | `or_else(map_get(metadata, "trace_id"), "none")` is the only dual-clean Option reader; `match` on `Option` is still blocked (`OOF-KIND4`). | ACTIVE | `LANG-SUMTYPE-CONSTRUCT-MATCH-P2` (Option matchability) |
| RC-P07 | **action is stringly (no Action variant)** | routes return `String` actions ("accept"/"retry"/…); a sealed `Action` variant would make the consumer exhaustive too. Kept String to mirror the fixtures' KDR. | ACTIVE — design | sealed `Action` variant once sumtype construct/match lands |
| RC-P08 | **effect surface — the probe + retry are IO** | every `DispatchSignal` is the result of an external probe (network/storage read); a real reconciler dispatches retries (effect) and persists receipts (effect). All injected here. | DOCUMENTED — behind | `PROP-035` effect surface + IO-runtime + ServiceLoop |

## Capability Discovery (positive)

This app is the fleet's **strongest variant/match showcase**: a 7-arm sealed
`Outcome` with payload binding across `String` / `Integer` / `Map[String,String]`,
exhaustive match in every router, and variant-value passthrough through `if/else`
branches (`Reconcile3`). It proves variant/match is production-ready for epistemic
routing — exactly the surface `LANG-SUMTYPE-CONSTRUCT-MATCH-P1` (76/76) targeted.

## Safety Interpretation

Proves the language can model the **unknown-external-state doctrine** as a pure,
typed, fail-closed core: timeout↛failure, lost-confirmation↛success,
model↛real. It does NOT claim: any network/storage IO, real retry dispatch, a
clock/poll source, receipt persistence, or a running reconcile loop.

## Non-Goals

- No network / HTTP / storage IO; no real retry dispatch.
- No clock / `now()` / poll scheduler.
- No `Map` construction (metadata injected).
- No dynamic dispatch (static, name-based).
- No nullable runtime; `Outcome` is a sealed variant.
- No effect-surface / ServiceLoop implementation (pressure, not a fix).

## Recommended Route

1. Keep as **regression evidence** for `LANG-SUMTYPE-CONSTRUCT-MATCH` (RC-P01/P02/P06).
2. `LANG-STDLIB-MAP` construction (RC-P05) — small, high-value ergonomics.
3. `LANG-FOLD-STRUCT-ACCUMULATOR` + ServiceLoop/`PROP-037` for the reconcile loop (RC-P04).
4. Effect surface + idempotency-as-capability (RC-P03/P08) once the IO membrane lands.

## Wave P13 Appendix Check (2026-06-15)

Ruby: ok/0. Rust: ok/0. Source files: 5. outside active fleet; appendix clean. This directory has a pressure registry but remains outside the 20-app active fleet metric inherited from Wave P12, so it is not counted as a P13 regression or resolution.
