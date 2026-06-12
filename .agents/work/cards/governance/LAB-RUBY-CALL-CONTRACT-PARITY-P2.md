# Agent Card: LAB-RUBY-CALL-CONTRACT-PARITY-P2

**Lane:** governance / implementation / Ruby parity  
**Mode:** PLANNING ONLY — no implementation  
**Status:** OPEN  
**Date:** 2026-06-12  
**Depends on:** LAB-RUBY-CALL-CONTRACT-PARITY-P1 (CLOSED 56/56)  
**Conditional on:** LANG-OUTPUT-TYPE-ASSIGNABILITY-P1 state (see Output Gate section)

---

## Goal

Produce a complete, reviewable implementation plan for adding `when "call_contract"` to
the Ruby TypeChecker `infer_call` switch. Plan is bounded to the safe subset established
by P1: Tier 1 literal callee + Tier 2 dynamic callee. No implementation in this card.

---

## TC Insertion Point

**File:** `igniter-lang/lib/igniter_lang/typechecker.rb`  
**Method:** `infer_call` (line 872)  
**Insert before:** the `else` arm at line 914  
**After:** the `when "or_else"` arm (line 911–913)

```ruby
# BEFORE (lines 911–917):
      when "or_else"
        infer_or_else(args, symbol_types, type_errors, type_warnings, node_name)
      else
        type_errors << oof("OOF-TY0", "Unknown function: #{fn}", node_name)
        typed_expr("call", type_ir("Unknown"), [], "fn" => fn, "args" => [])
      end

# AFTER:
      when "or_else"
        infer_or_else(args, symbol_types, type_errors, type_warnings, node_name)
      when "call_contract"
        # LAB-RUBY-CALL-CONTRACT-PARITY-P2
        infer_call_contract(expr, symbol_types, type_errors, type_warnings, node_name)
      else
        type_errors << oof("OOF-TY0", "Unknown function: #{fn}", node_name)
        typed_expr("call", type_ir("Unknown"), [], "fn" => fn, "args" => [])
      end
```

---

## Registry Plan

### Build site

`@call_contract_registry` is built in `typecheck` (line 105), alongside
`@same_module_registry` (line 118). Add at line 119:

```ruby
@call_contract_registry = build_call_contract_registry(classified_program)
```

### `build_call_contract_registry` method

Maps `contract_name → entry hash`. Mirrors `build_contract_registry` in
`igniter-lab/igniter-compiler/src/typechecker.rs` lines 1372–1413.

```ruby
def build_call_contract_registry(classified_program)
  classified_program.fetch("contracts").each_with_object({}) do |contract, reg|
    name    = contract.fetch("name")
    decls   = contract.fetch("declarations")
    inputs  = decls.select { |d| d.fetch("kind") == "input" }
    outputs = decls.select { |d| d.fetch("kind") == "output" }

    single_output_type = outputs.size == 1 ? outputs[0].fetch("type_annotation", nil) : nil
    single_output_name = outputs.size == 1 ? outputs[0].fetch("name") : nil

    reg[name] = {
      "modifier"            => contract.fetch("modifier", "pure"),
      "input_count"         => inputs.size,
      "input_names"         => inputs.map { |d| d.fetch("name") },
      "single_output_type"  => single_output_type,
      "single_output_name"  => single_output_name,
      "contract_name"       => name
    }
  end
end
```

**Separation note:** `@call_contract_registry` is distinct from `@same_module_registry`.
`@same_module_registry` is authoritative for `uses_contract` resolution; do not mutate it.

---

## Current Contract Name

`contract_name_str` is local to `typecheck_contract` (line 291). `infer_call` does not
currently receive it. The clean precedent is `@recur_context` (set at line 347), which
makes per-contract state available to all `infer_*` helpers via instance variable.

**Plan:** Set `@current_contract_name` in `typecheck_contract` before the declarations loop:

```ruby
# in typecheck_contract, after line 291:
@current_contract_name = contract_name_str
```

This mirrors the `@recur_context` pattern and avoids threading an extra param through
`infer_expr → infer_call → infer_call_contract`.

---

## Arg Count / Type Check Plan

`infer_call_contract(expr, symbol_types, type_errors, type_warnings, node_name)`

Steps, mirroring Rust lines 3664–3757:

1. **Empty args guard** — `args.empty?` → OOF-TY0 "call_contract requires at least one argument (contract name as String)"

2. **First-arg type check** — infer `args[0]`, check `type_name(typed_arg_0.resolved_type)`.
   - If not "String" and not "Unknown" → OOF-TY0 "call_contract: first argument must be String (contract name), got {type}"

3. **Tier dispatch** — inspect raw `args[0]`:
   - If `kind == "literal"` and `type_tag == "String"` → **Tier 1** (literal callee)
   - Otherwise → **Tier 2** (dynamic callee)

### Tier 1 — literal callee

`callee_name = args[0].fetch("value")`  
`positional_count = args.size - 1`

Fail-closed checks in order (match Rust precedence at lines 3693–3735):

| # | Condition | Error |
|---|-----------|-------|
| a | `@call_contract_registry[callee_name]` is nil | OOF-TY0 `"call_contract: unknown callee '#{callee_name}' — not found in this module"` |
| b | `entry["modifier"] != "pure"` | OOF-TY0 `"call_contract: callee '#{callee_name}' is not pure (modifier: #{entry["modifier"]}); only pure contracts may be called via call_contract in v0"` |
| c | `callee_name == @current_contract_name` | OOF-TY0 `"call_contract: self-recursion via '#{callee_name}' is closed in v0; use recur() for recursive contracts"` |
| d | `positional_count != entry["input_count"]` | OOF-TY0 `"call_contract: callee '#{callee_name}' expects #{entry["input_count"]} input(s), got #{positional_count}"` |
| ✓ | all pass | resolve output type (see Output Gate) |

On any error: return `typed_expr("call", type_ir("Unknown"), [], "fn" => fn, "args" => [])`

### Tier 2 — dynamic / variable callee

Return `typed_expr("call", type_ir("Unknown"), [], "fn" => fn, "args" => [])` immediately.
No error emitted. This matches Rust lines 3750–3752 and the VM fail-closed guarantee from P9.

---

## Output Type Resolution Plan

**Conditional on LANG-OUTPUT-TYPE-ASSIGNABILITY-P1 state.**

P1 safe path (before LANG-OUTPUT-TYPE-ASSIGNABILITY-P1 is implemented):

```ruby
def resolve_call_contract_output(single_output_type)
  return type_ir("Unknown") if single_output_type.nil?

  # Bare named type (String, Int, Boolean, user Record): resolve directly.
  # Parametric type (Collection[T], Option[T], Map[K,V]): Unknown until
  # LANG-OUTPUT-TYPE-ASSIGNABILITY-P1 structural check is available.
  if single_output_type.is_a?(Hash) && single_output_type.key?("params")
    type_ir("Unknown")   # parametric — deferred, not an error
  else
    type_ir(single_output_type)
  end
end
```

**When LANG-OUTPUT-TYPE-ASSIGNABILITY-P1 lands:** replace the `params` branch with
`structurally_assignable?` recursive check. That upgrade does not require re-opening P2.

---

## Stdlib String Names — Explicitly Out of Scope

P1 census: 34 STDLIB_FORM calls (e.g. `call_contract("append", ...)`,
`call_contract("empty", ...)`).

These fall into the Tier 1 path but must not resolve via `@call_contract_registry`
(stdlib functions are not user contracts). The `@call_contract_registry` is built only
from `classified_program.fetch("contracts")`, which contains user contracts only —
stdlib names will not appear in the registry and will emit OOF-TY0
`"not found in this module"`.

This is **correct and intentional**: stdlib form mis-routing is a user error, not a TC
gap. A dedicated stdlib routing track (separate from call_contract) is the future fix.
No special-casing in the `infer_call_contract` path.

---

## Dynamic Variable Callee — Tier 2 Acceptance Conditions

Tier 2 (`call_contract(name, ...)` where `name` is a Ref or computed expr) returns
`Unknown` with no error. This is accepted in v0 because:

1. VM fail-closed: P9 (LAB-RACK-P9) enforces runtime contract lookup failure → VM halt
2. Output assignability: until LANG-OUTPUT-TYPE-ASSIGNABILITY-P1, Unknown is a safe
   assignment target (no spurious type errors downstream)
3. Shape census: only 1 DYNAMIC call in 156 total (< 1%) — risk surface is minimal

Tier 2 is **not** a correctness acceptance — it is a deferred check with VM safety net.

---

## Proof Matrix for P3

Minimum 50 checks. Suggested distribution:

| Group | Count | Coverage |
|-------|-------|----------|
| Empty args → OOF-TY0 | 2 | zero-arg, empty array |
| First arg not String → OOF-TY0 | 3 | Int, Boolean, Record |
| Unknown callee → OOF-TY0 | 4 | typo, wrong case, stdlib name ("append"), cross-module name |
| Non-pure callee → OOF-TY0 | 3 | recursive, fuel_bounded, event modifier |
| Self-recursion → OOF-TY0 | 2 | exact match, case-sensitive variant |
| Arity mismatch → OOF-TY0 | 4 | 0 args for 1-input, 2 args for 1-input, 0 for 2, 3 for 2 |
| Tier 1 success, bare output | 6 | String, Int, Boolean, user Record, no-output (Unknown), 2-output (Unknown) |
| Tier 1 success, parametric output | 4 | Collection[T], Option[T], Map[K,V], nested parametric |
| Tier 2 dynamic → Unknown, no error | 4 | Ref, BinaryOp, function result, Unknown-typed arg |
| stdlib form (not found) | 4 | "append", "empty", "map", "filter" |
| OOF message parity with Rust | 6 | one per Tier 1 fail-closed case + stdlib + first-arg type |
| Multi-contract module (registry isolation) | 4 | 2 contracts, callee is contract B from A, B from B (self-recursion) |
| Lambda-internal (LAMBDA_INTERNAL shape) | 3 | Tier 1 resolves inside lambda body |
| **Total** | **≥ 50** | |

Proof runner convention: `igniter-lang/experiments/call_contract_parity_p2/verify_lab_ruby_call_contract_parity_p2.rb`  
(mirrors P1 runner path pattern)

---

## Closed

- No implementation in this card
- No dynamic dispatch acceptance (Tier 2 stays Unknown)
- No plugin model
- No VM/runtime changes
- No cross-module resolution (v0: same-module only)
- No stdlib routing (stdlib names → OOF-TY0 "not found in this module", correct)
- No LANG-OUTPUT-TYPE-ASSIGNABILITY-P1 implementation (deferred upgrade path documented)

---

## Next Route

**LAB-RUBY-CALL-CONTRACT-PARITY-P3** — implementation + proof runner (≥ 50 checks).  
TC change: `@call_contract_registry` build + `@current_contract_name` ivar +  
`when "call_contract"` arm + `infer_call_contract` method + `resolve_call_contract_output`.  
Gate: this P2 card approved.
