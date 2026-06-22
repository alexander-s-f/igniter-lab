# LAB-STDLIB-MATH-DETERMINISM-READINESS-P3 — deterministic math fork

Status: CLOSED
Lane: standard / stdlib math
Type: readiness / design
Delegation code: OPUS-STDLIB-MATH-DETERMINISM-READINESS-P3
Date: 2026-06-21
Skill: idd-agent-protocol

## Context

P1 found that emergence/Kuramoto and embedded swarm workloads both need transcendentals. P2 is expected to add
fast f64 `stdlib.Math.sin/cos/sqrt/pi`. That path is useful, but it is not a cross-architecture determinism
claim. For replay, consensus, embedded swarm, and long-running simulations, Igniter needs a deliberate answer to
"deterministic math" before users accidentally treat f64 libm behavior as canonical.

This card is design/readiness only. It should run in parallel with P2, but it must not block P2's fast path.

## Goal

Decide the v0 deterministic math strategy and surface. Produce a recommendation for `stdlib.Math.det.*` (or a
better name) that can be implemented later without breaking the fast f64 surface.

## Verify first

- P1 math pressure doc: `lab-docs/lang/lab-stdlib-math-pressure-kuramoto-p1-v0.md`
- P2 if already in progress/closed.
- Existing Decimal/fixed-point docs and implementation:
  - `lang/igniter-stdlib/src/decimal.rs`
  - `lab-docs/governance/igniter-stdlib-numeric-coverage-proposal-readiness-v0.md`
  - `lab-docs/governance/lab-stdlib-numeric-fixed-point-readiness-v0.md`
- VM Float serialization/evaluation behavior.
- Embedded/swarm/evidence docs if present; do not invent claims if not found.

## Questions to answer

1. What determinism level do we need for v0: same machine run, same architecture, or cross-architecture
   bit-identical?
2. Should deterministic math return `Decimal[N]`, scaled Integer, or Float with deterministic algorithm?
3. Which implementation family is best for Tier-1:
   - fixed-point polynomial;
   - CORDIC;
   - lookup table + interpolation;
   - rational approximations;
   - vendored pure Rust deterministic crate;
   - host-provided deterministic backend?
4. What is the acceptable error budget for `det.sin`, `det.cos`, and `det.sqrt`?
5. How are domains normalized (`sin` angle units, range reduction, sqrt negative)?
6. What surface name keeps the fast/nondeterministic and deterministic paths impossible to confuse?
7. What tests can prove determinism without multiple CPU architectures available locally?
8. Should `pi` have a deterministic representation distinct from f64 `pi()`?
9. How does this interact with source hashes, lock/provenance, and VM replay?

## Bias

Prefer two honest surfaces over one ambiguous one:

- `stdlib.Math.sin` = fast f64, useful for local simulation/visualization.
- `stdlib.Math.det.sin` or equivalent = deterministic, bounded error, replay-safe.

Do not pretend Rust/libm f64 is cross-arch deterministic unless proven.

## Required deliverable

- Readiness packet: `lab-docs/lang/lab-stdlib-math-determinism-readiness-p3-v0.md`
- Closing report in this card.
- A concrete implementation card name and acceptance matrix for deterministic Tier-1.

## Acceptance

- [x] At least four implementation strategies compared. (6 in the strategy table.)
- [x] Recommended deterministic surface and return types chosen. (`det.*`, `Float` finite-guarded.)
- [x] Error budget and test strategy proposed. (golden vectors + bit-stability + CI qemu cross-emulation.)
- [x] Cross-architecture/replay claim stated conservatively. (fixed algorithm + golden-vector plan; qemu and
  hardware remain proof gates.)
- [x] Interaction with source_hash/lock/provenance addressed. (`STDLIB_VERSION`-pinned; det = replay linchpin.)
- [x] No production code changes.

## Closed scope

- No implementation.
- No broad numeric tower.
- No implicit coercions.
- No deterministic claim for P2 f64 math.

---

## Closing Report (2026-06-21)

**Decision:** two honest surfaces. `stdlib.Math.sin/cos/sqrt` = fast platform `f64` (P2, NOT a determinism
claim); **`stdlib.Math.det.*` = deterministic `Float`**, built from (a) std `f64::sqrt` (IEEE-754 already
correctly-rounded → cross-arch deterministic) + finite-domain guard, and (b) a **vendored pure-Rust `libm`
(MUSL port)** for `det.sin/det.cos` — same fixed algorithm on every target, and Rust does not auto-contract
FMA, so bits are reproducible across architectures. Return `Float` (determinism in the algorithm, not the
type) so emergence sims adopt it by a one-line `sin→det.sin` swap, no fixed-point rewrite.

**Key verify-first findings that shaped it:** IEEE-754 mandates correct rounding for `sqrt` (so `det.sqrt`
needs no special algorithm) but NOT for `sin/cos` (the only hard problem); `pi()` is a constant, already
deterministic; **non-finite `f64` serializes to JSON `null`** in the VM observation stream (verified) → det
functions must stay finite (`det.sqrt(<0)`→error, never NaN); deterministic math already exists in-lab as the
**scale-1000 fixed-point Integer** app convention (neural_net/vector_math/quadcopter — prior art, not
invention), so the integer-domain det path is a **named, deferred embedded track**, not v0.

**Determinism is versioned + lock-pinned:** the det algorithm is part of the stdlib surface → bump
`STDLIB_VERSION` (package P6) → `igniter.lock` `toolchain.stdlib` drift catches any change. `det.*` is the
**linchpin** that extends byte-identical VM replay from Integer/Decimal to transcendental `Float` sims — the
direct connection to the emergence "exact replay" thesis and the swarm.

**Proof strategy without multi-arch HW:** golden-vector bit tests + bit-stability + **CI `qemu` aarch64/riscv64
identical-bits**. When run, qemu is the cross-arch proof without physical hardware; physical ESP32-vs-host
identity = the future swarm Stage-3 validation, claimed conservatively until then.

**Deliverables:** readiness packet `lab-docs/lang/lab-stdlib-math-determinism-readiness-p3-v0.md`; concrete
impl card `LAB-STDLIB-MATH-DET-TIER1-P4` named with an acceptance matrix (surface, sqrt/sin/cos sources,
return type, determinism proof, error budget, provenance, non-finite policy, dep footprint, scope).
**Open grammar dependency for P4:** confirm whether `stdlib.Math.det.sin` (3-level) parses or fall back to
`stdlib.DetMath.sin` / `det_sin`. No production code changed; design-only.

**Next:** `LAB-STDLIB-MATH-DET-TIER1-P4` (impl), and a separate `LAB-STDLIB-MATH-DET-FIXEDPOINT-READINESS-Pn`
when the swarm needs FPU-less integer nodes (consumes `lab-stdlib-numeric-fixed-point-readiness-v0`).
