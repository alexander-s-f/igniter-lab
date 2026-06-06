// tests/vm_candidate_proof_tests.rs
// Proof-local integration tests validating VMG-4 through VMG-12 matrix checks

use std::collections::HashMap;
use std::sync::Arc;
use igniter_vm::value::Value;
use igniter_vm::instructions::*;
use igniter_vm::compiler::Compiler;
use igniter_vm::tbackend::MemoryHistoryBackend;
use igniter_vm::vm::VM;

// VMG-4: Decimal add/sub/mul/div delegation parity with R238 stdlib
#[tokio::test]
async fn test_proof_vmg4_decimal_parity() {
    let vm = VM::new(None);

    // Test Decimal Addition: 10.50 + 25.25 = 35.75
    let add_instr = vec![
        Instruction::new(OP_PUSH_LIT, vec![Value::Decimal { value: 1050, scale: 2 }]),
        Instruction::new(OP_PUSH_LIT, vec![Value::Decimal { value: 2525, scale: 2 }]),
        Instruction::new(OP_ADD, vec![]),
        Instruction::new(OP_RET, vec![]),
    ];
    let res_add = vm.execute(&add_instr, &HashMap::new(), &HashMap::new()).await;
    assert_eq!(res_add, Ok(Value::Decimal { value: 3575, scale: 2 }));

    // Test Decimal Scale Mismatch (OOF-TC5): 10.50 + 2.5
    let err_instr = vec![
        Instruction::new(OP_PUSH_LIT, vec![Value::Decimal { value: 1050, scale: 2 }]),
        Instruction::new(OP_PUSH_LIT, vec![Value::Decimal { value: 25, scale: 1 }]),
        Instruction::new(OP_ADD, vec![]),
        Instruction::new(OP_RET, vec![]),
    ];
    let res_err = vm.execute(&err_instr, &HashMap::new(), &HashMap::new()).await;
    assert!(res_err.is_err());
    assert!(res_err.unwrap_err().contains("OOF-TC5"));
}

// VMG-5 & VMG-6: AOT Compiler lowering and stack/register execution
#[tokio::test]
async fn test_proof_vmg5_vmg6_compiler_and_stack_execution() {
    let contract_json = serde_json::json!({
        "expression": {
            "kind": "binary_op",
            "operator": "+",
            "left": {
                "kind": "literal",
                "value": 15
            },
            "right": {
                "kind": "literal",
                "value": 35
            }
        }
    });

    let mut compiler = Compiler::new();
    let bytecode = compiler.compile(&contract_json).expect("AOT compilation failed");

    // Lowering must produce: PUSH_LIT(15), PUSH_LIT(35), ADD, RET
    assert_eq!(bytecode.len(), 4);
    assert_eq!(bytecode[0].opcode, OP_PUSH_LIT);
    assert_eq!(bytecode[1].opcode, OP_PUSH_LIT);
    assert_eq!(bytecode[2].opcode, OP_ADD);
    assert_eq!(bytecode[3].opcode, OP_RET);

    let vm = VM::new(None);
    let result = vm.execute(&bytecode, &HashMap::new(), &HashMap::new()).await;
    assert_eq!(result, Ok(Value::Integer(50)));
}

// VMG-7 & VMG-8: Selected branch and non-selected branch silence evidence
#[tokio::test]
async fn test_proof_vmg7_vmg8_branch_selection_and_silence() {
    let contract_json = serde_json::json!({
        "modifier": "irreversible",
        "expression": {
            "kind": "if_expr",
            "condition": {
                "kind": "ref",
                "name": "cond_val"
            },
            "then_branch": {
                "kind": "emit_observation",
                "observation_kind": "then_branch_executed",
                "expression": {
                    "kind": "literal",
                    "value": 777
                }
            },
            "else_branch": {
                "kind": "emit_observation",
                "observation_kind": "else_branch_executed",
                "expression": {
                    "kind": "literal",
                    "value": 888
                }
            }
        }
    });

    let mut compiler = Compiler::new();
    let bytecode = compiler.compile(&contract_json).expect("AOT compilation failed");
    let vm = VM::new(None);

    // Case A: Selected Then Branch (cond_val = true)
    let mut inputs_true = HashMap::new();
    inputs_true.insert("cond_val".to_string(), Value::Bool(true));
    
    let res_true = vm.execute(&bytecode, &inputs_true, &HashMap::new()).await;
    assert_eq!(res_true, Ok(Value::Integer(777)));
    
    // Check observations: only then_branch_executed must be present
    let sink_true = vm.observation_sink.lock().await;
    assert_eq!(sink_true.len(), 1);
    assert_eq!(sink_true[0]["kind"], "then_branch_executed");
    drop(sink_true);

    // Case B: Non-selected Branch Silence (cond_val = false)
    let vm_false = VM::new(None);
    let mut inputs_false = HashMap::new();
    inputs_false.insert("cond_val".to_string(), Value::Bool(false));

    let res_false = vm_false.execute(&bytecode, &inputs_false, &HashMap::new()).await;
    assert_eq!(res_false, Ok(Value::Integer(888)));

    // Verify silence: only else_branch_executed must be present, then_branch_executed is silent
    let sink_false = vm_false.observation_sink.lock().await;
    assert_eq!(sink_false.len(), 1);
    assert_eq!(sink_false[0]["kind"], "else_branch_executed");
}

// VMG-9: Unsupported selected-path fail-closed evidence
#[tokio::test]
async fn test_proof_vmg9_unsupported_fail_closed() {
    let contract_json = serde_json::json!({
        "expression": {
            "kind": "unsupported"
        }
    });

    let mut compiler = Compiler::new();
    let bytecode = compiler.compile(&contract_json).expect("AOT compilation failed");
    assert_eq!(bytecode[0].opcode, OP_UNSUPPORTED);

    let vm = VM::new(None);
    let res = vm.execute(&bytecode, &HashMap::new(), &HashMap::new()).await;
    assert!(res.is_err());
    assert!(res.unwrap_err().contains("unsupported selected-path"));
}

// VMG-10: Malformed input / unknown opcode behavior evidence
#[tokio::test]
async fn test_proof_vmg10_malformed_input_unknown_opcode() {
    let malformed_bytecode = vec![
        Instruction::new(0xFF, vec![]), // Invalid/unknown opcode
    ];

    let vm = VM::new(None);
    let res = vm.execute(&malformed_bytecode, &HashMap::new(), &HashMap::new()).await;
    assert!(res.is_err());
    assert!(res.unwrap_err().contains("Unknown instruction opcode"));
}

// VMG-11: OP_LOAD_AS_OF / observation trace evidence with hash-based trace identifiers
#[tokio::test]
async fn test_proof_vmg11_hash_based_trace_identifiers() {
    let backend = Arc::new(MemoryHistoryBackend::new());
    backend.write_history("metrics", "2026-06-01T00:00:00Z", Value::Integer(42)).await;

    let vm = VM::new(Some(backend));
    let bytecode = vec![
        Instruction::new(OP_LOAD_AS_OF, vec![
            Value::String(Arc::from("metrics")),
            Value::String(Arc::from("as_of")),
        ]),
        Instruction::new(OP_RET, vec![]),
    ];

    let mut inputs = HashMap::new();
    inputs.insert("as_of".to_string(), Value::String(Arc::from("2026-06-02T00:00:00Z")));

    let res = vm.execute(&bytecode, &inputs, &HashMap::new()).await;
    assert_eq!(res, Ok(Value::Integer(42)));

    // Verify observation trace id matches the hash-based trace identifier wording and format
    let sink = vm.observation_sink.lock().await;
    assert_eq!(sink.len(), 1);
    assert_eq!(sink[0]["kind"], "temporal_live_read_observation");
    
    let trace_id = sink[0]["observation_id"].as_str().unwrap();
    assert!(trace_id.starts_with("obs/live-read/"));
    assert_eq!(trace_id.len(), 14 + 16); // "obs/live-read/" (14) + 16 hex chars
}

// VMG-12: Map-reduce aggregate evidence
#[tokio::test]
async fn test_proof_vmg12_map_reduce_aggregates() {
    let vm = VM::new(None);

    // Test count(filter(range(1, 5), x > 2)) -> (3, 4) -> count = 2
    let map_reduce_json = serde_json::json!({
        "kind": "map_reduce_aggregate",
        "source": {
            "kind": "range",
            "start": { "kind": "literal", "value": 1 },
            "end": { "kind": "literal", "value": 5 }
        },
        "pipeline": [
            {
                "kind": "filter",
                "param": "x",
                "body": {
                    "kind": "binary_op",
                    "operator": ">",
                    "left": { "kind": "ref", "name": "x" },
                    "right": { "kind": "literal", "value": 2 }
                }
            },
            {
                "kind": "count"
            }
        ]
    });

    let serialized = serde_json::to_string(&map_reduce_json).unwrap();
    let bytecode = vec![
        Instruction::new(OP_MAP_REDUCE, vec![Value::String(Arc::from(serialized))]),
        Instruction::new(OP_RET, vec![]),
    ];

    let res = vm.execute(&bytecode, &HashMap::new(), &HashMap::new()).await;
    assert_eq!(res, Ok(Value::Integer(2)));
}

// VMG-13: Loop and Service Loop execution support
#[tokio::test]
async fn test_proof_vmg13_local_loops_and_service_loops() {
    // 1. Loop test (Sum elements of an array)
    let contract_json = serde_json::json!({
        "compute_nodes": [
            {
                "name": "sum",
                "expr": { "kind": "literal", "value": 0 }
            },
            {
                "name": "ProcessLeads",
                "expr": {
                    "kind": "loop",
                    "name": "ProcessLeads",
                    "expr": { "kind": "literal", "value": [10, 20, 30] },
                    "options": { "max_steps": 100 },
                    "body_nodes": [
                        {
                            "name": "sum",
                            "expr": {
                                "kind": "binary_op",
                                "operator": "+",
                                "left": { "kind": "ref", "name": "sum" },
                                "right": { "kind": "ref", "name": "item" }
                            }
                        }
                    ]
                }
            },
            {
                "name": "final_sum",
                "expr": { "kind": "ref", "name": "sum" }
            }
        ]
    });

    let mut compiler = Compiler::new();
    let bytecode = compiler.compile(&contract_json).expect("Compilation of loop contract failed");
    
    let vm = VM::new(None);
    let res = vm.execute(&bytecode, &HashMap::new(), &HashMap::new()).await;
    assert_eq!(res, Ok(Value::Integer(60)));

    // 2. Loop fuel bounds execution error (max_steps: 2, array length: 3)
    let bad_contract_json = serde_json::json!({
        "compute_nodes": [
            {
                "name": "sum",
                "expr": { "kind": "literal", "value": 0 }
            },
            {
                "name": "ProcessLeads",
                "expr": {
                    "kind": "loop",
                    "name": "ProcessLeads",
                    "expr": { "kind": "literal", "value": [10, 20, 30] },
                    "options": { "max_steps": 2 },
                    "body_nodes": [
                        {
                            "name": "sum",
                            "expr": {
                                "kind": "binary_op",
                                "operator": "+",
                                "left": { "kind": "ref", "name": "sum" },
                                "right": { "kind": "ref", "name": "item" }
                            }
                        }
                    ]
                }
            }
        ]
    });

    let bad_bytecode = compiler.compile(&bad_contract_json).expect("Compilation failed");
    let bad_res = vm.execute(&bad_bytecode, &HashMap::new(), &HashMap::new()).await;
    assert!(bad_res.is_err());
    assert!(bad_res.unwrap_err().contains("OOF-L-FUEL"));

    // 3. Service Loop test (Clock tick loading with field access tick.time)
    let service_contract_json = serde_json::json!({
        "compute_nodes": [
            {
                "name": "ProcessQueue",
                "expr": {
                    "kind": "service_loop_node",
                    "name": "tick",
                    "interval": { "value": 5, "unit": "seconds" },
                    "body_nodes": [
                        {
                            "name": "as_of",
                            "expr": {
                                "kind": "binary_op",
                                "operator": "+",
                                "left": {
                                    "kind": "field_access",
                                    "object": { "kind": "ref", "name": "tick" },
                                    "field": "time"
                                },
                                "right": { "kind": "literal", "value": 0 }
                            }
                        }
                    ]
                }
            }
        ]
    });
    
    let service_bytecode = compiler.compile(&service_contract_json).expect("Compilation failed");
    let mut temporal_ctx = HashMap::new();
    temporal_ctx.insert("tick.time".to_string(), Value::Integer(1710000000));
    
    let service_res = vm.execute(&service_bytecode, &HashMap::new(), &temporal_ctx).await;
    assert_eq!(service_res, Ok(Value::Nil));

    // 4. Service Loop tick unresolved error (OOF-SL1)
    let bad_service_res = vm.execute(&service_bytecode, &HashMap::new(), &HashMap::new()).await;
    assert!(bad_service_res.is_err());
    assert!(bad_service_res.unwrap_err().contains("OOF-SL1"));
}

#[tokio::test]
async fn test_proof_vmg_tbackend_append_observation() {
    let backend = Arc::new(MemoryHistoryBackend::new());
    let vm = VM::new(Some(backend.clone()));

    // AST with emit_observation kind
    let contract_json = serde_json::json!({
        "modifier": "irreversible",
        "expression": {
            "kind": "emit_observation",
            "observation_kind": "custom_audit_obs",
            "expression": {
                "kind": "literal",
                "value": "payload-data"
            }
        }
    });

    let mut compiler = Compiler::new();
    let bytecode = compiler.compile(&contract_json).expect("Compilation failed");

    // Execute compiled bytecode
    let res = vm.execute(&bytecode, &HashMap::new(), &HashMap::new()).await;
    assert_eq!(res, Ok(Value::String(Arc::from("payload-data"))));

    // Verify VM sink
    let sink = vm.observation_sink.lock().await;
    assert_eq!(sink.len(), 1);
    assert_eq!(sink[0]["kind"], "custom_audit_obs");
    assert_eq!(sink[0]["value"], "payload-data");
    drop(sink);

    // Verify backend sink (connected VM-to-TBackend observation binding)
    let backend_sink = backend.observation_sink.read().await;
    assert_eq!(backend_sink.len(), 1);
    
    let obs_json = backend_sink[0].to_json();
    assert_eq!(obs_json["kind"], "custom_audit_obs");
    assert_eq!(obs_json["value"], "payload-data");
}

