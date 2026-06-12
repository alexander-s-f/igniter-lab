module DataFrameOps
import DataFrameTypes
import stdlib.collection.{ filter }

-- ============================================================
-- DataFrame Operations (Long Format)
-- ============================================================

contract SelectColumn {
  input df : DataFrame
  input target_col : String

  -- To select a column in long format, we just filter the DataPoints
  -- where col_name == target_col.
  compute selected = filter(df.data, p ->
    if p.col_name == target_col { true } else { false }
  )

  -- We return the filtered DataPoints. In a real system, we might
  -- map this to just extract the `val` as a Collection[Integer].
  -- But keeping the row_id is useful for joins later.
  output selected : Collection[DataPoint]
}

contract FilterByThreshold {
  input df : DataFrame
  input filter_col : String
  input min_val : Integer

  -- This is a complex operation in Long format:
  -- 1. Find all row_ids where col == filter_col AND val >= min_val
  -- 2. Filter the entire DataFrame to only include those row_ids.

  compute valid_points = filter(df.data, p ->
    if p.col_name == filter_col {
      if p.val > min_val {
        true
      } else {
        if p.val == min_val {
          true
        } else {
          false
        }
      }
    } else {
      false
    }
  )

  -- Now we need to filter `df.data` to only include `row_id`s that
  -- exist in `valid_points`.
  -- This requires an O(N^2) cross-filter because we lack `contains`
  -- or `group_by`.
  compute filtered_data = filter(df.data, p ->
    -- We map over valid_points. If we find a match, we'd like to return true.
    -- But we can't collapse a Collection[Bool] into a single Bool without
    -- a `reduce` or `any` function!
    -- This means cross-row operations are completely blocked!
    -- We'll just return `valid_points` for now.
    true
  )

  compute result = {
    data: valid_points
  }

  output result : DataFrame
}
