module DSAStrings
import DSATypes
import stdlib.collection.{ filter }

-- ============================================================
-- Strings
-- ============================================================

contract CharAt {
  input s : CharString
  input target_idx : Integer

  -- O(N) lookup for a character because strings are mocked
  -- as IndexedElement collections!
  compute matches = filter(s.chars, c ->
    if c.index == target_idx { true } else { false }
  )

  -- We output a Collection of matches because we lack head()
  output matches : Collection[IndexedElement]
}
