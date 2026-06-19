#!/usr/bin/env ruby
# frozen_string_literal: true
#
# verify_import_stdlib_surface_p4.rb
# LANG-STDLIB-IMPORT-SURFACE-P4 — Rust lab parity proof
# =====================================================
# Proves that the Rust MultifileResolver now mirrors Ruby P3 for stdlib
# import validation:
#   - known stdlib module paths compile cleanly (map/filter/count/append/etc.)
#   - OOF-IMP2 for unknown stdlib module paths
#   - OOF-IMP3 for known module + unknown alias name (fold/sum/etc.)
#   - OOF-IMP6 for user source declaring module stdlib.*
#   - imports stripped before TC/SIR (existing behavior)
#   - no capability/package/runtime/profile authority
#   - all four app fixtures move past the stdlib import blocker
#
# Oracle: Ruby P3 behavior + current stdlib-inventory.json (append now live)
#
# Sections:
#   A  Regression            (12)  — user module OOF-IMP1..5/DECL unchanged
#   B  Stdlib happy path     (10)  — known modules/names compile ok
#   C  OOF-IMP2 + OOF-IMP6  (7)   — unknown module; shadow guard
#   D  OOF-IMP3              (8)   — known module, unknown alias name
#   E  Authority closed      (6)   — no capability/package/profile/runtime fields
#   F  App fixtures          (9)   — AL/VE/AP/DT all move past stdlib blocker
#   G  Source text guards    (5)   — resolver text defines OOF-IMP2/3/6; table fn present
#
# Total: 57 checks

require "digest"
require "fileutils"
require "json"
require "open3"
require "pathname"
require "set"
require "tmpdir"

SCRIPT_DIR       = Pathname.new(__FILE__).realpath.dirname
LAB_ROOT         = SCRIPT_DIR.parent
WORKSPACE_ROOT   = LAB_ROOT.parent
COMPILER_BIN     = SCRIPT_DIR / "target" / "release" / "igniter_compiler"
MULTIFILE_RS     = SCRIPT_DIR / "src" / "multifile.rs"
APPS_DIR         = LAB_ROOT / "igniter-apps"
STDLIB_INVENTORY = WORKSPACE_ROOT / "igniter-lang" / "docs" / "spec" / "stdlib-inventory.json"

abort "Compiler binary not found: #{COMPILER_BIN}\nRun: cargo build --release" unless COMPILER_BIN.exist?
abort "multifile.rs not found: #{MULTIFILE_RS}" unless MULTIFILE_RS.exist?
abort "stdlib-inventory.json not found: #{STDLIB_INVENTORY}" unless STDLIB_INVENTORY.exist?

# ---------------------------------------------------------------------------
# Harness
# ---------------------------------------------------------------------------

CHECKS    = []
RS_SRC    = MULTIFILE_RS.read.encode("UTF-8", invalid: :replace, undef: :replace)
INVENTORY = JSON.parse(STDLIB_INVENTORY.read(encoding: "UTF-8"))

def check(label)
  pass = false
  detail = nil
  begin
    pass = yield == true
  rescue => e
    detail = "#{e.class}: #{e.message.lines.first&.strip}"
  end
  CHECKS << { label: label, pass: pass, detail: detail }
  puts "#{pass ? "PASS" : "FAIL"} #{label}"
  puts "     #{detail}" if detail && !pass
end

def section(name)
  puts "\n[#{name}]"
end

# ---------------------------------------------------------------------------
# Compile helpers
# ---------------------------------------------------------------------------

def rust_compile_multifile(files_hash)
  Dir.mktmpdir("p4_") do |dir|
    paths = files_hash.map do |filename, src|
      path = File.join(dir, filename)
      File.write(path, src.strip + "\n")
      path
    end
    out = File.join(dir, "out.igapp")
    stdout, _stderr, _status = Open3.capture3(COMPILER_BIN.to_s, "compile", *paths, "--out", out)
    result = JSON.parse(stdout.force_encoding("UTF-8")) rescue {}
    sir_path = File.join(out, "semantic_ir_program.json")
    sir = File.exist?(sir_path) ? JSON.parse(File.read(sir_path, encoding: "UTF-8")) : {}
    {
      status:  result["status"] || "unknown",
      codes:   Array(result["diagnostics"]).map { |d| d["rule"] }.compact,
      diags:   Array(result["diagnostics"]),
      result:  result,
      sir:     sir
    }
  end
end

def rust_compile_app(app_name, filenames)
  paths = filenames.map { |f| (APPS_DIR / app_name / f).to_s }
  Dir.mktmpdir("p4_app_") do |dir|
    out = File.join(dir, "out.igapp")
    stdout, _stderr, _status = Open3.capture3(COMPILER_BIN.to_s, "compile", *paths, "--out", out)
    result = JSON.parse(stdout.force_encoding("UTF-8")) rescue {}
    sir_path = File.join(out, "semantic_ir_program.json")
    sir = File.exist?(sir_path) ? JSON.parse(File.read(sir_path, encoding: "UTF-8")) : {}
    {
      status:  result["status"] || "unknown",
      codes:   Array(result["diagnostics"]).map { |d| d["rule"] }.compact,
      diags:   Array(result["diagnostics"]),
      result:  result,
      sir:     sir
    }
  end
end

# ---------------------------------------------------------------------------
# Fixture helpers
# ---------------------------------------------------------------------------

def companion(suffix = "Companion")
  <<~IG
    module Test.#{suffix}
    pure contract CompanionWork {
      input value : Integer
      compute out = value + 1
      output out : Integer
    }
  IG
end

def stdlib_importing_module(module_name, import_line, contract_suffix = "Main")
  <<~IG
    module #{module_name}
    #{import_line}
    pure contract #{contract_suffix} {
      input value : Integer
      compute out = value + 1
      output out : Integer
    }
  IG
end

def simple_module(module_name, contract_name = "DoWork", type_name = "WorkItem")
  <<~IG
    module #{module_name}
    type #{type_name} {
      value: Integer
    }
    pure contract #{contract_name} {
      input value : Integer
      compute out = { value: value }
      output out : #{type_name}
    }
  IG
end

# ---------------------------------------------------------------------------
# Section A — Regression
# ---------------------------------------------------------------------------

section("A-REGRESSION")

begin
  reg_valid = rust_compile_multifile(
    "provider.ig" => simple_module("Reg.Provider", "BuildProvided", "ProvidedValue"),
    "consumer.ig" => <<~IG
      module Reg.Consumer
      import Reg.Provider.{ProvidedValue}
      pure contract UseProvided {
        input value : Integer
        compute out = value + 1
        output out : Integer
      }
    IG
  )
  reg_unknown = rust_compile_multifile(
    "provider.ig" => simple_module("Reg.Provider2", "Build2", "Val2"),
    "consumer.ig" => <<~IG
      module Reg.Consumer2
      import Reg.Missing
      pure contract Use2 {
        input value : Integer
        compute out = value + 1
        output out : Integer
      }
    IG
  )
  reg_selective = rust_compile_multifile(
    "provider.ig" => simple_module("Reg.Sel.Provider", "BuildSel", "SelVal"),
    "consumer.ig" => <<~IG
      module Reg.Sel.Consumer
      import Reg.Sel.Provider.{MissingName}
      pure contract UseSel {
        input value : Integer
        compute out = value + 1
        output out : Integer
      }
    IG
  )
  reg_cycle = rust_compile_multifile(
    "a.ig" => "module Reg.Cycle.A\nimport Reg.Cycle.B\npure contract BuildA {\n  input value : Integer\n  compute out = value + 1\n  output out : Integer\n}",
    "b.ig" => "module Reg.Cycle.B\nimport Reg.Cycle.A\npure contract BuildB {\n  input value : Integer\n  compute out = value + 2\n  output out : Integer\n}"
  )
  reg_dup_module = rust_compile_multifile(
    "a.ig" => simple_module("Reg.Dup.Module", "BuildA", "DupA"),
    "b.ig" => simple_module("Reg.Dup.Module", "BuildB", "DupB")
  )
  reg_dup_contract = rust_compile_multifile(
    "a.ig" => simple_module("Reg.Dup.CA", "SameContract", "TypeA"),
    "b.ig" => simple_module("Reg.Dup.CB", "SameContract", "TypeB")
  )
  reg_dup_type = rust_compile_multifile(
    "a.ig" => simple_module("Reg.Dup.TA", "ContractA", "SameType"),
    "b.ig" => simple_module("Reg.Dup.TB", "ContractB", "SameType")
  )

  check("A-01 two-file user module import compiles")  { reg_valid[:status] == "ok" }
  check("A-02 source_units present in result")        { reg_valid[:sir]["source_units"].is_a?(Array) }
  check("A-03 imports stripped from merged source (no import lines in SIR)")  do
    # imports are stripped from merged source before TC; SIR has no import field
    reg_valid[:sir]["imports"].nil? || reg_valid[:sir]["imports"] == []
  end
  check("A-04 unknown user module import → OOF-IMP2") { reg_unknown[:codes].include?("OOF-IMP2") }
  check("A-05 unknown user module OOF-IMP2 carries source_path") do
    reg_unknown[:diags].find { |d| d["rule"] == "OOF-IMP2" }&.key?("source_path")
  end
  check("A-06 unknown user module OOF-IMP2 carries import_path") do
    reg_unknown[:diags].find { |d| d["rule"] == "OOF-IMP2" }&.key?("import_path")
  end
  check("A-07 missing selective name → OOF-IMP3")     { reg_selective[:codes].include?("OOF-IMP3") }
  check("A-08 selective OOF-IMP3 carries missing_name") do
    reg_selective[:diags].find { |d| d["rule"] == "OOF-IMP3" }&.key?("missing_name")
  end
  check("A-09 circular import → OOF-IMP1")            { reg_cycle[:codes].include?("OOF-IMP1") }
  check("A-10 duplicate module → OOF-IMP4")           { reg_dup_module[:codes].include?("OOF-IMP4") }
  check("A-11 duplicate contract → OOF-DECL-DUP-CONTRACT") do
    reg_dup_contract[:codes].include?("OOF-DECL-DUP-CONTRACT")
  end
  check("A-12 duplicate type → OOF-DECL-DUP-TYPE") do
    reg_dup_type[:codes].include?("OOF-DECL-DUP-TYPE")
  end
end

# ---------------------------------------------------------------------------
# Section B — Stdlib happy path
# ---------------------------------------------------------------------------

section("B-STDLIB-HAPPY")

begin
  b01 = rust_compile_multifile("main.ig" => stdlib_importing_module("B01", "import stdlib.collection.{ map }"), "c.ig" => companion("B01"))
  b02 = rust_compile_multifile("main.ig" => stdlib_importing_module("B02", "import stdlib.collection.{ filter }"), "c.ig" => companion("B02"))
  b03 = rust_compile_multifile("main.ig" => stdlib_importing_module("B03", "import stdlib.collection.{ count }"), "c.ig" => companion("B03"))
  b04 = rust_compile_multifile("main.ig" => stdlib_importing_module("B04", "import stdlib.collection.{ append }"), "c.ig" => companion("B04"))
  b05 = rust_compile_multifile("main.ig" => stdlib_importing_module("B05", "import stdlib.collection.{ map, filter, count, append }"), "c.ig" => companion("B05"))
  b06 = rust_compile_multifile("main.ig" => stdlib_importing_module("B06", "import stdlib.text.{ trim }"), "c.ig" => companion("B06"))
  b07 = rust_compile_multifile("main.ig" => stdlib_importing_module("B07", "import stdlib.text.{ contains, split }"), "c.ig" => companion("B07"))
  b08 = rust_compile_multifile("main.ig" => stdlib_importing_module("B08", "import stdlib.map.{ map_get }"), "c.ig" => companion("B08"))
  b09 = rust_compile_multifile("main.ig" => stdlib_importing_module("B09", "import stdlib.option.{ or_else }"), "c.ig" => companion("B09"))
  b10 = rust_compile_multifile(
    "main.ig" => "module B10\nimport stdlib.collection.{ map, filter }\nimport stdlib.text.{ trim }\npure contract B10 {\n  input v : Integer\n  compute out = v + 1\n  output out : Integer\n}",
    "c.ig" => companion("B10")
  )

  check("B-01 import stdlib.collection.{ map } compiles ok")             { b01[:status] == "ok" }
  check("B-02 import stdlib.collection.{ filter } compiles ok")          { b02[:status] == "ok" }
  check("B-03 import stdlib.collection.{ count } compiles ok")           { b03[:status] == "ok" }
  check("B-04 import stdlib.collection.{ append } compiles ok (inventory current)") { b04[:status] == "ok" }
  check("B-05 import stdlib.collection.{ map, filter, count, append } ok") { b05[:status] == "ok" }
  check("B-06 import stdlib.text.{ trim } compiles ok")                  { b06[:status] == "ok" }
  check("B-07 import stdlib.text.{ contains, split } compiles ok")       { b07[:status] == "ok" }
  check("B-08 import stdlib.map.{ map_get } compiles ok")                { b08[:status] == "ok" }
  check("B-09 import stdlib.option.{ or_else } compiles ok")             { b09[:status] == "ok" }
  check("B-10 two stdlib imports in one file compile ok")                 { b10[:status] == "ok" }
end

# ---------------------------------------------------------------------------
# Section C — OOF-IMP2 + OOF-IMP6
# ---------------------------------------------------------------------------

section("C-OOF-IMP2-IMP6")

begin
  c_bogus  = rust_compile_multifile("main.ig" => stdlib_importing_module("C.Bogus",  "import stdlib.bogus.{ foo }"),  "c.ig" => companion("CBogus"))
  c_crypto = rust_compile_multifile("main.ig" => stdlib_importing_module("C.Crypto", "import stdlib.crypto.{ hash }"), "c.ig" => companion("CCrypto"))
  c_imp6_col  = rust_compile_multifile("main.ig" => simple_module("stdlib.collection", "Shadow", "ShadowType"), "c.ig" => companion("CImp6"))
  c_imp6_text = rust_compile_multifile("main.ig" => simple_module("stdlib.text", "TextShadow", "ShadowText"), "c.ig" => companion("CImp6b"))

  check("C-01 import stdlib.bogus.{ foo } → OOF-IMP2")       { c_bogus[:codes].include?("OOF-IMP2") }
  check("C-02 import stdlib.crypto.{ hash } → OOF-IMP2")     { c_crypto[:codes].include?("OOF-IMP2") }
  check("C-03 stdlib OOF-IMP2 carries source_path + import_path") do
    d = c_bogus[:diags].find { |x| x["rule"] == "OOF-IMP2" } || {}
    d.key?("source_path") && d.key?("import_path")
  end
  check("C-04 stdlib OOF-IMP2 message mentions 'stdlib'") do
    d = c_bogus[:diags].find { |x| x["rule"] == "OOF-IMP2" } || {}
    d["message"].to_s.include?("stdlib")
  end
  check("C-05 module stdlib.collection → OOF-IMP6")       { c_imp6_col[:codes].include?("OOF-IMP6") }
  check("C-06 module stdlib.text → OOF-IMP6")             { c_imp6_text[:codes].include?("OOF-IMP6") }
  check("C-07 OOF-IMP6 carries source_path + module_path") do
    d = c_imp6_col[:diags].find { |x| x["rule"] == "OOF-IMP6" } || {}
    d.key?("source_path") && d.key?("module_path")
  end
end

# ---------------------------------------------------------------------------
# Section D — OOF-IMP3
# ---------------------------------------------------------------------------

section("D-OOF-IMP3")

begin
  d_fold     = rust_compile_multifile("main.ig" => stdlib_importing_module("D.Fold",  "import stdlib.collection.{ fold }"),  "c.ig" => companion("DFold"))
  d_sum      = rust_compile_multifile("main.ig" => stdlib_importing_module("D.Sum",   "import stdlib.collection.{ sum }"),   "c.ig" => companion("DSum"))
  d_bool     = rust_compile_multifile("main.ig" => stdlib_importing_module("D.Bool",  "import stdlib.bool.{ logical_not }"), "c.ig" => companion("DBool"))
  d_opt_some = rust_compile_multifile("main.ig" => stdlib_importing_module("D.Opt",   "import stdlib.option.{ some }"),      "c.ig" => companion("DOpt"))
  d_int_add  = rust_compile_multifile("main.ig" => stdlib_importing_module("D.Int",   "import stdlib.integer.{ add }"),      "c.ig" => companion("DInt"))
  d_mixed    = rust_compile_multifile("main.ig" => stdlib_importing_module("D.Mixed", "import stdlib.collection.{ fold, map }"), "c.ig" => companion("DMixed"))
  d_multi    = rust_compile_multifile("main.ig" => stdlib_importing_module("D.Multi", "import stdlib.collection.{ fold, sum }"), "c.ig" => companion("DMulti"))

  check("D-01 import stdlib.collection.{ fold } → OOF-IMP3")  { d_fold[:codes].include?("OOF-IMP3") }
  check("D-02 import stdlib.collection.{ sum } → OOF-IMP3")   { d_sum[:codes].include?("OOF-IMP3") }
  check("D-03 import stdlib.bool.{ logical_not } → OOF-IMP3 (bool module known, empty alias set)") { d_bool[:codes].include?("OOF-IMP3") }
  check("D-04 import stdlib.option.{ some } → OOF-IMP3")      { d_opt_some[:codes].include?("OOF-IMP3") }
  check("D-05 import stdlib.integer.{ add } → OOF-IMP3 (integer module known, empty alias set)") { d_int_add[:codes].include?("OOF-IMP3") }
  check("D-06 import stdlib.collection.{ fold, map } → OOF-IMP3 for fold only") do
    imp3s = d_mixed[:diags].select { |d2| d2["rule"] == "OOF-IMP3" }
    imp3s.length == 1 && imp3s.first["missing_name"] == "fold"
  end
  check("D-07 stdlib OOF-IMP3 carries source_path + module_path + import_path + missing_name") do
    d = d_fold[:diags].find { |x| x["rule"] == "OOF-IMP3" } || {}
    %w[source_path module_path import_path missing_name].all? { |k| d.key?(k) }
  end
  check("D-08 import stdlib.collection.{ fold, sum } → two OOF-IMP3 diagnostics") do
    d_multi[:diags].count { |d2| d2["rule"] == "OOF-IMP3" } == 2
  end
end

# ---------------------------------------------------------------------------
# Section E — Authority closed
# ---------------------------------------------------------------------------

section("E-AUTHORITY")

begin
  e_import = rust_compile_multifile(
    "main.ig" => stdlib_importing_module("E.WithImport", "import stdlib.collection.{ map }"),
    "c.ig" => companion("EWithImport")
  )
  e_no_import = rust_compile_multifile(
    "main.ig" => stdlib_importing_module("E.NoImport", ""),
    "c.ig" => companion("ENoImport")
  )

  e_json = e_import[:result].to_json
  check("E-01 manifest with stdlib import has no capability_import")  { !e_json.include?("capability_import") }
  check("E-02 manifest with stdlib import has no package_trust")      { !e_json.include?("package_trust") }
  check("E-03 manifest with stdlib import has no runtime_loader")     { !e_json.include?("runtime_loader") }
  check("E-04 manifest has no profile_binding from stdlib import")    { !e_json.include?("profile_binding") }
  check("E-05 contract count identical with vs without stdlib import") do
    a = Array(e_import[:result]["contracts"]).length
    b = Array(e_no_import[:result]["contracts"]).length
    a == b && a > 0
  end
  check("E-06 stdlib source not in source_units") do
    units = Array(e_import[:sir]["source_units"])
    units.none? { |u| u["module"].to_s.start_with?("stdlib.") }
  end
end

# ---------------------------------------------------------------------------
# Section F — App fixtures
# ---------------------------------------------------------------------------

section("F-APP-FIXTURES")

begin
  al = rust_compile_app("advanced_logistics", %w[api.ig router.ig spatial.ig types.ig])
  ve = rust_compile_app("vector_editor",      %w[document.ig tools.ig transform.ig types.ig])
  ap = rust_compile_app("arch_patterns",      %w[event_sourcing.ig example.ig pipeline.ig state_machine.ig types.ig])
  dt = rust_compile_app("decision_tree",      %w[builder.ig evaluator.ig example.ig types.ig])

  # advanced_logistics: map + filter both in inventory → fully compiles
  check("F-01 advanced_logistics: no OOF-IMP2 for stdlib.collection") do
    al[:codes].none? { |r| r == "OOF-IMP2" }
  end
  check("F-02 advanced_logistics: no stdlib-related OOF-IMP3") do
    al[:diags].none? { |d| d["rule"] == "OOF-IMP3" && d["import_path"].to_s.start_with?("stdlib.") }
  end

  # vector_editor: append + map both in inventory → moved past import blocker
  check("F-03 vector_editor: no OOF-IMP2 for stdlib.collection") do
    ve[:codes].none? { |r| r == "OOF-IMP2" }
  end
  check("F-04 vector_editor: no OOF-IMP3 for append (append now in inventory)") do
    ve[:diags].none? { |d| d["rule"] == "OOF-IMP3" && d["missing_name"] == "append" }
  end

  # arch_patterns: append + filter both in inventory → moved past import blocker
  check("F-05 arch_patterns: no OOF-IMP2 for stdlib.collection") do
    ap[:codes].none? { |r| r == "OOF-IMP2" }
  end
  check("F-06 arch_patterns: no OOF-IMP3 for append") do
    ap[:diags].none? { |d| d["rule"] == "OOF-IMP3" && d["missing_name"] == "append" }
  end

  # decision_tree: moves past stdlib import blocker (Rust parser does not treat label as keyword)
  check("F-07 decision_tree: no OOF-IMP2 for stdlib.collection") do
    dt[:codes].none? { |r| r == "OOF-IMP2" }
  end
  check("F-08 decision_tree: no OOF-IMP3 for append") do
    dt[:diags].none? { |d| d["rule"] == "OOF-IMP3" && d["missing_name"] == "append" }
  end

  # cross-app: no app has OOF-IMP2 for a known stdlib module
  check("F-09 no app emits OOF-IMP2 for a known stdlib module path") do
    known_modules = begin
      table = {}
      INVENTORY.fetch("entries", []).each do |e|
        canon = e["canonical_name"].to_s
        parts = canon.split(".")
        next unless parts.length >= 3 && parts[0] == "stdlib"
        table[parts[0...-1].join(".")] = true
      end
      table
    end
    [al, ve, ap, dt].all? do |c|
      c[:diags].none? { |d| d["rule"] == "OOF-IMP2" && known_modules.key?(d["import_path"].to_s) }
    end
  end
end

# ---------------------------------------------------------------------------
# Section G — Source text guards
# ---------------------------------------------------------------------------

section("G-SOURCE-TEXT")

check("G-01 multifile.rs defines OOF-IMP2 for stdlib path")    { RS_SRC.include?("OOF-IMP2") && RS_SRC.include?("starts_with(\"stdlib.\")") }
check("G-02 multifile.rs defines OOF-IMP3 for stdlib name")    { RS_SRC.include?("OOF-IMP3") }
check("G-03 multifile.rs defines OOF-IMP6 shadow guard")       { RS_SRC.include?("OOF-IMP6") }
check("G-04 stdlib_module_table function present in source")    { RS_SRC.include?("fn stdlib_module_table()") }
check("G-05 include_str! embeds inventory at compile time")     { RS_SRC.include?("include_str!") && RS_SRC.include?("stdlib-inventory.json") }

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

pass_count = CHECKS.count { |c| c[:pass] }
fail_count = CHECKS.count { |c| !c[:pass] }
puts "\nLANG-STDLIB-IMPORT-SURFACE-P4 #{fail_count.zero? ? "PASS" : "FAIL"} (#{pass_count}/#{CHECKS.length})"
unless fail_count.zero?
  CHECKS.reject { |c| c[:pass] }.each do |c|
    puts "  FAIL: #{c[:label]}"
    puts "        #{c[:detail]}" if c[:detail]
  end
end
exit(fail_count.zero? ? 0 : 1)
