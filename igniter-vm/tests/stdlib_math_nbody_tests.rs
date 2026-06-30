// LAB-STDLIB-MATH-NBODY-SWEEP-P11
//
// Scientific pressure proof: compute a Kuramoto-style order parameter over a Collection[Float] of phases,
// through the REAL compiler (`igniter_vm::compiler::Compiler`) + VM (`VM::execute`) — not hand-built
// bytecode. Builds on P5 (deterministic `det_sin/det_cos/det_sqrt`) and P10 (Tier-1 math inside HOF/lambda
// bodies). The order parameter is
//
//     r = (1/N) * sqrt( (Σ cos θ_j)^2 + (Σ sin θ_j)^2 )
//
// N is a fixed Float literal (no Integer→Float cast / numeric tower opened here, per card scope).
// Primary proof uses the deterministic `det_*` surface; a fast-surface case is a secondary check.

use igniter_vm::compiler::Compiler;
use igniter_vm::value::Value;
use igniter_vm::vm::VM;
use serde_json::json;
use std::collections::HashMap;

fn lit(v: f64) -> serde_json::Value {
    json!({ "kind": "literal", "type_tag": "Float", "value": v })
}
fn ref_(name: &str) -> serde_json::Value {
    json!({ "kind": "ref", "name": name })
}
fn call(fn_name: &str, args: Vec<serde_json::Value>) -> serde_json::Value {
    json!({ "kind": "call", "fn": fn_name, "args": args })
}
fn binop(op: &str, l: serde_json::Value, r: serde_json::Value) -> serde_json::Value {
    json!({ "kind": "binary_op", "op": op, "left": l, "right": r })
}
fn float_arr(vals: &[f64]) -> serde_json::Value {
    let items: Vec<_> = vals.iter().map(|v| lit(*v)).collect();
    json!({ "kind": "array_literal", "items": items })
}

/// `fold(vals, 0.0, (acc, theta) -> acc + <fn>(theta))` as a nestable sub-expression node.
fn fold_sum_node(vals: &[f64], call_name: &str) -> serde_json::Value {
    json!({
        "kind": "map_reduce_aggregate",
        "source": float_arr(vals),
        "pipeline": [{
            "kind": "fold",
            "param_acc": "acc",
            "param_val": "theta",
            "init": lit(0.0),
            "body": binop("+", ref_("acc"), call(call_name, vec![ref_("theta")]))
        }]
    })
}

/// Full order-parameter contract: r = sqrt((Σcos)^2 + (Σsin)^2) / N, with the two folds nested as
/// sub-expressions (each fold evaluated where referenced — deterministic, just recomputed).
fn order_param_contract(
    vals: &[f64],
    n: f64,
    cos_fn: &str,
    sin_fn: &str,
    sqrt_fn: &str,
) -> serde_json::Value {
    let sc = fold_sum_node(vals, cos_fn);
    let ss = fold_sum_node(vals, sin_fn);
    let mag2 = binop("+", binop("*", sc.clone(), sc), binop("*", ss.clone(), ss));
    let r = binop("/", call(sqrt_fn, vec![mag2]), lit(n));
    json!({ "contract_id": "NBodyOrder", "inputs": [], "expression": r })
}

async fn run(contract: serde_json::Value) -> Result<Value, String> {
    let mut c = Compiler::new();
    let bc = c.compile(&contract)?;
    VM::new(None)
        .execute(&bc, &HashMap::new(), &HashMap::new())
        .await
}
fn as_f64(r: Result<Value, String>) -> f64 {
    match r {
        Ok(Value::Float(x)) => x,
        other => panic!("expected Float, got {other:?}"),
    }
}

const FRAC_PI_2: f64 = std::f64::consts::FRAC_PI_2;
const PI: f64 = std::f64::consts::PI;
const FRAC_3PI_2: f64 = 3.0 * std::f64::consts::FRAC_PI_2;

// ── building-block anchors (top-level fold; guaranteed by P10) — isolate any nesting blocker ─────────

#[tokio::test]
async fn sum_cos_and_sum_sin_via_fold() {
    // [0, π/2, π]: Σcos = 1 + 0 − 1 = 0 ; Σsin = 0 + 1 + 0 = 1
    let sc = as_f64(
        run(json!({
            "contract_id": "SumCos", "inputs": [],
            "expression": fold_sum_node(&[0.0, FRAC_PI_2, PI], "det_cos")
        }))
        .await,
    );
    let ss = as_f64(
        run(json!({
            "contract_id": "SumSin", "inputs": [],
            "expression": fold_sum_node(&[0.0, FRAC_PI_2, PI], "det_sin")
        }))
        .await,
    );
    assert!(sc.abs() < 1e-9, "Σcos[0,π/2,π] ≈ 0, got {sc}");
    assert!((ss - 1.0).abs() < 1e-9, "Σsin[0,π/2,π] ≈ 1, got {ss}");
}

// ── the order-parameter proof (nested folds + det_sqrt + division), deterministic det_* surface ──────

#[tokio::test]
async fn order_param_synchronized_is_one() {
    // [0,0,0], N=3: Σcos=3, Σsin=0 → r = sqrt(9)/3 = 1.0 exactly (det_sqrt(9)=3 on a perfect square).
    let r = as_f64(
        run(order_param_contract(
            &[0.0, 0.0, 0.0],
            3.0,
            "det_cos",
            "det_sin",
            "det_sqrt",
        ))
        .await,
    );
    assert!(
        (r - 1.0).abs() < 1e-12,
        "synchronized order parameter = 1.0, got {r}"
    );
}

#[tokio::test]
async fn order_param_p9_sample_is_one_third() {
    // [0, π/2, π], N=3: Σcos≈0, Σsin≈1 → r = sqrt(0+1)/3 = 1/3.
    let r = as_f64(
        run(order_param_contract(
            &[0.0, FRAC_PI_2, PI],
            3.0,
            "det_cos",
            "det_sin",
            "det_sqrt",
        ))
        .await,
    );
    assert!(
        (r - 1.0 / 3.0).abs() < 1e-9,
        "P9 sample order parameter ≈ 1/3, got {r}"
    );
}

#[tokio::test]
async fn order_param_quarter_spread_is_zero() {
    // [0, π/2, π, 3π/2], N=4: Σcos≈0, Σsin≈0 → r ≈ 0.
    let r = as_f64(
        run(order_param_contract(
            &[0.0, FRAC_PI_2, PI, FRAC_3PI_2],
            4.0,
            "det_cos",
            "det_sin",
            "det_sqrt",
        ))
        .await,
    );
    assert!(
        r.abs() < 1e-9,
        "quarter-spread order parameter ≈ 0, got {r}"
    );
}

// ── secondary check: the fast (non-deterministic) surface yields the same physics within tolerance ───

#[tokio::test]
async fn order_param_fast_surface_matches() {
    let r = as_f64(
        run(order_param_contract(
            &[0.0, FRAC_PI_2, PI],
            3.0,
            "cos",
            "sin",
            "sqrt",
        ))
        .await,
    );
    assert!(
        (r - 1.0 / 3.0).abs() < 1e-9,
        "fast-surface order parameter ≈ 1/3, got {r}"
    );
}
