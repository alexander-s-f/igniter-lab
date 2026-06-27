// tests/vm_tests.rs
// Premium, comprehensive integration and concurrency verification suite for igniter-vm

#![allow(dead_code)]

use igniter_vm::instructions::*;
use igniter_vm::tbackend::MemoryHistoryBackend;
use igniter_vm::value::Value;
use igniter_vm::vm::VM;
use std::collections::HashMap;
use std::sync::Arc;
use tokio::task;

// Helper to create instructions easily
fn push_lit(v: Value) -> Instruction {
    Instruction::new(OP_PUSH_LIT, vec![v])
}

fn load_ref(name: &str) -> Instruction {
    Instruction::new(OP_LOAD_REF, vec![Value::String(Arc::from(name))])
}

fn store_reg(idx: i64) -> Instruction {
    Instruction::new(OP_STORE_REG, vec![Value::Integer(idx)])
}

fn load_reg(idx: i64) -> Instruction {
    Instruction::new(OP_LOAD_REG, vec![Value::Integer(idx)])
}

fn op_add() -> Instruction {
    Instruction::new(OP_ADD, vec![])
}

fn op_sub() -> Instruction {
    Instruction::new(OP_SUB, vec![])
}

fn op_mul() -> Instruction {
    Instruction::new(OP_MUL, vec![])
}

fn op_div() -> Instruction {
    Instruction::new(OP_DIV, vec![])
}

fn op_neg() -> Instruction {
    Instruction::new(OP_NEG, vec![])
}

fn op_ret() -> Instruction {
    Instruction::new(OP_RET, vec![])
}

async fn run_bytecode(instructions: Vec<Instruction>) -> Result<Value, String> {
    VM::new(None)
        .execute(&instructions, &HashMap::new(), &HashMap::new())
        .await
}

fn assert_err_contains(result: Result<Value, String>, expected: &str) {
    match result {
        Err(err) => assert!(
            err.contains(expected),
            "expected error containing '{expected}', got '{err}'"
        ),
        Ok(value) => panic!("expected error containing '{expected}', got value {value:?}"),
    }
}

#[tokio::test]
async fn checked_integer_arithmetic_errors_in_bytecode_path() {
    assert_err_contains(
        run_bytecode(vec![
            push_lit(Value::Integer(i64::MAX)),
            push_lit(Value::Integer(1)),
            op_add(),
            op_ret(),
        ])
        .await,
        "Integer overflow",
    );
    assert_err_contains(
        run_bytecode(vec![
            push_lit(Value::Integer(i64::MIN)),
            push_lit(Value::Integer(1)),
            op_sub(),
            op_ret(),
        ])
        .await,
        "Integer overflow",
    );
    assert_err_contains(
        run_bytecode(vec![
            push_lit(Value::Integer(i64::MAX)),
            push_lit(Value::Integer(2)),
            op_mul(),
            op_ret(),
        ])
        .await,
        "Integer overflow",
    );
    assert_err_contains(
        run_bytecode(vec![
            push_lit(Value::Integer(i64::MIN)),
            push_lit(Value::Integer(-1)),
            op_div(),
            op_ret(),
        ])
        .await,
        "Integer overflow",
    );
    assert_err_contains(
        run_bytecode(vec![
            push_lit(Value::Integer(i64::MIN)),
            op_neg(),
            op_ret(),
        ])
        .await,
        "Integer overflow",
    );
    assert_err_contains(
        run_bytecode(vec![
            push_lit(Value::Integer(1)),
            push_lit(Value::Integer(0)),
            op_div(),
            op_ret(),
        ])
        .await,
        "Division by zero",
    );

    assert_eq!(
        run_bytecode(vec![
            push_lit(Value::Integer(40)),
            push_lit(Value::Integer(2)),
            op_add(),
            op_ret(),
        ])
        .await,
        Ok(Value::Integer(42))
    );
    assert_eq!(
        run_bytecode(vec![
            push_lit(Value::Integer(-7)),
            op_neg(),
            op_ret(),
        ])
        .await,
        Ok(Value::Integer(7))
    );
}

#[tokio::test]
async fn test_decimal_addition_success() {
    let vm = VM::new(None);
    let instructions = vec![
        push_lit(Value::Decimal {
            value: 1050,
            scale: 2,
        }),
        push_lit(Value::Decimal {
            value: 2525,
            scale: 2,
        }),
        op_add(),
        op_ret(),
    ];

    let res = vm
        .execute(&instructions, &HashMap::new(), &HashMap::new())
        .await;
    assert_eq!(
        res,
        Ok(Value::Decimal {
            value: 3575,
            scale: 2
        })
    );
}

#[tokio::test]
async fn test_decimal_addition_scale_mismatch_error() {
    let vm = VM::new(None);
    let instructions = vec![
        push_lit(Value::Decimal {
            value: 1050,
            scale: 2,
        }),
        push_lit(Value::Decimal {
            value: 250,
            scale: 1,
        }),
        op_add(),
        op_ret(),
    ];

    let res = vm
        .execute(&instructions, &HashMap::new(), &HashMap::new())
        .await;
    assert!(res.is_err());
    assert!(res.unwrap_err().contains("OOF-TC5"));
}

#[tokio::test]
async fn test_decimal_subtraction_success() {
    let vm = VM::new(None);
    let instructions = vec![
        push_lit(Value::Decimal {
            value: 3575,
            scale: 2,
        }),
        push_lit(Value::Decimal {
            value: 1050,
            scale: 2,
        }),
        op_sub(),
        op_ret(),
    ];

    let res = vm
        .execute(&instructions, &HashMap::new(), &HashMap::new())
        .await;
    assert_eq!(
        res,
        Ok(Value::Decimal {
            value: 2525,
            scale: 2
        })
    );
}

#[tokio::test]
async fn test_decimal_subtraction_scale_mismatch_error() {
    let vm = VM::new(None);
    let instructions = vec![
        push_lit(Value::Decimal {
            value: 3575,
            scale: 2,
        }),
        push_lit(Value::Decimal {
            value: 250,
            scale: 1,
        }),
        op_sub(),
        op_ret(),
    ];

    let res = vm
        .execute(&instructions, &HashMap::new(), &HashMap::new())
        .await;
    assert!(res.is_err());
    assert!(res.unwrap_err().contains("OOF-TC5"));
}

#[tokio::test]
async fn test_decimal_multiplication_scale_summation() {
    let vm = VM::new(None);
    let instructions = vec![
        push_lit(Value::Decimal {
            value: 105,
            scale: 1,
        }),
        push_lit(Value::Decimal {
            value: 25,
            scale: 1,
        }),
        op_mul(),
        op_ret(),
    ];

    let res = vm
        .execute(&instructions, &HashMap::new(), &HashMap::new())
        .await;
    assert_eq!(
        res,
        Ok(Value::Decimal {
            value: 2625,
            scale: 2
        })
    );
}

#[tokio::test]
async fn test_decimal_division_scale_subtraction() {
    let vm = VM::new(None);
    let instructions = vec![
        push_lit(Value::Decimal {
            value: 2625,
            scale: 2,
        }),
        push_lit(Value::Decimal {
            value: 25,
            scale: 1,
        }),
        op_div(),
        op_ret(),
    ];

    let res = vm
        .execute(&instructions, &HashMap::new(), &HashMap::new())
        .await;
    assert_eq!(
        res,
        Ok(Value::Decimal {
            value: 105,
            scale: 1
        })
    );
}

#[tokio::test]
async fn test_decimal_division_by_zero_error() {
    let vm = VM::new(None);
    let instructions = vec![
        push_lit(Value::Decimal {
            value: 2625,
            scale: 2,
        }),
        push_lit(Value::Decimal { value: 0, scale: 1 }),
        op_div(),
        op_ret(),
    ];

    let res = vm
        .execute(&instructions, &HashMap::new(), &HashMap::new())
        .await;
    assert!(res.is_err());
    assert!(res.unwrap_err().contains("OOF-DM2"));
}

#[tokio::test]
async fn test_numeric_fallbacks() {
    let vm = VM::new(None);

    // Integers
    let instructions_int = vec![
        push_lit(Value::Integer(10)),
        push_lit(Value::Integer(20)),
        op_add(),
        op_ret(),
    ];
    assert_eq!(
        vm.execute(&instructions_int, &HashMap::new(), &HashMap::new())
            .await,
        Ok(Value::Integer(30))
    );

    // Floats
    let instructions_flt = vec![
        push_lit(Value::Float(1.5)),
        push_lit(Value::Float(2.5)),
        op_add(),
        op_ret(),
    ];
    assert_eq!(
        vm.execute(&instructions_flt, &HashMap::new(), &HashMap::new())
            .await,
        Ok(Value::Float(4.0))
    );
}

#[tokio::test]
async fn test_bitemporal_nonblocking_load_as_of() {
    let backend = Arc::new(MemoryHistoryBackend::new());
    backend
        .write_history("technician_jobs", "2026-05-01T00:00:00Z", Value::Integer(3))
        .await;
    backend
        .write_history("technician_jobs", "2026-05-15T00:00:00Z", Value::Integer(5))
        .await;

    let vm = VM::new(Some(backend.clone()));

    let instructions = vec![
        Instruction::new(
            OP_LOAD_AS_OF,
            vec![
                Value::String(Arc::from("technician_jobs")),
                Value::String(Arc::from("as_of")),
            ],
        ),
        op_ret(),
    ];

    // Case A: Query as of May 10th
    let mut inputs = HashMap::new();
    inputs.insert(
        "as_of".to_string(),
        Value::String(Arc::from("2026-05-10T12:00:00Z")),
    );
    let res_a = vm.execute(&instructions, &inputs, &HashMap::new()).await;
    assert_eq!(res_a, Ok(Value::Integer(3)));

    // Case B: Query as of May 20th
    let mut inputs_b = HashMap::new();
    inputs_b.insert(
        "as_of".to_string(),
        Value::String(Arc::from("2026-05-20T12:00:00Z")),
    );
    let res_b = vm.execute(&instructions, &inputs_b, &HashMap::new()).await;
    assert_eq!(res_b, Ok(Value::Integer(5)));

    // Check observation sink audit log
    let sink = vm.observation_sink.lock().await;
    assert_eq!(sink.len(), 2);
    assert_eq!(
        sink[0]["kind"].as_str(),
        Some("temporal_live_read_observation")
    );
    assert_eq!(sink[0]["store"].as_str(), Some("technician_jobs"));
    assert_eq!(sink[0]["result_present"].as_bool(), Some(true));
}

#[tokio::test]
async fn test_high_concurrency_stress() {
    let vm = Arc::new(VM::new(None));
    let instructions = Arc::new(vec![
        push_lit(Value::Decimal {
            value: 1000,
            scale: 2,
        }),
        push_lit(Value::Decimal {
            value: 2000,
            scale: 2,
        }),
        op_add(),
        op_ret(),
    ]);

    let mut handles = vec![];

    // Spawn 10 parallel threads concurrently evaluating the contract
    for _ in 0..10 {
        let vm_clone = vm.clone();
        let inst_clone = instructions.clone();
        handles.push(task::spawn(async move {
            vm_clone
                .execute(&inst_clone, &HashMap::new(), &HashMap::new())
                .await
        }));
    }

    for handle in handles {
        let result = handle.await.expect("Task failed");
        assert_eq!(
            result,
            Ok(Value::Decimal {
                value: 3000,
                scale: 2
            })
        );
    }
}

#[tokio::test]
async fn test_aot_compiler_lowering() {
    use igniter_vm::compiler::Compiler;

    let contract_json = serde_json::json!({
        "contract_id": "TechnicianBonusCalculator",
        "modifier": "irreversible",
        "inputs": ["technician_id", "as_of"],
        "expression": {
            "kind": "if_expr",
            "condition": {
                "kind": "binary_op",
                "operator": "==",
                "left": {
                    "kind": "temporal_read",
                    "store_ref": "technician_jobs",
                    "as_of_ref": "as_of"
                },
                "right": {
                    "kind": "literal",
                    "value": 5
                }
            },
            "then_branch": {
                "kind": "emit_observation",
                "observation_kind": "bonus_major_selected",
                "expression": {
                    "kind": "literal",
                    "value": 1000
                }
            },
            "else_branch": {
                "kind": "emit_observation",
                "observation_kind": "bonus_minor_selected",
                "expression": {
                    "kind": "literal",
                    "value": 200
                }
            }
        }
    });

    let mut compiler = Compiler::new();
    let bytecode = compiler
        .compile(&contract_json)
        .expect("Compilation failed");

    // Assert that the generated bytecode instructions length and structure are correct
    assert_eq!(bytecode.len(), 10);

    let backend = Arc::new(MemoryHistoryBackend::new());
    backend
        .write_history("technician_jobs", "2026-05-01T00:00:00Z", Value::Integer(3))
        .await;
    backend
        .write_history("technician_jobs", "2026-05-15T00:00:00Z", Value::Integer(5))
        .await;

    let vm = VM::new(Some(backend));

    // Scenario A: as_of May 10 -> Jobs count = 3 -> Else branch (returns 200)
    let mut inputs_a = HashMap::new();
    inputs_a.insert(
        "as_of".to_string(),
        Value::String(Arc::from("2026-05-10T12:00:00Z")),
    );
    let res_a = vm.execute(&bytecode, &inputs_a, &HashMap::new()).await;
    assert_eq!(res_a, Ok(Value::Integer(200)));

    // Scenario B: as_of May 20 -> Jobs count = 5 -> Then branch (returns 1000)
    let mut inputs_b = HashMap::new();
    inputs_b.insert(
        "as_of".to_string(),
        Value::String(Arc::from("2026-05-20T12:00:00Z")),
    );
    let res_b = vm.execute(&bytecode, &inputs_b, &HashMap::new()).await;
    assert_eq!(res_b, Ok(Value::Integer(1000)));
}

#[tokio::test]
async fn test_map_reduce_aggregate_optimizations() {
    use igniter_vm::compiler::Compiler;

    // Test Case 1: count(filter(range(1, 10), x > 5)) -> Expected: 4 (6, 7, 8, 9)
    let contract_count_json = serde_json::json!({
        "contract_id": "MapReduceCountTest",
        "inputs": [],
        "expression": {
            "kind": "map_reduce_aggregate",
            "source": {
                "kind": "range",
                "start": { "kind": "literal", "value": 1 },
                "end": { "kind": "literal", "value": 10 }
            },
            "pipeline": [
                {
                    "kind": "filter",
                    "param": "x",
                    "body": {
                        "kind": "binary_op",
                        "operator": ">",
                        "left": { "kind": "ref", "name": "x" },
                        "right": { "kind": "literal", "value": 5 }
                    }
                },
                {
                    "kind": "count"
                }
            ]
        }
    });

    let mut compiler = Compiler::new();
    let bytecode_count = compiler
        .compile(&contract_count_json)
        .expect("Compilation failed");
    assert_eq!(bytecode_count.len(), 2); // OP_MAP_REDUCE, OP_RET

    let vm = VM::new(None);
    let res_count = vm
        .execute(&bytecode_count, &HashMap::new(), &HashMap::new())
        .await;
    assert_eq!(res_count, Ok(Value::Integer(4)));

    // Test Case 2: fold(range(1, 6), 0, lambda acc, y: acc + y) -> Expected: 15 (1+2+3+4+5)
    let contract_fold_json = serde_json::json!({
        "contract_id": "MapReduceFoldTest",
        "inputs": [],
        "expression": {
            "kind": "map_reduce_aggregate",
            "source": {
                "kind": "range",
                "start": { "kind": "literal", "value": 1 },
                "end": { "kind": "literal", "value": 6 }
            },
            "pipeline": [
                {
                    "kind": "fold",
                    "param_acc": "acc",
                    "param_val": "y",
                    "init": { "kind": "literal", "value": 0 },
                    "body": {
                        "kind": "binary_op",
                        "operator": "+",
                        "left": { "kind": "ref", "name": "acc" },
                        "right": { "kind": "ref", "name": "y" }
                    }
                }
            ]
        }
    });

    let bytecode_fold = compiler
        .compile(&contract_fold_json)
        .expect("Compilation failed");
    let res_fold = vm
        .execute(&bytecode_fold, &HashMap::new(), &HashMap::new())
        .await;
    assert_eq!(res_fold, Ok(Value::Integer(15)));

    // Checked arithmetic also applies inside HOF lambda bodies, which use eval_ast.
    let contract_checked_fold_json = serde_json::json!({
        "contract_id": "MapReduceCheckedFoldTest",
        "inputs": [],
        "expression": {
            "kind": "map_reduce_aggregate",
            "source": {
                "kind": "array_literal",
                "items": [
                    { "kind": "literal", "value": 1 }
                ]
            },
            "pipeline": [
                {
                    "kind": "fold",
                    "param_acc": "acc",
                    "param_val": "y",
                    "init": { "kind": "literal", "value": i64::MAX },
                    "body": {
                        "kind": "binary_op",
                        "operator": "+",
                        "left": { "kind": "ref", "name": "acc" },
                        "right": { "kind": "ref", "name": "y" }
                    }
                }
            ]
        }
    });
    let bytecode_checked_fold = compiler
        .compile(&contract_checked_fold_json)
        .expect("Compilation failed");
    assert_err_contains(
        vm.execute(&bytecode_checked_fold, &HashMap::new(), &HashMap::new())
            .await,
        "Integer overflow",
    );

    // The eval_ast call/operator table is a separate dispatch surface from binary_op.
    let contract_checked_call_json = serde_json::json!({
        "contract_id": "MapReduceCheckedCallTest",
        "inputs": [],
        "expression": {
            "kind": "map_reduce_aggregate",
            "source": {
                "kind": "array_literal",
                "items": [
                    { "kind": "literal", "value": 1 }
                ]
            },
            "pipeline": [
                {
                    "kind": "fold",
                    "param_acc": "acc",
                    "param_val": "y",
                    "init": { "kind": "literal", "value": i64::MAX },
                    "body": {
                        "kind": "call",
                        "fn": "add",
                        "args": [
                            { "kind": "ref", "name": "acc" },
                            { "kind": "ref", "name": "y" }
                        ]
                    }
                }
            ]
        }
    });
    let bytecode_checked_call = compiler
        .compile(&contract_checked_call_json)
        .expect("Compilation failed");
    assert_err_contains(
        vm.execute(&bytecode_checked_call, &HashMap::new(), &HashMap::new())
            .await,
        "Integer overflow",
    );

    // Test Case 3: first(map(filter(range(1, 10), x > 5), x * 2)) -> Expected: 12 (first matches 6, 6 * 2 = 12)
    let contract_first_json = serde_json::json!({
        "contract_id": "MapReduceFirstTest",
        "inputs": [],
        "expression": {
            "kind": "map_reduce_aggregate",
            "source": {
                "kind": "range",
                "start": { "kind": "literal", "value": 1 },
                "end": { "kind": "literal", "value": 10 }
            },
            "pipeline": [
                {
                    "kind": "filter",
                    "param": "x",
                    "body": {
                        "kind": "binary_op",
                        "operator": ">",
                        "left": { "kind": "ref", "name": "x" },
                        "right": { "kind": "literal", "value": 5 }
                    }
                },
                {
                    "kind": "map",
                    "param": "x",
                    "body": {
                        "kind": "binary_op",
                        "operator": "*",
                        "left": { "kind": "ref", "name": "x" },
                        "right": { "kind": "literal", "value": 2 }
                    }
                },
                {
                    "kind": "first"
                }
            ]
        }
    });

    let bytecode_first = compiler
        .compile(&contract_first_json)
        .expect("Compilation failed");
    let res_first = vm
        .execute(&bytecode_first, &HashMap::new(), &HashMap::new())
        .await;
    assert_eq!(res_first, Ok(Value::Integer(12)));
}

#[tokio::test]
async fn test_path_splitting_load_as_of() {
    let backend = Arc::new(MemoryHistoryBackend::new());
    // Write directly to "technician" store
    backend
        .write_history(
            "technician",
            "2026-05-01T00:00:00Z",
            Value::String(Arc::from("tech42-data")),
        )
        .await;

    let vm = VM::new(Some(backend.clone()));

    let instructions = vec![
        Instruction::new(
            OP_LOAD_AS_OF,
            vec![
                Value::String(Arc::from("technician/tech42")),
                Value::String(Arc::from("as_of")),
            ],
        ),
        op_ret(),
    ];

    let mut inputs = HashMap::new();
    inputs.insert(
        "as_of".to_string(),
        Value::String(Arc::from("2026-05-10T12:00:00Z")),
    );
    let res = vm.execute(&instructions, &inputs, &HashMap::new()).await;
    // Should fallback to "technician" and retrieve "tech42-data"
    assert_eq!(res, Ok(Value::String(Arc::from("tech42-data"))));
}

#[tokio::test]
async fn test_new_opcodes_and_literals() {
    use igniter_vm::compiler::Compiler;

    // Test cases combining comparisons, logical, and array/record operations
    let contract_json = serde_json::json!({
        "contract_id": "NewOpcodesTest",
        "inputs": ["x", "y"],
        "expression": {
            "kind": "binary_op",
            "operator": "&&",
            "left": {
                "kind": "binary_op",
                "operator": "<",
                "left": { "kind": "ref", "name": "x" },
                "right": { "kind": "ref", "name": "y" }
            },
            "right": {
                "kind": "binary_op",
                "operator": "!=",
                "left": { "kind": "ref", "name": "x" },
                "right": { "kind": "literal", "value": 0 }
            }
        }
    });

    let mut compiler = Compiler::new();
    let bytecode = compiler
        .compile(&contract_json)
        .expect("Compilation failed");

    let vm = VM::new(None);

    // Case A: x = 5, y = 10 -> 5 < 10 && 5 != 0 -> true && true -> true
    let mut inputs = HashMap::new();
    inputs.insert("x".to_string(), Value::Integer(5));
    inputs.insert("y".to_string(), Value::Integer(10));
    let res = vm.execute(&bytecode, &inputs, &HashMap::new()).await;
    assert_eq!(res, Ok(Value::Bool(true)));

    // Case B: x = 15, y = 10 -> 15 < 10 && 15 != 0 -> false && true -> false
    let mut inputs = HashMap::new();
    inputs.insert("x".to_string(), Value::Integer(15));
    inputs.insert("y".to_string(), Value::Integer(10));
    let res = vm.execute(&bytecode, &inputs, &HashMap::new()).await;
    assert_eq!(res, Ok(Value::Bool(false)));

    // Case C: x = 0, y = 10 -> 0 < 10 && 0 != 0 -> true && false -> false
    let mut inputs = HashMap::new();
    inputs.insert("x".to_string(), Value::Integer(0));
    inputs.insert("y".to_string(), Value::Integer(10));
    let res = vm.execute(&bytecode, &inputs, &HashMap::new()).await;
    assert_eq!(res, Ok(Value::Bool(false)));
}

#[tokio::test]
async fn test_new_opcodes_array_record_unary_call() {
    use igniter_vm::compiler::Compiler;

    // Test array literal, record literal, and unary negation
    let contract_json = serde_json::json!({
        "contract_id": "ArrayRecordUnaryTest",
        "inputs": [],
        "expression": {
            "kind": "record_literal",
            "fields": {
                "flag": {
                    "kind": "unary_op",
                    "op": "!",
                    "operand": { "kind": "literal", "value": false }
                },
                "items": {
                    "kind": "array_literal",
                    "items": [
                        { "kind": "literal", "value": "hello" },
                        { "kind": "literal", "value": "world" }
                    ]
                }
            }
        }
    });

    let mut compiler = Compiler::new();
    let bytecode = compiler
        .compile(&contract_json)
        .expect("Compilation failed");

    let vm = VM::new(None);
    let res = vm
        .execute(&bytecode, &HashMap::new(), &HashMap::new())
        .await;

    // The output should be a record with keys "flag" and "items"
    let mut expected_map = std::collections::BTreeMap::new();
    expected_map.insert("flag".to_string(), Value::Bool(true));
    expected_map.insert(
        "items".to_string(),
        Value::Array(Arc::new(vec![
            Value::String(Arc::from("hello")),
            Value::String(Arc::from("world")),
        ])),
    );
    assert_eq!(res, Ok(Value::Record(Arc::new(expected_map))));
}

#[tokio::test]
async fn test_new_opcodes_concat_and_call() {
    use igniter_vm::compiler::Compiler;

    // Test string concatenation via ++ operator, and calling FFI wrapper/stdlib.option.wrap
    let contract_json = serde_json::json!({
        "contract_id": "ConcatCallTest",
        "inputs": [],
        "expression": {
            "kind": "call",
            "fn": "stdlib.option.wrap",
            "args": [
                {
                    "kind": "binary_op",
                    "operator": "++",
                    "left": { "kind": "literal", "value": "foo" },
                    "right": { "kind": "literal", "value": "bar" }
                }
            ]
        }
    });

    let mut compiler = Compiler::new();
    let bytecode = compiler
        .compile(&contract_json)
        .expect("Compilation failed");

    let vm = VM::new(None);
    let res = vm
        .execute(&bytecode, &HashMap::new(), &HashMap::new())
        .await;
    assert_eq!(res, Ok(Value::String(Arc::from("foobar"))));
}

#[tokio::test]
async fn test_category3_missing_kinds() {
    use igniter_vm::compiler::Compiler;

    // 1. Let binding with body, unary negation, concat, and record / array alternative kinds
    let contract_json = serde_json::json!({
        "contract_id": "Category3Test",
        "expression": {
            "kind": "let",
            "name": "my_val",
            "expr": {
                "kind": "unary",
                "op": "-",
                "operand": { "kind": "literal", "value": 42 }
            },
            "body": {
                "kind": "record",
                "fields": {
                    "negated": { "kind": "ref", "name": "my_val" },
                    "joined": {
                        "kind": "concat",
                        "left": { "kind": "literal", "value": "val:" },
                        "right": { "kind": "literal", "value": "100" }
                    },
                    "list": {
                        "kind": "array",
                        "items": [
                            { "kind": "literal", "value": 1 },
                            { "kind": "literal", "value": 2 }
                        ]
                    }
                }
            }
        }
    });

    let mut compiler = Compiler::new();
    let bytecode = compiler
        .compile(&contract_json)
        .expect("Compilation failed");

    let vm = VM::new(None);
    let res = vm
        .execute(&bytecode, &HashMap::new(), &HashMap::new())
        .await
        .unwrap();

    let mut expected_map = std::collections::BTreeMap::new();
    expected_map.insert("negated".to_string(), Value::Integer(-42));
    expected_map.insert("joined".to_string(), Value::String(Arc::from("val:100")));
    expected_map.insert(
        "list".to_string(),
        Value::Array(Arc::new(vec![Value::Integer(1), Value::Integer(2)])),
    );
    assert_eq!(res, Value::Record(Arc::new(expected_map)));
}

#[tokio::test]
async fn test_higher_order_functions() {
    use igniter_vm::compiler::Compiler;

    // test filter, map, and fold/reduce
    let contract_json = serde_json::json!({
        "contract_id": "HigherOrderTest",
        "expression": {
            "kind": "call",
            "fn": "fold",
            "args": [
                {
                    "kind": "map",
                    "fn": "map",
                    "args": [
                        {
                            "kind": "call",
                            "fn": "filter",
                            "args": [
                                { "kind": "array", "items": [{ "kind": "literal", "value": 1 }, { "kind": "literal", "value": 2 }, { "kind": "literal", "value": 3 }, { "kind": "literal", "value": 4 }] },
                                {
                                    "kind": "lambda",
                                    "params": ["x"],
                                    "body": {
                                        "kind": "binary_op",
                                        "operator": ">",
                                        "left": { "kind": "ref", "name": "x" },
                                        "right": { "kind": "literal", "value": 1 }
                                    }
                                }
                            ]
                        },
                        {
                            "kind": "lambda",
                            "params": ["y"],
                            "body": {
                                        "kind": "binary_op",
                                        "operator": "*",
                                        "left": { "kind": "ref", "name": "y" },
                                        "right": { "kind": "literal", "value": 2 }
                            }
                        }
                    ]
                },
                { "kind": "literal", "value": 0 },
                {
                    "kind": "fn",
                    "params": ["acc", "item"],
                    "body": {
                                        "kind": "binary_op",
                                        "operator": "+",
                                        "left": { "kind": "ref", "name": "acc" },
                                        "right": { "kind": "ref", "name": "item" }
                    }
                }
            ]
        }
    });

    let mut compiler = Compiler::new();
    let bytecode = compiler
        .compile(&contract_json)
        .expect("Compilation failed");

    let vm = VM::new(None);
    let res = vm
        .execute(&bytecode, &HashMap::new(), &HashMap::new())
        .await
        .unwrap();

    // filter([1, 2, 3, 4], x > 1) -> [2, 3, 4]
    // map([2, 3, 4], y * 2) -> [4, 6, 8]
    // fold([4, 6, 8], 0, acc + item) -> 18
    assert_eq!(res, Value::Integer(18));
}

#[tokio::test]
async fn test_modifier_pure_rejects_observation() {
    use igniter_vm::compiler::Compiler;
    let contract_json = serde_json::json!({
        "contract_id": "PureContract",
        "modifier": "pure",
        "expression": {
            "kind": "emit_observation",
            "observation_kind": "test_obs",
            "expression": { "kind": "literal", "value": 42 }
        }
    });
    let mut compiler = Compiler::new();
    let res = compiler.compile(&contract_json);
    assert!(res.is_err());
    assert!(res
        .unwrap_err()
        .contains("OOF-M1: emit_observation is not allowed in pure or observed contracts"));
}

#[tokio::test]
async fn test_modifier_observed_rejects_observation() {
    use igniter_vm::compiler::Compiler;
    let contract_json = serde_json::json!({
        "contract_id": "ObservedContract",
        "modifier": "observed",
        "expression": {
            "kind": "emit_observation",
            "observation_kind": "test_obs",
            "expression": { "kind": "literal", "value": 42 }
        }
    });
    let mut compiler = Compiler::new();
    let res = compiler.compile(&contract_json);
    assert!(res.is_err());
    assert!(res
        .unwrap_err()
        .contains("OOF-M1: emit_observation is not allowed in pure or observed contracts"));
}

#[tokio::test]
async fn test_modifier_privileged_validation() {
    use igniter_vm::compiler::Compiler;
    let contract_no_token = serde_json::json!({
        "contract_id": "PrivilegedContract",
        "modifier": "privileged",
        "expression": { "kind": "literal", "value": 42 }
    });
    let mut compiler = Compiler::new();
    let res1 = compiler.compile(&contract_no_token);
    assert!(res1.is_err());
    assert!(res1.unwrap_err().contains("OOF-M1: privileged contract 'PrivilegedContract' requires matching capability token in manifest"));

    let contract_with_token = serde_json::json!({
        "contract_id": "PrivilegedContract",
        "modifier": "privileged",
        "capability_tokens": ["PrivilegedContract"],
        "expression": { "kind": "literal", "value": 42 }
    });
    let res2 = compiler.compile(&contract_with_token);
    assert!(res2.is_ok());
}

#[tokio::test]
async fn test_modifier_irreversible_rejects_compensation() {
    use igniter_vm::compiler::Compiler;
    let contract_json = serde_json::json!({
        "contract_id": "IrreversibleContract",
        "modifier": "irreversible",
        "expression": {
            "kind": "compensation",
            "expression": { "kind": "literal", "value": 42 }
        }
    });
    let mut compiler = Compiler::new();
    let res = compiler.compile(&contract_json);
    assert!(res.is_err());
    assert!(res.unwrap_err().contains(
        "OOF-M1: compensation is not allowed in pure, observed, or irreversible contracts"
    ));
}
