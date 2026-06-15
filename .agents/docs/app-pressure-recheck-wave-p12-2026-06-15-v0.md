# APP-RECHECK-WAVE-P12

**Date:** 2026-06-15
**Scope:** 20-app fleet compile evidence and registry updates only.
**Prior wave:** APP-RECHECK-WAVE-P11 (15/16 DUAL-CLEAN)

Wave P12 refreshes the existing fleet plus four new companion apps:
`audit_ledger`, `batch_importer`, `job_runner`, and `web_router`.

This is an evidence-only recheck. Lab results do not create canon authority, the
external ecosystem report remains evidence rather than authority, and no old Ruby
framework surface is used as language authority.

---

## Method

Fresh compiles were run for every active fleet app using all `.ig` files in that
app directory.

- Ruby: `IgniterLang::CompilerOrchestrator.compile_sources` from `igniter-lang`.
- Rust: `cargo run --quiet -- compile ... --out /private/tmp/p12_<app>_rust.igapp`
  from `igniter-lab/igniter-compiler`.
- OOF outputs were captured from live compiler JSON; failed compiles do not emit
  `.igapp` artifacts.

No app source, compiler source, runtime source, migration, or canon file was
edited for this wave.

---

## Fleet Membership

The active P12 fleet has 20 apps:

1. `advanced_logistics`
2. `air_combat`
3. `arch_patterns`
4. `audit_ledger`
5. `batch_importer`
6. `bloom_filter`
7. `call_router`
8. `dataframes`
9. `decision_tree`
10. `dsa`
11. `igniter_parser`
12. `job_runner`
13. `lead_router`
14. `neural_net`
15. `rule_engine`
16. `sim_framework`
17. `trade_robot`
18. `vector_editor`
19. `vector_math`
20. `web_router`

Other app directories with registries exist in `igniter-apps`, but they were not
part of the P12 card's active fleet list.

---

## Fleet Status

| App | Source files | Ruby | Rust | Status | Notes |
|---|---:|---|---|---|---|
| advanced_logistics | 4 | ok/0 | ok/0 | DUAL-CLEAN | unchanged clean app |
| air_combat | 8 | ok/0 | ok/0 | DUAL-CLEAN | unchanged clean companion app |
| arch_patterns | 5 | ok/0 | ok/0 | DUAL-CLEAN | unchanged clean app |
| audit_ledger | 4 | ok/0 | ok/0 | DUAL-CLEAN | newly integrated P12 companion app |
| batch_importer | 3 | ok/0 | ok/0 | DUAL-CLEAN | newly integrated P12 companion app |
| bloom_filter | 4 | ok/0 | ok/0 | DUAL-CLEAN | unchanged clean app |
| call_router | 6 | ok/0 | ok/0 | DUAL-CLEAN | unchanged clean companion app |
| dataframes | 4 | ok/0 | ok/0 | DUAL-CLEAN | unchanged clean app |
| decision_tree | 4 | ok/0 | ok/0 | DUAL-CLEAN | unchanged clean app |
| dsa | 6 | ok/0 | ok/0 | DUAL-CLEAN | unchanged clean app |
| igniter_parser | 4 | ok/0 | ok/0 | DUAL-CLEAN | unchanged clean app |
| job_runner | 4 | ok/0 | ok/0 | DUAL-CLEAN | newly integrated P12 companion app |
| lead_router | 4 | ok/0 | ok/0 | DUAL-CLEAN | unchanged clean companion app |
| neural_net | 5 | ok/0 | ok/0 | DUAL-CLEAN | unchanged clean app |
| **rule_engine** | 4 | **oof/2** | **oof/2** | **BLOCKED** | intentional fail-closed dynamic dispatch boundary |
| sim_framework | 7 | ok/0 | ok/0 | DUAL-CLEAN | unchanged clean app |
| trade_robot | 7 | ok/0 | ok/0 | DUAL-CLEAN | unchanged clean app |
| vector_editor | 4 | ok/0 | ok/0 | DUAL-CLEAN | unchanged clean app |
| vector_math | 6 | ok/0 | ok/0 | DUAL-CLEAN | unchanged clean app |
| web_router | 3 | ok/0 | ok/0 | DUAL-CLEAN | newly integrated P12 companion app |

**Fleet total: 19/20 DUAL-CLEAN** (+4 apps vs Wave P11).

---

## Delta vs Wave P11

| App group | Wave P11 | Wave P12 | Net |
|---|---|---|---|
| 15 clean apps from P11 | DUAL-CLEAN | DUAL-CLEAN | unchanged |
| `audit_ledger` | not in fleet | DUAL-CLEAN | NEW - temporal/audit pure core |
| `batch_importer` | not in fleet | DUAL-CLEAN | NEW - partial-success importer pure core |
| `job_runner` | not in fleet | DUAL-CLEAN | NEW - Sidekiq-shaped job/retry pure core |
| `web_router` | not in fleet | DUAL-CLEAN | NEW - Rack-shaped router/response pure core |
| `rule_engine` | BLOCKED oof/2 + oof/2 | BLOCKED oof/2 + oof/2 | unchanged |

No existing app regressed.

---

## New Companion Apps

| App | Positive evidence | Main pressure routes |
|---|---|---|
| `audit_ledger` | pure bitemporal/append-only ledger core using explicit Integer time axes, filter, and fold | `PROP-022` History/BiHistory, Decimal/Money, fold-to-struct, effect-surface provenance |
| `batch_importer` | pure partial-success import receipt using user variant `RowResult`, map/filter/count, and match predicate | `LANG-SUMTYPE-CONSTRUCT-MATCH`, indexed map/enumerate, parse/storage effects |
| `job_runner` | pure static job dispatch and bounded retry receipt with sealed `JobOutcome` | `PROP-039` BudgetedLocalLoop Ruby parity, typed contract registry, ServiceLoop/effect surface |
| `web_router` | pure HTTP route and response composer using stdlib.text routing plus sealed `ContractResult` | `LANG-SUMTYPE-CONSTRUCT-MATCH`, `LANG-STDLIB-MAP`, split/Option typing, ServiceLoop/microservice envelope |

These are lab evidence surfaces only. They do not authorize BiHistory, Result,
queues, sockets, Rack compatibility, runtime effects, or canon language decisions.

---

## rule_engine

`rule_engine` remains the only non-clean app, and this is still the selected
safe route from `LAB-DYNAMIC-CONTRACT-DISPATCH-P2`.

```text
Rust: oof / 2
  [OOF-P1] Unresolved field: Unknown.action (node: active_decisions)
  [OOF-TY1] Output type mismatch: expected RuleDecision, got Unknown (node: decision)

Ruby: oof / 2
  [OOF-P1] Unresolved symbol: d (node: active_decisions)
  [OOF-P1] Unresolved field: Unknown.action (node: active_decisions)
```

Root cause remains Tier 2 dynamic contract dispatch (`call_contract(r, tx)`) plus
fail-closed Unknown field/output boundaries. No source migration was selected.

---

## Closed Surfaces

- No app source edits.
- No compiler or runtime source edits.
- No migrations.
- No implementation.
- No IO/runtime work.
- No canon decisions.
- No source formatting churn.
