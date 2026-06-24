# lab-stdlib-det-math-t2-third-isa-p4-v0 — third-ISA (riscv64/qemu) determinism evidence

**Card:** `LAB-STDLIB-DET-MATH-T2-THIRD-ISA-P4` · **Type:** evidence (proof) packet
**Authority: lab evidence only — NOT canon authority, NOT a promotion.** This packet raises the *evidence
tier* for the deterministic-math surface from **T1 (two real ISAs)** toward **T2 (a third ISA / qemu matrix)**,
exactly the `LAB-1` item recommended by `lab-stdlib-det-math-canon-promotion-readiness-p3-v0.md` §5. It changes
**no** implementation and makes **no** canon/portability/science claim beyond the tier actually demonstrated.

**Status: PARTIAL T2 — earned for the math surface; full VM bundle on the third ISA deferred (blocker named).**

## Result in one line

The six-function det math surface (`det_sqrt/det_sin/det_cos/det_ln/det_exp/det_tan`) reproduces **all 14
golden-vector f64 bit patterns exactly** on a **third ISA — riscv64 (riscv64gc), under qemu** — bit-identical
to the existing x86_64+aarch64 (T1) reference. Evidence digest is **identical** across all measured targets.

## Verify-first findings

- **Golden-vector source** (exact, verified against live source): `lang/igniter-vm/tests/stdlib_math_det_tests.rs::golden_vectors_exact_bits` — 14 `f64` checks (10 non-trivial bit literals + 4 exact-value cases). Backing functions confirmed in `lang/igniter-vm/src/vm.rs::eval_math_call`: `det_sin→libm::sin`, `det_cos→libm::cos`, `det_tan→libm::tan`, `det_ln→libm::log`, `det_exp→libm::exp`, `det_sqrt→f64::sqrt` (IEEE-754). **libm pinned `=0.2.16`** (`lang/igniter-vm/Cargo.toml` + `Cargo.lock`).
- **Functions covered:** all six promotion-candidate det fns.
- **Third-ISA path available:** no native riscv64 silicon in the home lab (inventory: `ai-main-lab`=x86_64, `pi5-lab`/`pi5-lab2`=aarch64 — i.e. only the two T1 ISAs as real hardware). The viable third-ISA path is therefore **qemu**, which the card and readiness §2/§5 explicitly accept ("a third ISA / qemu matrix (e.g. riscv64)"). Executed on real lab hardware `pi5-lab` (aarch64, Debian 13, rustc **1.96.0** = the T1 toolchain, Docker 29.3.1).
- **CI/build constraint found & solved:** the lab has **no Cargo workspace root** and `igniter-vm` carries cross-crate `../` path-deps, so cross-building the *whole VM* standalone on a remote host is impractical (see Deferred). The determinism-bearing core, however, is just `libm 0.2.16` + IEEE `sqrt`; a minimal standalone harness reproduces the VM's exact dispatch and cross-compiles cleanly.

## Method (genuine bit comparison — not a re-asserted claim)

A standalone harness crate (`det-math-t2-harness/`, this directory) depends on **only `libm = "=0.2.16"`** and
computes each golden case through the **identical** functions the VM dispatches to, comparing `f64::to_bits()`
to the checked-in golden patterns. With a single pure-Rust dependency it cross-compiles to a **static**
riscv64 binary, so the same golden set runs on the third ISA under emulation.

```text
host/cross-compiler : pi5-lab — aarch64, Debian 13, rustc 1.96.0 (ac68faa20 2026-05-25)   [= T1 toolchain]
target              : riscv64gc-unknown-linux-musl, statically linked (UCB RISC-V, RVC, double-float ABI)
link                : rust-lld + -C link-self-contained=yes -C panic=abort -C target-feature=+crt-static
                      (LINK flags only — libm algorithm and IEEE sqrt are untouched; no determinism-bearing change)
runtime             : qemu-riscv64 user-mode, registered via `tonistiigi/binfmt --install riscv64`
                      (binfmt_misc F-flag interpreter; Docker 29.3.1)
libm                : =0.2.16   ;   det_sqrt = IEEE-754 f64::sqrt
riscv64 binary sha256: f305310f4c8591ab1d89c3550851028cd1af448d78bc6c95708a0b281a39bd59
```

## Exact bit comparison — 14/14 identical on riscv64

`ALL_MATCH=true`, process exit `0` on riscv64. Each line is `fn(in-bits) → out-bits == want-bits`:

| fn | input (bits) | riscv64 out = golden | OK |
|---|---|---|---|
| `det_sin` | `0x3fe0…`(0.5) | `0x3fdeaee8744b05f0` | ✓ |
| `det_cos` | `0x3fe0…`(0.5) | `0x3fec1528065b7d50` | ✓ |
| `det_sin` | `0x3ff0…`(1.0) | `0x3feaed548f090cee` | ✓ |
| `det_sqrt` | `0x4000…`(2.0) | `0x3ff6a09e667f3bcd` | ✓ |
| `det_ln` | `0x4000…`(2.0) | `0x3fe62e42fefa39ef` | ✓ |
| `det_exp` | `0x3ff0…`(1.0) | `0x4005bf0a8b14576a` | ✓ |
| `det_exp` | `0xbff0…`(−1.0) | `0x3fd78b56362cef38` | ✓ |
| `det_tan` | `0x3fe0…`(0.5) | `0x3fe17b4f5bf3474a` | ✓ |
| `det_tan` | `0x3ff0…`(1.0) | `0x3ff8eb245cbee3a6` | ✓ |
| `det_tan` | `0x3ff788…`(1.4708) | `0x4023ef1c536b2da2` | ✓ |
| `det_sqrt` | `0x4010…`(4.0) | `0x4000000000000000` (2.0) | ✓ |
| `det_ln` | `0x3ff0…`(1.0) | `0x0000000000000000` (+0.0) | ✓ |
| `det_exp` | `0x0000…`(0.0) | `0x3ff0000000000000` (1.0) | ✓ |
| `det_tan` | `0x0000…`(0.0) | `0x0000000000000000` (+0.0) | ✓ |

**Cross-ISA evidence digest** (`sha256` of the 14 `V ` payload lines):

| target | rustc | digest |
|---|---|---|
| **riscv64gc** (qemu, pi5-lab) | 1.96.0 | `1a09885b9dfefb1276106db8e3b16b5e807ed3008deeb256cbc080824b272667` |
| aarch64-linux (pi5-lab, native) | 1.96.0 | `1a09885b9dfefb1276106db8e3b16b5e807ed3008deeb256cbc080824b272667` |
| aarch64-darwin (mac, native) | 1.95.0 | `1a09885b9dfefb1276106db8e3b16b5e807ed3008deeb256cbc080824b272667` |

All three **identical** → the third ISA agrees bit-for-bit. (The 1.95.0 mac run is *incidental* corroboration
only; this packet makes **no T3 / toolchain-invariance claim** — see Closed surfaces.)

## Exact commands

```bash
# on pi5-lab (aarch64, rustc 1.96.0), crate at ~/det-math-t2-harness:
. ~/.cargo/env
rustup target add riscv64gc-unknown-linux-musl
SYS=$(rustc --print sysroot); LLD=$(find "$SYS" -name rust-lld | head -1)
RUSTFLAGS="-C linker=$LLD -C linker-flavor=ld.lld -C link-self-contained=yes \
          -C panic=abort -C target-feature=+crt-static -C relocation-model=static" \
  cargo build --release --target riscv64gc-unknown-linux-musl
docker run --privileged --rm tonistiigi/binfmt --install riscv64     # register qemu-riscv64 in binfmt_misc
./target/riscv64gc-unknown-linux-musl/release/det-math-t2-harness     # runs under qemu via binfmt
#   → prints 14 `V …` lines, `# arch=riscv64`, `ALL_MATCH=true`; exit 0
./target/.../det-math-t2-harness | grep '^V ' | sha256sum             # → 1a09885b…272667
```

## Acceptance — mapping

- [x] Golden-vector source + exact functions identified (the 6 det fns; `stdlib_math_det_tests.rs`).
- [x] Third-ISA path identified: **qemu** (no native riscv64 silicon in lab) on real host `pi5-lab`.
- [x] Ran the det-math harness on the third ISA and **compared exact IEEE-754 bits** to the existing targets → 14/14 identical, digest match.
- [~] Minimal deterministic **bundle** on the third ISA — **deferred** (blocker below); the math-surface bits (the determinism-bearing core of any bundle) are proven identical.
- [x] Proof doc produced (this file).
- [x] **No det-math implementation changed** (no real mismatch found — nothing to fix).
- [x] `git diff --check` clean (additions are new untracked files only).

## Effect on canon-promotion readiness (P3 §5)

- **`LAB-1` (T2 third ISA):** moved from **open → substantially met for the det math *surface*** via a qemu
  riscv64 matrix with exact bit-identity. Readiness §2's T2 row can cite this packet.
- **Remaining nuance to keep wording honest:** (a) **qemu, not real riscv64 silicon** — emulated, faithful to
  the ISA's IEEE-754 F/D semantics but not a hardware claim; (b) the **full compiler→VM→bundle** run on
  riscv64 is not yet done. Neither blocks the §6 STDLIB_VERSION-relative, ISA-scoped wording; the canon PROP
  (GOV-1/GOV-2) remains the actual gate. **This packet is input to promotion, not the act.**

## Deferred (precise, not faked)

- **Full VM bundle on riscv64.** Blocker: the lab has **no Cargo workspace root**; `igniter-vm` resolves
  sibling crates by `../` path-deps, so cross-building the VM (or its `golden_vectors_exact_bits` test binary)
  standalone on a remote/emulated host needs the whole crate tree transferred and a heavier static-musl
  riscv64 link of `tokio`+deps. Out of proportion for this card. The exact next step: cross-build
  `igniter-vm`'s `stdlib_math_det_tests` for `riscv64gc-unknown-linux-musl` and run it under the same qemu
  binfmt — it must reproduce the same golden bits (the harness already proves its math core does).
- **Real riscv64 silicon.** No board in the lab inventory; acquiring one (e.g. VisionFive 2 / Pi-class
  riscv64) would upgrade qemu-T2 → hardware-T2.
- **T3 toolchain-variation** — explicitly **not** claimed here (see Closed surfaces), though the 1.95/1.96
  agreement is suggestive for a future LAB-2.

## Closed surfaces (honored)

No canon promotion; no `STDLIB_VERSION` change (no implementation change); no new math primitive; **no
toolchain-invariance claim**; no science claim beyond the tier achieved (qemu third-ISA math-surface bit
identity — not real-silicon, not full-bundle).

## Artifacts

- `lab-docs/lang/det-math-t2-harness/{Cargo.toml,src/main.rs}` — the standalone golden harness (libm =0.2.16).
- riscv64 static binary sha256 `f305310f4c8591ab1d89c3550851028cd1af448d78bc6c95708a0b281a39bd59` (built on `pi5-lab`, under `~/det-math-t2-harness/target/riscv64gc-unknown-linux-musl/release/`).
- Cross-ISA evidence digest `1a09885b9dfefb1276106db8e3b16b5e807ed3008deeb256cbc080824b272667`.

---

*Lab evidence. 2026-06-24. T2 third-ISA (riscv64gc, qemu) determinism for the det math surface: all 14 golden
f64 bit patterns reproduced exactly on riscv64, digest-identical to the x86_64+aarch64 (T1) reference. qemu,
not silicon; math surface, not full VM bundle (deferred, blocker = no Cargo workspace root for igniter-vm).
Evidence only — promotion remains a governance act.*
