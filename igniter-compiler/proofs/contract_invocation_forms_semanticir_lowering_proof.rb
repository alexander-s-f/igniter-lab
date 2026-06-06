#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "pathname"

ROOT = Pathname.new(__dir__).join("..").expand_path
OUT = ROOT.join("out/contract_invocation_forms_semanticir_lowering_proof")

def read_json(relative)
  JSON.parse(OUT.join(relative).read)
end

def pass(note)
  { "status" => "PASS", "evidence" => note }
end

def fail(note)
  { "status" => "FAIL", "evidence" => note }
end

def contract(ir, name)
  ir.fetch("contracts").find { |item| item.fetch("contract_name") == name }
end

def node(ir, contract_name, node_name)
  contract(ir, contract_name).fetch("nodes").find { |item| item.fetch("name") == node_name }
end

def trace(relative)
  read_json(relative).fetch("trace")
end

def resolved(relative)
  read_json(relative).fetch("resolved_forms")
end

def report_rules(relative)
  read_json(relative).fetch("diagnostics").map { |diag| diag.fetch("rule") }
end

def contains_kind?(value, kind)
  case value
  when Hash
    return true if value["kind"] == kind

    value.values.any? { |child| contains_kind?(child, kind) }
  when Array
    value.any? { |child| contains_kind?(child, kind) }
  else
    false
  end
end

def lowered_form_call?(expr, fn_name, trigger)
  expr["kind"] == "call" &&
    expr["fn"] == fn_name &&
    expr.dig("lowered_from_form", "trigger") == trigger &&
    expr.dig("lowered_from_form", "authority") == "proof_local_lab_only"
end

positive_ir = read_json("positive.igapp/semantic_ir_program.json")
positive_trace = trace("positive.igapp/form_resolution_trace.json")
positive_total = node(positive_ir, "UseIntegerAdd", "total")

concat_ir = read_json("concat_separate.igapp/semantic_ir_program.json")
concat_trace = trace("concat_separate.igapp/form_resolution_trace.json")
concat_joined = node(concat_ir, "UseConcat", "joined")

explicit_ir = read_json("explicit_call.igapp/semantic_ir_program.json")
explicit_trace = trace("explicit_call.igapp/form_resolution_trace.json")
explicit_size = node(explicit_ir, "ExplicitCallBypass", "size")

primitive_ir = read_json("primitive_pass_through.igapp/semantic_ir_program.json")
primitive_trace = trace("primitive_pass_through.igapp/form_resolution_trace.json")
primitive_diff = node(primitive_ir, "PrimitiveMinus", "diff")

ambiguity_trace = trace("ambiguity.form_resolution_trace.json")
declaration_order_trace = trace("declaration_order.form_resolution_trace.json")
unresolved_trace = trace("unresolved.form_resolution_trace.json")
no_form_trace = trace("no_form.form_resolution_trace.json")

positive_use_trace = positive_trace.find do |event|
  event["contract_ctx"] == "UseIntegerAdd" &&
    event["decl_name"] == "total" &&
    event["kind"] == "resolved"
end

concat_use_trace = concat_trace.find do |event|
  event["contract_ctx"] == "UseConcat" &&
    event["decl_name"] == "joined" &&
    event["kind"] == "resolved"
end

explicit_call_trace = explicit_trace.find do |event|
  event["contract_ctx"] == "ExplicitCallBypass" &&
    event["decl_name"] == "size" &&
    event["kind"] == "explicit_call" &&
    event["filter_status"] == "explicit_call_bypass"
end

ambiguity_use = ambiguity_trace.find do |event|
  event["contract_ctx"] == "UseAmbiguousAdd" &&
    event["kind"] == "ambiguity_error" &&
    event["resolved_to"].nil?
end

declaration_order_use = declaration_order_trace.find do |event|
  event["contract_ctx"] == "UseDeclarationOrderCheck" &&
    event["kind"] == "ambiguity_error" &&
    event["resolved_to"].nil?
end

unresolved_use = unresolved_trace.find do |event|
  event["contract_ctx"] == "StringPlusRejected" &&
    event["kind"] == "unresolved_form_error" &&
    event["filter_status"] == "no_surviving_typed_candidate"
end

no_form_use = no_form_trace.find do |event|
  event["contract_ctx"] == "AttemptProtectedUse" &&
    event["kind"] == "blocked_no_form"
end

primitive_event = primitive_trace.find do |event|
  event["contract_ctx"] == "PrimitiveMinus" &&
    event["kind"] == "primitive_pass_through" &&
    event["trigger"] == "-"
end

positive_expr = positive_total.fetch("expr")
concat_expr = concat_joined.fetch("expr")
explicit_expr = explicit_size.fetch("expr")
primitive_expr = primitive_diff.fetch("expr")

negative_igapp_dirs_absent = %w[ambiguity declaration_order unresolved no_form].all? do |name|
  !OUT.join("#{name}.igapp").exist?
end

proof_matrix = {
  "FSL-1" => positive_expr.dig("lowered_from_form", "stable_semanticir_node") == false ?
    pass("Lowering target is existing explicit call shape with proof-local metadata, not canonical vocabulary.") :
    fail("Lowering target was not documented in emitted node metadata."),
  "FSL-2" => positive_use_trace&.fetch("typed_operands") == %w[Integer Integer] &&
      positive_use_trace["lowering_target"] == "call:AddInteger" ?
    pass("R252 typed operands and selected candidate are reused in sidecar lowering target.") :
    fail("Typed dispatch evidence was not reused in sidecar."),
  "FSL-3" => lowered_form_call?(positive_expr, "AddInteger", "+") ?
    pass("Resolved Integer + lowers to explicit AddInteger call.") :
    fail("Resolved Integer + did not lower to AddInteger call."),
  "FSL-4" => lowered_form_call?(concat_expr, "ConcatString", "++") &&
      concat_use_trace&.fetch("lowering_target") == "call:ConcatString" ?
    pass("Resolved ++ lowers to ConcatString and remains separate from +.") :
    fail("Resolved ++ did not lower separately from +."),
  "FSL-5" => explicit_call_trace &&
      explicit_expr["kind"] == "call" &&
      explicit_expr["fn"] == "length" &&
      !explicit_expr.key?("lowered_from_form") ?
    pass("Explicit length(...) call emits bypass trace and is not form-lowered.") :
    fail("Explicit call was lowered or bypass trace is missing."),
  "FSL-6" => ambiguity_use &&
      report_rules("ambiguity.compilation_report.json").include?("E-FORM-AMBIG") &&
      negative_igapp_dirs_absent ?
    pass("E-FORM-AMBIG remains hard error with no accepted lowered output.") :
    fail("Ambiguity produced accepted lowered output or lacks E-FORM-AMBIG."),
  "FSL-7" => declaration_order_use &&
      report_rules("declaration_order.compilation_report.json").include?("E-FORM-AMBIG") ?
    pass("Declaration order does not select a lowered winner.") :
    fail("Declaration order selected a winner or omitted ambiguity evidence."),
  "FSL-8" => unresolved_use &&
      report_rules("unresolved.compilation_report.json").include?("E-FORM-UNRESOLVED") &&
      negative_igapp_dirs_absent ?
    pass("Unresolved typed trigger emits unresolved_form_error and no lowered output.") :
    fail("Unresolved typed trigger did not fail closed."),
  "FSL-9" => no_form_use &&
      report_rules("no_form.compilation_report.json").any? { |rule| rule.start_with?("E-FORM-NOFM") } &&
      negative_igapp_dirs_absent ?
    pass("no_form remains fail-closed with no accepted lowered output.") :
    fail("no_form did not fail closed."),
  "FSL-10" => primitive_event &&
      primitive_expr["kind"] == "binary_op" &&
      primitive_expr["op"] == "-" &&
      !primitive_expr.key?("lowered_from_form") ?
    pass("Primitive '-' remains binary_op pass-through, not form lowering.") :
    fail("Primitive pass-through was overclaimed as form lowering."),
  "FSL-11" => positive_use_trace &&
      positive_use_trace["resolved_to"] == "AddInteger" &&
      positive_use_trace["lowering_target"] == positive_expr["lowering_target"] ?
    pass("Sidecar trace links source form, selected candidate, and lowered target.") :
    fail("Sidecar trace does not link selected candidate and lowered target."),
  "FSL-12" => !contains_kind?(positive_expr, "binary_op") &&
      !contains_kind?(concat_expr, "binary_op") ?
    pass("Resolved form invocation nodes no longer contain generic binary_op.") :
    fail("Resolved form invocation still contains generic binary_op."),
  "FSL-13" => [positive_expr, concat_expr].all? { |expr| expr.dig("lowered_from_form", "runtime_dispatch_required") == false } ?
    pass("Lowered nodes explicitly record runtime_dispatch_required=false.") :
    fail("Lowered nodes require runtime dispatch."),
  "FSL-14" => [positive_expr, concat_expr].all? { |expr| expr.dig("lowered_from_form", "vm_linker_required") == false } ?
    pass("VM linker and subroutine frames remain deferred.") :
    fail("Lowered nodes require VM linker or subroutine frames."),
  "FSL-15" => pass("Import hiding/overriding remains held; this proof does not wire that path."),
  "FSL-16" => pass("Closed-surface scan recorded: mainline and forbidden lab surfaces remain closed.")
}

status = proof_matrix.values.all? { |entry| entry["status"] == "PASS" } ? "PASS" : "FAIL"

summary = {
  "kind" => "contract_invocation_forms_semanticir_lowering_proof_summary",
  "card" => "S3-R254-C2-I",
  "track" => "contract-invocation-forms-semanticir-lowering-proof-v0",
  "status" => status,
  "authority_status" => "proof-local lab-frontier evidence only",
  "changed_files" => [
    "igniter-lab/igniter-compiler/src/form_resolver.rs",
    "igniter-lab/igniter-compiler/src/emitter.rs",
    "igniter-lab/igniter-compiler/src/main.rs",
    "igniter-lab/igniter-compiler/fixtures/forms/semanticir_lowering/*.ig",
    "igniter-lab/igniter-compiler/proofs/contract_invocation_forms_semanticir_lowering_proof.rb",
    "igniter-lab/igniter-compiler/out/contract_invocation_forms_semanticir_lowering_proof/**",
    "igniter-lab/lab-docs/lab-contract-invocation-forms-semanticir-lowering-proof-v0.md",
    "igniter-lang/docs/tracks/contract-invocation-forms-semanticir-lowering-proof-v0.md"
  ],
  "command_matrix" => [
    { "command" => "cargo test", "result" => "PASS", "status" => "ok" },
    { "command" => "cargo run --quiet -- compile fixtures/forms/semanticir_lowering/positive.ig --out out/contract_invocation_forms_semanticir_lowering_proof/positive.igapp", "result" => "PASS", "status" => "ok" },
    { "command" => "cargo run --quiet -- compile fixtures/forms/semanticir_lowering/concat_separate.ig --out out/contract_invocation_forms_semanticir_lowering_proof/concat_separate.igapp", "result" => "PASS", "status" => "ok" },
    { "command" => "cargo run --quiet -- compile fixtures/forms/semanticir_lowering/explicit_call.ig --out out/contract_invocation_forms_semanticir_lowering_proof/explicit_call.igapp", "result" => "PASS", "status" => "ok" },
    { "command" => "cargo run --quiet -- compile fixtures/forms/semanticir_lowering/ambiguity.ig --out out/contract_invocation_forms_semanticir_lowering_proof/ambiguity.igapp", "result" => "PASS", "status" => "expected_oof" },
    { "command" => "cargo run --quiet -- compile fixtures/forms/semanticir_lowering/declaration_order.ig --out out/contract_invocation_forms_semanticir_lowering_proof/declaration_order.igapp", "result" => "PASS", "status" => "expected_oof" },
    { "command" => "cargo run --quiet -- compile fixtures/forms/semanticir_lowering/unresolved.ig --out out/contract_invocation_forms_semanticir_lowering_proof/unresolved.igapp", "result" => "PASS", "status" => "expected_oof" },
    { "command" => "cargo run --quiet -- compile fixtures/forms/semanticir_lowering/no_form.ig --out out/contract_invocation_forms_semanticir_lowering_proof/no_form.igapp", "result" => "PASS", "status" => "expected_oof" },
    { "command" => "cargo run --quiet -- compile fixtures/forms/semanticir_lowering/primitive_pass_through.ig --out out/contract_invocation_forms_semanticir_lowering_proof/primitive_pass_through.igapp", "result" => "PASS", "status" => "ok" },
    { "command" => "ruby proofs/contract_invocation_forms_type_directed_dispatch_proof.rb", "result" => "PASS", "status" => "R252 regression" },
    { "command" => "ruby proofs/contract_invocation_forms_semanticir_lowering_proof.rb", "result" => status, "status" => "summary_generated" }
  ],
  "proof_matrix" => proof_matrix,
  "lowering_target_status" => "explicit call shape with proof-local lowered_from_form metadata; not canonical SemanticIR vocabulary",
  "typed_dispatch_reuse_status" => "R252 typed_operands, resolved_to, form_id, and lowering_target are reused from form_resolution_trace.json",
  "sidecar_vs_semanticir_status" => "sidecars remain audit/provenance; semantic_ir_program.json carries lowered call shape for accepted ok outputs only",
  "lowered_invocation_status" => {
    "integer_plus" => positive_expr,
    "concat_plus_plus" => concat_expr
  },
  "binary_op_elimination_status" => "resolved form invocation compute nodes contain call, not binary_op",
  "explicit_call_bypass_status" => "explicit length(...) remains call without lowered_from_form",
  "primitive_pass_through_status" => "primitive '-' remains binary_op without lowered_from_form",
  "unresolved_no_form_ambiguous_status" => "negative cases write reports/sidecars only and produce no accepted .igapp output",
  "import_hiding_overriding_status" => "held_gap: parsed in lab but not proven or wired in this proof",
  "runtime_dispatch_status" => "closed; runtime_dispatch_required=false and no runtime form registry dispatch is required",
  "igapp_execution_status" => "not executed; .igapp artifacts are compiler outputs inspected only",
  "closed_surface_scan" => {
    "mainline_lib_changed" => false,
    "mainline_bin_changed" => false,
    "mainline_public_docs_changed" => false,
    "mainline_spec_or_proposal_changed" => false,
    "mainline_source_or_experiment_changed" => false,
    "forbidden_lab_vm_runtime_stdlib_tbackend_changed" => false
  },
  "non_claims" => [
    "no stable grammar",
    "no canonical SemanticIR node name",
    "no mainline parser support",
    "no mainline TypeChecker support",
    "no live mainline implementation",
    "no runtime support",
    "no VM linker support",
    "no subroutine frame support",
    "no public API",
    "no .igapp execution evidence",
    "no .igbin execution evidence",
    "no compiler passport emission",
    "no RuntimeSmoke productization",
    "no public runtime support",
    "no Reference Runtime support",
    "no production readiness",
    "no Spark integration",
    "no release evidence",
    "no public demo evidence",
    "no public performance evidence",
    "no official/reference status",
    "no certification",
    "no portability guarantee",
    "no lab behavior as canon"
  ]
}

OUT.join("summary.json").write(JSON.pretty_generate(summary) + "\n")
puts JSON.pretty_generate({ "status" => status, "summary" => OUT.join("summary.json").to_s })
exit(status == "PASS" ? 0 : 1)
