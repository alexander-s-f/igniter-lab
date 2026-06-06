# frozen_string_literal: true

require "json"
require "fileutils"

# ANSI styling
GREEN  = "\e[32m"
RED    = "\e[31m"
YELLOW = "\e[33m"
CYAN   = "\e[36m"
BOLD   = "\e[1m"
RESET  = "\e[0m"

$failed = false

def assert_equal(expected, actual, msg)
  if expected == actual
    puts "  #{GREEN}✔ PASS:#{RESET} #{msg}"
  else
    puts "  #{RED}✘ FAIL:#{RESET} #{msg} - Expected: #{expected.inspect}, Got: #{actual.inspect}"
    $failed = true
  end
end

puts "\n#{BOLD}#{CYAN}=== Ruby FFI Bindings Verification ===#{RESET}"

# Build native library
puts "Building native extension..."
build_ok = system("RUSTFLAGS='-C link-arg=-undefined -C link-arg=dynamic_lookup' cargo build --release")
unless build_ok
  puts "#{RED}Compilation failed!#{RESET}"
  exit 1
end

# Create symlink/copy for Ruby to load it on macOS
release_dir = File.expand_path("target/release", __dir__)
dylib = File.join(release_dir, "libigniter_machine.dylib")
bundle = File.join(release_dir, "igniter_machine.bundle")
if File.exist?(dylib)
  FileUtils.ln_sf("libigniter_machine.dylib", bundle)
end

# Load library from release target
$LOAD_PATH.unshift(release_dir)
require "igniter_machine"

# 1. Initialize Machine
machine = Igniter::Machine.new(nil, "in_memory")
puts "Machine initialized successfully!"

# 2. Compile and Register Contract in-process
source = <<~CONTRACT
  module Lang.Examples.Add
  contract Add {
    input  a: Integer
    input  b: Integer
    compute sum = a + b
    output sum: Integer
  }
CONTRACT

machine.load_contract(source, "Add")
puts "Contract loaded successfully!"

# 3. Dispatch and execute VM in-process (No TCP loopback!)
res = machine.dispatch("Add", { "a" => 19, "b" => 23 })
assert_equal(42, res, "Dispatch returns correct sum from in-process VM execution")

# 4. Write fact bitemporally in-process
fact = {
  "id" => "fact_ruby_1",
  "store" => "sales",
  "key" => "invoice_42",
  "value" => { "amount" => 250.75 },
  "value_hash" => "hash_string",
  "transaction_time" => 500.0,
  "valid_time" => 500.0,
  "schema_version" => 1
}
machine.write_fact(fact)
puts "Fact written successfully!"

# 5. Read fact travel point
read_f = machine.read_fact("sales", "invoice_42", 600.0)
assert_equal(250.75, read_f["value"]["amount"], "Bitemporal read retrieves correct fact value")

# 6. Checkpoint image to file
image_file = "image_test.igm"
FileUtils.rm_f(image_file)
machine.checkpoint(image_file)
assert_equal(true, File.exist?(image_file), "Checkpoint correctly dumped semantic image to disk")

# 7. Resume state from image
machine2 = Igniter::Machine.resume(image_file, nil, "in_memory")
puts "Resumed from checkpoint successfully!"

# Verify resumed contract execution
res2 = machine2.dispatch("Add", { "a" => 10, "b" => 20 })
assert_equal(30, res2, "Resumed machine successfully executes compiled contracts")

# Verify resumed bitemporal facts
read_f2 = machine2.read_fact("sales", "invoice_42", 600.0)
assert_equal(250.75, read_f2["value"]["amount"], "Resumed machine correctly preloaded all bitemporal facts")

FileUtils.rm_f(image_file)

if $failed
  puts "\n#{RED}✘ FFI bindings verification FAILED!#{RESET}"
  exit 1
else
  puts "\n#{GREEN}🏆 FFI BINDINGS VERIFICATION PASSED SUCCESSFULLY!#{RESET}"
  exit 0
end
