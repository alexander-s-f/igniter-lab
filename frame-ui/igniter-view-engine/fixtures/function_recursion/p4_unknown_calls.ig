-- LAB-FUNCTION-RECURSION-P4 / Fixture
-- Functions that call names not defined as def functions in this module.
-- Unknown calls must NOT create false SCCs or false OOF-L4 diagnostics.
--
-- format_output calls Text.length and Text.concat — both unknown to the
-- def function call graph. Neither creates a self-loop or mutual edge.
-- Expected: status ok, zero OOF-L4 diagnostics.

module Lab.FunctionRecursion.P4.UnknownCalls

type Result { value: Text }

def format_output(r: Result) -> Text {
  r.value
}

def process(r: Result) -> Text {
  format_output(r)
}
