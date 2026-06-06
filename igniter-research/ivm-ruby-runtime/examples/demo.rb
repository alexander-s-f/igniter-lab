# frozen_string_literal: true

require "time"
require_relative "../lib/ivm"

# =============================================================================
# 1. Structured Contract (representing Compiled SemanticIR)
# =============================================================================
#
# Logic:
#   Query the historical 'technician_jobs' store as of the given 'as_of' date.
#   Extract count. If count == 5, emit 'bonus_major' and return 1000.
#   Otherwise, emit 'bonus_minor' and return 200.
#
# AST Representation:
#
#   if_expr (
#     condition: (temporal_read("technician_jobs", "as_of") == 5),
#     then_branch: emit_observation("bonus_major_selected", literal(1000)),
#     else_branch: emit_observation("bonus_minor_selected", literal(200))
#   )
# =============================================================================
contract = {
  "contract_id" => "TechnicianBonusCalculator",
  "inputs" => ["technician_id", "as_of"],
  "expression" => {
    "kind" => "if_expr",
    "condition" => {
      "kind" => "binary_op",
      "operator" => "==",
      "left" => {
        "kind" => "temporal_read",
        "store_ref" => "technician_jobs",
        "as_of_ref" => "as_of"
      },
      "right" => {
        "kind" => "literal",
        "value" => 5
      }
    },
    "then_branch" => {
      "kind" => "emit_observation",
      "observation_kind" => "bonus_major_selected",
      "expression" => {
        "kind" => "literal",
        "value" => 1000
      }
    },
    "else_branch" => {
      "kind" => "emit_observation",
      "observation_kind" => "bonus_minor_selected",
      "expression" => {
        "kind" => "literal",
        "value" => 200
      }
    }
  }
}

puts "\n" + "=" * 80
puts " 🌟 IGNITER VIRTUAL MACHINE (IVM) PROTOTYPE DEMO 🌟"
puts "=" * 80

# =============================================================================
# 2. Ahead-of-Time Bytecode Compilation
# =============================================================================
puts "\n[1/4] Compiling SemanticIR AST to IVM Bytecode..."
compiler = IVM::Compiler.new
bytecode = compiler.compile(contract)
puts "      Compilation successful! Generated #{bytecode.length} VM instructions."

# =============================================================================
# 3. Disassembler Output
# =============================================================================
puts "\n[2/4] Disassembling compiled IVM Bytecode..."
puts "-" * 80
printf(" %-6s | %-12s | %-16s | %-36s \n", "OFFSET", "OPCODE (HEX)", "MNEMONIC", "ARGUMENTS")
puts "-" * 80
bytecode.each_with_index do |inst, idx|
  hex_op = "0x#{inst.opcode.to_s(16).upcase.rjust(2, '0')}"
  args_str = inst.args.empty? ? "-" : inst.args.map(&:inspect).join(", ")
  printf("  %04d  |     %-8s | %-16s | %-36s \n", idx, hex_op, inst.mnemonic, args_str)
end
puts "-" * 80

# =============================================================================
# 4. Pluggable Temporal Database Setup
# =============================================================================
puts "\n[3/4] Initializing Temporal Backend (MemoryHistoryBackend)..."
backend = IVM::MemoryHistoryBackend.new

# Populate bitemporal history for technician jobs count:
# tech-01 has 3 jobs as of May 1st, which grows to 5 jobs by May 15th
backend.write_history("technician_jobs", "2026-05-01T00:00:00Z", 3)
backend.write_history("technician_jobs", "2026-05-15T00:00:00Z", 5)

puts "      Historical database states populated:"
puts "      - 2026-05-01T00:00:00Z => Jobs Count: 3"
puts "      - 2026-05-15T00:00:00Z => Jobs Count: 5"

# =============================================================================
# 5. Virtual Machine Execution Loop (Demonstrating lazy branching & temporal reads)
# =============================================================================
puts "\n[4/4] Executing VM against historical timeline..."
vm = IVM::VM.new(backend: backend)

# Run Test Case A: Query as of May 10th (Should match May 1st record => 3 jobs -> minor bonus)
as_of_a = "2026-05-10T12:00:00Z"
inputs_a = { "technician_id" => "tech-01" }
temporal_context_a = { "as_of" => as_of_a }

puts "\n  >>> [Query Timeline A] as_of: #{as_of_a}"
result_a = vm.execute(bytecode, inputs_a, temporal_context_a)
puts "      Resulting Bonus Value: #{result_a} (Expected: 200)"

# Run Test Case B: Query as of May 20th (Should match May 15th record => 5 jobs -> major bonus)
as_of_b = "2026-05-20T12:00:00Z"
inputs_b = { "technician_id" => "tech-01" }
temporal_context_b = { "as_of" => as_of_b }

puts "\n  >>> [Query Timeline B] as_of: #{as_of_b}"
result_b = vm.execute(bytecode, inputs_b, temporal_context_b)
puts "      Resulting Bonus Value: #{result_b} (Expected: 1000)"

# =============================================================================
# 6. Audit & Traceability Envelopes
# =============================================================================
puts "\n" + "=" * 80
puts " 🔐 CRITICAL EVIDENCE & AUDIT OBSERVATION ENVELOPES"
puts "=" * 80

puts "\nTotal observations captured in this session: #{vm.observation_sink.length}"
puts "Notice that ONLY the active/selected branches emitted their observations!"
puts "Non-selected branches were never evaluated (Lazy Evaluation Verified)."

vm.observation_sink.each_with_index do |obs, idx|
  puts "\n[Observation ##{idx + 1}] ID: #{obs['observation_id']}"
  puts "-" * 80
  case obs["kind"]
  when "temporal_live_read_observation"
    puts "  Type: Bitemporal Live Read Observation (AT-10 Compliance)"
    puts "  Store queried:   #{obs['store']}"
    puts "  Temporal Axis:   #{obs['axis']}"
    puts "  As Of Time:      #{obs['as_of']}"
    puts "  Result Present:  #{obs['result_present']}"
    puts "  Resolved Value:  #{obs['result_value']}"
    puts "  Backend trace:   #{obs['backend_observation']['observation_id']}"
  when "bonus_minor_selected", "bonus_major_selected"
    puts "  Type: Custom Computation Observation"
    puts "  Semantic Kind:   #{obs['kind']}"
    puts "  Evaluated Value: #{obs['value']}"
  end
  puts "-" * 80
end

puts "\n" + "=" * 80
puts " 🌟 IVM DEMONSTRATION COMPLETE 🌟"
puts "=" * 80
