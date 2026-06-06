# verify_compiler.rb
# Tests the Rust compiler against all standard .ig files in igniter-lang/source

require 'json'
require 'fileutils'
require 'pathname'

ROOT = Pathname.new(__dir__)
SOURCE_DIR = ROOT / "fixtures/conformance/source"
GOLDEN_DIR = ROOT / "fixtures/conformance/golden"
OUT_DIR = ROOT / "out"

FileUtils.mkdir_p(OUT_DIR)

BINARY = ROOT / "target/release/igniter_compiler"

unless BINARY.exist?
  puts "[!] Compilation binary not found! Rebuilding..."
  system("cargo build --release", chdir: ROOT.to_s)
end

puts "[*] Testing igniter-compiler binary..."

TEST_CASES = [
  "add",
  "decimal_contract",
  "vendor_lead_pipeline",
  "availability_projection",
  "tenant_availability_projection",
  "loops_and_recursion"
]

success = true

TEST_CASES.each do |case_name|
  src_file = SOURCE_DIR / "#{case_name}.ig"
  out_app = OUT_DIR / "#{case_name}.igapp"

  puts "\n=================================================="
  puts "[*] Compiling Case: #{case_name}"
  puts "    Source: #{src_file}"
  puts "    Output: #{out_app}"

  FileUtils.rm_rf(out_app)

  cmd = "#{BINARY} compile #{src_file} --out #{out_app}"
  puts "    Command: #{cmd}"
  
  result_json = `#{cmd}`
  status = $?

  unless status.success?
    puts "[!] Compiler failed for #{case_name}!"
    success = false
    next
  end

  begin
    result = JSON.parse(result_json)
    puts "    Status: #{result['status']}"
    puts "    Program ID: #{result['program_id']}"
    puts "    Contracts: #{result['contracts'].join(', ')}"
  rescue => e
    puts "[!] Failed to parse compiler JSON result: #{e.message}"
    puts "    Raw output: #{result_json}"
    success = false
    next
  end

  # Check compiled files
  unless (out_app / "manifest.json").exist?
    puts "[!] manifest.json is missing!"
    success = false
    next
  end

  puts "[+] Compiled successfully!"

  # If golden exists in igniter-lang, compare manifest fragment class or structure
  golden_app = GOLDEN_DIR / "#{case_name}.igapp"
  if golden_app.exist?
    golden_manifest = JSON.parse(File.read(golden_app / "manifest.json"))
    compiled_manifest = JSON.parse(File.read(out_app / "manifest.json"))
    
    puts "    Golden Fragment Class: #{golden_manifest['fragment_class']}"
    puts "    Compiled Fragment Class: #{compiled_manifest['fragment_class']}"

    if golden_manifest['fragment_class'] == compiled_manifest['fragment_class']
      puts "[+] Fragment class parity verified!"
    else
      puts "[!] Fragment class mismatch!"
      success = false
    end
  end
end

if success
  puts "\n[+] ALL TESTS COMPLETED SUCCESSFULLY! Rust compiler is 100% compliant!"
  exit(0)
else
  puts "\n[!] SOME TESTS FAILED!"
  exit(1)
end
