# LAB-IGNITER-WEB-RENDER-HTML-OUTPUT-SAFETY-P1

Date: 2026-06-27
Status: DONE
Lane: igniter-lab / web / render-html / foundation-hardening

## Scope

This is lab evidence for the live `frame-ui/igniter-render-html` crate. The card's older
`server/igniter-render-html` anchor was rehomed; no canon `igniter-lang`, server transport,
machine, compiler, VM, stdlib, home-lab, SparkCRM, or private governance files were edited.

## Policy

`safe_url` now keeps the existing allowlist:

- relative references without a recognized scheme
- `http:`
- `https:`

It now fails closed with `RenderHtmlError::UnsafeUrl` for:

- explicit non-allowed schemes such as `javascript:`, `data:`, and `mailto:`
- ASCII control characters anywhere in the trimmed URL, covering browser-strippable
  `java\nscript:`, `java\tscript:`, `java\rscript:`, and C0-prefixed schemes
- protocol-relative URLs such as `//evil.example/x`

The renderer continues to use one explicit escaping helper for text and double-quoted
attribute contexts. It escapes `&`, `<`, `>`, `"`, and `'`. Link hrefs are routed through
`safe_url` and then escaped before insertion into `href="..."`.

## Evidence

Changed files:

- `frame-ui/igniter-render-html/src/lib.rs`
- `frame-ui/igniter-render-html/tests/render_html_tests.rs`
- `.agents/work/cards/lang/LAB-IGNITER-WEB-RENDER-HTML-OUTPUT-SAFETY-P1.md`
- `lab-docs/lang/lab-igniter-web-render-html-output-safety-p1.md`

Tests added:

- `safe_url_rejects_control_character_scheme_bypasses`
- `safe_url_rejects_protocol_relative_urls`
- `link_rejects_control_character_scheme_bypasses_and_protocol_relative_urls`
- `link_href_attribute_escapes_double_and_single_quotes`

Commands:

```text
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab/frame-ui/igniter-render-html
cargo test -- --nocapture
```

Result:

```text
unit tests: 5 passed
integration tests: 14 passed
doc tests: 0 passed
```

```text
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab
git diff --check
```

Result:

```text
passed
```

## Follow-Up

`frame-ui/igniter-gui/src/lib.rs` and `frame-ui/igniter-ui-kit/src/lib.rs` still have duplicated
SVG-oriented `esc` helpers that only escape `&`, `<`, and `>`. They were not changed in this card:
the acceptance allowed render-html-first closure, and the worktree already had unrelated active
frame-ui changes. Treat those helpers as a separate, narrow frame-ui cleanup card if they start
emitting quoted attributes from user-controlled values.
