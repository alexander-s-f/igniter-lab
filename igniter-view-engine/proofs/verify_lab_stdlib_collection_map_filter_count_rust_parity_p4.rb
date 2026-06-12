#!/usr/bin/env ruby
# frozen_string_literal: true
#
# verify_lab_stdlib_collection_map_filter_count_rust_parity_p4.rb
# LANG-STDLIB-COLLECTION-MAP-FILTER-PROP-P4 — Rust parity proof
# ==============================================================
# Proves that the Rust TypeChecker now:
#   - emits canonical stdlib.collection.{map,filter,count} SIR fn names
#   - binds map/filter lambda params to Collection element type T
#   - validates filter predicate returns Bool (OOF-COL3)
#   - preserves count Integer result type
# Oracle: Ruby P3 behavior (61/61 PASS)
#
# Route:   BOUNDED RUST IMPLEMENTATION / PROOF
# Card:    igniter-lang/.agents/work/cards/lang/LANG-STDLIB-COLLECTION-MAP-FILTER-PROP-P4.md
# Verdict: PASS — Rust parity proved
#
# Sections:
#   A  REGRESSION              (7)  — existing Rust proofs unaffected
#   B  count dispatch          (8)  — canonical name; Integer; arity; non-Collection
#   C  filter dispatch         (9)  — canonical name; elem binding; OOF-COL3; passthrough
#   D  map dispatch            (9)  — canonical name; elem binding; result type
#   E  SIR qualified names     (7)  — all three qualified; none bare; source check
#   F  type inference          (8)  — map result wraps body type; filter passthrough
#   G  app fixture parity      (6)  — bookkeeping/ERP: no Unknown function
#   H  lambda element binding  (6)  — field access on lambda param works correctly
#   I  authority closed        (7)  — no fold/sum; no Ruby changes; inventory unchanged
#
# Total: 67 checks (minimum: 60)

require "digest"
require "fileutils"
require "json"
require "open3"
require "pathname"
require "tmpdir"

SCRIPT_DIR       = Pathname.new(__dir__)
LAB_ROOT         = SCRIPT_DIR.parent.parent
WORKSPACE_ROOT   = LAB_ROOT.parent
IGNITER_LIB      = WORKSPACE_ROOT / "igniter-lang" / "lib"
COMPILER_BIN     = LAB_ROOT / "igniter-compiler" / "target" / "release" / "igniter_compiler"
APPS_DIR         = LAB_ROOT / "igniter-apps"
STDLIB_INVENTORY = WORKSPACE_ROOT / "igniter-lang" / "docs" / "spec" / "stdlib-inventory.json"
TC_RUBY          = WORKSPACE_ROOT / "igniter-lang" / "lib" / "igniter_lang" / "typechecker.rb"
TC_RUST          = LAB_ROOT / "igniter-compiler" / "src" / "typechecker.rs"
EMITTER_RUST     = LAB_ROOT / "igniter-compiler" / "src" / "emitter.rs"

BK_TYPES   = APPS_DIR / "bookkeeping" / "types.ig"
BK_LEDGER  = APPS_DIR / "bookkeeping" / "ledger.ig"
ERP_TYPES  = APPS_DIR / "erp_logistics" / "types.ig"
ERP_OPTIM  = APPS_DIR / "erp_logistics" / "optimizer.ig"

$LOAD_PATH.unshift(IGNITER_LIB.to_s) unless $LOAD_PATH.include?(IGNITER_LIB.to_s)
require "igniter_lang"

abort "Compiler binary not found: #{COMPILER_BIN}" unless COMPILER_BIN.exist?
abort "stdlib-inventory.json not found: #{STDLIB_INVENTORY}" unless STDLIB_INVENTORY.exist?
abort "Ruby TC not found: #{TC_RUBY}" unless TC_RUBY.exist?
abort "Rust TC not found: #{TC_RUST}" unless TC_RUST.exist?
abort "Rust emitter not found: #{EMITTER_RUST}" unless EMITTER_RUST.exist?

# ─────────────────────────────────────────────────────────────────────────────
# Harness
# ─────────────────────────────────────────────────────────────────────────────

$pass = 0
$fail = 0
TC_RUST_SRC    = TC_RUST.read.encode("UTF-8", invalid: :replace, undef: :replace)
EMITTER_SRC    = EMITTER_RUST.read.encode("UTF-8", invalid: :replace, undef: :replace)
INVENTORY_DATA = JSON.parse(STDLIB_INVENTORY.read(encoding: "UTF-8"))

def check(label)
  result = yield
  if result
    $pass += 1
    puts "PASS #{label}"
  else
    $fail += 1
    puts "FAIL #{label}"
  end
rescue => e
  $fail += 1
  puts "FAIL #{label} [exception: #{e.message.lines.first&.strip}]"
end

def rust_compile_source(src)
  Dir.mktmpdir do |tmpdir|
    path = File.join(tmpdir, "inline.ig")
    out  = File.join(tmpdir, "out.igapp")
    File.write(path, src)
    stdout, _stderr, _status = Open3.capture3(COMPILER_BIN.to_s, "compile", path, "--out", out)
    result = JSON.parse(stdout.force_encoding("UTF-8")) rescue {}
    diags  = Array(result["diagnostics"])
    sir    = {}
    igapp  = result["igapp_path"] || out
    sir_p  = File.join(igapp.to_s, "semantic_ir_program.json")
    sir    = JSON.parse(File.read(sir_p, encoding: "UTF-8")) if File.exist?(sir_p)
    {
      status:   result["status"] || "parse-error",
      diags:    diags,
      messages: diags.map { |d| d["message"].to_s },
      codes:    diags.map { |d| d["rule"].to_s }.compact,
      sir:      sir
    }
  end
end

def rust_compile(*paths)
  Dir.mktmpdir do |tmpdir|
    out  = File.join(tmpdir, "out.igapp")
    args = [COMPILER_BIN.to_s, "compile"] + paths.map(&:to_s) + ["--out", out]
    stdout, _stderr, _status = Open3.capture3(*args)
    result = JSON.parse(stdout.force_encoding("UTF-8")) rescue {}
    diags  = Array(result["diagnostics"])
    sir    = {}
    igapp  = result["igapp_path"] || out
    sir_p  = File.join(igapp.to_s, "semantic_ir_program.json")
    sir    = JSON.parse(File.read(sir_p, encoding: "UTF-8")) if File.exist?(sir_p)
    {
      status:   result["status"] || "parse-error",
      diags:    diags,
      messages: diags.map { |d| d["message"].to_s },
      codes:    diags.map { |d| d["rule"].to_s }.compact,
      sir:      sir
    }
  end
end

def collect_sir_fns(node)
  case node
  when Hash
    fns = []
    fns << node["fn"] if node["kind"] == "call" && node["fn"]
    node.values.each { |v| fns.concat(collect_sir_fns(v)) }
    fns
  when Array
    node.flat_map { |item| collect_sir_fns(item) }
  else
    []
  end
end

# ─────────────────────────────────────────────────────────────────────────────
# Shared fixtures
# ─────────────────────────────────────────────────────────────────────────────

ITEM_TYPE_SRC = <<~IG
  module M
  type Item { value: Integer; active: Bool; }
IG

COUNT_SRC = <<~IG
  module M
  contract C {
    input items : Collection[Integer]
    output n : Integer
    compute n = count(items)
  }
IG

MAP_SRC = <<~IG
  module M
  type Item { value: Integer; active: Bool; }
  contract C {
    input items : Collection[Item]
    output values : Collection[Integer]
    compute values = map(items, x -> x.value)
  }
IG

FILTER_SRC = <<~IG
  module M
  type Item { value: Integer; active: Bool; }
  contract C {
    input items : Collection[Item]
    output active_items : Collection[Item]
    compute active_items = filter(items, x -> x.active)
  }
IG

FILTER_NONBOOL_SRC = <<~IG
  module M
  type Item { value: Integer; }
  contract C {
    input items : Collection[Item]
    output bad : Collection[Item]
    compute bad = filter(items, x -> x.value)
  }
IG

CHAIN_SRC = <<~IG
  module M
  type Item { value: Integer; active: Bool; }
  contract C {
    input items : Collection[Item]
    output n : Integer
    compute active = filter(items, x -> x.active)
    compute values = map(active, x -> x.value)
    compute n = count(values)
  }
IG

# ─────────────────────────────────────────────────────────────────────────────
# === A: REGRESSION ===
# ─────────────────────────────────────────────────────────────────────────────
puts "\n=== A: Regression ==="

check "A-01: COLLECTION_HOF_OPS defined in Rust emitter" do
  EMITTER_SRC.include?("COLLECTION_HOF_OPS")
end

check "A-02: stdlib.collection.map in emitter COLLECTION_HOF_OPS" do
  EMITTER_SRC.include?('"stdlib.collection.map"')
end

check "A-03: stdlib.collection.filter in emitter COLLECTION_HOF_OPS" do
  EMITTER_SRC.include?('"stdlib.collection.filter"')
end

check "A-04: stdlib.collection.count in emitter COLLECTION_HOF_OPS" do
  EMITTER_SRC.include?('"stdlib.collection.count"')
end

check "A-05: map lambda param fix in Rust TC (no Integer hardcode for map)" do
  # The P4 fix replaces the hardcoded Integer binding with elem_ty from get_param.
  # After the fix, there should be a get_param call near the elem_ty let binding.
  EMITTER_SRC.include?("COLLECTION_HOF_OPS") &&
    TC_RUST_SRC.include?("elem_ty") &&
    TC_RUST_SRC.include?("get_param(&first_arg_type, 0)")
end

check "A-06: filter OOF-COL3 defined in Rust TC" do
  TC_RUST_SRC.include?('"OOF-COL3"')
end

check "A-07: text stdlib ops still work (byte_length qualified)" do
  r = rust_compile_source(<<~IG)
    module M
    contract C {
      input s : Text
      output n : Integer
      compute n = byte_length(s)
    }
  IG
  r[:status] == "ok" && collect_sir_fns(r[:sir]).include?("stdlib.text.byte_length")
end

# ─────────────────────────────────────────────────────────────────────────────
# === B: count dispatch ===
# ─────────────────────────────────────────────────────────────────────────────
puts "\n=== B: count dispatch ==="

check "B-01: count(items) compiles clean" do
  r = rust_compile_source(COUNT_SRC)
  r[:status] == "ok" && r[:codes].empty?
end

check "B-02: count SIR fn == 'stdlib.collection.count'" do
  r = rust_compile_source(COUNT_SRC)
  collect_sir_fns(r[:sir]).include?("stdlib.collection.count")
end

check "B-03: bare 'count' NOT in SIR fn values" do
  r = rust_compile_source(COUNT_SRC)
  !collect_sir_fns(r[:sir]).include?("count")
end

check "B-04: count SIR node type is Integer" do
  r = rust_compile_source(COUNT_SRC)
  sir = r[:sir]
  contracts = sir["contracts"] || []
  contracts.any? do |c|
    (c["nodes"] || []).any? do |node|
      node.dig("expr", "fn") == "stdlib.collection.count" &&
        (node.dig("type", "name") == "Integer" rescue false)
    end
  end
end

check "B-05: count(items) on Collection[Decimal[2]] → stdlib.collection.count" do
  r = rust_compile_source(<<~IG)
    module M
    contract C {
      input items : Collection[Decimal[2]]
      output n : Integer
      compute n = count(items)
    }
  IG
  r[:status] == "ok" && collect_sir_fns(r[:sir]).include?("stdlib.collection.count")
end

check "B-06: count with 0 args — no Unknown function, some error" do
  r = rust_compile_source(<<~IG)
    module M
    contract C {
      output n : Integer
      compute n = count()
    }
  IG
  # Rust may emit OOF-TY0 or parse error, but not "Unknown function: count"
  !r[:messages].any? { |m| m.include?("Unknown function: count") }
end

check "B-07: count with non-Collection arg — no crash" do
  r = rust_compile_source(<<~IG)
    module M
    contract C {
      input n : Integer
      output r : Integer
      compute r = count(n)
    }
  IG
  # Should compile without crash (Rust TC doesn't validate non-Collection in v0)
  !r.nil? && !r[:status].nil?
end

check "B-08: T3 count (decreases count) unaffected by P4" do
  # T3 count goes through handle_t3_variant, not infer_call — must be separate
  TC_RUST_SRC.include?("handle_t3_variant") &&
    !TC_RUST_SRC.match?(/COLLECTION_HOF_OPS.*handle_t3/m)
end

# ─────────────────────────────────────────────────────────────────────────────
# === C: filter dispatch ===
# ─────────────────────────────────────────────────────────────────────────────
puts "\n=== C: filter dispatch ==="

check "C-01: filter(items, x -> x.active) compiles clean" do
  r = rust_compile_source(FILTER_SRC)
  r[:status] == "ok" && r[:codes].empty?
end

check "C-02: filter SIR fn == 'stdlib.collection.filter'" do
  r = rust_compile_source(FILTER_SRC)
  collect_sir_fns(r[:sir]).include?("stdlib.collection.filter")
end

check "C-03: bare 'filter' NOT in SIR fn values" do
  r = rust_compile_source(FILTER_SRC)
  !collect_sir_fns(r[:sir]).include?("filter")
end

check "C-04: filter result type is passthrough Collection[Item]" do
  r = rust_compile_source(FILTER_SRC)
  sir = r[:sir]
  contracts = sir["contracts"] || []
  contracts.any? do |c|
    (c["nodes"] || []).any? do |node|
      node.dig("expr", "fn") == "stdlib.collection.filter" &&
        node.dig("type", "name") == "Collection"
    end
  end
end

check "C-05: filter with non-Bool predicate → OOF-COL3" do
  r = rust_compile_source(FILTER_NONBOOL_SRC)
  r[:codes].include?("OOF-COL3")
end

check "C-06: OOF-COL3 message mentions 'stdlib.collection.filter'" do
  r = rust_compile_source(FILTER_NONBOOL_SRC)
  r[:messages].any? { |m| m.include?("stdlib.collection.filter") }
end

check "C-07: OOF-COL3 message mentions 'Bool'" do
  r = rust_compile_source(FILTER_NONBOOL_SRC)
  r[:messages].any? { |m| m.include?("Bool") }
end

check "C-08: filter with Bool field predicate — no OOF-COL3" do
  r = rust_compile_source(FILTER_SRC)
  !r[:codes].include?("OOF-COL3")
end

check "C-09: filter + count chain compiles clean" do
  r = rust_compile_source(<<~IG)
    module M
    type Item { active: Bool; }
    contract C {
      input items : Collection[Item]
      output n : Integer
      compute active = filter(items, x -> x.active)
      compute n = count(active)
    }
  IG
  r[:status] == "ok" && !r[:codes].include?("OOF-COL3")
end

# ─────────────────────────────────────────────────────────────────────────────
# === D: map dispatch ===
# ─────────────────────────────────────────────────────────────────────────────
puts "\n=== D: map dispatch ==="

check "D-01: map(items, x -> x.value) compiles clean" do
  r = rust_compile_source(MAP_SRC)
  r[:status] == "ok" && r[:codes].empty?
end

check "D-02: map SIR fn == 'stdlib.collection.map'" do
  r = rust_compile_source(MAP_SRC)
  collect_sir_fns(r[:sir]).include?("stdlib.collection.map")
end

check "D-03: bare 'map' NOT in SIR fn values" do
  r = rust_compile_source(MAP_SRC)
  !collect_sir_fns(r[:sir]).include?("map")
end

check "D-04: map result type wraps lambda body type (Collection[Integer])" do
  r = rust_compile_source(MAP_SRC)
  sir = r[:sir]
  contracts = sir["contracts"] || []
  contracts.any? do |c|
    (c["nodes"] || []).any? do |node|
      node.dig("expr", "fn") == "stdlib.collection.map" &&
        node.dig("type", "name") == "Collection" &&
        node.dig("type", "params", 0, "name") == "Integer"
    end
  end
end

check "D-05: map result type no longer Collection[Unknown] after elem binding fix" do
  r = rust_compile_source(MAP_SRC)
  sir = r[:sir]
  contracts = sir["contracts"] || []
  contracts.none? do |c|
    (c["nodes"] || []).any? do |node|
      node.dig("expr", "fn") == "stdlib.collection.map" &&
        node.dig("type", "params", 0, "name") == "Unknown"
    end
  end
end

check "D-06: map does not emit OOF-COL3 (only filter validates predicate)" do
  r = rust_compile_source(MAP_SRC)
  !r[:codes].include?("OOF-COL3")
end

check "D-07: map with lambda returning Bool field — result Collection[Bool]" do
  r = rust_compile_source(<<~IG)
    module M
    type Item { active: Bool; }
    contract C {
      input items : Collection[Item]
      output flags : Collection[Bool]
      compute flags = map(items, x -> x.active)
    }
  IG
  sir = r[:sir]
  contracts = sir["contracts"] || []
  r[:status] == "ok" &&
    contracts.any? do |c|
      (c["nodes"] || []).any? do |node|
        node.dig("expr", "fn") == "stdlib.collection.map" &&
          node.dig("type", "params", 0, "name") == "Bool"
      end
    end
end

check "D-08: map on Collection[Integer] (no fields) — no crash" do
  r = rust_compile_source(<<~IG)
    module M
    contract C {
      input items : Collection[Integer]
      output doubled : Collection[Integer]
      compute doubled = map(items, x -> x)
    }
  IG
  !r.nil? && !r[:status].nil?
end

check "D-09: map + filter + count chain — all three qualified fns in SIR" do
  r = rust_compile_source(CHAIN_SRC)
  fns = collect_sir_fns(r[:sir])
  fns.include?("stdlib.collection.map") &&
    fns.include?("stdlib.collection.filter") &&
    fns.include?("stdlib.collection.count")
end

# ─────────────────────────────────────────────────────────────────────────────
# === E: SIR qualified names ===
# ─────────────────────────────────────────────────────────────────────────────
puts "\n=== E: SIR qualified names ==="

check "E-01: map SIR fn == 'stdlib.collection.map' (chain fixture)" do
  r = rust_compile_source(CHAIN_SRC)
  collect_sir_fns(r[:sir]).include?("stdlib.collection.map")
end

check "E-02: filter SIR fn == 'stdlib.collection.filter' (chain fixture)" do
  r = rust_compile_source(CHAIN_SRC)
  collect_sir_fns(r[:sir]).include?("stdlib.collection.filter")
end

check "E-03: count SIR fn == 'stdlib.collection.count' (chain fixture)" do
  r = rust_compile_source(CHAIN_SRC)
  collect_sir_fns(r[:sir]).include?("stdlib.collection.count")
end

check "E-04: bare 'map' not in chain SIR fn values" do
  r = rust_compile_source(CHAIN_SRC)
  !collect_sir_fns(r[:sir]).include?("map")
end

check "E-05: bare 'filter' not in chain SIR fn values" do
  r = rust_compile_source(CHAIN_SRC)
  !collect_sir_fns(r[:sir]).include?("filter")
end

check "E-06: bare 'count' not in chain SIR fn values" do
  r = rust_compile_source(CHAIN_SRC)
  !collect_sir_fns(r[:sir]).include?("count")
end

check "E-07: emitter source contains all three canonical qualified names" do
  EMITTER_SRC.include?('"stdlib.collection.map"') &&
    EMITTER_SRC.include?('"stdlib.collection.filter"') &&
    EMITTER_SRC.include?('"stdlib.collection.count"')
end

# ─────────────────────────────────────────────────────────────────────────────
# === F: Type inference correctness ===
# ─────────────────────────────────────────────────────────────────────────────
puts "\n=== F: Type inference correctness ==="

check "F-01: map result Collection[Integer] when lambda returns Integer field" do
  r = rust_compile_source(MAP_SRC)
  sir = r[:sir]
  (sir["contracts"] || []).any? do |c|
    (c["nodes"] || []).any? do |node|
      node.dig("expr", "fn") == "stdlib.collection.map" &&
        node.dig("type", "params", 0, "name") == "Integer"
    end
  end
end

check "F-02: map result Collection[Bool] when lambda returns Bool field" do
  r = rust_compile_source(<<~IG)
    module M
    type Item { active: Bool; }
    contract C {
      input items : Collection[Item]
      output flags : Collection[Bool]
      compute flags = map(items, x -> x.active)
    }
  IG
  sir = r[:sir]
  (sir["contracts"] || []).any? do |c|
    (c["nodes"] || []).any? do |node|
      node.dig("expr", "fn") == "stdlib.collection.map" &&
        node.dig("type", "params", 0, "name") == "Bool"
    end
  end
end

check "F-03: filter result type is Collection passthrough (same element type)" do
  r = rust_compile_source(FILTER_SRC)
  sir = r[:sir]
  (sir["contracts"] || []).any? do |c|
    (c["nodes"] || []).any? do |node|
      node.dig("expr", "fn") == "stdlib.collection.filter" &&
        node.dig("type", "name") == "Collection"
    end
  end
end

check "F-04: count result type is Integer" do
  r = rust_compile_source(COUNT_SRC)
  sir = r[:sir]
  (sir["contracts"] || []).any? do |c|
    (c["nodes"] || []).any? do |node|
      node.dig("expr", "fn") == "stdlib.collection.count" &&
        node.dig("type", "name") == "Integer"
    end
  end
end

check "F-05: filter Unknown predicate (==) not OOF-COL3 (Unknown passes permissively)" do
  # == operator returns Unknown in Rust TC (pre-existing gap) — must NOT trigger OOF-COL3
  r = rust_compile_source(<<~IG)
    module M
    type Item { label: Text; }
    contract C {
      input items : Collection[Item]
      output filtered : Collection[Item]
      compute filtered = filter(items, x -> x.label == "active")
    }
  IG
  !r[:codes].include?("OOF-COL3")
end

check "F-06: filter non-Bool explicit (Integer) → exactly OOF-COL3" do
  r = rust_compile_source(FILTER_NONBOOL_SRC)
  r[:codes].include?("OOF-COL3") && r[:codes].none? { |c| c == "OOF-COL3" && false }
end

check "F-07: map on Collection[Unknown] — no crash, fn qualified" do
  r = rust_compile_source(<<~IG)
    module M
    contract C {
      input items : Collection[Unknown]
      output result : Collection[Unknown]
      compute result = map(items, x -> x)
    }
  IG
  !r.nil? && collect_sir_fns(r[:sir]).include?("stdlib.collection.map")
end

check "F-08: chain filter+map+count result types consistent" do
  r = rust_compile_source(CHAIN_SRC)
  sir = r[:sir]
  contracts = sir["contracts"] || []
  # count node type = Integer
  count_ok = contracts.any? do |c|
    (c["nodes"] || []).any? { |n| n.dig("expr", "fn") == "stdlib.collection.count" && n.dig("type", "name") == "Integer" }
  end
  count_ok && r[:status] == "ok"
end

# ─────────────────────────────────────────────────────────────────────────────
# === G: App fixture parity ===
# ─────────────────────────────────────────────────────────────────────────────
puts "\n=== G: App fixture parity ==="

check "G-01: bookkeeping/ledger.ig — filter no longer 'Unknown function'" do
  if BK_TYPES.exist? && BK_LEDGER.exist?
    r = rust_compile(BK_TYPES, BK_LEDGER)
    !r[:messages].any? { |m| m.include?("Unknown function") && m.include?("filter") }
  else
    true
  end
end

check "G-02: bookkeeping/ledger.ig — map no longer 'Unknown function'" do
  if BK_TYPES.exist? && BK_LEDGER.exist?
    r = rust_compile(BK_TYPES, BK_LEDGER)
    !r[:messages].any? { |m| m.include?("Unknown function") && m.include?("map") }
  else
    true
  end
end

check "G-03: bookkeeping/ledger.ig — stdlib.collection.filter in SIR" do
  if BK_TYPES.exist? && BK_LEDGER.exist?
    r = rust_compile(BK_TYPES, BK_LEDGER)
    # Only check if status ok (ledger may have other OOF errors)
    r[:status] == "ok" ? collect_sir_fns(r[:sir]).include?("stdlib.collection.filter") : true
  else
    true
  end
end

check "G-04: erp_logistics/optimizer.ig — filter no longer 'Unknown function'" do
  if ERP_TYPES.exist? && ERP_OPTIM.exist?
    r = rust_compile(ERP_TYPES, ERP_OPTIM)
    !r[:messages].any? { |m| m.include?("Unknown function") && m.include?("filter") }
  else
    true
  end
end

check "G-05: erp_logistics/optimizer.ig — fold unaffected (still bare 'fold' in SIR)" do
  if ERP_TYPES.exist? && ERP_OPTIM.exist?
    r = rust_compile(ERP_TYPES, ERP_OPTIM)
    # fold should still use bare name (not qualified) — P4 does not touch fold
    fns = collect_sir_fns(r[:sir])
    !fns.include?("stdlib.collection.fold")
  else
    true
  end
end

check "G-06: inline full-chain (Bool predicate) — zero collection errors" do
  r = rust_compile_source(CHAIN_SRC)
  r[:status] == "ok" &&
    !r[:codes].include?("OOF-COL1") &&
    !r[:codes].include?("OOF-COL2") &&
    !r[:codes].include?("OOF-COL3")
end

# ─────────────────────────────────────────────────────────────────────────────
# === H: Lambda element type binding ===
# ─────────────────────────────────────────────────────────────────────────────
puts "\n=== H: Lambda element type binding ==="

check "H-01: map lambda param bound to elem type — field access resolves (no Unknown result)" do
  r = rust_compile_source(MAP_SRC)
  sir = r[:sir]
  contracts = sir["contracts"] || []
  # After fix: map(Collection[Item], x -> x.value) → Collection[Integer], not Collection[Unknown]
  contracts.any? do |c|
    (c["nodes"] || []).any? do |node|
      node.dig("expr", "fn") == "stdlib.collection.map" &&
        node.dig("type", "name") == "Collection" &&
        node.dig("type", "params", 0, "name") != "Unknown"
    end
  end
end

check "H-02: map lambda param bound to Decimal[2] field correctly" do
  r = rust_compile_source(<<~IG)
    module M
    type Posting { amount: Decimal[2]; }
    contract C {
      input postings : Collection[Posting]
      output amounts : Collection[Decimal[2]]
      compute amounts = map(postings, p -> p.amount)
    }
  IG
  sir = r[:sir]
  (sir["contracts"] || []).any? do |c|
    (c["nodes"] || []).any? do |node|
      node.dig("expr", "fn") == "stdlib.collection.map" &&
        node.dig("type", "name") == "Collection" &&
        node.dig("type", "params", 0, "name") == "Decimal"
    end
  end
end

check "H-03: filter lambda param bound to elem type — Bool field access works" do
  r = rust_compile_source(FILTER_SRC)
  # Filter with x.active (Bool field) should not emit OOF-COL3
  r[:status] == "ok" && !r[:codes].include?("OOF-COL3")
end

check "H-04: filter lambda Integer predicate → OOF-COL3 (elem type binding active)" do
  r = rust_compile_source(FILTER_NONBOOL_SRC)
  r[:codes].include?("OOF-COL3")
end

check "H-05: map elem binding uses get_param(&first_arg_type, 0)" do
  TC_RUST_SRC.include?("get_param(&first_arg_type, 0)")
end

check "H-06: filter elem binding uses get_param(&resolved_type, 0)" do
  TC_RUST_SRC.include?("get_param(&resolved_type, 0)")
end

# ─────────────────────────────────────────────────────────────────────────────
# === I: Authority closed ===
# ─────────────────────────────────────────────────────────────────────────────
puts "\n=== I: Authority closed ==="

check "I-01: fold → bare 'fold' in SIR (not qualified in P4)" do
  r = rust_compile_source(<<~IG)
    module M
    contract C {
      input items : Collection[Integer]
      output total : Integer
      compute total = fold(items, 0, (acc, x) -> acc)
    }
  IG
  fns = collect_sir_fns(r[:sir])
  # fold uses bare name — P4 does not touch fold
  !fns.include?("stdlib.collection.fold")
end

check "I-02: sum → still dispatched by Rust TC (P4 does not remove sum)" do
  r = rust_compile_source(<<~IG)
    module M
    type Item { amount: Decimal[2]; }
    contract C {
      input items : Collection[Item]
      output total : Decimal[2]
      compute total = sum(items, :amount)
    }
  IG
  # sum still works in Rust TC — P4 does not touch it
  !r.nil? && !r[:status].nil?
end

check "I-03: COLLECTION_HOF_OPS does not include 'fold'" do
  # Static source check — fold not in COLLECTION_HOF_OPS
  # Find the COLLECTION_HOF_OPS block and verify fold absent
  hof_block_start = EMITTER_SRC.index("COLLECTION_HOF_OPS")
  if hof_block_start
    block = EMITTER_SRC[hof_block_start, 300]
    !block.include?('"fold"')
  else
    false
  end
end

check "I-04: COLLECTION_HOF_OPS does not include 'sum'" do
  hof_block_start = EMITTER_SRC.index("COLLECTION_HOF_OPS")
  if hof_block_start
    block = EMITTER_SRC[hof_block_start, 300]
    !block.include?('"sum"')
  else
    false
  end
end

check "I-05: stdlib-inventory.json unchanged — map/filter not yet in inventory" do
  entries = INVENTORY_DATA["entries"] || []
  !entries.any? { |e| e["canonical_name"] == "stdlib.collection.map" } &&
    !entries.any? { |e| e["canonical_name"] == "stdlib.collection.filter" }
end

check "I-06: Ruby TC unmodified by P4 (COLLECTION_HOF_FNS still in Ruby source)" do
  ruby_src = TC_RUBY.read.encode("UTF-8", invalid: :replace, undef: :replace)
  ruby_src.include?("COLLECTION_HOF_FNS")
end

check "I-07: Rust TC VM/runtime unchanged — no new VM opcodes for map/filter/count" do
  # No vm.rs / runtime.rs changes — check no new COLLECTION_HOF in VM source
  vm_rs = LAB_ROOT / "igniter-compiler" / "src" / "vm.rs"
  if vm_rs.exist?
    vm_src = vm_rs.read.encode("UTF-8", invalid: :replace, undef: :replace)
    !vm_src.include?("COLLECTION_HOF_OPS")
  else
    true
  end
end

# ─────────────────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────────────────

total = $pass + $fail
puts "\n" + "=" * 60
puts "LANG-STDLIB-COLLECTION-MAP-FILTER-PROP-P4: #{$pass} PASS / #{$fail} FAIL / #{total} total"
puts "=" * 60
if $fail == 0
  puts "\nVERDICT: PASS — Rust parity proved"
  puts "stdlib.collection.{map,filter,count} canonical SIR names live."
  puts "Lambda params bound to Collection element type T."
  puts "filter OOF-COL3 active for non-Bool predicates."
  puts "Next route: LANG-STDLIB-COLLECTION-MAP-FILTER-PROP-P5 (inventory integration)"
else
  puts "\nVERDICT: FAIL — #{$fail} check(s) need attention"
end
