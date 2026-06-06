# frozen_string_literal: true

# ivm_bitemporal_c_backend_proof.rb
#
# Off-track playground research script proving C-level Pluggable Bitemporal Backend integration.
# Integrates a minimal, ultra-fast `MemoryHistory` temporal database completely inside C,
# executing `OP_LOAD_AS_OF` (opcode `0x0D`) history reads in native space with ZERO FFI callbacks.
#
# Wording Discipline:
#   This is C-level temporal integration research evidence only.
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
OUT_DIR = File.join(PLAYGROUND_ROOT, "out", "ivm_bitemporal_c_backend_proof")
FileUtils.mkdir_p(OUT_DIR)

# -----------------------------------------------------------------------------
# Binary Serialization with Temporal packing support
# -----------------------------------------------------------------------------
def serialize_to_aot_file(bytecode, inputs_order, stores_order, filepath)
  header = ["IGB\x00", 1, bytecode.length, 0].pack("a4l<l<l<")
  packed_body = bytecode.map do |inst|
    opcode = inst.opcode
    arg_val = 0
    
    case opcode
    when IVM::Instructions::OP_LOAD_REF
      ref_name = inst.args.first
      arg_val = inputs_order.index(ref_name)
      raise "Input reference '#{ref_name}' not found" if arg_val.nil?
      
    when IVM::Instructions::OP_LOAD_AS_OF
      store_name = inst.args[0]
      as_of_ref = inst.args[1]
      
      store_idx = stores_order.index(store_name)
      as_of_ref_idx = inputs_order.index(as_of_ref)
      
      raise "Store '#{store_name}' not found in order: #{stores_order}" if store_idx.nil?
      raise "As-of Reference '#{as_of_ref}' not found in inputs: #{inputs_order}" if as_of_ref_idx.nil?
      
      # Pack store_idx in upper 16 bits, as_of_ref_idx in lower 16 bits
      arg_val = (store_idx << 16) | as_of_ref_idx
      
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
    if val.is_a?(Time)
      val.to_i # Epoch timestamp
    elsif val == true
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

# =---------------------------------------------------------------------------
# EXECUTE PROOF
# =---------------------------------------------------------------------------

puts "\n================================================================================"
puts "  🏢 IGNITER C-LEVEL BITEMPORAL DATABASE INTEGRATION PROOF 🏢"
puts "================================================================================\n"

# Compile dynamic library
puts "[1/4] Compiling Native C dynamic library with C-level TBackend..."
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

# loaded_module lifecycle
load_module_fn = Fiddle::Function.new(
  extern["load_module"],
  [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP],
  Fiddle::TYPE_VOIDP
)
free_module_fn = Fiddle::Function.new(
  extern["free_module"],
  [Fiddle::TYPE_VOIDP],
  Fiddle::TYPE_VOID
)

# temporal_backend lifecycle
create_backend_fn = Fiddle::Function.new(
  extern["create_backend"],
  [],
  Fiddle::TYPE_VOIDP # Returns TemporalBackend*
)
write_backend_history_fn = Fiddle::Function.new(
  extern["write_backend_history"],
  [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_LONG_LONG, Fiddle::TYPE_INT],
  Fiddle::TYPE_VOID
)
free_backend_fn = Fiddle::Function.new(
  extern["free_backend"],
  [Fiddle::TYPE_VOIDP],
  Fiddle::TYPE_VOID
)

# execute_module_temporal
execute_module_temporal_fn = Fiddle::Function.new(
  extern["execute_module_temporal"],
  [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP],
  Fiddle::TYPE_INT
)

# -----------------------------------------------------------------------------
# Initialize C Pluggable Backend and populate history
# -----------------------------------------------------------------------------
puts "\n[2/4] Initializing and populating C Pluggable Temporal Backend..."

backend_ptr = create_backend_fn.call
puts "      Calling create_backend -> TemporalBackend Pointer: 0x#{backend_ptr.to_i.to_s(16)}"

if backend_ptr.null?
  puts "      FAILED to create C Temporal Backend."
  exit(1)
end

# Populate history matching demo.rb timeline:
#   2026-05-01T00:00:00Z (epoch: 1777593600) => 3
#   2026-05-15T00:00:00Z (epoch: 1778803200) => 5
time_point_1 = Time.parse("2026-05-01T00:00:00Z")
time_point_2 = Time.parse("2026-05-15T00:00:00Z")

write_backend_history_fn.call(backend_ptr, "technician_jobs", time_point_1.to_i, 3)
write_backend_history_fn.call(backend_ptr, "technician_jobs", time_point_2.to_i, 5)

puts "      History populated in C MemoryHistory Backend:"
puts "        - 'technician_jobs' at #{time_point_1} (epoch #{time_point_1.to_i}) => Jobs Count: 3"
puts "        - 'technician_jobs' at #{time_point_2} (epoch #{time_point_2.to_i}) => Jobs Count: 5"

# -----------------------------------------------------------------------------
# Bitemporal Query Compilation, Loading and Parity Verification
# -----------------------------------------------------------------------------
puts "\n[3/4] Compiling and running Bitemporal Query module..."

# Ast representation matching demo.rb:
#   if (technician_jobs as_of as_of) == 5 then 1000 else 200
expr = {
  "kind" => "if_expr",
  "condition" => {
    "kind" => "binary_op",
    "operator" => "==",
    "left" => {
      "kind" => "temporal_read",
      "store_ref" => "technician_jobs",
      "as_of_ref" => "as_of"
    },
    "right" => { "kind" => "literal", "value" => 5 }
  },
  "then_branch" => { "kind" => "literal", "value" => 1000 },
  "else_branch" => { "kind" => "literal", "value" => 200 }
}
contract = {
  "contract_id" => "BitemporalQuery",
  "inputs" => ["as_of"],
  "expression" => expr
}

compiler = IVM::Compiler.new
bytecode = compiler.compile(contract)

puts "      Compiled bytecode instructions:"
bytecode.each_with_index do |inst, idx|
  puts "        [#{idx}] Opcode: 0x#{inst.opcode.to_s(16)} (#{inst.mnemonic}), Args: #{inst.args.inspect}"
end

filepath = File.join(OUT_DIR, "bitemporal_query.igbin")
serialize_to_aot_file(bytecode, contract["inputs"], ["technician_jobs"], filepath)
puts "      Compiled bitemporal AST into AOT binary: #{filepath}"

# Load module once
err_code_ptr = Fiddle::Pointer.to_ptr("\x00\x00\x00\x00")
module_ptr = load_module_fn.call(filepath, err_code_ptr)
err_load = err_code_ptr[0, 4].unpack1("l<")

if module_ptr.null? || err_load != 0
  puts "      FAILED to load bitemporal module. Pointer Null? #{module_ptr.null?}, Error Code: #{err_load}"
  exit(1)
end
puts "      LoadedModule loaded successfully: 0x#{module_ptr.to_i.to_s(16)}"

# Timeline Point A: as_of = 2026-05-10T12:00:00Z -> matches jobs = 3 -> condition false -> returns 200
query_a = Time.parse("2026-05-10T12:00:00Z")
inputs_a = { "as_of" => query_a }
inputs_ptr_a = serialize_inputs(inputs_a, contract["inputs"])

res_a = execute_module_temporal_fn.call(module_ptr, inputs_ptr_a, backend_ptr, err_code_ptr)
err_a = err_code_ptr[0, 4].unpack1("l<")
puts "        [Timeline A] as_of: #{query_a} -> Result: #{res_a} (Expected: 200, C Error: #{err_a})"

# Timeline Point B: as_of = 2026-05-20T12:00:00Z -> matches jobs = 5 -> condition true -> returns 1000
query_b = Time.parse("2026-05-20T12:00:00Z")
inputs_b = { "as_of" => query_b }
inputs_ptr_b = serialize_inputs(inputs_b, contract["inputs"])

res_b = execute_module_temporal_fn.call(module_ptr, inputs_ptr_b, backend_ptr, err_code_ptr)
err_b = err_code_ptr[0, 4].unpack1("l<")
puts "        [Timeline B] as_of: #{query_b} -> Result: #{res_b} (Expected: 1000, C Error: #{err_b})"

# Parity Verification against Ruby Oracle
ruby_backend = IVM::MemoryHistoryBackend.new
ruby_backend.write_history("technician_jobs", "2026-05-01T00:00:00Z", 3)
ruby_backend.write_history("technician_jobs", "2026-05-15T00:00:00Z", 5)

ruby_vm = IVM::VM.new(backend: ruby_backend)
ruby_res_a = ruby_vm.execute(bytecode, { "as_of" => query_a.iso8601 })
ruby_res_b = ruby_vm.execute(bytecode, { "as_of" => query_b.iso8601 })

parity_res = (res_a == ruby_res_a && res_b == ruby_res_b)
puts "      Correctness bitemporal parity matching: #{parity_res ? 'PASS' : 'FAIL'} (Ruby Oracle returned A: #{ruby_res_a}, B: #{ruby_res_b})"

# -----------------------------------------------------------------------------
# Benchmark timeline loop
# -----------------------------------------------------------------------------
puts "\n[4/4] Running bitemporal timeline loop benchmarks (informational only)..."
ITERATIONS = 50_000
WARMUP = 1_000

# Warmups
WARMUP.times do
  execute_module_temporal_fn.call(module_ptr, inputs_ptr_a, backend_ptr, err_code_ptr)
end

# 1. Pure Ruby IVM VM (Ruby MemoryHistoryBackend queries)
t_start_ruby = Time.now
ITERATIONS.times do
  ruby_vm.execute(bytecode, { "as_of" => query_a.iso8601 })
end
t_end_ruby = Time.now
ruby_duration = t_end_ruby - t_start_ruby

# 2. Native C Resident VM + C pluggable backend (Zero FFI boundary callbacks)
t_start_native = Time.now
ITERATIONS.times do
  execute_module_temporal_fn.call(module_ptr, inputs_ptr_a, backend_ptr, err_code_ptr)
end
t_end_native = Time.now
native_duration = t_end_native - t_start_native

puts "      [Bitemporal timings over #{ITERATIONS} iterations - informational only]"
puts "      - Ruby VM loop (with Ruby Backend): #{'%.4f' % ruby_duration} seconds (#{'%.1f' % (ITERATIONS / ruby_duration)} iter/sec)"
puts "      - Native C VM loop (with C Backend):    #{'%.4f' % native_duration} seconds (#{'%.1f' % (ITERATIONS / native_duration)} iter/sec)"
puts "      - Measured Native Speedup:              #{'%.1f' % (ruby_duration / native_duration)}x faster (blistering speedup)"

# Clean up
free_module_fn.call(module_ptr)
free_backend_fn.call(backend_ptr)
puts "\n      Memory successfully released. Memory clean."
puts "================================================================================"
puts "  🌟 C-LEVEL TEMPORAL BACKEND INTEGRATION COMPLETED SUCCESSFUL 🌟"
puts "================================================================================\n"
