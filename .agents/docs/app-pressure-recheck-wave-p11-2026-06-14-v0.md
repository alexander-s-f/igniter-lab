# APP-RECHECK-WAVE-P11

**Date:** 2026-06-14
**Trigger:** `LAB-AIR-COMBAT-BASELINE-P2`, `LAB-LEAD-ROUTER-BASELINE-P1`, and `LAB-CALL-ROUTER-BASELINE-P1` all CLOSED; Fold P3/P4 already landed.
**Scope:** All 16 fleet apps — evidence and registry updates only; no compiler, runtime, or app source changes.
**Prior wave:** APP-RECHECK-WAVE-P10 (12/13 DUAL-CLEAN)

---

## Fleet Status (Wave P11)

| App | Rust | Ruby | Status | Notes |
|---|---|---|---|---|
| advanced_logistics | ok/0 | ok/0 | DUAL-CLEAN | unchanged clean app from Wave P10 |
| arch_patterns | ok/0 | ok/0 | DUAL-CLEAN | unchanged clean app from Wave P10 |
| bloom_filter | ok/0 | ok/0 | DUAL-CLEAN | unchanged clean app from Wave P10 |
| dataframes | ok/0 | ok/0 | DUAL-CLEAN | unchanged clean app from Wave P10 |
| decision_tree | ok/0 | ok/0 | DUAL-CLEAN | unchanged clean app from Wave P10 |
| dsa | ok/0 | ok/0 | DUAL-CLEAN | unchanged clean app from Wave P10 |
| igniter_parser | ok/0 | ok/0 | DUAL-CLEAN | unchanged clean app from Wave P10 |
| neural_net | ok/0 | ok/0 | DUAL-CLEAN | unchanged clean app from Wave P10 |
| sim_framework | ok/0 | ok/0 | DUAL-CLEAN | unchanged clean app from Wave P10 |
| trade_robot | ok/0 | ok/0 | DUAL-CLEAN | unchanged clean app from Wave P10 |
| vector_editor | ok/0 | ok/0 | DUAL-CLEAN | unchanged clean app from Wave P10 |
| vector_math | ok/0 | ok/0 | DUAL-CLEAN | unchanged clean app from Wave P10 |
| **rule_engine** | oof/2 | oof/2 | **BLOCKED** | intentional fail-closed dynamic dispatch boundary |
| air_combat | ok/0 | ok/0 | DUAL-CLEAN | integrated via LAB-AIR-COMBAT-BASELINE-P2 |
| lead_router | ok/0 | ok/0 | DUAL-CLEAN | integrated via LAB-LEAD-ROUTER-BASELINE-P1 |
| call_router | ok/0 | ok/0 | DUAL-CLEAN | integrated via LAB-CALL-ROUTER-BASELINE-P1 |

**Fleet total: 15/16 DUAL-CLEAN** (+3 apps vs Wave P10: `air_combat`, `lead_router`, `call_router`).

---

## Delta vs Wave P10

| App | Wave P10 | Wave P11 | Net |
|---|---|---|---|
| air_combat | not in fleet | DUAL-CLEAN | NEW — entrypoint rebaseline accepted |
| lead_router | not in fleet | DUAL-CLEAN | NEW — request/reply railway companion accepted |
| call_router | not in fleet | DUAL-CLEAN | NEW — two-stream webhook correlation companion accepted |
| rule_engine | BLOCKED oof/2 + oof/2 | BLOCKED oof/2 + oof/2 | unchanged |
| other 12 apps | DUAL-CLEAN | DUAL-CLEAN | unchanged |

No existing app regressed.

---

## Companion Baselines Integrated

| App | Baseline card | Proof | Entrypoint | Source hash |
|---|---|---|---|---|
| air_combat | `LAB-AIR-COMBAT-BASELINE-P2` | 115/115 PASS | `RunDuel` | `sha256:b3c2bdd046475442d1b78705fbcb9bfda55da09b070df93a3d36ff8f825b0c55` |
| lead_router | `LAB-LEAD-ROUTER-BASELINE-P1` | 175/175 PASS | `RunAccept` | `sha256:3cca9ed52a593e60ed86fb59e359809d255425af5690ded364cd8329fab71e1b` |
| call_router | `LAB-CALL-ROUTER-BASELINE-P1` | 178/178 PASS | `RunConnectedMatched` | `sha256:1b8da43dd1fb66ae6b587056bfe459734e9eb854ccb2a1b308e996ac0334eed5` |

Together these add three distinct companion shapes to the fleet:

- `air_combat`: tick-loop / ServiceLoop pressure.
- `lead_router`: request/reply railway with `variant Pipe` + `match`.
- `call_router`: two-stream webhook correlation + operator state machine.

---

## rule_engine (Unchanged)

`rule_engine` remains the only non-clean app, and this is the selected safe route from `LAB-DYNAMIC-CONTRACT-DISPATCH-P2`.

```text
Rust: oof / 2
  [OOF-P1] Unresolved field: Unknown.action (node: active_decisions)
  [OOF-TY1] Output type mismatch: expected RuleDecision, got Unknown (node: decision)

Ruby: oof / 2
  [OOF-P1] Unresolved symbol: d (node: active_decisions)
  [OOF-P1] Unresolved field: Unknown.action (node: active_decisions)
```

Root cause remains Tier 2 dynamic contract dispatch (`call_contract(r, tx)`) plus fail-closed Unknown field/output boundaries. No source migration was selected.

---

## Fold P3/P4 Impact

`LANG-FOLD-STRUCT-ACCUMULATOR-P3` and `LANG-FOLD-STRUCT-ACCUMULATOR-P4` are both CLOSED, but Wave P11 does not edit app source. The fleet therefore shows no automatic diagnostic delta from fold support: apps with manual fold/unroll/factory shapes remain clean and preserve their pressure IDs as migration/design opportunities.

Notable pressure routes now ready for future app-side migration or follow-up governance:

- `air_combat` AC-P01/AC-P02/AC-P03.
- `lead_router` LR-P02/LR-P03.
- `call_router` CR-P06.
- `trade_robot` TR-P04/TR-P08 family.

---

## Canon Tutorial Boundary

Wave P11 treats `/Users/alex/dev/projects/igniter-workspace/igniter-lang/docs/dev-tutorial.md` as the current canon tutorial/truth snapshot for dual-toolchain readiness. Lab notes remain evidence and do not override canon claims.

---

## Closed Surfaces

- No app source edits.
- No compiler or runtime source edits.
- No IO/runtime work.
- No new OOF codes.
- No canon decisions.
