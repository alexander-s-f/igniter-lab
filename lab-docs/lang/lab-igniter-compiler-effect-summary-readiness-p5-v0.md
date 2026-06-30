# LAB-IGNITER-COMPILER-EFFECT-SUMMARY-READINESS-P5

Date: 2026-06-27
Status: DONE
Lane: igniter-lab / compiler / purity and effect summary readiness
Skill: idd-agent-protocol

## Authority Boundary

This is a readiness packet. It clarifies current compiler and host-runner
enforcement and recommends the next implementation card. It does not change
syntax, `Decision` semantics, VM/runtime authority, host config, public bind
policy, or canon language authority.

Current source wins over older audit wording. The important current distinction
is:

- `.ig` contracts remain pure/local in the sense that they construct values and
  host intents;
- host IO is executed only by host runner / machine capability boundaries;
- `Decision::ReadThen` and `Decision::InvokeEffect` are typed values that name
  host seams, not in-language IO handles.

## Current Enforcement

### Compiler classifier

`lang/igniter-compiler/src/classifier.rs` enforces local contract-body IO rules:

- gathers per-contract `capability` declarations;
- validates every `effect ... using <capability>` references a declared
  capability;
- requires each declared capability to have a matching effect declaration;
- walks contract body expressions with `check_expr_io`;
- blocks `stdlib.IO.*` calls inside `pure` contracts with
  `E-IO-AMBIENT-BLOCKED`;
- blocks ambient `stdlib.IO.*` calls without a capability context;
- checks read/write capability mode by name (`read` vs `write`);
- rejects escape declarations in `pure` contracts (`OOF-M1`);
- rejects writes in `observed` contracts and compensation in `irreversible`
  contracts.

This is intra-contract and expression-local. It does not currently compute a
transitive summary through app-local `def` functions or through
`call_contract("Name", ...)` callees.

### Compiler typechecker

`lang/igniter-compiler/src/typechecker.rs` already has useful graph machinery:

- `build_contract_registry` records literal-call callees by contract name with
  modifier, input count/types, and single output type/name;
- app-local `def` calls are resolved by name and return type;
- an SCC/Tarjan function call graph is already built for recursive-function
  checks (`OOF-L4`);
- `now()` is explicitly forbidden in user functions;
- `Decision::InvokeEffect.input` and `RespondJson.body` are open
  `Unknown` payload positions by design.

What is missing is a transitive effect summary. The typechecker resolves
`def` return types but does not mark whether a `def` body performs or forwards
ambient IO. The contract registry has callee shape, but not callee effect class.

### Emitter and SIR

`lang/igniter-compiler/src/emitter.rs` emits current metadata:

- `modifier`;
- `fragment_class`;
- `capabilities`;
- `effects`;
- escape boundaries.

It does not emit a `effect_summary` / `decision_summary` field today.

### Machine declared-effect surface

`runtime/igniter-machine` already treats declared effect contracts separately
from IgWeb decisions:

- `service_loop::discover_effect_surface` reads modifier/capability/effect
  metadata from emitted IR;
- `run_service` preflight refuses pure contracts for declared host effects;
- `capability_io_host_tests.rs` proves pure contracts have no declared effect
  surface and are refused by the host entrypoint.

That host-side guard is current and useful, but it does not answer IgWeb
decision-production questions at compile time.

## Decision Boundary Classification

| Decision arm | Current class | Runtime boundary |
|---|---|---|
| `Respond` | response-producing | Pure value to HTTP JSON response. |
| `RespondError` | response-producing / app-owned error | Pure typed app error envelope; host-owned errors remain separate. |
| `RespondJson` | response-producing / structured JSON | Pure typed payload becomes response body root. |
| `RespondView` | response-producing / JSON view descriptor | Pure typed descriptor becomes JSON response. |
| `Render` | render-producing | App gives artifact JSON string; `igniter-web` render host validates/escapes/fails closed. |
| `RenderView` | render-producing | App gives typed `ViewArtifact`; `igniter-web` serializes and renders it. |
| `ReadThen` | read-staged host intent | Host executes read through `StagedReadHost`, reconciles typed rows, and redispatches continuation; bounded by `MAX_READ_HOPS = 8`. |
| `InvokeEffect` | effect-producing host intent | Sync mode observes it; async machine mode routes it through `MachineEffectHost` only if host write/effect bindings exist. |

`ReadThen` and `InvokeEffect` do not violate language purity by themselves. They
are deterministic host-intent values. The host owns whether an intent is denied,
observed, or executed.

## Homes Compared

| Home | Fit | Tradeoff |
|---|---|---|
| Compiler/typechecker summary | Best fit for static evidence. It sees the AST, app-local functions, literal `call_contract` registry, sealed `Decision` constructors, and existing SCC graph. | Requires a small new summary model and tests, but avoids host-only guesswork. |
| IgWeb lowering guard | Useful for route-shell contracts because `.igweb` lowers to static `call_contract` leaves. | Too narrow: hand-authored `.ig` apps, helper `def`s, and non-IgWeb contracts would still have no summary. |
| VM/runtime | Good defense-in-depth because the host already denies unbound effects and declared-effect misuse. | Too late for compile diagnostics; runtime cannot explain source-level transitive leakage clearly. |
| Host runner metadata / boot checks | Useful for deployment checks such as typed `ReadThen` continuation validation. | Host sees compiled contracts and config, not full source intent; this should consume compiler metadata, not invent summary rules. |
| Docs only / defer | Acceptable only if no live ambiguity remains. | Not sufficient: the audit gap is real for transitive `def`/callee classification, and current docs still need a concrete route. |

## Recommendation

Implement a compiler summary next. The smallest useful surface is not a broad
effect system and must not reject current IgWeb `pure contract -> Decision`
patterns. It should compute and expose a transitive summary with these flags:

| Flag | Meaning |
|---|---|
| `ambient_io` | A body or app-local `def` transitively calls `stdlib.IO.*`. |
| `declared_effect_surface` | A contract declares capability/effect metadata for host service execution. |
| `decision_response` | The contract may produce response/render-only `Decision` arms. |
| `decision_read_staged` | The contract may produce `Decision::ReadThen`. |
| `decision_effect_intent` | The contract may produce `Decision::InvokeEffect`. |
| `unknown_dynamic` | The compiler cannot classify a dynamic callee or non-literal decision arm precisely. |

Enforcement for the first implementation card:

- reject `pure` contracts whose transitive function summary has `ambient_io`;
- do not reject `decision_effect_intent` or `decision_read_staged` from `pure`
  contracts, because those are host intents, not ambient IO;
- emit summary metadata into SIR so host/lowering docs can stop guessing;
- keep runtime/host fail-closed behavior unchanged.

## Concrete Next Card

`LAB-IGNITER-COMPILER-EFFECT-SUMMARY-P6`

Acceptance for that implementation card:

- build a per-`def` summary using the existing function call graph and SCC
  machinery;
- build a per-contract summary using local body scan plus static
  `call_contract("Name", ...)` callee summaries where the callee is known;
- classify sealed `Decision` constructors into response/read/effect intent
  flags;
- reject a `pure contract` that reaches `stdlib.IO.*` through an app-local `def`;
- preserve current IgWeb route patterns where pure handlers return
  `RespondJson`, `RenderView`, `ReadThen`, or `InvokeEffect`;
- emit `effect_summary` or `decision_summary` metadata in SIR;
- add focused tests for direct IO, IO-via-def, pure `InvokeEffect` intent,
  `ReadThen` continuation, and static `call_contract` summary propagation;
- do not move host authority into `.ig` and do not change `Decision` runtime
  semantics.

## Existing Tests That Guard Adjacent Behavior

- `lang/igniter-compiler/tests/effect_name_parity_tests.rs` keeps capability
  binding validation intact while ensuring effect labels are host verbs, not
  authority selectors.
- `lang/igniter-compiler/tests/igweb_lowering_tests.rs` proves generated IgWeb
  route shells are `pure contract Serve` with static `call_contract("...")`
  leaves and no dynamic dispatch.
- `server/igniter-web/tests/igweb_serve_machine_mode_tests.rs` proves
  `ReadThen` runner behavior through the machine-mode path.
- `server/igniter-web/tests/async_machine_runner_tests.rs` proves final
  `InvokeEffect` can be routed through `MachineEffectHost`.
- `runtime/igniter-machine/tests/capability_io_host_tests.rs` proves declared
  host-effect execution refuses pure contracts at the machine service-loop
  boundary.

## Verification

Commands:

```text
cargo test --manifest-path lang/igniter-compiler/Cargo.toml --test igweb_lowering_tests
cargo test --manifest-path server/igniter-web/Cargo.toml --features machine --test igweb_serve_machine_mode_tests
git diff --check
```

Results: see card closing report.

Verified results:

```text
cargo test --manifest-path lang/igniter-compiler/Cargo.toml --test igweb_lowering_tests
  11 passed; 0 failed

cargo test --manifest-path server/igniter-web/Cargo.toml --features machine --test igweb_serve_machine_mode_tests
  12 passed; 0 failed

git diff --check
  PASS
```
