module Forms.Test

-- Contract with InfixForm
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

-- Contract with PostfixMethodForm
contract Sum
  form (collection) ".sum"
  priority 10
{
  input collection: Integer
  compute result = collection
  output result: Integer
}

-- Contract with BlockMethodForm
contract Where
  form (collection) ".where" { (pred) }
  priority 10
{
  input collection: Integer
  input pred: Boolean
  compute result = collection
  output result: Integer
}

-- Contract with KeywordBlockForm
contract Guard
  form "guard" (condition) "else" (errors)
  priority 1
{
  input condition: Boolean
  input errors: Boolean
  compute result = condition
  output result: Boolean
}

-- Contract that USES forms (triggers resolution)
contract UseAdd {
  input a: Integer
  input b: Integer
  compute total = a + b
  compute diff  = a - b
  output total: Integer
}
