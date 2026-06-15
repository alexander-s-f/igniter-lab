# VM RUN-OK Recheck P3 - 2026-06-15

**Card:** `LAB-VM-RUN-OK-RECHECK-P3`  
**Authority:** evidence-only runtime recheck; no source files modified  
**Proof runner:** `igniter-view-engine/proofs/verify_lab_vm_run_ok_recheck_p3.rb`

## Result

The active registry-backed runtime fleet remains **25 apps**. Fresh compile + VM run
evidence gives **RUN-OK 24/25**.

Delta vs P2: **+1**. `spreadsheet` moved from RUN-NOT-OK to RUN-OK after
`LAB-FUNCTION-SIR-RUNTIME-P1` materialized app-local `def` functions into executable SIR
and the VM static function registry. `rule_engine` remains the single non-green app and
stays governance-gated.

The resolved spreadsheet owner class is the former **function SIR/runtime substrate**
blocker from P2.

## Active Fleet

| app | selected entrypoint | runtime status | source hash |
|---|---:|---|---|
| `advanced_logistics` | `RunDailyRoutesDemo` | RUN-OK | `sha256:5f3101fd7661057fa62cc09b735dc324ecb4e2b4b4d46865180bced6605a77a5` |
| `air_combat` | `RunDuel` | RUN-OK | `sha256:45a48b34a061ef4c7f5782f04039f9773e963ffd20b006f64b966aa52975d767` |
| `arch_patterns` | `RunFullScenario` | RUN-OK | `sha256:3a2a43fba745d43d2cded9f151ed45aa2c6fae1b80404cd8237d7545ffba0cf3` |
| `audit_ledger` | `BalanceAsOfDay5` | RUN-OK | `sha256:a36b339b5e22c554451f89f5f2c12aea9c93fc4a835e1a8d0b111c5575fab42c` |
| `batch_importer` | `RunImport` | RUN-OK | `sha256:50f3627e53492da89914c7e9e8af93c6086c0ce80be75bb3b250b7897e2baafa` |
| `bloom_filter` | `RunBloomExample` | RUN-OK | `sha256:7b8b985333f4ac46eee3cc828ece8e81d81a62c496658f627a604368b0638756` |
| `bookkeeping` | `ComputeAccountBalance` | RUN-OK | `sha256:d0299d01e68173a56d79ed1a63872a0aa28f9c7f24583366ddb1c9a3f21453c0` |
| `call_router` | `RunConnectedMatched` | RUN-OK | `sha256:ed6d81148c1c49de71250d3df22aa6ae4d664e4245fc15ea202e6865597339ed` |
| `dataframes` | `RunDataFrameExample` | RUN-OK | `sha256:46a50095ff53ae098ed0b131c63de510634b22249223c909b8563482e0c784d1` |
| `decision_tree` | `RunLoanExample` | RUN-OK | `sha256:88b2795e68bcf82d4f0a231df635dda5d321fc60cae8a78a4593e448445720b4` |
| `dsa` | `RunArrayExample` | RUN-OK | `sha256:ab92780a15fc37f71e15515822eb176c61fc39bb5b499b1f0f58a6a0f007b448` |
| `erp_logistics` | `RunBestRoute` | RUN-OK | `sha256:7e33d8aee91f696e6a1453a09decc4b220d3b237e34ab5f620d63271c6991149` |
| `igniter_parser` | `RunParseDemo` | RUN-OK | `sha256:77a60f0cc78c5e26de267c336a2a587caf742e0950e8f57177b6e2f7a881ae8f` |
| `job_runner` | `RunSuccessSecond` | RUN-OK | `sha256:41e9af571d7d7197cf5aa64ffee37bc22bc65f031faa12c4f547fbb375e7b329` |
| `lead_router` | `RunAccept` | RUN-OK | `sha256:203d3209a678a0d49ad501e4f6c9b4c8035d98948603a3c2036a28d0f44d5cba` |
| `neural_net` | `RunInference` | RUN-OK | `sha256:cbee0e2247cc223758372d78947241f399943d4db244e0bb2b34cfc50ce60c5e` |
| `query_engine` | `RunQuery` | RUN-OK | `sha256:60975b2e273ef103354a3658d0c2745afcf91d83034b3ca6ccfb7cca798be935` |
| `reconciler` | `RunReconcileLoop` | RUN-OK | `sha256:34fdba42b363978913536cc25e4438ea3831bcdcc30dbacee0027f4c8142ed08` |
| `rule_engine` | `RunRuleEngine` | COMPILE-NOT-OK | `sha256:36aa0fd65ffce6db0f1c0b162934bba43bdf450ac0be9cd4585e48620410b8c8` |
| `sim_framework` | `RunEcosystemSim` | RUN-OK | `sha256:c8c5eb5f145e5fcdf45d4b30d8ad514ca27f5bf1c53744d978068f607cb49642` |
| `spreadsheet` | `RunWorkbookDemo` | RUN-OK | `sha256:412ec0f347efc63f726dedefc95ae492b4b75e0ae3a3c4966277c050d0533644` |
| `trade_robot` | `RunTradingBot` | RUN-OK | `sha256:ed207e4085898ce234ad1e754e1fa881dcd564d5fbb3ba11f5b68e365e8e0f2b` |
| `vector_editor` | `RunCanvasClickDemo` | RUN-OK | `sha256:c0b20e11d0ec0e9ea3edccc4aa26a48f704aea01912cf9a9649b0f64c218624e` |
| `vector_math` | `Vec2Example` | RUN-OK | `sha256:721581f2881c98234f976e5e9a04f66ffa1ad66ebae13484346736f738d575d9` |
| `web_router` | `RunArticle` | RUN-OK | `sha256:e6ff9b78b98aa6ab639816213a08fdcddcb5bb3962ae703a02f77050b2ae54a2` |

## Delta

| app | P2 status | P3 status | evidence |
|---|---|---|---|
| `spreadsheet` | RUN-NOT-OK (`Unsupported operator: eval_expr`) | RUN-OK | SIR now has `functions` entries for `eval_expr` and `eval_ref`; VM result is `[{"kind":"Number","num_val":7.0,"str_val":null}]` |

## Non-Green Owner

| app | status | owner class | evidence | next route |
|---|---|---|---|---|
| `rule_engine` | COMPILE-NOT-OK | governance-gated dynamic dispatch | compile remains fail-closed on `Unknown.action` + `expected RuleDecision, got Unknown` | `LAB-DYNAMIC-CONTRACT-DISPATCH-P2` selected safe route / ledger D-001 |

## Boundaries

- No compiler changes.
- No VM changes.
- No app migrations.
- No app `.ig` source files modified.
- Compile status and runtime status remain separate.
- No pressure resolution is claimed without live runtime evidence.
