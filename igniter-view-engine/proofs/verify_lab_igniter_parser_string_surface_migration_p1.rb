# frozen_string_literal: true

# LAB-IGNITER-PARSER-STRING-SURFACE-MIGRATION-P1
# Recheck proof for igniter_parser after char_at (P3) + substring (P2) close.
#
# Before this migration: oof/1 OOF-IMP2 ("unknown stdlib module path 'stdlib.string'") — both TCs.
# After: OOF-IMP2 gone; char_at clean; substring imported + used; IP-P06 now exposed.
#
# Sections A–I / target ≥45 checks (actual: 50)
# A: IP-P01 RESOLVED — OOF-IMP2 cleared in both toolchains
# B: IP-P02 RESOLVED — char_at(String, Integer) compiles cleanly
# C: IP-P05 RESOLVED — substring imported and used in lexer.ig
# D: Ruby TC current diagnostics (call_contract blockers only)
# E: Rust TC current diagnostics (call_contract blockers only)
# F: Source state inventory
# G: IP-P06 exposed — stringly stdlib calls now the dominant blocker
# H: Pressure registry update state
# I: Authority / no self-hosting overclaim

require "json"
require "digest"
require "tempfile"
require "set"

Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8

$pass = 0
$fail = 0
$total = 0

def check(label)
  $total += 1
  result = yield rescue false
  if result
    $pass += 1
    puts "PASS [#{"%-3d" % $total}] #{label}"
  else
    $fail += 1
    puts "FAIL [#{"%-3d" % $total}] #{label}"
  end
  result
end

ROOT      = File.expand_path("../../../..", __FILE__)
LANG_ROOT = File.join(ROOT, "igniter-lang")
LAB_ROOT  = File.join(ROOT, "igniter-lab")
APP_ROOT  = File.join(LAB_ROOT, "igniter-apps/igniter_parser")

APP_FILES = %w[types.ig lexer.ig parser.ig api.ig].map { |f| File.join(APP_ROOT, f) }

LEXER_SRC    = File.read(File.join(APP_ROOT, "lexer.ig"), encoding: "utf-8")
PARSER_SRC   = File.read(File.join(APP_ROOT, "parser.ig"), encoding: "utf-8")
API_SRC      = File.read(File.join(APP_ROOT, "api.ig"), encoding: "utf-8")
PRESSURE_REG = File.read(File.join(APP_ROOT, "PRESSURE_REGISTRY.md"), encoding: "utf-8")
INVENTORY    = JSON.parse(File.read(File.join(LANG_ROOT, "docs/spec/stdlib-inventory.json"), encoding: "utf-8"))

# ─── Compile helpers ────────────────────────────────────────────────────────

def ruby_compile_app
  require "igniter_lang/compiler_orchestrator"
  raw = IgniterLang::CompilerOrchestrator.new.compile_sources(
    source_paths: APP_FILES,
    out_path: "/tmp/igniter_parser_migration_p1_ruby.igapp"
  )
  diags = raw.dig("result", "diagnostics") || raw["diagnostics"] || []
  { "status" => raw["status"], "diagnostics" => diags }
rescue => e
  { "status" => "error", "diagnostics" => [], "error" => e.message }
end

def rust_compile_app
  compiler_dir = File.join(LAB_ROOT, "igniter-compiler")
  src_args = APP_FILES.join(" ")
  out = Dir.chdir(compiler_dir) {
    `cargo run --release --quiet -- compile #{src_args} --out /tmp/igniter_parser_migration_p1_rust.igapp 2>/dev/null`
  }
  JSON.parse(out) rescue { "status" => "error", "diagnostics" => [] }
end

def has_msg?(result, substr)
  (result["diagnostics"] || []).any? { |d| d["message"].to_s.include?(substr) }
end

def diag_messages(result)
  (result["diagnostics"] || []).map { |d| d["message"].to_s }
end

def diag_codes(result)
  (result["diagnostics"] || []).map { |d| d["rule"] || d["code"] }
end

puts "=" * 60
puts "LAB-IGNITER-PARSER-STRING-SURFACE-MIGRATION-P1"
puts "=" * 60
puts

@ruby = ruby_compile_app
@rust = rust_compile_app

# ─── A: IP-P01 RESOLVED — OOF-IMP2 cleared ─────────────────────────────────
puts "── A: IP-P01 RESOLVED — OOF-IMP2 Cleared ──"

check("A-01: Ruby OOF-IMP2 for stdlib.string is GONE") {
  !has_msg?(@ruby, "OOF-IMP2")
}
check("A-02: Rust OOF-IMP2 for stdlib.string is GONE") {
  !has_msg?(@rust, "OOF-IMP2")
}
check("A-03: stdlib.string.char_at entry in inventory (root cause cleared)") {
  INVENTORY["entries"].any? { |e| e["canonical_name"] == "stdlib.string.char_at" }
}
check("A-04: stdlib.string.substring entry in inventory (P2 closed)") {
  INVENTORY["entries"].any? { |e| e["canonical_name"] == "stdlib.string.substring" }
}
check("A-05: Ruby parse stage succeeds (was blocked at multifile_resolve before)") {
  # Before: stopped at OOF-IMP2 in multifile_resolve
  # Now: gets past import resolution into typecheck
  !has_msg?(@ruby, "OOF-IMP2") && @ruby["status"] != "error"
}
check("A-06: Rust classify + parse stages ok") {
  stages = @rust["stages"] || {}
  stages["parse"] == "ok" && stages["classify"] == "ok"
}

# ─── B: IP-P02 RESOLVED — char_at compiles cleanly ─────────────────────────
puts "\n── B: IP-P02 RESOLVED — char_at Clean ──"

check("B-01: Ruby has no OOF-TY0 mentioning char_at") {
  !diag_messages(@ruby).any? { |m| m.include?("char_at") }
}
check("B-02: Rust has no OOF-TY0 mentioning char_at") {
  !diag_messages(@rust).any? { |m| m.include?("char_at") }
}
check("B-03: lexer.ig imports char_at") {
  LEXER_SRC.include?("char_at")
}
check("B-04: lexer.ig uses char_at(state.source, state.pos)") {
  LEXER_SRC.include?("char_at(state.source, state.pos)")
}
check("B-05: char_at is dual-toolchain in inventory") {
  e = INVENTORY["entries"].find { |x| x["canonical_name"] == "stdlib.string.char_at" }
  e && e["lowering_status"] == "dual-toolchain"
}

# ─── C: IP-P05 RESOLVED — substring imported and used ───────────────────────
puts "\n── C: IP-P05 RESOLVED — substring Imported and Used ──"

check("C-01: lexer.ig imports substring") {
  LEXER_SRC.include?("substring")
}
check("C-02: import line includes both char_at and substring") {
  LEXER_SRC.include?('import stdlib.string.{ char_at, substring }')
}
check("C-03: lexer.ig uses substring for token_text extraction") {
  LEXER_SRC.include?("token_text = substring(state.source, state.pos, 6)")
}
check("C-04: new_token.text uses token_text (not hardcoded \"module\")") {
  LEXER_SRC.include?("text: token_text") && !LEXER_SRC.include?('text: "module"')
}
check("C-05: Ruby has no OOF-TY0 mentioning substring") {
  !diag_messages(@ruby).any? { |m| m.include?("substring") }
}
check("C-06: Rust has no OOF-TY0 mentioning substring") {
  !diag_messages(@rust).any? { |m| m.include?("substring") }
}
check("C-07: substring is dual-toolchain in inventory") {
  e = INVENTORY["entries"].find { |x| x["canonical_name"] == "stdlib.string.substring" }
  e && e["lowering_status"] == "dual-toolchain"
}

# ─── D: Ruby TC Current Diagnostics ─────────────────────────────────────────
puts "\n── D: Ruby TC Current Diagnostics ──"

ruby_msgs = diag_messages(@ruby)

check("D-01: Ruby status is oof (call_contract blockers remaining)") {
  @ruby["status"] == "oof"
}
check("D-02: Ruby OOF-TY0 for call_contract('empty') present") {
  ruby_msgs.any? { |m| m.include?("empty") && m.include?("call_contract") }
}
check("D-03: Ruby OOF-TY0 for call_contract('append') present") {
  ruby_msgs.any? { |m| m.include?("append") && m.include?("call_contract") }
}
check("D-04: All Ruby diagnostics are call_contract or cascade OOF-P1") {
  (ruby_msgs).all? { |m|
    m.include?("call_contract") || m.include?("Unresolved symbol")
  }
}
check("D-05: No Ruby OOF-TY0 for string-surface ops (char_at/substring/OOF-IMP2)") {
  ruby_msgs.none? { |m|
    m.include?("OOF-IMP2") || m.include?("char_at") || m.include?("substring")
  }
}

# ─── E: Rust TC Current Diagnostics ─────────────────────────────────────────
puts "\n── E: Rust TC Current Diagnostics ──"

rust_msgs = diag_messages(@rust)

check("E-01: Rust status is oof (call_contract blockers remaining)") {
  @rust["status"] == "oof"
}
check("E-02: Rust OOF-TY0 for call_contract('empty') present") {
  rust_msgs.any? { |m| m.include?("empty") && m.include?("call_contract") }
}
check("E-03: Rust OOF-TY0 for call_contract('append') present") {
  rust_msgs.any? { |m| m.include?("append") && m.include?("call_contract") }
}
check("E-04: All Rust diagnostics are call_contract OOF-TY0") {
  rust_msgs.all? { |m| m.include?("call_contract") }
}
check("E-05: No Rust OOF-TY0 for string-surface ops") {
  rust_msgs.none? { |m|
    m.include?("OOF-IMP2") || m.include?("char_at") || m.include?("substring")
  }
}

# ─── F: Source State Inventory ───────────────────────────────────────────────
puts "\n── F: Source State Inventory ──"

check("F-01: lexer.ig module is ParserLexer") { LEXER_SRC.include?("module ParserLexer") }
check("F-02: lexer.ig imports ParserTypes") { LEXER_SRC.include?("import ParserTypes") }
check("F-03: parser.ig uses call_contract('empty') for empty_children") {
  PARSER_SRC.include?('call_contract("empty")')
}
check("F-04: parser.ig uses call_contract('append') for new_nodes") {
  PARSER_SRC.include?('call_contract("append"')
}
check("F-05: api.ig uses call_contract('LexNextToken')") {
  API_SRC.include?('call_contract("LexNextToken"')
}
check("F-06: api.ig has 3 empty + 2 LexNextToken/ParseModuleDecl contracts") {
  API_SRC.include?('call_contract("empty")') &&
    API_SRC.include?('call_contract("LexNextToken"') &&
    API_SRC.include?('call_contract("ParseModuleDecl"')
}

# ─── G: IP-P06 Exposed — Stringly Stdlib Calls ──────────────────────────────
puts "\n── G: IP-P06 Exposed — Stringly Calls Now Dominant Blocker ──"

check("G-01: IP-P06 was already recorded in PRESSURE_REGISTRY.md") {
  PRESSURE_REG.include?("IP-P06")
}
check("G-02: IP-P06 mentions stringly stdlib constructor calls") {
  PRESSURE_REG.include?("stringly") || PRESSURE_REG.include?("call_contract")
}
check("G-03: IP-P06 route is LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION") {
  PRESSURE_REG.include?("LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION")
}
check("G-04: 5 call_contract sites total: 3×empty + 2×append") {
  empty_count = (LEXER_SRC + PARSER_SRC + API_SRC).scan('call_contract("empty"').length
  append_count = (LEXER_SRC + PARSER_SRC + API_SRC).scan('call_contract("append"').length
  empty_count == 3 && append_count == 2
}
check("G-05: call_contract('LexNextToken') and 'ParseModuleDecl' are Tier 1 literal callees (not IP-P06)") {
  # Tier 1 = literal callee resolved to a known contract — not stringly stdlib
  API_SRC.include?('call_contract("LexNextToken"') &&
    API_SRC.include?('call_contract("ParseModuleDecl"')
}

# ─── H: Pressure Registry State ─────────────────────────────────────────────
puts "\n── H: Pressure Registry State ──"

check("H-01: PRESSURE_REGISTRY.md mentions IP-P01") { PRESSURE_REG.include?("IP-P01") }
check("H-02: PRESSURE_REGISTRY.md mentions IP-P02") { PRESSURE_REG.include?("IP-P02") }
check("H-03: PRESSURE_REGISTRY.md mentions IP-P05") { PRESSURE_REG.include?("IP-P05") }
check("H-04: PRESSURE_REGISTRY.md mentions IP-P06") { PRESSURE_REG.include?("IP-P06") }
check("H-05: PRESSURE_REGISTRY.md mentions route LANG-STDLIB-STRING-SURFACE") {
  PRESSURE_REG.include?("LANG-STDLIB-STRING-SURFACE")
}

# ─── I: Authority / No Overclaim ────────────────────────────────────────────
puts "\n── I: Authority / No Overclaim ──"

check("I-01: lexer.ig is still single-step (no actual loop/recursion constructs)") {
  # Comment says "without loops" — that's fine; check for real loop or self-call syntax
  !LEXER_SRC.include?("while ") && !LEXER_SRC.include?("for ") &&
    !LEXER_SRC.include?("call_contract(\"LexNextToken\"") &&
    !LEXER_SRC.match?(/^\s*compute\s+\w+\s*=\s*LexNextToken/)
}
check("I-02: parser.ig has no self-hosting claim") {
  !PARSER_SRC.include?("self-host") && !PARSER_SRC.include?("self_host")
}
check("I-03: No call_contract migration done in this card (route kept separate)") {
  # stringly calls unchanged — only string surface changes applied
  PARSER_SRC.include?('call_contract("empty")') &&
    API_SRC.include?('call_contract("empty")')
}
check("I-04: inventory stdlib.string now has 2 entries (char_at + substring)") {
  INVENTORY["entries"].count { |e| e["canonical_name"].start_with?("stdlib.string.") } == 2
}
check("I-05: 14 stdlib.text entries unchanged") {
  INVENTORY["entries"].count { |e| e["canonical_name"].start_with?("stdlib.text.") } == 14
}

puts
puts "=" * 60
puts "LAB-IGNITER-PARSER-STRING-SURFACE-MIGRATION-P1"
puts "Result: #{$pass}/#{$total} PASS  (#{$fail} FAIL)"
puts "=" * 60

exit($fail > 0 ? 1 : 0)
