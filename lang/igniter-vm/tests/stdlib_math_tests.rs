// LAB-STDLIB-MATH-TRANSCENDENTALS-P2
//
// Numeric proof for the Tier-1 Float transcendentals (`sin/cos/sqrt/pi`) wired into the VM's function-call
// dispatch. `igniter-vm trace` reports execution but not the returned value, so we exercise the dispatch
// directly via `VM::execute` with hand-built OP_CALL bytecode and assert the f64 result within tolerance.
//
// Tolerance (not bit-equality): the fast path uses platform `f64` intrinsics, so we assert |got - exact| <
// 1e-12 for these exact-representable / well-conditioned points. Cross-architecture bit-identity is a
// SEPARATE concern (the deterministic `det.*` track), explicitly out of scope here.

use igniter_vm::instructions::*;
use igniter_vm::value::Value;
use igniter_vm::vm::VM;
use std::collections::HashMap;
use std::sync::Arc;

const TOL: f64 = 1e-12;

fn lit(x: f64) -> Instruction {
    Instruction::new(OP_PUSH_LIT, vec![Value::Float(x)])
}
fn call(name: &str, argc: i64) -> Instruction {
    Instruction::new(OP_CALL, vec![Value::String(Arc::from(name)), Value::Integer(argc)])
}

async fn run(instr: Vec<Instruction>) -> Result<Value, String> {
    let vm = VM::new(None);
    vm.execute(&instr, &HashMap::new(), &HashMap::new()).await
}

async fn call1(name: &str, x: f64) -> f64 {
    match run(vec![lit(x), call(name, 1), Instruction::new(OP_RET, vec![])]).await {
        Ok(Value::Float(v)) => v,
        other => panic!("{name}({x}) expected Float, got {other:?}"),
    }
}

#[tokio::test]
async fn sin_cos_sqrt_known_values() {
    assert!((call1("sin", 0.0).await - 0.0).abs() < TOL, "sin(0)=0");
    assert!((call1("sin", std::f64::consts::FRAC_PI_2).await - 1.0).abs() < TOL, "sin(pi/2)=1");
    assert!((call1("cos", 0.0).await - 1.0).abs() < TOL, "cos(0)=1");
    assert!((call1("sqrt", 4.0).await - 2.0).abs() < TOL, "sqrt(4)=2");
    assert!((call1("sqrt", 2.0).await - std::f64::consts::SQRT_2).abs() < TOL, "sqrt(2)");
}

#[tokio::test]
async fn pi_is_a_zero_arg_constant() {
    let v = run(vec![call("pi", 0), Instruction::new(OP_RET, vec![])]).await.unwrap();
    match v {
        Value::Float(p) => assert!((p - std::f64::consts::PI).abs() < TOL, "pi()=π, got {p}"),
        other => panic!("pi() expected Float, got {other:?}"),
    }
}

/// The qualified name `stdlib.math.sqrt` dispatches identically to the bare `sqrt`.
#[tokio::test]
async fn qualified_name_dispatches() {
    let v = run(vec![lit(9.0), call("stdlib.math.sqrt", 1), Instruction::new(OP_RET, vec![])])
        .await
        .unwrap();
    assert_eq!(v, Value::Float(3.0));
}

/// Wrong arity is a runtime error (defensive — the typechecker rejects it earlier).
#[tokio::test]
async fn wrong_arity_errors() {
    let two_arg = run(vec![lit(1.0), lit(2.0), call("sqrt", 2), Instruction::new(OP_RET, vec![])]).await;
    assert!(two_arg.is_err(), "sqrt/2 must error");
    let pi_with_arg = run(vec![lit(1.0), call("pi", 1), Instruction::new(OP_RET, vec![])]).await;
    assert!(pi_with_arg.is_err(), "pi/1 must error");
}

/// A non-Float argument is rejected (no implicit Integer→Float coercion, the P2 bias).
#[tokio::test]
async fn non_float_argument_errors() {
    let int_arg = run(vec![
        Instruction::new(OP_PUSH_LIT, vec![Value::Integer(4)]),
        call("sqrt", 1),
        Instruction::new(OP_RET, vec![]),
    ])
    .await;
    assert!(int_arg.is_err(), "sqrt(Integer) must error (no implicit coercion)");
}
