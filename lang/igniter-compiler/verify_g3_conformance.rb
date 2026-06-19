# verify_g3_conformance.rb
# Lab G3 conformance verification — three sub-tasks:
#   G3a: OOF-R2 (recursive missing decreases) + OOF-R4 (fuel_bounded/decreases fuel missing max_steps)
#   G3b: FiniteLoop `for Name item in source { body }` — parse → exec
#   G3c: IR shape — kind="loop_node", loop_class, termination, source_ref

require 'json'
require 'tmpdir'
require 'fileutils'
require 'pathname'
require_relative '../tools/proof_harness/bounded_command'

ROOT    = Pathname.new(__dir__)
COMP    = ROOT / "target/release/igniter_compiler"
VM_TOML = File.expand_path("../igniter-vm/Cargo.toml", __dir__)

$pass_count = 0
$fail_count = 0

def pass(msg)  = (puts "[+] PASS: #{msg}";  $pass_count += 1)
def fail!(msg) = (puts "[!] FAIL: #{msg}";  $fail_count += 1)

def compile_src(src, label)
  tmp = Dir.mktmpdir("g3_#{label}")
  ig  = File.join(tmp, "#{label}.ig")
  out = File.join(tmp, "#{label}.igapp")
  File.write(ig, src)
  # LAB-PROOF-HYGIENE-P1: bounded execution — hard timeout, kills process group
  r = BoundedCommand.run("#{COMP} compile #{ig} --out #{out}",
                         label: "compile:#{label}",
                         timeout: BoundedCommand::EXEC_TIMEOUT)
  BoundedCommand.print_result(r) unless r.ok?
  [r.combined, out, tmp]
end

def run_vm(app, inputs_json)
  tmp    = Dir.mktmpdir("g3_vm")
  infile = File.join(tmp, "inputs.json")
  File.write(infile, inputs_json.to_json)
  # LAB-PROOF-HYGIENE-P1: bounded VM execution — hard timeout, kills process group
  r = BoundedCommand.run(
    "cargo run --manifest-path #{VM_TOML} --release -- run --contract #{app} --inputs #{infile} --json",
    label: "vm:run",
    timeout: BoundedCommand::CARGO_TIMEOUT
  )
  FileUtils.rm_rf(tmp)
  BoundedCommand.print_result(r) unless r.ok?
  r.stdout
rescue => e
  "[run_vm error: #{e.message}]"
end

unless COMP.exist?
  puts "[*] Building compiler..."
  # LAB-PROOF-HYGIENE-P1: bounded cargo build
  r = BoundedCommand.run("cargo build --release",
                         label: "cargo build --release",
                         timeout: BoundedCommand::CARGO_TIMEOUT)
  unless r.ok?
    BoundedCommand.print_result(r)
    puts "[!] Compiler build failed — aborting"
    exit(1)
  end
end

puts "\n=== G3a: OOF-R2 / OOF-R4 diagnostic conformance ===\n"

# OOF-R2: recursive contract without decreases → classifier emits OOF-R2
SRC_R2_BAD = <<~IGNITER
  module M1
  recursive contract BadRecursive {
    input n: Integer
    output r: Integer
    compute r = n
  }
IGNITER

result, out, tmp = compile_src(SRC_R2_BAD, "oof_r2_bad")
FileUtils.rm_rf(tmp)
if result.include?("OOF-R2")
  pass "OOF-R2 fires for recursive contract without decreases"
else
  fail! "OOF-R2 not emitted for recursive without decreases (got: #{result[0..200]})"
end

# OOF-R2 suppressed: recursive contract WITH decreases → no OOF-R2
SRC_R2_GOOD = <<~IGNITER
  module M1
  recursive contract GoodRecursive {
    input n: Integer
    output r: Integer
    decreases n
    compute r = n
  }
IGNITER

result, out, tmp = compile_src(SRC_R2_GOOD, "oof_r2_good")
FileUtils.rm_rf(tmp)
if result.include?("OOF-R2")
  fail! "OOF-R2 incorrectly fires for recursive WITH decreases"
else
  pass "OOF-R2 suppressed for recursive contract with decreases"
end

# OOF-R4: fuel_bounded without max_steps
SRC_R4_BAD = <<~IGNITER
  module M1
  fuel_bounded contract BadFuel {
    input n: Integer
    output r: Integer
    compute r = n
  }
IGNITER

result, out, tmp = compile_src(SRC_R4_BAD, "oof_r4_bad")
FileUtils.rm_rf(tmp)
if result.include?("OOF-R4")
  pass "OOF-R4 fires for fuel_bounded without max_steps"
else
  fail! "OOF-R4 not emitted for fuel_bounded without max_steps (got: #{result[0..200]})"
end

# OOF-R4 suppressed: fuel_bounded WITH max_steps
SRC_R4_GOOD = <<~IGNITER
  module M1
  fuel_bounded contract GoodFuel {
    input n: Integer
    output r: Integer
    max_steps 100
    compute r = n
  }
IGNITER

result, out, tmp = compile_src(SRC_R4_GOOD, "oof_r4_good")
FileUtils.rm_rf(tmp)
if result.include?("OOF-R4")
  fail! "OOF-R4 incorrectly fires for fuel_bounded WITH max_steps"
else
  pass "OOF-R4 suppressed for fuel_bounded with max_steps"
end

# OOF-R4: recursive + decreases fuel without max_steps
SRC_R4_FUEL_BAD = <<~IGNITER
  module M1
  recursive contract FuelNoSteps {
    input n: Integer
    output r: Integer
    decreases fuel
    compute r = n
  }
IGNITER

result, out, tmp = compile_src(SRC_R4_FUEL_BAD, "oof_r4_fuel_bad")
FileUtils.rm_rf(tmp)
if result.include?("OOF-R4")
  pass "OOF-R4 fires for recursive + decreases fuel without max_steps"
else
  fail! "OOF-R4 not emitted for recursive+decreases fuel missing max_steps (got: #{result[0..200]})"
end

puts "\n=== G3b: FiniteLoop `for Name item in source { body }` ===\n"

SRC_FINITE = <<~IGNITER
  module W1
  contract SumAll {
    input items: Collection[Integer]
    compute total = 0
    for ProcessAll item in items {
      compute total = total + item
    }
    output total: Integer
  }
IGNITER

result, app_path, tmp = compile_src(SRC_FINITE, "finite_loop")
if result.include?("OOF-") && !result.include?("finished") && !result.include?("Compiling")
  # Check if it's only pre-existing OOF-L1 from the loop without max_steps path (shouldn't appear for for)
  oof_codes = result.scan(/OOF-\w+/).uniq
  # OOF-L1 is the lab "unbounded loop" check — for `for` loop it should NOT fire
  if oof_codes.any? { |c| c == "OOF-L1" && result.include?("unbounded") }
    fail! "FiniteLoop `for` incorrectly triggers unbounded-loop OOF-L1"
  end
end

# Try to compile and see if it succeeds at all
compile_ok = File.exist?(app_path)
if compile_ok
  pass "FiniteLoop `for Name item in source { body }` compiles successfully"
else
  fail! "FiniteLoop failed to compile (output: #{result[0..300]})"
  FileUtils.rm_rf(tmp)
end

if compile_ok
  # Check IR shape: kind=loop_node, loop_class=finite, termination=collection_exhaustion
  # .igapp is a directory; IR lives in semantic_ir_program.json
  sir_path = File.join(app_path, "semantic_ir_program.json")
  if File.exist?(sir_path)
    app_data = JSON.parse(File.read(sir_path)) rescue nil
    if app_data
      contracts = app_data["contracts"] || []
      loop_nodes = []
      (contracts.is_a?(Array) ? contracts : [contracts]).each do |contract|
        nodes = contract["nodes"] || []
        nodes.each { |n| loop_nodes << n if n["kind"] == "loop_node" || n["kind"] == "loop" }
      end

      finite_nodes = loop_nodes.select { |n| n["loop_class"] == "finite" }

      if loop_nodes.any? { |n| n["kind"] == "loop_node" }
        pass "G3c: IR shape kind='loop_node' (was 'loop')"
      else
        fail! "G3c: IR kind still 'loop', expected 'loop_node' (found: #{loop_nodes.map{|n| n['kind']}})"
      end

      if finite_nodes.any?
        n = finite_nodes.first
        if n["termination"] == "collection_exhaustion"
          pass "G3c: FiniteLoop termination='collection_exhaustion'"
        else
          fail! "G3c: FiniteLoop termination='#{n['termination']}', expected 'collection_exhaustion'"
        end
        if n["source_ref"]
          pass "G3c: source_ref='#{n['source_ref']}' present"
        else
          fail! "G3c: source_ref missing in FiniteLoop node"
        end
        pass "G3c: loop_class='finite' in IR"
      else
        fail! "G3c: No finite loop_node found in IR (nodes: #{loop_nodes.map{|n| n.slice('kind','loop_class')}})"
      end
    else
      fail! "G3c: Could not parse semantic_ir_program.json"
    end
  else
    fail! "G3c: semantic_ir_program.json not found in #{app_path}"
  end

  # Run VM execution for FiniteLoop
  puts "\n[*] Running FiniteLoop on VM (sum of [5,10,15] = 30)..."
  vm_result_raw = run_vm(app_path, { "items" => [5, 10, 15] })
  begin
    vm_response = JSON.parse(vm_result_raw)
    if vm_response["status"] == "success" && vm_response["result"] == 30
      pass "G3b: FiniteLoop VM executes correctly (5+10+15=30)"
    elsif vm_response["status"] == "success"
      fail! "G3b: FiniteLoop result=#{vm_response['result']}, expected 30"
    else
      fail! "G3b: VM error: #{vm_response['error']}"
    end
  rescue => e
    fail! "G3b: VM output parse failed: #{e.message} | raw=#{vm_result_raw[0..200]}"
  end

  FileUtils.rm_rf(tmp)
end

puts "\n=== G3c: BudgetedLocalLoop IR shape (existing loop) ===\n"

SRC_BUDGETED = <<~IGNITER
  module W1
  contract BudgetCheck {
    input nums: Collection[Integer]
    compute total = 0
    loop ProcessNums n in nums max_steps: 50 {
      compute total = total + n
    }
    output total: Integer
  }
IGNITER

result, app_path, tmp = compile_src(SRC_BUDGETED, "budgeted_ir")
sir_path = File.join(app_path, "semantic_ir_program.json")
if File.exist?(sir_path)
  app_data = JSON.parse(File.read(sir_path)) rescue nil
  if app_data
    contracts = app_data["contracts"] || []
    loop_nodes = []
    (contracts.is_a?(Array) ? contracts : [contracts]).each do |contract|
      nodes = contract["nodes"] || []
      nodes.each { |n| loop_nodes << n if n["kind"] == "loop_node" || n["kind"] == "loop" }
    end
    budgeted = loop_nodes.select { |n| n["loop_class"] == "budgeted" }
    if budgeted.any?
      n = budgeted.first
      pass "G3c: BudgetedLocalLoop kind='loop_node', loop_class='budgeted'"
      if n["termination"] == "budget_exhaustion"
        pass "G3c: BudgetedLocalLoop termination='budget_exhaustion'"
      else
        fail! "G3c: termination='#{n['termination']}', expected 'budget_exhaustion'"
      end
      if n["max_steps"]
        pass "G3c: max_steps=#{n['max_steps']} present at top level"
      else
        fail! "G3c: max_steps missing from top-level loop_node"
      end
    else
      fail! "G3c: No budgeted loop_node found (nodes: #{loop_nodes.map{|n| n.slice('kind','loop_class')}})"
    end
  end
end
FileUtils.rm_rf(tmp)

puts "\n==============================="
total = $pass_count + $fail_count
puts "[*] Results: #{$pass_count}/#{total} PASS, #{$fail_count} FAIL"
if $fail_count == 0
  puts "[+] G3 CONFORMANCE PASS — G3a OOF-R2/R4 ✓, G3b FiniteLoop ✓, G3c IR shape ✓"
  exit 0
else
  puts "[!] G3 CONFORMANCE FAIL — #{$fail_count} check(s) failed"
  exit 1
end
