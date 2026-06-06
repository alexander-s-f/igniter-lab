# Walkthrough: Igniter Virtual Machine (IVM) POC Prototype

This note preserves an early stack-based, register-gated **Igniter Virtual Machine (IVM)** research prototype now stored under `igniter-research/ivm-ruby-runtime/`.

This implementation is historical research evidence for AOT bytecode compilation and execution ideas; it is not the active Igniter runtime.

---

## 1. Accomplished File Layout

The research code was organized as:

```text
├── lib/
│   ├── ivm.rb                  # Loader and namespace entry
│   └── ivm/
│       ├── instructions.rb     # Opcode specifications and mnemonics
│       ├── vm.rb               # Execution core (stack, registers, instructions loop)
│       ├── compiler.rb         # Ahead-of-Time (AOT) compiler (SemanticIR -> Bytecode)
│       └── tbackend.rb         # Pluggable bitemporal MemoryHistory database backend
└── examples/
    └── demo.rb                 # Executable disassembly and simulation script
```

---

## 2. Bytecode Instruction Set Specifications

The VM is stack-based, decoding instructions represented by 8-bit opcodes.

```ruby
# Opcodes mapped to 8-bit integers
OP_PUSH_LIT    = 0x01  # Push a literal value to the stack
OP_LOAD_REF    = 0x02  # Load input/coordinate name to the stack
OP_STORE_REG   = 0x03  # Store top of stack to register index
OP_LOAD_REG    = 0x04  # Load from register index to the stack
OP_ADD         = 0x05  # Pop two, add, push
OP_SUB         = 0x06  # Pop two, subtract, push
OP_MUL         = 0x07  # Pop two, multiply, push
OP_DIV         = 0x08  # Pop two, divide, push
OP_EQ          = 0x09  # Pop two, compare, push Bool
OP_JMP         = 0x0A  # Unconditional jump to offset
OP_JMP_IF      = 0x0B  # Pop Bool, jump if true
OP_JMP_UNLESS  = 0x0C  # Pop Bool, jump if false (implements lazy branch condition)
OP_LOAD_AS_OF  = 0x0D  # Pop as_of, query backend, push unwrapped raw historical value
OP_EMIT_OBS    = 0x0E  # Pop value, push to observation sink, push back onto stack
OP_RET         = 0x0F  # Pop value and return, halting VM execution
```

---

## 3. Ahead-of-Time (AOT) Conditional Compile Flow

A critical architectural accomplishment is compiling recursive `if_expr` (conditional) AST nodes into **flat JMP offsets**, guaranteeing **lazy evaluation** at the bytecode level:

```ruby
compile_expr(node.fetch("condition"))

# Emit placeholder JMP_UNLESS jump target
jmp_unless_idx = emit(Instructions::OP_JMP_UNLESS, :placeholder_else)

compile_expr(node.fetch("then_branch"))

# Emit placeholder JMP to skip else branch
jmp_end_idx = emit(Instructions::OP_JMP, :placeholder_end)

else_branch_start_idx = @instructions.length
compile_expr(node.fetch("else_branch"))

end_idx = @instructions.length

# Resolve placeholder targets
resolve_placeholder(jmp_unless_idx, else_branch_start_idx)
resolve_placeholder(jmp_end_idx, end_idx)
```

During execution, only the selected branch instructions are decoded and run. Non-selected branches are completely skipped, meaning their inner code (such as custom observation emissions) never fires.

---

## 4. Execution & Disassembly Results

We executed the `examples/demo.rb` script and verified the exact outputs:

```text
================================================================================
 IGNITER VIRTUAL MACHINE (IVM) PROTOTYPE DEMO
================================================================================

[1/4] Compiling SemanticIR AST to IVM Bytecode...
      Compilation successful! Generated 10 VM instructions.

[2/4] Disassembling compiled IVM Bytecode...
--------------------------------------------------------------------------------
 OFFSET | OPCODE (HEX) | MNEMONIC         | ARGUMENTS                            
--------------------------------------------------------------------------------
  0000  |     0x0D     | LOAD_AS_OF       | "technician_jobs", "as_of"           
  0001  |     0x01     | PUSH_LIT         | 5                                    
  0002  |     0x09     | EQ               | -                                    
  0003  |     0x0C     | JMP_UNLESS       | 7                                    
  0004  |     0x01     | PUSH_LIT         | 1000                                 
  0005  |     0x0E     | EMIT_OBS         | "bonus_major_selected"               
  0006  |     0x0A     | JMP              | 9                                    
  0007  |     0x01     | PUSH_LIT         | 200                                  
  0008  |     0x0E     | EMIT_OBS         | "bonus_minor_selected"               
  0009  |     0x0F     | RET              | -                                    
--------------------------------------------------------------------------------

[3/4] Initializing Temporal Backend (MemoryHistoryBackend)...
      Historical database states populated:
      - 2026-05-01T00:00:00Z => Jobs Count: 3
      - 2026-05-15T00:00:00Z => Jobs Count: 5

[4/4] Executing VM against historical timeline...

  >>> [Query Timeline A] as_of: 2026-05-10T12:00:00Z
      Resulting Bonus Value: 200 (Expected: 200)

  >>> [Query Timeline B] as_of: 2026-05-20T12:00:00Z
      Resulting Bonus Value: 1000 (Expected: 1000)

================================================================================
 🔐 CRITICAL EVIDENCE & AUDIT OBSERVATION ENVELOPES
================================================================================

Total observations captured in this session: 4
Notice that ONLY the active/selected branches emitted their observations!
Non-selected branches were never evaluated (Lazy Evaluation Verified).

[Observation #1] ID: obs/live-read/6ead671c917c6892
--------------------------------------------------------------------------------
  Type: Bitemporal Live Read Observation (AT-10 Compliance)
  Store queried:   technician_jobs
  Temporal Axis:   valid_time
  As Of Time:      2026-05-10T12:00:00Z
  Result Present:  true
  Resolved Value:  {"kind"=>"some", "value"=>3}
  Backend trace:   obs/prov/859d14a50b8d54d7
--------------------------------------------------------------------------------

[Observation #2] ID: obs/eval/28325109e255bf47
--------------------------------------------------------------------------------
  Type: Custom Computation Observation
  Semantic Kind:   bonus_minor_selected
  Evaluated Value: 200
--------------------------------------------------------------------------------

[Observation #3] ID: obs/live-read/7730f6e0755d478f
--------------------------------------------------------------------------------
  Type: Bitemporal Live Read Observation (AT-10 Compliance)
  Store queried:   technician_jobs
  Temporal Axis:   valid_time
  As Of Time:      2026-05-20T12:00:00Z
  Result Present:  true
  Resolved Value:  {"kind"=>"some", "value"=>5}
  Backend trace:   obs/prov/627481b82742e689
--------------------------------------------------------------------------------

[Observation #4] ID: obs/eval/8bd089e6a9fe1c19
--------------------------------------------------------------------------------
  Type: Custom Computation Observation
  Semantic Kind:   bonus_major_selected
  Evaluated Value: 1000
--------------------------------------------------------------------------------

================================================================================
 IVM DEMONSTRATION COMPLETE
================================================================================
```

---

## 5. Key Verification Highlights

1. **AOT bytecode compilation was demonstrated for selected fixtures**: Nested expression graphs successfully lower to a linear stream of compact VM opcodes.
2. **Lazy Branch Evaluation (Highly Sound)**:
    - On Timeline A (jobs = 3), only `bonus_minor_selected` is emitted. `bonus_major_selected` remains unexecuted.
    - On Timeline B (jobs = 5), only `bonus_major_selected` is emitted. `bonus_minor_selected` remains unexecuted.
    - This proves that bytecode execution behaves lazily as mathematically required, avoiding any eager path evaluation side-effects.
3. **Pluggable Bitemporal DB Integration**: `LOAD_AS_OF` successfully resolves valid-time history queries, unwraps the option result wrapper, and returns `some` counts dynamically.
4. **Automatic Trace Observability**: Every execution read and calculation emits tamper-evident observation envelopes signed with unique IDs and backend provenance keys.
