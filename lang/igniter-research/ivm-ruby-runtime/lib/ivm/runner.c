#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// Bounded IVM Bytecode Instruction representation
typedef struct {
    int32_t opcode;
    int32_t arg;
} Instruction;

// Bounded IVM Native Bytecode Execution Engine
// Implements BCP-1 to BCP-12 correct parity execution logic
int32_t execute_bytecode(const Instruction* instructions, int32_t count, const int32_t* inputs, int32_t* error_code) {
    int32_t stack[256];
    int32_t sp = 0;
    int32_t ip = 0;

    if (count <= 0 || instructions == NULL) {
        *error_code = 6; // Malformed input
        return -1;
    }

    while (ip < count) {
        Instruction inst = instructions[ip];
        
        switch (inst.opcode) {
            case 0x01: // OP_PUSH_LIT
                if (sp >= 256) {
                    *error_code = 7; // Stack overflow
                    return -1;
                }
                stack[sp++] = inst.arg;
                ip++;
                break;

            case 0x02: // OP_LOAD_REF
                if (sp >= 256) {
                    *error_code = 7; // Stack overflow
                    return -1;
                }
                stack[sp++] = inputs[inst.arg];
                ip++;
                break;

            case 0x05: // OP_ADD
                if (sp < 2) {
                    *error_code = 1; // Stack underflow
                    return -1;
                }
                {
                    int32_t b = stack[--sp];
                    int32_t a = stack[--sp];
                    stack[sp++] = a + b;
                }
                ip++;
                break;

            case 0x10: // OP_GT
                if (sp < 2) {
                    *error_code = 1; // Stack underflow
                    return -1;
                }
                {
                    int32_t b = stack[--sp];
                    int32_t a = stack[--sp];
                    stack[sp++] = (a > b) ? 1 : 0;
                }
                ip++;
                break;

            case 0x0A: // OP_JMP
                if (inst.arg < 0 || inst.arg >= count) {
                    *error_code = 4; // Out of bounds jump
                    return -1;
                }
                ip = inst.arg;
                break;

            case 0x0C: // OP_JMP_UNLESS
                if (sp < 1) {
                    *error_code = 1; // Stack underflow
                    return -1;
                }
                {
                    int32_t cond = stack[--sp];
                    if (cond != 0 && cond != 1) {
                        *error_code = 5; // Condition type error (non-bool)
                        return -1;
                    }
                    if (cond == 0) {
                        if (inst.arg < 0 || inst.arg >= count) {
                            *error_code = 4; // Out of bounds jump
                            return -1;
                        }
                        ip = inst.arg;
                    } else {
                        ip++;
                    }
                }
                break;

            case 0x0F: // OP_RET
                if (sp < 1) {
                    *error_code = 1; // Stack underflow
                    return -1;
                }
                *error_code = 0; // Success
                return stack[--sp];

            case 0x99: // OP_UNSUPPORTED
                *error_code = 3; // Unsupported selected-path node
                return -1;

            default:
                *error_code = 3; // Unknown instruction
                return -1;
        }
    }

    *error_code = 8; // Halt without RET
    return -1;
}

// Bounded IVM Native AOT Bytecode File Execution Engine
int32_t execute_bytecode_file(const char* filepath, const int32_t* inputs, int32_t* error_code) {
    FILE* f = fopen(filepath, "rb");
    if (!f) {
        *error_code = 9; // File not found / open error
        return -1;
    }

    // Read header (16 bytes)
    uint8_t header[16];
    if (fread(header, 1, 16, f) != 16) {
        fclose(f);
        *error_code = 10; // Malformed header / read error
        return -1;
    }

    // Verify magic bytes: "IGB\x00"
    if (header[0] != 'I' || header[1] != 'G' || header[2] != 'B' || header[3] != 0x00) {
        fclose(f);
        *error_code = 11; // Invalid magic header
        return -1;
    }

    // Verify version (must be 1)
    int32_t version = *(int32_t*)(header + 4);
    if (version != 1) {
        fclose(f);
        *error_code = 12; // Unsupported version
        return -1;
    }

    // Verify instruction count
    int32_t count = *(int32_t*)(header + 8);
    if (count <= 0 || count > 10000) {
        fclose(f);
        *error_code = 13; // Invalid instruction count
        return -1;
    }

    // Verify file size matches expected length (16 + 8 * count)
    fseek(f, 0, SEEK_END);
    long file_size = ftell(f);
    fseek(f, 16, SEEK_SET);

    if (file_size != 16 + 8 * count) {
        fclose(f);
        *error_code = 14; // File length mismatch
        return -1;
    }

    // Read instructions
    Instruction* instructions = (Instruction*)malloc(sizeof(Instruction) * count);
    if (!instructions) {
        fclose(f);
        *error_code = 15; // Memory allocation failure
        return -1;
    }

    if (fread(instructions, sizeof(Instruction), count, f) != count) {
        free(instructions);
        fclose(f);
        *error_code = 16; // Bytecode read error
        return -1;
    }

    fclose(f);

    // Structural validations: invalid opcodes and out-of-bounds jumps
    for (int32_t i = 0; i < count; i++) {
        int32_t op = instructions[i].opcode;
        int32_t arg = instructions[i].arg;
        
        // Supported opcodes check: 0x01, 0x02, 0x05, 0x09, 0x10, 0x0A, 0x0C, 0x0F, 0x0D, 0x99
        if (op != 0x01 && op != 0x02 && op != 0x05 && op != 0x09 && op != 0x10 && op != 0x0A && op != 0x0C && op != 0x0F && op != 0x0D && op != 0x99) {
            free(instructions);
            *error_code = 17; // Invalid opcode in file
            return -1;
        }

        // Jump boundary check ahead of execution
        if (op == 0x0A || op == 0x0C) {
            if (arg < 0 || arg >= count) {
                free(instructions);
                *error_code = 4; // Out of bounds jump
                return -1;
            }
        }
    }

    // Execute the bytecode
    int32_t res = execute_bytecode(instructions, count, inputs, error_code);

    free(instructions);
    return res;
}

// LoadedModule struct packaging bytecode in memory
typedef struct {
    Instruction* instructions;
    int32_t count;
} LoadedModule;

// Load AOT binary file once into memory (Module Loading Stage)
LoadedModule* load_module(const char* filepath, int32_t* error_code) {
    FILE* f = fopen(filepath, "rb");
    if (!f) {
        *error_code = 9; // File not found
        return NULL;
    }

    uint8_t header[16];
    if (fread(header, 1, 16, f) != 16) {
        fclose(f);
        *error_code = 10; // Malformed header
        return NULL;
    }

    if (header[0] != 'I' || header[1] != 'G' || header[2] != 'B' || header[3] != 0x00) {
        fclose(f);
        *error_code = 11; // Invalid magic header
        return NULL;
    }

    int32_t version = *(int32_t*)(header + 4);
    if (version != 1) {
        fclose(f);
        *error_code = 12; // Unsupported version
        return NULL;
    }

    int32_t count = *(int32_t*)(header + 8);
    if (count <= 0 || count > 10000) {
        fclose(f);
        *error_code = 13; // Invalid instruction count
        return NULL;
    }

    fseek(f, 0, SEEK_END);
    long file_size = ftell(f);
    fseek(f, 16, SEEK_SET);

    if (file_size != 16 + 8 * count) {
        fclose(f);
        *error_code = 14; // File length mismatch
        return NULL;
    }

    Instruction* instructions = (Instruction*)malloc(sizeof(Instruction) * count);
    if (!instructions) {
        fclose(f);
        *error_code = 15; // Memory allocation failure
        return NULL;
    }

    if (fread(instructions, sizeof(Instruction), count, f) != count) {
        free(instructions);
        fclose(f);
        *error_code = 16; // Bytecode read error
        return NULL;
    }

    fclose(f);

    // Static analysis validation of opcodes and jumps ahead of execution
    for (int32_t i = 0; i < count; i++) {
        int32_t op = instructions[i].opcode;
        int32_t arg = instructions[i].arg;
        
        if (op != 0x01 && op != 0x02 && op != 0x05 && op != 0x09 && op != 0x10 && op != 0x0A && op != 0x0C && op != 0x0F && op != 0x0D && op != 0x99) {
            free(instructions);
            *error_code = 17; // Invalid opcode
            return NULL;
        }

        if (op == 0x0A || op == 0x0C) {
            if (arg < 0 || arg >= count) {
                free(instructions);
                *error_code = 4; // Out of bounds jump
                return NULL;
            }
        }
    }

    LoadedModule* module = (LoadedModule*)malloc(sizeof(LoadedModule));
    if (!module) {
        free(instructions);
        *error_code = 15; // Memory allocation failure
        return NULL;
    }

    module->instructions = instructions;
    module->count = count;
    *error_code = 0; // Success
    return module;
}

// Execute loaded module in-memory (Timeline Evaluation Stage)
int32_t execute_module(const LoadedModule* module, const int32_t* inputs, int32_t* error_code) {
    if (!module || !module->instructions || module->count <= 0) {
        *error_code = 6; // Malformed input module
        return -1;
    }
    return execute_bytecode(module->instructions, module->count, inputs, error_code);
}

// Free module resources to prevent memory leaks
void free_module(LoadedModule* module) {
    if (module) {
        if (module->instructions) {
            free(module->instructions);
        }
        free(module);
    }
}

// Bitemporal Historical Point Representation in C
typedef struct {
    int64_t valid_time;
    int32_t value;
} HistoricalRecord;

// Bitemporal Database Store/Table in C
typedef struct {
    char store_name[64];
    HistoricalRecord* records;
    int32_t count;
    int32_t capacity;
} TemporalStore;

// Pluggable Temporal Database Backend in C (Minimal MemoryHistoryBackend)
typedef struct {
    TemporalStore* stores;
    int32_t count;
    int32_t capacity;
} TemporalBackend;

// Create a new dynamic C TemporalBackend
TemporalBackend* create_backend() {
    TemporalBackend* backend = (TemporalBackend*)malloc(sizeof(TemporalBackend));
    if (!backend) return NULL;
    backend->stores = NULL;
    backend->count = 0;
    backend->capacity = 0;
    return backend;
}

// Write historical data point directly into C Backend (populates memory history)
void write_backend_history(TemporalBackend* backend, const char* store_name, int64_t valid_time, int32_t value) {
    if (!backend) return;

    TemporalStore* store = NULL;
    for (int i = 0; i < backend->count; i++) {
        if (strcmp(backend->stores[i].store_name, store_name) == 0) {
            store = &backend->stores[i];
            break;
        }
    }

    if (!store) {
        if (backend->count >= backend->capacity) {
            backend->capacity = backend->capacity == 0 ? 4 : backend->capacity * 2;
            backend->stores = (TemporalStore*)realloc(backend->stores, sizeof(TemporalStore) * backend->capacity);
        }
        store = &backend->stores[backend->count++];
        strncpy(store->store_name, store_name, 63);
        store->store_name[63] = '\0';
        store->records = NULL;
        store->count = 0;
        store->capacity = 0;
    }

    if (store->count >= store->capacity) {
        store->capacity = store->capacity == 0 ? 4 : store->capacity * 2;
        store->records = (HistoricalRecord*)realloc(store->records, sizeof(HistoricalRecord) * store->capacity);
    }

    store->records[store->count].valid_time = valid_time;
    store->records[store->count].value = value;
    store->count++;

    // Maintain sorted order by valid_time ascending (Insertion Sort)
    for (int i = store->count - 1; i > 0; i--) {
        if (store->records[i].valid_time < store->records[i-1].valid_time) {
            HistoricalRecord temp = store->records[i];
            store->records[i] = store->records[i-1];
            store->records[i-1] = temp;
        } else {
            break;
        }
    }
}

// Read closest value as of valid time completely in C (Zero FFI boundary queries)
int32_t read_as_of_c(const TemporalBackend* backend, int32_t store_idx, int64_t query_time, int32_t* matched) {
    if (!backend || store_idx < 0 || store_idx >= backend->count) {
        *matched = 0;
        return -1;
    }

    const TemporalStore* store = &backend->stores[store_idx];
    for (int i = store->count - 1; i >= 0; i--) {
        if (store->records[i].valid_time <= query_time) {
            *matched = 1;
            return store->records[i].value;
        }
    }

    *matched = 0;
    return -1;
}

// Free C temporal backend memory to prevent leaks
void free_backend(TemporalBackend* backend) {
    if (backend) {
        for (int i = 0; i < backend->count; i++) {
            if (backend->stores[i].records) {
                free(backend->stores[i].records);
            }
        }
        if (backend->stores) {
            free(backend->stores);
        }
        free(backend);
    }
}

// Fully featured C bytecode interpreter loop with OP_LOAD_AS_OF temporal support
int32_t execute_bytecode_temporal(const Instruction* instructions, int32_t count, const int32_t* inputs, const TemporalBackend* backend, int32_t* error_code) {
    int32_t stack[256];
    int32_t sp = 0;
    int32_t ip = 0;

    if (count <= 0 || instructions == NULL) {
        *error_code = 6; // Malformed input
        return -1;
    }

    while (ip < count) {
        Instruction inst = instructions[ip];
        
        switch (inst.opcode) {
            case 0x01: // OP_PUSH_LIT
                if (sp >= 256) {
                    *error_code = 7; // Stack overflow
                    return -1;
                }
                stack[sp++] = inst.arg;
                ip++;
                break;

            case 0x02: // OP_LOAD_REF
                if (sp >= 256) {
                    *error_code = 7; // Stack overflow
                    return -1;
                }
                stack[sp++] = inputs[inst.arg];
                ip++;
                break;

            case 0x05: // OP_ADD
                if (sp < 2) {
                    *error_code = 1; // Stack underflow
                    return -1;
                }
                {
                    int32_t b = stack[--sp];
                    int32_t a = stack[--sp];
                    stack[sp++] = a + b;
                }
                ip++;
                break;

            case 0x09: // OP_EQ
                if (sp < 2) {
                    *error_code = 1; // Stack underflow
                    return -1;
                }
                {
                    int32_t b = stack[--sp];
                    int32_t a = stack[--sp];
                    stack[sp++] = (a == b) ? 1 : 0;
                }
                ip++;
                break;

            case 0x10: // OP_GT
                if (sp < 2) {
                    *error_code = 1; // Stack underflow
                    return -1;
                }
                {
                    int32_t b = stack[--sp];
                    int32_t a = stack[--sp];
                    stack[sp++] = (a > b) ? 1 : 0;
                }
                ip++;
                break;

            case 0x0A: // OP_JMP
                if (inst.arg < 0 || inst.arg >= count) {
                    *error_code = 4; // Out of bounds jump
                    return -1;
                }
                ip = inst.arg;
                break;

            case 0x0C: // OP_JMP_UNLESS
                if (sp < 1) {
                    *error_code = 1; // Stack underflow
                    return -1;
                }
                {
                    int32_t cond = stack[--sp];
                    if (cond != 0 && cond != 1) {
                        *error_code = 5; // Condition type error
                        return -1;
                    }
                    if (cond == 0) {
                        if (inst.arg < 0 || inst.arg >= count) {
                            *error_code = 4; // Out of bounds jump
                            return -1;
                        }
                        ip = inst.arg;
                    } else {
                        ip++;
                    }
                }
                break;

            case 0x0D: // OP_LOAD_AS_OF
                if (sp >= 256) {
                    *error_code = 7; // Stack overflow
                    return -1;
                }
                {
                    int32_t store_idx = (inst.arg >> 16) & 0xFFFF;
                    int32_t as_of_ref_idx = inst.arg & 0xFFFF;
                    
                    int64_t query_time = inputs[as_of_ref_idx];
                    int32_t matched = 0;
                    
                    int32_t val = read_as_of_c(backend, store_idx, query_time, &matched);
                    if (!matched) {
                        *error_code = 20; // Temporal record not found
                        return -1;
                    }
                    
                    stack[sp++] = val;
                }
                ip++;
                break;

            case 0x0F: // OP_RET
                if (sp < 1) {
                    *error_code = 1; // Stack underflow
                    return -1;
                }
                *error_code = 0; // Success
                return stack[--sp];

            case 0x99: // OP_UNSUPPORTED
                *error_code = 3; // Unsupported selected-path node
                return -1;

            default:
                *error_code = 3; // Unknown instruction
                return -1;
        }
    }

    *error_code = 8; // Halt without RET
    return -1;
}

// Execute loaded module in-memory with C Temporal Backend (Blistering timeline speeds)
int32_t execute_module_temporal(const LoadedModule* module, const int32_t* inputs, const TemporalBackend* backend, int32_t* error_code) {
    if (!module || !module->instructions || module->count <= 0) {
        *error_code = 6; // Malformed input module
        return -1;
    }
    return execute_bytecode_temporal(module->instructions, module->count, inputs, backend, error_code);
}



