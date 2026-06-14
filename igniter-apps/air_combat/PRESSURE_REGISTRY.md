# Air Combat Pressure Registry

Updated: 2026-06-14 (LAB-AIR-COMBAT-BASELINE-P2 — CLOSED — DUAL-CLEAN, 115/115 PASS; `entrypoint RunDuel` rebaseline)

`air_combat` is a multiplayer, strategy-driven swarm simulation: each player owns a
swarm (fleet) of aircraft and authors a `Strategy` record; the swarm then operates
**autonomously** as a pure derivative of that strategy. It exercises target tracking
(alpha-beta / steady-state Kalman), pursuit/evasion guidance, and a per-tick
authoritative world step — all at the SIMULATION level (no IO, no clock, no RNG).

## Baseline

Dual-toolchain CLEAN.

```bash
cd igniter-compiler
cargo run -- compile \
  ../igniter-apps/air_combat/types.ig ../igniter-apps/air_combat/vec.ig \
  ../igniter-apps/air_combat/kalman.ig ../igniter-apps/air_combat/guidance.ig \
  ../igniter-apps/air_combat/strategy.ig ../igniter-apps/air_combat/swarm.ig \
  ../igniter-apps/air_combat/engine.ig ../igniter-apps/air_combat/example.ig \
  --out /tmp/air_combat.igapp
```

| Metric | Value |
|---|---|
| Ruby | ok / 0 diagnostics |
| Rust | ok / 0 diagnostics |
| source files | 8 |
| types | 9 |
| contracts | 31 |
| call_contract sites | 61 (all Tier-1 string literals — static dispatch) |
| fold sites | 6 (all SCALAR — record folds blocked, see AC-P01/02) |
| map / filter sites | 2 / 2 |
| source_hash | `sha256:b3c2bdd046475442d1b78705fbcb9bfda55da09b070df93a3d36ff8f825b0c55` (P2 rebaseline: `entrypoint RunDuel` present) |

> NOTE: the Rust CLI writes a directory-package `.igapp`. Always compile to a
> fresh `--out` path; piping stdout through `head`/truncating consumers can SIGPIPE
> the writer and surface a spurious "Internal compiler error: No such file or
> directory". Redirect to a file to see the real `ok` result.

## Pressures

| ID | Name | Evidence | Status | Route |
|---|---|---|---|---|
| AC-P01 | **fold-to-struct (Kalman track)** | `kalman.ig` `TrackFold3` manually unrolls `TrackStep` over 3 measurements — it WANTS `fold(measurements, track0, (t, m) -> TrackStep(t, m))` but the record accumulator `Track {est, vel, p}` fails (`OOF-COL4`). The headline pressure. | ACTIVE — primary | `LANG-FOLD-STRUCT-ACCUMULATOR-P2/P3` |
| AC-P02 | **fold-to-struct (swarm centroid)** | `swarm.ig` `SwarmCentroid` runs TWO scalar folds + `count` because `{sum_x, sum_y, count}` can't be folded in one pass. | ACTIVE | `LANG-FOLD-STRUCT-ACCUMULATOR-P2/P3` |
| AC-P03 | **manual unroll / fold-over-state** | `engine.ig` `RunBattle3` unrolls `WorldTick` ×3 (trade_robot RunBacktest pattern). Wants `fold(range(0,N), world0, (w,_) -> WorldTick(w))`. | ACTIVE | fold-struct + `LANG-COMPOSE-ENTITY` |
| AC-P04 | **factory contracts** | `MakePlane` / `MakeStrategy` exist only to construct typed records (inline/branch records infer to Unknown). | ACTIVE | `LANG-RUBY-RECORD-LITERAL-INFERENCE` / `LAB-NESTED-RECORD-LITERAL-TYPING` |
| AC-P05 | **state threading / entity** | `engine.ig` `WorldTick` re-threads `Player`/`Swarm` records field-by-field; `Player` is the config(strategy)+state(swarm,score)+behavior(doctrines) triad a future `entity` would bind. | ACTIVE — design | `LANG-COMPOSE-ENTITY-P1 → PROP` |
| AC-P06 | **dynamic strategy dispatch avoided** | `strategy.ig` `DoctrineDispatcher` hardcodes `CombinedDoctrine`; we want `call_contract(swarm.doctrine, ...)` but a variable callee returns Unknown. Static-dispatch discipline preserved. | INTENTIONAL fail-closed | `LAB-DYNAMIC-CONTRACT-DISPATCH-P2` (policy; not an unblock) |
| AC-P07 | **missing math: sqrt / normalize** | `vec.ig` keeps distances SQUARED (`VMag2`/`VDist2`) and guidance uses gain-scaled steering instead of true unit vectors because there is no `sqrt`. True proportional navigation needs a normalized line-of-sight rate. | ACTIVE — stdlib gap | new `LANG-STDLIB-MATH` (sqrt/hypot) proposal |
| AC-P08 | **IO surface needed for a real game** | Pure sim only: no clock, no RNG, no input, no rendering, no networking, no persistence. See "What We Need From IO" in `report.md`. | DOCUMENTED — behind | `PROP-035` effect surface / `PROP-023` stream input / IO-runtime track |

## Entrypoint / DX Refactor (2026-06-14)

`entrypoint RunDuel` added to `example.ig` — the first time the fleet uses the
implemented `entrypoint` selector (parser→TC→SemanticIR→manifest, dual-clean). It
names the program's start contract in source instead of relying on tool heuristics.

| ID | Name | Evidence | Status | Route |
|---|---|---|---|---|
| AC-P10 | **named run-profiles wanted** | only ONE bare `entrypoint` is allowed; `RunDuel` and `TrackBogey` each want to be a named PROP-029 run-profile (panel preset with `args`/`output`/`default`). | ACTIVE — DX | `PROP-029` rich entrypoint (revive profiles) |

> P2 REBASELINE CLOSED: live Ruby/Rust compilers now agree on
> `sha256:b3c2bdd046475442d1b78705fbcb9bfda55da09b070df93a3d36ff8f825b0c55`.
> The dispatch-card claim `sha256:8b698e66d8635f83306d209c702f7231c8184b1e6ffddb8a63f3a147ed9600f8`
> is superseded by the live artifact evidence. No `.ig` app source migration was
> made for P2.

## ServiceLoop / Progression Direction

`air_combat` should not route future game-loop work through an ad hoc host loop.
The language already has the right conceptual direction: **ServiceLoop** as an
alive-by-liveness loop class, with source binding mapped through **PROP-037
Progression** descriptors.

Canonical anchors:

- [`docs/spec/ch13-managed-recursion.md`](/Users/alex/dev/projects/igniter-workspace/igniter-lang/docs/spec/ch13-managed-recursion.md): `ServiceLoop` is the service-liveness loop class; §13.5 names `clock.every(N.duration)` and explicit `tick.time` event-time binding.
- [`docs/language-covenant.md`](/Users/alex/dev/projects/igniter-workspace/igniter-lang/docs/language-covenant.md): Postulate 14 says service-loop liveness maps through PROP-037 progression descriptors.
- PROP-023 stream input remains the right direction for player strategy edits / commands over time.

Current status remains closed: no scheduler, no clock capability, no socket loop,
no parser/runtime authorization for a real ServiceLoop. The point of AC-P09 is to
keep future agents on the canonical ServiceLoop/Progression route instead of
inventing a side-channel loop.

## Safety Interpretation

This app proves the current language can compile a non-trivial, multi-agent,
strategy-parametrised real-time-style simulation with **pure** kinematics, target
tracking, and autonomous swarm behaviour. It does NOT claim:

- proven real-time behaviour (no clock, no scheduler),
- multiplayer networking (no IO),
- stochastic realism (measurement noise is hand-authored, not sampled),
- numerically exact guidance (no sqrt; squared-distance + gain-steer approximation).

## Non-Goals

- No `now()` / clock / tick source.
- No RNG / sampled noise.
- No network / socket / Rack / HTTP authoritative loop.
- No rendering / telemetry / broadcast IO.
- No persistence / replay store.
- No dynamic doctrine dispatch (static only).
- No fold-to-struct or entity implementation (this app is pressure, not a fix).

## Recommended Route

1. `LANG-FOLD-STRUCT-ACCUMULATOR-P3/P4` — the single highest-leverage unlock here
   (collapses AC-P01, AC-P02, and half of AC-P03).
2. `LANG-COMPOSE-ENTITY` PROP — collapses AC-P05 and the rest of AC-P03.
3. A new `LANG-STDLIB-MATH` (sqrt/hypot) readiness card for AC-P07.
4. IO-runtime / effect-surface work (AC-P08) only after the pure-sim pressure is
   harvested; the report names exactly what each game subsystem needs.
5. ServiceLoop / Progression work (AC-P09) only through PROP-037 + PROP-023, not
   through an ad hoc host loop.

## Wave P10 Recheck Summary (2026-06-14)

Rust: ok / 0 diagnostics — baseline frozen. Ruby: ok / 0 diagnostics — baseline frozen. DUAL-TOOLCHAIN CLEAN. air_combat is officially integrated into the fleet and proof verified by verify_lab_air_combat_baseline_p1.rb (99/99 PASS). No new pressures. No regressions.

## Entrypoint Rebaseline P2 Summary (2026-06-14)

Rust: ok / 0 diagnostics. Ruby: ok / 0 diagnostics. Manifest and SemanticIR both
carry `entrypoint RunDuel` as the default program selector. The stable dual-
toolchain `source_hash` is
`sha256:b3c2bdd046475442d1b78705fbcb9bfda55da09b070df93a3d36ff8f825b0c55`.
AC-P01..AC-P10 are preserved and routed. `AC-P10` remains pressure for PROP-029
rich named run profiles; it is not host-loop configuration. No `.ig` app source
was changed for this rebaseline.
