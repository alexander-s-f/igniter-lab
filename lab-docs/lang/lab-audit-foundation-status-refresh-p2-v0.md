# LAB-AUDIT-FOUNDATION-STATUS-REFRESH-P2

Date: 2026-06-27
Status: DONE
Lane: igniter-lab / foundation-audit / status refresh
Skill: idd-agent-protocol

## Authority Boundary

This is a verify-first assimilation packet. It updates lab navigation/status
docs after recent hardening work. It does not create canon language authority,
does not change public emergence/home-lab/SparkCRM docs, and does not change
code.

Current truth comes from live source, current cards/proof packets, and
package-local `IMPLEMENTED_SURFACE.md` files. The 2026-06-26 audit packets are
historical snapshots; their `Status: OPEN` lines are not enough to route new
work.

## Audit Packets Checked

Checked and annotated with a 2026-06-27 refresh note:

| Packet | Current handling |
|---|---|
| `lab-docs/igniter-compiler-core-foundation-audit-p1.md` | Historical snapshot; parser depth, float literal safety, and lock-on-build findings have later closures. |
| `lab-docs/igniter-vm-core-foundation-audit-p1.md` | Historical snapshot; checked arithmetic, eval depth, collection budget, step budget, map-lambda `call_contract`, and `variant_construct` fleet blocker have later closures. |
| `lab-docs/igniter-stdlib-core-foundation-audit-p1.md` | Historical snapshot; Decimal money safety and IO sandbox write hardening have later closures. |
| `lab-docs/igniter-machine-core-foundation-audit-p1.md` | Historical snapshot; signed passport data-plane, MCP local auth/checkpoint sandbox, and inbound read hardening have later closures. |
| `lab-docs/igniter-web-core-foundation-audit-p1.md` | Historical snapshot; render-html `safe_url` C0 rejection, IgWeb signed effect passport, and bind preauthorization have later closures. |
| `lab-docs/igniter-server-core-foundation-audit-p1.md` | Historical snapshot; inbound read hardening and live-bind gate API have later closures. |
| `lab-docs/igniter-frame-ui-foundation-audit-p1.md` | Historical snapshot; empty `leads` panic has later closure. |

The home-lab TBackend audit was not rewritten by this card because the scope
forbids home-lab edits.

## Closure Matrix

| Audit blocker / stale route | Current verified status |
|---|---|
| Compiler parser recursion and float literal panic | CLOSED by `LAB-IGNITER-COMPILER-INPUT-ROBUSTNESS-P1`: parser depth is budgeted and float literals use finite diagnostic handling. |
| Compiler lockfile computed but not enforced on build | PARTLY CLOSED by `LAB-IGNITER-COMPILER-LOCK-ON-BUILD-P2`: `compile --project-root ... --locked` / `--frozen` fails missing, stale, or integrity-bad locks before emit. Remaining: default policy and dependency-path containment. |
| VM int overflow, `eval_ast` stack depth, huge collection/range allocation, non-progress loop | CLOSED by checked arithmetic work and `LAB-IGNITER-VM-EVAL-DEPTH-AND-COLLECTION-BUDGET-P2`: checked integer ops, `MAX_EVAL_AST_DEPTH`, `MAX_COLLECTION_ELEMENTS`, and `MAX_VM_STEPS` are in source. |
| Decimal money wrap/truncate/scale comparison | CLOSED by `LAB-STDLIB-DECIMAL-MONEY-CONTRACT-READINESS-P1` and `LAB-STDLIB-DECIMAL-MONEY-SAFE-P2`: checked i128 arithmetic, exact-only division, bounded scale, and scale-normalized comparison are implemented. |
| stdlib IO write symlink escape | CLOSED by `lab-stdlib-io-sandbox-hardening-p1`: sandbox root and write parents are canonicalized; symlink write targets are refused. |
| render-html `safe_url` control-character bypass | CLOSED by `lab-igniter-web-render-html-output-safety-p1`: C0/control scheme bypasses and protocol-relative URLs are refused. |
| frame-ui empty `leads` panic | CLOSED by `LAB-FRAME-UI-EMPTY-LEADS-PANIC-P1`: empty leads return schema error instead of panic. |
| Machine forgeable passport on data-plane | CLOSED for explicit signed entrypoints by `LAB-MACHINE-SIGNED-PASSPORT-DATAPLANE-P26`: signed write, atomic write, service, and coordination entrypoints refuse forged/unsigned passports. Legacy unsigned entrypoints remain compatibility surfaces. |
| IgWeb forgeable effect passport | CLOSED by `LAB-IGNITER-WEB-SIGNED-EFFECT-PASSPORT-P27`: effect passport minting/verifying is signed in the IgWeb effect host path. v0 keying is process-local. |
| Server/machine unbounded inbound reads and auth composition | CLOSED by `lab-igniter-server-inbound-hardened-read-p28`: shared policy defaults cap headers/body, time out incomplete reads, and apply middleware ordering before dispatch. |
| Loopback-to-live bind gate missing | CLOSED for server API by `LAB-IGNITER-SERVER-LIVE-BIND-GATE-P31`; IgWeb source now calls `authorize_bind` before sync and machine listener binds (`P32`). Public bind remains closed. |
| MCP unauthenticated local tools and arbitrary checkpoint write | CLOSED by `lab-machine-mcp-auth-checkpoint-sandbox-p30`: local env token is required for `tools/call`, checkpoint paths are root-confined, and reserved stores are refused. This is not P26 signed passport auth. |
| VM map lambda `call_contract` / `variant_construct` parity | CLOSED for covered specimens by `lab-vm-map-lambda-callcontract-parity-p1-v0.md` and `LAB-VM-EVALAST-VARIANT-CONSTRUCT-IMPL-P5`. |
| Machine fleet stale HOLD 11/13 | CLOSED by live 2026-06-27 fleet recheck: 13/13 OK. |

## Current Verified Next Cards

- `LAB-IGNITER-WEB-HOST-CONFIG-TYPED-FIELD-KINDS` for operator-configurable Bool/Decimal read kinds.
- `LAB-IGNITER-COMPILER-TYPE-IR-ENUM-P*` for stringly type-IR soundness.
- `LAB-IGNITER-COMPILER-EFFECT-SUMMARY-P*` for interprocedural purity/effect summary.
- `LAB-IGNITER-COMPILER-DEP-PATH-CONTAINMENT-P*` and/or compile-lock default policy for resolver containment and build-lock policy.
- `LAB-IGNITER-SERVER-LIVE-BIND-TLS-CHECKLIST-P*` before any public bind.
- `LAB-MACHINE-DURABLE-CAS-SEQID-FSYNC-P*` for multi-process/durable exactly-once and replay ordering.
- `LAB-IGNITER-VM-SOURCE-RUN-REPL-P*` for direct source execution / REPL DX.
- `LAB-FRAME-UI-IDE-PREVIEW-REHOME-P2` / layout vocab / render-host work for product unpause.

## Files Updated

- `lab-docs/igniter-foundation-hardening-roadmap-p1.md`
- `lab-docs/lang/current-waves-index.md`
- `lang/igniter-vm/IMPLEMENTED_SURFACE.md`
- `runtime/igniter-machine/IMPLEMENTED_SURFACE.md`
- the seven lab audit packets listed above, with a short refresh note
- `.agents/work/cards/lang/LAB-AUDIT-FOUNDATION-STATUS-REFRESH-P2.md`

## Verification

Machine fleet command:

```text
cargo test --manifest-path runtime/igniter-machine/Cargo.toml --test machine_tests test_machine_fleet_sweep -- --nocapture
```

Result:

```text
machine-fleet sweep: 13/13 ok
test test_machine_fleet_sweep ... ok
test result: ok. 1 passed; 0 failed
```

Final whitespace check:

```text
git diff --check
```

Result: PASS.

## Not Changed

- No code changed for this card.
- No public emergence, home-lab, SparkCRM, or canon `igniter-lang` documents were edited.
- No public listener, TLS, production deploy, registry, semver solver, signing PKI, or canon language promise is inferred.
