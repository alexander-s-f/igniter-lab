// src/vm.rs
// Stack-based, register-gated execution Virtual Machine (IVM) in pure Rust

use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::Mutex;
use crate::value::Value;
use crate::instructions::*;
use crate::tbackend::TBackend;
use igniter_stdlib::decimal::Decimal;
// LAB-STR-UNICODE-P2: UAX #29 extended grapheme cluster segmentation
use unicode_segmentation::UnicodeSegmentation;

fn parse_utc(dt_str: &str) -> Result<chrono::DateTime<chrono::Utc>, String> {
    if let Ok(dt) = chrono::DateTime::parse_from_rfc3339(dt_str) {
        return Ok(dt.with_timezone(&chrono::Utc));
    }
    if let Ok(ndt) = chrono::NaiveDateTime::parse_from_str(dt_str, "%Y-%m-%d %H:%M:%S") {
        return Ok(ndt.and_utc());
    }
    if let Ok(ndt) = chrono::NaiveDateTime::parse_from_str(dt_str, "%Y-%m-%dT%H:%M:%SZ") {
        return Ok(ndt.and_utc());
    }
    Err(format!("Invalid datetime string: {}", dt_str))
}

// LAB-RACK-P9: pre-compiled dispatch entry for user-contract calls.
// bytecode: compiled instructions for the callee contract.
// input_names: input declaration names in declaration order (used for positional arg mapping).
// modifier: contract modifier ("pure", "effect", etc.); non-pure callees are rejected at dispatch.
// contract_name: the callee contract name (for error messages).
#[derive(Clone)]
pub struct DispatchEntry {
    pub bytecode: Vec<crate::instructions::Instruction>,
    pub input_names: Vec<String>,
    pub modifier: String,
    pub contract_name: String,
}

// LAB-RACK-P9: Maximum user-contract call depth.
// Prevents stack overflow from deep or cyclic dispatch chains.
pub const MAX_CALL_DEPTH: i64 = 64;

pub struct VM {
    backend: Option<Arc<dyn TBackend>>,
    pub observation_sink: Arc<Mutex<Vec<serde_json::Value>>>,
    // LAB-RACK-P9: pre-built dispatch table for call_contract("Name", ...) support.
    // Key: contract_name. Built from igapp at load time in main.rs; empty by default.
    pub dispatch_table: HashMap<String, DispatchEntry>,
    // LAB-VMTRACE-P1: opt-in record-only trace collector; None = trace disabled (normal run).
    pub trace_collector: Option<std::sync::Arc<std::sync::Mutex<Vec<serde_json::Value>>>>,
}

impl VM {
    pub fn new(backend: Option<Arc<dyn TBackend>>) -> Self {
        Self {
            backend,
            observation_sink: Arc::new(Mutex::new(Vec::new())),
            dispatch_table: HashMap::new(),
            trace_collector: None,
        }
    }

    // LAB-VMTRACE-P1: drain collected trace events (leaves collector empty for reuse).
    pub fn take_trace_events(&self) -> Vec<serde_json::Value> {
        match &self.trace_collector {
            Some(c) => std::mem::take(&mut c.lock().unwrap()),
            None => Vec::new(),
        }
    }

    // Shared cross-contract call. Single source of dispatch truth used by BOTH the
    // bytecode OP_CALL path and the eval_ast tree-walker (lambda / HOF bodies), so
    // the two execution paths can no longer diverge on call_contract semantics.
    pub async fn call_contract_value(
        &self,
        callee_name: &str,
        positional_args: &[Value],
        temporal_context: &HashMap<String, Value>,
    ) -> Result<Value, String> {
        let current_depth = temporal_context.get("__call_depth__")
            .and_then(|v| if let Value::Integer(d) = v { Some(*d) } else { None })
            .unwrap_or(0);
        if current_depth >= MAX_CALL_DEPTH {
            return Err(format!(
                "call_contract: max call depth ({}) exceeded; check for indirect recursion",
                MAX_CALL_DEPTH
            ));
        }
        let call_chain_str = temporal_context.get("__call_chain__")
            .and_then(|v| if let Value::String(s) = v { Some(s.as_ref().to_string()) } else { None })
            .unwrap_or_default();
        let chain_names: Vec<&str> = call_chain_str.split(',').filter(|s| !s.is_empty()).collect();
        if chain_names.contains(&callee_name) {
            return Err(format!(
                "call_contract: dispatch cycle detected ({} -> {}); self-recursion and cycles closed in v0",
                if call_chain_str.is_empty() { "(root)".to_string() } else { call_chain_str.clone() },
                callee_name
            ));
        }
        let entry = self.dispatch_table.get(callee_name)
            .ok_or_else(|| {
                let mut av: Vec<&str> = self.dispatch_table.keys().map(|s| s.as_str()).collect();
                av.sort();
                format!(
                    "call_contract: no contract named '{}' in igapp (available: [{}])",
                    callee_name,
                    if av.is_empty() { "none".to_string() } else { av.join(", ") }
                )
            })?
            .clone();
        if entry.modifier != "pure" {
            return Err(format!(
                "call_contract: callee '{}' is not pure (modifier: {}); cross-contract call requires pure callee in v0",
                callee_name, entry.modifier
            ));
        }
        if positional_args.len() != entry.input_names.len() {
            return Err(format!(
                "call_contract: contract '{}' expects {} input(s) [{}], got {}",
                callee_name, entry.input_names.len(), entry.input_names.join(", "), positional_args.len()
            ));
        }
        let callee_inputs: HashMap<String, Value> = entry.input_names.iter()
            .zip(positional_args.iter())
            .map(|(name, val)| (name.clone(), val.clone()))
            .collect();
        let new_chain = if call_chain_str.is_empty() {
            callee_name.to_string()
        } else {
            format!("{},{}", call_chain_str, callee_name)
        };
        let mut callee_temporal = temporal_context.clone();
        callee_temporal.insert("__call_depth__".to_string(), Value::Integer(current_depth + 1));
        callee_temporal.insert("__call_chain__".to_string(), Value::String(Arc::from(new_chain.as_str())));
        Box::pin(self.execute(&entry.bytecode, &callee_inputs, &callee_temporal)).await
    }

    pub async fn execute(
        &self,
        instructions: &[Instruction],
        inputs: &HashMap<String, Value>,
        temporal_context: &HashMap<String, Value>,
    ) -> Result<Value, String> {
        self.execute_with_grants(instructions, inputs, temporal_context, &HashMap::new()).await
    }

    pub async fn execute_with_grants(
        &self,
        instructions: &[Instruction],
        inputs: &HashMap<String, Value>,
        temporal_context: &HashMap<String, Value>,
        resolved_grants: &HashMap<String, crate::passport::CapabilityGrant>,
    ) -> Result<Value, String> {
        struct LoopFrame {
            name: String,
            collection: Vec<Value>,
            index: usize,
            fuel: u64,
        }
        let mut loop_stack: Vec<LoopFrame> = Vec::new();

        let mut stack: Vec<Value> = Vec::with_capacity(256); // Pre-allocated flat stack
        let mut registers: HashMap<i64, Value> = HashMap::new();
        let mut ip = 0; // Instruction Pointer
        let total_instructions = instructions.len();
        // LAB-VMTRACE-P1: monotonic sequence counter for trace events.
        let mut trace_seq: usize = 0;

        while ip < total_instructions {
            let inst = &instructions[ip];
            // LAB-VMTRACE-P1: capture pre-instruction state (zero-cost when trace_collector is None).
            let trace_pre_ip = ip;
            let trace_pre_depth = stack.len();
            let trace_pre_opcode = inst.opcode;
            match inst.opcode {
                OP_PUSH_LIT => {
                    let lit = inst.args.get(0).ok_or("Missing literal argument")?;
                    stack.push(lit.clone());
                    ip += 1;
                }

                OP_LOAD_REF => {
                    let name = inst.args.get(0)
                        .ok_or("Missing reference symbol name")?
                        .as_str()?;
                    
                    let val = if let Some(v) = inputs.get(name) {
                        v.clone()
                    } else if let Some(v) = temporal_context.get(name) {
                        v.clone()
                    } else if resolved_grants.contains_key(name) {
                        Value::String(Arc::from(name))
                    } else {
                        return Err(format!("Reference symbol '{}' not found in inputs or temporal context", name));
                    };
                    stack.push(val);
                    ip += 1;
                }

                OP_STORE_REG => {
                    let reg_idx = inst.args.get(0)
                        .ok_or("Missing register index")?
                        .as_integer()?;
                    
                    let val = stack.pop().ok_or("Stack underflow during STORE_REG")?;
                    registers.insert(reg_idx, val);
                    ip += 1;
                }

                OP_LOAD_REG => {
                    let reg_idx = inst.args.get(0)
                        .ok_or("Missing register index")?
                        .as_integer()?;
                    
                    let val = registers.get(&reg_idx)
                        .ok_or_else(|| format!("Register index {} is uninitialized", reg_idx))?;
                    stack.push(val.clone());
                    ip += 1;
                }

                OP_ADD => {
                    let b = stack.pop().ok_or("Stack underflow during ADD second operand")?;
                    let a = stack.pop().ok_or("Stack underflow during ADD first operand")?;
                    let res = match (&a, &b) {
                        (Value::Decimal { value: av, scale: as_ }, Value::Decimal { value: bv, scale: bs }) => {
                            let da = Decimal::new(*av, *as_);
                            let db = Decimal::new(*bv, *bs);
                            match da.add(&db) {
                                Ok(res_dec) => Value::Decimal { value: res_dec.value, scale: res_dec.scale },
                                Err(e) => return Err(e),
                            }
                        }
                        (Value::Integer(av), Value::Integer(bv)) => Value::Integer(av + bv),
                        (Value::Float(av), Value::Float(bv)) => Value::Float(av + bv),
                        _ => return Err(format!("Invalid operand types for ADD: {:?} + {:?}", a, b)),
                    };
                    stack.push(res);
                    ip += 1;
                }

                OP_SUB => {
                    let b = stack.pop().ok_or("Stack underflow during SUB second operand")?;
                    let a = stack.pop().ok_or("Stack underflow during SUB first operand")?;
                    let res = match (&a, &b) {
                        (Value::Decimal { value: av, scale: as_ }, Value::Decimal { value: bv, scale: bs }) => {
                            let da = Decimal::new(*av, *as_);
                            let db = Decimal::new(*bv, *bs);
                            match da.sub(&db) {
                                Ok(res_dec) => Value::Decimal { value: res_dec.value, scale: res_dec.scale },
                                Err(e) => return Err(e),
                            }
                        }
                        (Value::Integer(av), Value::Integer(bv)) => Value::Integer(av - bv),
                        (Value::Float(av), Value::Float(bv)) => Value::Float(av - bv),
                        _ => return Err(format!("Invalid operand types for SUB: {:?} - {:?}", a, b)),
                    };
                    stack.push(res);
                    ip += 1;
                }

                OP_MUL => {
                    let b = stack.pop().ok_or("Stack underflow during MUL second operand")?;
                    let a = stack.pop().ok_or("Stack underflow during MUL first operand")?;
                    let res = match (&a, &b) {
                        (Value::Decimal { value: av, scale: as_ }, Value::Decimal { value: bv, scale: bs }) => {
                            let da = Decimal::new(*av, *as_);
                            let db = Decimal::new(*bv, *bs);
                            let res_dec = da.mul(&db);
                            Value::Decimal { value: res_dec.value, scale: res_dec.scale }
                        }
                        (Value::Integer(av), Value::Integer(bv)) => Value::Integer(av * bv),
                        (Value::Float(av), Value::Float(bv)) => Value::Float(av * bv),
                        _ => return Err(format!("Invalid operand types for MUL: {:?} * {:?}", a, b)),
                    };
                    stack.push(res);
                    ip += 1;
                }

                OP_DIV => {
                    let b = stack.pop().ok_or("Stack underflow during DIV second operand")?;
                    let a = stack.pop().ok_or("Stack underflow during DIV first operand")?;
                    let res = match (&a, &b) {
                        (Value::Decimal { value: av, scale: as_ }, Value::Decimal { value: bv, scale: bs }) => {
                            let da = Decimal::new(*av, *as_);
                            let db = Decimal::new(*bv, *bs);
                            match da.div(&db) {
                                Ok(res_dec) => Value::Decimal { value: res_dec.value, scale: res_dec.scale },
                                Err(e) => return Err(e),
                            }
                        }
                        (Value::Integer(av), Value::Integer(bv)) => {
                            if *bv == 0 {
                                return Err("Division by zero".to_string());
                            }
                            Value::Integer(av / bv)
                        }
                        (Value::Float(av), Value::Float(bv)) => {
                            if *bv == 0.0 {
                                return Err("Division by zero".to_string());
                            }
                            Value::Float(av / bv)
                        }
                        _ => return Err(format!("Invalid operand types for DIV: {:?} / {:?}", a, b)),
                    };
                    stack.push(res);
                    ip += 1;
                }

                OP_EQ => {
                    let b = stack.pop().ok_or("Stack underflow during EQ second operand")?;
                    let a = stack.pop().ok_or("Stack underflow during EQ first operand")?;
                    stack.push(Value::Bool(a == b));
                    ip += 1;
                }

                OP_GT => {
                    let b = stack.pop().ok_or("Stack underflow during GT second operand")?;
                    let a = stack.pop().ok_or("Stack underflow during GT first operand")?;
                    let res = match (&a, &b) {
                        (Value::Decimal { value: av, scale: as_ }, Value::Decimal { value: bv, scale: bs }) => {
                            let da = Decimal::new(*av, *as_);
                            let db = Decimal::new(*bv, *bs);
                            Value::Bool(da.to_f64() > db.to_f64())
                        }
                        (Value::Integer(av), Value::Integer(bv)) => Value::Bool(av > bv),
                        (Value::Float(av), Value::Float(bv)) => Value::Bool(av > bv),
                        _ => return Err(format!("Invalid operand types for GT: {:?} > {:?}", a, b)),
                    };
                    stack.push(res);
                    ip += 1;
                }

                OP_LT => {
                    let b = stack.pop().ok_or("Stack underflow during LT second operand")?;
                    let a = stack.pop().ok_or("Stack underflow during LT first operand")?;
                    let res = match (&a, &b) {
                        (Value::Decimal { value: av, scale: as_ }, Value::Decimal { value: bv, scale: bs }) => {
                            let da = Decimal::new(*av, *as_);
                            let db = Decimal::new(*bv, *bs);
                            Value::Bool(da.to_f64() < db.to_f64())
                        }
                        (Value::Integer(av), Value::Integer(bv)) => Value::Bool(av < bv),
                        (Value::Float(av), Value::Float(bv)) => Value::Bool(av < bv),
                        (Value::String(av), Value::String(bv)) => Value::Bool(av < bv),
                        _ => return Err(format!("Invalid operand types for LT: {:?} < {:?}", a, b)),
                    };
                    stack.push(res);
                    ip += 1;
                }

                OP_LE => {
                    let b = stack.pop().ok_or("Stack underflow during LE second operand")?;
                    let a = stack.pop().ok_or("Stack underflow during LE first operand")?;
                    let res = match (&a, &b) {
                        (Value::Decimal { value: av, scale: as_ }, Value::Decimal { value: bv, scale: bs }) => {
                            let da = Decimal::new(*av, *as_);
                            let db = Decimal::new(*bv, *bs);
                            Value::Bool(da.to_f64() <= db.to_f64())
                        }
                        (Value::Integer(av), Value::Integer(bv)) => Value::Bool(av <= bv),
                        (Value::Float(av), Value::Float(bv)) => Value::Bool(av <= bv),
                        (Value::String(av), Value::String(bv)) => Value::Bool(av <= bv),
                        _ => return Err(format!("Invalid operand types for LE: {:?} <= {:?}", a, b)),
                    };
                    stack.push(res);
                    ip += 1;
                }

                OP_GE => {
                    let b = stack.pop().ok_or("Stack underflow during GE second operand")?;
                    let a = stack.pop().ok_or("Stack underflow during GE first operand")?;
                    let res = match (&a, &b) {
                        (Value::Decimal { value: av, scale: as_ }, Value::Decimal { value: bv, scale: bs }) => {
                            let da = Decimal::new(*av, *as_);
                            let db = Decimal::new(*bv, *bs);
                            Value::Bool(da.to_f64() >= db.to_f64())
                        }
                        (Value::Integer(av), Value::Integer(bv)) => Value::Bool(av >= bv),
                        (Value::Float(av), Value::Float(bv)) => Value::Bool(av >= bv),
                        (Value::String(av), Value::String(bv)) => Value::Bool(av >= bv),
                        _ => return Err(format!("Invalid operand types for GE: {:?} >= {:?}", a, b)),
                    };
                    stack.push(res);
                    ip += 1;
                }

                OP_NE => {
                    let b = stack.pop().ok_or("Stack underflow during NE second operand")?;
                    let a = stack.pop().ok_or("Stack underflow during NE first operand")?;
                    stack.push(Value::Bool(a != b));
                    ip += 1;
                }

                OP_AND => {
                    let b = stack.pop().ok_or("Stack underflow during AND second operand")?;
                    let a = stack.pop().ok_or("Stack underflow during AND first operand")?;
                    let res = match (&a, &b) {
                        (Value::Bool(av), Value::Bool(bv)) => Value::Bool(*av && *bv),
                        _ => return Err(format!("Invalid operand types for AND: {:?} && {:?}", a, b)),
                    };
                    stack.push(res);
                    ip += 1;
                }

                OP_OR => {
                    let b = stack.pop().ok_or("Stack underflow during OR second operand")?;
                    let a = stack.pop().ok_or("Stack underflow during OR first operand")?;
                    let res = match (&a, &b) {
                        (Value::Bool(av), Value::Bool(bv)) => Value::Bool(*av || *bv),
                        _ => return Err(format!("Invalid operand types for OR: {:?} || {:?}", a, b)),
                    };
                    stack.push(res);
                    ip += 1;
                }

                OP_NOT => {
                    let a = stack.pop().ok_or("Stack underflow during NOT operand")?;
                    let res = match &a {
                        Value::Bool(av) => Value::Bool(!*av),
                        _ => return Err(format!("Invalid operand type for NOT: {:?}", a)),
                    };
                    stack.push(res);
                    ip += 1;
                }

                OP_CONCAT => {
                    let b = stack.pop().ok_or("Stack underflow during CONCAT second operand")?;
                    let a = stack.pop().ok_or("Stack underflow during CONCAT first operand")?;
                    let res = match (&a, &b) {
                        (Value::String(av), Value::String(bv)) => {
                            let mut s = av.to_string();
                            s.push_str(bv);
                            Value::String(Arc::from(s.as_str()))
                        }
                        (Value::Array(av), Value::Array(bv)) => {
                            let mut list = (**av).clone();
                            list.extend_from_slice(bv);
                            Value::Array(Arc::new(list))
                        }
                        _ => return Err(format!("Invalid operand types for CONCAT: {:?} ++ {:?}", a, b)),
                    };
                    stack.push(res);
                    ip += 1;
                }

                OP_PUSH_ARRAY => {
                    let count = inst.args.get(0)
                        .ok_or("Missing element count argument for PUSH_ARRAY")?
                        .as_integer()?;
                    if count < 0 {
                        return Err(format!("Invalid negative element count for PUSH_ARRAY: {}", count));
                    }
                    let mut items = Vec::with_capacity(count as usize);
                    for _ in 0..count {
                        let item = stack.pop().ok_or("Stack underflow during PUSH_ARRAY")?;
                        items.push(item);
                    }
                    items.reverse();
                    stack.push(Value::Array(Arc::new(items)));
                    ip += 1;
                }

                OP_PUSH_RECORD => {
                    let key_count = inst.args.get(0)
                        .ok_or("Missing key count argument for PUSH_RECORD")?
                        .as_integer()?;
                    if key_count < 0 {
                        return Err(format!("Invalid negative key count for PUSH_RECORD: {}", key_count));
                    }
                    let mut map = std::collections::BTreeMap::new();
                    for i in (0..key_count).rev() {
                        let key_val = inst.args.get((i + 1) as usize)
                            .ok_or("Missing key string for PUSH_RECORD")?;
                        let key_str = key_val.as_str()?;
                        let val = stack.pop().ok_or("Stack underflow during PUSH_RECORD")?;
                        map.insert(key_str.to_string(), val);
                    }
                    stack.push(Value::Record(Arc::new(map)));
                    ip += 1;
                }

                OP_CALL => {
                    let fn_name_val = inst.args.get(0).ok_or("Missing function name for OP_CALL")?;
                    let fn_name = fn_name_val.as_str()?;
                    let arg_count = inst.args.get(1).ok_or("Missing arg count for OP_CALL")?.as_integer()?;
                    
                    let mut args = Vec::with_capacity(arg_count as usize);
                    for _ in 0..arg_count {
                        args.push(stack.pop().ok_or("Stack underflow during OP_CALL")?);
                    }
                    args.reverse();
                    
                    // Closure captures (LAB-VM-HOF-CLOSURE-CONVERSION-P1): if any arg is
                    // a lambda carrying a `captures` list, resolve those enclosing compute
                    // registers and expose them to the lambda body via `inputs` (which
                    // eval_ast's `ref` resolution already consults). One chokepoint covers
                    // every HOF arm. Inputs flow through unchanged; only computes are added.
                    // Recursively collect captures from the lambda arg AND any nested
                    // lambdas in its body — all reference the current contract's registers.
                    let mut captured: HashMap<String, Value> = HashMap::new();
                    for a in &args {
                        if let Value::String(s) = a {
                            if s.starts_with('{') {
                                if let Ok(la) = serde_json::from_str::<serde_json::Value>(s) {
                                    collect_captures(&la, &registers, &mut captured);
                                }
                            }
                        }
                    }
                    let aug_inputs;
                    let inputs: &HashMap<String, Value> = if captured.is_empty() {
                        inputs
                    } else {
                        let mut m = inputs.clone();
                        for (k, v) in captured { m.insert(k, v); }
                        aug_inputs = m;
                        &aug_inputs
                    };

                    // stdlib.collection.* namespaced aliases -> existing bare handlers.
                    // The compiler emits namespaced names; the VM historically matched
                    // bare names. (Same alignment the text.* ops already received.)
                    let fn_name = match fn_name {
                        "stdlib.collection.filter" => "filter",
                        "stdlib.collection.map"    => "map",
                        "stdlib.collection.fold"   => "fold",
                        "stdlib.collection.reduce" => "reduce",
                        "stdlib.collection.count"  => "count",
                        "stdlib.collection.range"  => "range",
                        "stdlib.collection.first"  => "first",
                        "stdlib.collection.last"   => "last",
                        "stdlib.collection.sum"    => "sum",
                        "stdlib.collection.take"   => "take",
                        "stdlib.collection.zip"    => "zip",
                        "stdlib.collection.any"    => "any",
                        "stdlib.collection.all"    => "all",
                        "stdlib.collection.find"   => "find",
                        "stdlib.string.concat"     => "concat",
                        other => other,
                    };

                    let res = match fn_name {
                        "stdlib.IO.read_text" => {
                            if args.len() != 2 {
                                return Err(format!("stdlib.IO.read_text expects 2 arguments, got {}", args.len()));
                            }
                            let path_str = args[0].as_str()?;
                            let cap_name = args[1].as_str()?;
                            
                            let grant = resolved_grants.get(cap_name)
                                .ok_or_else(|| format!("AmbientAccessViolation: Stack frame does not possess capability grant '{}'", cap_name))?;
                                
                            if !grant.read_allowed {
                                return Err(format!("CapabilityError: Local grant '{}' does not allow read", cap_name));
                            }
                            
                            let cap_json = serde_json::to_string(grant).map_err(|e| e.to_string())?;
                            
                            let c_path = std::ffi::CString::new(path_str).map_err(|e| e.to_string())?;
                            let c_cap_json = std::ffi::CString::new(cap_json).map_err(|e| e.to_string())?;
                            
                            let res_ptr = unsafe {
                                igniter_stdlib::io::stdlib_io_read_text(c_path.as_ptr(), c_cap_json.as_ptr())
                            };
                            if res_ptr.is_null() {
                                return Err("C ABI function returned null".to_string());
                            }
                            let res_c_str = unsafe { std::ffi::CStr::from_ptr(res_ptr) };
                            let res_str = res_c_str.to_string_lossy().into_owned();
                            unsafe {
                                igniter_stdlib::io::stdlib_io_free_string(res_ptr);
                            }
                            
                            let res_val: serde_json::Value = serde_json::from_str(&res_str)
                                .map_err(|e| format!("Failed to parse stdlib response: {}", e))?;
                                
                            if let Some(err) = res_val.get("err") {
                                return Err(format!("FFI Read error: {:?}", err));
                            }
                            
                            // Capture observation
                            let mut metadata = res_val.get("metadata")
                                .and_then(|v| v.as_object())
                                .cloned()
                                .unwrap_or_default();
                            metadata.insert("delegation_chain".to_string(), serde_json::json!(grant.capability_id));
                            let obs_id = format!("obs/io-read/{}", uuid::Uuid::new_v4().to_string().replace("-", "")[0..16].to_string());
                            metadata.insert("observation_id".to_string(), serde_json::json!(obs_id));
                            metadata.insert("kind".to_string(), serde_json::json!("io_read_observation"));
                            
                            let mut sink = self.observation_sink.lock().await;
                            sink.push(serde_json::Value::Object(metadata));
                            
                            let ok_str = res_val.get("ok").and_then(|v| v.as_str()).ok_or("Invalid FFI response")?;
                            Value::String(Arc::from(ok_str))
                        }

                        "stdlib.IO.write_text" => {
                            if args.len() != 3 {
                                return Err(format!("stdlib.IO.write_text expects 3 arguments, got {}", args.len()));
                            }
                            let path_str = args[0].as_str()?;
                            let content_str = args[1].as_str()?;
                            let cap_name = args[2].as_str()?;
                            
                            let grant = resolved_grants.get(cap_name)
                                .ok_or_else(|| format!("AmbientAccessViolation: Stack frame does not possess capability grant '{}'", cap_name))?;
                                
                            if !grant.write_allowed {
                                return Err(format!("CapabilityError: Local grant '{}' does not allow write", cap_name));
                            }
                            
                            let cap_json = serde_json::to_string(grant).map_err(|e| e.to_string())?;
                            
                            let c_path = std::ffi::CString::new(path_str).map_err(|e| e.to_string())?;
                            let c_content = std::ffi::CString::new(content_str).map_err(|e| e.to_string())?;
                            let c_cap_json = std::ffi::CString::new(cap_json).map_err(|e| e.to_string())?;
                            
                            let res_ptr = unsafe {
                                igniter_stdlib::io::stdlib_io_write_text(c_path.as_ptr(), c_content.as_ptr(), c_cap_json.as_ptr())
                            };
                            if res_ptr.is_null() {
                                return Err("C ABI function returned null".to_string());
                            }
                            let res_c_str = unsafe { std::ffi::CStr::from_ptr(res_ptr) };
                            let res_str = res_c_str.to_string_lossy().into_owned();
                            unsafe {
                                igniter_stdlib::io::stdlib_io_free_string(res_ptr);
                            }
                            
                            let res_val: serde_json::Value = serde_json::from_str(&res_str)
                                .map_err(|e| format!("Failed to parse stdlib response: {}", e))?;
                                
                            if let Some(err) = res_val.get("err") {
                                return Err(format!("FFI Write error: {:?}", err));
                            }
                            
                            // Capture receipt
                            let mut ok_obj = res_val.get("ok")
                                .and_then(|v| v.as_object())
                                .cloned()
                                .unwrap_or_default();
                            ok_obj.insert("delegation_chain".to_string(), serde_json::json!(grant.capability_id));
                            let receipt_id = format!("rcpt/io-write/{}", uuid::Uuid::new_v4().to_string().replace("-", "")[0..16].to_string());
                            ok_obj.insert("receipt_id".to_string(), serde_json::json!(receipt_id));
                            ok_obj.insert("kind".to_string(), serde_json::json!("io_write_receipt"));
                            
                            let mut sink = self.observation_sink.lock().await;
                            sink.push(serde_json::Value::Object(ok_obj.clone()));
                            
                            Value::from_json(&serde_json::Value::Object(ok_obj))
                        }

                        "count" => {
                            if args.len() != 1 {
                                return Err(format!("count expects exactly 1 argument, got {}", args.len()));
                            }
                            match &args[0] {
                                Value::Array(a) => Value::Integer(a.len() as i64),
                                Value::Nil => Value::Integer(0),
                                _ => return Err("count argument must be an array".to_string()),
                            }
                        }
                        "length" => {
                            if args.len() != 1 {
                                return Err(format!("length expects exactly 1 argument, got {}", args.len()));
                            }
                            let s = args[0].as_str()?;
                            Value::Integer(s.len() as i64)
                        }
                        "concat" => {
                            if args.len() != 2 {
                                return Err(format!("concat expects exactly 2 arguments, got {}", args.len()));
                            }
                            match (&args[0], &args[1]) {
                                (Value::Array(a), Value::Array(b)) => {
                                    let mut merged: Vec<Value> = a.iter().cloned().collect();
                                    merged.extend(b.iter().cloned());
                                    Value::Array(Arc::new(merged))
                                }
                                _ => {
                                    let a = args[0].as_str()?;
                                    let b = args[1].as_str()?;
                                    Value::String(Arc::from(format!("{}{}", a, b)))
                                }
                            }
                        }
                        "trim" => {
                            if args.len() != 1 {
                                return Err(format!("trim expects exactly 1 argument, got {}", args.len()));
                            }
                            let s = args[0].as_str()?;
                            Value::String(Arc::from(s.trim()))
                        }
                        "split" => {
                            if args.len() != 2 {
                                return Err(format!("split expects exactly 2 arguments, got {}", args.len()));
                            }
                            let s = args[0].as_str()?;
                            let sep = args[1].as_str()?;
                            // LAB-STR-UNICODE-P3: align bare handler with stdlib.text.split policy
                            // empty delimiter is an operational error (v0 policy); no bypass via legacy name
                            if sep.is_empty() {
                                return Err("split: empty delimiter is an operational error (v0 policy)".to_string());
                            }
                            let parts: Vec<Value> = s.split(sep).map(|p| Value::String(Arc::from(p))).collect();
                            Value::Array(Arc::new(parts))
                        }
                        "contains" => {
                            if args.len() != 2 {
                                return Err(format!("contains expects exactly 2 arguments, got {}", args.len()));
                            }
                            let s = args[0].as_str()?;
                            let sub = args[1].as_str()?;
                            Value::Bool(s.contains(sub))
                        }
                        "starts_with" => {
                            if args.len() != 2 {
                                return Err(format!("starts_with expects exactly 2 arguments, got {}", args.len()));
                            }
                            let s = args[0].as_str()?;
                            let prefix = args[1].as_str()?;
                            Value::Bool(s.starts_with(prefix))
                        }
                        // stdlib.text.* namespaced aliases — compiler emits these after Text/String Core update
                        // LAB-RACK-P5: align VM OP_CALL dispatch with compiler stdlib.text.* naming
                        "stdlib.text.starts_with" => {
                            if args.len() != 2 {
                                return Err(format!("stdlib.text.starts_with expects exactly 2 arguments, got {}", args.len()));
                            }
                            let s = args[0].as_str()?;
                            let prefix = args[1].as_str()?;
                            Value::Bool(s.starts_with(prefix))
                        }
                        "stdlib.text.split" => {
                            if args.len() != 2 {
                                return Err(format!("stdlib.text.split expects exactly 2 arguments, got {}", args.len()));
                            }
                            let s = args[0].as_str()?;
                            let sep = args[1].as_str()?;
                            // LAB-STR-UNICODE-P2: empty delimiter is an operational error (policy v0)
                            if sep.is_empty() {
                                return Err("stdlib.text.split: empty delimiter is an operational error (v0 policy)".to_string());
                            }
                            let parts: Vec<Value> = s.split(sep).map(|p| Value::String(Arc::from(p))).collect();
                            Value::Array(Arc::new(parts))
                        }
                        "stdlib.text.byte_length" => {
                            if args.len() != 1 {
                                return Err(format!("stdlib.text.byte_length expects exactly 1 argument, got {}", args.len()));
                            }
                            let s = args[0].as_str()?;
                            Value::Integer(s.len() as i64)
                        }
                        // ── LAB-STR-UNICODE-P2: Unicode Text runtime ops ────────────────────
                        // lab-text-unicode-runtime-ops-implementation-proof-v0
                        // Policy: Text = valid UTF-8; rune = Unicode scalar; grapheme = UAX #29
                        "stdlib.text.rune_length" => {
                            if args.len() != 1 {
                                return Err(format!("stdlib.text.rune_length expects exactly 1 argument, got {}", args.len()));
                            }
                            let s = args[0].as_str()?;
                            Value::Integer(s.chars().count() as i64)
                        }
                        "stdlib.text.grapheme_length" => {
                            if args.len() != 1 {
                                return Err(format!("stdlib.text.grapheme_length expects exactly 1 argument, got {}", args.len()));
                            }
                            let s = args[0].as_str()?;
                            Value::Integer(s.graphemes(true).count() as i64)
                        }
                        "stdlib.text.byte_slice" => {
                            if args.len() != 3 {
                                return Err(format!("stdlib.text.byte_slice expects exactly 3 arguments, got {}", args.len()));
                            }
                            let s = args[0].as_str()?;
                            let raw_start = args[1].as_integer()?;
                            let raw_end   = args[2].as_integer()?;
                            let byte_len  = s.len() as i64;
                            let start = raw_start.max(0).min(byte_len) as usize;
                            let end   = raw_end.max(0).min(byte_len) as usize;
                            if start >= end {
                                Value::String(Arc::from(""))
                            } else {
                                // fail-closed: invalid UTF-8 boundary → ""
                                Value::String(Arc::from(s.get(start..end).unwrap_or("")))
                            }
                        }
                        "stdlib.text.rune_slice" => {
                            if args.len() != 3 {
                                return Err(format!("stdlib.text.rune_slice expects exactly 3 arguments, got {}", args.len()));
                            }
                            let s = args[0].as_str()?;
                            let raw_start = args[1].as_integer()?;
                            let raw_end   = args[2].as_integer()?;
                            let rune_count = s.chars().count() as i64;
                            let start = raw_start.max(0).min(rune_count) as usize;
                            let end   = raw_end.max(0).min(rune_count) as usize;
                            if start >= end {
                                Value::String(Arc::from(""))
                            } else {
                                let result: String = s.chars().skip(start).take(end - start).collect();
                                Value::String(Arc::from(result.as_str()))
                            }
                        }
                        "stdlib.text.grapheme_slice" => {
                            if args.len() != 3 {
                                return Err(format!("stdlib.text.grapheme_slice expects exactly 3 arguments, got {}", args.len()));
                            }
                            let s = args[0].as_str()?;
                            let raw_start = args[1].as_integer()?;
                            let raw_end   = args[2].as_integer()?;
                            let graphemes: Vec<&str> = s.graphemes(true).collect();
                            let g_count = graphemes.len() as i64;
                            let start = raw_start.max(0).min(g_count) as usize;
                            let end   = raw_end.max(0).min(g_count) as usize;
                            if start >= end {
                                Value::String(Arc::from(""))
                            } else {
                                Value::String(Arc::from(graphemes[start..end].join("")))
                            }
                        }
                        "stdlib.text.ends_with" => {
                            if args.len() != 2 {
                                return Err(format!("stdlib.text.ends_with expects exactly 2 arguments, got {}", args.len()));
                            }
                            let s      = args[0].as_str()?;
                            let suffix = args[1].as_str()?;
                            Value::Bool(s.ends_with(suffix))
                        }
                        "stdlib.text.replace" => {
                            if args.len() != 3 {
                                return Err(format!("stdlib.text.replace expects exactly 3 arguments, got {}", args.len()));
                            }
                            let s           = args[0].as_str()?;
                            let pattern     = args[1].as_str()?;
                            let replacement = args[2].as_str()?;
                            if pattern.is_empty() {
                                return Err("stdlib.text.replace: empty pattern is an operational error (v0 policy)".to_string());
                            }
                            Value::String(Arc::from(s.replacen(pattern, replacement, 1).as_str()))
                        }
                        "stdlib.text.replace_all" => {
                            if args.len() != 3 {
                                return Err(format!("stdlib.text.replace_all expects exactly 3 arguments, got {}", args.len()));
                            }
                            let s           = args[0].as_str()?;
                            let pattern     = args[1].as_str()?;
                            let replacement = args[2].as_str()?;
                            if pattern.is_empty() {
                                return Err("stdlib.text.replace_all: empty pattern is an operational error (v0 policy)".to_string());
                            }
                            Value::String(Arc::from(s.replace(pattern, replacement).as_str()))
                        }
                        // Qualified aliases for ops with bare-name legacy handlers.
                        // Compiler emits stdlib.text.* names; these aliases bridge legacy bare-name handlers.
                        "stdlib.text.concat" => {
                            if args.len() != 2 {
                                return Err(format!("stdlib.text.concat expects exactly 2 arguments, got {}", args.len()));
                            }
                            let a = args[0].as_str()?;
                            let b = args[1].as_str()?;
                            Value::String(Arc::from(format!("{}{}", a, b)))
                        }
                        "stdlib.text.trim" => {
                            if args.len() != 1 {
                                return Err(format!("stdlib.text.trim expects exactly 1 argument, got {}", args.len()));
                            }
                            let s = args[0].as_str()?;
                            Value::String(Arc::from(s.trim()))
                        }
                        "stdlib.text.contains" => {
                            if args.len() != 2 {
                                return Err(format!("stdlib.text.contains expects exactly 2 arguments, got {}", args.len()));
                            }
                            let s   = args[0].as_str()?;
                            let sub = args[1].as_str()?;
                            Value::Bool(s.contains(sub))
                        }
                        "stdlib.collection.concat" => {
                            if args.len() != 2 {
                                return Err(format!("stdlib.collection.concat expects exactly 2 arguments, got {}", args.len()));
                            }
                            match (&args[0], &args[1]) {
                                (Value::Array(a), Value::Array(b)) => {
                                    let mut merged: Vec<Value> = a.iter().cloned().collect();
                                    merged.extend(b.iter().cloned());
                                    Value::Array(Arc::new(merged))
                                }
                                _ => return Err("stdlib.collection.concat: both arguments must be collections".to_string()),
                            }
                        }
                        // ── end LAB-STR-UNICODE-P2 ──────────────────────────────────────────
                        "diff_seconds" => {
                            if args.len() != 2 {
                                return Err(format!("diff_seconds expects exactly 2 arguments, got {}", args.len()));
                            }
                            let dt1_str = args[0].as_str()?;
                            let dt2_str = args[1].as_str()?;
                            let t1 = parse_utc(dt1_str)?;
                            let t2 = parse_utc(dt2_str)?;
                            Value::Integer((t1 - t2).num_seconds())
                        }
                        "add_seconds" => {
                            if args.len() != 2 {
                                return Err(format!("add_seconds expects exactly 2 arguments, got {}", args.len()));
                            }
                            let dt_str = args[0].as_str()?;
                            let seconds = args[1].as_integer()?;
                            let t = parse_utc(dt_str)?;
                            let added = t + chrono::Duration::seconds(seconds);
                            Value::String(Arc::from(added.format("%Y-%m-%dT%H:%M:%SZ").to_string()))
                        }
                        "parse_datetime" => {
                            if args.len() != 2 {
                                return Err(format!("parse_datetime expects exactly 2 arguments, got {}", args.len()));
                            }
                            let s = args[0].as_str()?;
                            let fmt = args[1].as_str()?;
                            if let Ok(dt) = chrono::DateTime::parse_from_str(s, fmt) {
                                let utc_dt = dt.with_timezone(&chrono::Utc);
                                Value::String(Arc::from(utc_dt.format("%Y-%m-%dT%H:%M:%SZ").to_string()))
                            } else if let Ok(ndt) = chrono::NaiveDateTime::parse_from_str(s, fmt) {
                                let dt = ndt.and_utc();
                                Value::String(Arc::from(dt.format("%Y-%m-%dT%H:%M:%SZ").to_string()))
                            } else if let Ok(nd) = chrono::NaiveDate::parse_from_str(s, fmt) {
                                if let Some(ndt) = nd.and_hms_opt(0, 0, 0) {
                                    let dt = ndt.and_utc();
                                    Value::String(Arc::from(dt.format("%Y-%m-%dT%H:%M:%SZ").to_string()))
                                } else {
                                    Value::Nil
                                }
                            } else {
                                Value::Nil
                            }
                        }
                        "format_datetime" => {
                            if args.len() != 2 {
                                return Err(format!("format_datetime expects exactly 2 arguments, got {}", args.len()));
                            }
                            let dt_str = args[0].as_str()?;
                            let fmt = args[1].as_str()?;
                            let t = parse_utc(dt_str)?;
                            Value::String(Arc::from(t.format(fmt).to_string()))
                        }
                        "is_before" => {
                            if args.len() != 2 {
                                return Err(format!("is_before expects exactly 2 arguments, got {}", args.len()));
                            }
                            let dt1_str = args[0].as_str()?;
                            let dt2_str = args[1].as_str()?;
                            let t1 = parse_utc(dt1_str)?;
                            let t2 = parse_utc(dt2_str)?;
                            Value::Bool(t1 < t2)
                        }
                        "is_after" => {
                            if args.len() != 2 {
                                return Err(format!("is_after expects exactly 2 arguments, got {}", args.len()));
                            }
                            let dt1_str = args[0].as_str()?;
                            let dt2_str = args[1].as_str()?;
                            let t1 = parse_utc(dt1_str)?;
                            let t2 = parse_utc(dt2_str)?;
                            Value::Bool(t1 > t2)
                        }
                        "first" => {
                            if args.len() != 1 {
                                return Err(format!("first expects exactly 1 argument, got {}", args.len()));
                            }
                            match &args[0] {
                                Value::Array(a) => a.first().cloned().unwrap_or(Value::Nil),
                                Value::Nil => Value::Nil,
                                _ => return Err("first argument must be an array".to_string()),
                            }
                        }
                        "last" => {
                            if args.len() != 1 {
                                return Err(format!("last expects exactly 1 argument, got {}", args.len()));
                            }
                            match &args[0] {
                                Value::Array(a) => a.last().cloned().unwrap_or(Value::Nil),
                                Value::Nil => Value::Nil,
                                _ => return Err("last argument must be an array".to_string()),
                            }
                        }
                        "sum" => {
                            if args.len() != 2 {
                                return Err(format!("sum expects exactly 2 arguments, got {}", args.len()));
                            }
                            let array = match &args[0] {
                                Value::Array(a) => a,
                                Value::Nil => &Arc::new(Vec::new()),
                                _ => return Err("sum first argument must be an array".to_string()),
                            };
                            let field = args[1].as_str()?;
                            let mut sum_integer = 0i64;
                            let mut sum_decimal = Decimal::new(0, 0);
                            let mut has_integer = false;
                            let mut has_decimal = false;

                            for item in array.iter() {
                                let val = match item {
                                    Value::Record(map) => map.get(field).cloned().unwrap_or(Value::Nil),
                                    _ => return Err("sum expects record items in array".to_string()),
                                };
                                match val {
                                    Value::Integer(i) => {
                                        sum_integer += i;
                                        has_integer = true;
                                    }
                                    Value::Decimal { value: v, scale: s } => {
                                        if !has_decimal {
                                            sum_decimal = Decimal::new(0, s);
                                            has_decimal = true;
                                        }
                                        let d = Decimal::new(v, s);
                                        sum_decimal = sum_decimal.add(&d)?;
                                    }
                                    Value::Nil => {}
                                    _ => return Err(format!("Unsupported type for sum: {:?}", val)),
                                }
                            }
                            if has_decimal {
                                Value::Decimal { value: sum_decimal.value, scale: sum_decimal.scale }
                            } else {
                                Value::Integer(sum_integer)
                            }
                        }
                        "take" => {
                            if args.len() != 2 {
                                return Err(format!("take expects exactly 2 arguments, got {}", args.len()));
                            }
                            let array = match &args[0] {
                                Value::Array(a) => a,
                                _ => return Err("take first argument must be an array".to_string()),
                            };
                            let n = args[1].as_integer()?;
                            if n <= 0 {
                                Value::Array(Arc::new(Vec::new()))
                            } else {
                                let limit = std::cmp::min(n as usize, array.len());
                                Value::Array(Arc::new(array[0..limit].to_vec()))
                            }
                        }
                        "avg" => {
                            if args.len() != 2 {
                                return Err(format!("avg expects exactly 2 arguments, got {}", args.len()));
                            }
                            let array = match &args[0] {
                                Value::Array(a) => a,
                                _ => return Err("avg first argument must be an array".to_string()),
                            };
                            if array.is_empty() {
                                Value::Nil
                            } else {
                                let field = args[1].as_str()?;
                                let mut sum_integer = 0i64;
                                let mut sum_decimal = Decimal::new(0, 0);
                                let mut has_integer = false;
                                let mut has_decimal = false;
                                let mut count = 0i64;

                                for item in array.iter() {
                                    let val = match item {
                                        Value::Record(map) => map.get(field).cloned().unwrap_or(Value::Nil),
                                        _ => return Err("avg expects record items in array".to_string()),
                                    };
                                    match val {
                                        Value::Integer(i) => {
                                            sum_integer += i;
                                            has_integer = true;
                                            count += 1;
                                        }
                                        Value::Decimal { value: v, scale: s } => {
                                            if !has_decimal {
                                                sum_decimal = Decimal::new(0, s);
                                                has_decimal = true;
                                            }
                                            let d = Decimal::new(v, s);
                                            sum_decimal = sum_decimal.add(&d)?;
                                            count += 1;
                                        }
                                        Value::Nil => {}
                                        _ => return Err(format!("Unsupported type for avg: {:?}", val)),
                                    }
                                }

                                if count == 0 {
                                    Value::Nil
                                } else if has_decimal {
                                    Value::Decimal { value: sum_decimal.value / count, scale: sum_decimal.scale }
                                } else {
                                    Value::Integer(sum_integer / count)
                                }
                            }
                        }
                        "min" | "max" => {
                            if args.len() != 2 {
                                return Err(format!("min/max expects exactly 2 arguments, got {}", args.len()));
                            }
                            let array = match &args[0] {
                                Value::Array(a) => a,
                                _ => return Err("min/max first argument must be an array".to_string()),
                            };
                            if array.is_empty() {
                                Value::Nil
                            } else {
                                let field = args[1].as_str()?;
                                let mut extremum: Option<Value> = None;

                                for item in array.iter() {
                                    let val = match item {
                                        Value::Record(map) => map.get(field).cloned().unwrap_or(Value::Nil),
                                        _ => return Err("min/max expects record items".to_string()),
                                    };
                                    if val == Value::Nil { continue; }
                                    match &extremum {
                                        None => { extremum = Some(val); }
                                        Some(current) => {
                                            let is_better = match (fn_name, &val, current) {
                                                ("min", Value::Integer(x), Value::Integer(y)) => x < y,
                                                ("max", Value::Integer(x), Value::Integer(y)) => x > y,
                                                ("min", Value::Decimal { value: av, scale: as_ }, Value::Decimal { value: bv, scale: bs }) => {
                                                    ((*av as f64) / 10f64.powi(*as_ as i32)) < ((*bv as f64) / 10f64.powi(*bs as i32))
                                                }
                                                ("max", Value::Decimal { value: av, scale: as_ }, Value::Decimal { value: bv, scale: bs }) => {
                                                    ((*av as f64) / 10f64.powi(*as_ as i32)) > ((*bv as f64) / 10f64.powi(*bs as i32))
                                                }
                                                ("min", Value::Float(x), Value::Float(y)) => x < y,
                                                ("max", Value::Float(x), Value::Float(y)) => x > y,
                                                _ => false
                                            };
                                            if is_better {
                                                extremum = Some(val);
                                            }
                                        }
                                    }
                                }
                                extremum.unwrap_or(Value::Nil)
                            }
                        }
                        "zip" => {
                            if args.len() != 2 {
                                return Err(format!("zip expects exactly 2 arguments, got {}", args.len()));
                            }
                            let array_a = match &args[0] {
                                Value::Array(a) => a,
                                _ => return Err("zip first argument must be an array".to_string()),
                            };
                            let array_b = match &args[1] {
                                Value::Array(a) => a,
                                _ => return Err("zip second argument must be an array".to_string()),
                            };
                            let len = std::cmp::min(array_a.len(), array_b.len());
                            let mut zipped = Vec::with_capacity(len);
                            for i in 0..len {
                                let mut map = std::collections::BTreeMap::new();
                                map.insert("first".to_string(), array_a[i].clone());
                                map.insert("second".to_string(), array_b[i].clone());
                                zipped.push(Value::Record(Arc::new(map)));
                            }
                            Value::Array(Arc::new(zipped))
                        }
                        "range" => {
                            if args.len() != 2 {
                                return Err(format!("range expects exactly 2 arguments, got {}", args.len()));
                            }
                            let start = args[0].as_integer()?;
                            let end = args[1].as_integer()?;
                            let mut list = Vec::new();
                            for i in start..end {
                                list.push(Value::Integer(i));
                            }
                            Value::Array(Arc::new(list))
                        }
                        "stdlib.option.wrap" | "some" => {
                            if args.len() != 1 {
                                return Err(format!("some expects exactly 1 argument, got {}", args.len()));
                            }
                            args[0].clone()
                        }
                        "none" => {
                            if args.len() != 0 {
                                return Err(format!("none expects exactly 0 arguments, got {}", args.len()));
                            }
                            Value::Nil
                        }
                        "ok" => {
                            if args.len() != 1 {
                                return Err(format!("ok expects exactly 1 argument, got {}", args.len()));
                            }
                            let mut map = std::collections::BTreeMap::new();
                            map.insert("ok".to_string(), args[0].clone());
                            Value::Record(Arc::new(map))
                        }
                        "err" => {
                            if args.len() != 1 {
                                return Err(format!("err expects exactly 1 argument, got {}", args.len()));
                            }
                            let mut map = std::collections::BTreeMap::new();
                            map.insert("err".to_string(), args[0].clone());
                            Value::Record(Arc::new(map))
                        }
                        "is_some" | "some?" => {
                            if args.len() != 1 {
                                return Err(format!("is_some expects exactly 1 argument, got {}", args.len()));
                            }
                            Value::Bool(args[0] != Value::Nil)
                        }
                        "is_none" | "none?" => {
                            if args.len() != 1 {
                                return Err(format!("is_none expects exactly 1 argument, got {}", args.len()));
                            }
                            Value::Bool(args[0] == Value::Nil)
                        }
                        "is_ok" | "ok?" => {
                            if args.len() != 1 {
                                return Err(format!("is_ok expects exactly 1 argument, got {}", args.len()));
                            }
                            let is_ok = match &args[0] {
                                Value::Record(map) => map.contains_key("ok"),
                                _ => false,
                            };
                            Value::Bool(is_ok)
                        }
                        "is_err" | "err?" => {
                            if args.len() != 1 {
                                return Err(format!("is_err expects exactly 1 argument, got {}", args.len()));
                            }
                            let is_err = match &args[0] {
                                Value::Record(map) => map.contains_key("err"),
                                _ => false,
                            };
                            Value::Bool(is_err)
                        }
                        "unwrap" => {
                            if args.len() != 1 {
                                return Err(format!("unwrap expects exactly 1 argument, got {}", args.len()));
                            }
                            match &args[0] {
                                Value::Record(map) => {
                                    if let Some(ok_val) = map.get("ok") {
                                        ok_val.clone()
                                    } else {
                                        return Err(format!("Unwrapped Err: {:?}", args[0]));
                                    }
                                }
                                _ => return Err(format!("unwrap expects a Result, got {:?}", args[0])),
                            }
                        }
                        "or_else" | "unwrap_or" => {
                            if args.len() != 2 {
                                return Err(format!("{} expects exactly 2 arguments, got {}", fn_name, args.len()));
                            }
                            let val = &args[0];
                            let fallback = &args[1];
                            match val {
                                Value::Nil => fallback.clone(),
                                Value::Record(map) => {
                                    if map.contains_key("ok") {
                                        map.get("ok").unwrap().clone()
                                    } else if map.contains_key("err") {
                                        fallback.clone()
                                    } else {
                                        val.clone()
                                    }
                                }
                                _ => val.clone(),
                            }
                        }
                        "stdlib.numeric.add" | "add" => {
                            if args.len() != 2 {
                                return Err(format!("add expects exactly 2 arguments, got {}", args.len()));
                            }
                            match (&args[0], &args[1]) {
                                (Value::Decimal { value: av, scale: as_ }, Value::Decimal { value: bv, scale: bs }) => {
                                    let da = Decimal::new(*av, *as_);
                                    let db = Decimal::new(*bv, *bs);
                                    let res_dec = da.add(&db)?;
                                    Value::Decimal { value: res_dec.value, scale: res_dec.scale }
                                }
                                (Value::Integer(av), Value::Integer(bv)) => Value::Integer(av + bv),
                                (Value::Float(av), Value::Float(bv)) => Value::Float(av + bv),
                                _ => return Err(format!("Invalid operand types for add: {:?} + {:?}", args[0], args[1])),
                            }
                        }
                        "stdlib.integer.lt" | "stdlib.integer.gt" | "stdlib.integer.lte" | "stdlib.integer.gte" => {
                            if args.len() != 2 {
                                return Err(format!("{} expects exactly 2 arguments, got {}", fn_name, args.len()));
                            }
                            let a = args[0].as_integer()?;
                            let b = args[1].as_integer()?;
                            let r = match fn_name {
                                "stdlib.integer.lt"  => a < b,
                                "stdlib.integer.gt"  => a > b,
                                "stdlib.integer.lte" => a <= b,
                                _                    => a >= b,
                            };
                            Value::Bool(r)
                        }
                        "stdlib.collection.append" | "append" => {
                            if args.len() != 2 {
                                return Err(format!("append expects exactly 2 arguments, got {}", args.len()));
                            }
                            let mut list = match &args[0] {
                                Value::Array(a) => (**a).clone(),
                                Value::Nil => Vec::new(),
                                _ => return Err("append first argument must be an array".to_string()),
                            };
                            list.push(args[1].clone());
                            Value::Array(Arc::new(list))
                        }
                        "filter" => {
                            if args.len() != 2 {
                                return Err(format!("filter expects exactly 2 arguments, got {}", args.len()));
                            }
                            let array = match &args[0] {
                                Value::Array(a) => a,
                                _ => return Err("filter first argument must be an array".to_string()),
                            };
                            let lambda_str = args[1].as_str()?;
                            let lambda_ast: serde_json::Value = serde_json::from_str(lambda_str)
                                .map_err(|e| format!("Invalid lambda JSON in filter: {}", e))?;
                            
                            let params = lambda_ast.get("params")
                                .and_then(|p| p.as_array())
                                .ok_or("Missing params in lambda")?;
                            let param_name = params.first()
                                .and_then(|p| p.as_str())
                                .ok_or("Lambda must have at least one parameter")?;
                            let body = lambda_ast.get("body")
                                .ok_or("Missing body in lambda")?;
                            
                            let mut filtered = Vec::new();
                            for item in array.iter() {
                                let mut local_env = HashMap::new();
                                local_env.insert(param_name.to_string(), item.clone());
                                let cond_val = eval_ast(body, inputs, temporal_context, &local_env, &self.backend, self).await?;
                                if cond_val.as_bool()? {
                                    filtered.push(item.clone());
                                }
                            }
                            Value::Array(Arc::new(filtered))
                        }
                        "find" => {
                            if args.len() != 2 {
                                return Err(format!("find expects exactly 2 arguments, got {}", args.len()));
                            }
                            let array = match &args[0] {
                                Value::Array(a) => a,
                                Value::Nil => return Ok(Value::Nil),
                                _ => return Err("find first argument must be an array".to_string()),
                            };
                            let lambda_str = args[1].as_str()?;
                            let lambda_ast: serde_json::Value = serde_json::from_str(lambda_str)
                                .map_err(|e| format!("Invalid lambda JSON in find: {}", e))?;
                            let params = lambda_ast.get("params")
                                .and_then(|p| p.as_array())
                                .ok_or("Missing params in lambda")?;
                            let param_name = params.first()
                                .and_then(|p| p.as_str())
                                .ok_or("Lambda must have at least one parameter")?;
                            let body = lambda_ast.get("body")
                                .ok_or("Missing body in lambda")?;
                            let mut found = Value::Nil;
                            for item in array.iter() {
                                let mut local_env = HashMap::new();
                                local_env.insert(param_name.to_string(), item.clone());
                                let cond_val = eval_ast(body, inputs, temporal_context, &local_env, &self.backend, self).await?;
                                if cond_val.as_bool()? {
                                    found = item.clone();
                                    break;
                                }
                            }
                            found
                        }
                        "any" => {
                            if args.len() != 2 {
                                return Err(format!("any expects exactly 2 arguments, got {}", args.len()));
                            }
                            let array = match &args[0] {
                                Value::Array(a) => a,
                                Value::Nil => return Ok(Value::Bool(false)),
                                _ => return Err("any first argument must be an array".to_string()),
                            };
                            let lambda_str = args[1].as_str()?;
                            let lambda_ast: serde_json::Value = serde_json::from_str(lambda_str)
                                .map_err(|e| format!("Invalid lambda JSON in any: {}", e))?;
                            let params = lambda_ast.get("params")
                                .and_then(|p| p.as_array())
                                .ok_or("Missing params in lambda")?;
                            let param_name = params.first()
                                .and_then(|p| p.as_str())
                                .ok_or("Lambda must have at least one parameter")?;
                            let body = lambda_ast.get("body")
                                .ok_or("Missing body in lambda")?;
                            let mut result = false;
                            for item in array.iter() {
                                let mut local_env = HashMap::new();
                                local_env.insert(param_name.to_string(), item.clone());
                                let cond_val = eval_ast(body, inputs, temporal_context, &local_env, &self.backend, self).await?;
                                if cond_val.as_bool()? {
                                    result = true;
                                    break;
                                }
                            }
                            Value::Bool(result)
                        }
                        "all" => {
                            if args.len() != 2 {
                                return Err(format!("all expects exactly 2 arguments, got {}", args.len()));
                            }
                            let array = match &args[0] {
                                Value::Array(a) => a,
                                Value::Nil => return Ok(Value::Bool(true)),
                                _ => return Err("all first argument must be an array".to_string()),
                            };
                            let lambda_str = args[1].as_str()?;
                            let lambda_ast: serde_json::Value = serde_json::from_str(lambda_str)
                                .map_err(|e| format!("Invalid lambda JSON in all: {}", e))?;
                            let params = lambda_ast.get("params")
                                .and_then(|p| p.as_array())
                                .ok_or("Missing params in lambda")?;
                            let param_name = params.first()
                                .and_then(|p| p.as_str())
                                .ok_or("Lambda must have at least one parameter")?;
                            let body = lambda_ast.get("body")
                                .ok_or("Missing body in lambda")?;
                            let mut result = true;
                            for item in array.iter() {
                                let mut local_env = HashMap::new();
                                local_env.insert(param_name.to_string(), item.clone());
                                let cond_val = eval_ast(body, inputs, temporal_context, &local_env, &self.backend, self).await?;
                                if !cond_val.as_bool()? {
                                    result = false;
                                    break;
                                }
                            }
                            Value::Bool(result)
                        }
                        "try_catch" => {
                            if args.len() != 2 {
                                return Err(format!("try_catch expects exactly 2 arguments, got {}", args.len()));
                            }
                            let res = &args[0];
                            match res {
                                Value::Record(map) if map.contains_key("ok") => {
                                    map.get("ok").cloned().unwrap_or(Value::Nil)
                                }
                                Value::Record(map) if map.contains_key("err") => {
                                    let err_val = map.get("err").cloned().unwrap_or(Value::Nil);
                                    let lambda_str = args[1].as_str()?;
                                    let lambda_ast: serde_json::Value = serde_json::from_str(lambda_str)
                                        .map_err(|e| format!("Invalid lambda JSON in try_catch: {}", e))?;
                                    let params = lambda_ast.get("params")
                                        .and_then(|p| p.as_array())
                                        .ok_or("Missing params in try_catch lambda")?;
                                    let param_name = params.first()
                                        .and_then(|p| p.as_str())
                                        .unwrap_or("e");
                                    let body = lambda_ast.get("body")
                                        .ok_or("Missing body in try_catch lambda")?;
                                    let mut local_env = HashMap::new();
                                    local_env.insert(param_name.to_string(), err_val);
                                    eval_ast(body, inputs, temporal_context, &local_env, &self.backend, self).await?
                                }
                                _ => res.clone(),
                            }
                        }
                        "propagate" => {
                            if args.is_empty() {
                                return Err("propagate expects 1 argument".to_string());
                            }
                            let res = &args[0];
                            match res {
                                Value::Record(map) if map.contains_key("ok") => {
                                    map.get("ok").cloned().unwrap_or(Value::Nil)
                                }
                                Value::Record(map) if map.contains_key("err") => {
                                    Value::Record(map.clone())
                                }
                                _ => res.clone(),
                            }
                        }
                        "validate" => {
                            if args.len() != 3 {
                                return Err(format!("validate expects exactly 3 arguments, got {}", args.len()));
                            }
                            let val = args[0].clone();
                            let err_val = args[2].clone();
                            let lambda_str = args[1].as_str()?;
                            let lambda_ast: serde_json::Value = serde_json::from_str(lambda_str)
                                .map_err(|e| format!("Invalid lambda JSON in validate: {}", e))?;
                            let params = lambda_ast.get("params")
                                .and_then(|p| p.as_array())
                                .ok_or("Missing params in validate lambda")?;
                            let param_name = params.first()
                                .and_then(|p| p.as_str())
                                .unwrap_or("v");
                            let body = lambda_ast.get("body")
                                .ok_or("Missing body in validate lambda")?;
                            let mut local_env = HashMap::new();
                            local_env.insert(param_name.to_string(), val.clone());
                            let cond = eval_ast(body, inputs, temporal_context, &local_env, &self.backend, self).await?;
                            if cond.as_bool().unwrap_or(false) {
                                let mut ok_map = std::collections::BTreeMap::new();
                                ok_map.insert("ok".to_string(), val);
                                Value::Record(Arc::new(ok_map))
                            } else {
                                let mut err_map = std::collections::BTreeMap::new();
                                err_map.insert("err".to_string(), err_val);
                                Value::Record(Arc::new(err_map))
                            }
                        }
                        "map" => {
                            if args.len() != 2 {
                                return Err(format!("map expects exactly 2 arguments, got {}", args.len()));
                            }
                            let coll = &args[0];
                            let lambda_str = args[1].as_str()?;
                            match coll {
                                Value::Array(array) => {
                                    let lambda_ast: serde_json::Value = serde_json::from_str(lambda_str)
                                        .map_err(|e| format!("Invalid lambda JSON in map: {}", e))?;
                                    let params = lambda_ast.get("params")
                                        .and_then(|p| p.as_array())
                                        .ok_or("Missing params in lambda")?;
                                    let param_name = params.first()
                                        .and_then(|p| p.as_str())
                                        .ok_or("Lambda must have at least one parameter")?;
                                    let body = lambda_ast.get("body")
                                        .ok_or("Missing body in lambda")?;
                                    
                                    let mut mapped = Vec::new();
                                    for item in array.iter() {
                                        let mut local_env = HashMap::new();
                                        local_env.insert(param_name.to_string(), item.clone());
                                        let val = eval_ast(body, inputs, temporal_context, &local_env, &self.backend, self).await?;
                                        mapped.push(val);
                                    }
                                    Value::Array(Arc::new(mapped))
                                }
                                Value::Nil => Value::Nil,
                                Value::Record(map) if map.contains_key("ok") => {
                                    let ok_val = map.get("ok").unwrap().clone();
                                    let empty_env = HashMap::new();
                                    let res = eval_lambda(lambda_str, ok_val, inputs, temporal_context, &empty_env, &self.backend, self).await?;
                                    let mut new_map = std::collections::BTreeMap::new();
                                    new_map.insert("ok".to_string(), res);
                                    Value::Record(Arc::new(new_map))
                                }
                                Value::Record(map) if map.contains_key("err") => {
                                    coll.clone()
                                }
                                _ => {
                                    // Option Some represented as raw value
                                    let empty_env = HashMap::new();
                                    let res = eval_lambda(lambda_str, coll.clone(), inputs, temporal_context, &empty_env, &self.backend, self).await?;
                                    res
                                }
                            }
                        }
                        "flat_map" | "and_then" => {
                            if args.len() != 2 {
                                return Err(format!("{} expects exactly 2 arguments, got {}", fn_name, args.len()));
                            }
                            let coll = &args[0];
                            let lambda_str = args[1].as_str()?;
                            match coll {
                                Value::Array(array) => {
                                    let lambda_ast: serde_json::Value = serde_json::from_str(lambda_str)
                                        .map_err(|e| format!("Invalid lambda JSON in flat_map: {}", e))?;
                                    let params = lambda_ast.get("params")
                                        .and_then(|p| p.as_array())
                                        .ok_or("Missing params in lambda")?;
                                    let param_name = params.first()
                                        .and_then(|p| p.as_str())
                                        .ok_or("Lambda must have at least one parameter")?;
                                    let body = lambda_ast.get("body")
                                        .ok_or("Missing body in lambda")?;
                                    
                                    let mut flat_mapped = Vec::new();
                                    for item in array.iter() {
                                        let mut local_env = HashMap::new();
                                        local_env.insert(param_name.to_string(), item.clone());
                                        let val = eval_ast(body, inputs, temporal_context, &local_env, &self.backend, self).await?;
                                        match val {
                                            Value::Array(a) => flat_mapped.extend(a.iter().cloned()),
                                            v => flat_mapped.push(v),
                                        }
                                    }
                                    Value::Array(Arc::new(flat_mapped))
                                }
                                Value::Nil => Value::Nil,
                                Value::Record(map) if map.contains_key("ok") => {
                                    let ok_val = map.get("ok").unwrap().clone();
                                    let empty_env = HashMap::new();
                                    let res = eval_lambda(lambda_str, ok_val, inputs, temporal_context, &empty_env, &self.backend, self).await?;
                                    res
                                }
                                Value::Record(map) if map.contains_key("err") => {
                                    coll.clone()
                                }
                                _ => {
                                    // Option Some represented as raw value
                                    let empty_env = HashMap::new();
                                    let res = eval_lambda(lambda_str, coll.clone(), inputs, temporal_context, &empty_env, &self.backend, self).await?;
                                    res
                                }
                            }
                        }
                        "fold" | "reduce" => {
                            if args.len() != 3 {
                                return Err(format!("fold expects exactly 3 arguments, got {}", args.len()));
                            }
                            let array = match &args[0] {
                                Value::Array(a) => a,
                                _ => return Err("fold first argument must be an array".to_string()),
                            };
                            let init_val = args[1].clone();
                            let lambda_str = args[2].as_str()?;
                            let lambda_ast: serde_json::Value = serde_json::from_str(lambda_str)
                                .map_err(|e| format!("Invalid lambda JSON in fold: {}", e))?;
                            
                            let params = lambda_ast.get("params")
                                .and_then(|p| p.as_array())
                                .ok_or("Missing params in lambda")?;
                            if params.len() < 2 {
                                return Err("Lambda in fold/reduce must have at least 2 parameters (acc, item)".to_string());
                            }
                            let param_acc = params[0].as_str().ok_or("First parameter must be string")?;
                            let param_val = params[1].as_str().ok_or("Second parameter must be string")?;
                            let body = lambda_ast.get("body")
                                .ok_or("Missing body in lambda")?;
                            
                            let mut acc = init_val;
                            for item in array.iter() {
                                let mut local_env = HashMap::new();
                                local_env.insert(param_acc.to_string(), acc.clone());
                                local_env.insert(param_val.to_string(), item.clone());
                                acc = eval_ast(body, inputs, temporal_context, &local_env, &self.backend, self).await?;
                            }
                            acc
                        }
                        // LAB-RACK-P9: explicit named user-contract dispatch.
                        // call_contract("ContractName", arg1, arg2, ...) — first arg is the
                        // callee contract name; remaining args are positional inputs mapped
                        // to the callee's input declarations (in declaration order).
                        //
                        // Policy (v0):
                        //   - Callee must be pure (effect/privileged callee → error)
                        //   - Single output only (first declared output)
                        //   - Positional arg count must match callee input count exactly
                        //   - Call depth ≤ MAX_CALL_DEPTH (8); excess → error
                        //   - Cycles detected via __call_chain__ threaded through temporal_context
                        //   - Self-recursion detected as a cycle (caller in chain before dispatch)
                        //
                        // Depth and chain are tracked through special keys in temporal_context:
                        //   __call_depth__: Integer (default 0)
                        //   __call_chain__: String (comma-separated contract names, default "")
                        "call_contract" => {
                            // Unified dispatch — same VM::call_contract_value the eval_ast
                            // tree-walker uses, so the two paths cannot diverge.
                            if args.is_empty() {
                                return Err("call_contract: missing contract name argument (first arg must be String)".to_string());
                            }
                            let callee_name = match &args[0] {
                                Value::String(s) => s.to_string(),
                                other => return Err(format!(
                                    "call_contract: first argument must be String (contract name), got {:?}",
                                    other
                                )),
                            };
                            self.call_contract_value(&callee_name, &args[1..], temporal_context).await?
                        }
                        // ── LAB-VM-MAP-P1: Map runtime operations ────────────────────────────
                        // Option representation: None = Value::Nil, Some(v) = raw v (no wrapper).
                        // Map runtime representation: Value::Record(BTreeMap<String, Value>).
                        // map_get(map, key)     → Option[V]: Nil if absent, raw value if present.
                        // map_has_key(map, key) → Bool: true iff key exists.
                        // or_else(option, fallback) is handled above (pre-existing).
                        "map_get" | "stdlib.map.get" => {
                            if args.len() != 2 {
                                return Err(format!("map_get expects exactly 2 arguments, got {}", args.len()));
                            }
                            let key = args[1].as_str()?;
                            match &args[0] {
                                Value::Record(map) => map.get(key).cloned().unwrap_or(Value::Nil),
                                Value::Nil => Value::Nil,
                                _ => return Err(format!(
                                    "map_get: first argument must be a Map (Record), got {:?}", args[0]
                                )),
                            }
                        }
                        "map_has_key" | "stdlib.map.has_key" => {
                            if args.len() != 2 {
                                return Err(format!("map_has_key expects exactly 2 arguments, got {}", args.len()));
                            }
                            let key = args[1].as_str()?;
                            match &args[0] {
                                Value::Record(map) => Value::Bool(map.contains_key(key)),
                                Value::Nil => Value::Bool(false),
                                _ => return Err(format!(
                                    "map_has_key: first argument must be a Map (Record), got {:?}", args[0]
                                )),
                            }
                        }
                        // ── end LAB-VM-MAP-P1 ────────────────────────────────────────────────
                        _ => {
                            return Err(format!("OP_CALL: Unknown/unimplemented function '{}' with {} arguments", fn_name, arg_count));
                        }
                    };
                    stack.push(res);
                    ip += 1;
                }

                OP_NEG => {
                    let val = stack.pop().ok_or("Stack underflow during NEG")?;
                    let res = match val {
                        Value::Integer(i) => Value::Integer(-i),
                        Value::Float(f) => Value::Float(-f),
                        Value::Decimal { value, scale } => Value::Decimal { value: -value, scale },
                        _ => return Err(format!("Invalid operand type for NEG: {:?}", val)),
                    };
                    stack.push(res);
                    ip += 1;
                }

                OP_GET_FIELD => {
                    // LAB-RECORD-VM-P2: Extract a named field from a record value.
                    // Args: [field_name: String]
                    // Stack in:  ... record
                    // Stack out: ... field_value
                    let field_name = inst.args.get(0)
                        .ok_or("OP_GET_FIELD: missing field name argument")?
                        .as_str()?;
                    let record_val = stack.pop().ok_or("Stack underflow during OP_GET_FIELD")?;
                    match record_val {
                        Value::Record(ref map) => {
                            let val = map.get(field_name)
                                .ok_or_else(|| format!(
                                    "OP_GET_FIELD: field '{}' not found in record (available: [{}])",
                                    field_name,
                                    map.keys().cloned().collect::<Vec<_>>().join(", ")
                                ))?;
                            stack.push(val.clone());
                        }
                        other => {
                            return Err(format!(
                                "OP_GET_FIELD: expected Record, got {:?}",
                                other
                            ));
                        }
                    }
                    ip += 1;
                }

                OP_JMP => {
                    let target = inst.args.get(0)
                        .ok_or("Missing jump target")?
                        .as_integer()? as usize;
                    if target >= total_instructions {
                        return Err(format!("Cannot jump to out-of-bounds offset {} (total {})", target, total_instructions));
                    }
                    ip = target;
                }

                OP_JMP_IF => {
                    let cond = stack.pop().ok_or("Stack underflow during JMP_IF condition")?.as_bool()?;
                    if cond {
                        let target = inst.args.get(0)
                            .ok_or("Missing jump target")?
                            .as_integer()? as usize;
                        if target >= total_instructions {
                            return Err(format!("Cannot jump to out-of-bounds offset {} (total {})", target, total_instructions));
                        }
                        ip = target;
                    } else {
                        ip += 1;
                    }
                }

                OP_JMP_UNLESS => {
                    let cond = stack.pop().ok_or("Stack underflow during JMP_UNLESS condition")?.as_bool()?;
                    if !cond {
                        let target = inst.args.get(0)
                            .ok_or("Missing jump target")?
                            .as_integer()? as usize;
                        if target >= total_instructions {
                            return Err(format!("Cannot jump to out-of-bounds offset {} (total {})", target, total_instructions));
                        }
                        ip = target;
                    } else {
                        ip += 1;
                    }
                }

                OP_LOAD_AS_OF => {
                    let store_name = inst.args.get(0).ok_or("Missing store name")?.as_str()?;
                    let as_of_ref = inst.args.get(1).ok_or("Missing as_of reference")?.as_str()?;
                    
                    let as_of_val = if let Some(v) = inputs.get(as_of_ref) {
                        v.as_str()?
                    } else if let Some(v) = temporal_context.get(as_of_ref) {
                        v.as_str()?
                    } else {
                        return Err(format!("as_of coordinate ref '{}' not resolved", as_of_ref));
                    };

                    let backend = self.backend.as_ref().ok_or("No temporal backend bound to VM")?;
                    let result = backend.read_as_of(store_name, as_of_val).await?;
                    let val = result.unwrap_or(Value::Nil);
                    stack.push(val.clone());

                    // Audit compliance observation ID hex hashing
                    let raw_digest = format!("{}-{}", store_name, as_of_val);
                    let obs_id = format!("obs/live-read/{}", sha256_hex(&raw_digest));

                    let mut obs_obj = serde_json::Map::new();
                    obs_obj.insert("kind".to_string(), "temporal_live_read_observation".into());
                    obs_obj.insert("observation_id".to_string(), obs_id.into());
                    obs_obj.insert("store".to_string(), store_name.into());
                    obs_obj.insert("axis".to_string(), "valid_time".into());
                    obs_obj.insert("as_of".to_string(), as_of_val.into());
                    obs_obj.insert("result_present".to_string(), (val != Value::Nil).into());
                    obs_obj.insert("result_value".to_string(), val.to_json());
                    
                    let mut sink = self.observation_sink.lock().await;
                    sink.push(serde_json::Value::Object(obs_obj));

                    ip += 1;
                }

                OP_EMIT_OBS => {
                    let modifier = temporal_context.get("contract_modifier")
                        .or_else(|| inputs.get("contract_modifier"))
                        .and_then(|v| v.as_str().ok())
                        .unwrap_or("irreversible");
                    if modifier == "pure" || modifier == "observed" {
                        return Err("OOF-M1: emit_observation is not allowed in pure or observed contracts".to_string());
                    }
                    let obs_kind = inst.args.get(0).ok_or("Missing observation kind")?.as_str()?;
                    let val = stack.pop().ok_or("Stack underflow during EMIT_OBS")?;
                    
                    let raw_digest = format!("{}-{:?}", obs_kind, val);
                    let obs_id = format!("obs/eval/{}", sha256_hex(&raw_digest));

                    let mut obs_obj = serde_json::Map::new();
                    obs_obj.insert("kind".to_string(), obs_kind.into());
                    obs_obj.insert("observation_id".to_string(), obs_id.into());
                    obs_obj.insert("value".to_string(), val.to_json());

                    let mut sink = self.observation_sink.lock().await;
                    sink.push(serde_json::Value::Object(obs_obj.clone()));

                    if let Some(backend) = &self.backend {
                        let obs_val = Value::from_json(&serde_json::Value::Object(obs_obj));
                        backend.append_observation(obs_val).await?;
                    }

                    stack.push(val); // Push value back to stack
                    ip += 1;
                }

                OP_MAP_REDUCE => {
                    let serialized = inst.args.get(0)
                        .ok_or("Missing map_reduce argument")?
                        .as_str()?;
                    
                    let node: serde_json::Value = serde_json::from_str(serialized)
                        .map_err(|e| format!("Invalid map_reduce JSON: {}", e))?;
                    
                    let source = node.get("source").ok_or("Missing source in map_reduce_aggregate")?;
                    let pipeline = node.get("pipeline")
                        .ok_or("Missing pipeline in map_reduce_aggregate")?
                        .as_array()
                        .ok_or("pipeline must be an array")?;

                    let source_val = eval_ast(source, inputs, temporal_context, &HashMap::new(), &self.backend, self).await?;

                    let mut items = Vec::new();
                    match &source_val {
                        Value::Array(arr) => {
                            items = (**arr).clone();
                        }
                        _ => {
                            // If not an array, treat as empty
                        }
                    }

                    let mut result_val = Value::Nil;
                    let mut first_found = false;
                    let mut count_acc = 0i64;
                    let mut passed_count = 0i64;
                    let mut fold_acc: Option<Value> = None;
                    let mut sum_integer = 0i64;
                    let mut sum_decimal = Decimal::new(0, 0);
                    let mut has_integer = false;
                    let mut has_decimal = false;

                    let terminal_step = pipeline.last().ok_or("pipeline must not be empty")?;
                    let terminal_kind = terminal_step.get("kind").and_then(|k| k.as_str()).ok_or("Missing terminal step kind")?;

                    if terminal_kind == "fold" {
                        let init_ast = terminal_step.get("init").ok_or("Missing init in fold")?;
                        let init_val = eval_ast(init_ast, inputs, temporal_context, &HashMap::new(), &self.backend, self).await?;
                        fold_acc = Some(init_val);
                    }

                    'item_loop: for item in items.iter() {
                        let mut current_value = item.clone();

                        for step in &pipeline[0..pipeline.len()-1] {
                            let step_kind = step.get("kind").and_then(|k| k.as_str()).ok_or("Missing step kind")?;
                            match step_kind {
                                "filter" => {
                                    let param = step.get("param").ok_or("Missing param in filter")?.as_str().ok_or("param must be string")?;
                                    let body = step.get("body").ok_or("Missing body in filter")?;
                                    
                                    let mut local_env = HashMap::new();
                                    local_env.insert(param.to_string(), current_value.clone());
                                    
                                    let cond = eval_ast(body, inputs, temporal_context, &local_env, &self.backend, self).await?;
                                    if !cond.as_bool()? {
                                        continue 'item_loop;
                                    }
                                }
                                "map" => {
                                    let param = step.get("param").ok_or("Missing param in map")?.as_str().ok_or("param must be string")?;
                                    let body = step.get("body").ok_or("Missing body in map")?;
                                    
                                    let mut local_env = HashMap::new();
                                    local_env.insert(param.to_string(), current_value.clone());
                                    
                                    current_value = eval_ast(body, inputs, temporal_context, &local_env, &self.backend, self).await?;
                                }
                                _ => return Err(format!("Unsupported intermediate pipeline step: {}", step_kind)),
                            }
                        }

                        passed_count += 1;

                        match terminal_kind {
                            "count" => {
                                count_acc += 1;
                            }
                            "first" => {
                                result_val = current_value;
                                first_found = true;
                                break 'item_loop;
                            }
                            "last" => {
                                result_val = current_value;
                                first_found = true;
                            }
                            "sum" | "avg" => {
                                let field = terminal_step.get("field").ok_or("Missing field in sum/avg")?.as_str().ok_or("field must be string")?;
                                let val = match &current_value {
                                    Value::Record(map) => map.get(field).cloned().unwrap_or(Value::Nil),
                                    _ => return Err("sum/avg expects record items in array".to_string()),
                                };
                                match val {
                                    Value::Integer(i) => {
                                        sum_integer += i;
                                        has_integer = true;
                                    }
                                    Value::Decimal { value: v, scale: s } => {
                                        if !has_decimal {
                                            sum_decimal = Decimal::new(0, s);
                                            has_decimal = true;
                                        }
                                        let d = Decimal::new(v, s);
                                        sum_decimal = sum_decimal.add(&d)?;
                                    }
                                    Value::Nil => {}
                                    _ => return Err(format!("Unsupported type for sum/avg: {:?}", val)),
                                }
                            }
                            "min" | "max" => {
                                let field = terminal_step.get("field").ok_or("Missing field in min/max")?.as_str().ok_or("field must be string")?;
                                let val = match &current_value {
                                    Value::Record(map) => map.get(field).cloned().unwrap_or(Value::Nil),
                                    _ => return Err("min/max expects record items".to_string()),
                                };
                                if val != Value::Nil {
                                    if !first_found {
                                        result_val = val;
                                        first_found = true;
                                    } else {
                                        let is_better = match (terminal_kind, &val, &result_val) {
                                            ("min", Value::Integer(x), Value::Integer(y)) => x < y,
                                            ("max", Value::Integer(x), Value::Integer(y)) => x > y,
                                            ("min", Value::Decimal { value: av, scale: as_ }, Value::Decimal { value: bv, scale: bs }) => {
                                                ((*av as f64) / 10f64.powi(*as_ as i32)) < ((*bv as f64) / 10f64.powi(*bs as i32))
                                            }
                                            ("max", Value::Decimal { value: av, scale: as_ }, Value::Decimal { value: bv, scale: bs }) => {
                                                ((*av as f64) / 10f64.powi(*as_ as i32)) > ((*bv as f64) / 10f64.powi(*bs as i32))
                                            }
                                            ("min", Value::Float(x), Value::Float(y)) => x < y,
                                            ("max", Value::Float(x), Value::Float(y)) => x > y,
                                            _ => false
                                        };
                                        if is_better {
                                            result_val = val;
                                        }
                                    }
                                }
                            }
                            "fold" => {
                                let param_acc = terminal_step.get("param_acc").ok_or("Missing param_acc")?.as_str().ok_or("param_acc must be string")?;
                                let param_val = terminal_step.get("param_val").ok_or("Missing param_val")?.as_str().ok_or("param_val must be string")?;
                                let body = terminal_step.get("body").ok_or("Missing body in fold")?;

                                let mut local_env = HashMap::new();
                                local_env.insert(param_acc.to_string(), fold_acc.as_ref().unwrap().clone());
                                local_env.insert(param_val.to_string(), current_value);

                                let next_acc = eval_ast(body, inputs, temporal_context, &local_env, &self.backend, self).await?;
                                fold_acc = Some(next_acc);
                            }
                            _ => return Err(format!("Unsupported terminal pipeline step: {}", terminal_kind)),
                        }
                    }

                    let final_res = match terminal_kind {
                        "count" => Value::Integer(count_acc),
                        "first" => {
                            if first_found {
                                result_val
                            } else {
                                Value::Nil
                            }
                        }
                        "last" => {
                            if first_found {
                                result_val
                            } else {
                                Value::Nil
                            }
                        }
                        "fold" => fold_acc.unwrap_or(Value::Nil),
                        "sum" => {
                            if has_decimal {
                                Value::Decimal { value: sum_decimal.value, scale: sum_decimal.scale }
                            } else {
                                Value::Integer(sum_integer)
                            }
                        }
                        "avg" => {
                            if passed_count == 0 {
                                Value::Nil
                            } else if has_decimal {
                                Value::Decimal { value: sum_decimal.value / passed_count, scale: sum_decimal.scale }
                            } else {
                                Value::Integer(sum_integer / passed_count)
                            }
                        }
                        "min" | "max" => {
                            if first_found {
                                result_val
                            } else {
                                Value::Nil
                            }
                        }
                        _ => unreachable!(),
                    };

                    stack.push(final_res);
                    ip += 1;
                }

                OP_RET => {
                    let val = stack.pop().ok_or("Stack empty on RET instruction")?;
                    // LAB-VMTRACE-P1: record before returning (OP_RET is the only early-return instruction).
                    if let Some(ref collector) = self.trace_collector {
                        collector.lock().unwrap().push(serde_json::json!({
                            "seq": trace_seq,
                            "ip_before": trace_pre_ip,
                            "opcode": format!("0x{:02X}", trace_pre_opcode),
                            "mnemonic": "RET",
                            "stack_depth_before": trace_pre_depth,
                            "stack_depth_after": stack.len()
                        }));
                    }
                    return Ok(val);
                }


                OP_LOOP_START => {
                    let name = inst.args.get(0).ok_or("Missing loop name arg")?.as_str()?.to_string();
                    let raw_steps = inst.args.get(1).ok_or("Missing max_steps arg")?.as_integer()? as u64;
                    // G3b: max_steps=0 means FiniteLoop (no budget — terminates via collection exhaustion).
                    // Use u64::MAX as sentinel so the fuel-exhaustion check never fires.
                    let fuel = if raw_steps == 0 { u64::MAX } else { raw_steps };
                    let collection_val = stack.pop().ok_or("LOOP_START expects collection on stack")?;
                    let collection = match collection_val {
                        Value::Array(arr) => (*arr).clone(),
                        _ => return Err(format!("LOOP_START expects Array, got {:?}", collection_val)),
                    };

                    loop_stack.push(LoopFrame { name, collection, index: 0, fuel });
                    ip += 1;
                }

                OP_LOOP_STEP => {
                    let exit_ip = inst.args.get(0).ok_or("Missing exit_ip arg")?.as_integer()? as usize;
                    let frame = loop_stack.last_mut().ok_or("OP_LOOP_STEP called without loop frame")?;
                    
                    if frame.index >= frame.collection.len() {
                        loop_stack.pop();
                        ip = exit_ip;
                    } else {
                        if frame.fuel == 0 {
                            return Err("OOF-L-FUEL: loop fuel exhausted".to_string());
                        }
                        frame.fuel -= 1;
                        
                        let next_item = frame.collection[frame.index].clone();
                        frame.index += 1;
                        stack.push(next_item);
                        ip += 1;
                    }
                }

                OP_LOOP_BREAK => {
                    loop_stack.pop().ok_or("OP_LOOP_BREAK called without loop frame")?;
                    ip += 1;
                }

                OP_LOAD_TICK => {
                    let _interval_ms = inst.args.get(0).ok_or("Missing interval_ms arg")?.as_integer()?;
                    let tick_time = temporal_context.get("tick.time")
                        .cloned()
                        .or_else(|| temporal_context.get("time").cloned())
                        .or_else(|| inputs.get("tick.time").cloned())
                        .or_else(|| inputs.get("time").cloned())
                        .ok_or_else(|| "OOF-SL1: service loop clock tick time unresolved".to_string())?;
                    stack.push(tick_time);
                    ip += 1;
                }

                OP_UNSUPPORTED => {
                    return Err("Decoded unsupported selected-path bytecode instruction".to_string());
                }

                _ => return Err(format!("Unknown instruction opcode: 0x{:02X}", inst.opcode)),
            }
            // LAB-VMTRACE-P1: post-instruction trace recording for all non-returning instructions.
            if let Some(ref collector) = self.trace_collector {
                collector.lock().unwrap().push(serde_json::json!({
                    "seq": trace_seq,
                    "ip_before": trace_pre_ip,
                    "opcode": format!("0x{:02X}", trace_pre_opcode),
                    "mnemonic": crate::instructions::opcode_mnemonic(trace_pre_opcode),
                    "stack_depth_before": trace_pre_depth,
                    "stack_depth_after": stack.len()
                }));
                trace_seq += 1;
            }
        }

        Err("Evaluation halted without explicit RET instruction".to_string())
    }
}

fn eval_ast<'a>(
    node: &'a serde_json::Value,
    inputs: &'a HashMap<String, Value>,
    temporal_context: &'a HashMap<String, Value>,
    local_env: &'a HashMap<String, Value>,
    backend: &'a Option<Arc<dyn TBackend>>,
    vm: &'a VM,
) -> std::pin::Pin<Box<dyn std::future::Future<Output = Result<Value, String>> + Send + 'a>> {
    Box::pin(async move {
        let kind = node.get("kind")
            .ok_or_else(|| "AST node missing kind".to_string())?
            .as_str()
            .ok_or_else(|| "kind must be string".to_string())?;

        match kind {
            "literal" => {
                let val = node.get("value").ok_or_else(|| "Missing literal value".to_string())?;
                Ok(Value::from_json(val))
            }
            "ref" => {
                let name = node.get("name")
                    .ok_or_else(|| "Missing ref name".to_string())?
                    .as_str()
                    .ok_or_else(|| "name must be string".to_string())?;
                if let Some(v) = local_env.get(name) {
                    Ok(v.clone())
                } else if let Some(v) = inputs.get(name) {
                    Ok(v.clone())
                } else if let Some(v) = temporal_context.get(name) {
                    Ok(v.clone())
                } else {
                    Err(format!("Symbol '{}' not found in env", name))
                }
            }
            "field_access" => {
                let object = node.get("object").ok_or_else(|| "Missing object in field_access".to_string())?;
                let field = node.get("field").ok_or_else(|| "Missing field in field_access".to_string())?.as_str().ok_or_else(|| "field must be string".to_string())?;
                if let Some("ref") = object.get("kind").and_then(|k| k.as_str()) {
                    let obj_name = object.get("name").ok_or_else(|| "Missing name in ref".to_string())?.as_str().ok_or_else(|| "name must be string".to_string())?;
                    let full_name = format!("{}.{}", obj_name, field);
                    if let Some(v) = local_env.get(&full_name) {
                        return Ok(v.clone());
                    } else if let Some(v) = inputs.get(&full_name) {
                        return Ok(v.clone());
                    } else if let Some(v) = temporal_context.get(&full_name) {
                        return Ok(v.clone());
                    }
                    if let Some(v) = local_env.get(obj_name) {
                        if let Value::Record(map) = v {
                            if let Some(val) = map.get(field) {
                                return Ok(val.clone());
                            }
                        }
                        return Ok(v.clone());
                    } else if let Some(v) = inputs.get(obj_name) {
                        if let Value::Record(map) = v {
                            if let Some(val) = map.get(field) {
                                return Ok(val.clone());
                            }
                        }
                        return Ok(v.clone());
                    } else if let Some(v) = temporal_context.get(obj_name) {
                        if let Value::Record(map) = v {
                            if let Some(val) = map.get(field) {
                                return Ok(val.clone());
                            }
                        }
                        return Ok(v.clone());
                    }
                }
                // General case: object is an arbitrary expression (nested field
                // access, call result, indexed element, …) that yields a Record.
                let obj_val = eval_ast(object, inputs, temporal_context, local_env, backend, vm).await?;
                match obj_val {
                    Value::Record(map) => map.get(field).cloned().ok_or_else(||
                        format!("Field access: record has no field '{}'", field)),
                    other => Err(format!(
                        "Field access not resolvable for field '{}' on value {:?}", field, other)),
                }
            }
            "binary_op" => {
                let left_val = eval_ast(node.get("left").ok_or_else(|| "Missing left".to_string())?, inputs, temporal_context, local_env, backend, vm).await?;
                let right_val = eval_ast(node.get("right").ok_or_else(|| "Missing right".to_string())?, inputs, temporal_context, local_env, backend, vm).await?;
                let op = node.get("operator").or_else(|| node.get("op"))
                    .ok_or_else(|| "Missing operator".to_string())?
                    .as_str()
                    .ok_or_else(|| "operator must be string".to_string())?;
                match op {
                    "+" => {
                        match (&left_val, &right_val) {
                            (Value::Decimal { value: av, scale: as_ }, Value::Decimal { value: bv, scale: bs }) => {
                                let da = Decimal::new(*av, *as_);
                                let db = Decimal::new(*bv, *bs);
                                match da.add(&db) {
                                    Ok(res_dec) => Ok(Value::Decimal { value: res_dec.value, scale: res_dec.scale }),
                                    Err(e) => Err(e),
                                }
                            }
                            (Value::Integer(av), Value::Integer(bv)) => Ok(Value::Integer(av + bv)),
                            (Value::Float(av), Value::Float(bv)) => Ok(Value::Float(av + bv)),
                            _ => Err(format!("Invalid operand types for ADD: {:?} + {:?}", left_val, right_val)),
                        }
                    }
                    "-" => {
                        match (&left_val, &right_val) {
                            (Value::Decimal { value: av, scale: as_ }, Value::Decimal { value: bv, scale: bs }) => {
                                let da = Decimal::new(*av, *as_);
                                let db = Decimal::new(*bv, *bs);
                                match da.sub(&db) {
                                    Ok(res_dec) => Ok(Value::Decimal { value: res_dec.value, scale: res_dec.scale }),
                                    Err(e) => Err(e),
                                }
                            }
                            (Value::Integer(av), Value::Integer(bv)) => Ok(Value::Integer(av - bv)),
                            (Value::Float(av), Value::Float(bv)) => Ok(Value::Float(av - bv)),
                            _ => Err(format!("Invalid operand types for SUB: {:?} - {:?}", left_val, right_val)),
                        }
                    }
                    "*" => {
                        match (&left_val, &right_val) {
                            (Value::Decimal { value: av, scale: as_ }, Value::Decimal { value: bv, scale: bs }) => {
                                let da = Decimal::new(*av, *as_);
                                let db = Decimal::new(*bv, *bs);
                                let res_dec = da.mul(&db);
                                Ok(Value::Decimal { value: res_dec.value, scale: res_dec.scale })
                            }
                            (Value::Integer(av), Value::Integer(bv)) => Ok(Value::Integer(av * bv)),
                            (Value::Float(av), Value::Float(bv)) => Ok(Value::Float(av * bv)),
                            _ => Err(format!("Invalid operand types for MUL: {:?} * {:?}", left_val, right_val)),
                        }
                    }
                    "/" => {
                        match (&left_val, &right_val) {
                            (Value::Decimal { value: av, scale: as_ }, Value::Decimal { value: bv, scale: bs }) => {
                                let da = Decimal::new(*av, *as_);
                                let db = Decimal::new(*bv, *bs);
                                match da.div(&db) {
                                    Ok(res_dec) => Ok(Value::Decimal { value: res_dec.value, scale: res_dec.scale }),
                                    Err(e) => Err(e),
                                }
                            }
                            (Value::Integer(av), Value::Integer(bv)) => {
                                if *bv == 0 {
                                    Err("Division by zero".to_string())
                                } else {
                                    Ok(Value::Integer(av / bv))
                                }
                            }
                            (Value::Float(av), Value::Float(bv)) => {
                                if *bv == 0.0 {
                                    Err("Division by zero".to_string())
                                } else {
                                    Ok(Value::Float(av / bv))
                                }
                            }
                            _ => Err(format!("Invalid operand types for DIV: {:?} / {:?}", left_val, right_val)),
                        }
                    }
                    "==" => {
                        Ok(Value::Bool(left_val == right_val))
                    }
                    "!=" => {
                        Ok(Value::Bool(left_val != right_val))
                    }
                    ">" => {
                        match (&left_val, &right_val) {
                            (Value::Decimal { value: av, scale: as_ }, Value::Decimal { value: bv, scale: bs }) => {
                                let da = Decimal::new(*av, *as_);
                                let db = Decimal::new(*bv, *bs);
                                Ok(Value::Bool(da.to_f64() > db.to_f64()))
                            }
                            (Value::Integer(av), Value::Integer(bv)) => Ok(Value::Bool(av > bv)),
                            (Value::Float(av), Value::Float(bv)) => Ok(Value::Bool(av > bv)),
                            _ => Err(format!("Invalid operand types for GT: {:?} > {:?}", left_val, right_val)),
                        }
                    }
                    "<" => {
                        match (&left_val, &right_val) {
                            (Value::Decimal { value: av, scale: as_ }, Value::Decimal { value: bv, scale: bs }) => {
                                let da = Decimal::new(*av, *as_);
                                let db = Decimal::new(*bv, *bs);
                                Ok(Value::Bool(da.to_f64() < db.to_f64()))
                            }
                            (Value::Integer(av), Value::Integer(bv)) => Ok(Value::Bool(av < bv)),
                            (Value::Float(av), Value::Float(bv)) => Ok(Value::Bool(av < bv)),
                            (Value::String(av), Value::String(bv)) => Ok(Value::Bool(av < bv)),
                            _ => Err(format!("Invalid operand types for LT: {:?} < {:?}", left_val, right_val)),
                        }
                    }
                    "<=" => {
                        match (&left_val, &right_val) {
                            (Value::Decimal { value: av, scale: as_ }, Value::Decimal { value: bv, scale: bs }) => {
                                let da = Decimal::new(*av, *as_);
                                let db = Decimal::new(*bv, *bs);
                                Ok(Value::Bool(da.to_f64() <= db.to_f64()))
                            }
                            (Value::Integer(av), Value::Integer(bv)) => Ok(Value::Bool(av <= bv)),
                            (Value::Float(av), Value::Float(bv)) => Ok(Value::Bool(av <= bv)),
                            (Value::String(av), Value::String(bv)) => Ok(Value::Bool(av <= bv)),
                            _ => Err(format!("Invalid operand types for LE: {:?} <= {:?}", left_val, right_val)),
                        }
                    }
                    ">=" => {
                        match (&left_val, &right_val) {
                            (Value::Decimal { value: av, scale: as_ }, Value::Decimal { value: bv, scale: bs }) => {
                                let da = Decimal::new(*av, *as_);
                                let db = Decimal::new(*bv, *bs);
                                Ok(Value::Bool(da.to_f64() >= db.to_f64()))
                            }
                            (Value::Integer(av), Value::Integer(bv)) => Ok(Value::Bool(av >= bv)),
                            (Value::Float(av), Value::Float(bv)) => Ok(Value::Bool(av >= bv)),
                            (Value::String(av), Value::String(bv)) => Ok(Value::Bool(av >= bv)),
                            _ => Err(format!("Invalid operand types for GE: {:?} >= {:?}", left_val, right_val)),
                        }
                    }
                    "&&" => {
                        match (&left_val, &right_val) {
                            (Value::Bool(av), Value::Bool(bv)) => Ok(Value::Bool(*av && *bv)),
                            _ => Err(format!("Invalid operand types for AND: {:?} && {:?}", left_val, right_val)),
                        }
                    }
                    "||" => {
                        match (&left_val, &right_val) {
                            (Value::Bool(av), Value::Bool(bv)) => Ok(Value::Bool(*av || *bv)),
                            _ => Err(format!("Invalid operand types for OR: {:?} || {:?}", left_val, right_val)),
                        }
                    }
                    "++" => {
                        match (&left_val, &right_val) {
                            (Value::String(av), Value::String(bv)) => {
                                let mut s = av.to_string();
                                s.push_str(bv);
                                Ok(Value::String(Arc::from(s.as_str())))
                            }
                            (Value::Array(av), Value::Array(bv)) => {
                                let mut list = (**av).clone();
                                list.extend_from_slice(bv);
                                Ok(Value::Array(Arc::new(list)))
                            }
                            _ => Err(format!("Invalid operand types for CONCAT: {:?} ++ {:?}", left_val, right_val)),
                        }
                    }
                    _ => Err(format!("Unsupported operator: {}", op)),
                }
            }
            "unary" | "unary_op" => {
                let op = node.get("op")
                    .or_else(|| node.get("operator"))
                    .ok_or_else(|| "Missing unary operator".to_string())?
                    .as_str()
                    .ok_or_else(|| "unary operator must be string".to_string())?;
                let operand = node.get("operand")
                    .or_else(|| node.get("expr"))
                    .or_else(|| node.get("expression"))
                    .ok_or_else(|| "Missing unary operand".to_string())?;
                let val = eval_ast(operand, inputs, temporal_context, local_env, backend, vm).await?;
                match op {
                    "!" => match val {
                        Value::Bool(b) => Ok(Value::Bool(!b)),
                        _ => Err(format!("Invalid operand type for NOT operator: {:?}", val)),
                    }
                    "-" => match val {
                        Value::Integer(i) => Ok(Value::Integer(-i)),
                        Value::Float(f) => Ok(Value::Float(-f)),
                        Value::Decimal { value, scale } => Ok(Value::Decimal { value: -value, scale }),
                        _ => Err(format!("Invalid operand type for NEG operator: {:?}", val)),
                    }
                    _ => Err(format!("Unsupported unary operator: {}", op)),
                }
            }
            "array" | "array_literal" => {
                let items = node.get("items").ok_or_else(|| "Missing items in array".to_string())?.as_array().ok_or_else(|| "items must be array".to_string())?;
                let mut vals = Vec::with_capacity(items.len());
                for item in items {
                    vals.push(eval_ast(item, inputs, temporal_context, local_env, backend, vm).await?);
                }
                Ok(Value::Array(Arc::new(vals)))
            }
            "record" | "record_literal" => {
                let fields = node.get("fields").ok_or_else(|| "Missing fields in record".to_string())?.as_object().ok_or_else(|| "fields must be object".to_string())?;
                let mut map = std::collections::BTreeMap::new();
                for (k, v) in fields {
                    let val = eval_ast(v, inputs, temporal_context, local_env, backend, vm).await?;
                    map.insert(k.clone(), val);
                }
                Ok(Value::Record(Arc::new(map)))
            }
            "concat" => {
                let left_val = eval_ast(node.get("left").ok_or_else(|| "Missing left in concat".to_string())?, inputs, temporal_context, local_env, backend, vm).await?;
                let right_val = eval_ast(node.get("right").ok_or_else(|| "Missing right in concat".to_string())?, inputs, temporal_context, local_env, backend, vm).await?;
                match (&left_val, &right_val) {
                    (Value::String(av), Value::String(bv)) => {
                        let mut s = av.to_string();
                        s.push_str(bv);
                        Ok(Value::String(Arc::from(s.as_str())))
                    }
                    (Value::Array(av), Value::Array(bv)) => {
                        let mut list = (**av).clone();
                        list.extend_from_slice(bv);
                        Ok(Value::Array(Arc::new(list)))
                    }
                    _ => Err(format!("Invalid operand types for CONCAT: {:?} ++ {:?}", left_val, right_val)),
                }
            }
            "let" => {
                let name = node.get("name")
                    .ok_or_else(|| "Missing let variable name".to_string())?
                    .as_str()
                    .ok_or_else(|| "let variable name must be string".to_string())?;
                let expr = node.get("expr")
                    .or_else(|| node.get("value"))
                    .or_else(|| node.get("expression"))
                    .ok_or_else(|| "Missing let value expression".to_string())?;
                
                let val = eval_ast(expr, inputs, temporal_context, local_env, backend, vm).await?;
                
                if let Some(body) = node.get("body") {
                    let mut new_env = local_env.clone();
                    new_env.insert(name.to_string(), val);
                    eval_ast(body, inputs, temporal_context, &new_env, backend, vm).await
                } else {
                    Ok(val)
                }
            }
            "lambda" | "fn" => {
                let serialized = serde_json::to_string(node)
                    .map_err(|e| format!("Failed to serialize lambda: {}", e))?;
                Ok(Value::String(Arc::from(serialized)))
            }
            "emit_observation" => {
                let modifier = temporal_context.get("contract_modifier")
                    .or_else(|| inputs.get("contract_modifier"))
                    .and_then(|v| v.as_str().ok())
                    .unwrap_or("irreversible");
                if modifier == "pure" || modifier == "observed" {
                    return Err("OOF-M1: emit_observation is not allowed in pure or observed contracts".to_string());
                }
                let obs_kind = node.get("observation_kind")
                    .ok_or_else(|| "Missing observation_kind".to_string())?
                    .as_str()
                    .ok_or_else(|| "observation_kind must be string".to_string())?;
                let expr = node.get("expression").ok_or_else(|| "Missing expression in emit_observation".to_string())?;
                
                let val = eval_ast(expr, inputs, temporal_context, local_env, backend, vm).await?;
                
                let raw_digest = format!("{}-{:?}", obs_kind, val);
                let obs_id = format!("obs/eval/{}", sha256_hex(&raw_digest));

                let mut obs_obj = serde_json::Map::new();
                obs_obj.insert("kind".to_string(), obs_kind.into());
                obs_obj.insert("observation_id".to_string(), obs_id.into());
                obs_obj.insert("value".to_string(), val.to_json());

                if let Some(backend_ref) = backend {
                    let obs_val = Value::from_json(&serde_json::Value::Object(obs_obj));
                    backend_ref.append_observation(obs_val).await?;
                }
                
                Ok(val)
            }
            "if_expr" => {
                let cond_val = eval_ast(node.get("condition").ok_or_else(|| "Missing condition".to_string())?, inputs, temporal_context, local_env, backend, vm).await?;
                let cond = cond_val.as_bool()?;
                if cond {
                    eval_ast(node.get("then_branch").ok_or_else(|| "Missing then_branch".to_string())?, inputs, temporal_context, local_env, backend, vm).await
                } else {
                    eval_ast(node.get("else_branch").ok_or_else(|| "Missing else_branch".to_string())?, inputs, temporal_context, local_env, backend, vm).await
                }
            }
            "range" => {
                let start_val = eval_ast(node.get("start").ok_or_else(|| "Missing start".to_string())?, inputs, temporal_context, local_env, backend, vm).await?;
                let end_val = eval_ast(node.get("end").ok_or_else(|| "Missing end".to_string())?, inputs, temporal_context, local_env, backend, vm).await?;
                let start = start_val.as_integer()?;
                let end = end_val.as_integer()?;
                let mut list = Vec::new();
                for i in start..end {
                    list.push(Value::Integer(i));
                }
                Ok(Value::Array(Arc::new(list)))
            }
            "temporal_read" => {
                let store_name = node.get("store_ref")
                    .ok_or_else(|| "Missing store_ref".to_string())?
                    .as_str()
                    .ok_or_else(|| "store_ref must be string".to_string())?;
                let as_of_ref = node.get("as_of_ref")
                    .ok_or_else(|| "Missing as_of_ref".to_string())?
                    .as_str()
                    .ok_or_else(|| "as_of_ref must be string".to_string())?;
                
                let as_of_val = if let Some(v) = inputs.get(as_of_ref) {
                    v.as_str()?
                } else if let Some(v) = temporal_context.get(as_of_ref) {
                    v.as_str()?
                } else {
                    return Err(format!("as_of coordinate ref '{}' not resolved", as_of_ref));
                };

                let backend_ref = backend.as_ref().ok_or_else(|| "No temporal backend bound to VM".to_string())?;
                let result = backend_ref.read_as_of(store_name, as_of_val).await?;
                Ok(result.unwrap_or(Value::Nil))
            }
            "apply" | "call" | "map" | "filter" | "fold" | "reduce" => {
                let op_fallback = serde_json::Value::String(kind.to_string());
                let op = if kind == "apply" {
                    node.get("operator")
                } else if kind == "call" {
                    node.get("fn")
                } else {
                    node.get("fn").or(Some(&op_fallback))
                }.ok_or_else(|| "Missing operator/fn".to_string())?.as_str().ok_or_else(|| "operator/fn must be string".to_string())?;

                let operands = if kind == "apply" {
                    node.get("operands")
                } else if kind == "call" {
                    node.get("args")
                } else {
                    node.get("args").or_else(|| node.get("operands"))
                }.ok_or_else(|| "Missing operands/args".to_string())?.as_array().ok_or_else(|| "operands/args must be array".to_string())?;

                let mut evaluated_operands = Vec::new();
                for operand in operands {
                    let val = eval_ast(operand, inputs, temporal_context, local_env, backend, vm).await?;
                    evaluated_operands.push(val);
                }

                match op {
                    "count" => {
                        if evaluated_operands.len() != 1 {
                            return Err(format!("count expects exactly 1 argument, got {}", evaluated_operands.len()));
                        }
                        match &evaluated_operands[0] {
                            Value::Array(a) => Ok(Value::Integer(a.len() as i64)),
                            Value::Nil => Ok(Value::Integer(0)),
                            _ => Err("count argument must be an array".to_string()),
                        }
                    }
                    "length" => {
                        if evaluated_operands.len() != 1 {
                            return Err(format!("length expects exactly 1 argument, got {}", evaluated_operands.len()));
                        }
                        let s = evaluated_operands[0].as_str()?;
                        Ok(Value::Integer(s.len() as i64))
                    }
                    "concat" => {
                        if evaluated_operands.len() != 2 {
                            return Err(format!("concat expects exactly 2 arguments, got {}", evaluated_operands.len()));
                        }
                        match (&evaluated_operands[0], &evaluated_operands[1]) {
                            (Value::Array(a), Value::Array(b)) => {
                                let mut merged: Vec<Value> = a.iter().cloned().collect();
                                merged.extend(b.iter().cloned());
                                Ok(Value::Array(Arc::new(merged)))
                            }
                            _ => {
                                let a = evaluated_operands[0].as_str()?;
                                let b = evaluated_operands[1].as_str()?;
                                Ok(Value::String(Arc::from(format!("{}{}", a, b))))
                            }
                        }
                    }
                    "trim" => {
                        if evaluated_operands.len() != 1 {
                            return Err(format!("trim expects exactly 1 argument, got {}", evaluated_operands.len()));
                        }
                        let s = evaluated_operands[0].as_str()?;
                        Ok(Value::String(Arc::from(s.trim())))
                    }
                    "split" => {
                        if evaluated_operands.len() != 2 {
                            return Err(format!("split expects exactly 2 arguments, got {}", evaluated_operands.len()));
                        }
                        let s = evaluated_operands[0].as_str()?;
                        let sep = evaluated_operands[1].as_str()?;
                        let parts: Vec<Value> = s.split(sep).map(|p| Value::String(Arc::from(p))).collect();
                        Ok(Value::Array(Arc::new(parts)))
                    }
                    "contains" => {
                        if evaluated_operands.len() != 2 {
                            return Err(format!("contains expects exactly 2 arguments, got {}", evaluated_operands.len()));
                        }
                        let s = evaluated_operands[0].as_str()?;
                        let sub = evaluated_operands[1].as_str()?;
                        Ok(Value::Bool(s.contains(sub)))
                    }
                    "starts_with" => {
                        if evaluated_operands.len() != 2 {
                            return Err(format!("starts_with expects exactly 2 arguments, got {}", evaluated_operands.len()));
                        }
                        let s = evaluated_operands[0].as_str()?;
                        let prefix = evaluated_operands[1].as_str()?;
                        Ok(Value::Bool(s.starts_with(prefix)))
                    }
                    "diff_seconds" => {
                        if evaluated_operands.len() != 2 {
                            return Err(format!("diff_seconds expects exactly 2 arguments, got {}", evaluated_operands.len()));
                        }
                        let dt1_str = evaluated_operands[0].as_str()?;
                        let dt2_str = evaluated_operands[1].as_str()?;
                        let t1 = parse_utc(dt1_str)?;
                        let t2 = parse_utc(dt2_str)?;
                        Ok(Value::Integer((t1 - t2).num_seconds()))
                    }
                    "add_seconds" => {
                        if evaluated_operands.len() != 2 {
                            return Err(format!("add_seconds expects exactly 2 arguments, got {}", evaluated_operands.len()));
                        }
                        let dt_str = evaluated_operands[0].as_str()?;
                        let seconds = evaluated_operands[1].as_integer()?;
                        let t = parse_utc(dt_str)?;
                        let added = t + chrono::Duration::seconds(seconds);
                        Ok(Value::String(Arc::from(added.format("%Y-%m-%dT%H:%M:%SZ").to_string())))
                    }
                    "parse_datetime" => {
                        if evaluated_operands.len() != 2 {
                            return Err(format!("parse_datetime expects exactly 2 arguments, got {}", evaluated_operands.len()));
                        }
                        let s = evaluated_operands[0].as_str()?;
                        let fmt = evaluated_operands[1].as_str()?;
                        if let Ok(dt) = chrono::DateTime::parse_from_str(s, fmt) {
                            let utc_dt = dt.with_timezone(&chrono::Utc);
                            Ok(Value::String(Arc::from(utc_dt.format("%Y-%m-%dT%H:%M:%SZ").to_string())))
                        } else if let Ok(ndt) = chrono::NaiveDateTime::parse_from_str(s, fmt) {
                            let dt = ndt.and_utc();
                            Ok(Value::String(Arc::from(dt.format("%Y-%m-%dT%H:%M:%SZ").to_string())))
                        } else if let Ok(nd) = chrono::NaiveDate::parse_from_str(s, fmt) {
                            if let Some(ndt) = nd.and_hms_opt(0, 0, 0) {
                                let dt = ndt.and_utc();
                                Ok(Value::String(Arc::from(dt.format("%Y-%m-%dT%H:%M:%SZ").to_string())))
                            } else {
                                Ok(Value::Nil)
                            }
                        } else {
                            Ok(Value::Nil)
                        }
                    }
                    "format_datetime" => {
                        if evaluated_operands.len() != 2 {
                            return Err(format!("format_datetime expects exactly 2 arguments, got {}", evaluated_operands.len()));
                        }
                        let dt_str = evaluated_operands[0].as_str()?;
                        let fmt = evaluated_operands[1].as_str()?;
                        let t = parse_utc(dt_str)?;
                        Ok(Value::String(Arc::from(t.format(fmt).to_string())))
                    }
                    "is_before" => {
                        if evaluated_operands.len() != 2 {
                            return Err(format!("is_before expects exactly 2 arguments, got {}", evaluated_operands.len()));
                        }
                        let dt1_str = evaluated_operands[0].as_str()?;
                        let dt2_str = evaluated_operands[1].as_str()?;
                        let t1 = parse_utc(dt1_str)?;
                        let t2 = parse_utc(dt2_str)?;
                        Ok(Value::Bool(t1 < t2))
                    }
                    "is_after" => {
                        if evaluated_operands.len() != 2 {
                            return Err(format!("is_after expects exactly 2 arguments, got {}", evaluated_operands.len()));
                        }
                        let dt1_str = evaluated_operands[0].as_str()?;
                        let dt2_str = evaluated_operands[1].as_str()?;
                        let t1 = parse_utc(dt1_str)?;
                        let t2 = parse_utc(dt2_str)?;
                        Ok(Value::Bool(t1 > t2))
                    }
                    "first" => {
                        if evaluated_operands.len() != 1 {
                            return Err(format!("first expects exactly 1 argument, got {}", evaluated_operands.len()));
                        }
                        match &evaluated_operands[0] {
                            Value::Array(a) => Ok(a.first().cloned().unwrap_or(Value::Nil)),
                            Value::Nil => Ok(Value::Nil),
                            _ => Err("first argument must be an array".to_string()),
                        }
                    }
                    "last" => {
                        if evaluated_operands.len() != 1 {
                            return Err(format!("last expects exactly 1 argument, got {}", evaluated_operands.len()));
                        }
                        match &evaluated_operands[0] {
                            Value::Array(a) => Ok(a.last().cloned().unwrap_or(Value::Nil)),
                            Value::Nil => Ok(Value::Nil),
                            _ => Err("last argument must be an array".to_string()),
                        }
                    }
                    "sum" => {
                        if evaluated_operands.len() != 2 {
                            return Err(format!("sum expects exactly 2 arguments, got {}", evaluated_operands.len()));
                        }
                        let array = match &evaluated_operands[0] {
                            Value::Array(a) => a,
                            Value::Nil => &Arc::new(Vec::new()),
                            _ => return Err("sum first argument must be an array".to_string()),
                        };
                        let field = evaluated_operands[1].as_str()?;
                        let mut sum_integer = 0i64;
                        let mut sum_decimal = Decimal::new(0, 0);
                        let mut has_integer = false;
                        let mut has_decimal = false;

                        for item in array.iter() {
                            let val = match item {
                                Value::Record(map) => map.get(field).cloned().unwrap_or(Value::Nil),
                                _ => return Err("sum expects record items in array".to_string()),
                            };
                            match val {
                                Value::Integer(i) => {
                                    sum_integer += i;
                                    has_integer = true;
                                }
                                Value::Decimal { value: v, scale: s } => {
                                    if !has_decimal {
                                        sum_decimal = Decimal::new(0, s);
                                        has_decimal = true;
                                    }
                                    let d = Decimal::new(v, s);
                                    sum_decimal = sum_decimal.add(&d)?;
                                }
                                Value::Nil => {}
                                _ => return Err(format!("Unsupported type for sum: {:?}", val)),
                            }
                        }
                        if has_decimal {
                            Ok(Value::Decimal { value: sum_decimal.value, scale: sum_decimal.scale })
                        } else {
                            Ok(Value::Integer(sum_integer))
                        }
                    }
                    "zip" => {
                        if evaluated_operands.len() != 2 {
                            return Err(format!("zip expects exactly 2 arguments, got {}", evaluated_operands.len()));
                        }
                        let array_a = match &evaluated_operands[0] {
                            Value::Array(a) => a,
                            _ => return Err("zip first argument must be an array".to_string()),
                        };
                        let array_b = match &evaluated_operands[1] {
                            Value::Array(a) => a,
                            _ => return Err("zip second argument must be an array".to_string()),
                        };
                        let len = std::cmp::min(array_a.len(), array_b.len());
                        let mut zipped = Vec::with_capacity(len);
                        for i in 0..len {
                            let mut map = std::collections::BTreeMap::new();
                            map.insert("first".to_string(), array_a[i].clone());
                            map.insert("second".to_string(), array_b[i].clone());
                            zipped.push(Value::Record(Arc::new(map)));
                        }
                        Ok(Value::Array(Arc::new(zipped)))
                    }
                    "stdlib.option.wrap" | "some" => {
                        if evaluated_operands.len() != 1 {
                            return Err(format!("some expects exactly 1 argument, got {}", evaluated_operands.len()));
                        }
                        Ok(evaluated_operands[0].clone())
                    }
                    "none" => {
                        if evaluated_operands.len() != 0 {
                            return Err(format!("none expects exactly 0 arguments, got {}", evaluated_operands.len()));
                        }
                        Ok(Value::Nil)
                    }
                    "ok" => {
                        if evaluated_operands.len() != 1 {
                            return Err(format!("ok expects exactly 1 argument, got {}", evaluated_operands.len()));
                        }
                        let mut map = std::collections::BTreeMap::new();
                        map.insert("ok".to_string(), evaluated_operands[0].clone());
                        Ok(Value::Record(Arc::new(map)))
                    }
                    "err" => {
                        if evaluated_operands.len() != 1 {
                            return Err(format!("err expects exactly 1 argument, got {}", evaluated_operands.len()));
                        }
                        let mut map = std::collections::BTreeMap::new();
                        map.insert("err".to_string(), evaluated_operands[0].clone());
                        Ok(Value::Record(Arc::new(map)))
                    }
                    "is_some" | "some?" => {
                        if evaluated_operands.len() != 1 {
                            return Err(format!("is_some expects exactly 1 argument, got {}", evaluated_operands.len()));
                        }
                        Ok(Value::Bool(evaluated_operands[0] != Value::Nil))
                    }
                    "is_none" | "none?" => {
                        if evaluated_operands.len() != 1 {
                            return Err(format!("is_none expects exactly 1 argument, got {}", evaluated_operands.len()));
                        }
                        Ok(Value::Bool(evaluated_operands[0] == Value::Nil))
                    }
                    "is_ok" | "ok?" => {
                        if evaluated_operands.len() != 1 {
                            return Err(format!("is_ok expects exactly 1 argument, got {}", evaluated_operands.len()));
                        }
                        let is_ok = match &evaluated_operands[0] {
                            Value::Record(map) => map.contains_key("ok"),
                            _ => false,
                        };
                        Ok(Value::Bool(is_ok))
                    }
                    "is_err" | "err?" => {
                        if evaluated_operands.len() != 1 {
                            return Err(format!("is_err expects exactly 1 argument, got {}", evaluated_operands.len()));
                        }
                        let is_err = match &evaluated_operands[0] {
                            Value::Record(map) => map.contains_key("err"),
                            _ => false,
                        };
                        Ok(Value::Bool(is_err))
                    }
                    "unwrap" => {
                        if evaluated_operands.len() != 1 {
                            return Err(format!("unwrap expects exactly 1 argument, got {}", evaluated_operands.len()));
                        }
                        match &evaluated_operands[0] {
                            Value::Record(map) => {
                                if let Some(ok_val) = map.get("ok") {
                                    Ok(ok_val.clone())
                                } else {
                                    Err(format!("Unwrapped Err: {:?}", evaluated_operands[0]))
                                }
                            }
                            _ => Err(format!("unwrap expects a Result, got {:?}", evaluated_operands[0])),
                        }
                    }
                    "or_else" | "unwrap_or" => {
                        if evaluated_operands.len() != 2 {
                            return Err(format!("{} expects exactly 2 arguments, got {}", op, evaluated_operands.len()));
                        }
                        let val = &evaluated_operands[0];
                        let fallback = &evaluated_operands[1];
                        match val {
                            Value::Nil => Ok(fallback.clone()),
                            Value::Record(map) => {
                                if map.contains_key("ok") {
                                    Ok(map.get("ok").unwrap().clone())
                                } else if map.contains_key("err") {
                                    Ok(fallback.clone())
                                } else {
                                    Ok(val.clone())
                                }
                            }
                            _ => Ok(val.clone()),
                        }
                    }
                    "take" => {
                        if evaluated_operands.len() != 2 {
                            return Err(format!("take expects exactly 2 arguments, got {}", evaluated_operands.len()));
                        }
                        let array = match &evaluated_operands[0] {
                            Value::Array(a) => a,
                            _ => return Err("take first argument must be an array".to_string()),
                        };
                        let n = evaluated_operands[1].as_integer()?;
                        if n <= 0 {
                            Ok(Value::Array(Arc::new(Vec::new())))
                        } else {
                            let limit = std::cmp::min(n as usize, array.len());
                            Ok(Value::Array(Arc::new(array[0..limit].to_vec())))
                        }
                    }
                    "avg" => {
                        if evaluated_operands.len() != 2 {
                            return Err(format!("avg expects exactly 2 arguments, got {}", evaluated_operands.len()));
                        }
                        let array = match &evaluated_operands[0] {
                            Value::Array(a) => a,
                            _ => return Err("avg first argument must be an array".to_string()),
                        };
                        if array.is_empty() {
                            Ok(Value::Nil)
                        } else {
                            let field = evaluated_operands[1].as_str()?;
                            let mut sum_integer = 0i64;
                            let mut sum_decimal = Decimal::new(0, 0);
                            let mut has_integer = false;
                            let mut has_decimal = false;
                            let mut count = 0i64;

                            for item in array.iter() {
                                let val = match item {
                                    Value::Record(map) => map.get(field).cloned().unwrap_or(Value::Nil),
                                    _ => return Err("avg expects record items in array".to_string()),
                                };
                                match val {
                                    Value::Integer(i) => {
                                        sum_integer += i;
                                        has_integer = true;
                                        count += 1;
                                    }
                                    Value::Decimal { value: v, scale: s } => {
                                        if !has_decimal {
                                            sum_decimal = Decimal::new(0, s);
                                            has_decimal = true;
                                        }
                                        let d = Decimal::new(v, s);
                                        sum_decimal = sum_decimal.add(&d)?;
                                        count += 1;
                                    }
                                    Value::Nil => {}
                                    _ => return Err(format!("Unsupported type for avg: {:?}", val)),
                                }
                            }

                            if count == 0 {
                                Ok(Value::Nil)
                            } else if has_decimal {
                                Ok(Value::Decimal { value: sum_decimal.value / count, scale: sum_decimal.scale })
                            } else {
                                Ok(Value::Integer(sum_integer / count))
                            }
                        }
                    }
                    "min" | "max" => {
                        if evaluated_operands.len() != 2 {
                            return Err(format!("min/max expects exactly 2 arguments, got {}", evaluated_operands.len()));
                        }
                        let array = match &evaluated_operands[0] {
                            Value::Array(a) => a,
                            _ => return Err("min/max first argument must be an array".to_string()),
                        };
                        if array.is_empty() {
                            Ok(Value::Nil)
                        } else {
                            let field = evaluated_operands[1].as_str()?;
                            let mut extremum: Option<Value> = None;

                            for item in array.iter() {
                                let val = match item {
                                    Value::Record(map) => map.get(field).cloned().unwrap_or(Value::Nil),
                                    _ => return Err("min/max expects record items".to_string()),
                                };
                                if val == Value::Nil { continue; }
                                match &extremum {
                                    None => { extremum = Some(val); }
                                    Some(current) => {
                                        let is_better = match (op, &val, current) {
                                            ("min", Value::Integer(x), Value::Integer(y)) => x < y,
                                            ("max", Value::Integer(x), Value::Integer(y)) => x > y,
                                            ("min", Value::Decimal { value: av, scale: as_ }, Value::Decimal { value: bv, scale: bs }) => {
                                                ((*av as f64) / 10f64.powi(*as_ as i32)) < ((*bv as f64) / 10f64.powi(*bs as i32))
                                            }
                                            ("max", Value::Decimal { value: av, scale: as_ }, Value::Decimal { value: bv, scale: bs }) => {
                                                ((*av as f64) / 10f64.powi(*as_ as i32)) > ((*bv as f64) / 10f64.powi(*bs as i32))
                                            }
                                            ("min", Value::Float(x), Value::Float(y)) => x < y,
                                            ("max", Value::Float(x), Value::Float(y)) => x > y,
                                            _ => false
                                        };
                                        if is_better {
                                            extremum = Some(val);
                                        }
                                    }
                                }
                            }
                            Ok(extremum.unwrap_or(Value::Nil))
                        }
                    }
                    "filter" => {
                        if evaluated_operands.len() != 2 {
                            return Err(format!("filter expects exactly 2 arguments, got {}", evaluated_operands.len()));
                        }
                        let array = match &evaluated_operands[0] {
                            Value::Array(a) => a,
                            _ => return Err("filter first argument must be an array".to_string()),
                        };
                        let lambda_str = evaluated_operands[1].as_str()?;
                        let lambda_ast: serde_json::Value = serde_json::from_str(lambda_str)
                            .map_err(|e| format!("Invalid lambda JSON in filter: {}", e))?;
                        
                        let params = lambda_ast.get("params")
                            .and_then(|p| p.as_array())
                            .ok_or("Missing params in lambda")?;
                        let param_name = params.first()
                            .and_then(|p| p.as_str())
                            .ok_or("Lambda must have at least one parameter")?;
                        let body = lambda_ast.get("body")
                            .ok_or("Missing body in lambda")?;
                        
                        let mut filtered = Vec::new();
                        for item in array.iter() {
                            let mut inner_env = local_env.clone();
                            inner_env.insert(param_name.to_string(), item.clone());
                            let cond_val = eval_ast(body, inputs, temporal_context, &inner_env, backend, vm).await?;
                            if cond_val.as_bool()? {
                                filtered.push(item.clone());
                            }
                        }
                        Ok(Value::Array(Arc::new(filtered)))
                    }
                    "find" => {
                        if evaluated_operands.len() != 2 {
                            return Err(format!("find expects exactly 2 arguments, got {}", evaluated_operands.len()));
                        }
                        let array = match &evaluated_operands[0] {
                            Value::Array(a) => a,
                            Value::Nil => return Ok(Value::Nil),
                            _ => return Err("find first argument must be an array".to_string()),
                        };
                        let lambda_str = evaluated_operands[1].as_str()?;
                        let lambda_ast: serde_json::Value = serde_json::from_str(lambda_str)
                            .map_err(|e| format!("Invalid lambda JSON in find: {}", e))?;
                        let params = lambda_ast.get("params")
                            .and_then(|p| p.as_array())
                            .ok_or("Missing params in lambda")?;
                        let param_name = params.first()
                            .and_then(|p| p.as_str())
                            .ok_or("Lambda must have at least one parameter")?;
                        let body = lambda_ast.get("body")
                            .ok_or("Missing body in lambda")?;
                        let mut found = Value::Nil;
                        for item in array.iter() {
                            let mut inner_env = local_env.clone();
                            inner_env.insert(param_name.to_string(), item.clone());
                            let cond_val = eval_ast(body, inputs, temporal_context, &inner_env, backend, vm).await?;
                            if cond_val.as_bool()? {
                                found = item.clone();
                                break;
                            }
                        }
                        Ok(found)
                    }
                    "any" => {
                        if evaluated_operands.len() != 2 {
                            return Err(format!("any expects exactly 2 arguments, got {}", evaluated_operands.len()));
                        }
                        let array = match &evaluated_operands[0] {
                            Value::Array(a) => a,
                            Value::Nil => return Ok(Value::Bool(false)),
                            _ => return Err("any first argument must be an array".to_string()),
                        };
                        let lambda_str = evaluated_operands[1].as_str()?;
                        let lambda_ast: serde_json::Value = serde_json::from_str(lambda_str)
                            .map_err(|e| format!("Invalid lambda JSON in any: {}", e))?;
                        let params = lambda_ast.get("params")
                            .and_then(|p| p.as_array())
                            .ok_or("Missing params in lambda")?;
                        let param_name = params.first()
                            .and_then(|p| p.as_str())
                            .ok_or("Lambda must have at least one parameter")?;
                        let body = lambda_ast.get("body")
                            .ok_or("Missing body in lambda")?;
                        let mut result = false;
                        for item in array.iter() {
                            let mut inner_env = local_env.clone();
                            inner_env.insert(param_name.to_string(), item.clone());
                            let cond_val = eval_ast(body, inputs, temporal_context, &inner_env, backend, vm).await?;
                            if cond_val.as_bool()? {
                                result = true;
                                break;
                            }
                        }
                        Ok(Value::Bool(result))
                    }
                    "all" => {
                        if evaluated_operands.len() != 2 {
                            return Err(format!("all expects exactly 2 arguments, got {}", evaluated_operands.len()));
                        }
                        let array = match &evaluated_operands[0] {
                            Value::Array(a) => a,
                            Value::Nil => return Ok(Value::Bool(true)),
                            _ => return Err("all first argument must be an array".to_string()),
                        };
                        let lambda_str = evaluated_operands[1].as_str()?;
                        let lambda_ast: serde_json::Value = serde_json::from_str(lambda_str)
                            .map_err(|e| format!("Invalid lambda JSON in all: {}", e))?;
                        let params = lambda_ast.get("params")
                            .and_then(|p| p.as_array())
                            .ok_or("Missing params in lambda")?;
                        let param_name = params.first()
                            .and_then(|p| p.as_str())
                            .ok_or("Lambda must have at least one parameter")?;
                        let body = lambda_ast.get("body")
                            .ok_or("Missing body in lambda")?;
                        let mut result = true;
                        for item in array.iter() {
                            let mut inner_env = local_env.clone();
                            inner_env.insert(param_name.to_string(), item.clone());
                            let cond_val = eval_ast(body, inputs, temporal_context, &inner_env, backend, vm).await?;
                            if !cond_val.as_bool()? {
                                result = false;
                                break;
                            }
                        }
                        Ok(Value::Bool(result))
                    }
                    "try_catch" => {
                        if evaluated_operands.len() != 2 {
                            return Err(format!("try_catch expects exactly 2 arguments, got {}", evaluated_operands.len()));
                        }
                        let res = &evaluated_operands[0];
                        match res {
                            Value::Record(map) if map.contains_key("ok") => {
                                Ok(map.get("ok").cloned().unwrap_or(Value::Nil))
                            }
                            Value::Record(map) if map.contains_key("err") => {
                                let err_val = map.get("err").cloned().unwrap_or(Value::Nil);
                                let lambda_str = evaluated_operands[1].as_str()?;
                                let lambda_ast: serde_json::Value = serde_json::from_str(lambda_str)
                                    .map_err(|e| format!("Invalid lambda JSON in try_catch: {}", e))?;
                                let params = lambda_ast.get("params")
                                    .and_then(|p| p.as_array())
                                    .ok_or("Missing params in try_catch lambda")?;
                                let param_name = params.first()
                                    .and_then(|p| p.as_str())
                                    .unwrap_or("e");
                                let body = lambda_ast.get("body")
                                    .ok_or("Missing body in try_catch lambda")?;
                                let mut inner_env = local_env.clone();
                                inner_env.insert(param_name.to_string(), err_val);
                                eval_ast(body, inputs, temporal_context, &inner_env, backend, vm).await
                            }
                            _ => Ok(res.clone()),
                        }
                    }
                    "propagate" => {
                        if evaluated_operands.is_empty() {
                            return Err("propagate expects 1 argument".to_string());
                        }
                        let res = &evaluated_operands[0];
                        match res {
                            Value::Record(map) if map.contains_key("ok") => {
                                Ok(map.get("ok").cloned().unwrap_or(Value::Nil))
                            }
                            Value::Record(map) if map.contains_key("err") => {
                                Ok(Value::Record(map.clone()))
                            }
                            _ => Ok(res.clone()),
                        }
                    }
                    "validate" => {
                        if evaluated_operands.len() != 3 {
                            return Err(format!("validate expects exactly 3 arguments, got {}", evaluated_operands.len()));
                        }
                        let val = evaluated_operands[0].clone();
                        let err_val = evaluated_operands[2].clone();
                        let lambda_str = evaluated_operands[1].as_str()?;
                        let lambda_ast: serde_json::Value = serde_json::from_str(lambda_str)
                            .map_err(|e| format!("Invalid lambda JSON in validate: {}", e))?;
                        let params = lambda_ast.get("params")
                            .and_then(|p| p.as_array())
                            .ok_or("Missing params in validate lambda")?;
                        let param_name = params.first()
                            .and_then(|p| p.as_str())
                            .unwrap_or("v");
                        let body = lambda_ast.get("body")
                            .ok_or("Missing body in validate lambda")?;
                        let mut inner_env = local_env.clone();
                        inner_env.insert(param_name.to_string(), val.clone());
                        let cond = eval_ast(body, inputs, temporal_context, &inner_env, backend, vm).await?;
                        if cond.as_bool().unwrap_or(false) {
                            let mut ok_map = std::collections::BTreeMap::new();
                            ok_map.insert("ok".to_string(), val);
                            Ok(Value::Record(Arc::new(ok_map)))
                        } else {
                            let mut err_map = std::collections::BTreeMap::new();
                            err_map.insert("err".to_string(), err_val);
                            Ok(Value::Record(Arc::new(err_map)))
                        }
                    }
                    "map" => {
                        if evaluated_operands.len() != 2 {
                            return Err(format!("map expects exactly 2 arguments, got {}", evaluated_operands.len()));
                        }
                        let coll = &evaluated_operands[0];
                        let lambda_str = evaluated_operands[1].as_str()?;
                        match coll {
                            Value::Array(array) => {
                                let lambda_ast: serde_json::Value = serde_json::from_str(lambda_str)
                                    .map_err(|e| format!("Invalid lambda JSON in map: {}", e))?;
                                let params = lambda_ast.get("params")
                                    .and_then(|p| p.as_array())
                                    .ok_or("Missing params in lambda")?;
                                let param_name = params.first()
                                    .and_then(|p| p.as_str())
                                    .ok_or("Lambda must have at least one parameter")?;
                                let body = lambda_ast.get("body")
                                    .ok_or("Missing body in lambda")?;
                                
                                let mut mapped = Vec::new();
                                for item in array.iter() {
                                    let mut inner_env = local_env.clone();
                                    inner_env.insert(param_name.to_string(), item.clone());
                                    let val = eval_ast(body, inputs, temporal_context, &inner_env, backend, vm).await?;
                                    mapped.push(val);
                                }
                                Ok(Value::Array(Arc::new(mapped)))
                            }
                            Value::Nil => Ok(Value::Nil),
                            Value::Record(map) if map.contains_key("ok") => {
                                let ok_val = map.get("ok").unwrap().clone();
                                let res = eval_lambda(lambda_str, ok_val, inputs, temporal_context, local_env, backend, vm).await?;
                                let mut new_map = std::collections::BTreeMap::new();
                                new_map.insert("ok".to_string(), res);
                                Ok(Value::Record(Arc::new(new_map)))
                            }
                            Value::Record(map) if map.contains_key("err") => {
                                Ok(coll.clone())
                            }
                            _ => {
                                // Option Some represented as raw value
                                let res = eval_lambda(lambda_str, coll.clone(), inputs, temporal_context, local_env, backend, vm).await?;
                                Ok(res)
                            }
                        }
                    }
                    "flat_map" | "and_then" => {
                        if evaluated_operands.len() != 2 {
                            return Err(format!("{} expects exactly 2 arguments, got {}", op, evaluated_operands.len()));
                        }
                        let coll = &evaluated_operands[0];
                        let lambda_str = evaluated_operands[1].as_str()?;
                        match coll {
                            Value::Array(array) => {
                                let lambda_ast: serde_json::Value = serde_json::from_str(lambda_str)
                                    .map_err(|e| format!("Invalid lambda JSON in flat_map: {}", e))?;
                                let params = lambda_ast.get("params")
                                    .and_then(|p| p.as_array())
                                    .ok_or("Missing params in lambda")?;
                                let param_name = params.first()
                                    .and_then(|p| p.as_str())
                                    .ok_or("Lambda must have at least one parameter")?;
                                let body = lambda_ast.get("body")
                                    .ok_or("Missing body in lambda")?;
                                
                                let mut flat_mapped = Vec::new();
                                for item in array.iter() {
                                    let mut inner_env = local_env.clone();
                                    inner_env.insert(param_name.to_string(), item.clone());
                                    let val = eval_ast(body, inputs, temporal_context, &inner_env, backend, vm).await?;
                                    match val {
                                        Value::Array(a) => flat_mapped.extend(a.iter().cloned()),
                                        v => flat_mapped.push(v),
                                    }
                                }
                                Ok(Value::Array(Arc::new(flat_mapped)))
                            }
                            Value::Nil => Ok(Value::Nil),
                            Value::Record(map) if map.contains_key("ok") => {
                                let ok_val = map.get("ok").unwrap().clone();
                                let res = eval_lambda(lambda_str, ok_val, inputs, temporal_context, local_env, backend, vm).await?;
                                Ok(res)
                            }
                            Value::Record(map) if map.contains_key("err") => {
                                Ok(coll.clone())
                            }
                            _ => {
                                // Option Some represented as raw value
                                let res = eval_lambda(lambda_str, coll.clone(), inputs, temporal_context, local_env, backend, vm).await?;
                                Ok(res)
                            }
                        }
                    }
                    "fold" | "reduce" => {
                        if evaluated_operands.len() != 3 {
                            return Err(format!("fold expects exactly 3 arguments, got {}", evaluated_operands.len()));
                        }
                        let array = match &evaluated_operands[0] {
                            Value::Array(a) => a,
                            _ => return Err("fold first argument must be an array".to_string()),
                        };
                        let init_val = evaluated_operands[1].clone();
                        let lambda_str = evaluated_operands[2].as_str()?;
                        let lambda_ast: serde_json::Value = serde_json::from_str(lambda_str)
                            .map_err(|e| format!("Invalid lambda JSON in fold: {}", e))?;
                        
                        let params = lambda_ast.get("params")
                            .and_then(|p| p.as_array())
                            .ok_or("Missing params in lambda")?;
                        if params.len() < 2 {
                            return Err("Lambda in fold/reduce must have at least 2 parameters (acc, item)".to_string());
                        }
                        let param_acc = params[0].as_str().ok_or("First parameter must be string")?;
                        let param_val = params[1].as_str().ok_or("Second parameter must be string")?;
                        let body = lambda_ast.get("body")
                            .ok_or("Missing body in lambda")?;
                        
                        let mut acc = init_val;
                        for item in array.iter() {
                            let mut inner_env = local_env.clone();
                            inner_env.insert(param_acc.to_string(), acc.clone());
                            inner_env.insert(param_val.to_string(), item.clone());
                            acc = eval_ast(body, inputs, temporal_context, &inner_env, backend, vm).await?;
                        }
                        Ok(acc)
                    }
                    "call_contract" => {
                        // Unified with the bytecode OP_CALL path via VM::call_contract_value.
                        // Enables cross-contract calls inside lambda / HOF bodies (tree-walked).
                        if evaluated_operands.is_empty() {
                            return Err("call_contract: missing contract name (first operand)".to_string());
                        }
                        let callee_name = match &evaluated_operands[0] {
                            Value::String(s) => s.to_string(),
                            other => return Err(format!(
                                "call_contract: first operand must be String (contract name), got {:?}", other
                            )),
                        };
                        vm.call_contract_value(&callee_name, &evaluated_operands[1..], temporal_context).await
                    }
                    _ => {
                        if evaluated_operands.len() != 2 {
                            return Err(format!("Operator {} expects exactly 2 operands; got {}", op, evaluated_operands.len()));
                        }
                        let left_val = &evaluated_operands[0];
                        let right_val = &evaluated_operands[1];
                        match op {
                            "+" | "add" | "stdlib.numeric.add" => {
                                match (left_val, right_val) {
                                    (Value::Decimal { value: av, scale: as_ }, Value::Decimal { value: bv, scale: bs }) => {
                                        let da = Decimal::new(*av, *as_);
                                        let db = Decimal::new(*bv, *bs);
                                        match da.add(&db) {
                                            Ok(res_dec) => Ok(Value::Decimal { value: res_dec.value, scale: res_dec.scale }),
                                            Err(e) => Err(e),
                                        }
                                    }
                                    (Value::Integer(av), Value::Integer(bv)) => Ok(Value::Integer(av + bv)),
                                    (Value::Float(av), Value::Float(bv)) => Ok(Value::Float(av + bv)),
                                    _ => Err(format!("Invalid operand types for ADD: {:?} + {:?}", left_val, right_val)),
                                }
                            }
                            "-" | "sub" => {
                                match (left_val, right_val) {
                                    (Value::Decimal { value: av, scale: as_ }, Value::Decimal { value: bv, scale: bs }) => {
                                        let da = Decimal::new(*av, *as_);
                                        let db = Decimal::new(*bv, *bs);
                                        match da.sub(&db) {
                                            Ok(res_dec) => Ok(Value::Decimal { value: res_dec.value, scale: res_dec.scale }),
                                            Err(e) => Err(e),
                                        }
                                    }
                                    (Value::Integer(av), Value::Integer(bv)) => Ok(Value::Integer(av - bv)),
                                    (Value::Float(av), Value::Float(bv)) => Ok(Value::Float(av - bv)),
                                    _ => Err(format!("Invalid operand types for SUB: {:?} - {:?}", left_val, right_val)),
                                }
                            }
                            "*" | "mul" => {
                                match (left_val, right_val) {
                                    (Value::Decimal { value: av, scale: as_ }, Value::Decimal { value: bv, scale: bs }) => {
                                        let da = Decimal::new(*av, *as_);
                                        let db = Decimal::new(*bv, *bs);
                                        let res_dec = da.mul(&db);
                                        Ok(Value::Decimal { value: res_dec.value, scale: res_dec.scale })
                                    }
                                    (Value::Integer(av), Value::Integer(bv)) => Ok(Value::Integer(av * bv)),
                                    (Value::Float(av), Value::Float(bv)) => Ok(Value::Float(av * bv)),
                                    _ => Err(format!("Invalid operand types for MUL: {:?} * {:?}", left_val, right_val)),
                                }
                            }
                            "/" | "div" => {
                                match (left_val, right_val) {
                                    (Value::Decimal { value: av, scale: as_ }, Value::Decimal { value: bv, scale: bs }) => {
                                        let da = Decimal::new(*av, *as_);
                                        let db = Decimal::new(*bv, *bs);
                                        match da.div(&db) {
                                            Ok(res_dec) => Ok(Value::Decimal { value: res_dec.value, scale: res_dec.scale }),
                                            Err(e) => Err(e),
                                        }
                                    }
                                    (Value::Integer(av), Value::Integer(bv)) => {
                                        if *bv == 0 {
                                            Err("Division by zero".to_string())
                                        } else {
                                            Ok(Value::Integer(av / bv))
                                        }
                                    }
                                    (Value::Float(av), Value::Float(bv)) => {
                                        if *bv == 0.0 {
                                            Err("Division by zero".to_string())
                                        } else {
                                            Ok(Value::Float(av / bv))
                                        }
                                    }
                                    _ => Err(format!("Invalid operand types for DIV: {:?} / {:?}", left_val, right_val)),
                                }
                            }
                            "==" | "eq" => {
                                Ok(Value::Bool(left_val == right_val))
                            }
                            "!=" | "ne" => {
                                Ok(Value::Bool(left_val != right_val))
                            }
                            ">" | "gt" | "stdlib.integer.gt" => {
                                match (left_val, right_val) {
                                    (Value::Decimal { value: av, scale: as_ }, Value::Decimal { value: bv, scale: bs }) => {
                                        let da = Decimal::new(*av, *as_);
                                        let db = Decimal::new(*bv, *bs);
                                        Ok(Value::Bool(da.to_f64() > db.to_f64()))
                                    }
                                    (Value::Integer(av), Value::Integer(bv)) => Ok(Value::Bool(av > bv)),
                                    (Value::Float(av), Value::Float(bv)) => Ok(Value::Bool(av > bv)),
                                    _ => Err(format!("Invalid operand types for GT: {:?} > {:?}", left_val, right_val)),
                                }
                            }
                            "<" | "lt" | "stdlib.integer.lt" => {
                                match (left_val, right_val) {
                                    (Value::Decimal { value: av, scale: as_ }, Value::Decimal { value: bv, scale: bs }) => {
                                        let da = Decimal::new(*av, *as_);
                                        let db = Decimal::new(*bv, *bs);
                                        Ok(Value::Bool(da.to_f64() < db.to_f64()))
                                    }
                                    (Value::Integer(av), Value::Integer(bv)) => Ok(Value::Bool(av < bv)),
                                    (Value::Float(av), Value::Float(bv)) => Ok(Value::Bool(av < bv)),
                                    (Value::String(av), Value::String(bv)) => Ok(Value::Bool(av < bv)),
                                    _ => Err(format!("Invalid operand types for LT: {:?} < {:?}", left_val, right_val)),
                                }
                            }
                            "<=" | "le" | "stdlib.integer.lte" => {
                                match (left_val, right_val) {
                                    (Value::Decimal { value: av, scale: as_ }, Value::Decimal { value: bv, scale: bs }) => {
                                        let da = Decimal::new(*av, *as_);
                                        let db = Decimal::new(*bv, *bs);
                                        Ok(Value::Bool(da.to_f64() <= db.to_f64()))
                                    }
                                    (Value::Integer(av), Value::Integer(bv)) => Ok(Value::Bool(av <= bv)),
                                    (Value::Float(av), Value::Float(bv)) => Ok(Value::Bool(av <= bv)),
                                    (Value::String(av), Value::String(bv)) => Ok(Value::Bool(av <= bv)),
                                    _ => Err(format!("Invalid operand types for LE: {:?} <= {:?}", left_val, right_val)),
                                }
                            }
                            ">=" | "ge" | "stdlib.integer.gte" => {
                                match (left_val, right_val) {
                                    (Value::Decimal { value: av, scale: as_ }, Value::Decimal { value: bv, scale: bs }) => {
                                        let da = Decimal::new(*av, *as_);
                                        let db = Decimal::new(*bv, *bs);
                                        Ok(Value::Bool(da.to_f64() >= db.to_f64()))
                                    }
                                    (Value::Integer(av), Value::Integer(bv)) => Ok(Value::Bool(av >= bv)),
                                    (Value::Float(av), Value::Float(bv)) => Ok(Value::Bool(av >= bv)),
                                    (Value::String(av), Value::String(bv)) => Ok(Value::Bool(av >= bv)),
                                    _ => Err(format!("Invalid operand types for GE: {:?} >= {:?}", left_val, right_val)),
                                }
                            }
                            "&&" | "and" => {
                                match (left_val, right_val) {
                                    (Value::Bool(av), Value::Bool(bv)) => Ok(Value::Bool(*av && *bv)),
                                    _ => Err(format!("Invalid operand types for AND: {:?} && {:?}", left_val, right_val)),
                                }
                            }
                            "||" | "or" => {
                                match (left_val, right_val) {
                                    (Value::Bool(av), Value::Bool(bv)) => Ok(Value::Bool(*av || *bv)),
                                    _ => Err(format!("Invalid operand types for OR: {:?} || {:?}", left_val, right_val)),
                                }
                            }
                            "++" | "concat" => {
                                match (left_val, right_val) {
                                    (Value::String(av), Value::String(bv)) => {
                                        let mut s = av.to_string();
                                        s.push_str(bv);
                                        Ok(Value::String(Arc::from(s.as_str())))
                                    }
                                    (Value::Array(av), Value::Array(bv)) => {
                                        let mut list = (**av).clone();
                                        list.extend_from_slice(bv);
                                        Ok(Value::Array(Arc::new(list)))
                                    }
                                    _ => Err(format!("Invalid operand types for CONCAT: {:?} ++ {:?}", left_val, right_val)),
                                }
                            }
                            _ => Err(format!("Unsupported operator: {}", op)),
                        }
                    }
                }
            }
            _ => Err(format!("Unsupported AST kind in VM evaluator: {}", kind)),
        }
    })
}

fn eval_lambda<'a>(
    lambda_str: &'a str,
    arg: Value,
    inputs: &'a HashMap<String, Value>,
    temporal_context: &'a HashMap<String, Value>,
    local_env: &'a HashMap<String, Value>,
    backend: &'a Option<Arc<dyn TBackend>>,
    vm: &'a VM,
) -> std::pin::Pin<Box<dyn std::future::Future<Output = Result<Value, String>> + Send + 'a>> {
    Box::pin(async move {
        let lambda_ast: serde_json::Value = serde_json::from_str(lambda_str)
            .map_err(|e| format!("Invalid lambda JSON: {}", e))?;
        let params = lambda_ast.get("params")
            .and_then(|p| p.as_array())
            .ok_or("Missing params in lambda")?;
        let param_name = params.first()
            .and_then(|p| p.as_str())
            .ok_or("Lambda must have at least one parameter")?;
        let body = lambda_ast.get("body")
            .ok_or("Missing body in lambda")?;
        let mut inner_env = local_env.clone();
        inner_env.insert(param_name.to_string(), arg);
        eval_ast(body, inputs, temporal_context, &inner_env, backend, vm).await
    })
}

// SHA256 hex digest generator slicing first 16 characters
fn sha256_hex(input: &str) -> String {

    use sha2::{Sha256, Digest};
    let mut hasher = Sha256::new();
    hasher.update(input.as_bytes());
    let result = hasher.finalize();
    hex::encode(&result[0..8]) // 8 bytes = 16 hex chars
}

// Closure conversion (LAB-VM-HOF-CLOSURE-CONVERSION-P1): recursively gather every
// `captures` entry in a lambda artifact (including nested lambdas) and resolve each
// to its enclosing-contract register value. All captures reference the contract that
// is currently executing, so the live `registers` map resolves them at any nesting.
fn collect_captures(
    v: &serde_json::Value,
    registers: &HashMap<i64, Value>,
    out: &mut HashMap<String, Value>,
) {
    match v {
        serde_json::Value::Object(map) => {
            if let Some(caps) = map.get("captures").and_then(|c| c.as_array()) {
                for cap in caps {
                    if let (Some(n), Some(r)) = (
                        cap.get("name").and_then(|x| x.as_str()),
                        cap.get("reg").and_then(|x| x.as_i64()),
                    ) {
                        if let Some(val) = registers.get(&r) {
                            out.insert(n.to_string(), val.clone());
                        }
                    }
                }
            }
            for (_, c) in map.iter() { collect_captures(c, registers, out); }
        }
        serde_json::Value::Array(arr) => { for c in arr.iter() { collect_captures(c, registers, out); } }
        _ => {}
    }
}
