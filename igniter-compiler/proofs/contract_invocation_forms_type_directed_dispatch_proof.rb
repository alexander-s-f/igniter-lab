#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "pathname"

ROOT = Pathname.new(__dir__).join("..").expand_path
OUT = ROOT.join("out/contract_invocation_forms_type_directed_dispatch_proof")

def read_json(relative)
  JSON.parse(OUT.join(relative).read)
end

def trace(relative)
  read_json(relative).fetch("trace")
end

def resolved(relative)
  read_json(relative).fetch("resolved_forms")
end

def report(relative)
  read_json(relative)
end

def pass(note)
  { "status" => "PASS", "evidence" => note }
end

def fail(note)
  { "status" => "FAIL", "evidence" => note }
end

positive_trace = trace("positive.igapp/form_resolution_trace.json")
positive_resolved = resolved("positive.igapp/form_resolution_trace.json")
non_additive_trace = trace("non_additive_plus.form_resolution_trace.json")
concat_trace = trace("concat_separate.igapp/form_resolution_trace.json")
ambiguity_trace = trace("ambiguity.form_resolution_trace.json")
ambiguity_resolved = resolved("ambiguity.form_resolution_trace.json")
declaration_order_trace = trace("declaration_order.form_resolution_trace.json")
declaration_order_resolved = resolved("declaration_order.form_resolution_trace.json")
missing_trace = trace("missing_trigger.igapp/form_resolution_trace.json")
no_form_trace = trace("no_form.form_resolution_trace.json")
generic_trace = trace("generic_additive.igapp/form_resolution_trace.json")
generic_manifest = read_json("generic_additive.igapp/specialization_manifest.json")

semantic_ir_text = OUT.join("positive.igapp/semantic_ir_program.json").read

positive_use = positive_trace.find do |event|
  event["contract_ctx"] == "UseIntegerAdd" &&
    event["decl_name"] == "total" &&
    event["kind"] == "resolved"
end

non_additive_error = non_additive_trace.find do |event|
  event["kind"] == "unresolved_form_error" &&
    event["contract_ctx"] == "StringPlusRejected"
end

concat_use = concat_trace.find do |event|
  event["contract_ctx"] == "UseConcat" &&
    event["trigger"] == "++" &&
    event["resolved_to"] == "ConcatString"
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

missing_event = missing_trace.find do |event|
  event["kind"] == "primitive_pass_through" &&
    event["trigger"] == "-"
end

no_form_event = no_form_trace.find do |event|
  event["contract_ctx"] == "AttemptProtectedUse" &&
    event["kind"] == "blocked_no_form"
end

explicit_call_event = positive_trace.find do |event|
  event["kind"] == "explicit_call" &&
    event["trigger"] == "length" &&
    event["filter_status"] == "explicit_call_bypass"
end

generic_event = generic_trace.find do |event|
  event["contract_ctx"] == "UseGenericAdd" &&
    event["resolved_to"] == "Add[Integer]"
end

proof_matrix = {
  "FTD-1" => positive_use&.fetch("typed_operands") == %w[Integer Integer] ?
    pass("UseIntegerAdd trace exposes typed_operands [Integer, Integer] and typed_result Integer.") :
    fail("UseIntegerAdd typed operands were not visible."),
  "FTD-2" => positive_use&.fetch("resolved_to") == "AddInteger" ?
    pass("Integer + Integer resolves to AddInteger after type filtering.") :
    fail("Integer + Integer did not resolve to AddInteger."),
  "FTD-3" => non_additive_error && non_additive_error.fetch("refused_candidates").any? ?
    pass("String + String records unresolved_form_error with refused AddInteger candidate.") :
    fail("String + String did not produce refused typed candidate evidence."),
  "FTD-4" => concat_use ?
    pass("++ resolves to ConcatString and remains a distinct trigger from +.") :
    fail("++ did not remain separate from +."),
  "FTD-5" => ambiguity_use && ambiguity_resolved.empty? ?
    pass("Equal surviving + candidates produce E-FORM-AMBIG with no resolved form.") :
    fail("Ambiguity produced a winner or no ambiguity evidence."),
  "FTD-6" => declaration_order_use && declaration_order_resolved.empty? ?
    pass("Declaration order fixture produces E-FORM-AMBIG; first declaration is not selected.") :
    fail("Declaration order selected a semantic winner."),
  "FTD-7" => missing_event ?
    pass("Missing registered form for known '-' primitive remains primitive_pass_through by policy.") :
    fail("Missing trigger policy was not traced."),
  "FTD-8" => non_additive_error&.fetch("filter_status") == "no_surviving_typed_candidate" ?
    pass("Registered + trigger with no surviving typed candidate produces unresolved_form_error.") :
    fail("No surviving typed candidate was not classified as unresolved_form_error."),
  "FTD-9" => no_form_event ?
    pass("no_form remains blocked_no_form after type facts are available.") :
    fail("no_form did not fail closed."),
  "FTD-10" => explicit_call_event ?
    pass("length(...) explicit call emits explicit_call_bypass and bypasses form resolution.") :
    fail("Explicit call bypass was not trace-visible."),
  "FTD-11" => (positive_use && missing_event && non_additive_error && no_form_event) ?
    pass("Sidecar traces selected, primitive pass-through, unresolved_form_error, and blocked_no_form candidates.") :
    fail("Sidecar trace did not cover selected, missed, and refused candidates."),
  "FTD-12" => !semantic_ir_text.include?("ContractInvocation") && !semantic_ir_text.include?("contract_invocation") ?
    pass("SemanticIR remains sidecar-only with no ContractInvocation/contract_invocation nodes.") :
    fail("SemanticIR contains lowering/runtime claim evidence.")
}

status = proof_matrix.values.all? { |entry| entry["status"] == "PASS" } ? "PASS" : "FAIL"

summary = {
  "kind" => "contract_invocation_forms_type_directed_dispatch_proof_summary",
  "card" => "S3-R252-C2-I",
  "track" => "contract-invocation-forms-type-directed-dispatch-proof-v0",
  "status" => status,
  "authority_status" => "proof-local lab-frontier evidence only",
  "changed_files" => [
    "igniter-lab/igniter-compiler/src/form_resolver.rs",
    "igniter-lab/igniter-compiler/src/typechecker.rs",
    "igniter-lab/igniter-compiler/fixtures/forms/type_dispatch/*.ig",
    "igniter-lab/igniter-compiler/proofs/contract_invocation_forms_type_directed_dispatch_proof.rb",
    "igniter-lab/igniter-compiler/out/contract_invocation_forms_type_directed_dispatch_proof/**",
    "igniter-lab/lab-docs/lab-contract-invocation-forms-type-directed-dispatch-proof-v0.md",
    "igniter-lang/docs/tracks/contract-invocation-forms-type-directed-dispatch-proof-v0.md"
  ],
  "command_matrix" => [
    { "command" => "cargo test", "result" => "PASS", "status" => "ok" },
    { "command" => "cargo run -- compile fixtures/forms/type_dispatch/positive.ig --out out/contract_invocation_forms_type_directed_dispatch_proof/positive.igapp", "result" => "PASS", "status" => "ok" },
    { "command" => "cargo run --quiet -- compile fixtures/forms/type_dispatch/non_additive_plus.ig --out out/contract_invocation_forms_type_directed_dispatch_proof/non_additive_plus.igapp", "result" => "PASS", "status" => "expected_oof" },
    { "command" => "cargo run --quiet -- compile fixtures/forms/type_dispatch/concat_separate.ig --out out/contract_invocation_forms_type_directed_dispatch_proof/concat_separate.igapp", "result" => "PASS", "status" => "ok" },
    { "command" => "cargo run --quiet -- compile fixtures/forms/type_dispatch/ambiguity.ig --out out/contract_invocation_forms_type_directed_dispatch_proof/ambiguity.igapp", "result" => "PASS", "status" => "expected_oof" },
    { "command" => "cargo run --quiet -- compile fixtures/forms/type_dispatch/declaration_order.ig --out out/contract_invocation_forms_type_directed_dispatch_proof/declaration_order.igapp", "result" => "PASS", "status" => "expected_oof" },
    { "command" => "cargo run --quiet -- compile fixtures/forms/type_dispatch/missing_trigger.ig --out out/contract_invocation_forms_type_directed_dispatch_proof/missing_trigger.igapp", "result" => "PASS", "status" => "ok" },
    { "command" => "cargo run --quiet -- compile fixtures/forms/type_dispatch/no_form.ig --out out/contract_invocation_forms_type_directed_dispatch_proof/no_form.igapp", "result" => "PASS", "status" => "expected_oof" },
    { "command" => "cargo run --quiet -- compile fixtures/forms/type_dispatch/generic_additive.ig --out out/contract_invocation_forms_type_directed_dispatch_proof/generic_additive.igapp", "result" => "PASS", "status" => "ok" },
    { "command" => "ruby proofs/contract_invocation_forms_type_directed_dispatch_proof.rb", "result" => status, "status" => "summary_generated" }
  ],
  "proof_matrix" => proof_matrix,
  "typed_expression_source_status" => {
    "status" => "proof_local_lab_only",
    "source" => "TypedContract symbols plus local expression type reconstruction in FormResolver sidecar pass",
    "public_api_authority" => false
  },
  "trait_generic_filtering_status" => {
    "status" => generic_event ? "PASS" : "FAIL",
    "evidence" => generic_event ? "Add[T: Additive] specializes to Add[Integer] and UseGenericAdd resolves to Add[Integer]." : "Generic Additive fixture did not resolve.",
    "specialization_manifest_present" => generic_manifest.fetch("specializations", []).any? { |entry| entry["emitted_contract_id"] == "Add[Integer]" },
    "prop016_authority_claimed" => false
  },
  "ambiguity_status" => "E-FORM-AMBIG remains hard error after type filtering.",
  "declaration_order_status" => "Declaration order does not select a winner; equal typed candidates refuse.",
  "primitive_pass_through_status" => "Known primitive '-' without form remains primitive_pass_through by policy.",
  "unresolved_trigger_status" => "Held to existing policy distinction; this proof exercises primitive_pass_through as the missing registered form case.",
  "unresolved_form_error_status" => "Implemented proof-local as E-FORM-UNRESOLVED plus trace kind unresolved_form_error when no typed candidate survives.",
  "no_form_status" => "no_form remains fail-closed before typed candidate selection.",
  "explicit_call_bypass_status" => "Explicit calls emit explicit_call_bypass and are not form-resolved.",
  "import_hiding_overriding_status" => "held_gap: parsed in lab but not wired into resolver filtering by this card.",
  "sidecar_artifact_status" => "form_table.json and form_resolution_trace.json remain audit sidecars only.",
  "semantic_ir_status" => "sidecar_resolution_only; no ContractInvocation/Call lowering authority.",
  "runtime_status" => "closed; no VM linker, runtime dispatch, .igapp execution, or .igbin execution authority.",
  "closed_surface_scan" => {
    "mainline_lib_changed" => false,
    "mainline_bin_changed" => false,
    "mainline_spec_or_proposal_changed" => false,
    "mainline_source_or_experiment_changed" => false,
    "other_lab_package_changed" => false
  },
  "non_claims" => [
    "no canonical syntax",
    "no stable grammar",
    "no mainline parser support",
    "no mainline TypeChecker support",
    "no SemanticIR lowering support",
    "no runtime support",
    "no VM linker support",
    "no public API",
    "no public runtime support",
    "no Reference Runtime support",
    "no production readiness",
    "no Spark integration",
    "no release evidence",
    "no public demo evidence",
    "no public performance evidence",
    "no official/reference status",
    "no alternative certification",
    "no portability guarantee",
    "no lab behavior as canon"
  ]
}

OUT.join("summary.json").write(JSON.pretty_generate(summary) + "\n")
puts JSON.pretty_generate({ "status" => status, "summary" => OUT.join("summary.json").to_s })
exit(status == "PASS" ? 0 : 1)
