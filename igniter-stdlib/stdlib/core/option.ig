-- stdlib/core/option.ig
-- Declarative signatures for monadic Option operations

module stdlib.core.Option

def some(v: T) -> Option[T]
def none() -> Option[T]
def is_some(opt: Option[T]) -> Bool
def is_none(opt: Option[T]) -> Bool
def some?(opt: Option[T]) -> Bool
def none?(opt: Option[T]) -> Bool
def or_else(opt: Option[T], fallback: T) -> T
def unwrap_or(opt: Option[T], fallback: T) -> T
def map(opt: Option[T], mapper: (T) -> U) -> Option[U]
def flat_map(opt: Option[T], mapper: (T) -> Option[U]) -> Option[U]
def and_then(opt: Option[T], mapper: (T) -> Option[U]) -> Option[U]
