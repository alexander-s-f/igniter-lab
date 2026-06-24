# det_* lab→canon promotion — readiness packet (P3 v0)

Card: `LAB-STDLIB-DET-MATH-CANON-PROMOTION-READINESS-P3`. Date: 2026-06-24.
**Authority: lab readiness. Recommendation, not a promotion. No code changes. Canon promotion is a
governance decision — never lab alone** (`igniter-gov/DELTA-LEDGER.md`, `authority-and-certification.md`).

This packet decides *what is required* to promote the deterministic math surface `det_*` from lab
frontier to a stable/canon stdlib surface, and gives a per-function promote/defer recommendation. It
does not promote anything.

## 1. What exists today (verified against source)

Surface (`lang/igniter-stdlib/stdlib/math.ig`; VM impl `lang/igniter-vm/src/vm.rs::eval_math_call`):

| fn | built on | totality (never NaN/Inf escapes) |
| --- | --- | --- |
| `det_sqrt(x)` | **IEEE-754 `f64::sqrt`** (correctly-rounded by the standard) | non-finite → error; `x<0` → domain error |
| `det_sin(x)` | `libm::sin` (pinned pure-Rust libm) | non-finite input → error |
| `det_cos(x)` | `libm::cos` | non-finite input → error |
| `det_ln(x)` | `libm::log` | non-finite → error; `x≤0` → domain error |
| `det_exp(x)` | `libm::exp` | non-finite → error; overflow → error; underflow → exact `0.0` |
| `det_tan(x)` | `libm::tan` | non-finite input/result (pole) → error; finite over `(−π/2, π/2)` |

- **libm pinned** `0.2.16` (`lang/igniter-vm/Cargo.toml`) — pure-Rust MUSL soft-float port; no system libm.
- **Golden vectors**: exact `f64` bit literals in `lang/igniter-vm/tests/stdlib_math_det_tests.rs`
  (`golden_vectors_exact_bits`), tolerance = **exact bit equality** (`u64` patterns), generated once from
  `libm 0.2.16` and checked in. A libm/algorithm change flips bits → test fails → forces a governed
  `STDLIB_VERSION` bump.
- **STDLIB_VERSION** `0.1.7` (`lang/igniter-compiler/src/lib.rs`, mirrored in `igniter-stdlib/Cargo.toml`);
  guard `stdlib_version_mirrors_crate`. Surface grew `0.1.0→0.1.1` (Tier-1 P5) → `0.1.6` (ln/exp P1) →
  `0.1.7` (tan P2).
- The fast `stdlib.Math.sin/cos/sqrt` (P2) is a **separate, explicitly non-deterministic** path — not part
  of this promotion.

## 2. Evidence tier actually achieved

| tier | definition | det_* status |
| --- | --- | --- |
| T0 | deterministic & exactly replayable on a fixed build, same ISA | **achieved** (golden vectors + run-to-run repeatability) |
| T1 | bit-identical across ≥2 **real** ISAs, **fixed toolchain** | **achieved** — x86_64 (AMD Ryzen V1756B) + aarch64 (Cortex-A76), `rustc 1.96.0`, `libm 0.2.16` |
| T2 | + a third ISA / qemu matrix (e.g. riscv64) | **open** |
| T3 | toolchain variation (≥2 rustc / libm pin policy stated as contract) | **open** (see §6 — may be unnecessary if wording is STDLIB_VERSION-relative) |
| T4 | physical embedded multi-arch (ESP32 swarm) | **open / out of scope for stdlib promotion** |

T1 evidence is **distributed** across repos (a governance observation in itself — a PROP must consolidate it):
- Tier-1 math grid (`det_sin/cos/sqrt`): `igniter-emergence/experiments/determinism-cross-arch-t1/results/comparison.json` — identical SHA-256 `85cb3828…` on both real ISAs; "NOT qemu emulation"; controlled `rustc 1.96.0` + `libm 0.2.16`.
- Tier-2 ln/exp: lab card `LAB-STDLIB-MATH-DET-TIER2-LN-EXP-P1` — 6001-pt grid SHA-256 `9d420a30…` bit-identical, real x86_64 + aarch64.
- Tier-2 tan: lab card `LAB-STDLIB-MATH-DET-TIER2-TAN-P2` — 3001-pt grid SHA-256 `31b0294d…`, same.
- One full result **bundle** (compiler→VM→measurement→CSV) bit-identical cross-arch: `igniter-emergence` cards `…BUNDLE-CROSS-ARCH-P3`, `…MEASUREMENT` (P13).

Note: the original P5 lab proof doc said Tier-1 cross-arch was "deferred to qemu CI"; that gap was later
**closed empirically on real hardware** by the consuming project. The honest current claim is **T1, not
T0**, but **not** T2/T3/T4.

## 3. Promote / defer recommendation (per function)

Promotion-**eligible** = has golden vectors **and** T1 cross-arch bit-identity **and** a clean totality
rule. All six qualify. Recommended v1 candidate set = all six, promoted as one coherent surface (a
fragmented half-surface is worse DX), **conditioned on the §5 gate**.

| fn | evidence | totality | consumer pull | verdict |
| --- | --- | --- | --- | --- |
| `det_sqrt` | T1 + **IEEE-mandated** (strongest) | clean | — | **promote v1** (anchor; portable by standard) |
| `det_sin` | T1 (golden + real 2-ISA) | clean | **load-bearing** (emergence Kuramoto coupling) | **promote v1** |
| `det_cos` | T1 | clean | host measurement (via libm) | **promote v1** |
| `det_ln` | T1 | clean (domain error `x≤0`) | — | **promote v1** |
| `det_exp` | T1 | clean (overflow error) | — | **promote v1** |
| `det_tan` | T1 | pole→error; Lorentzian-range only | optional (ω generation) | **promote v1** (document the operational range) |
| `det_atan2` | none (named, not implemented) | — | science-pulled gap (mean phase angle) — not yet needed | **defer** |
| `det_pow` | none (named, not implemented) | — | — | **defer** |
| distributions | `random.ig` is integer-PRNG; distributions not built | — | — | **defer** (separate track) |

If governance prefers a minimal first promotion, the conservative subset is `{det_sqrt, det_sin,
det_cos}` (Tier-1; det_sqrt IEEE-anchored, det_sin the only load-bearing science dependency), with
`{det_ln, det_exp, det_tan}` as v1.1 — but their evidence is already equivalent, so this packet
recommends the full six.

## 4. Authority boundary (evidence vs canon)

| actor | owns | must not |
| --- | --- | --- |
| **Lab** (`igniter-lab`) | the `det_*` impl, golden-bit lock, evidence; can raise the evidence tier (T1→T2→T3) | claim canon authority or a public/stable/portability guarantee |
| **Canon** (`igniter-lang`) | whether `det_*` is a stable, citeable language surface; the determinism **wording** | import behavior/evidence as authority "from lab alone" |
| **Science** (`igniter-emergence`) | claim wording; must license each sentence to the demonstrated tier (today T1, fixed toolchain) | claim third-ISA / toolchain-invariance / embedded identity / canon status |

Governance rule (quoted): *"`lab-ahead` — lab proved a form; canon has not committed. Route =
open/advance a PROP. Lab form is pressure evidence, not grammar."* (`igniter-gov/DELTA-LEDGER.md`).
*"never lab alone."* Canon today defines **no** transcendental math — only integer/float/decimal/numeric
operators (`igniter-lang/docs/spec/ch8-stdlib.md`, PROP-013, fragment class CORE). So `det_*` promotion is
net-new canon surface, not an edit of an existing one.

## 5. Acceptance matrix — implementation/governance follow-up

| id | owner | task | gate |
| --- | --- | --- | --- |
| GOV-1 | canon | Open a PROP in `igniter-lang` for the `det_*` stdlib surface: candidate set (§3), signatures, **determinism contract** (§6), totality rules (§1), libm-pin + golden-vector lock as conformance. | PROP drafted |
| GOV-2 | governance | Review + gate decision (canon gate/PROP process, e.g. `igniter-lang/.agents/work/gates/`); record in `DELTA-LEDGER` (`lab-ahead` → accepted). | gate decision doc |
| LAB-1 | lab | **T2**: qemu (or real) **third ISA** (riscv64) golden-vector + one-bundle proof; bit-compare. | new proof card |
| LAB-2 | lab/canon | Decide T3: either run a toolchain-variation check **or** adopt STDLIB_VERSION-relative wording (§6) so toolchain-invariance is explicitly *not* claimed. | wording or proof |
| LAB-3 | lab | Consolidate the distributed T1 evidence (emergence + lab cards) into a single conformance artifact the PROP can cite. | artifact |
| EMG-1 | emergence | Keep claim wording locked to demonstrated tier (already done: `EMERGENCE-DETERMINISM-CLAIM-WORDING-LOCK-P10`). Re-license if a tier changes. | wording lock green |
| DEFER | — | `det_atan2`, `det_pow`, distributions stay lab-only until science-pulled **and** evidence tier met. | — |

Recommended **minimum canon-promotion gate**: T1 (met) **+ LAB-1 (T2 third ISA)** + GOV-1/GOV-2, with
canon wording per §6. T3/T4 are **not** required for a v1 stdlib promotion if the contract is
STDLIB_VERSION-relative.

## 6. Canon wording that avoids overclaiming (the six questions, answered)

1. **Candidate v1 set** — `{det_sqrt, det_sin, det_cos, det_ln, det_exp, det_tan}` (§3). Defer
   `det_atan2`, `det_pow`, distributions.
2. **Evidence tier required** — already at **T1** (two real ISAs, fixed toolchain). Recommended promotion
   gate adds **T2** (a third ISA / qemu). T4 (physical embedded swarm) is a *swarm* claim, not a
   precondition for a stdlib surface.
3. **libm + golden-vector locking** — libm pinned (`0.2.16`) in the build; golden vectors are exact-bit
   literals; **STDLIB_VERSION** bumps on any algorithm/libm change and `igniter.lock` drift is caught by
   `verify`/`--frozen`. For canon: adopt the golden-vector test as a **conformance artifact** and treat the
   libm pin as part of the versioned contract.
4. **Totality/domain rules** — *never* NaN/Inf escapes; every out-of-domain or non-finite case is a
   **deterministic runtime error** (per-fn in §1; `det_exp` underflow → exact `0.0`). Canon should adopt
   these errors as part of the spec, not implementation detail.
5. **Lab-only remainder** — `det_atan2` (the real science-pulled gap, for mean phase angle `atan2(Σsin,
   Σcos)`, but *not yet needed*), `det_pow`, and probability distributions.
6. **Wording that avoids overclaim** — scope determinism to **"bit-identical for a given STDLIB_VERSION
   (which pins the libm algorithm), across the supported/tested ISA set"** — *not* "all platforms /
   toolchains". Distinguish `det_sqrt` (**IEEE-754 correctly-rounded — portable by the standard**) from
   `det_sin/cos/ln/exp/tan` (**fixed pure-Rust algorithm, bit-identical across tested ISAs; not an IEEE
   correct-rounding guarantee**). Do not use gov-forbidden phrasing ("portability guarantee", "production
   ready", "stable API") before authority. This mirrors lab's existing conservative wording and emergence's
   tier-licensed claims.

## 7. Bottom line

The `det_*` surface is **technically promotion-eligible at T1** with a clean totality story and a
versioned lock. The blocking items are **governance, not engineering**: a canon PROP + gate decision
(GOV-1/GOV-2) and one cheap evidence broadening (LAB-1, third ISA). Canon wording must stay
STDLIB_VERSION-relative and ISA-scoped. Promotion remains a governance act; this packet is the input to
it, not the act.
