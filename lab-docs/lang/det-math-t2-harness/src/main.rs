// LAB-STDLIB-DET-MATH-T2-THIRD-ISA-P4 — deterministic-math golden harness.
//
// Recomputes the EXACT det_* surface the VM uses (`igniter-vm/src/vm.rs::eval_math_call`) with the
// SAME backing functions — libm 0.2.16 for sin/cos/tan/ln/exp, IEEE-754 `f64::sqrt` for sqrt — and compares
// the resulting f64 BIT PATTERNS to the checked-in golden vectors
// (`igniter-vm/tests/stdlib_math_det_tests.rs::golden_vectors_exact_bits`).
//
// The point of this standalone crate is portability: with only `libm` as a dependency it cross-compiles to a
// self-contained static riscv64 binary, so the same golden set can be evaluated on a THIRD ISA (riscv64,
// under qemu) and bit-compared to the x86_64+aarch64 (T1) reference. Output is deterministic; lines prefixed
// `V ` are the hashable evidence payload (`grep '^V ' | sha256sum`).

fn det_sqrt(x: f64) -> f64 {
    // IEEE-754 correctly-rounded sqrt (hardware/std) — portable by the standard.
    x.sqrt()
}

fn compute(name: &str, x: f64) -> f64 {
    match name {
        "det_sin" => libm::sin(x),
        "det_cos" => libm::cos(x),
        "det_tan" => libm::tan(x),
        "det_ln" => libm::log(x),
        "det_exp" => libm::exp(x),
        "det_sqrt" => det_sqrt(x),
        other => panic!("unknown fn {other}"),
    }
}

fn main() {
    // (fn, input, expected f64 bits) — golden vectors copied verbatim from the VM test. The first ten are
    // the non-trivial bit literals; the last four are the exact-value cases (sqrt(4)=2, ln(1)=0, exp(0)=1,
    // tan(0)=0) expressed as their exact bit patterns.
    let checks: [(&str, f64, u64); 14] = [
        ("det_sin", 0.5, 0x3fdeaee8744b05f0),
        ("det_cos", 0.5, 0x3fec1528065b7d50),
        ("det_sin", 1.0, 0x3feaed548f090cee),
        ("det_sqrt", 2.0, 0x3ff6a09e667f3bcd),
        ("det_ln", 2.0, 0x3fe62e42fefa39ef),
        ("det_exp", 1.0, 0x4005bf0a8b14576a),
        ("det_exp", -1.0, 0x3fd78b56362cef38),
        ("det_tan", 0.5, 0x3fe17b4f5bf3474a),
        ("det_tan", 1.0, 0x3ff8eb245cbee3a6),
        ("det_tan", 1.4708, 0x4023ef1c536b2da2),
        ("det_sqrt", 4.0, 0x4000000000000000), // 2.0
        ("det_ln", 1.0, 0x0000000000000000),   // +0.0
        ("det_exp", 0.0, 0x3ff0000000000000),  // 1.0
        ("det_tan", 0.0, 0x0000000000000000),  // +0.0
    ];

    let mut all_match = true;
    for (name, x, want) in checks.iter() {
        let got = compute(name, *x);
        let gb = got.to_bits();
        let ok = gb == *want;
        all_match &= ok;
        // Hashable evidence line: fn, input-as-bits (exact), result-as-bits, expected-as-bits.
        println!(
            "V {name} in={:#018x} out={gb:#018x} want={want:#018x} {}",
            x.to_bits(),
            if ok { "OK" } else { "MISMATCH" }
        );
    }
    println!("# arch={} ptr_width={}", std::env::consts::ARCH, usize::BITS);
    println!("# libm=0.2.16 sqrt=ieee754");
    println!("ALL_MATCH={all_match}");
    std::process::exit(if all_match { 0 } else { 1 });
}
