module SpreadsheetApi
import SpreadsheetTypes
import SpreadsheetEngine

contract RecalculateWorkbook {
  input grid : Grid

  compute evaluated_cells = call_contract("CalculateGrid", grid)

  output evaluated_cells : Collection[CellValue]
}
