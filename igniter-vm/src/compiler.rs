// src/compiler.rs
// Ahead-of-Time (AOT) Compiler translating SemanticIR AST node graphs to Compiled IVM Bytecode

use std::collections::HashMap;
use std::sync::Arc;
use crate::instructions::*;
use crate::value::Value;

pub struct Compiler {
    instructions: Vec<Instruction>,
    compute_node_registers: HashMap<String, i64>,
    next_register: i64,
}

impl Compiler {
    pub fn new() -> Self {
        Self {
            instructions: Vec::new(),
            compute_node_registers: HashMap::new(),
            next_register: 1000,
        }
    }

    // Compile a high-level contract graph into linear bytecode instructions.
    // Defaults to contracts[0] (backward-compatible). See compile_entry for named selection.
    pub fn compile(&mut self, contract_jv: &serde_json::Value) -> Result<Vec<Instruction>, String> {
        self.compile_entry(contract_jv, None)
    }

    // LAB-RACK-P7: Named entrypoint selector.
    // When entry_name is Some(name), selects the contract whose "contract_name" (SemanticIR
    // field) or "name" matches. Falls back to contracts[0] when None (default behavior).
    // Fails closed with a descriptive error listing available contract names when the
    // requested entry is not found.
    pub fn compile_entry(&mut self, contract_jv: &serde_json::Value, entry_name: Option<&str>) -> Result<Vec<Instruction>, String> {
        self.instructions.clear();
        self.compute_node_registers.clear();
        self.next_register = 1000;

        // Extract contract object: support semantic_ir_program format or direct contract JSON.
        // LAB-RACK-P7: with entry_name, search by contract_name; else contracts[0] (default).
        let contract_obj = if let Some(contracts_arr) = contract_jv.get("contracts").and_then(|c| c.as_array()) {
            if let Some(name) = entry_name {
                contracts_arr.iter()
                    .find(|c| {
                        c.get("contract_name").and_then(|n| n.as_str()) == Some(name)
                            || c.get("name").and_then(|n| n.as_str()) == Some(name)
                    })
                    .ok_or_else(|| {
                        let available: Vec<&str> = contracts_arr.iter()
                            .filter_map(|c| {
                                c.get("contract_name").and_then(|n| n.as_str())
                                    .or_else(|| c.get("name").and_then(|n| n.as_str()))
                            })
                            .collect();
                        format!(
                            "Entry '{}' not found in igapp (available: [{}])",
                            name,
                            if available.is_empty() { "none".to_string() } else { available.join(", ") }
                        )
                    })?
            } else {
                contracts_arr.get(0).ok_or("No contracts found in semantic_ir_program")?
            }
        } else {
            contract_jv
        };

        let modifier = contract_obj.get("modifier")
            .and_then(|m| m.as_str())
            .unwrap_or("pure");

        let contract_name = contract_obj.get("name")
            .or_else(|| contract_obj.get("contract_id"))
            .and_then(|n| n.as_str())
            .unwrap_or("");

        if modifier == "privileged" {
            let tokens = contract_jv.get("capability_tokens")
                .or_else(|| contract_obj.get("capability_tokens"))
                .and_then(|t| t.as_array());
            
            let has_token = if let Some(arr) = tokens {
                arr.iter().any(|t| t.as_str() == Some(contract_name))
            } else {
                false
            };
            if !has_token {
                return Err(format!("OOF-M1: privileged contract '{}' requires matching capability token in manifest", contract_name));
            }
        }

        verify_ast_constraints(contract_obj, modifier)?;

        // Determine if contract has compute_nodes or nodes
        let nodes_val = contract_obj.get("compute_nodes")
            .or_else(|| contract_obj.get("nodes"));

        if let Some(nodes_arr) = nodes_val.and_then(|v| v.as_array()) {
            // 1. Assign register IDs to each compute node
            for node in nodes_arr {
                if let Some(name) = node.get("name").and_then(|n| n.as_str()) {
                    let reg = self.next_register;
                    self.next_register += 1;
                    self.compute_node_registers.insert(name.to_string(), reg);
                }
            }

            // 2. Compile each compute node's expression and store in register
            for node in nodes_arr {
                let kind = node.get("kind").and_then(|k| k.as_str()).unwrap_or("");
                if kind == "loop_node" || kind == "service_loop_node" {
                    self.compile_expr(node)?;
                } else {
                    let expr = node.get("expression")
                        .or_else(|| node.get("expr"));
                    
                    if let Some(e) = expr {
                        self.compile_expr(e)?;
                    } else {
                        // Skip nodes without expressions (declarations, metadata, temporal/stream inputs)
                        continue;
                    }
                }

                if let Some(name) = node.get("name").and_then(|n| n.as_str()) {
                    let reg = *self.compute_node_registers.get(name).unwrap();
                    self.emit(OP_STORE_REG, vec![Value::Integer(reg)]);
                }
            }

            // 3. Load the output result and return
            let mut loaded_output = false;
            if let Some(outputs_arr) = contract_obj.get("outputs").and_then(|o| o.as_array()) {
                if let Some(first_output) = outputs_arr.first() {
                    if let Some(out_name) = first_output.get("name").and_then(|n| n.as_str()) {
                        if let Some(&reg) = self.compute_node_registers.get(out_name) {
                            self.emit(OP_LOAD_REG, vec![Value::Integer(reg)]);
                            loaded_output = true;
                        }
                    }
                }
            }

            if !loaded_output {
                if let Some(last_node) = nodes_arr.last() {
                    if let Some(name) = last_node.get("name").and_then(|n| n.as_str()) {
                        if let Some(&reg) = self.compute_node_registers.get(name) {
                            self.emit(OP_LOAD_REG, vec![Value::Integer(reg)]);
                        }
                    }
                }
            }
            self.emit(OP_RET, vec![]);
        } else {
            // Traditional single-expression compilation
            let expr = contract_obj.get("expression")
                .ok_or("Contract is missing 'expression' or 'nodes' AST node")?;

            self.compile_expr(expr)?;
            self.emit(OP_RET, vec![]);
        }

        Ok(self.instructions.clone())
    }

    // LAB-RACK-P9: Build a DispatchEntry for a single contract object from a SemanticIR program.
    // Compiles the contract and extracts input_names (in declaration order) + modifier.
    // Used by main.rs to populate the VM's dispatch_table for call_contract("Name", ...) support.
    //
    // SemanticIR contract structure (from emitter.rs):
    //   contract_obj["inputs"]   — array of { "name": "...", "type": { ... } }
    //   contract_obj["modifier"] — "pure" | "effect" | "privileged" | etc.
    //   contract_obj["nodes"]    — compute nodes (also "compute_nodes" for legacy)
    pub fn build_dispatch_entry(
        &mut self,
        contract_jv: &serde_json::Value,
        contract_name: &str,
    ) -> Result<crate::vm::DispatchEntry, String> {
        // Extract input names from the "inputs" top-level array (SemanticIR structure).
        // Each input has a "name" field; extract in declaration order.
        let input_names: Vec<String> = contract_jv
            .get("inputs")
            .and_then(|d| d.as_array())
            .map(|inputs| {
                inputs.iter()
                    .filter_map(|inp| inp.get("name").and_then(|n| n.as_str()).map(|s| s.to_string()))
                    .collect()
            })
            .unwrap_or_default();

        // Modifier (for pure-only enforcement at dispatch time)
        let modifier = contract_jv.get("modifier")
            .and_then(|m| m.as_str())
            .unwrap_or("pure")
            .to_string();

        // Compile bytecode — passes contract object directly (not wrapped in program envelope).
        // compile_entry handles the case where contract_jv has no "contracts" key (direct contract).
        let bytecode = self.compile_entry(contract_jv, None)?;

        Ok(crate::vm::DispatchEntry {
            bytecode,
            input_names,
            modifier,
            contract_name: contract_name.to_string(),
        })
    }

    fn emit(&mut self, opcode: u8, args: Vec<Value>) -> usize {
        let inst = Instruction::new(opcode, args);
        self.instructions.push(inst);
        self.instructions.len() - 1
    }

    fn compile_expr(&mut self, node: &serde_json::Value) -> Result<(), String> {
        let kind = node.get("kind")
            .ok_or("Expression node must be a Hash with a 'kind' key")?
            .as_str()
            .ok_or("kind must be a string")?;

        match kind {
            "literal" => {
                let val = node.get("value").ok_or("Missing literal value")?;
                self.emit(OP_PUSH_LIT, vec![Value::from_json(val)]);
            }

            "symbol" => {
                let val = node.get("value").ok_or("Missing symbol value")?
                    .as_str()
                    .ok_or("symbol value must be a string")?;
                self.emit(OP_PUSH_LIT, vec![Value::String(Arc::from(val))]);
            }

            "range" => {
                let start = node.get("start").ok_or("Missing start in range")?;
                let end = node.get("end").ok_or("Missing end in range")?;
                self.compile_expr(start)?;
                self.compile_expr(end)?;
                self.emit(OP_CALL, vec![Value::String(Arc::from("range")), Value::Integer(2)]);
            }

            "ref" => {
                let name = node.get("name")
                    .ok_or("Missing ref name")?
                    .as_str()
                    .ok_or("name must be string")?;
                
                if let Some(&reg_idx) = self.compute_node_registers.get(name) {
                    self.emit(OP_LOAD_REG, vec![Value::Integer(reg_idx)]);
                } else {
                    self.emit(OP_LOAD_REF, vec![Value::String(Arc::from(name))]);
                }
            }

            "binary_op" => {
                let left = node.get("left").ok_or("Missing left operand")?;
                let right = node.get("right").ok_or("Missing right operand")?;
                let op = node.get("operator")
                    .or_else(|| node.get("op"))
                    .ok_or("Missing operator")?
                    .as_str()
                    .ok_or("operator must be string")?;

                self.compile_expr(left)?;
                self.compile_expr(right)?;

                match op {
                    "+" => { self.emit(OP_ADD, vec![]); }
                    "-" => { self.emit(OP_SUB, vec![]); }
                    "*" => { self.emit(OP_MUL, vec![]); }
                    "/" => { self.emit(OP_DIV, vec![]); }
                    "==" => { self.emit(OP_EQ, vec![]); }
                    ">" => { self.emit(OP_GT, vec![]); }
                    "<" => { self.emit(OP_LT, vec![]); }
                    "<=" => { self.emit(OP_LE, vec![]); }
                    ">=" => { self.emit(OP_GE, vec![]); }
                    "!=" => { self.emit(OP_NE, vec![]); }
                    "&&" => { self.emit(OP_AND, vec![]); }
                    "||" => { self.emit(OP_OR, vec![]); }
                    "++" => { self.emit(OP_CONCAT, vec![]); }
                    _ => return Err(format!("Unsupported binary operator: {}", op)),
                }
            }

            "apply" | "call" | "map" | "filter" | "fold" | "reduce" => {
                let op_fallback = serde_json::Value::String(kind.to_string());
                let op = if kind == "apply" {
                    node.get("operator")
                } else if kind == "call" {
                    node.get("fn")
                } else {
                    node.get("fn").or(Some(&op_fallback))
                }.ok_or("Missing operator/fn")?.as_str().ok_or("operator/fn must be a string")?;

                let operands = if kind == "apply" {
                    node.get("operands")
                } else if kind == "call" {
                    node.get("args")
                } else {
                    node.get("args").or_else(|| node.get("operands"))
                }.ok_or("Missing operands/args")?.as_array().ok_or("operands/args must be an array")?;

                for operand in operands {
                    self.compile_expr(operand)?;
                }

                match op {
                    "+" | "add" => { self.emit(OP_ADD, vec![]); }
                    "-" | "sub" => { self.emit(OP_SUB, vec![]); }
                    "*" | "mul" => { self.emit(OP_MUL, vec![]); }
                    "/" | "div" => { self.emit(OP_DIV, vec![]); }
                    "==" | "eq" => { self.emit(OP_EQ, vec![]); }
                    ">" | "gt" => { self.emit(OP_GT, vec![]); }
                    "<" | "lt" => { self.emit(OP_LT, vec![]); }
                    "<=" | "le" => { self.emit(OP_LE, vec![]); }
                    ">=" | "ge" => { self.emit(OP_GE, vec![]); }
                    "!=" | "ne" => { self.emit(OP_NE, vec![]); }
                    "&&" | "and" => { self.emit(OP_AND, vec![]); }
                    "||" | "or" => { self.emit(OP_OR, vec![]); }
                    "++" | "concat" => { self.emit(OP_CONCAT, vec![]); }
                    _ => {
                        self.emit(OP_CALL, vec![Value::String(Arc::from(op)), Value::Integer(operands.len() as i64)]);
                    }
                }
            }

            "if_expr" => {
                let cond = node.get("condition").ok_or("Missing if condition")?;
                let then_b = node.get("then_branch").ok_or("Missing then branch")?;
                let else_b = node.get("else_branch").ok_or("Missing else branch")?;

                self.compile_expr(cond)?;

                // Emit placeholder JMP_UNLESS
                let jmp_unless_idx = self.emit(OP_JMP_UNLESS, vec![Value::Integer(0)]);

                self.compile_expr(then_b)?;

                // Emit placeholder JMP to skip else branch
                let jmp_end_idx = self.emit(OP_JMP, vec![Value::Integer(0)]);

                // Label: start of else branch is the current instruction pointer offset
                let else_branch_start_idx = self.instructions.len() as i64;

                self.compile_expr(else_b)?;

                // Label: end is the current instruction pointer offset
                let end_idx = self.instructions.len() as i64;

                // Re-emit instructions with resolved placeholder targets
                self.instructions[jmp_unless_idx].args = vec![Value::Integer(else_branch_start_idx)];
                self.instructions[jmp_end_idx].args = vec![Value::Integer(end_idx)];
            }

            "temporal_read" => {
                let store_ref = node.get("store_ref")
                    .ok_or("Missing store_ref")?
                    .as_str()
                    .ok_or("store_ref must be string")?;
                let as_of_ref = node.get("as_of_ref")
                    .ok_or("Missing as_of_ref")?
                    .as_str()
                    .ok_or("as_of_ref must be string")?;

                self.emit(OP_LOAD_AS_OF, vec![
                    Value::String(Arc::from(store_ref)),
                    Value::String(Arc::from(as_of_ref)),
                ]);
            }

            "emit_observation" => {
                let obs_kind = node.get("observation_kind")
                    .ok_or("Missing observation_kind")?
                    .as_str()
                    .ok_or("observation_kind must be string")?;
                let inner = node.get("expression").ok_or("Missing inner expression")?;

                self.compile_expr(inner)?;
                self.emit(OP_EMIT_OBS, vec![Value::String(Arc::from(obs_kind))]);
            }

            "field_access" => {
                // LAB-RECORD-VM-P2: field extraction from a record value.
                // Strategy:
                //   1. If `name.field` is a pre-computed register (pre-extracted sub-field), load it directly.
                //   2. If `name` is a register holding a Record, load the record + OP_GET_FIELD to extract.
                //   3. Otherwise, OP_LOAD_REF "name.field" (inputs/temporal_context lookup fallback).
                let object = node.get("object").ok_or("Missing object in field_access")?;
                let field = node.get("field").ok_or("Missing field in field_access")?.as_str().ok_or("field must be string")?;

                if let Some("ref") = object.get("kind").and_then(|k| k.as_str()) {
                    let name = object.get("name").ok_or("Missing name in ref")?.as_str().ok_or("name must be string")?;
                    let full_name = format!("{}.{}", name, field);
                    if let Some(&reg_idx) = self.compute_node_registers.get(&full_name) {
                        // Pre-computed sub-field register — load directly
                        self.emit(OP_LOAD_REG, vec![Value::Integer(reg_idx)]);
                        return Ok(());
                    }
                    if let Some(&reg_idx) = self.compute_node_registers.get(name) {
                        // Record in a register — load the record, then extract the named field
                        self.emit(OP_LOAD_REG, vec![Value::Integer(reg_idx)]);
                        self.emit(OP_GET_FIELD, vec![Value::String(Arc::from(field))]);
                        return Ok(());
                    }
                    // LAB-VM-MAP-P1: input record field access fallback.
                    // When `name` is an input (not a computed register), emit
                    // OP_LOAD_REF(name) + OP_GET_FIELD(field) so the VM resolves
                    // the base record from inputs and extracts the named field.
                    // Previously emitted OP_LOAD_REF("name.field") which failed
                    // at runtime because inputs use bare names as keys, not dotted paths.
                    self.emit(OP_LOAD_REF, vec![Value::String(Arc::from(name))]);
                    self.emit(OP_GET_FIELD, vec![Value::String(Arc::from(field))]);
                    return Ok(());
                }
                // LAB-RECORD-VM-P3: chained field access — object is itself an expression
                // (e.g. another field_access). Recursively compile the object onto the stack,
                // then extract the named field with OP_GET_FIELD.
                // Handles: envelope.headers.content_type, receipt.meta.priority, etc.
                self.compile_expr(object)?;
                self.emit(OP_GET_FIELD, vec![Value::String(Arc::from(field))]);
                return Ok(());
            }

            "map_reduce_aggregate" => {
                let serialized = serde_json::to_string(node)
                    .map_err(|e| format!("Failed to serialize map_reduce_aggregate: {}", e))?;
                self.emit(OP_MAP_REDUCE, vec![Value::String(Arc::from(serialized))]);
            }

            "loop_node" => {
                // G3c: kind="loop_node" (was "loop"); G3b: finite loops have max_steps=0 (unlimited)
                let loop_name = node.get("name").and_then(|n| n.as_str()).ok_or("Missing loop name")?;
                let collection = node.get("expr").or_else(|| node.get("expression")).ok_or("Missing loop collection expr")?;

                // Compile collection expression (pushes collection to stack)
                self.compile_expr(collection)?;

                // G3b: read max_steps from top-level (new emitter) or options (old compat)
                // max_steps=0 means FiniteLoop (unlimited — VM uses u64::MAX, see vm.rs OP_LOOP_START)
                let max_steps = node.get("max_steps")
                    .and_then(|ms| ms.as_i64())
                    .or_else(|| node.get("options")
                        .and_then(|o| o.get("max_steps"))
                        .and_then(|ms| ms.as_i64().or_else(|| ms.get("value").and_then(|v| v.as_i64()))))
                    .unwrap_or(0);
                
                // 1. LOOP_START (pops collection, creates frame)
                self.emit(OP_LOOP_START, vec![Value::String(Arc::from(loop_name)), Value::Integer(max_steps)]);
                
                // 2. Loop header JMP target (start of iteration)
                let loop_header_ip = self.instructions.len() as i64;
                
                // 3. LOOP_STEP (checks fuel, pushes next item, jumps to exit if done)
                let loop_step_idx = self.emit(OP_LOOP_STEP, vec![Value::Integer(0)]);
                
                // 4. Bind loop variables to a new register
                let item_reg = self.next_register;
                self.next_register += 1;
                
                // G1: use explicit item variable name from IR if present,
                // otherwise fall back to singularize(loop_name) for backward compat.
                let explicit_item = node.get("item").and_then(|v| v.as_str()).map(|s| s.to_string());
                let default_item = singularize(loop_name);
                let primary_item = explicit_item.clone().unwrap_or_else(|| default_item.clone());
                let mut var_names = vec![primary_item.clone(), "item".to_string(), singularize(loop_name)];
                if let Some(coll_ref) = collection.get("name").and_then(|n| n.as_str()) {
                    var_names.push(singularize(coll_ref));
                }
                var_names.sort();
                var_names.dedup();
                
                for var_name in &var_names {
                    self.compute_node_registers.insert(var_name.clone(), item_reg);
                }
                
                // 5. Store current item from stack into loop variable register
                self.emit(OP_STORE_REG, vec![Value::Integer(item_reg)]);
                
                // 6. Register registers for loop body compute nodes
                let body_nodes = node.get("body_nodes").and_then(|b| b.as_array());
                if let Some(body) = body_nodes {
                    for inner in body {
                        if let Some(inner_name) = inner.get("name").and_then(|n| n.as_str()) {
                            if !self.compute_node_registers.contains_key(inner_name) {
                                let reg = self.next_register;
                                self.next_register += 1;
                                self.compute_node_registers.insert(inner_name.to_string(), reg);
                            }
                        }
                    }
                    
                    // Compile loop body compute nodes
                    for inner in body {
                        let inner_expr = inner.get("expr").or_else(|| inner.get("expression")).ok_or("Missing loop body compute expr")?;
                        self.compile_expr(inner_expr)?;
                        
                        if let Some(inner_name) = inner.get("name").and_then(|n| n.as_str()) {
                            let reg = *self.compute_node_registers.get(inner_name).unwrap();
                            self.emit(OP_STORE_REG, vec![Value::Integer(reg)]);
                        }
                    }
                }
                
                // 7. JMP back to loop header (OP_LOOP_STEP)
                self.emit(OP_JMP, vec![Value::Integer(loop_header_ip)]);
                
                // 8. Push Nil as the result of the loop expression
                self.emit(OP_PUSH_LIT, vec![Value::Nil]);
                
                // 9. Update OP_LOOP_STEP exit IP
                let exit_ip = (self.instructions.len() - 1) as i64;
                self.instructions[loop_step_idx].args = vec![Value::Integer(exit_ip)];
            }

            "service_loop_node" => {
                let loop_name = node.get("name").and_then(|n| n.as_str()).ok_or("Missing service loop name")?;
                
                // Get interval value (milliseconds)
                let interval_val = node.get("interval").and_then(|i| i.get("value")).and_then(|v| v.as_i64()).ok_or("Missing interval value")?;
                let interval_unit = node.get("interval").and_then(|i| i.get("unit")).and_then(|u| u.as_str()).ok_or("Missing interval unit")?;
                
                let interval_ms = match interval_unit {
                    "seconds" => interval_val * 1000,
                    "minutes" => interval_val * 60 * 1000,
                    "hours" => interval_val * 60 * 60 * 1000,
                    _ => interval_val,
                };
                
                // Load temporal clock tick timestamp into loop tick variable register
                let tick_reg = self.next_register;
                self.next_register += 1;
                self.compute_node_registers.insert(loop_name.to_string(), tick_reg);
                
                // 1. OP_LOAD_TICK pushes tick value onto stack
                self.emit(OP_LOAD_TICK, vec![Value::Integer(interval_ms)]);
                
                // 2. Store it in tick register
                self.emit(OP_STORE_REG, vec![Value::Integer(tick_reg)]);
                
                // 3. Register registers for loop body compute nodes and compile them
                let body_nodes = node.get("body_nodes").and_then(|b| b.as_array());
                if let Some(body) = body_nodes {
                    for inner in body {
                        if let Some(inner_name) = inner.get("name").and_then(|n| n.as_str()) {
                            if !self.compute_node_registers.contains_key(inner_name) {
                                let reg = self.next_register;
                                self.next_register += 1;
                                self.compute_node_registers.insert(inner_name.to_string(), reg);
                            }
                        }
                    }
                    
                    for inner in body {
                        let inner_expr = inner.get("expr").or_else(|| inner.get("expression")).ok_or("Missing service loop body compute expr")?;
                        self.compile_expr(inner_expr)?;
                        
                        if let Some(inner_name) = inner.get("name").and_then(|n| n.as_str()) {
                            let reg = *self.compute_node_registers.get(inner_name).unwrap();
                            self.emit(OP_STORE_REG, vec![Value::Integer(reg)]);
                        }
                    }
                }
                
                // 4. Push Nil as the result of the service loop
                self.emit(OP_PUSH_LIT, vec![Value::Nil]);
            }

            "unary" | "unary_op" => {
                let op = node.get("op")
                    .or_else(|| node.get("operator"))
                    .ok_or("Missing unary operator")?
                    .as_str()
                    .ok_or("unary operator must be string")?;
                let operand = node.get("operand")
                    .or_else(|| node.get("expr"))
                    .or_else(|| node.get("expression"))
                    .ok_or("Missing unary operand")?;
                self.compile_expr(operand)?;
                match op {
                    "!" => { self.emit(OP_NOT, vec![]); }
                    "-" => { self.emit(OP_NEG, vec![]); }
                    _ => return Err(format!("Unsupported unary operator: {}", op)),
                }
            }

            "array" | "array_literal" => {
                let items = node.get("items").ok_or("Missing items in array")?.as_array().ok_or("items must be array")?;
                for item in items {
                    self.compile_expr(item)?;
                }
                self.emit(OP_PUSH_ARRAY, vec![Value::Integer(items.len() as i64)]);
            }

            "record" | "record_literal" => {
                let fields = node.get("fields").ok_or("Missing fields in record")?.as_object().ok_or("fields must be object")?;
                let mut sorted_keys: Vec<String> = fields.keys().cloned().collect();
                sorted_keys.sort();
                for key in &sorted_keys {
                    let val_expr = fields.get(key).unwrap();
                    self.compile_expr(val_expr)?;
                }
                let mut args = vec![Value::Integer(sorted_keys.len() as i64)];
                for key in sorted_keys {
                    args.push(Value::String(Arc::from(key.as_str())));
                }
                self.emit(OP_PUSH_RECORD, args);
            }

            "concat" => {
                let left = node.get("left").ok_or("Missing left operand in concat")?;
                let right = node.get("right").ok_or("Missing right operand in concat")?;
                self.compile_expr(left)?;
                self.compile_expr(right)?;
                self.emit(OP_CONCAT, vec![]);
            }

            "let" => {
                let expr = node.get("expr")
                    .or_else(|| node.get("value"))
                    .or_else(|| node.get("expression"))
                    .ok_or("Missing let value expression")?;
                let name = node.get("name")
                    .ok_or("Missing let variable name")?
                    .as_str()
                    .ok_or("let variable name must be string")?;
                
                self.compile_expr(expr)?;
                
                let reg = self.next_register;
                self.next_register += 1;
                self.compute_node_registers.insert(name.to_string(), reg);
                
                self.emit(OP_STORE_REG, vec![Value::Integer(reg)]);
                
                if let Some(body) = node.get("body") {
                    self.compile_expr(body)?;
                } else {
                    self.emit(OP_LOAD_REG, vec![Value::Integer(reg)]);
                }
            }

            "lambda" | "fn" => {
                let serialized = serde_json::to_string(node)
                    .map_err(|e| format!("Failed to serialize lambda: {}", e))?;
                self.emit(OP_PUSH_LIT, vec![Value::String(Arc::from(serialized))]);
            }

            // LAB-VARIANT-VM-P1: Path B — variant_construct → OP_PUSH_RECORD with __arm discriminant.
            // SIR shape: { kind, arm, variant, fields: {name: expr, ...}, resolved_type }
            // Lowering: ordinary record containing:
            //   __arm     → arm name (compiler-owned discriminant)
            //   __variant → variant name (diagnostic use)
            //   + payload fields verbatim
            // No Value::Variant. No OP_PUSH_VARIANT.
            "variant_construct" => {
                let arm_name = node.get("arm")
                    .and_then(|a| a.as_str())
                    .ok_or("variant_construct: missing arm")?;
                let variant_name = node.get("variant")
                    .and_then(|v| v.as_str())
                    .unwrap_or(arm_name);
                let fields_obj = node.get("fields")
                    .and_then(|f| f.as_object())
                    .ok_or("variant_construct: missing fields object")?;

                // Collect all keys: payload fields + __arm + __variant
                let mut all_keys: Vec<String> = fields_obj.keys().cloned().collect();
                all_keys.push("__arm".to_string());
                all_keys.push("__variant".to_string());
                all_keys.sort();

                // Push values in sorted-key order (OP_PUSH_RECORD pops in reverse)
                for key in &all_keys {
                    if key == "__arm" {
                        self.emit(OP_PUSH_LIT, vec![Value::String(Arc::from(arm_name))]);
                    } else if key == "__variant" {
                        self.emit(OP_PUSH_LIT, vec![Value::String(Arc::from(variant_name))]);
                    } else {
                        let field_expr = fields_obj.get(key.as_str())
                            .ok_or_else(|| format!("variant_construct: missing field expr for '{}'", key))?;
                        self.compile_expr(field_expr)?;
                    }
                }

                let mut args = vec![Value::Integer(all_keys.len() as i64)];
                for key in &all_keys {
                    args.push(Value::String(Arc::from(key.as_str())));
                }
                self.emit(OP_PUSH_RECORD, args);
            }

            // LAB-VARIANT-VM-P1: Path B — match_node → OP_GET_FIELD(__arm) + OP_EQ + OP_JMP_UNLESS chain.
            // SIR shape: { kind, subject, subject_type, arms: [{pattern, body, resolved_type}],
            //              exhaustive, has_wildcard, resolved_type }
            // "match_expr" is the raw-AST form used for nested match nodes in arm bodies
            // (annotate_expr_with_type preserves the Expr::MatchExpr serde tag).
            // Lowering:
            //   1. Compile subject once, store in temp register R_subject.
            //   2. For each non-wildcard arm: load R_subject, GET_FIELD "__arm", compare, JMP_UNLESS next.
            //      Bind payload fields, compile body, JMP end.
            //   3. Wildcard arm: compile body, JMP end.
            //   4. No-match fallback (no wildcard): OP_UNSUPPORTED — fail closed, never silent Nil.
            //   5. Patch all end-jumps to current IP.
            // No OP_MATCH. No Value::Variant.
            "match_node" | "match_expr" => {
                let subject = node.get("subject").ok_or("match_node: missing subject")?;
                let arms = node.get("arms")
                    .and_then(|a| a.as_array())
                    .ok_or("match_node: missing arms array")?;
                let has_wildcard = node.get("has_wildcard")
                    .and_then(|w| w.as_bool())
                    .unwrap_or(false);

                // Step 1: compile subject and store in a dedicated temp register
                self.compile_expr(subject)?;
                let subject_reg = self.next_register;
                self.next_register += 1;
                self.emit(OP_STORE_REG, vec![Value::Integer(subject_reg)]);

                // Step 2 & 3: compile each arm
                let mut jmp_end_idxs: Vec<usize> = Vec::new();

                for arm in arms {
                    let pattern = arm.get("pattern");
                    let is_wildcard = pattern
                        .and_then(|p| p.get("wildcard"))
                        .and_then(|w| w.as_bool())
                        .unwrap_or(false);
                    let arm_name = pattern
                        .and_then(|p| p.get("arm"))
                        .and_then(|a| a.as_str())
                        .unwrap_or("_");
                    let bindings: Vec<String> = pattern
                        .and_then(|p| p.get("bindings"))
                        .and_then(|b| b.as_array())
                        .map(|arr| arr.iter().filter_map(|v| v.as_str().map(|s| s.to_string())).collect())
                        .unwrap_or_default();
                    let body = arm.get("body").ok_or("match_node: missing arm body")?;

                    // Discriminant compare (skipped for wildcard)
                    let jmp_unless_idx = if !is_wildcard {
                        self.emit(OP_LOAD_REG, vec![Value::Integer(subject_reg)]);
                        self.emit(OP_GET_FIELD, vec![Value::String(Arc::from("__arm"))]);
                        self.emit(OP_PUSH_LIT, vec![Value::String(Arc::from(arm_name))]);
                        self.emit(OP_EQ, vec![]);
                        Some(self.emit(OP_JMP_UNLESS, vec![Value::Integer(0)]))
                    } else {
                        None
                    };

                    // Extract payload bindings into scoped temp registers
                    let mut binding_regs: Vec<(String, i64)> = Vec::new();
                    for binding in &bindings {
                        self.emit(OP_LOAD_REG, vec![Value::Integer(subject_reg)]);
                        self.emit(OP_GET_FIELD, vec![Value::String(Arc::from(binding.as_str()))]);
                        let reg = self.next_register;
                        self.next_register += 1;
                        self.emit(OP_STORE_REG, vec![Value::Integer(reg)]);
                        // Make binding available in arm body scope
                        self.compute_node_registers.insert(binding.clone(), reg);
                        binding_regs.push((binding.clone(), reg));
                    }

                    // Compile arm body (result left on stack)
                    self.compile_expr(body)?;

                    // Remove bindings from scope before moving on
                    for (name, _) in &binding_regs {
                        self.compute_node_registers.remove(name);
                    }

                    // Jump to end (successful arm — skip remaining arms)
                    let jmp_end_idx = self.emit(OP_JMP, vec![Value::Integer(0)]);
                    jmp_end_idxs.push(jmp_end_idx);

                    // Patch discriminant JMP_UNLESS to point to start of next arm
                    if let Some(idx) = jmp_unless_idx {
                        let next_arm_ip = self.instructions.len() as i64;
                        self.instructions[idx].args = vec![Value::Integer(next_arm_ip)];
                    }
                }

                // Step 4: fail-closed fallback if no wildcard covers all cases
                // Reached only when no arm matched — defensive, never silent Nil
                if !has_wildcard {
                    self.emit(OP_UNSUPPORTED, vec![]);
                }

                // Step 5: patch all arm end-jumps to current IP (first instruction after match)
                let end_ip = self.instructions.len() as i64;
                for idx in jmp_end_idxs {
                    self.instructions[idx].args = vec![Value::Integer(end_ip)];
                }
            }

            "unsupported" => {
                self.emit(OP_UNSUPPORTED, vec![]);
            }

            _ => return Err(format!("Unsupported AST expression kind: {}", kind)),
        }

        Ok(())
    }
}

fn singularize(s: &str) -> String {
    let s_lower = s.to_lowercase();
    if s_lower.ends_with("s") {
        let base = s_lower[0..s_lower.len() - 1].to_string();
        if base.ends_with("_lead") {
            "lead".to_string()
        } else {
            base
        }
    } else {
        s_lower
    }
}

fn verify_ast_constraints(node: &serde_json::Value, modifier: &str) -> Result<(), String> {
    if let Some(kind) = node.get("kind").and_then(|k| k.as_str()) {
        if kind == "emit_observation" && (modifier == "pure" || modifier == "observed") {
            return Err("OOF-M1: emit_observation is not allowed in pure or observed contracts".to_string());
        }
        if kind == "compensation" && (modifier == "pure" || modifier == "observed" || modifier == "irreversible") {
            return Err("OOF-M1: compensation is not allowed in pure, observed, or irreversible contracts".to_string());
        }
    }
    if let Some(obj) = node.as_object() {
        for val in obj.values() {
            verify_ast_constraints(val, modifier)?;
        }
    } else if let Some(arr) = node.as_array() {
        for val in arr {
            verify_ast_constraints(val, modifier)?;
        }
    }
    Ok(())
}
