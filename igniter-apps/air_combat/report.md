# Air Combat — Pressure Report

## The Game

`air_combat` is a **multiplayer, strategy-driven swarm simulation**. Two players
each command a **swarm** (fleet) of aircraft. A player does not fly planes directly;
instead they author a **`Strategy`** — a small record of doctrine parameters
(aggression, intercept gain, lead time, evade threshold, formation spread). From
then on the swarm acts **autonomously**, as a *pure derivative of the strategy*:

```
player authors Strategy  ──►  Swarm (Collection[Plane])  ──►  per-tick autonomous behaviour
        (the "program")              (the "fleet")              (the strategy, executed)
```

Interceptors hunt; evaders flee. Each side tracks the enemy with a steady-state
Kalman (alpha-beta) filter, steers with a pursuit/evasion law, and the engine
resolves engagements and scores each authoritative tick. Everything is **pure**:
fixed-point Integer math (scale 100), no clock, no randomness, no IO.

This is deliberately a **simulation-level** experiment. It is exactly the layer the
language can express today — and it makes the gaps that block a *real* game
extremely concrete.

## Why This App Exists

To grow the lab fleet and put **directed pressure** on the two highest-leverage
language tracks already in flight, plus to articulate the IO surface we still lack:

1. **fold-to-struct** — target tracking and swarm aggregates are textbook record
   accumulators. They are the cleanest motivation yet for
   `LANG-FOLD-STRUCT-ACCUMULATOR`.
2. **entity / compose** — a `Player` is a config+state+behaviour triad threaded by
   hand. It is the cleanest motivation yet for `LANG-COMPOSE-ENTITY`.
3. **IO** — a simulation is not a game. The report names what each subsystem needs.
4. **ServiceLoop readiness** — the pure `WorldTick` core is already shaped like a future PROP-037 progression step handler.

## Pressure 1 — fold-to-struct (the headline)

A Kalman/alpha-beta filter refines an estimate over a *sequence* of measurements.
That is, definitionally, a fold whose accumulator is a record:

```igniter
-- WHAT WE WANT
compute estimate = fold(measurements, track0, (track, m) -> TrackStep(track, m))
output estimate : Track          -- Track { est : Vec2, vel : Vec2, p : Integer }

-- WHAT WE MUST WRITE TODAY  (kalman.ig : TrackFold3)
compute t1 = call_contract("TrackStep", t0, m1)
compute t2 = call_contract("TrackStep", t1, m2)
compute t3 = call_contract("TrackStep", t2, m3)
output t3 : Track
```

Folding into a record fails today with `OOF-COL4` (lambda return ≠ accumulator).
The same wall appears in `SwarmCentroid`, which must run **two** scalar folds plus a
`count` instead of one fold into `{sum_x, sum_y, count}`. This app turns that
abstract limitation into a felt one: tracking depth and swarm size are both capped
at "however many steps we were willing to unroll."

## Pressure 2 — entity / compose

`WorldTick` (engine.ig) is mostly *plumbing*. To advance the world one step it
re-threads every `Player` and `Swarm` field by hand:

```igniter
compute swarm_a2 = { team: ..., doctrine: ..., strategy: strat_a, planes: engaged_a }
compute player_a2 = { id: ..., name: ..., swarm: swarm_a2, score: ... + kills_by_a }
-- ...and the same again for player B, every tick.
```

A `Player` is precisely the **config (Strategy) + state (Swarm, score) + behaviour
(doctrine contracts)** triad that a future `entity` would bind, auto-threading state
instead of demanding manual reconstruction. `RunBattle3`'s hand-unroll of `WorldTick`
is the same pain in the time dimension (fold-over-state).

## Pressure 3 — static dispatch held the line

We *wanted* `call_contract(swarm.doctrine, plane, ...)` so a player could name their
doctrine in data. A variable callee returns `Unknown`, so `DoctrineDispatcher`
hardcodes `CombinedDoctrine` — the trade_robot `StrategyDispatcher` pattern. This is
the intentional `LAB-DYNAMIC-CONTRACT-DISPATCH-P2` fail-closed boundary, and the app
respects it: behaviour is selected by name, never by a runtime string.

## Pressure 4 — missing math (sqrt)

Real guidance (proportional navigation) needs a unit line-of-sight vector and a
true range — i.e. `sqrt`. We have none, so `vec.ig` keeps everything **squared**
(`VMag2`, `VDist2`) and the guidance law is a gain-scaled, axis-clamped steer rather
than a normalized one. Good enough for a sim, wrong for fidelity. This motivates a
small `LANG-STDLIB-MATH` surface (`sqrt`, `hypot`).

---

## What We Need From IO (to make this a real game)

A simulation that compiles is not yet a playable, multiplayer game. Each missing
piece is an IO/runtime capability, currently behind. Naming them is part of the
pressure:

| Game subsystem | What it needs from IO | Closest language/runtime track |
|---|---|---|
| **Frame / tick loop** | a real time source and scheduler to advance `WorldTick` at a fixed rate | **ServiceLoop / PROP-037 Progression** (`clock.every`, explicit `tick.time`) — concept exists; runtime scheduler/clock authority closed |
| **Player input** | an event stream of strategy edits / commands arriving over time | `PROP-023` stream input surface; feeds future ServiceLoop step materialization |
| **Stochastic realism** | an RNG capability to sample measurement & process noise (today noise is hand-authored constants) | effect-surface RNG capability (none yet) |
| **Multiplayer** | an authoritative server loop: accept connections, ingest each client's strategy, broadcast world state | `PROP-035` effect surface + IO-runtime (`LAB-IGNITER-LANG-IO-RUNTIME`, `MICROSERVICE`) — no Rack/socket today |
| **Rendering / telemetry** | an output capability to emit world snapshots to a renderer or client | effect-surface output capability |
| **Persistence / replay** | a storage capability to save match state and replay ticks deterministically | `PROP-046` storage capability / IO-runtime |

### ServiceLoop / Progression: the intended game-loop direction

The authoritative tick loop should not be an ad hoc host while-loop. Igniter
already names the right concept: **ServiceLoop** / **Progression**.

- [`docs/spec/ch13-managed-recursion.md`](/Users/alex/dev/projects/igniter-workspace/igniter-lang/docs/spec/ch13-managed-recursion.md) classifies `ServiceLoop` as the alive-by-liveness loop class. §13.5 gives the relevant timer binding shape: `loop TickLoop tick in clock.every(250.ms) { as_of = tick.time ... }`.
- [`docs/language-covenant.md`](/Users/alex/dev/projects/igniter-workspace/igniter-lang/docs/language-covenant.md) Postulate 14 says service-loop liveness maps through PROP-037 progression descriptors.
- `PROP-023` stream input is the matching direction for player strategy edits / commands arriving over time.

That maps directly onto this app:

```text
ProgressionSource(clock.every)  ->  tick.time
                                 ->  PURE CORE: WorldTick(world)
PROP-023 input stream           ->  strategy edits / commands
Effect/output capabilities      ->  broadcast, replay, persistence
```

Current status is intentionally closed: no parser/runtime ServiceLoop authority,
no scheduler, no clock capability, no socket loop. The useful fact is that
`air_combat` is already shaped for that future surface: `WorldTick` is pure, time
is an explicit tick input, and strategy dispatch is static.

**The shape of the ask.** Crucially, the *core* of the game stays pure: `WorldTick`,
the doctrines, the Kalman filter, the guidance law are all CORE contracts and should
remain so. What IO must provide is a **thin authoritative shell** around that pure
core:

```
   [ IO: clock ] → tick → [ IO: input stream ] → strategies
                              │
                              ▼
                    PURE CORE:  WorldTick(world)   ← stays pure, deterministic
                              │
                              ▼
   [ IO: output/broadcast ] ← snapshot ← [ IO: storage ] ← replay log
```

That is the right division for Igniter's philosophy: the **game logic is a pure
fold over ticks**; IO is only the membrane that feeds it time, input, randomness,
and carries its output out. Once `fold-to-struct` and `entity` land, the pure core
of this app shrinks dramatically — and the remaining surface is *exactly* the IO
membrane above. That makes `air_combat` a forcing function for both the language
tracks and the IO-runtime roadmap.

## Status

Dual-toolchain CLEAN (Ruby 0 / Rust ok 0). 8 files, 9 types, 31 contracts. This app
is a positive baseline and a pressure source — not a blocker. See
`PRESSURE_REGISTRY.md` for the routed pressure table.
