-- positive_forms.ig
-- Proof fixture: P1-P6, P10, P11, P12
--
-- P2: parser is type-blind — all operators below appear as generic BinaryOp/
--     FieldAccess/Call AST nodes in classified_ast.json
-- P10: explicit Call nodes (fn_name=...) bypass form resolution — see
--     "explicit_call" events in form_resolution_trace.json
-- P11: runtime receives only resolved contract names in form_table.json;
--     no runtime form dispatch occurs
-- P12: "+" and "++" are independent triggers; Add owns "+", Concat owns "++"

module Forms.Positive

-- P1: InfixForm declaration ("+" belongs to numeric Add only)
-- P12: "+" is numeric; "++" is concat — separate triggers
contract Add
  form (left) "+" (right)
  priority 5
  associativity :left
{
  input left: Integer
  input right: Integer
  compute result = left + right
  output result: Integer
}

-- P12: "++" is a distinct trigger — no collision with "+"
contract Concat
  form (left) "++" (right)
  priority 4
  associativity :left
{
  input left: Integer
  input right: Integer
  compute result = left + right
  output result: Integer
}

-- PostfixMethodForm (priority 10)
contract Sum
  form (collection) ".sum"
  priority 10
{
  input collection: Integer
  compute result = collection
  output result: Integer
}

-- BlockMethodForm
contract Where
  form (collection) ".where" { (pred) }
  priority 10
{
  input collection: Integer
  input pred: Boolean
  compute result = collection
  output result: Integer
}

-- KeywordBlockForm guard-style (no block)
contract Guard
  form "guard" (condition) "else" (errors)
  priority 1
{
  input condition: Boolean
  input errors: Boolean
  compute result = condition
  output result: Boolean
}

-- P4: "a + b" BinaryOp resolves to Add via form registry trigger "+"
-- P3: Form Registry has 5 entries (Add, Concat, Sum, Where, Guard)
-- P5: form_resolution_trace.json records the "+" resolution event
-- P6: form_table.json lists all registered forms
contract UseAdd {
  input a: Integer
  input b: Integer
  compute total   = a + b
  compute product = a * b
  output total: Integer
}

-- P10: explicit Call nodes bypass form resolution entirely
-- length(s) is a Call node → produces "explicit_call" trace event, NOT form-resolved
-- Even if "length" had a no_form contract, Call syntax is always valid
contract ExplicitCallPath {
  input s: String
  compute char_count = length(s)
  output char_count: Integer
}
