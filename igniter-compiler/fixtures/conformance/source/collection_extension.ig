-- collection_extension.ig
-- Conformance fixture verifying find, any, all, and collection concat.

module SparkCRM.CollectionExtensions

type Item {
  id: Integer,
  value: Integer
}

contract CollectionWorkflow {
  input items: Collection[Item]
  input threshold: Integer
  input extra: Collection[Item]

  -- find: first item with value > threshold (returns Option[Item])
  compute found = find(items, i -> i.value > threshold)

  -- any: does any item have value > threshold?
  compute has_any = any(items, i -> i.value > threshold)

  -- all: do all items have value > 0?
  compute all_pos = all(items, i -> i.value > 0)

  -- concat: join items and extra into one collection
  compute merged = concat(items, extra)
  compute merged_count = count(merged)

  output found: Option[Item]
  output has_any: Bool
  output all_pos: Bool
  output merged_count: Integer
}
