-- stdlib/core/result.ig
-- Declarative signatures for monadic Result operations

module stdlib.core.Result

def ok(v: T) -> Result[T, E]
def err(e: E) -> Result[T, E]
def is_ok(res: Result[T, E]) -> Bool
def is_err(res: Result[T, E]) -> Bool
def ok?(res: Result[T, E]) -> Bool
def err?(res: Result[T, E]) -> Bool
def map(res: Result[T, E], mapper: (T) -> U) -> Result[U, E]
def flat_map(res: Result[T, E], mapper: (T) -> Result[U, E]) -> Result[U, E]
def and_then(res: Result[T, E], mapper: (T) -> Result[U, E]) -> Result[U, E]
def unwrap_or(res: Result[T, E], fallback: T) -> T
def unwrap(res: Result[T, E]) -> T
def try_catch(res: Result[T, E], handler: (E) -> T) -> T
def propagate(res: Result[T, E]) -> T
def validate(val: T, predicate: (T) -> Bool, error: E) -> Result[T, E]
