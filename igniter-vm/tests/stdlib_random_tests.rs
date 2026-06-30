// LAB-STDLIB-RANDOM-PRNG-WITHOUT-BITOPS-P2
//
// Pure deterministic SplitMix64 PRNG, scalar state-threaded surface, NO language bitops, NO record returns.
// Tested through the shared single source (`eval_math_call`, used by both OP_CALL and the eval_ast/HOF path,
// P10) and through the real compiler→VM (`Compiler`→`VM::execute`) to confirm dispatch parity.

use igniter_vm::compiler::Compiler;
use igniter_vm::value::Value;
use igniter_vm::vm::{eval_math_call, VM};
use serde_json::json;
use std::collections::HashMap;

fn rng_call(name: &str, state: i64) -> i64 {
    match eval_math_call(name, &[Value::Integer(state)])
        .unwrap()
        .unwrap()
    {
        Value::Integer(i) => i,
        other => panic!("{name} expected Integer, got {other:?}"),
    }
}
fn uniform01(state: i64) -> f64 {
    match eval_math_call("rng_uniform01", &[Value::Integer(state)])
        .unwrap()
        .unwrap()
    {
        Value::Float(x) => x,
        other => panic!("rng_uniform01 expected Float, got {other:?}"),
    }
}
fn uniform_int(lo: i64, hi: i64, state: i64) -> i64 {
    match eval_math_call(
        "rng_uniform_int",
        &[
            Value::Integer(lo),
            Value::Integer(hi),
            Value::Integer(state),
        ],
    )
    .unwrap()
    .unwrap()
    {
        Value::Integer(i) => i,
        other => panic!("rng_uniform_int expected Integer, got {other:?}"),
    }
}
fn bernoulli_per_million(p: i64, state: i64) -> bool {
    match eval_math_call(
        "rng_bernoulli_per_million",
        &[Value::Integer(p), Value::Integer(state)],
    )
    .unwrap()
    .unwrap()
    {
        Value::Bool(b) => b,
        other => panic!("rng_bernoulli_per_million expected Bool, got {other:?}"),
    }
}

/// Thread the seed through `rng_next`, reading `rng_value` off each state — the canonical SplitMix64 stream.
fn seq(seed: i64, n: usize) -> Vec<i64> {
    let mut s = rng_call("rng_seed", seed);
    (0..n)
        .map(|_| {
            s = rng_call("rng_next", s);
            rng_call("rng_value", s)
        })
        .collect()
}
fn states(seed: i64, n: usize) -> Vec<i64> {
    let mut s = rng_call("rng_seed", seed);
    (0..n)
        .map(|_| {
            s = rng_call("rng_next", s);
            s
        })
        .collect()
}

/// GOLDEN: the first 5 samples for seed 0 are pinned (locks the algorithm + constants). The first u64 is the
/// canonical SplitMix64 seed-0 output `0xE220A8397B1DCDAF`, confirming this is reference SplitMix64.
#[test]
fn seed0_golden_sequence() {
    let got = seq(0, 5);
    let golden: [i64; 5] = [
        -2152535657050944081, // 0xE220A8397B1DCDAF — canonical SplitMix64 first output
        7960286522194355700,
        487617019471545679,
        -537132696929009172,
        1961750202426094747,
    ];
    assert_eq!(got, golden, "SplitMix64 seed-0 golden stream");
    assert_eq!(
        (got[0] as u64),
        0xE220_A839_7B1D_CDAF,
        "first sample is canonical SplitMix64(seed=0)"
    );
}

/// Same seed → identical sequence (replay-safe).
#[test]
fn same_seed_identical_sequence() {
    assert_eq!(seq(42, 8), seq(42, 8));
}

/// Different seeds → different first output (small sanity).
#[test]
fn different_seeds_differ() {
    assert_ne!(seq(1, 1)[0], seq(2, 1)[0]);
    assert_ne!(seq(0, 1)[0], seq(123456789, 1)[0]);
}

/// `rng_uniform01` stays in [0,1), is deterministic, and is finite.
#[test]
fn uniform01_in_unit_interval_and_deterministic() {
    let mut s = rng_call("rng_seed", 7);
    for _ in 0..32 {
        s = rng_call("rng_next", s);
        let u = uniform01(s);
        assert!(
            (0.0..1.0).contains(&u) && u.is_finite(),
            "uniform01 ∈ [0,1) finite, got {u}"
        );
        assert_eq!(u, uniform01(s), "uniform01 deterministic for a fixed state");
    }
}

/// `rng_uniform_int` samples a fixed explicit state; callers advance state with `rng_next`.
#[test]
fn uniform_int_seed0_golden_and_bounds() {
    let got: Vec<i64> = states(0, 5)
        .into_iter()
        .map(|s| uniform_int(10, 19, s))
        .collect();
    assert_eq!(got, vec![18, 14, 10, 19, 11]);
    assert!(got.iter().all(|v| (10..=19).contains(v)));

    let fixed = states(123, 1)[0];
    assert_eq!(uniform_int(7, 7, fixed), 7, "single-value range");
    assert_eq!(
        uniform_int(i64::MIN, i64::MAX, states(0, 1)[0]),
        7070836379803831727,
        "full i64 range stays deterministic"
    );
}

/// Bernoulli uses an exact integer probability scale: p_per_million ∈ [0, 1_000_000].
#[test]
fn bernoulli_per_million_seed0_golden_and_bounds() {
    let got: Vec<bool> = states(0, 5)
        .into_iter()
        .map(|s| bernoulli_per_million(500_000, s))
        .collect();
    assert_eq!(got, vec![false, true, true, false, true]);

    for s in states(9, 8) {
        assert!(!bernoulli_per_million(0, s), "p=0 is always false");
        assert!(
            bernoulli_per_million(1_000_000, s),
            "p=1_000_000 is always true"
        );
    }
}

/// Wrong arity / non-Integer argument are deterministic errors (not panics, not silent).
#[test]
fn arity_and_type_errors() {
    assert!(
        eval_math_call("rng_next", &[]).unwrap().is_err(),
        "0-arg rng_next errors"
    );
    assert!(
        eval_math_call("rng_next", &[Value::Integer(1), Value::Integer(2)])
            .unwrap()
            .is_err(),
        "2-arg rng_next errors"
    );
    assert!(
        eval_math_call("rng_value", &[Value::Float(1.0)])
            .unwrap()
            .is_err(),
        "non-Integer rng_value errors"
    );
    // not an rng/math fn → None (caller falls through)
    assert!(eval_math_call("rng_bogus", &[]).is_none());
}

#[test]
fn distribution_domain_and_type_errors() {
    assert!(
        eval_math_call(
            "rng_uniform_int",
            &[Value::Integer(2), Value::Integer(1), Value::Integer(0)]
        )
        .unwrap()
        .is_err(),
        "lo > hi errors"
    );
    assert!(
        eval_math_call("rng_uniform_int", &[Value::Integer(1), Value::Integer(2)])
            .unwrap()
            .is_err(),
        "wrong arity errors"
    );
    assert!(
        eval_math_call(
            "rng_uniform_int",
            &[Value::Integer(1), Value::Integer(2), Value::Float(0.0)]
        )
        .unwrap()
        .is_err(),
        "non-Integer state errors"
    );
    assert!(
        eval_math_call(
            "rng_bernoulli_per_million",
            &[Value::Integer(-1), Value::Integer(0)]
        )
        .unwrap()
        .is_err(),
        "negative probability errors"
    );
    assert!(
        eval_math_call(
            "rng_bernoulli_per_million",
            &[Value::Integer(1_000_001), Value::Integer(0)]
        )
        .unwrap()
        .is_err(),
        "probability above scale errors"
    );
    assert!(
        eval_math_call(
            "rng_bernoulli_per_million",
            &[Value::Integer(500_000), Value::Float(0.0)]
        )
        .unwrap()
        .is_err(),
        "non-Integer state errors"
    );
}

// ── OP_CALL + eval_ast parity: run through the real compiler→VM (not just eval_math_call directly) ────────

async fn run(contract: serde_json::Value) -> Result<Value, String> {
    let mut c = Compiler::new();
    let bc = c.compile(&contract)?;
    VM::new(None)
        .execute(&bc, &HashMap::new(), &HashMap::new())
        .await
}
fn lit_int(v: i64) -> serde_json::Value {
    json!({ "kind": "literal", "type_tag": "Integer", "value": v })
}
fn call(fn_name: &str, args: Vec<serde_json::Value>) -> serde_json::Value {
    json!({ "kind": "call", "fn": fn_name, "args": args })
}

/// `rng_value(rng_next(rng_seed(0)))` composed as a nested expression, compiled + executed through the VM,
/// equals the first golden sample — proving the PRNG dispatches identically on the real bytecode path.
#[tokio::test]
async fn first_sample_through_compiler_vm() {
    let expr = call(
        "rng_value",
        vec![call("rng_next", vec![call("rng_seed", vec![lit_int(0)])])],
    );
    let contract = json!({ "contract_id": "RngFirst", "inputs": [], "expression": expr });
    let r = run(contract).await.expect("compile+run");
    assert_eq!(
        r,
        Value::Integer(-2152535657050944081),
        "first sample via compiler→VM matches golden"
    );
}

/// Distribution helpers also compile and execute through nested OP_CALL bytecode, not only direct Rust tests.
#[tokio::test]
async fn distributions_through_compiler_vm() {
    let state = call("rng_next", vec![call("rng_seed", vec![lit_int(0)])]);
    let int_expr = call(
        "rng_uniform_int",
        vec![lit_int(10), lit_int(19), state.clone()],
    );
    let int_contract =
        json!({ "contract_id": "RngUniformInt", "inputs": [], "expression": int_expr });
    assert_eq!(
        run(int_contract).await.expect("uniform int compile+run"),
        Value::Integer(18)
    );

    let bool_expr = call("rng_bernoulli_per_million", vec![lit_int(500_000), state]);
    let bool_contract =
        json!({ "contract_id": "RngBernoulli", "inputs": [], "expression": bool_expr });
    assert_eq!(
        run(bool_contract).await.expect("bernoulli compile+run"),
        Value::Bool(false)
    );
}
