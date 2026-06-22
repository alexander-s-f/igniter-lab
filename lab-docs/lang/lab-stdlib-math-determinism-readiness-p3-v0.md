# lab-stdlib-math-determinism-readiness-p3-v0 — deterministic transcendental math fork

**Card:** `LAB-STDLIB-MATH-DETERMINISM-READINESS-P3` · **Type:** readiness / design (NO code)
**Status:** CLOSED (readiness) — decides the v0 deterministic-math strategy + surface that can be built later
without breaking P2's fast `f64` path. Runs in parallel with P2; does **not** block it.
**Authority:** Lab readiness. Recommendation, not implementation. Grounded in live wiring + prior governance.

## Why this matters (and is not the same as P2)

P2 adds fast `stdlib.Math.sin/cos/sqrt/pi` over platform `libm` (`f64`). That is correct and useful — **but
platform `f64` transcendentals are NOT cross-architecture deterministic.** IEEE-754 mandates correct rounding
only for `+ − × ÷` and **`sqrt`**; it does **not** mandate it for `sin/cos/exp/ln` — every platform `libm`
may return different last bits ("table-maker's dilemma"), and x87 80-bit intermediates / `-ffast-math` /
FMA-contraction perturb results further. So the moment a simulation, consensus, or swarm node treats
`stdlib.Math.sin` output as canonical, **byte-identical replay silently breaks across machines.** The
emergence research line's headline thesis (exact reproducible replay) and the embedded-swarm line both depend
on a deliberate answer here.

## Verify-first findings (live)

- **`f64` serializes deterministically — except non-finite.** VM `value.rs`: `Value::Float(f) =>
  serde_json::Value::from(*f)`. serde_json uses **ryū** (shortest round-trip) for finite `f64` → deterministic
  and lossless in the observation/lineage stream. **But `serde_json::Value::from(NaN|Inf)` yields JSON
  `null`** (serde can't represent them) → information loss and a replay/digest hazard. **Any deterministic
  surface must keep results finite** (so `det.sqrt(-1.0)` cannot just return `NaN`).
- **`sqrt` is already deterministic by IEEE-754.** It is a correctly-rounded mandated operation; std `f64::sqrt`
  is bit-identical across IEEE-754-compliant FPUs (caveat: must avoid x87 80-bit and `fast-math`; Rust's
  default SSE2/AArch64/RISC-V `f64` path is compliant). So **`det.sqrt` needs no special algorithm** — only a
  finite-domain guard.
- **Deterministic math already exists in the lab as an app convention.** `lab-stdlib-numeric-fixed-point-readiness-v0`
  (CLOSED–SPLIT): `neural_net`, `vector_math`, and the `LAB-PURSUIT` quadcopter run **scale-1000 fixed-point
  Integer** arithmetic — integer-only, bit-identical across architectures by construction. `igniter-stdlib-numeric-coverage-proposal-readiness-v0`
  independently names this the keystone embed gap ("no `abs/min/max/clamp/isqrt/pow`, no `sqrt/sin/cos/atan`").
  So a fixed-point deterministic path is **prior art to formalize, not invention.**
- **`pi` is already deterministic.** It is a literal constant (`0x400921FB54442D18`), bit-identical
  everywhere — `pi()` needs no `det` variant.
- **`Decimal{value:i64, scale:u32}`** (`igniter-stdlib/src/decimal.rs`) is the existing fixed-point carrier
  (`to_f64`/`from_f64`, scale-matched add) — the natural return type for an integer-domain det path.
- P2 had not landed `sin` at read time; this packet targets the *expected* P2 surface, no assumption on wiring.

## The honest core distinction

| Op | IEEE-754 status | Deterministic today? | v0 answer |
|---|---|---|---|
| `+ − × ÷` | correctly rounded (mandated) | yes (compliant FPU) | already fine |
| `sqrt` | correctly rounded (mandated) | **yes** | `det.sqrt` = std `f64::sqrt` + finite guard |
| `sin` `cos` | **not** mandated | **no** (platform libm varies) | needs a **fixed algorithm** |
| `pi` | constant | yes | `pi()` already deterministic |

So the only genuinely hard problem is **deterministic `sin`/`cos`** (and later `tan/exp/ln/atan`).

## Strategy comparison (≥4)

| # | Strategy | Return | Cross-arch determinism | Error budget | Effort | Embedded (FPU-less) | Verdict |
|---|---|---|---|---|---|---|---|
| 1 | **Vendored pure-Rust `libm` (MUSL port)** | `Float` | **yes** — same algorithm everywhere; Rust does **not** auto-contract FMA (needs explicit `mul_add`), so bits are fixed across targets | ≤ ~1–2 ULP (libm-quality) | **low** | works (soft `f64`, slower) | **RECOMMENDED for sin/cos** |
| 2 | Fixed-point **CORDIC** | `Integer`/`Decimal[N]` | yes (integer shift-add) | ~2^-(n) after n iters (n=20 → ~2e-6) | medium | **ideal** (no FPU) | defer (embedded track) |
| 3 | Fixed-point **minimax polynomial** (range-reduced to [−π/4,π/4]) | `Integer`/`Decimal[N]` | yes (integer mul+shift) | degree-5 → ~1e-7 | medium | ideal | defer (embedded track) |
| 4 | **LUT + interpolation** | `Integer`/`Decimal[N]` | yes | table-density bound | low–med | ok (memory cost) | defer |
| 5 | Rational/Padé | `Float`/fixed | yes if fixed algorithm | tunable | medium | ok | subsumed by #1 |
| 6 | **Host-provided deterministic backend** (capability) | any | **no** — reintroduces host/platform variance | — | low | n/a | **rejected** (defeats the purpose) |
| — | std `f64::sqrt` (IEEE) | `Float` | **yes** (mandated) | ≤0.5 ULP | trivial | ok | **RECOMMENDED for sqrt** |

## Recommendation (v0)

**Two honest surfaces, never confusable** (the card's bias, endorsed):

- `stdlib.Math.sin/cos/sqrt` = **fast**, platform `f64` libm (P2). Useful for local sim/visualization. NOT a
  determinism claim — documented as such.
- `stdlib.Math.det.sin/det.cos/det.sqrt` = **deterministic, replay-safe, `Float` return**, implemented as:
  - `det.sqrt` → std `f64::sqrt` (already IEEE-correct) + a **finite-domain guard** (negative input → `Result`/
    error, never `NaN`, because `NaN`→JSON `null`).
  - `det.sin`/`det.cos` → **vendored pure-Rust `libm` crate** (MUSL port), the same fixed algorithm on every
    target. This unblocks Kuramoto by a **one-line swap** (`sin` → `det.sin`) with no fixed-point rewrite.

**Return type = `Float`** for the v0 det surface: the determinism lives in the *algorithm*, not the type, and
keeping `Float` lets the emergence sims (Kuramoto and beyond) adopt it without rewriting into scaled integers.

**The fixed-point Integer/Decimal det path (#2–#4) is deferred to a separate embedded track** — it is the
right answer for FPU-less microcontrollers (ESP32-C3/C6 RISC-V may lack an `f64` FPU) and aligns with the
existing scale-1000 app convention. Name it now, build it when the swarm needs integer-only nodes:
`LAB-STDLIB-MATH-DET-FIXEDPOINT-READINESS-Pn` (consumes `lab-stdlib-numeric-fixed-point-readiness-v0`).

### Surface-name note (grammar dependency)

`stdlib.Math.det.sin` assumes a **3-level** dotted stdlib namespace. Live stdlib is 2-level (`stdlib.Math`,
`stdlib.collection`). If the grammar/dispatch does not accept a third segment, fall back to a dedicated module
`stdlib.DetMath.sin` (2-level, equally unambiguous) or `stdlib.Math.det_sin`. **Verify before P4 implements**;
the readiness recommendation is the `det` grouping, exact spelling TBD by grammar.

## Error budget (v0)

- `det.sqrt`: correctly rounded, ≤ 0.5 ULP (IEEE).
- `det.sin`/`det.cos`: libm-quality, **≤ ~2 ULP** worst case — *but the load-bearing property is
  bit-reproducibility across architectures, not minimal error.* The contract is "same bits everywhere,"
  characterized by golden vectors.
- (deferred fixed-point track): state per-method (CORDIC n=20 → <2e-6; degree-5 poly → ~1e-7).

## Domain / edge semantics (Q4/Q5)

- Angles in **radians** (match the fast path). Range reduction handled by the libm port (correct for large
  arguments — a classic determinism pitfall the MUSL algorithm already solves).
- `det.sqrt(x<0)` → **`Result::Err`** (or a documented domain error), **never `NaN`** — because non-finite
  `f64` serializes to JSON `null` (verified), which would corrupt the lineage/digest. The fast `sqrt` may
  return `NaN`; the **det** surface must not.
- `det.sin/cos` are total on finite inputs; document behavior at `±Inf` input as a domain error (don't
  propagate non-finite).

## Test strategy WITHOUT multiple physical architectures (Q7)

1. **Golden-vector bit tests** — a checked-in table `(input → exact f64 bits)` computed once from the chosen
   algorithm; assert exact reproduction. These bits **are** the cross-arch contract.
2. **Bit-stability** — run twice, assert identical (guards against accidental nondeterminism, e.g. hashmap
   iteration order).
3. **Differential vs platform libm** — assert `det.sin` may differ from `f64::sin` yet stays within tolerance;
   proves the det path is a distinct, canonical implementation (not a passthrough).
4. **CI cross-compile + emulate** — run the golden-vector suite under `qemu`/`cross` for `aarch64` and
   `riscv64`; assert identical bits across targets. When run, this is a **real cross-arch proof with no
   physical hardware**, and the strongest local evidence.
5. **True in-materio proof = the swarm** — bit-identity on actual ESP32 vs host is the emergence Stage-3 /
   swarm validation; stated as **future** verification, claimed conservatively until then.

**Conservative claim wording (Q4 bias):** "Lab claim: fixed-algorithm/golden-vector deterministic surface;
qemu cross-arch identity and physical multi-arch identity remain pending until those proof cards record them."
Do **not** claim hardware cross-arch identity before #5.

## Interaction with source_hash / lock / provenance / replay (Q9)

- The det algorithm is part of the **stdlib surface** → governed by the compiler-owned **`STDLIB_VERSION`**
  (package wave P6). Any change to the det implementation MUST bump `STDLIB_VERSION` → `igniter.lock`
  `toolchain.stdlib` drift catches it (`verify`/`--frozen`). The determinism guarantee is thus **versioned and
  lock-pinned**.
- **det.* is the prerequisite that extends byte-identical VM replay from Integer/Decimal to transcendental
  `Float` sims.** Today exact replay holds for integer/Decimal; a sim using platform `sin` would diverge
  across machines. `det.sin` closes the fixed-algorithm/golden-vector gap; qemu cross-arch and physical swarm
  identity remain separate proof gates.
- **Float serialization caveat (verified):** finite `f64` → JSON via ryū is deterministic + lossless; non-finite
  → `null`. Hence the finite-domain guards above. A separate hardening could give the value model an explicit
  non-finite policy, but for v0 the det surface simply stays finite.

## Pi (Q8)

No `det.pi` — `pi()` returns a constant literal, bit-identical by construction. (If a fixed-point track lands,
it provides a scaled-integer `pi` constant for that domain.)

## Implementation card + acceptance matrix (required deliverable)

**Next card: `LAB-STDLIB-MATH-DET-TIER1-P4` — deterministic Tier-1 (`det.sin/det.cos/det.sqrt`).**

| Acceptance dimension | Target |
|---|---|
| Surface | `det.*` grouping (exact spelling per grammar check), distinct from fast path |
| `det.sqrt` | std `f64::sqrt`; `x<0` → domain error (never NaN) |
| `det.sin`/`det.cos` | vendored pure-Rust `libm` (MUSL port); explicit no-FMA discipline |
| Return type | `Float`, finite-guaranteed |
| Determinism proof | golden-vector bit tests + bit-stability + **CI `qemu` aarch64/riscv64 identical bits** |
| Error budget | sqrt ≤0.5 ULP; sin/cos ≤~2 ULP, bit-reproducible |
| Provenance | bump `STDLIB_VERSION`; lock-drift test for det-algorithm change |
| Non-finite | no NaN/Inf escapes to the observation stream |
| Dep footprint | one pure-Rust `no_std` crate (`libm`); weigh vs the "no new deps" bias explicitly in P4 |
| Scope | no fixed-point/CORDIC, no `tan/exp/ln`, no Decimal transcendentals, no implicit coercion |

## Acceptance (this card) — mapping

- [x] ≥4 implementation strategies compared (6 in the table).
- [x] Recommended deterministic surface (`det.*`) + return type (`Float`, finite-guarded) chosen.
- [x] Error budget + test strategy (golden vectors + CI cross-emulation) proposed.
- [x] Cross-arch/replay claim stated **conservatively** (fixed algorithm + golden-vector plan; qemu and
  hardware proof gates remain explicit).
- [x] Interaction with `source_hash`/lock/`STDLIB_VERSION`/replay addressed.
- [x] No production code changes (design-only).

## Closed scope

No implementation; no fixed-point/CORDIC/LUT build; no `tan/exp/ln`; no Decimal transcendentals; no numeric
tower / implicit coercion; no determinism claim about P2's fast `f64` path; no canon claim.

## Next

`LAB-STDLIB-MATH-DET-TIER1-P4` (impl per the matrix), and — separately, when the swarm needs FPU-less integer
nodes — `LAB-STDLIB-MATH-DET-FIXEDPOINT-READINESS-Pn` (formalize the scale-1000 CORDIC/poly path into stdlib,
consuming `lab-stdlib-numeric-fixed-point-readiness-v0`).

---

*Lab readiness. 2026-06-21. Deterministic transcendentals decided: fast `f64` (P2) and a `det.*` surface that
returns `Float` made reproducible by a fixed pure-Rust `libm` algorithm (`sin`/`cos`) plus IEEE-correct
`sqrt`, finite-guarded against the verified NaN→`null` serialization hazard, lock-pinned via `STDLIB_VERSION`.
The lab claim is fixed-algorithm/golden-vector determinism; qemu cross-emulation and physical swarm identity
remain pending proof gates. Fixed-point integer det math (existing scale-1000 app convention) is a named,
deferred embedded track.*
