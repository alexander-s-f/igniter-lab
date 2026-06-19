-- add.ig
-- Canonical CORE contract for Add
-- Compiler acceptance target: fixtures/add.igapp/

module Lang.Examples.Add

contract Add {
  input  a: Integer
  input  b: Integer

  compute sum = a + b

  output sum: Integer
}
