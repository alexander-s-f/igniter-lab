# frozen_string_literal: true

# verify_vm_stdlib_integration.rb
# Automated Integration & Correctness Verification Suite for VM + Rust Stdlib FFI

require_relative "../lib/ivm"

# ANSI styling
GREEN  = "\e[32m"
RED    = "\e[31m"
YELLOW = "\e[33m"
CYAN   = "\e[36m"
BOLD   = "\e[1m"
RESET  = "\e[0m"

$failed_assertions = 0

def assert_equal(expected, actual, msg = "Assertion failed")
  if expected == actual
    puts "  #{GREEN}✔ PASS:#{RESET} #{msg}"
  else
    puts "  #{RED}✘ FAIL:#{RESET} #{msg} - Expected: #{expected.inspect}, Got: #{actual.inspect}"
    $failed_assertions += 1
  end
end

def assert_error(error_klass, pattern, msg = "Error expectation failed")
  begin
    yield
    puts "  #{RED}✘ FAIL:#{RESET} #{msg} - Expected error #{error_klass} matching #{pattern.inspect} but no error was raised"
    $failed_assertions += 1
  rescue => e
    if e.is_a?(error_klass) && e.message.match?(pattern)
      puts "  #{GREEN}✔ PASS:#{RESET} #{msg} (Successfully raised #{e.class}: #{e.message})"
    else
      puts "  #{RED}✘ FAIL:#{RESET} #{msg} - Expected error #{error_klass} matching #{pattern.inspect}, got #{e.class}: #{e.message}"
      $failed_assertions += 1
    end
  end
end

puts "\n" + "=" * 80
puts " 🌟 IGNITER VM + RUST STDLIB INTEGRATION VERIFICATION SUITE 🌟"
puts "=" * 80

compiler = IVM::Compiler.new
vm = IVM::VM.new

# Define Contracts
add_contract = {
  "contract_id" => "DecimalAddTest",
  "inputs" => ["a", "b"],
  "expression" => {
    "kind" => "binary_op",
    "operator" => "+",
    "left" => { "kind" => "ref", "name" => "a" },
    "right" => { "kind" => "ref", "name" => "b" }
  }
}

sub_contract = {
  "contract_id" => "DecimalSubTest",
  "inputs" => ["a", "b"],
  "expression" => {
    "kind" => "binary_op",
    "operator" => "-",
    "left" => { "kind" => "ref", "name" => "a" },
    "right" => { "kind" => "ref", "name" => "b" }
  }
}

mul_contract = {
  "contract_id" => "DecimalMulTest",
  "inputs" => ["a", "b"],
  "expression" => {
    "kind" => "binary_op",
    "operator" => "*",
    "left" => { "kind" => "ref", "name" => "a" },
    "right" => { "kind" => "ref", "name" => "b" }
  }
}

div_contract = {
  "contract_id" => "DecimalDivTest",
  "inputs" => ["a", "b"],
  "expression" => {
    "kind" => "binary_op",
    "operator" => "/",
    "left" => { "kind" => "ref", "name" => "a" },
    "right" => { "kind" => "ref", "name" => "b" }
  }
}

# =============================================================================
# 1. Verification of Decimal Addition (OP_ADD)
# =============================================================================
puts "\n#{BOLD}#{CYAN}=== 1. Verifying Decimal Addition (OP_ADD) ===#{RESET}"
add_bytecode = compiler.compile(add_contract)

# A. Normal execution with symbol keys
inputs_a = {
  "a" => { value: 1050, scale: 2 },
  "b" => { value: 2525, scale: 2 }
}
res_a = vm.execute(add_bytecode, inputs_a)
assert_equal({ value: 3575, scale: 2 }, res_a, "10.50 + 25.25 = 35.75 (symbol keys)")

# B. Normal execution with string keys (key neutrality)
inputs_b = {
  "a" => { "value" => 1050, "scale" => 2 },
  "b" => { "value" => 2525, "scale" => 2 }
}
res_b = vm.execute(add_bytecode, inputs_b)
assert_equal({ value: 3575, scale: 2 }, res_b, "10.50 + 25.25 = 35.75 (string keys)")

# C. Scale mismatch error propagation (OOF-TC5 rule)
inputs_c = {
  "a" => { value: 1050, scale: 2 },
  "b" => { value: 250, scale: 1 }
}
assert_error(IVM::VM::ExecutionError, /OOF-TC5/, "Scale mismatch adds trigger static ScaleMismatchError") do
  vm.execute(add_bytecode, inputs_c)
end


# =============================================================================
# 2. Verification of Decimal Subtraction (OP_SUB)
# =============================================================================
puts "\n#{BOLD}#{CYAN}=== 2. Verifying Decimal Subtraction (OP_SUB) ===#{RESET}"
sub_bytecode = compiler.compile(sub_contract)

inputs_d = {
  "a" => { value: 3575, scale: 2 },
  "b" => { value: 1050, scale: 2 }
}
res_d = vm.execute(sub_bytecode, inputs_d)
assert_equal({ value: 2525, scale: 2 }, res_d, "35.75 - 10.50 = 25.25")

inputs_e = {
  "a" => { value: 3575, scale: 2 },
  "b" => { value: 250, scale: 1 }
}
assert_error(IVM::VM::ExecutionError, /OOF-TC5/, "Scale mismatch subs trigger static ScaleMismatchError") do
  vm.execute(sub_bytecode, inputs_e)
end


# =============================================================================
# 3. Verification of Decimal Multiplication (OP_MUL)
# =============================================================================
puts "\n#{BOLD}#{CYAN}=== 3. Verifying Decimal Multiplication (OP_MUL) ===#{RESET}"
mul_bytecode = compiler.compile(mul_contract)

inputs_f = {
  "a" => { value: 105, scale: 1 },
  "b" => { value: 25, scale: 1 }
}
res_f = vm.execute(mul_bytecode, inputs_f)
assert_equal({ value: 2625, scale: 2 }, res_f, "10.5 * 2.5 = 26.25 (scale = S1 + S2 = 2)")


# =============================================================================
# 4. Verification of Decimal Division (OP_DIV)
# =============================================================================
puts "\n#{BOLD}#{CYAN}=== 4. Verifying Decimal Division (OP_DIV) ===#{RESET}"
div_bytecode = compiler.compile(div_contract)

inputs_g = {
  "a" => { value: 2625, scale: 2 },
  "b" => { value: 25, scale: 1 }
}
res_g = vm.execute(div_bytecode, inputs_g)
assert_equal({ value: 105, scale: 1 }, res_g, "26.25 / 2.5 = 10.5 (scale = S1 - S2 = 1)")

# Division by zero rejection (OOF-DM2 rule)
inputs_h = {
  "a" => { value: 2625, scale: 2 },
  "b" => { value: 0, scale: 1 }
}
assert_error(IVM::VM::ExecutionError, /OOF-DM2/, "Division by zero triggers static DivisionError") do
  vm.execute(div_bytecode, inputs_h)
end


# =============================================================================
# 5. Verification of Fallback (Non-decimal operations)
# =============================================================================
puts "\n#{BOLD}#{CYAN}=== 5. Verifying Fallback for Standard Numbers ===#{RESET}"

# Regular integers
inputs_i = { "a" => 10, "b" => 20 }
res_i = vm.execute(add_bytecode, inputs_i)
assert_equal(30, res_i, "10 + 20 = 30 (integer fallback)")

# Regular floats
inputs_j = { "a" => 1.5, "b" => 2.5 }
res_j = vm.execute(add_bytecode, inputs_j)
assert_equal(4.0, res_j, "1.5 + 2.5 = 4.0 (float fallback)")


# =============================================================================
# Summary
# =============================================================================
puts "\n" + "=" * 80
if $failed_assertions == 0
  puts " #{GREEN}🏆 INTEGRATION VERIFICATION COMPLETE: ALL VM + STDLIB TESTS PASSED!#{RESET}"
  exit(0)
else
  puts " #{RED}✘ INTEGRATION VERIFICATION FAILED: #{$failed_assertions} TESTS FAILED!#{RESET}"
  exit(1)
end
puts "=" * 80
