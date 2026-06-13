# APP-RECHECK-WAVE-P9

**Date:** 2026-06-13
**Trigger:** LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P4 CLOSED + LAB-VE-NEW-OBJ-INFERENCE-P1 CLOSED + LAB-VECTOR-MATH-FIELD-ALIGNMENT-P1 CLOSED (gate satisfied) + LAB-HOF-LAMBDA-ERROR-PROPAGATION-P2 CLOSED + LAB-PARSER-RECORD-IN-HOF-P1 CLOSED
**Scope:** All 12 apps — evidence + registry updates only; no compiler or app source changes in this wave
**Prior wave:** APP-RECHECK-WAVE-P8 (8/12 DUAL-CLEAN)

---

## Fleet Status (Wave P9)

| App | Rust | Ruby | Status | Notes |
|---|---|---|---|---|
| advanced_logistics | ok/0 | ok/0 | DUAL-CLEAN | Unchanged since Wave P3 |
| arch_patterns | ok/0 | ok/0 | DUAL-CLEAN | Unchanged since Wave P7 |
| bloom_filter | ok/0 | ok/0 | DUAL-CLEAN | Unchanged since Wave P8 |
| dataframes | ok/0 | ok/0 | DUAL-CLEAN | Unchanged since Wave P6 |
| decision_tree | ok/0 | ok/0 | DUAL-CLEAN | Unchanged since Wave P8 |
| dsa | ok/0 | ok/0 | DUAL-CLEAN | Unchanged since Wave P6 |
| neural_net | ok/0 | ok/0 | DUAL-CLEAN | Unchanged since Wave P6 |
| sim_framework | ok/0 | ok/0 | DUAL-CLEAN | Unchanged since Wave P8 |
| **igniter_parser** | **ok/0** | **ok/0** | **DUAL-CLEAN** | **NEW** — IP-P06 RESOLVED (LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P4) |
| **vector_editor** | **ok/0** | **ok/0** | **DUAL-CLEAN** | **NEW** — VE-P09 RESOLVED (LAB-VE-NEW-OBJ-INFERENCE-P1) |
| **vector_math** | **ok/0** | **ok/0** | **DUAL-CLEAN** | **NEW** — VM-P10 RESOLVED (LAB-VECTOR-MATH-FIELD-ALIGNMENT-P1) |
| rule_engine | oof/2 | oof/2 | BLOCKED | RE-P04+RE-P07; diagnostics unchanged from Wave P8 |

**Fleet total: 11/12 DUAL-CLEAN** (+3 vs Wave P8)

---

## Delta vs Wave P8

| App | Wave P8 Rust | Wave P8 Ruby | Wave P9 Rust | Wave P9 Ruby | Net |
|---|---|---|---|---|---|
| advanced_logistics | ok/0 | ok/0 | ok/0 | ok/0 | — |
| arch_patterns | ok/0 | ok/0 | ok/0 | ok/0 | — |
| bloom_filter | ok/0 | ok/0 | ok/0 | ok/0 | — |
| dataframes | ok/0 | ok/0 | ok/0 | ok/0 | — |
| decision_tree | ok/0 | ok/0 | ok/0 | ok/0 | — |
| dsa | ok/0 | ok/0 | ok/0 | ok/0 | — |
| neural_net | ok/0 | ok/0 | ok/0 | ok/0 | — |
| sim_framework | ok/0 | ok/0 | ok/0 | ok/0 | — |
| igniter_parser | oof/5 | oof/7 | **ok/0** | **ok/0** | **−5 Rust −7 Ruby → DUAL-CLEAN** |
| vector_editor | ok/0 | oof/1 | ok/0 | **ok/0** | **−1 Ruby → DUAL-CLEAN** |
| vector_math | ok/0 | oof/36 | ok/0 | **ok/0** | **−36 Ruby → DUAL-CLEAN** |
| rule_engine | oof/2 | oof/2 | oof/2 | oof/2 | — (diagnostic form unchanged since P8) |

**Wave P9 net change:** 3 apps newly DUAL-CLEAN (+3). All other apps unchanged.

---

## What Made igniter_parser DUAL-CLEAN

**LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P4** (51/51 PASS) resolved IP-P06 — the last active pressure after IP-P01 was cleared in Wave P8.

5 `call_contract("empty"/"append")` stringly-typed stdlib constructor sites were migrated to canonical forms:
- `api.ig`: `initial_tokens` and `initial_nodes` → `Collection[Token] = []` / `Collection[AstNode] = []`
- `parser.ig`: `empty_children` → `Collection[String] = []`; `new_nodes` → `append(state.nodes, module_node)`
- `lexer.ig`: `next_tokens` → `append(state.tokens, new_token)`

Tier-1 `call_contract("LexNextToken")` and `call_contract("ParseModuleDecl")` preserved (user contracts, not stdlib).

Wave P8 had exposed IP-P06 after IP-P01 was cleared by prior stdlib surface work (stdlib.string, char_at, substring). P4 closes the igniter_parser track entirely.

---

## What Made vector_editor DUAL-CLEAN

**LAB-VE-NEW-OBJ-INFERENCE-P1** (38/38 PASS) resolved VE-P09 — the sole Ruby residual after Rust was already clean.

Root cause (Classification 1 — app-source shape issue): `GraphicObject` has 7 fields in `@type_shapes`; the parser strips `?` from optional annotations so all appear required. Original `new_obj` had 5 fields. P3 structural matching requires exact field set equality → no candidates → Unknown → OOF-P1 "Unresolved symbol: new_obj".

Fix (tools.ig only): added `compute default_text = { content: "", font_size: 0 }`, annotated `compute new_obj : GraphicObject = { ... }`, extended with `path_pts: []` and `text_data: default_text`.

Design observation flagged for future work: `?` suffix on type annotations has no semantic effect on partial record initialization → `LANG-OPTIONAL-FIELD-PARTIAL-RECORD-P1`.

---

## What Made vector_math DUAL-CLEAN

**LAB-VECTOR-MATH-FIELD-ALIGNMENT-P1** (49/49 PASS) resolved VM-P10 — 36 Ruby diagnostics all from `x/y/z` vs `r0/r1/r2` field name mismatch in 6 `mat3.ig` contracts.

Root cause: `infer_record_literal` propagated outer node_name ("result") into inner field-value inference — inner Vec3 row literals validated against Mat3 (wrong shape). Fix: 6 mat3.ig contracts (Mat3Identity, Mat3Transpose, Mat3Add, Mat3Scale, MakeRotation2D, MakeScale3D) extract inner Vec3 rows as `compute r0/r1/r2 : Vec3 = {...}` annotated computes, breaking the name propagation chain.

Ruby: 36→0 diagnostics. Rust: ok/0 preserved throughout.

*(Note: LAB-VECTOR-MATH-FIELD-ALIGNMENT-P1 added its own Wave P9 Recheck section to the vector_math PRESSURE_REGISTRY directly. That section is authoritative.)*

---

## rule_engine (Unchanged)

No change from Wave P8. Diagnostic form is unchanged since the Wave P8 HOF-P2 change.

**Wave P9 diagnostics:**

```
Rust: oof / 2
  [OOF-P1] Unresolved field: Unknown.action (node: active_decisions)
  [OOF-TY1] Output type mismatch: expected RuleDecision, got Unknown (node: decision)

Ruby: oof / 2
  [OOF-P1] Unresolved symbol: d (node: active_decisions)
  [OOF-P1] Unresolved field: Unknown.action (node: active_decisions)
```

Root cause: Tier 2 dynamic dispatch (`call_contract(r, t)` where `r` is a variable callee). LAB-HOF-LAMBDA-ERROR-PROPAGATION-P2 made Rust propagate HOF lambda body OOF-P1 (matching Ruby behavior); OOF-P1 now appears in Rust for `Unknown.action` instead of only at the OOF-TY1 boundary. RE-P01 baseline source hash unchanged. Route: `LAB-DYNAMIC-CONTRACT-DISPATCH-P1`.

---

## Closed Surfaces

- No app source changes in this wave recheck (source changes were made by the gate cards before this wave ran).
- No compiler source changes.
- No new OOF codes.
- No new canon decisions.

---

## Open Routes After Wave P9

| Priority | Card | Scope |
|---|---|---|
| 1 | `LAB-DYNAMIC-CONTRACT-DISPATCH-P2` | Validation receipt and fail-closed semantics for variable callees |
| 2 | `LAB-HOF-LAMBDA-ERROR-PROPAGATION-P1` | Rust HOF temp_errors vs Ruby propagation divergence (superseded in filter/map by P2; other HOFs remain) |
| 3 | `LAB-OUTPUT-TYPE-PARAMETER-CHECK-P2` | Parametric container assignability planning |
| 4 | `LAB-PARSER-RECORD-IN-HOF-P2` | Lookahead disambiguation in parse_lambda (both parsers, ~5 lines each) |
| 5 | `LAB-RUST-HOF-RECORD-INFERENCE-P1` | Rust TC: record literal type inference inside HOF lambda without output type context |
| 6 | `LANG-OPTIONAL-FIELD-PARTIAL-RECORD-P1` | `?` suffix on type annotations has no semantic effect on partial record initialization |

Only `rule_engine` remains blocked. All other 11 apps are DUAL-CLEAN.
