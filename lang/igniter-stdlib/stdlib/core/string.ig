-- stdlib/core/string.ig
-- Declarative signatures for monadic String operations

module stdlib.core.String

def length(s: String) -> Integer
def concat(a: String, b: String) -> String
def trim(s: String) -> String
def split(s: String, sep: String) -> Collection[String]
def contains(s: String, sub: String) -> Bool
def starts_with(s: String, prefix: String) -> Bool
