# Card: LAB-MACHINE-MCP-IO-BOUNDARY-P1 — the agent/MCP IO boundary

**Status: DEFINITION / GOVERNANCE (the fence).** Records what kind of IO the MCP/agent
surface is, so no one later infers "MCP can write → the Igniter language has IO." Written
while the insight is fresh (observed by Alex during MCP-live; affirmed by Meta-Architect).

## The two layers (do not collapse them)

| Layer | What it is | Effects |
|---|---|---|
| **Igniter language** | pure contracts: computation over facts; facts are data; deterministic dispatch | **NONE** — contract bodies have no IO, no side effects |
| **Machine / MCP (host/agent substrate)** | the controlled external shell that drives the machine | `write_fact`, `capsule_snapshot` / `fork` / `activate` / `diff`, `load_contract` / `load_program` / `resume`, `checkpoint` |

**IO lives at the agent boundary, NOT inside a contract.** The agent (via MCP) performs
effects on the world (facts, capsules). A contract, when dispatched, only *reads* facts
and *computes* — it never performs IO itself.

## Why this is the right form (not an accidental leak)

We kept IO out of the language on purpose. It re-appeared at the boundary — and that is
the correct place, because there every effect is:

- **a recorded bitemporal fact** → auditable (transaction_time = "what we knew, when");
- **an immutable capsule frame** → reversible (fork a new frame, never mutate the past);
- **loggable, diffable, replayable, constrainable** at the host level.

So this is "functional core (Igniter), agent-as-imperative-shell (MCP)". Effects are
**first-class data** (facts + frames), not opaque side-effects scattered in contract code.

## Allowed host/agent effects (the substrate API)

`write_fact` · `capsule_snapshot` · `capsule_fork` · `capsule_activate` · `capsule_diff`
· `load_contract` · `load_program` · `resume` · `checkpoint`. These are **host operations**,
attributed to the agent, recorded as facts/frames.

## FORBIDDEN inference (the whole point of this card)

- ❌ "MCP/agent can write facts, therefore contracts may do IO." **No.** Contract purity
  is unchanged: no IO opcodes, no side effects in contract bodies.
- ❌ "The machine has effects, therefore Igniter the language has effects." The effect
  surface is the **host/agent**, never the language.
- ❌ Promoting this to canon as "Igniter has IO." This is **lab host substrate**, not a
  language IO proposal. A real language-IO/effect proposal would be a separate canon route
  (and is NOT implied by this).

## Closed surfaces

- No language IO; no contract side effects; no canon IO claim.
- No new effect beyond the listed host operations.
- No durable-IO authority (file/network/clock) inside contracts.

## Relation

Pairs with `LAB-MACHINE-CAPSULE-MANAGER-P1` (the capsule control panel) and the canon
effect-surface discipline. The filmstrip tooling that exercises this boundary:
`LAB-MACHINE-MCP-FILMSTRIP-P1`.
