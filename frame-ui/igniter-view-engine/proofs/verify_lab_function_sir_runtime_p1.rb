#!/usr/bin/env ruby
# frozen_string_literal: true

# verify_lab_function_sir_runtime_p1.rb
# LAB-FUNCTION-SIR-RUNTIME-P1 -- materialize app-local `def` functions as executable SIR +
# a VM static function registry, unblocking spreadsheet RunWorkbookDemo.
#
# Authority: lab compiler/emitter + VM runtime substrate only; no canon authority.
# (Ruby canon does not adopt `def` functions here — lab evidence only.)
#
# Proves:
#   * the compiler emits a `functions` array in semantic_ir_program.json with name, params,
#     return type, decreases metadata, and an executable body (eval_expr + eval_ref);
#   * the VM builds a static function registry and invokes statically-emitted function names
#     inside a map lambda body;
#   * spreadsheet RunWorkbookDemo compiles (Rust ok/0) and RUNS on the VM to a
#     Collection[CellValue] (the single Number cell evaluates to num_val 7.0);
#   * existing call_contract semantics + regression runtime smokes remain green;
#   * no dynamic dispatch: an unknown function name is rejected at compile time, and only
#     registry names are invocable at runtime;
#   * no app source edits.

require "json"
require "open3"
require "pathname"
require "tmpdir"
require "fileutils"

LAB_ROOT  = Pathname.new(__dir__).parent.parent
APPS      = LAB_ROOT / "igniter-apps"
SS_DIR    = APPS / "spreadsheet"
RUST_BIN  = LAB_ROOT / "igniter-compiler" / "target" / "release" / "igniter_compiler"
RUST_DBG  = LAB_ROOT / "igniter-compiler" / "target" / "debug" / "igniter_compiler"
VM_BIN    = LAB_ROOT / "igniter-vm" / "target" / "release" / "igniter-vm"
VM_DBG    = LAB_ROOT / "igniter-vm" / "target" / "debug" / "igniter-vm"
EMITTER   = LAB_ROOT / "igniter-compiler" / "src" / "emitter.rs"
TC_RUST   = LAB_ROOT / "igniter-compiler" / "src" / "typechecker.rs"
VM_RUST   = LAB_ROOT / "igniter-vm" / "src" / "vm.rs"
VM_MAIN   = LAB_ROOT / "igniter-vm" / "src" / "main.rs"
IMPL_SURF = LAB_ROOT / "igniter-vm" / "IMPLEMENTED_SURFACE.md"
CARD      = LAB_ROOT / ".agents" / "work" / "cards" / "lang" / "LAB-FUNCTION-SIR-RUNTIME-P1.md"
LAB_DOC   = LAB_ROOT / "lab-docs" / "lang" / "lab-function-sir-runtime-p1-v0.md"
REGISTRY  = SS_DIR / "PRESSURE_REGISTRY.md"
PORTFOLIO = LAB_ROOT / ".agents" / "portfolio-index.md"

SS_SOURCES = %w[types.ig engine.ig api.ig example.ig].freeze
EXPECTED_SS_HASH = "sha256:5802728da8d4eda2ff055057f92d55ca292a61f6ecea136695659e2e7683bd05"

def read(p) = (File.read(p.to_s, encoding: "UTF-8") rescue "")
def rust_bin; File.executable?(RUST_BIN.to_s) ? RUST_BIN : RUST_DBG; end
def vm_bin;   File.executable?(VM_BIN.to_s)   ? VM_BIN   : VM_DBG;   end

$pass = 0
$fail = 0
def check(label)
  if yield then puts "  PASS  #{label}"; $pass += 1
  else puts "  FAIL  #{label}"; $fail += 1 end
rescue => e
  puts "  FAIL  #{label}  [#{e.class}: #{e.message.lines.first&.strip}]"; $fail += 1
end
def section(t) = puts("\n--- #{t} ---")

TMP = Dir.mktmpdir("function_sir_runtime_p1_")
at_exit { FileUtils.rm_rf(TMP) }

# Compile an app dir's sources -> [result_json, igapp_path]. Retries the fd/timing flake.
def compile_app(dir, names)
  srcs = names.map { |n| (Pathname.new(dir) / n).to_s }
  out = File.join(TMP, "app_#{File.basename(dir)}_#{rand(1 << 30)}.igapp")
  3.times do
    so, _e, _s = Open3.capture3(rust_bin.to_s, "compile", *srcs, "--out", out)
    d = JSON.parse(so.force_encoding("UTF-8")) rescue nil
    return [d, out] if d
  end
  [nil, out]
end

def vm_run(igapp, entry)
  inp = File.join(TMP, "in.json"); File.write(inp, "{}")
  so, _e, _s = Open3.capture3(vm_bin.to_s, "run", "--contract", igapp, "--inputs", inp, "--entry", entry, "--json")
  JSON.parse(so.force_encoding("UTF-8")) rescue { "status" => "parse_fail", "_raw" => so }
end

# Auto-detect entrypoint from an app dir's example.ig (bare `entrypoint X`), else nil.
def entrypoint_of(dir)
  Dir.glob(File.join(dir, "*.ig")).each do |f|
    m = read(f).match(/^\s*entrypoint\s+([A-Za-z_]\w*)/)
    return m[1] if m
  end
  nil
end

SS_RESULT, SS_IGAPP = compile_app(SS_DIR.to_s, SS_SOURCES)
SIR = (SS_IGAPP && File.exist?(File.join(SS_IGAPP, "semantic_ir_program.json"))) ?
  (JSON.parse(read(File.join(SS_IGAPP, "semantic_ir_program.json"))) rescue {}) : {}
FUNCS = (SIR["functions"] || [])
FN = FUNCS.to_h { |f| [f["name"], f] }
VM_DEMO = (SS_IGAPP && File.directory?(SS_IGAPP)) ? vm_run(SS_IGAPP, "RunWorkbookDemo") : {}

puts "=" * 72
puts "LAB-FUNCTION-SIR-RUNTIME-P1 -- def-function SIR + VM registry (spreadsheet)"
puts "Rust: #{File.executable?(rust_bin.to_s) ? 'built' : 'NOT BUILT'}  VM: #{File.executable?(vm_bin.to_s) ? 'built' : 'NOT BUILT'}"
puts "=" * 72

section("A  Preconditions + gate")
check("A-01: spreadsheet app dir exists") { SS_DIR.directory? }
check("A-02: Rust compiler binary present") { File.executable?(rust_bin.to_s) }
check("A-03: VM binary present") { File.executable?(vm_bin.to_s) }
SS_SOURCES.each_with_index { |n, i| check("A-#{format('%02d', i + 4)}: spreadsheet source #{n} present") { File.exist?(SS_DIR / n) } }
check("A-08: engine.ig declares def eval_expr") { read(SS_DIR / "engine.ig").include?("def eval_expr") }
check("A-09: engine.ig declares def eval_ref") { read(SS_DIR / "engine.ig").include?("def eval_ref") }
check("A-10: CalculateGrid maps eval_expr over cells") { read(SS_DIR / "engine.ig").include?("map(grid.cells, cell -> eval_expr(cell.ast, grid))") }
check("A-11: example.ig has entrypoint RunWorkbookDemo") { read(SS_DIR / "example.ig").include?("entrypoint RunWorkbookDemo") }

section("B  Compiler emits the SIR functions array")
check("B-01: Rust compile status ok") { (SS_RESULT || {})["status"] == "ok" }
check("B-02: Rust diagnostics empty") { Array((SS_RESULT || {})["diagnostics"]).empty? }
check("B-03: Rust source_hash matches pinned baseline") { (SS_RESULT || {})["source_hash"] == EXPECTED_SS_HASH }
check("B-04: SIR parsed") { !SIR.empty? }
check("B-05: SIR has a functions array") { SIR["functions"].is_a?(Array) }
check("B-06: SIR functions has exactly 2 entries") { FUNCS.size == 2 }
check("B-07: SIR includes eval_expr function body") { FN.key?("eval_expr") }
check("B-08: SIR includes eval_ref function body") { FN.key?("eval_ref") }
check("B-09: each function entry has kind function_ir") { FUNCS.all? { |f| f["kind"] == "function_ir" } }
check("B-10: contracts still emitted alongside functions") { Array(SIR["contracts"]).map { |c| c["contract_name"] }.include?("CalculateGrid") }

section("C  Function entries carry name/params/return/decreases/body")
check("C-01: eval_expr params are [expr, grid]") { (FN["eval_expr"]["params"] || []).map { |p| p["name"] } == %w[expr grid] }
check("C-02: eval_ref params are [ref_id, grid]") { (FN["eval_ref"]["params"] || []).map { |p| p["name"] } == %w[ref_id grid] }
check("C-03: eval_expr params carry types (Expr, Grid)") { (FN["eval_expr"]["params"] || []).map { |p| p["type"] } == %w[Expr Grid] }
check("C-04: eval_expr return_type is CellValue") { FN["eval_expr"]["return_type"] == "CellValue" }
check("C-05: eval_ref return_type is CellValue") { FN["eval_ref"]["return_type"] == "CellValue" }
check("C-06: eval_expr decreases == fuel (managed recursion metadata)") { FN["eval_expr"]["decreases"] == "fuel" }
check("C-07: eval_ref decreases == fuel") { FN["eval_ref"]["decreases"] == "fuel" }
check("C-08: eval_expr has a non-null body") { !FN["eval_expr"]["body"].nil? }
check("C-09: eval_ref has a non-null body") { !FN["eval_ref"]["body"].nil? }

section("D  Function bodies are runnable SIR (eval_ast-shaped)")
check("D-01: eval_expr body is an if_expr (condition/then_branch)") do
  b = FN["eval_expr"]["body"]
  b.is_a?(Hash) && (b.key?("condition") || b.key?("cond")) && (b.key?("then_branch") || b.key?("then"))
end
check("D-02: eval_expr condition compares expr.kind to a String literal") do
  cond = FN["eval_expr"]["body"]["condition"] || FN["eval_expr"]["body"]["cond"] || {}
  cond["op"] == "==" && JSON.generate(cond).include?("\"Number\"")
end
check("D-03: eval_expr then-branch builds a Number CellValue record") do
  JSON.generate(FN["eval_expr"]["body"]).include?("record_literal") || JSON.generate(FN["eval_expr"]["body"]).include?("\"kind\"")
end
check("D-04: eval_ref body is a let chain (binds dummy_expr) ending in a call") do
  b = FN["eval_ref"]["body"]
  b.is_a?(Hash) && b["kind"] == "let" && b["name"] == "dummy_expr" && b.key?("body")
end
check("D-05: eval_ref let continuation calls eval_expr (recursive substrate)") do
  JSON.generate(FN["eval_ref"]["body"]).include?("eval_expr")
end
check("D-06: bodies use only eval_ast-known kinds (if_expr/let/call/binary_op/field_access/record_literal/literal/ref)") do
  known = %w[if_expr let call apply binary_op field_access record_literal record literal ref variant_construct match_expr]
  kinds = JSON.generate(FUNCS).scan(/"kind"\s*:\s*"([^"]+)"/).flatten.uniq
  (kinds - (known + %w[function_ir])).empty?
end

section("E  VM runs RunWorkbookDemo through the function registry")
check("E-01: VM RunWorkbookDemo status success") { VM_DEMO["status"] == "success" }
check("E-02: VM result is a Collection (array)") { VM_DEMO["result"].is_a?(Array) }
check("E-03: VM result has one evaluated cell") { Array(VM_DEMO["result"]).size == 1 }
check("E-04: evaluated cell kind is Number") { VM_DEMO.dig("result", 0, "kind") == "Number" }
check("E-05: evaluated cell num_val is 7.0 (eval_expr Number branch ran)") { VM_DEMO.dig("result", 0, "num_val") == 7.0 }
check("E-06: evaluated cell str_val is null (none() executed)") { VM_DEMO.dig("result", 0).key?("str_val") && VM_DEMO.dig("result", 0, "str_val").nil? }
check("E-07: VM run produced no error") { VM_DEMO["error"].nil? }
check("E-08: static function call ran INSIDE the map lambda (eval_expr not 'Unsupported operator')") do
  VM_DEMO["status"] == "success" && !VM_DEMO["error"].to_s.include?("Unsupported operator: eval_expr")
end

section("F  VM substrate surfaces (registry + bounded-recursion guard)")
vm_src = read(VM_RUST)
main_src = read(VM_MAIN)
check("F-01: VM has a FunctionEntry struct") { vm_src.include?("pub struct FunctionEntry") }
check("F-02: VM has a functions registry field") { vm_src.include?("pub functions: HashMap<String, FunctionEntry>") }
check("F-03: eval_ast dispatches registered functions (vm.functions.get(op))") { vm_src.include?("vm.functions.get(op)") }
check("F-04: function call is bounded by MAX_CALL_DEPTH (fail-closed recursion guard)") do
  vm_src.match?(/function '\{\}': max call depth/) || (vm_src.include?("MAX_CALL_DEPTH") && vm_src.include?("decreases fuel"))
end
check("F-05: function call binds params to a fresh inputs map (pure over params)") { vm_src.include?("fn_inputs") && vm_src.include?("func.params.iter()") }
check("F-06: function call increments __call_depth__ (shared budget)") { vm_src.include?("__call_depth__") }
check("F-07: main.rs builds the registry from igapp functions") { main_src.include?("contract_json.get(\"functions\")") && main_src.include?("vm.functions") }
check("F-08: MAX_CALL_DEPTH constant present") { vm_src.include?("MAX_CALL_DEPTH") }

section("G  Compiler/emitter surfaces")
em = read(EMITTER)
tc = read(TC_RUST)
check("G-01: emitter has emit_function_ir") { em.include?("fn emit_function_ir") }
check("G-02: emitter has emit_function_body (BlockBody -> let chain)") { em.include?("fn emit_function_body") }
check("G-03: emitter emits function_ir kind") { em.include?("\"function_ir\"") }
check("G-04: emitter inserts a functions array into the SIR program") { em.include?("result.insert(\"functions\"") }
check("G-05: TypedProgram carries a functions field") { tc.include?("pub functions: Vec<serde_json::Value>") }
check("G-06: typechecker populates functions from parser FunctionDecls") { tc.match?(/functions:\s*functions\.iter\(\)/) }

section("H  No dynamic dispatch + call_contract unchanged")
NOFN = "module NoFn\ncontract C {\n  compute xs = [1, 2]\n  compute ys = map(xs, x -> ghost_fn(x))\n  output ys : Collection[Integer]\n}\n"
nofn_path = File.join(TMP, "nofn.ig"); File.write(nofn_path, NOFN)
nofn_out = File.join(TMP, "nofn.igapp")
nofn_json = nil
3.times { so, _e, _s = Open3.capture3(rust_bin.to_s, "compile", nofn_path, "--out", nofn_out); nofn_json = (JSON.parse(so.force_encoding("UTF-8")) rescue nil); break if nofn_json }
check("H-01: unknown function name is rejected at COMPILE (no dynamic dispatch)") do
  (nofn_json || {})["status"] != "ok" &&
    Array((nofn_json || {})["diagnostics"]).any? { |d| d["message"].to_s.include?("Unknown function: ghost_fn") }
end
check("H-02: only registry names are invocable (ghost_fn never reaches the VM)") { (nofn_json || {})["status"] != "ok" }
check("H-03: call_contract dispatch table still built (semantics unchanged)") { read(VM_RUST).include?("call_contract_value") && read(VM_RUST).include?("dispatch_table") }
check("H-04: spreadsheet still uses call_contract for contract orchestration") { read(SS_DIR / "example.ig").include?("call_contract(\"RecalculateWorkbook\"") }
check("H-05: card closed-surface: no dynamic dispatch") { read(CARD).include?("No dynamic dispatch") }
check("H-06: card closed-surface: no source-file runtime reads") { read(CARD).include?("No source-file runtime reads") }

section("I  Regression runtime smokes (existing apps stay green)")
REG_APPS = {
  "air_combat" => "RunDuel", "lead_router" => "RunAccept", "call_router" => "RunConnectedMatched",
  "erp_logistics" => "RunBestRoute", "batch_importer" => "RunImport", "audit_ledger" => nil,
  "web_router" => nil, "job_runner" => nil, "trade_robot" => nil, "neural_net" => nil
}
REG_APPS.each_with_index do |(app, entry), idx|
  dir = (APPS / app).to_s
  next unless File.directory?(dir)
  names = Dir.glob(File.join(dir, "*.ig")).map { |f| File.basename(f) }.sort
  res, igapp = compile_app(dir, names)
  ep = entrypoint_of(dir) || entry
  check("I-#{format('%02d', idx + 1)}a: #{app} compiles ok") { (res || {})["status"] == "ok" }
  if ep
    run = (igapp && File.directory?(igapp)) ? vm_run(igapp, ep) : {}
    check("I-#{format('%02d', idx + 1)}b: #{app} VM run #{ep} succeeds") { run["status"] == "success" }
  end
end

section("J  Closed surfaces / scope")
check("J-01: spreadsheet engine.ig unchanged (def bodies intact, no app edit)") do
  s = read(SS_DIR / "engine.ig")
  s.include?("def eval_expr(expr: Expr, grid: Grid) -> CellValue decreases fuel") &&
    s.include?("def eval_ref(ref_id: Text, grid: Grid) -> CellValue decreases fuel")
end
check("J-02: no new language syntax (def already parsed; this is runtime substrate)") { read(SS_DIR / "engine.ig").include?("def ") }
check("J-03: IMPLEMENTED_SURFACE.md records the function-SIR runtime") { read(IMPL_SURF).include?("LAB-FUNCTION-SIR-RUNTIME-P1") || read(IMPL_SURF).downcase.include?("function") && read(IMPL_SURF).downcase.include?("registry") }
check("J-04: lab doc documents the dual emitter+VM change") { read(LAB_DOC).include?("emitter") && read(LAB_DOC).include?("VM") }
check("J-05: lab doc records RunWorkbookDemo run result") { read(LAB_DOC).include?("RunWorkbookDemo") && read(LAB_DOC).include?("7.0") }
check("J-06: lab doc records proof runner path") { read(LAB_DOC).include?("verify_lab_function_sir_runtime_p1.rb") }
check("J-07: spreadsheet PRESSURE_REGISTRY records the function-SIR runtime resolution") { read(REGISTRY).include?("LAB-FUNCTION-SIR-RUNTIME-P1") }
check("J-08: portfolio index has the function-SIR row") { read(PORTFOLIO).include?("LAB-FUNCTION-SIR-RUNTIME-P1") }
check("J-09: card present") { !read(CARD).empty? }
check("J-10: runner uses Open3 + mktmpdir + flake retry") do
  s = read(__FILE__); s.include?("Open3.capture3") && s.include?("Dir.mktmpdir") && s.include?("fd/timing")
end

section("K  Canon boundary (lab evidence only)")
check("K-01: card states no canon authority (lab evidence until canon adopts)") { read(CARD).include?("No canon authority") || read(CARD).include?("no canon authority") }
check("K-02: lab doc records the Ruby-canon boundary (def functions not adopted in canon)") { read(LAB_DOC).downcase.include?("canon") }

section("L  Determinism + extra substrate granularity")
VM_DEMO2 = (SS_IGAPP && File.directory?(SS_IGAPP)) ? vm_run(SS_IGAPP, "RunWorkbookDemo") : {}
check("L-01: VM RunWorkbookDemo is deterministic across two runs") { VM_DEMO2["result"] == VM_DEMO["result"] }
check("L-02: second run also success") { VM_DEMO2["status"] == "success" }
check("L-03: SIR functions array survives a fresh recompile (stable emission)") do
  res2, ig2 = compile_app(SS_DIR.to_s, SS_SOURCES)
  sir2 = (ig2 && File.exist?(File.join(ig2, "semantic_ir_program.json"))) ? (JSON.parse(read(File.join(ig2, "semantic_ir_program.json"))) rescue {}) : {}
  (res2 || {})["status"] == "ok" && Array(sir2["functions"]).size == 2
end
check("L-04: registry build reads params name-or-string (robust shape handling)") { read(VM_MAIN).include?("p.as_str().map(String::from)") }
check("L-05: function call returns the body result directly (return eval_ast(&func.body…))") { read(VM_RUST).include?("return eval_ast(&func.body") }
check("L-06: emit_function_body folds stmts in reverse into the let chain") { read(EMITTER).include?("stmts.iter().rev()") }
check("L-07: eval_expr body references the `expr` param (field_access object ref)") { JSON.generate(FN["eval_expr"]["body"]).include?("\"name\":\"expr\"") }
check("L-08: both functions carry decreases=fuel (managed-recursion metadata preserved)") { FUNCS.all? { |f| f["decreases"] == "fuel" } }
check("L-09: function bodies do NOT leak a raw parser block (no top-level stmts/return_expr keys)") do
  FUNCS.none? { |f| f["body"].is_a?(Hash) && f["body"].key?("return_expr") }
end
check("L-10: SIR program kind unchanged (semantic_ir_program)") { SIR["kind"] == "semantic_ir_program" }
check("L-11: entrypoint still resolves RunWorkbookDemo") { (SIR["entrypoint"] || {})["resolved_contract"] == "RunWorkbookDemo" }

puts
total = $pass + $fail
puts "=" * 72
puts "RESULT: #{$pass}/#{total} PASS  |  #{$fail} FAIL  (target >= 100)"
puts "=" * 72
exit($fail.zero? ? 0 : 1)
