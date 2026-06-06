# frozen_string_literal: true

# verify_stdlib.rb
#
# Stdlib lab verifier — Decimal FFI correctness + signature file presence.
#
# Exact verifier scope (S3-R238-C2-I / STD-P5):
#   - Decimal FFI correctness:  14 assertions (add/sub/mul/div + OOF-TC5/OOF-DM2)
#   - Signature file presence:   3 assertions (math.ig, collections.ig, temporal.ig)
#   - Collections correctness:   NOT tested by this script
#   - Temporal correctness:      NOT tested by this script
#
# Authority notice:
#   This verifier produces proof-local stdlib candidate evidence only.
#   It is not public stdlib API, not runtime support, not stable API,
#   not production ready, not Reference Runtime, not release evidence,
#   and not a portability guarantee.
#
# The exit string below is lab-assertion style. It does not imply general
# stdlib correctness beyond the exact scope stated above.

require "fiddle"
require "json"
require "fileutils"

# ANSI styling
GREEN  = "\e[32m"
RED    = "\e[31m"
YELLOW = "\e[33m"
CYAN   = "\e[36m"
BOLD   = "\e[1m"
RESET  = "\e[0m"

$failed_assertions = 0

def assert(cond, msg = "Assertion failed")
  if cond
    puts "  #{GREEN}✔ PASS:#{RESET} #{msg}"
  else
    puts "  #{RED}✘ FAIL:#{RESET} #{msg}"
    $failed_assertions += 1
  end
end

def assert_equal(expected, actual, msg = "Assertion failed")
  if expected == actual
    puts "  #{GREEN}✔ PASS:#{RESET} #{msg}"
  else
    puts "  #{RED}✘ FAIL:#{RESET} #{msg} - Expected: #{expected.inspect}, Got: #{actual.inspect}"
    $failed_assertions += 1
  end
end

# Rebuild target
puts "\n#{BOLD}#{CYAN}=== 1. Building igniter-stdlib CDYLIB Target ===#{RESET}"
system("cargo build --release")

lib_name = RUBY_PLATFORM.include?("darwin") ? "libigniter_stdlib.dylib" : "libigniter_stdlib.so"
lib_path = File.expand_path("target/release/#{lib_name}", __dir__)

unless File.exist?(lib_path)
  puts "#{RED}CDYLIB target not found: #{lib_path}#{RESET}"
  exit 1
end
puts "  #{GREEN}✔#{RESET} Dynamic library successfully loaded: #{lib_path}"

# Bind via Fiddle
puts "\n#{BOLD}#{CYAN}=== 2. Loading Dynamic Library via Fiddle FFI ===#{RESET}"
extern = Fiddle.dlopen(lib_path)

# stdlib_decimal_add(a_val, a_scale, b_val, b_scale, out_val, out_scale) -> i32
stdlib_decimal_add = Fiddle::Function.new(
  extern["stdlib_decimal_add"],
  [Fiddle::TYPE_LONG_LONG, Fiddle::TYPE_INT, Fiddle::TYPE_LONG_LONG, Fiddle::TYPE_INT, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP],
  Fiddle::TYPE_INT
)

# stdlib_decimal_sub
stdlib_decimal_sub = Fiddle::Function.new(
  extern["stdlib_decimal_sub"],
  [Fiddle::TYPE_LONG_LONG, Fiddle::TYPE_INT, Fiddle::TYPE_LONG_LONG, Fiddle::TYPE_INT, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP],
  Fiddle::TYPE_INT
)

# stdlib_decimal_mul
stdlib_decimal_mul = Fiddle::Function.new(
  extern["stdlib_decimal_mul"],
  [Fiddle::TYPE_LONG_LONG, Fiddle::TYPE_INT, Fiddle::TYPE_LONG_LONG, Fiddle::TYPE_INT, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP],
  Fiddle::TYPE_VOID
)

# stdlib_decimal_div
stdlib_decimal_div = Fiddle::Function.new(
  extern["stdlib_decimal_div"],
  [Fiddle::TYPE_LONG_LONG, Fiddle::TYPE_INT, Fiddle::TYPE_LONG_LONG, Fiddle::TYPE_INT, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP],
  Fiddle::TYPE_INT
)

puts "\n#{BOLD}#{CYAN}=== 3. Verifying Fixed-Point Decimal Math via FFI ===#{RESET}"

# Allocation pointers
out_val = Fiddle::Pointer.to_ptr("\x00" * 8)
out_scale = Fiddle::Pointer.to_ptr("\x00" * 4)

# A. Addition (matching scale)
err1 = stdlib_decimal_add.call(1050, 2, 2525, 2, out_val, out_scale) # 10.50 + 25.25 = 35.75
res_val = out_val[0, 8].unpack1("q")
res_scale = out_scale[0, 4].unpack1("l")
assert_equal(0, err1, "Addition with identical scale succeeds")
assert_equal(3575, res_val, "Value is correctly computed: 3575")
assert_equal(2, res_scale, "Scale is correctly propagated: 2")

# B. Addition (mismatched scale -> OOF-TC5 scale mismatch)
err2 = stdlib_decimal_add.call(1050, 2, 250, 1, out_val, out_scale)
assert_equal(1, err2, "Addition with scale mismatch fails with scale mismatch code (OOF-TC5)")

# C. Subtraction
err3 = stdlib_decimal_sub.call(3575, 2, 1050, 2, out_val, out_scale) # 35.75 - 10.50 = 25.25
res_val = out_val[0, 8].unpack1("q")
res_scale = out_scale[0, 4].unpack1("l")
assert_equal(0, err3, "Subtraction with identical scale succeeds")
assert_equal(2525, res_val, "Value is correctly computed: 2525")
assert_equal(2, res_scale, "Scale is correctly propagated: 2")

# D. Subtraction (mismatched scale -> OOF-TC5)
err4 = stdlib_decimal_sub.call(3575, 2, 250, 1, out_val, out_scale)
assert_equal(1, err4, "Subtraction with scale mismatch fails with scale mismatch code (OOF-TC5)")

# E. Multiplication: S1 * S2 -> scale = S1 + S2
stdlib_decimal_mul.call(105, 1, 25, 1, out_val, out_scale) # 10.5 * 2.5 = 26.25 (scale = 2)
res_val = out_val[0, 8].unpack1("q")
res_scale = out_scale[0, 4].unpack1("l")
assert_equal(2625, res_val, "Multiplication scale summation computes 2625")
assert_equal(2, res_scale, "Multiplication scale is S1 + S2 = 2")

# F. Division: S1 / S2 -> scale = S1 - S2
err5 = stdlib_decimal_div.call(2625, 2, 25, 1, out_val, out_scale) # 26.25 / 2.5 = 10.5 (scale = 1)
res_val = out_val[0, 8].unpack1("q")
res_scale = out_scale[0, 4].unpack1("l")
assert_equal(0, err5, "Division succeeds")
assert_equal(105, res_val, "Division scale subtraction computes 105")
assert_equal(1, res_scale, "Division scale is S1 - S2 = 1")

# G. Division by zero -> OOF-DM2
err6 = stdlib_decimal_div.call(2625, 2, 0, 1, out_val, out_scale)
assert_equal(2, err6, "Division by zero fails with division error code (OOF-DM2)")

puts "\n#{BOLD}#{CYAN}=== 4. Verifying Signature File Hygiene ===#{RESET}"
assert(File.exist?(File.expand_path("stdlib/math.ig", __dir__)), "stdlib/math.ig is present")
assert(File.exist?(File.expand_path("stdlib/collections.ig", __dir__)), "stdlib/collections.ig is present")
assert(File.exist?(File.expand_path("stdlib/temporal.ig", __dir__)), "stdlib/temporal.ig is present")

if $failed_assertions == 0
  puts "\n#{GREEN}🏆 ALL STANDARD LIBRARY CORRECTNESS AND LINKABILITY TESTS PASSED SUCCESSFULLY!#{RESET}\n\n"
  exit(0)
else
  puts "\n#{RED}[!] #{$failed_assertions} TESTS FAILED!#{RESET}\n\n"
  exit(1)
end
