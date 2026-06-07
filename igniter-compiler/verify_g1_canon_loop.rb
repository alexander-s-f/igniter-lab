# verify_g1_canon_loop.rb
# Conformance verification for G1: BudgetedLocalLoop item variable (PROP-039 gate 3)
#
# Canon grammar: loop Name item in source max_steps: N
# Tests that the Rust lab compiler accepts and correctly executes the canon form.
# Full vertical slice: .ig → parse → classify → typecheck → emit → assemble → bytecode → VM exec
#
# Expected: sum of [10, 20, 30, 40] = 100 (each `lead` added via `compute sum = sum + lead`)

require 'json'
require 'fileutils'
require 'pathname'

ROOT         = Pathname.new(__dir__)
FIXTURE      = ROOT / "fixtures/loops/budgeted_loop_canon_g1.ig"
OUT_IGAPP    = ROOT / "out/g1_canon_loop.igapp"
OUT_INPUTS   = ROOT / "out/g1_canon_loop_inputs.json"
COMPILER_BIN = ROOT / "target/release/igniter_compiler"
VM_MANIFEST  = File.expand_path("../igniter-vm/Cargo.toml", ROOT)

PASS = "[+]"
FAIL = "[!]"

FileUtils.mkdir_p(ROOT / "out")

failures = []

# ── Step 1: build compiler if needed ──────────────────────────────────────────
unless COMPILER_BIN.exist?
  puts "#{PASS} Building release compiler..."
  unless system("cargo build --release", chdir: ROOT.to_s)
    puts "#{FAIL} Compiler build failed"
    exit(1)
  end
end

# ── Step 2: compile canon fixture ─────────────────────────────────────────────
puts "[*] Compiling #{FIXTURE.basename}..."
compile_out = `#{COMPILER_BIN} compile #{FIXTURE} --out #{OUT_IGAPP} 2>&1`
unless $?.success?
  puts "#{FAIL} Compilation failed:\n#{compile_out}"
  exit(1)
end

result_json = JSON.parse(compile_out) rescue {}

if result_json["status"] != "ok"
  puts "#{FAIL} Compiler reported errors:"
  (result_json["diagnostics"] || []).each { |d| puts "    #{d["rule"]}: #{d["message"]}" }
  exit(1)
end

stages = result_json["stages"] || {}
%w[parse classify typecheck emit assemble].each do |stage|
  if stages[stage] == "ok"
    puts "#{PASS} Stage #{stage}: ok"
  else
    failures << "Stage #{stage}: #{stages[stage].inspect}"
    puts "#{FAIL} Stage #{stage}: #{stages[stage].inspect}"
  end
end

# ── Step 3: write inputs ───────────────────────────────────────────────────────
inputs = { "pending_leads" => [10, 20, 30, 40] }
File.write(OUT_INPUTS, JSON.generate(inputs))
puts "[*] Inputs: #{inputs}"

# ── Step 4: run on VM ─────────────────────────────────────────────────────────
puts "[*] Running on VM..."
vm_out = `cargo run --manifest-path #{VM_MANIFEST} --release -- run --contract #{OUT_IGAPP} --inputs #{OUT_INPUTS} --json 2>/dev/null`
unless $?.success?
  puts "#{FAIL} VM execution failed:\n#{vm_out}"
  exit(1)
end

vm_result = JSON.parse(vm_out) rescue {}
if vm_result["status"] == "success"
  sum = vm_result["result"]
  if sum == 100
    puts "#{PASS} VM result: #{sum} — correct (10+20+30+40=100)"
  else
    failures << "VM result: #{sum} (expected 100)"
    puts "#{FAIL} VM result: #{sum} (expected 100)"
  end
else
  failures << "VM error: #{vm_result["error"]}"
  puts "#{FAIL} VM error: #{vm_result["error"]}"
end

# ── Report ─────────────────────────────────────────────────────────────────────
puts
if failures.empty?
  puts "#{PASS} G1 CONFORMANCE PASS — canon `loop Name item in source` accepted and executed"
  puts "    full slice: parse ✓ → classify ✓ → typecheck ✓ → emit ✓ → assemble ✓ → VM exec ✓"
  exit(0)
else
  puts "#{FAIL} G1 CONFORMANCE FAIL"
  failures.each { |f| puts "    - #{f}" }
  exit(1)
end
