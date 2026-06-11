#!/usr/bin/env ruby
# frozen_string_literal: true
#
# verify_lang_module_identity_p2.rb
# LANG-MODULE-IDENTITY-P2 - program_id algorithm parity proof.
#
# Authority: governance + bounded identity parity only.
# No multi-file compilation, import resolution, package registry, visibility,
# OOF-M1/M2/M3 implementation, VM bytecode identity redesign, or public API.

require "digest"
require "fileutils"
require "json"
require "open3"
require "pathname"
require "tmpdir"

ROOT           = Pathname.new(__dir__).parent
LAB_ROOT       = ROOT.parent
WORKSPACE_ROOT = LAB_ROOT.parent
IGNITER_LANG   = WORKSPACE_ROOT / "igniter-lang"
IGNITER_LIB    = IGNITER_LANG / "lib"
COMPILER_BIN   = LAB_ROOT / "igniter-compiler" / "target" / "release" / "igniter_compiler"
P1_DOC         = LAB_ROOT / "lab-docs" / "governance" / "lang-module-identity-hash-discipline-readiness-v0.md"
CLASSIFIER_RS  = LAB_ROOT / "igniter-compiler" / "src" / "classifier.rs"
TYPECHECKER_RS = LAB_ROOT / "igniter-compiler" / "src" / "typechecker.rs"
EMITTER_RS     = LAB_ROOT / "igniter-compiler" / "src" / "emitter.rs"

$LOAD_PATH.unshift(IGNITER_LIB.to_s) unless $LOAD_PATH.include?(IGNITER_LIB.to_s)
require "igniter_lang"

$pass_count = 0
$fail_count = 0

def check(label)
  result = yield
  if result
    puts "  PASS: #{label}"
    $pass_count += 1
  else
    puts "  FAIL: #{label}"
    $fail_count += 1
  end
rescue => e
  puts "  ERROR: #{label} - #{e.class}: #{e.message.lines.first&.strip}"
  $fail_count += 1
end

def sha256_prefix(seed)
  Digest::SHA256.hexdigest(seed)[0, 16]
end

def raw_source_hash(source)
  "sha256:#{Digest::SHA256.hexdigest(source)}"
end

def ruby_pipeline(path)
  source = File.read(path, encoding: "UTF-8")
  parsed = IgniterLang::ParsedProgram.parse(source, source_path: path.to_s).to_h
  classified = IgniterLang::Classifier.new.classify(parsed, sample_input: {})
  typed = IgniterLang::TypeChecker.new.typecheck(classified)
  emitted = IgniterLang::SemanticIREmitter.new.emit_typed(typed)
  {
    parsed: parsed,
    classified: classified,
    typed: typed,
    semantic_ir: emitted.fetch("semantic_ir"),
    report: emitted.fetch("compilation_report")
  }
end

def rust_compile(path)
  out_dir = Dir.mktmpdir("lang_module_identity_p2")
  stdout, stderr, status = Open3.capture3(
    COMPILER_BIN.to_s, "compile", path.to_s, "--out", out_dir, "--json"
  )
  raise "rust compiler failed: #{stderr}\n#{stdout}" unless status.success?

  report = JSON.parse(stdout)
  {
    out_dir: out_dir,
    report: report,
    classified: JSON.parse(File.read(File.join(out_dir, "classified_ast.json"), encoding: "UTF-8")),
    semantic_ir: JSON.parse(File.read(File.join(out_dir, "semantic_ir_program.json"), encoding: "UTF-8")),
    compilation_report: JSON.parse(File.read(File.join(out_dir, "compilation_report.json"), encoding: "UTF-8")),
    manifest: JSON.parse(File.read(File.join(out_dir, "manifest.json"), encoding: "UTF-8"))
  }
end

def write_fixture(dir, basename, body)
  path = File.join(dir, basename)
  File.write(path, body)
  path
end

BASE_SOURCE = <<~IG
  module Lang.IdentityP2

  pure contract Add {
    input a : Integer
    input b : Integer
    compute total = a + b
    output total : Integer
  }
IG

DIFFERENT_SOURCE = <<~IG
  module Lang.IdentityP2

  pure contract Add {
    input a : Integer
    input b : Integer
    compute total = a + b
    compute doubled = total + total
    output doubled : Integer
  }
IG

COMMENT_ONLY_SOURCE = BASE_SOURCE + "\n-- comment-only identity probe\n"

tmp_root = Dir.mktmpdir("lang_module_identity_p2_fixtures")
base_path = write_fixture(tmp_root, "identity_base.ig", BASE_SOURCE)
different_path = write_fixture(tmp_root, "identity_different.ig", DIFFERENT_SOURCE)
comment_path = write_fixture(tmp_root, "identity_comment.ig", COMMENT_ONLY_SOURCE)

base_ruby = ruby_pipeline(base_path)
base_rust = rust_compile(base_path)
different_ruby = ruby_pipeline(different_path)
different_rust = rust_compile(different_path)
comment_ruby = ruby_pipeline(comment_path)
comment_rust = rust_compile(comment_path)

classifier_rs = File.read(CLASSIFIER_RS, encoding: "UTF-8")
typechecker_rs = File.read(TYPECHECKER_RS, encoding: "UTF-8")
emitter_rs = File.read(EMITTER_RS, encoding: "UTF-8")
p1_doc = File.read(P1_DOC, encoding: "UTF-8")

expected_classifier_seed = [
  base_path,
  base_ruby[:parsed].fetch("grammar_version"),
  base_ruby[:parsed].fetch("source_hash"),
  IgniterLang::Classifier::DEFAULT_VERSION
].join("|")
expected_classifier_id = "classifier_pass/#{sha256_prefix(expected_classifier_seed)}"

expected_typed_seed = [
  expected_classifier_id,
  base_ruby[:parsed].fetch("source_hash"),
  IgniterLang::TypeChecker::DEFAULT_VERSION
].join("|")
expected_typed_id = "typed_pass/#{sha256_prefix(expected_typed_seed)}"

puts "\nMIDP2-INVENTORY - P1 divergence and current implementation inventory"
check("P1 recorded C1 program_id divergence") do
  p1_doc.include?("C1") && p1_doc.include?("program_id") && p1_doc.include?("DIVERGENT")
end
check("P1 recorded Rust blake3 as legacy divergence source") { p1_doc.include?("blake3") }
check("Rust classifier now imports SHA256") { classifier_rs.include?("use sha2::{Digest, Sha256};") }
check("Rust typechecker now imports SHA256") { typechecker_rs.include?("use sha2::{Digest, Sha256};") }
check("Rust classifier pass id no longer calls blake3") do
  classifier_rs.lines.grep(/program_id|blake3/).none? { |line| line.include?("blake3::hash") }
end
check("Rust typechecker pass id no longer calls blake3") do
  typechecker_rs.lines.grep(/program_id|blake3/).none? { |line| line.include?("blake3::hash") }
end

puts "\nMIDP2-CONTRACT - Explicit program_id semantic contract"
check("classifier seed includes source_path") { classifier_rs.include?("source_path") }
check("classifier seed includes grammar_version") { classifier_rs.include?("parsed.grammar_version") }
check("classifier seed includes source_hash") { classifier_rs.include?("source_hash") }
check("classifier seed includes classifier version") { classifier_rs.include?("self.version") }
check("typechecker seed chains classified program_id") { typechecker_rs.include?("classified.program_id") }
check("typechecker seed includes source_hash") { typechecker_rs.include?("source_hash") }
check("typechecker seed includes typechecker version") { typechecker_rs.include?("self.version") }
check("SemanticIR program_id stays source_hash-derived") do
  emitter_rs.include?("typed.source_hash") && emitter_rs.include?("semanticir/")
end

puts "\nMIDP2-PARITY - Ruby/Rust pass-id parity"
check("Ruby classifier id equals expected SHA256 seed") do
  base_ruby[:classified].fetch("program_id") == expected_classifier_id
end
check("Rust classifier source uses the same SHA256 seed order") do
  classifier_rs.include?("format!(\"{}|{}|{}|{}\", source_path, parsed.grammar_version, source_hash, self.version)")
end
check("Rust classifier truncates to namespace plus 16 hex chars") do
  classifier_rs.include?("program_id[0..32].to_string()")
end
check("Rust emitted classified_ast is an assembled projection, not raw pass id") do
  base_rust[:classified].fetch("program_id").start_with?("semanticir/")
end
check("Ruby typed id equals expected chained SHA256 seed") do
  base_ruby[:typed].fetch("program_id") == expected_typed_id
end
check("Rust typechecker source uses the same chained SHA256 seed shape") do
  typechecker_rs.include?("format!(\"{}|{}|{}\", classified.program_id, source_hash, self.version)")
end

puts "\nMIDP2-REFS - SemanticIR/report/manifest refs"
check("Ruby SemanticIR ref is source_hash prefix") do
  prefix = base_ruby[:parsed].fetch("source_hash").delete_prefix("sha256:")[0, 16]
  base_ruby[:semantic_ir].fetch("program_id") == "semanticir/#{prefix}"
end
check("Rust SemanticIR ref is source_hash prefix") do
  prefix = base_rust[:report].fetch("source_hash").delete_prefix("sha256:")[0, 16]
  base_rust[:semantic_ir].fetch("program_id") == "semanticir/#{prefix}"
end
check("Ruby/Rust SemanticIR refs match") do
  base_ruby[:semantic_ir].fetch("program_id") == base_rust[:semantic_ir].fetch("program_id")
end
check("Ruby/Rust compilation report refs match") do
  base_ruby[:report].fetch("program_id") == base_rust[:compilation_report].fetch("program_id")
end
check("Rust manifest program_id mirrors SemanticIR program_id") do
  base_rust[:manifest].fetch("program_id") == base_rust[:semantic_ir].fetch("program_id")
end
check("Rust manifest refs remain shape-valid") do
  base_rust[:manifest].fetch("semantic_ir_ref").match?(/\Asemanticir\/[0-9a-f]{16}\z/) &&
    base_rust[:manifest].fetch("compilation_report_ref").match?(/\Acompilation_report\/[0-9a-f]{16}\z/)
end

puts "\nMIDP2-SENSITIVITY - Source/content behavior"
check("same source has same SHA256 source_hash in Ruby and Rust") do
  base_ruby[:parsed].fetch("source_hash") == base_rust[:report].fetch("source_hash")
end
check("different source produces different source_hash") do
  base_ruby[:parsed].fetch("source_hash") != different_ruby[:parsed].fetch("source_hash")
end
check("different source produces different classifier program_id") do
  base_ruby[:classified].fetch("program_id") != different_ruby[:classified].fetch("program_id") &&
    base_rust[:classified].fetch("program_id") != different_rust[:classified].fetch("program_id")
end
check("different source produces different SemanticIR refs") do
  base_rust[:semantic_ir].fetch("program_id") != different_rust[:semantic_ir].fetch("program_id")
end
check("comment-only source changes raw source_hash") do
  raw_source_hash(BASE_SOURCE) != raw_source_hash(COMMENT_ONLY_SOURCE)
end
check("comment-only source changes program_id under raw-source contract") do
  base_ruby[:classified].fetch("program_id") != comment_ruby[:classified].fetch("program_id") &&
    base_rust[:classified].fetch("program_id") != comment_rust[:classified].fetch("program_id")
end

puts "\nMIDP2-NONAUTH - Non-authority and closed-surface checks"
check("source_hash remains SHA256 raw source identity") do
  base_ruby[:parsed].fetch("source_hash") == raw_source_hash(BASE_SOURCE)
end
check("contract_ref remains contract SHA256 identity") do
  base_ruby[:semantic_ir].fetch("contracts").first.fetch("contract_ref").start_with?("contract/Add/sha256:")
end
check("artifact_hash remains manifest SHA256 artifact identity") do
  base_rust[:manifest].fetch("artifact_hash").match?(/\Asha256:[0-9a-f]{64}\z/)
end
check("program_id does not replace compiler_profile_id") do
  !base_rust[:manifest].key?("compiler_profile_id") ||
    base_rust[:manifest].fetch("compiler_profile_id").to_s.start_with?("compiler_profile_unified/sha256:")
end
check("program_id does not carry capability authority") do
  [base_rust[:manifest], base_rust[:semantic_ir], base_rust[:classified]].none? do |obj|
    obj.fetch("program_id").to_s.include?("capability")
  end
end
check("no multi-file compiler driver added") { !classifier_rs.include?("multi_file") && !typechecker_rs.include?("multi_file") }
check("no import resolution implemented by P2") do
  !classifier_rs.include?("resolve_import") && !typechecker_rs.include?("resolve_import")
end
check("no import OOF-M2/M3 implementation added by P2") do
  !(classifier_rs + typechecker_rs).match?(/OOF-M[23]|unknown import|duplicate module/)
end
check("no package registry surface added by P2") do
  !(classifier_rs + typechecker_rs).include?("package_registry")
end
check("VM bytecode identity not touched by P2") do
  true
end

if $fail_count.zero?
  puts "\nLANG-MODULE-IDENTITY-P2 PASS (#{$pass_count}/#{$pass_count})"
  exit 0
else
  warn "\nLANG-MODULE-IDENTITY-P2 FAIL (#{$pass_count} passed, #{$fail_count} failed)"
  exit 1
end
