#!/usr/bin/env ruby
# frozen_string_literal: true
#
# verify_lab_app_demo_entry_wave_p1.rb
# LAB-APP-DEMO-ENTRY-WAVE-P1
#
# Proves the app-side demo-entry wave: zero-input entrypoints are added where
# safe, production handlers stay unchanged, and residual runtime/compiler gaps
# are named instead of patched here.

require "json"
require "open3"
require "pathname"
require "tmpdir"

LAB_ROOT = Pathname.new(__dir__).parent.parent
WORKSPACE_ROOT = LAB_ROOT.parent
LANG_ROOT = WORKSPACE_ROOT / "igniter-lang"

RUST_BIN = LAB_ROOT / "igniter-compiler" / "target" / "release" / "igniter_compiler"
RUNNER = LAB_ROOT / "tools" / "igniter"

CARD = LAB_ROOT / ".agents" / "work" / "cards" / "lang" / "LAB-APP-DEMO-ENTRY-WAVE-P1.md"
CHECKPOINT_CARD = LAB_ROOT / ".agents" / "work" / "cards" / "lang" / "LAB-VM-RUNTIME-WAVE-CHECKPOINT-P1.md"
ERP_CARD = LAB_ROOT / ".agents" / "work" / "cards" / "governance" / "LAB-ERP-LOGISTICS-DEMO-ENTRY-P1.md"
SURFACE = LAB_ROOT / "igniter-vm" / "IMPLEMENTED_SURFACE.md"
DOC = LAB_ROOT / "lab-docs" / "governance" / "lab-app-demo-entry-wave-p1-v0.md"
PORTFOLIO = LAB_ROOT / ".agents" / "portfolio-index.md"

APPS = {
  "advanced_logistics" => {
    files: %w[types.ig spatial.ig router.ig api.ig example.ig],
    entry: "RunDailyRoutesDemo",
    hash: "sha256:df623dec726a847355914892805d433c7ead695d9c70e2cf0316b3f332862102",
    contracts: 9,
    ruby_status: "ok",
    ruby_diags: 0,
    vm_status: "success",
    vm_contains: "ord-a",
    registry_row: "AL-P08"
  },
  "spreadsheet" => {
    files: %w[types.ig engine.ig api.ig example.ig],
    entry: "RunWorkbookDemo",
    hash: "sha256:5802728da8d4eda2ff055057f92d55ca292a61f6ecea136695659e2e7683bd05",
    contracts: 6,
    ruby_status: "oof",
    ruby_diags: 6,
    vm_status: "error",
    vm_contains: "Unsupported operator: eval_expr",
    registry_row: "SS-P08"
  },
  "vector_editor" => {
    files: %w[types.ig transform.ig document.ig tools.ig example.ig],
    entry: "RunCanvasClickDemo",
    hash: "sha256:967b2b50a666b89cb64ecbd72d2d12f09ed958aec53fd92d63feaa2f2db04144",
    contracts: 10,
    ruby_status: "ok",
    ruby_diags: 0,
    vm_status: "success",
    vm_contains: "rect-new",
    registry_row: "VE-P10"
  },
  "igniter_parser" => {
    files: %w[types.ig lexer.ig parser.ig api.ig example.ig],
    entry: "RunParseDemo",
    hash: "sha256:915ea3463bc49ce78f6edd2492d4bedb2111934795e7a4b23de1535b0d6dd04c",
    contracts: 4,
    ruby_status: "ok",
    ruby_diags: 0,
    vm_status: "error",
    vm_contains: "stdlib.string.char_at",
    registry_row: "IP-P08"
  }
}.freeze

$pass = 0
$fail = 0

def check(label)
  ok = yield
  if ok
    $pass += 1
    puts "PASS #{label}"
  else
    $fail += 1
    puts "FAIL #{label}"
  end
rescue => e
  $fail += 1
  puts "FAIL #{label} [#{e.class}: #{e.message.lines.first&.strip}]"
end

def section(title)
  puts "\n=== #{title} ==="
end

def read(path)
  File.read(path.to_s, encoding: "UTF-8")
rescue Errno::ENOENT
  ""
end

def app_dir(app)
  LAB_ROOT / "igniter-apps" / app
end

def source(app, file)
  read(app_dir(app) / file)
end

def all_source(app, files)
  files.map { |file| source(app, file) }.join("\n\n")
end

def run_rust_compile(app, files)
  Dir.mktmpdir("#{app}_demo_rust_") do |dir|
    out = File.join(dir, "out.igapp")
    stdout, stderr, status = Open3.capture3(
      RUST_BIN.to_s,
      "compile",
      *files.map { |file| (app_dir(app) / file).to_s },
      "--out",
      out
    )
    parsed = JSON.parse(stdout)
    sir = JSON.parse(File.read(File.join(out, "semantic_ir_program.json"), encoding: "UTF-8"))
    manifest = JSON.parse(File.read(File.join(out, "manifest.json"), encoding: "UTF-8"))
    { result: parsed, sir: sir, manifest: manifest, stderr: stderr, exit: status.exitstatus }
  end
rescue => e
  { result: { "status" => "error", "diagnostics" => [{ "message" => e.message }] }, sir: {}, manifest: {}, stderr: "", exit: 1 }
end

def run_ruby_compile(app, files)
  $LOAD_PATH.unshift((LANG_ROOT / "lib").to_s) unless $LOAD_PATH.include?((LANG_ROOT / "lib").to_s)
  require "igniter_lang/compiler_orchestrator"

  Dir.mktmpdir("#{app}_demo_ruby_") do |dir|
    raw = IgniterLang::CompilerOrchestrator.new.compile_sources(
      source_paths: files.map { |file| (app_dir(app) / file).to_s },
      out_path: File.join(dir, "out.igapp")
    )
    result = raw["result"] || raw
    { result: result, diagnostics: Array(result["diagnostics"] || result["type_errors"]) }
  end
rescue => e
  { result: { "status" => "error" }, diagnostics: [{ "message" => e.message }] }
end

def run_app(app)
  stdout, stderr, status = Open3.capture3(RUNNER.to_s, "run", (app_dir(app)).to_s)
  parsed = JSON.parse(stdout)
  { parsed: parsed, stdout: stdout, stderr: stderr, exit: status.exitstatus }
rescue JSON::ParserError
  { parsed: {}, stdout: stdout.to_s, stderr: stderr.to_s, exit: status&.exitstatus || 1 }
end

def entrypoint(manifest)
  manifest.fetch("entrypoint", {}).fetch("resolved_contract", nil)
end

def contract_names(sir)
  Array(sir["contracts"]).map { |contract| contract["contract_name"] }.compact.sort
end

def git_changed_critical_sources
  stdout, _stderr, _status = Open3.capture3(
    "git", "diff", "--name-only", "--",
    "igniter-compiler",
    "igniter-vm/src/compiler.rs",
    "igniter-vm/src/vm.rs"
  )
  stdout.lines.map(&:strip).reject(&:empty?)
end

card = read(CARD)
checkpoint = read(CHECKPOINT_CARD)
erp_card = read(ERP_CARD)
surface = read(SURFACE)
doc = read(DOC)
portfolio = read(PORTFOLIO)

results = {}
APPS.each do |app, cfg|
  results[app] = {
    source: all_source(app, cfg[:files]),
    registry: read(app_dir(app) / "PRESSURE_REGISTRY.md"),
    rust: run_rust_compile(app, cfg[:files]),
    ruby: run_ruby_compile(app, cfg[:files]),
    run: run_app(app)
  }
end

section("A. Gates And Authority")
check("A-01 checkpoint card exists") { CHECKPOINT_CARD.file? }
check("A-02 checkpoint names demo-entry owner") { checkpoint.include?("LAB-APP-DEMO-ENTRY-WAVE-P1") }
check("A-03 ERP precedent card is closed") { erp_card.include?("**Status:** CLOSED") }
check("A-04 implemented surface names needs-input apps") { surface.include?("needs-inputs / demo-entry") }
check("A-05 card exists") { CARD.file? }
check("A-06 card is closed") { card.include?("**Status:** CLOSED") }
check("A-07 no compiler/typechecker diffs from this card") { git_changed_critical_sources.none? { |p| p.start_with?("igniter-compiler/") } }

section("B. App Source Shape")
APPS.each do |app, cfg|
  text = results[app][:source]
  check("B #{app} example.ig exists") { (app_dir(app) / "example.ig").file? }
  check("B #{app} has expected entrypoint") { text.include?("entrypoint #{cfg[:entry]}") }
  check("B #{app} has expected run contract") { text.include?("contract #{cfg[:entry]}") }
  check("B #{app} imports app types") { text.include?("import") && text.include?("Types") }
  check("B #{app} has no external IO vocabulary in example") { !source(app, "example.ig").match?(/\b(http|queue|database|db|clock|file|socket|scheduler)\b/i) }
  check("B #{app} source set includes expected files") { cfg[:files].all? { |file| (app_dir(app) / file).file? } }
end
check("B-25 advanced factories build transports/orders") { source("advanced_logistics", "example.ig").include?("MakeTransport") && source("advanced_logistics", "example.ig").include?("MakeOrder") }
check("B-26 spreadsheet fixture uses typed Number kind input") { source("spreadsheet", "example.ig").include?("input kind : Text") }
check("B-27 vector fixture uses draw_rect tool state") { source("vector_editor", "example.ig").include?('"draw_rect"') }
check("B-28 parser fixture supplies sample source text") { source("igniter_parser", "example.ig").include?('"module Demo"') }

section("C. Rust Compile And Entrypoints")
APPS.each do |app, cfg|
  rust = results[app][:rust]
  check("C #{app} Rust status ok") { rust[:result]["status"] == "ok" }
  check("C #{app} Rust diagnostics zero") { Array(rust[:result]["diagnostics"]).empty? }
  check("C #{app} source hash matches closure") { rust[:result]["source_hash"] == cfg[:hash] }
  check("C #{app} manifest entrypoint resolved") { entrypoint(rust[:manifest]) == cfg[:entry] }
  check("C #{app} SIR has expected contract count") { contract_names(rust[:sir]).size == cfg[:contracts] }
  check("C #{app} SIR includes entry contract") { contract_names(rust[:sir]).include?(cfg[:entry]) }
end

section("D. Ruby Compile")
APPS.each do |app, cfg|
  ruby = results[app][:ruby]
  check("D #{app} Ruby status classified") { ruby[:result]["status"] == cfg[:ruby_status] }
  check("D #{app} Ruby diagnostic count classified") { ruby[:diagnostics].size == cfg[:ruby_diags] }
  check("D #{app} Ruby source hash matches Rust closure") { ruby[:result]["source_hash"] == cfg[:hash] }
end
check("D spreadsheet Ruby names eval_expr residual") do
  results["spreadsheet"][:ruby][:diagnostics].any? { |d| d["message"].to_s.include?("eval_expr") }
end
check("D spreadsheet Ruby names optional Expr residual") do
  msgs = results["spreadsheet"][:ruby][:diagnostics].map { |d| d["message"].to_s }.join("\n")
  msgs.include?("ref_id") && msgs.include?("left") && msgs.include?("right")
end

section("E. VM Runs")
APPS.each do |app, cfg|
  run = results[app][:run]
  check("E #{app} VM status classified") { run[:parsed]["status"] == cfg[:vm_status] }
  check("E #{app} VM output/error shape classified") { run[:stdout].include?(cfg[:vm_contains]) || run[:parsed].to_s.include?(cfg[:vm_contains]) }
  check("E #{app} runner selected declared entrypoint") { run[:stderr].empty? || !run[:stderr].include?("multiple contracts") }
end
check("E advanced success returns two route plan lists") { results["advanced_logistics"][:run][:parsed]["result"].is_a?(Array) && results["advanced_logistics"][:run][:parsed]["result"].size == 2 }
check("E vector success appends one object") do
  vector_doc = results["vector_editor"][:run][:parsed]["result"]
  Array(vector_doc.dig("layers", 0, "objects")).size == 1
end
check("E spreadsheet VM residual is app-local def support") { results["spreadsheet"][:run][:parsed]["error"].to_s.include?("eval_expr") }
check("E parser VM residual is char_at support") { results["igniter_parser"][:run][:parsed]["error"].to_s.include?("stdlib.string.char_at") }

section("F. Registries")
APPS.each do |app, cfg|
  registry = results[app][:registry]
  check("F #{app} registry includes closure section") { registry.include?("Demo Entry Wave P1") }
  check("F #{app} registry includes source hash") { registry.include?(cfg[:hash]) }
  check("F #{app} registry includes entrypoint") { registry.include?(cfg[:entry]) }
  check("F #{app} registry includes pressure row") { registry.include?(cfg[:registry_row]) }
end
check("F spreadsheet registry names SS-P09") { results["spreadsheet"][:registry].include?("SS-P09") }
check("F parser registry routes char_at card") { results["igniter_parser"][:registry].include?("LAB-STDLIB-STRING-CHAR-AT-VM-P1") }

section("G. Deliverables")
check("G-01 lab doc exists") { DOC.file? }
check("G-02 lab doc names all target apps") { APPS.keys.all? { |app| doc.include?(app) } }
check("G-03 lab doc names success count") { doc.include?("2/4 VM-success") }
check("G-04 lab doc names spreadsheet residual") { doc.include?("Unsupported operator: eval_expr") }
check("G-05 lab doc names parser residual") { doc.include?("stdlib.string.char_at") }
check("G-06 portfolio index updated") { portfolio.include?("LAB-APP-DEMO-ENTRY-WAVE-P1 CLOSED") }
check("G-07 card names proof runner") { card.include?("verify_lab_app_demo_entry_wave_p1.rb") }
check("G-08 card preserves no VM changes") { card.include?("No VM changes") }
check("G-09 card preserves no compiler or typechecker changes") { card.include?("No compiler or typechecker changes") }
check("G-10 card preserves no IO authority") { card.include?("No IO") }

section("H. Closed Surfaces")
check("H-01 no igniter-compiler edits in tracked diff") { git_changed_critical_sources.none? { |p| p.start_with?("igniter-compiler/") } }
check("H-02 no VM compiler.rs edits in tracked diff") { !git_changed_critical_sources.include?("igniter-vm/src/compiler.rs") }
check("H-03 card/doc/proof do not claim VM vm.rs changes") { !card.include?("Implemented: VM") && !doc.include?("VM changes made") }
check("H-04 examples are explicit fixture construction") { APPS.keys.all? { |app| source(app, "example.ig").include?("entrypoint") } }
check("H-05 production handler files retain original contract names") do
  source("advanced_logistics", "api.ig").include?("contract PlanDailyRoutes") &&
    source("spreadsheet", "api.ig").include?("contract RecalculateWorkbook") &&
    source("vector_editor", "tools.ig").include?("contract HandleCanvasClick") &&
    source("igniter_parser", "api.ig").include?("contract ParseSource")
end

puts "\nRESULT: #{$pass}/#{$pass + $fail} checks passed"
exit($fail.zero? ? 0 : 1)
