-- liveness_parser_import_steps.ig
-- LAB-COMPILER-LIVENESS-P4 calibration fixture: parser.parse_import.max_steps
--
-- Exercises parse_import with three import statements to confirm the structural
-- bound: the Igniter lexer merges dotted module paths (A.B.C) into a single
-- Ident token when all characters after dots are uppercase.  As a result,
-- parse_import_max_steps is structurally bounded at:
--
--   0  → no import statements in the file
--   1  → one or more import statements (any path depth, all uppercase-dotted)
--
-- This fixture imports three multi-segment modules to confirm max_steps = 1,
-- not 3 (the loop runs once per import statement, so the maximum across all
-- statements is still 1).
--
-- Expected: parser.parse_import.max_steps = 1, status = ok
-- P4 Finding: counter cannot exceed 1 without lexer changes (see lab doc).

module Lang.Lab.LivenessParserImportSteps

import Lang.Stdlib.Collections
import Lang.Stdlib.Math
import Lang.Stdlib.Types

contract Simple {
  input x: Integer
  compute result = x
  output result: Integer
}
