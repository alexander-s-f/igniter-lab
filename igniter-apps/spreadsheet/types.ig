module SpreadsheetTypes

type CellValue {
  kind : Text
  num_val : Float?
  str_val : Text?
}

type Expr {
  kind : Text
  num_val : Float?
  ref_id  : Text?
  left : Expr?
  right : Expr?
}

type Cell {
  id : Text
  ast : Expr
}

type Grid {
  cells : Collection[Cell]
}
