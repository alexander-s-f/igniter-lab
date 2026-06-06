# frozen_string_literal: true

# ivm_resident_supervisor_proof.rb
#
# Off-track playground research script proving a Resident Native Execution Supervisor.
# Splits bitemporal bytecode execution into two clean architectural stages:
#   1. Module Loading Stage: Loads `.igbin` file once into an in-memory LoadedModule struct.
#   2. Timeline Evaluation Stage: Executes the loaded module repeatedly from memory with zero filesystem access.
#
# Wording Discipline:
#   This is resident native supervisor research evidence only.
#   It is NOT Reference Runtime, public runtime support, stable API, or production support.

require "digest"
require "fileutils"
require "fiddle"
require "json"
require "shellwords"
require "time"

# Require mainline compiler facade
REPO_ROOT = File.expand_path("../../../igniter-lang", __dir__)
$LOAD_PATH.unshift(File.join(REPO_ROOT, "lib"))
require "igniter_lang"

# Require playground IVM
$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "ivm"

# Directories
PLAYGROUND_ROOT = File.expand_path("..", __dir__)
OUT_DIR = File.join(PLAYGROUND_ROOT, "out", "ivm_resident_supervisor_proof")
FileUtils.mkdir_p(OUT_DIR)

FRESH_IF_ELSE_IGAPP = File.join(PLAYGROUND_ROOT, "out", "ivm_adapter_branch_coverage_proof", "fresh_if_else.igapp")
SEMANTIC_IR_PROG_IF_PATH = File.join(FRESH_IF_ELSE_IGAPP, "semantic_ir_program.json")

# -----------------------------------------------------------------------------
# Binary Serialization Helpers
# -----------------------------------------------------------------------------
def serialize_to_aot_file(bytecode, inputs_order, filepath)
  header = ["IGB\x00", 1, bytecode.length, 0].pack("a4l<l<l<")
  packed_body = bytecode.map do |inst|
    opcode = inst.opcode
    arg_val = 0
    
    if opcode == IVM::Instructions::OP_LOAD_REF
      ref_name = inst.args.first
      arg_val = inputs_order.index(ref_name)
    else
      val = inst.args.first
      if val.is_a?(Integer)
        arg_val = val
      elsif val == true
        arg_val = 1
      elsif val == false
        arg_val = 0
      end
    end
    [opcode, arg_val].pack("l<l<")
  end.join
  File.binwrite(filepath, header + packed_body)
end

def serialize_inputs(inputs_hash, inputs_order)
  vals = inputs_order.map do |name|
    val = inputs_hash[name]
    if val == true
      1
    elsif val == false
      0
    elsif val.is_a?(Integer)
      val
    else
      0
    end
  end
  Fiddle::Pointer.to_ptr(vals.pack("l<*"))
end

# -----------------------------------------------------------------------------
# AST Translation
# -----------------------------------------------------------------------------
class HardenedCompilerToIvmAdapter
  def self.adapt_semantic_ir_program(json_path)
    data = JSON.parse(File.read(json_path))
    contract_data = data["contracts"].first
    inputs = contract_data["inputs"].map { |i| i["name"] }
    output_name = contract_data["outputs"].first["name"]
    output_node = contract_data["nodes"].find { |n| n["name"] == output_name }
    
    {
      "contract_id" => contract_data["contract_name"],
      "inputs" => inputs,
      "expression" => map_expr(output_node["expr"])
    }
  end

  def self.map_expr(expr)
    kind = expr["kind"]
    case kind
    when "literal"
      { "kind" => "literal", "value" => expr["value"] }
    when "ref"
      { "kind" => "ref", "name" => expr["name"] }
    when "binary_op"
      { "kind" => "binary_op", "operator" => expr["operator"], "left" => map_expr(expr["left"]), "right" => map_expr(expr["right"]) }
    when "if_expr"
      { "kind" => "if_expr", "condition" => map_expr(expr["condition"]), "then_branch" => map_expr(expr["then_branch"]), "else_branch" => map_expr(expr["else_branch"]) }
    else
      { "kind" => "unsupported", "original_kind" => kind }
    end
  end
end

# =---------------------------------------------------------------------------
# EXECUTE PROOF
# =---------------------------------------------------------------------------

puts "\n================================================================================"
puts "  🏢 IGNITER RESIDENT RESIDENT NATIVE SUPERVISOR RESEARCH PROOF 🏢"
puts "================================================================================\n"

# Compile dynamic library
puts "[1/4] Compiling Native C dynamic library with resident supervisor..."
lib_name = RUBY_PLATFORM.include?("darwin") ? "librunner.dylib" : "librunner.so"
c_source = File.join(PLAYGROUND_ROOT, "lib", "ivm", "runner.c")
compiled_lib = File.join(OUT_DIR, lib_name)

cc_compiler = "cc"
compile_cmd = "#{cc_compiler} -shared -fPIC -o #{Shellwords.escape(compiled_lib)} #{Shellwords.escape(c_source)}"
system(compile_cmd)

unless File.exist?(compiled_lib)
  puts "      Compilation FAILED."
  exit(1)
end
puts "      Library successfully compiled: #{compiled_lib}"

# Bind via Fiddle FFI
extern = Fiddle.dlopen(compiled_lib)

# execute_bytecode_file (for file benchmark)
execute_file_fn = Fiddle::Function.new(
  extern["execute_bytecode_file"],
  [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP],
  Fiddle::TYPE_INT
)

# load_module (Module Loading Stage)
load_module_fn = Fiddle::Function.new(
  extern["load_module"],
  [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP],
  Fiddle::TYPE_VOIDP # Returns pointer to LoadedModule
)

# execute_module (Timeline Evaluation Stage)
execute_module_fn = Fiddle::Function.new(
  extern["execute_module"],
  [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP],
  Fiddle::TYPE_INT
)

# free_module
free_module_fn = Fiddle::Function.new(
  extern["free_module"],
  [Fiddle::TYPE_VOIDP],
  Fiddle::TYPE_VOID # Returns void
)

# -----------------------------------------------------------------------------
# Module Loading and Execution Verification
# -----------------------------------------------------------------------------
puts "\n[2/4] Testing Resident Native Supervisor pipeline..."

mapped_if_ast = HardenedCompilerToIvmAdapter.adapt_semantic_ir_program(SEMANTIC_IR_PROG_IF_PATH)
compiler = IVM::Compiler.new
bytecode = compiler.compile(mapped_if_ast)

filepath = File.join(OUT_DIR, "if_module.igbin")
serialize_to_aot_file(bytecode, mapped_if_ast["inputs"], filepath)
puts "      Serialized bytecode into AOT file: #{filepath}"

# 1. Load module once (Module Loading Stage)
err_code_ptr = Fiddle::Pointer.to_ptr("\x00\x00\x00\x00")
module_ptr = load_module_fn.call(filepath, err_code_ptr)
err_load = err_code_ptr[0, 4].unpack1("l<")

puts "      Calling load_module -> LoadedModule Pointer: 0x#{module_ptr.to_i.to_s(16)} (C Error Code: #{err_load})"

if module_ptr.null? || err_load != 0
  puts "      FAILED to load module."
  exit(1)
end

# 2. Execute module repeatedly with different inputs (Timeline Evaluation Stage)
puts "      Evaluating loaded module against multiple input timelines..."

# Case A: flag = true -> executes then_branch (expected 42)
inputs_a = { "flag" => true, "a" => 42, "b" => 99 }
inputs_ptr_a = serialize_inputs(inputs_a, mapped_if_ast["inputs"])
res_a = execute_module_fn.call(module_ptr, inputs_ptr_a, err_code_ptr)
err_a = err_code_ptr[0, 4].unpack1("l<")
puts "        [Timeline Point A] inputs: flag=true, a=42 -> Result: #{res_a} (Expected: 42, C Error: #{err_a})"

# Case B: flag = false -> executes else_branch (expected 99)
inputs_b = { "flag" => false, "a" => 42, "b" => 99 }
inputs_ptr_b = serialize_inputs(inputs_b, mapped_if_ast["inputs"])
res_b = execute_module_fn.call(module_ptr, inputs_ptr_b, err_code_ptr)
err_b = err_code_ptr[0, 4].unpack1("l<")
puts "        [Timeline Point B] inputs: flag=false, b=99 -> Result: #{res_b} (Expected: 99, C Error: #{err_b})"

# Assert correctness parity
correct_parity = (res_a == 42 && err_a == 0 && res_b == 99 && err_b == 0)
puts "      Correctness parity verified: #{correct_parity ? 'PASS' : 'FAIL'}"

# -----------------------------------------------------------------------------
# Benchmark Comparison
# -----------------------------------------------------------------------------
puts "\n[3/4] Running Benchmark Comparison (informational only)..."
ITERATIONS = 50_000
WARMUP = 1_000

# Warmups
WARMUP.times do
  execute_module_fn.call(module_ptr, inputs_ptr_a, err_code_ptr)
end

# 1. Pure Ruby IVM VM loop
t_start_ruby = Time.now
ruby_vm = IVM::VM.new
ITERATIONS.times do
  ruby_vm.execute(bytecode, inputs_a)
end
t_end_ruby = Time.now
ruby_duration = t_end_ruby - t_start_ruby

# 2. Native C AOT File VM (Reads file every iteration)
t_start_file = Time.now
ITERATIONS.times do
  execute_file_fn.call(filepath, inputs_ptr_a, err_code_ptr)
end
t_end_file = Time.now
file_duration = t_end_file - t_start_file

# 3. Native C Resident Supervisor VM (Executes in-memory repeatedly)
t_start_supervisor = Time.now
ITERATIONS.times do
  execute_module_fn.call(module_ptr, inputs_ptr_a, err_code_ptr)
end
t_end_supervisor = Time.now
supervisor_duration = t_end_supervisor - t_start_supervisor

puts "      [Timings over #{ITERATIONS} iterations - informational only]"
puts "      - Ruby IVM VM loop:                 #{'%.4f' % ruby_duration} seconds (#{'%.1f' % (ITERATIONS / ruby_duration)} iter/sec)"
puts "      - Native C AOT File VM loop:        #{'%.4f' % file_duration} seconds (#{'%.1f' % (ITERATIONS / file_duration)} iter/sec)"
puts "      - Native C Resident Supervisor VM:  #{'%.4f' % supervisor_duration} seconds (#{'%.1f' % (ITERATIONS / supervisor_duration)} iter/sec)"
puts "      - Supervisor speedup over Ruby VM:  #{'%.1f' % (ruby_duration / supervisor_duration)}x faster (rough comparison)"
puts "      - Supervisor speedup over File VM:  #{'%.1f' % (file_duration / supervisor_duration)}x faster (rough comparison)"

# -----------------------------------------------------------------------------
# Clean up
# -----------------------------------------------------------------------------
puts "\n[4/4] Freeing loaded module memory resources..."
free_module_fn.call(module_ptr)
puts "      free_module successfully called. Memory clean."
puts "================================================================================"
puts "  🌟 RESIDENT NATIVE SUPERVISOR PROOF & BENCHMARKS COMPLETED SUCCESSFUL 🌟"
puts "================================================================================\n"
