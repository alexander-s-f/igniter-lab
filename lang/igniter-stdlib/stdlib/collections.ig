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

