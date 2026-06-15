# APP-RECHECK-WAVE-P13

**Date:** 2026-06-15
**Scope:** 20-app active fleet compile evidence, registry updates, and appendix checks for registry-bearing non-fleet directories.
**Prior wave:** APP-RECHECK-WAVE-P12 (19/20 DUAL-CLEAN)
**Status:** CLOSED — 19/20 DUAL-CLEAN
**Authority:** evidence-only fleet recheck; no compiler or app source authority

Wave P13 refreshes the P12 active fleet after `LANG-MATCH-ARM-PARAM-UNIFICATION-P2`,
`LANG-SUMTYPE-COLLECT-P3`, `LAB-BATCH-IMPORTER-FILTER-MAP-MIGRATION-P1`, and
`LAB-RUST-LOOP-BODY-ASSIGNMENT-P1`.

This is an evidence-only recheck. Lab results do not create canon authority,
the external ecosystem report remains evidence rather than authority, and no
old Ruby framework surface is used as language authority.

---

## Method

Fresh compiles were run for every active fleet app using all `.ig` files in
that app directory.

- Ruby: `IgniterLang::CompilerOrchestrator.compile_sources` from `igniter-lang`.
- Rust: release `igniter_compiler compile ... --out <mktmpdir>/out.igapp`.
- Each app/toolchain used a fresh `Dir.mktmpdir`; no shared output directory or
  shell redirection was used for compiler artifacts.
- Diagnostics were captured from live compiler JSON.

No app source, compiler source, runtime source, migration, or canon file was
edited for this wave.

## Fleet Reconciliation

P12 active fleet size was 20. P13 keeps the same active fleet for comparability.
The filesystem currently has 25 registry-bearing app directories; five are
appendix-checked below but remain outside the active fleet metric:
`bookkeeping`, `erp_logistics`, `query_engine`, `reconciler`, and `spreadsheet`.

## Active Fleet Status

| App | Source files | Ruby | Rust | Status | Entrypoint | Source hash | Notes |
|---|---:|---|---|---|---|---|---|
| advanced_logistics | 4 | ok/0 | ok/0 | DUAL-CLEAN | `none` | `sha256:4bb462de0378f9d3907d05f01d3a95e6e4b6d0b5247003a01aca6f4d214042f1` | unchanged clean app |
| air_combat | 8 | ok/0 | ok/0 | DUAL-CLEAN | `RunDuel` | `sha256:b3c2bdd046475442d1b78705fbcb9bfda55da09b070df93a3d36ff8f825b0c55` | unchanged clean companion app |
| arch_patterns | 5 | ok/0 | ok/0 | DUAL-CLEAN | `none` | `sha256:1996496fed1c6a7f11b6dc3d0e809a3dec8c404fd891f3cdc9b186e43b29cb89` | unchanged clean app |
| audit_ledger | 4 | ok/0 | ok/0 | DUAL-CLEAN | `BalanceAsOfDay5` | `sha256:6789a12ecae4d888c84519ac268c20fcd7e1b91ac277bc1c335e6ce3c1346022` | unchanged clean companion app |
| batch_importer | 3 | ok/0 | ok/0 | DUAL-CLEAN | `RunImport` | `sha256:1cf7a0f1e5d874c418954b699e5145a3e8c7dfada40bd1c3f94f78093d91d0fa` | BI-P01 resolved via filter_map migration |
| bloom_filter | 4 | ok/0 | ok/0 | DUAL-CLEAN | `none` | `sha256:1a7f62f1976a027d57f69b3ca4b12b5d5d3a3d81e3baefee67bc4c8cb80370f3` | unchanged clean app |
| call_router | 6 | ok/0 | ok/0 | DUAL-CLEAN | `RunConnectedMatched` | `sha256:1b8da43dd1fb66ae6b587056bfe459734e9eb854ccb2a1b308e996ac0334eed5` | unchanged clean companion app |
| dataframes | 4 | ok/0 | ok/0 | DUAL-CLEAN | `none` | `sha256:66ef942093603e04c200377c51e669ebd3c53cd8e6330aae3e87b51df1fc285a` | unchanged clean app |
| decision_tree | 4 | ok/0 | ok/0 | DUAL-CLEAN | `none` | `sha256:31119d34516505bf3bc802a5565ffb7e670e17d475c86ede29c5ca6c937dec72` | unchanged clean app |
| dsa | 6 | ok/0 | ok/0 | DUAL-CLEAN | `none` | `sha256:06afdd6e758f3c687af95051f54b69689709cdbc9c75642c66044a16b029e490` | unchanged clean app |
| igniter_parser | 4 | ok/0 | ok/0 | DUAL-CLEAN | `none` | `sha256:f7d388d96cc7248604cbacfc05ebaa1361174dbf56585e23568509e81edcf9cb` | unchanged clean app |
| job_runner | 4 | ok/0 | ok/0 | DUAL-CLEAN | `RunSuccessSecond` | `sha256:546c30b56c9b79d4b8bf1fbc396bb2252aec0b6ae58ac85bd7e7708932c3b91c` | loop-body assignment tightening caused no regression |
| lead_router | 4 | ok/0 | ok/0 | DUAL-CLEAN | `RunAccept` | `sha256:3cca9ed52a593e60ed86fb59e359809d255425af5690ded364cd8329fab71e1b` | unchanged clean companion app |
| neural_net | 5 | ok/0 | ok/0 | DUAL-CLEAN | `none` | `sha256:9a6506e3f42aec717fd3a857ccd1d5b759e158169f4589ffcff4849c4a3368c8` | unchanged clean app |
| **rule_engine** | 4 | oof/2 | oof/2 | **BLOCKED** | `none` | `sha256:0cf7f61465246aedb46242c9c6c36add39f9d71956950461a7831e9bdc22486b` | intentional fail-closed dynamic dispatch boundary |
| sim_framework | 7 | ok/0 | ok/0 | DUAL-CLEAN | `none` | `sha256:fc86b48e42382103212f21890438e59157df539dcd84aaf903bca48388591571` | unchanged clean app |
| trade_robot | 7 | ok/0 | ok/0 | DUAL-CLEAN | `none` | `sha256:3b279c19c641940d21ec76e455e3fa40a121d936fea3fbba4ffa9604cc32612a` | unchanged clean app |
| vector_editor | 4 | ok/0 | ok/0 | DUAL-CLEAN | `none` | `sha256:cafd7085a537f8efb8751ebe48148fbc9931ebb10041babb6f4b33f1b20fb2fc` | unchanged clean app |
| vector_math | 6 | ok/0 | ok/0 | DUAL-CLEAN | `none` | `sha256:332e41a1b646a31dfa97ff2b690e5eee678601f8678f00960ed2db7da8a01764` | unchanged clean app |
| web_router | 3 | ok/0 | ok/0 | DUAL-CLEAN | `RunArticle` | `sha256:15cc6c7d4ba22f29aa02878f58b8507ce4c7cbc53f3c39d1a228004f0b57c3ce` | unchanged clean companion app |

**Fleet total: 19/20 DUAL-CLEAN** (unchanged vs Wave P12).

## Delta vs Wave P12

| App group | Wave P12 | Wave P13 | Net |
|---|---|---|---|
| 18 clean apps excluding `batch_importer` | DUAL-CLEAN | DUAL-CLEAN | unchanged |
| `batch_importer` | DUAL-CLEAN with BI-P01 active | DUAL-CLEAN with BI-P01 RESOLVED | expected app-pressure resolution |
| `job_runner` | DUAL-CLEAN | DUAL-CLEAN | loop-body safety tightening caused no regression |
| `rule_engine` | BLOCKED oof/2 + oof/2 | BLOCKED oof/2 + oof/2 | unchanged fail-closed boundary |

No active fleet app regressed.

## rule_engine Golden

`rule_engine` remains the only non-clean active-fleet app, and this is still the
selected safe route from `LAB-DYNAMIC-CONTRACT-DISPATCH-P2`.

```text
Rust: oof / 2
  [OOF-P1] Unresolved field: Unknown.action (node: active_decisions)
  [OOF-TY1] Output type mismatch: expected RuleDecision, got Unknown (node: decision)

Ruby: oof / 2
  [OOF-P1] Unresolved symbol: d (node: active_decisions)
  [OOF-P1] Unresolved field: Unknown.action (node: active_decisions)
```

Root cause remains Tier 2 dynamic contract dispatch plus fail-closed Unknown
field/output boundaries. No source migration was selected.

## batch_importer Delta

`batch_importer` remains dual-clean and now reflects the landed
`LAB-BATCH-IMPORTER-FILTER-MAP-MIGRATION-P1` app migration:

- BI-P01 is RESOLVED.
- `CountAccepted` uses `filter_map` to produce `Collection[ImportRecord]`.
- Ruby/Rust source hash under the stable route:
  `sha256:1cf7a0f1e5d874c418954b699e5145a3e8c7dfada40bd1c3f94f78093d91d0fa`.

This is app-source evidence only; it does not migrate the app to built-in
`Result` and does not authorize parse/storage effects.

## Appendix: Registry-Bearing Non-Fleet Directories

These directories were checked to avoid stale-doc routing, but they are not part
of the P12/P13 active fleet metric.

| App | Source files | Ruby | Rust | Notes |
|---|---:|---|---|---|
| bookkeeping | 3 | oof/6 | oof/1 | outside active fleet; Decimal/sum/fold blockers remain |
| erp_logistics | 4 | oof/4 | ok/0 | outside active fleet; Ruby Float/operator blockers remain |
| query_engine | 4 | ok/0 | ok/0 | outside active fleet; appendix clean |
| reconciler | 5 | ok/0 | ok/0 | outside active fleet; appendix clean |
| spreadsheet | 3 | oof/2 | ok/0 | outside active fleet; Ruby call/function blocker remains |

## Closed Surfaces

- No app source edits in this wave.
- No compiler or runtime source edits in this wave.
- No migrations in this wave.
- No implementation.
- No IO/runtime work.
- No canon decisions.
- No source formatting churn.
