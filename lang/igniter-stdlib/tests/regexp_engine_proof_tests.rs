//! LAB-STDLIB-REGEXP-P2 — proof-local regexp engine semantics (NOT a stdlib surface).
//!
//! This file proves the candidate `stdlib.regexp` v0 semantics chosen in P1, over Rust's linear-time
//! `regex` crate, BEFORE any compiler/VM wiring. The adapter (`RegexEngine` trait + `RegexCrateEngine`)
//! lives entirely in this test — `regex` is a DEV dependency, so nothing here is reachable from `.ig`
//! programs or the published library. Pure, deterministic, no fs/net/global state.
//!
//! Locked v0 surface (proven below): `matches(text,pattern) -> Bool`,
//! `capture(text,pattern,index) -> Option<String>`. `captures` is proven but RECOMMENDED DEFERRED
//! (see `captures_groups_only_is_ambiguous_recommend_defer`).

use regex::Regex;

#[derive(Debug, PartialEq, Eq)]
enum RegexError {
    /// Pattern failed to compile (invalid syntax, or a rejected feature like lookaround/backref).
    InvalidPattern(String),
}

/// The candidate v0 engine seam. A future richer engine could implement this same trait without
/// changing the `.ig`-facing surface (P1 §2). v0 ships only `RegexCrateEngine`.
trait RegexEngine {
    fn matches(&self, text: &str, pattern: &str) -> Result<bool, RegexError>;
    fn capture(&self, text: &str, pattern: &str, index: usize) -> Result<Option<String>, RegexError>;
    fn captures(&self, text: &str, pattern: &str) -> Result<Vec<String>, RegexError>;
}

struct RegexCrateEngine;

impl RegexCrateEngine {
    fn compile(pattern: &str) -> Result<Regex, RegexError> {
        // Rust `regex` is linear-time (no backtracking) and rejects lookaround/backrefs at COMPILE
        // time — so unsupported features surface as InvalidPattern here, never as a silent mismatch.
        Regex::new(pattern).map_err(|e| RegexError::InvalidPattern(e.to_string()))
    }
}

impl RegexEngine for RegexCrateEngine {
    /// true iff the pattern matches anywhere in `text`. The author anchors with `^…$` — we never
    /// secretly anchor.
    fn matches(&self, text: &str, pattern: &str) -> Result<bool, RegexError> {
        Ok(Self::compile(pattern)?.is_match(text))
    }

    /// `index 0` = the whole match; `index >= 1` = that capture group. Out-of-range OR an optional
    /// group that did not participate → `Ok(None)`. No match → `Ok(None)`. Returns the matched
    /// SUBSTRING (never a byte/rune offset).
    fn capture(&self, text: &str, pattern: &str, index: usize) -> Result<Option<String>, RegexError> {
        let re = Self::compile(pattern)?;
        Ok(re
            .captures(text)
            .and_then(|c| c.get(index))
            .map(|m| m.as_str().to_string()))
    }

    /// Groups ONLY (`1..n`), since `capture(_, _, 0)` already covers the whole match. An optional
    /// group that did not participate is rendered as `""` — this loss of "did-it-match" information
    /// is exactly why the proof recommends DEFERRING `captures` in favor of positional `capture`.
    fn captures(&self, text: &str, pattern: &str) -> Result<Vec<String>, RegexError> {
        let re = Self::compile(pattern)?;
        Ok(match re.captures(text) {
            None => Vec::new(),
            Some(c) => (1..c.len())
                .map(|i| c.get(i).map(|m| m.as_str().to_string()).unwrap_or_default())
                .collect(),
        })
    }
}

const E: RegexCrateEngine = RegexCrateEngine;

// ── core behavior ────────────────────────────────────────────────────────────────────────────────

#[test]
fn matches_anchored_and_unanchored() {
    assert_eq!(E.matches("/todos/42", "^/todos/([0-9]+)$"), Ok(true));
    assert_eq!(E.matches("/todos/x", "^/todos/([0-9]+)$"), Ok(false));
    // unanchored matches anywhere — explicit, not secretly anchored.
    assert_eq!(E.matches("abc123", "[0-9]+"), Ok(true));
    assert_eq!(E.matches("abc", "[0-9]+"), Ok(false));
}

#[test]
fn capture_index_semantics() {
    let p = "^/todos/([0-9]+)$";
    assert_eq!(E.capture("/todos/42", p, 0), Ok(Some("/todos/42".to_string()))); // whole match
    assert_eq!(E.capture("/todos/42", p, 1), Ok(Some("42".to_string()))); // group 1
    assert_eq!(E.capture("/todos/42", p, 2), Ok(None)); // out-of-range → None
    assert_eq!(E.capture("/todos/x", p, 1), Ok(None)); // no match → None
    // optional group that did not participate → None.
    assert_eq!(E.capture("ab", "^a(x)?b$", 1), Ok(None));
    assert_eq!(E.capture("axb", "^a(x)?b$", 1), Ok(Some("x".to_string())));
}

// ── IgWeb route pressure ─────────────────────────────────────────────────────────────────────────

#[test]
fn route_id_extraction() {
    assert_eq!(E.capture("/todos/42", "^/todos/([0-9]+)$", 1), Ok(Some("42".into())));
    assert_eq!(E.capture("/todos/42/done", "^/todos/([0-9]+)/done$", 1), Ok(Some("42".into())));
}

#[test]
fn route_nested_middle_param_extraction() {
    // The decisive win: middle-param capture that split+last+nth CANNOT do (WR-P04 / DX-SHAPE-P2 fx2).
    let p = "^/accounts/([0-9]+)/todos/([0-9]+)$";
    assert_eq!(E.capture("/accounts/7/todos/42", p, 1), Ok(Some("7".into()))); // account_id
    assert_eq!(E.capture("/accounts/7/todos/42", p, 2), Ok(Some("42".into()))); // todo_id
}

#[test]
fn route_webhook_vendor_and_mismatch_is_false_not_panic() {
    assert_eq!(E.capture("/webhooks/callrail", "^/webhooks/([a-z0-9_-]+)$", 1), Ok(Some("callrail".into())));
    // a mismatch is a clean false / None — never a panic.
    assert_eq!(E.matches("/nope", "^/webhooks/([a-z0-9_-]+)$"), Ok(false));
    assert_eq!(E.capture("/nope", "^/webhooks/([a-z0-9_-]+)$", 1), Ok(None));
}

// ── validation / extraction pressure ───────────────────────────────────────────────────────────

#[test]
fn validation_pressure() {
    let email = r"^[^@\s]+@[^@\s]+\.[^@\s]+$";
    assert_eq!(E.matches("ada@example.test", email), Ok(true));
    assert_eq!(E.matches("not-an-email", email), Ok(false));

    let uuid = r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$";
    assert_eq!(E.matches("550e8400-e29b-41d4-a716-446655440000", uuid), Ok(true));
    assert_eq!(E.matches("550e8400", uuid), Ok(false));

    let phone = r"^\+?[0-9][0-9 .-]{6,}$";
    assert_eq!(E.matches("+1 555-0100", phone), Ok(true));
    assert_eq!(E.matches("call-me", phone), Ok(false));

    // extract a 5-digit token from a larger string.
    assert_eq!(E.capture("zip is 90210 today", r"([0-9]{5})", 1), Ok(Some("90210".into())));
}

// ── Unicode / text policy ──────────────────────────────────────────────────────────────────────

#[test]
fn unicode_capture_is_valid_utf8_substring_not_offset() {
    // Unicode-mode `.` captures the cyrillic segment; we return the SUBSTRING, never an offset.
    let got = E.capture("/todos/київ", "^/todos/(.+)$", 1).unwrap().unwrap();
    assert_eq!(got, "київ");
    assert_eq!(got.chars().count(), 4, "rune-correct substring (4 scalars), valid UTF-8");
    // The API exposes no byte/rune/grapheme offsets at all — only matched substrings.
}

// ── safety / rejected engine features ────────────────────────────────────────────────────────────

#[test]
fn lookaround_and_backrefs_are_invalid_pattern() {
    // Rust `regex` rejects lookaround and backreferences at compile time (a SAFETY feature: it keeps
    // search linear-time). They must surface as InvalidPattern, never as a silent mismatch.
    assert!(matches!(E.matches("foobar", "foo(?=bar)"), Err(RegexError::InvalidPattern(_))));
    assert!(matches!(E.matches("aa", r"(a)\1"), Err(RegexError::InvalidPattern(_))));
}

#[test]
fn invalid_syntax_returns_err_never_false_or_none() {
    for bad in ["(", "[", "a{2,1}", "*"] {
        assert!(matches!(E.matches("x", bad), Err(RegexError::InvalidPattern(_))), "pattern {bad:?} must Err");
        assert!(matches!(E.capture("x", bad, 0), Err(RegexError::InvalidPattern(_))), "pattern {bad:?} must Err");
    }
}

#[test]
fn deterministic_pure_repeatable() {
    // pure function of (text, pattern): identical calls yield identical results.
    let a = E.capture("/accounts/7/todos/42", "^/accounts/([0-9]+)/todos/([0-9]+)$", 2);
    let b = E.capture("/accounts/7/todos/42", "^/accounts/([0-9]+)/todos/([0-9]+)$", 2);
    assert_eq!(a, b);
    assert_eq!(a, Ok(Some("42".into())));
}

// ── captures: proven, but recommended DEFERRED ────────────────────────────────────────────────────

#[test]
fn captures_groups_only_is_ambiguous_recommend_defer() {
    // groups-only (1..n): for a fully-matched pattern this is fine…
    assert_eq!(
        E.captures("/accounts/7/todos/42", "^/accounts/([0-9]+)/todos/([0-9]+)$"),
        Ok(vec!["7".to_string(), "42".to_string()])
    );
    // …but an optional unmatched group renders as "" — INDISTINGUISHABLE from a genuine empty match.
    // This loss of information is why v0 should ship positional `capture` (Option) and DEFER `captures`.
    assert_eq!(E.captures("ab", "^a(x)?(b)$"), Ok(vec!["".to_string(), "b".to_string()]));
    // no match → empty vec.
    assert_eq!(E.captures("zzz", "^a(x)?(b)$"), Ok(Vec::new()));
}
