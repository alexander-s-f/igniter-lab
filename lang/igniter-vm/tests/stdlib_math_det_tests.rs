// LAB-STDLIB-MATH-DET-TIER1-P5
//
// Deterministic Tier-1 transcendentals (`det_sin/det_cos/det_sqrt`). Unlike the fast P2 path, these are
// **replay-safe**: det_sin/det_cos use the vendored pure-Rust `libm` (one fixed algorithm on every target);
// det_sqrt uses IEEE-754-correct std `f64::sqrt`. They NEVER emit NaN/Inf (non-finite → JSON null in the
// observation stream) — a non-finite input or a negative det_sqrt is a deterministic runtime error.
//
// GOLDEN VECTORS: we pin exact f64 bit patterns. Same input → these exact bits, every run. The cross-arch
// determinism CLAIM (same bits on aarch64/riscv64) rests on pure-Rust libm + Rust not auto-contracting FMA;
// these literals are the reference a cross-arch (qemu) CI would confirm. A libm-algorithm change flips the
// bits → the test fails → forcing a governed STDLIB_VERSION bump.

use igniter_vm::instructions::*;
use igniter_vm::value::Value;
use igniter_vm::vm::VM;
use std::collections::HashMap;
use std::sync::Arc;

fn lit(x: f64) -> Instruction {
    Instruction::new(OP_PUSH_LIT, vec![Value::Float(x)])
}
fn call(name: &str, argc: i64) -> Instruction {
    Instruction::new(
        OP_CALL,
        vec![Value::String(Arc::from(name)), Value::Integer(argc)],
    )
}
async fn run(instr: Vec<Instruction>) -> Result<Value, String> {
    VM::new(None)
        .execute(&instr, &HashMap::new(), &HashMap::new())
        .await
}
async fn det1(name: &str, x: f64) -> Result<Value, String> {
    run(vec![
        lit(x),
        call(name, 1),
        Instruction::new(OP_RET, vec![]),
    ])
    .await
}
fn bits(v: &Value) -> u64 {
    match v {
        Value::Float(f) => f.to_bits(),
        other => panic!("expected Float, got {other:?}"),
    }
}

/// Golden vectors: the deterministic surface produces these EXACT bit patterns.
#[tokio::test]
async fn golden_vectors_exact_bits() {
    assert_eq!(
        bits(&det1("det_sin", 0.5).await.unwrap()),
        0x3fdeaee8744b05f0,
        "det_sin(0.5)"
    );
    assert_eq!(
        bits(&det1("det_cos", 0.5).await.unwrap()),
        0x3fec1528065b7d50,
        "det_cos(0.5)"
    );
    assert_eq!(
        bits(&det1("det_sin", 1.0).await.unwrap()),
        0x3feaed548f090cee,
        "det_sin(1.0)"
    );
    // det_sqrt is IEEE-correct: sqrt(2) is the canonical correctly-rounded double.
    assert_eq!(
        bits(&det1("det_sqrt", 2.0).await.unwrap()),
        0x3ff6a09e667f3bcd,
        "det_sqrt(2.0)"
    );
    // det_sqrt of a perfect square is exact.
    assert_eq!(det1("det_sqrt", 4.0).await.unwrap(), Value::Float(2.0));
    // LAB-STDLIB-MATH-DET-TIER2: ln/exp golden vectors (vendored libm; the cross-arch reference).
    assert_eq!(
        bits(&det1("det_ln", 2.0).await.unwrap()),
        0x3fe62e42fefa39ef,
        "det_ln(2.0)"
    );
    // ln(1) is exactly 0.
    assert_eq!(det1("det_ln", 1.0).await.unwrap(), Value::Float(0.0));
    assert_eq!(
        bits(&det1("det_exp", 1.0).await.unwrap()),
        0x4005bf0a8b14576a,
        "det_exp(1.0)"
    );
    // exp(0) is exactly 1.
    assert_eq!(det1("det_exp", 0.0).await.unwrap(), Value::Float(1.0));
    assert_eq!(
        bits(&det1("det_exp", -1.0).await.unwrap()),
        0x3fd78b56362cef38,
        "det_exp(-1.0)"
    );
}

/// LAB-STDLIB-MATH-DET-TIER2: det_ln/det_exp are total over finite values — domain & overflow are
/// deterministic ERRORS, never NaN/Inf.
#[tokio::test]
async fn det_ln_exp_totality() {
    // ln domain: x must be > 0.
    let z = det1("det_ln", 0.0).await;
    assert!(z.is_err() && z.unwrap_err().contains("domain"), "det_ln(0) domain error");
    let n = det1("det_ln", -1.0).await;
    assert!(n.is_err() && n.unwrap_err().contains("domain"), "det_ln(-1) domain error");
    // exp overflow: exp(710) is +Inf in f64 → must error, not emit Inf.
    let o = det1("det_exp", 710.0).await;
    assert!(o.is_err() && o.unwrap_err().contains("overflow"), "det_exp(710) overflow error");
    // non-finite inputs refused.
    assert!(det1("det_ln", f64::INFINITY).await.is_err(), "det_ln(Inf) errors");
    assert!(det1("det_exp", f64::NAN).await.is_err(), "det_exp(NaN) errors");
    // exp of large-negative underflows to exactly 0.0 (finite) — allowed.
    assert_eq!(det1("det_exp", -1000.0).await.unwrap(), Value::Float(0.0));
}

/// Determinism: the same input yields byte-identical bits across repeated runs.
#[tokio::test]
async fn repeatable_across_runs() {
    let a = bits(&det1("det_sin", 0.5).await.unwrap());
    let b = bits(&det1("det_sin", 0.5).await.unwrap());
    assert_eq!(a, b, "det_sin must be bit-identical run-to-run");
}

/// Correctness: det values match std within a tight tolerance (libm is ~1 ULP).
#[tokio::test]
async fn det_values_are_correct() {
    let approx = |v: &Value, exact: f64| {
        (bits(v) ^ exact.to_bits()).count_ones() == 0 || {
            if let Value::Float(f) = v {
                (f - exact).abs() < 1e-15
            } else {
                false
            }
        }
    };
    assert!(
        approx(&det1("det_sin", 0.0).await.unwrap(), 0.0),
        "det_sin(0)=0"
    );
    assert!(
        approx(&det1("det_cos", 0.0).await.unwrap(), 1.0),
        "det_cos(0)=1"
    );
    assert!(
        approx(&det1("det_sqrt", 9.0).await.unwrap(), 3.0),
        "det_sqrt(9)=3"
    );
}

/// Never NaN/Inf: a negative det_sqrt is a deterministic ERROR, not a silent NaN/null.
#[tokio::test]
async fn negative_sqrt_is_error_not_nan() {
    let r = det1("det_sqrt", -1.0).await;
    assert!(r.is_err(), "det_sqrt(-1) must error, got {r:?}");
    assert!(r.unwrap_err().contains("domain"), "domain error message");
}

/// Non-finite input is refused deterministically (NaN/Inf would collapse to JSON null downstream).
#[tokio::test]
async fn non_finite_input_is_error() {
    assert!(
        det1("det_sin", f64::NAN).await.is_err(),
        "det_sin(NaN) must error"
    );
    assert!(
        det1("det_cos", f64::INFINITY).await.is_err(),
        "det_cos(Inf) must error"
    );
    assert!(
        det1("det_sqrt", f64::INFINITY).await.is_err(),
        "det_sqrt(Inf) must error"
    );
}

/// Arity + non-Float rejected (defensive — the typechecker rejects earlier).
#[tokio::test]
async fn arity_and_type_errors() {
    assert!(run(vec![
        lit(1.0),
        lit(2.0),
        call("det_sin", 2),
        Instruction::new(OP_RET, vec![])
    ])
    .await
    .is_err());
    assert!(
        run(vec![
            Instruction::new(OP_PUSH_LIT, vec![Value::Integer(4)]),
            call("det_sqrt", 1),
            Instruction::new(OP_RET, vec![]),
        ])
        .await
        .is_err(),
        "det_sqrt(Integer) must error (no coercion)"
    );
}
