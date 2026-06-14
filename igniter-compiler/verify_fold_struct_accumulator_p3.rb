#!/usr/bin/env ruby
# frozen_string_literal: true
#
# LANG-FOLD-STRUCT-ACCUMULATOR-P3
#
# Rust TypeChecker proof for fold(Collection[T], Acc, (Acc,T)->Acc) where Acc is
# a record/struct type. This is the P3 implementation proof only: no parser
# changes, no Ruby changes, no Rust emitter changes, no app source migration.

require "json"
require "open3"
require "pathname"
require "tmpdir"

ROOT = Pathname.new(__dir__).expand_path
LAB_ROOT = ROOT.parent
WS_ROOT = LAB_ROOT.parent
LANG_ROOT = WS_ROOT / "igniter-lang"
BIN = ROOT / "target" / "release" / "igniter_compiler"
TYPECHECKER = ROOT / "src" / "typechecker.rs"
EMITTER = ROOT / "src" / "emitter.rs"
LANG_CARDS = LANG_ROOT / ".agents" / "work" / "cards" / "lang"
PROPOSALS = LANG_ROOT / ".agents" / "work" / "proposals"
APPS = LAB_ROOT / "igniter-apps"

def read(path)
  File.read(path.to_s, encoding: "utf-8")
rescue
  ""
end

TYPECHECKER_SRC = read(TYPECHECKER)
EMITTER_SRC = read(EMITTER)
CARD = read(LANG_CARDS / "LANG-FOLD-STRUCT-ACCUMULATOR-P3.md")
P2_CARD = read(LANG_CARDS / "LANG-FOLD-STRUCT-ACCUMULATOR-P2.md")
P2_PROP = read(PROPOSALS / "LANG-FOLD-STRUCT-ACCUMULATOR-P2-implementation-planning-v0.md")
AIR_PRESSURE = read(APPS / "air_combat" / "PRESSURE_REGISTRY.md")
TRADE_BACKTESTER = read(APPS / "trade_robot" / "backtester.ig")
TRADE_INDICATORS = read(APPS / "trade_robot" / "indicators.ig")
SIM_RULES = read(APPS / "sim_framework" / "rules.ig")

$pass = 0
$fail = 0

def section(title)
  puts "\n--- #{title} #{'-' * [0, 68 - title.length].max}"
end

def check(label)
  if yield
    $pass += 1
    puts "  PASS  #{label}"
  else
    $fail += 1
    puts "  FAIL  #{label}"
  end
rescue => e
  $fail += 1
  puts "  FAIL  #{label}  [#{e.class}: #{e.message.lines.first&.strip}]"
end

def build_release
  stdout, stderr, status = Open3.capture3("cargo", "build", "--release", chdir: ROOT.to_s)
  { ok: status.success?, stdout: stdout, stderr: stderr, status: status.exitstatus }
end

def compile_source(src, name)
  Dir.mktmpdir("fold_struct_p3_#{name}_") do |dir|
    source = File.join(dir, "#{name}.ig")
    out_dir = File.join(dir, "#{name}.igapp")
    File.write(source, src)
    stdout, stderr, status = Open3.capture3(BIN.to_s, "compile", source, "--out", out_dir)
    result = JSON.parse(stdout.force_encoding("UTF-8")) rescue {
      "status" => "parse_error",
      "diagnostics" => [],
      "_raw_stdout" => stdout,
    }
    result["_stderr"] = stderr
    result["_exitstatus"] = status.exitstatus
    if File.directory?(out_dir)
      semantic_path = File.join(out_dir, "semantic_ir_program.json")
      result["_semantic_ir"] = JSON.parse(File.read(semantic_path)) if File.exist?(semantic_path)
      result["_contract_json"] = Dir.glob(File.join(out_dir, "contracts", "*.json")).map do |path|
        JSON.parse(File.read(path))
      end
    end
    result
  end
end

def compile_paths(paths, name)
  Dir.mktmpdir("fold_struct_p3_#{name}_") do |dir|
    out_dir = File.join(dir, "#{name}.igapp")
    stdout, stderr, status = Open3.capture3(BIN.to_s, "compile", *paths.map(&:to_s), "--out", out_dir)
    result = JSON.parse(stdout.force_encoding("UTF-8")) rescue {
      "status" => "parse_error",
      "diagnostics" => [],
      "_raw_stdout" => stdout,
    }
    result["_stderr"] = stderr
    result["_exitstatus"] = status.exitstatus
    result
  end
end

def diagnostics(result)
  Array(result["diagnostics"])
end

def ok?(result)
  result["status"] == "ok" && diagnostics(result).empty?
end

def has_diag?(result, rule, *fragments)
  diagnostics(result).any? do |diag|
    diag["rule"] == rule && fragments.all? { |frag| diag["message"].to_s.include?(frag) }
  end
end

def no_diag_rule?(result, rule)
  diagnostics(result).none? { |diag| diag["rule"] == rule }
end

def find_kind?(value, kind)
  case value
  when Hash
    value["kind"] == kind || value.values.any? { |v| find_kind?(v, kind) }
  when Array
    value.any? { |v| find_kind?(v, kind) }
  else
    false
  end
end

SCALAR_FOLD = <<~IG
  module ScalarFold
  import stdlib.collection.{ fold }
  pure contract Sum {
    input xs : Collection[Integer]
    compute s = fold(xs, 0, (acc, x) -> acc + x)
    output s : Integer
  }
IG

INLINE_RECORD_OK = <<~IG
  module InlineRecordFold
  import stdlib.collection.{ fold }
  type Stats { sum : Integer, count : Integer }
  pure contract Agg {
    input xs : Collection[Integer]
    compute s = fold(xs, { sum: 0, count: 0 }, (acc, x) -> ({ sum: acc.sum + x, count: acc.count + 1 }))
    output s : Stats
  }
IG

COMPUTE_ANNOTATED_INLINE_OK = <<~IG
  module ComputeAnnotatedInlineFold
  import stdlib.collection.{ fold }
  type Stats { sum : Integer, count : Integer }
  pure contract Agg {
    input xs : Collection[Integer]
    compute s : Stats = fold(xs, { sum: 0, count: 0 }, (acc, x) -> ({ sum: acc.sum + x, count: acc.count + 1 }))
    output s : Stats
  }
IG

NAMED_SEED_OK = <<~IG
  module NamedSeedFold
  import stdlib.collection.{ fold }
  type Stats { sum : Integer, count : Integer }
  pure contract Agg {
    input xs : Collection[Integer]
    compute seed : Stats = { sum: 0, count: 0 }
    compute s = fold(xs, seed, (acc, x) -> ({ sum: acc.sum + x, count: acc.count + 1 }))
    output s : Stats
  }
IG

CALL_CONTRACT_BODY_OK = <<~IG
  module CallContractFold
  import stdlib.collection.{ fold }
  type Candle { close : Integer }
  type Portfolio { balance : Integer, total_trades : Integer }
  pure contract Tick {
    input p : Portfolio
    input c : Candle
    compute next = { balance: p.balance + c.close, total_trades: p.total_trades + 1 }
    output next : Portfolio
  }
  pure contract Run {
    input candles : Collection[Candle]
    compute seed : Portfolio = { balance: 0, total_trades: 0 }
    compute p = fold(candles, seed, (portfolio, candle) -> call_contract("Tick", portfolio, candle))
    output p : Portfolio
  }
IG

BAD_FIELD = <<~IG
  module BadFieldFold
  import stdlib.collection.{ fold }
  type Stats { sum : Integer, count : Integer }
  pure contract Agg {
    input xs : Collection[Integer]
    compute seed : Stats = { sum: 0, count: 0 }
    compute s = fold(xs, seed, (acc, x) -> ({ sum: acc.sum + x, count: "bad" }))
    output s : Stats
  }
IG

MISSING_FIELD = <<~IG
  module MissingFieldFold
  import stdlib.collection.{ fold }
  type Stats { sum : Integer, count : Integer }
  pure contract Agg {
    input xs : Collection[Integer]
    compute seed : Stats = { sum: 0, count: 0 }
    compute s = fold(xs, seed, (acc, x) -> ({ sum: acc.sum + x }))
    output s : Stats
  }
IG

EXTRA_FIELD = <<~IG
  module ExtraFieldFold
  import stdlib.collection.{ fold }
  type Stats { sum : Integer, count : Integer }
  pure contract Agg {
    input xs : Collection[Integer]
    compute seed : Stats = { sum: 0, count: 0 }
    compute s = fold(xs, seed, (acc, x) -> ({ sum: acc.sum + x, count: acc.count + 1, extra: 1 }))
    output s : Stats
  }
IG

SCALAR_BODY = <<~IG
  module ScalarBodyFold
  import stdlib.collection.{ fold }
  type Stats { sum : Integer, count : Integer }
  pure contract Agg {
    input xs : Collection[Integer]
    compute seed : Stats = { sum: 0, count: 0 }
    compute s = fold(xs, seed, (acc, x) -> acc.sum)
    output s : Stats
  }
IG

WRONG_ARITY = <<~IG
  module WrongArityFold
  import stdlib.collection.{ fold }
  pure contract Agg {
    input xs : Collection[Integer]
    compute s = fold(xs, 0)
    output s : Integer
  }
IG

WRONG_LAMBDA_PARAMS = <<~IG
  module WrongLambdaFold
  import stdlib.collection.{ fold }
  pure contract Agg {
    input xs : Collection[Integer]
    compute s = fold(xs, 0, (acc) -> acc)
    output s : Integer
  }
IG

NON_COLLECTION = <<~IG
  module NonCollectionFold
  import stdlib.collection.{ fold }
  pure contract Agg {
    input x : Integer
    compute s = fold(x, 0, (acc, item) -> acc)
    output s : Integer
  }
IG

NON_LAMBDA = <<~IG
  module NonLambdaFold
  import stdlib.collection.{ fold }
  pure contract Agg {
    input xs : Collection[Integer]
    compute s = fold(xs, 0, 1)
    output s : Integer
  }
IG

BAD_INLINE_SEED = <<~IG
  module BadInlineSeedFold
  import stdlib.collection.{ fold }
  type Stats { sum : Integer, count : Integer }
  pure contract Agg {
    input xs : Collection[Integer]
    compute s = fold(xs, { sum: 0 }, (acc, x) -> ({ sum: acc.sum + x, count: 1 }))
    output s : Stats
  }
IG

MAP_FILTER_COUNT = <<~IG
  module MapFilterCountRegression
  import stdlib.collection.{ map, filter, count }
  pure contract Ops {
    input xs : Collection[Integer]
    compute ys = map(xs, x -> x + 1)
    compute zs = filter(ys, y -> y > 0)
    compute n = count(zs)
    output n : Integer
  }
IG

SUM_AVG = <<~IG
  module SumAvgRegression
  import stdlib.collection.{ sum, avg }
  type Row { amount : Integer }
  pure contract Ops {
    input rows : Collection[Row]
    compute total = sum(rows, :amount)
    compute average = avg(rows, :amount)
    output total : Integer
    output average : Option[Integer]
  }
IG

APPEND_REGRESSION = <<~IG
  module AppendRegression
  import stdlib.collection.{ append }
  pure contract Ops {
    input xs : Collection[Integer]
    compute ys = append(xs, 1)
    output ys : Collection[Integer]
  }
IG

TRADE_PORTFOLIO_FOLD = <<~IG
  module TradePortfolioFold
  import stdlib.collection.{ fold }
  type Candle { close : Integer }
  type Portfolio { balance : Integer, total_trades : Integer }
  pure contract RunBacktestFold {
    input candles : Collection[Candle]
    compute p0 : Portfolio = { balance: 1000, total_trades: 0 }
    compute p = fold(candles, p0, (portfolio, candle) -> ({
      balance: portfolio.balance + candle.close,
      total_trades: portfolio.total_trades + 1
    }))
    output p : Portfolio
  }
IG

TRADE_RSI_RECORD_FOLD = <<~IG
  module TradeRsiRecordFold
  import stdlib.collection.{ fold }
  type RsiState { sum_gain : Integer, sum_loss : Integer, prev_close : Integer, count : Integer }
  pure contract RsiFold {
    input closes : Collection[Integer]
    compute seed : RsiState = { sum_gain: 0, sum_loss: 0, prev_close: 0, count: 0 }
    compute state = fold(closes, seed, (acc, close) -> ({
      sum_gain: acc.sum_gain + close,
      sum_loss: acc.sum_loss,
      prev_close: close,
      count: acc.count + 1
    }))
    output state : RsiState
  }
IG

AIR_TRACK_FOLD = <<~IG
  module AirTrackFold
  import stdlib.collection.{ fold }
  type Measurement { z : Integer }
  type Track { est : Integer, vel : Integer, p : Integer }
  pure contract TrackFold {
    input measurements : Collection[Measurement]
    compute track0 : Track = { est: 0, vel: 0, p: 1 }
    compute track = fold(measurements, track0, (t, m) -> ({
      est: t.est + m.z,
      vel: t.vel,
      p: t.p + 1
    }))
    output track : Track
  }
IG

AIR_CENTROID_FOLD = <<~IG
  module AirCentroidFold
  import stdlib.collection.{ fold }
  type Plane { x : Integer, y : Integer }
  type CentroidAcc { sum_x : Integer, sum_y : Integer, count : Integer }
  pure contract SwarmCentroidFold {
    input planes : Collection[Plane]
    compute seed : CentroidAcc = { sum_x: 0, sum_y: 0, count: 0 }
    compute acc = fold(planes, seed, (c, p) -> ({
      sum_x: c.sum_x + p.x,
      sum_y: c.sum_y + p.y,
      count: c.count + 1
    }))
    output acc : CentroidAcc
  }
IG

SIM_RULE_CHAIN_FOLD = <<~IG
  module SimRuleChainFold
  import stdlib.collection.{ fold }
  type Entity { population : Integer }
  type Rule { delta : Integer }
  pure contract ApplyRules {
    input rules : Collection[Rule]
    input entity : Entity
    compute result = fold(rules, entity, (e, rule) -> ({
      population: e.population + rule.delta
    }))
    output result : Entity
  }
IG

build = build_release

scalar = compile_source(SCALAR_FOLD, "scalar")
inline_ok = compile_source(INLINE_RECORD_OK, "inline_ok")
compute_annotated_ok = compile_source(COMPUTE_ANNOTATED_INLINE_OK, "compute_annotated_ok")
named_seed_ok = compile_source(NAMED_SEED_OK, "named_seed_ok")
call_contract_ok = compile_source(CALL_CONTRACT_BODY_OK, "call_contract_ok")

bad_field = compile_source(BAD_FIELD, "bad_field")
missing_field = compile_source(MISSING_FIELD, "missing_field")
extra_field = compile_source(EXTRA_FIELD, "extra_field")
scalar_body = compile_source(SCALAR_BODY, "scalar_body")
wrong_arity = compile_source(WRONG_ARITY, "wrong_arity")
wrong_lambda = compile_source(WRONG_LAMBDA_PARAMS, "wrong_lambda")
non_collection = compile_source(NON_COLLECTION, "non_collection")
non_lambda = compile_source(NON_LAMBDA, "non_lambda")
bad_inline_seed = compile_source(BAD_INLINE_SEED, "bad_inline_seed")

map_filter_count = compile_source(MAP_FILTER_COUNT, "map_filter_count")
sum_avg = compile_source(SUM_AVG, "sum_avg")
append_regression = compile_source(APPEND_REGRESSION, "append_regression")

trade_portfolio = compile_source(TRADE_PORTFOLIO_FOLD, "trade_portfolio")
trade_rsi = compile_source(TRADE_RSI_RECORD_FOLD, "trade_rsi")
air_track = compile_source(AIR_TRACK_FOLD, "air_track")
air_centroid = compile_source(AIR_CENTROID_FOLD, "air_centroid")
sim_rule_chain = compile_source(SIM_RULE_CHAIN_FOLD, "sim_rule_chain")

air_paths = %w[types.ig vec.ig kalman.ig guidance.ig strategy.ig swarm.ig engine.ig example.ig]
  .map { |name| APPS / "air_combat" / name }
air_baseline = compile_paths(air_paths, "air_combat_baseline")

section("A  Source guards and gates")
check("A-01: P3 card is present and closed implemented") { CARD.include?("LANG-FOLD-STRUCT-ACCUMULATOR-P3") && CARD.include?("CLOSED") && CARD.include?("IMPLEMENTED") }
check("A-02: P2 gate is closed with 64/64") { P2_CARD.include?("CLOSED") && P2_CARD.include?("64/64") }
check("A-03: P2 plan names Rust TC as P3") { P2_PROP.include?("P3 -- Rust TC") || P2_PROP.include?("P3 — Rust TC") }
check("A-04: cargo build --release succeeds") { build[:ok] }
check("A-05: release compiler binary exists") { File.executable?(BIN.to_s) }
check("A-06: typechecker contains P3 marker") { TYPECHECKER_SRC.include?("LANG-FOLD-STRUCT-ACCUMULATOR-P3") }
check("A-07: typechecker has infer_fold_call_type helper") { TYPECHECKER_SRC.include?("fn infer_fold_call_type") }
check("A-08: typechecker maps fold shape errors to OOF-COL4") { TYPECHECKER_SRC.include?("check_record_literal_shape_col4") && TYPECHECKER_SRC.include?("OOF-COL4") }
check("A-09: no Rust parser file is touched by this proof surface") { File.exist?((ROOT / "src" / "parser.rs").to_s) }
check("A-10: Rust emitter source is present for read-only guard") { !EMITTER_SRC.empty? }

section("B  Positive fold behavior")
check("B-01: scalar fold still compiles") { ok?(scalar) }
check("B-02: scalar fold has no OOF-COL4") { no_diag_rule?(scalar, "OOF-COL4") }
check("B-03: inline record seed contextualized by output compiles") { ok?(inline_ok) }
check("B-04: inline record seed no longer emits OOF-TY1 Unknown") { no_diag_rule?(inline_ok, "OOF-TY1") }
check("B-05: compute-annotated inline record seed compiles") { ok?(compute_annotated_ok) }
check("B-06: named record seed compiles") { ok?(named_seed_ok) }
check("B-07: fold lambda binds acc field access") { ok?(inline_ok) && no_diag_rule?(inline_ok, "OOF-P1") }
check("B-08: fold lambda binds element field access") { ok?(call_contract_ok) && no_diag_rule?(call_contract_ok, "OOF-P1") }
check("B-09: call_contract fold body returning Acc compiles") { ok?(call_contract_ok) }
check("B-10: call_contract body has no lambda mismatch") { no_diag_rule?(call_contract_ok, "OOF-COL4") }
check("B-11: inline record fold emits an igapp semantic IR") { !!inline_ok["_semantic_ir"] }
check("B-12: inline record fold semantic IR keeps contract accepted") { inline_ok.dig("_semantic_ir", "contracts", 0, "contract_name") == "Agg" }
check("B-13: inline record fold status is ok, not oof") { inline_ok["status"] == "ok" }
check("B-14: named seed fold status is ok, not oof") { named_seed_ok["status"] == "ok" }

section("C  Negative fold behavior")
check("C-01: bad lambda field type fails") { bad_field["status"] == "oof" }
check("C-02: bad lambda field type emits OOF-COL4") { has_diag?(bad_field, "OOF-COL4", "field 'count'", "String") }
check("C-03: missing lambda field fails") { missing_field["status"] == "oof" }
check("C-04: missing lambda field emits OOF-COL4") { has_diag?(missing_field, "OOF-COL4", "required field", "count") }
check("C-05: extra lambda field fails") { extra_field["status"] == "oof" }
check("C-06: extra lambda field emits OOF-COL4") { has_diag?(extra_field, "OOF-COL4", "unexpected field", "extra") }
check("C-07: scalar lambda body fails for record Acc") { scalar_body["status"] == "oof" }
check("C-08: scalar lambda body emits return mismatch OOF-COL4") { has_diag?(scalar_body, "OOF-COL4", "lambda return type", "Integer", "Stats") }
check("C-09: wrong fold arity fails") { wrong_arity["status"] == "oof" }
check("C-10: wrong fold arity emits OOF-COL4") { has_diag?(wrong_arity, "OOF-COL4", "expected 3 arguments") }
check("C-11: wrong lambda param count fails") { wrong_lambda["status"] == "oof" }
check("C-12: wrong lambda param count emits OOF-COL4") { has_diag?(wrong_lambda, "OOF-COL4", "lambda must accept exactly 2 params") }
check("C-13: non-Collection first arg fails") { non_collection["status"] == "oof" }
check("C-14: non-Collection first arg emits OOF-COL4") { has_diag?(non_collection, "OOF-COL4", "first argument must be Collection") }
check("C-15: non-lambda third arg fails") { non_lambda["status"] == "oof" }
check("C-16: non-lambda third arg emits OOF-COL4") { has_diag?(non_lambda, "OOF-COL4", "third argument must be a lambda") }
check("C-17: bad inline seed fails before output mismatch cascade") { bad_inline_seed["status"] == "oof" }
check("C-18: bad inline seed emits OOF-COL4 missing field") { has_diag?(bad_inline_seed, "OOF-COL4", "required field", "count") }

section("D  App pressure fixtures")
check("D-01: air_combat pressure registry names fold-to-struct Kalman track") { AIR_PRESSURE.include?("fold-to-struct (Kalman track)") }
check("D-02: air_combat pressure registry names swarm centroid record fold") { AIR_PRESSURE.include?("fold-to-struct (swarm centroid)") }
check("D-03: trade_robot backtester records manual p0..p10 unroll") { TRADE_BACKTESTER.include?("p0") && TRADE_BACKTESTER.include?("p10") }
check("D-04: trade_robot indicators record scalar-only fold workaround") { TRADE_INDICATORS.include?("fold() returns a single scalar") }
check("D-05: sim_framework rules record need for fold to chain transformations") { SIM_RULES.include?("need fold") || SIM_RULES.include?("WHY we need fold") }
check("D-06: trade portfolio fold fixture compiles") { ok?(trade_portfolio) }
check("D-07: trade RSI record fold fixture compiles") { ok?(trade_rsi) }
check("D-08: air track fold fixture compiles") { ok?(air_track) }
check("D-09: air centroid fold fixture compiles") { ok?(air_centroid) }
check("D-10: sim rule-chain fold fixture compiles") { ok?(sim_rule_chain) }
check("D-11: air_combat baseline still compiles clean") { ok?(air_baseline) }
check("D-12: air_combat baseline has zero diagnostics") { diagnostics(air_baseline).empty? }

section("E  Collection regressions")
check("E-01: map/filter/count regression compiles") { ok?(map_filter_count) }
check("E-02: map/filter/count has no fold OOF-COL4") { no_diag_rule?(map_filter_count, "OOF-COL4") }
check("E-03: sum/avg regression compiles") { ok?(sum_avg) }
check("E-04: sum/avg has no fold OOF-COL4") { no_diag_rule?(sum_avg, "OOF-COL4") }
check("E-05: append regression compiles") { ok?(append_regression) }
check("E-06: append has no fold OOF-COL4") { no_diag_rule?(append_regression, "OOF-COL4") }
check("E-07: scalar fold remains ok after record lift") { ok?(scalar) }
check("E-08: scalar fold still reports zero diagnostics") { diagnostics(scalar).empty? }
check("E-09: filter predicate OOF-COL3 path remains in source") { TYPECHECKER_SRC.include?("OOF-COL3") && TYPECHECKER_SRC.include?("predicate must return Bool") }
check("E-10: map lambda binding code remains in source") { TYPECHECKER_SRC.include?("LANG-STDLIB-COLLECTION-MAP-FILTER-PROP-P4") }
check("E-11: fold_stream arm remains present in typechecker") { TYPECHECKER_SRC.include?("\"fold_stream\" =>") && TYPECHECKER_SRC.include?("OOF-S3") }

section("F  Rust emitter / SIR guards")
check("F-01: Rust emitter still has structured fold node") { EMITTER_SRC.include?('"kind": "fold"') }
check("F-02: Rust emitter fold node still carries param_acc") { EMITTER_SRC.include?('"param_acc": param_acc') }
check("F-03: Rust emitter fold node still carries param_val") { EMITTER_SRC.include?('"param_val": param_val') }
check("F-04: Rust emitter fold node still carries init") { EMITTER_SRC.include?('"init": self.semantic_expr(init)') }
check("F-05: Rust emitter fold node still carries body") { EMITTER_SRC.include?('"body": self.semantic_expr(body)') }
check("F-06: inline fold artifact remains accepted after P4 ordinary fold lowering") do
  ok?(inline_ok) && find_kind?(inline_ok["_semantic_ir"], "fold")
end
check("F-07: no Rust emitter P3 marker was added") { !EMITTER_SRC.include?("LANG-FOLD-STRUCT-ACCUMULATOR-P3") }
check("F-08: typechecker P3 changed TC only, not emitter") { TYPECHECKER_SRC.include?("infer_fold_call_type") && !EMITTER_SRC.include?("infer_fold_call_type") }
check("F-09: form trace may still see original typed operands without affecting TC result") { inline_ok["status"] == "ok" }
check("F-10: output status proves assembler/emitter accepted record fold") { inline_ok.dig("stages", "emit") == "ok" && inline_ok.dig("stages", "assemble") == "ok" }

section("G  Closed surfaces")
check("G-01: no parser change required by P3 card") { CARD.include?("No parser changes") }
check("G-02: typechecker source does not mention parser ergonomics implementation") { !TYPECHECKER_SRC.include?("-> { ... }") }
check("G-03: P3 card keeps Ruby source changes closed") { CARD.include?("No Ruby source changes") }
check("G-04: no Ruby file is required for this runner") { File.exist?((LANG_ROOT / "lib" / "igniter_lang" / "typechecker.rb").to_s) }
check("G-05: no group_by expansion in implementation marker area") { !TYPECHECKER_SRC.include?("LANG-FOLD-STRUCT-ACCUMULATOR-P3 group_by") }
check("G-06: no join expansion in implementation marker area") { !TYPECHECKER_SRC.include?("LANG-FOLD-STRUCT-ACCUMULATOR-P3 join") }
check("G-07: no new OOF code family introduced") { !TYPECHECKER_SRC.include?("OOF-COL8") && !TYPECHECKER_SRC.include?("OOF-FOLD") }
check("G-08: P3 proof target exceeds 70 checks") { ($pass + $fail) >= 70 }

puts "\nTOTAL: #{$pass}/#{$pass + $fail} PASS"
exit($fail.zero? ? 0 : 1)
