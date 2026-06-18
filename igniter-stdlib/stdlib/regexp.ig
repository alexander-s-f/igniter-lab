-- stdlib/regexp.ig
-- Linear-time regular-expression operations (LAB-STDLIB-REGEXP-P3).
-- Backed by the Rust `regex` crate: linear-time, Unicode by default, NO lookaround/backrefs.
-- v0 surface is intentionally narrow: `matches` + `capture` (substrings, never offsets).
-- `captures`/`capture_named`/`split_regexp`/`replace_regexp` are deferred (see lab-stdlib-regexp-p2).

module stdlib.regexp

def matches(text: String, pattern: String) -> Bool
def capture(text: String, pattern: String, index: Integer) -> Option[String]
