-- stdlib/collections.ig
-- Declarative signatures for functional collections pipeline operations

module stdlib.Collections

def range(start: Integer, end: Integer) -> Collection[Integer]
def filter(coll: Collection[T], predicate: (T) -> Bool) -> Collection[T]
def map(coll: Collection[T], mapper: (T) -> U) -> Collection[U]
def fold(coll: Collection[T], initial: U, accumulator: (U, T) -> U) -> U
def first(coll: Collection[T]) -> Option[T]
def last(coll: Collection[T]) -> Option[T]
def sum(coll: Collection[T], field: Symbol) -> Decimal[S]
-- zip: positional pairing into Pair{first, second}. UNEQUAL LENGTHS TRUNCATE to the shorter
-- (deterministic, total — never errors on mismatch). Pair[A,B] field access is typed (.first->A,
-- .second->B). A paired statistic that must not silently drop observations should guard equal length
-- itself (count(a)==count(b)) before zipping. Proven: LAB-STDLIB-COLLECTION-ZIP-PROOF-P2.
def zip(a: Collection[A], b: Collection[B]) -> Collection[Pair[A, B]]
def count(coll: Collection[T]) -> Integer
def avg(coll: Collection[T], field: Symbol) -> Option[T]
def min(coll: Collection[T], field: Symbol) -> Option[T]
def max(coll: Collection[T], field: Symbol) -> Option[T]
def take(coll: Collection[T], n: Integer) -> Collection[T]
def find(coll: Collection[T], predicate: (T) -> Bool) -> Option[T]
def any(coll: Collection[T], predicate: (T) -> Bool) -> Bool
def all(coll: Collection[T], predicate: (T) -> Bool) -> Bool
def concat(a: Collection[T], b: Collection[T]) -> Collection[T]

