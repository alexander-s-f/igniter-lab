# verify_loops.rb
# End-to-end integration and verification script for loops and service loops.

require 'json'
require 'fileutils'
require 'pathname'

ROOT = Pathname.new(__dir__)
SOURCE_FILE = ROOT / "fixtures/conformance/source/loops_and_recursion.ig"
OUT_APP = ROOT / "out/loops_and_recursion.igapp"
INPUTS_FILE = ROOT / "out/loops_and_recursion_inputs.json"

FileUtils.mkdir_p(ROOT / "out")

# 1. Compile the contract
puts "[*] Compiling loops_and_recursion.ig..."
compiler_bin = ROOT / "target/release/igniter_compiler"
unless compiler_bin.exist?
  puts "[!] Target release compiler not found, building..."
  system("cargo build --release", chdir: ROOT.to_s)
end

cmd_compile = "#{compiler_bin} compile #{SOURCE_FILE} --out #{OUT_APP}"
compile_result = `#{cmd_compile}`
unless $?.success?
  puts "[!] Compilation failed!"
  puts compile_result
  exit(1)
end
puts "[+] Compilation successful!"

# 2. Write inputs file
inputs = {
  "pending_leads" => [10, 20, 30, 40],
  "tick.time" => 1710000000
}
File.write(INPUTS_FILE, JSON.pretty_generate(inputs))
puts "[*] Inputs file written to #{INPUTS_FILE}"

# 3. Run using igniter-vm via cargo run
puts "[*] Executing LoopTester contract on IVM..."
vm_cargo_toml = File.expand_path("../igniter-vm/Cargo.toml", __dir__)
cmd_run = "cargo run --manifest-path #{vm_cargo_toml} --release -- run --contract #{OUT_APP} --inputs #{INPUTS_FILE} --json"
vm_output = `#{cmd_run}`

unless $?.success?
  puts "[!] VM execution failed!"
  puts vm_output
  exit(1)
end

begin
  response = JSON.parse(vm_output)
  if response["status"] == "success"
    result = response["result"]
    puts "[+] VM execution successful! Result: #{result}"
    
    # Validate loop output: 10 + 20 + 30 + 40 = 100
    if result == 100
      puts "[+] Verification SUCCESS: Loop computed sum correctly!"
      exit(0)
    else
      puts "[!] Verification FAILURE: Loop computed sum as #{result}, expected 100"
      exit(1)
    end
  else
    puts "[!] VM execution reported error: #{response['error']}"
    exit(1)
  end
rescue => e
  puts "[!] Failed to parse VM output: #{e.message}"
  puts "    Raw output: #{vm_output}"
  exit(1)
end
