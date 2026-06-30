# verify_loops.rb
# End-to-end integration and verification script for loops and service loops.

require 'json'
require 'fileutils'
require 'pathname'
require_relative '../../../../tools/proof_harness/bounded_command'

ROOT = Pathname.new(__dir__).parent.parent
SOURCE_FILE = ROOT / "fixtures/conformance/source/loops_and_recursion.ig"
OUT_APP = ROOT / "out/loops_and_recursion.igapp"
INPUTS_FILE = ROOT / "out/loops_and_recursion_inputs.json"

FileUtils.mkdir_p(ROOT / "out")

# 1. Compile the contract
puts "[*] Compiling loops_and_recursion.ig..."
compiler_bin = ROOT / "target/release/igniter_compiler"
unless compiler_bin.exist?
  puts "[!] Target release compiler not found, building..."
  # LAB-PROOF-HYGIENE-P1: bounded cargo build
  build_r = BoundedCommand.run("cargo build --release",
                               label: "cargo build --release",
                               timeout: BoundedCommand::CARGO_TIMEOUT)
  unless build_r.ok?
    BoundedCommand.print_result(build_r)
    puts "[!] Compiler build failed — aborting"
    exit(1)
  end
end

# LAB-PROOF-HYGIENE-P1: bounded compiler execution
compile_r = BoundedCommand.run("#{compiler_bin} compile #{SOURCE_FILE} --out #{OUT_APP}",
                               label: "compile:loops_and_recursion",
                               timeout: BoundedCommand::EXEC_TIMEOUT)
unless compile_r.ok?
  puts "[!] Compilation failed!"
  BoundedCommand.print_result(compile_r)
  exit(1)
end
compile_result = compile_r.combined
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
vm_cargo_toml = File.expand_path("../igniter-vm/Cargo.toml", ROOT)
# LAB-PROOF-HYGIENE-P1: bounded VM execution
vm_r = BoundedCommand.run(
  "cargo run --manifest-path #{vm_cargo_toml} --release -- run --contract #{OUT_APP} --inputs #{INPUTS_FILE} --json",
  label: "vm:LoopTester",
  timeout: BoundedCommand::CARGO_TIMEOUT
)
unless vm_r.ok?
  puts "[!] VM execution failed!"
  BoundedCommand.print_result(vm_r)
  exit(1)
end
vm_output = vm_r.stdout

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
