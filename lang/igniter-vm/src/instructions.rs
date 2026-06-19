// src/instructions.rs
// Bytecode Instruction Definitions for the Igniter Virtual Machine (IVM)

use crate::value::Value;

// Opcodes mapping to unique 8-bit integers
pub const OP_PUSH_LIT: u8 = 0x01; // Argument: literal value
pub const OP_LOAD_REF: u8 = 0x02; // Argument: string symbol name
pub const OP_STORE_REG: u8 = 0x03; // Argument: register index (Integer)
pub const OP_LOAD_REG: u8 = 0x04; // Argument: register index (Integer)
pub const OP_ADD: u8 = 0x05; // None
pub const OP_SUB: u8 = 0x06; // None
pub const OP_MUL: u8 = 0x07; // None
pub const OP_DIV: u8 = 0x08; // None
pub const OP_EQ: u8 = 0x09; // None
pub const OP_JMP: u8 = 0x0A; // Argument: instruction pointer offset (Integer)
pub const OP_JMP_IF: u8 = 0x0B; // Argument: instruction pointer offset (Integer)
pub const OP_JMP_UNLESS: u8 = 0x0C; // Argument: instruction pointer offset (Integer)
pub const OP_LOAD_AS_OF: u8 = 0x0D; // Arguments: [store_name, as_of_input_ref]
pub const OP_EMIT_OBS: u8 = 0x0E; // Argument: observation kind (String)
pub const OP_RET: u8 = 0x0F; // None
pub const OP_GT: u8 = 0x10; // None
pub const OP_MAP_REDUCE: u8 = 0x11; // Argument: map_reduce descriptor JSON
pub const OP_LOOP_START: u8 = 0x12; // Arguments: [name: String, max_steps: Integer]
pub const OP_LOOP_STEP: u8 = 0x13; // Argument: exit_ip (Integer)
pub const OP_LOOP_BREAK: u8 = 0x14; // None
pub const OP_LOAD_TICK: u8 = 0x15; // Argument: interval_ms (Integer)
pub const OP_LT: u8 = 0x16; // None
pub const OP_LE: u8 = 0x17; // None
pub const OP_GE: u8 = 0x18; // None
pub const OP_NE: u8 = 0x19; // None
pub const OP_AND: u8 = 0x1A; // None
pub const OP_OR: u8 = 0x1B; // None
pub const OP_NOT: u8 = 0x1C; // None
pub const OP_CONCAT: u8 = 0x1D; // None
pub const OP_PUSH_ARRAY: u8 = 0x1E; // Argument: element_count (Integer)
pub const OP_PUSH_RECORD: u8 = 0x1F; // Argument: key_count (Integer), followed by keys and values
pub const OP_CALL: u8 = 0x20; // Arguments: [fn_name: String, arg_count: Integer]
pub const OP_NEG: u8 = 0x21; // None
pub const OP_GET_FIELD: u8 = 0x22; // Argument: field_name (String) — pops record, pushes field value
pub const OP_UNSUPPORTED: u8 = 0x99; // None

#[derive(Debug, Clone)]
pub struct Instruction {
    pub opcode: u8,
    pub args: Vec<Value>,
}

// LAB-SRCMAP-P2: human-readable mnemonic for an opcode byte.
pub fn opcode_mnemonic(opcode: u8) -> &'static str {
    match opcode {
        OP_PUSH_LIT => "PUSH_LIT",
        OP_LOAD_REF => "LOAD_REF",
        OP_STORE_REG => "STORE_REG",
        OP_LOAD_REG => "LOAD_REG",
        OP_ADD => "ADD",
        OP_SUB => "SUB",
        OP_MUL => "MUL",
        OP_DIV => "DIV",
        OP_EQ => "EQ",
        OP_JMP => "JMP",
        OP_JMP_IF => "JMP_IF",
        OP_JMP_UNLESS => "JMP_UNLESS",
        OP_LOAD_AS_OF => "LOAD_AS_OF",
        OP_EMIT_OBS => "EMIT_OBS",
        OP_RET => "RET",
        OP_GT => "GT",
        OP_MAP_REDUCE => "MAP_REDUCE",
        OP_LOOP_START => "LOOP_START",
        OP_LOOP_STEP => "LOOP_STEP",
        OP_LOOP_BREAK => "LOOP_BREAK",
        OP_LOAD_TICK => "LOAD_TICK",
        OP_LT => "LT",
        OP_LE => "LE",
        OP_GE => "GE",
        OP_NE => "NE",
        OP_AND => "AND",
        OP_OR => "OR",
        OP_NOT => "NOT",
        OP_CONCAT => "CONCAT",
        OP_PUSH_ARRAY => "PUSH_ARRAY",
        OP_PUSH_RECORD => "PUSH_RECORD",
        OP_CALL => "CALL",
        OP_NEG => "NEG",
        OP_GET_FIELD => "GET_FIELD",
        OP_UNSUPPORTED => "UNSUPPORTED",
        _ => "UNKNOWN",
    }
}

impl Instruction {
    pub fn new(opcode: u8, args: Vec<Value>) -> Self {
        Instruction { opcode, args }
    }

    pub fn from_json(jv: &serde_json::Value) -> Result<Self, String> {
        let obj = jv.as_object().ok_or("Instruction must be a JSON Object")?;
        let opcode = obj
            .get("opcode")
            .ok_or("Missing 'opcode'")?
            .as_u64()
            .ok_or("Opcode must be an integer")? as u8;

        let args_val = obj.get("args").ok_or("Missing 'args'")?;
        let args_arr = args_val.as_array().ok_or("Args must be an array")?;
        let args = args_arr.iter().map(Value::from_json).collect();

        Ok(Instruction { opcode, args })
    }
}
