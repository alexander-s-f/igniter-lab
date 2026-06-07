# Card: LAB-WEB-FRAMEWORK-P4

**Title:** Layout Primitives
**Track:** lab-igniter-web-framework
**Status:** DONE
**Date:** 2026-06-07
**Surface:** lab-only · proof-local · no canon claim · no stable API

---

## D — Decision

Define a proof-local `LayoutEngine` Ruby module that implements layout primitives for
the Igniter Web Framework: named slot model, slot filling with safety integration,
layout validation, rendering, and 2-level inheritance.

**Authority boundary:** `igniter-view-engine/` only. `igniter-lang` untouched. No
production site edits. No new external dependencies.

---

## S — Scope

### Authorized writes (all created new)

| Path | Purpose |
|:-----|:--------|
| `igniter-view-engine/lib/layout_engine.rb` | LayoutEngine implementation |
| `igniter-view-engine/proofs/web_framework_p4_proof.rb` | Proof runner (45 checks) |
| `igniter-view-engine/fixtures/web_framework_p4/base_layout.json` | Base layout fixture |
| `igniter-view-engine/fixtures/web_framework_p4/article_layout.json` | Article layout fixture |
| `igniter-view-engine/fixtures/web_framework_p4/sample_content.md` | Sample content fixture |
| `igniter-view-engine/fixtures/web_framework_p4/sample_nav.md` | Navigation fixture |
| `igniter-view-engine/fixtures/web_framework_p4/sample_sidebar.md` | Sidebar fixture |
| `lab-docs/view/lab-igniter-web-framework-layout-primitives-v0.md` | Lab documentation |
| `.agents/work/cards/view/LAB-WEB-FRAMEWORK-P4.md` | This card receipt |

### Closed (not modified)

- `igniter-lang/` — untouched (verified by git status)
- `igniter-org/` — untouched
- All existing `igniter-view-engine/lib/` files (igv_compiler, ssr_renderer, view_artifact,
  site_content_compiler, slot_type_linker, compiled_contract_extractor,
  contract_schema_supplement) — layout_engine.rb is net-new only

**Note:** `SiteContentCompiler` received a class-level `.compile` convenience method added
via `class SiteContentCompiler` reopening inside `layout_engine.rb`. This is additive
only — no existing methods were modified.

---

## T — Tests (Proof Results)

Proof runner: `igniter-view-engine/proofs/web_framework_p4_proof.rb`

```
Total: 45  |  PASS: 45  |  FAIL: 0
Result: ALL CHECKS PASSED
```

### Check Matrix

| Group | Check | Status |
|:------|:------|:-------|
| LAYOUT-SCHEMA | define_layout_returns_hash_with_name | PASS |
| LAYOUT-SCHEMA | define_layout_returns_hash_with_slots | PASS |
| LAYOUT-SCHEMA | define_layout_returns_hash_with_template | PASS |
| LAYOUT-SCHEMA | define_layout_raises_on_unknown_slot | PASS |
| LAYOUT-SCHEMA | validate_layout_valid_layout_returns_true | PASS |
| LAYOUT-SCHEMA | validate_layout_empty_name_returns_error | PASS |
| LAYOUT-SCHEMA | validate_layout_unknown_slot_returns_error | PASS |
| LAYOUT-SCHEMA | validate_layout_nil_template_returns_error | PASS |
| LAYOUT-SCHEMA | SLOT_NAMES_contains_expected_values | PASS |
| LAYOUT-SCHEMA | REQUIRED_SLOTS_contains_only_content | PASS |
| LAYOUT-FILL | fill_slot_returns_compiled_html | PASS |
| LAYOUT-FILL | fill_slot_raises_on_unknown_slot | PASS |
| LAYOUT-FILL | fill_slot_sanitizes_script_tag | PASS |
| LAYOUT-FILL | fill_slot_header_slot_works | PASS |
| LAYOUT-FILL | fill_slot_nav_slot_works | PASS |
| LAYOUT-FILL | fill_slot_sidebar_slot_works | PASS |
| LAYOUT-FILL | fill_slot_footer_slot_works | PASS |
| LAYOUT-FILL | fill_slot_returns_hash_with_required_keys | PASS |
| LAYOUT-RENDER | render_with_content_slot_ok_true | PASS |
| LAYOUT-RENDER | render_without_content_slot_ok_false | PASS |
| LAYOUT-RENDER | render_substitutes_content_slot | PASS |
| LAYOUT-RENDER | render_substitutes_nav_slot | PASS |
| LAYOUT-RENDER | render_optional_slots_use_empty_defaults | PASS |
| LAYOUT-RENDER | render_result_has_required_keys | PASS |
| LAYOUT-RENDER | render_html_contains_content_at_position | PASS |
| LAYOUT-RENDER | render_with_multiple_slots_all_substituted | PASS |
| LAYOUT-RENDER | render_extra_slot_ignored_gracefully | PASS |
| LAYOUT-RENDER | render_filled_slots_lists_explicitly_filled | PASS |
| LAYOUT-INHERIT | render_inherited_ok_true | PASS |
| LAYOUT-INHERIT | child_html_injected_as_parent_content | PASS |
| LAYOUT-INHERIT | parent_template_wraps_child_content | PASS |
| LAYOUT-INHERIT | render_inherited_propagates_child_error | PASS |
| LAYOUT-INHERIT | render_inherited_parent_content_satisfied | PASS |
| LAYOUT-INHERIT | render_inherited_parent_nav_explicit | PASS |
| LAYOUT-INHERIT | render_inherited_html_contains_both_parent_and_child | PASS |
| LAYOUT-INHERIT | render_inherited_missing_child_required_slot_ok_false | PASS |
| LAYOUT-SAFETY | script_tag_blocked_or_stripped | PASS |
| LAYOUT-SAFETY | javascript_scheme_link_blocked | PASS |
| LAYOUT-SAFETY | valid_safe_content_passes_through | PASS |
| LAYOUT-SAFETY | fill_slot_uses_site_content_compiler | PASS |
| LAYOUT-STABLE | layout_engine_responds_to_required_methods | PASS |
| LAYOUT-STABLE | site_content_compiler_dependency_loaded | PASS |
| LAYOUT-STABLE | no_net_http_usage_in_layout_engine | PASS |
| LAYOUT-STABLE | igniter_lang_untouched | PASS |
| LAYOUT-STABLE | layout_engine_is_new_file_not_existing_lib | PASS |

---

## R — Recommended Next

**Card:** `LAB-WEB-FRAMEWORK-P5`
**Title:** i18n + hreflang + Sitemap Generation
**Summary:** Extend `SiteContentCompiler` and the route model from P2 to emit canonical
tags, hreflang alternates, and a `sitemap.xml` for multi-locale pages. This completes
the static site artifact pipeline end-to-end.
**Authority:** Lab-only. No `igniter-org` edits. No `igniter-lang` changes.

---

## Non-Claims

- LayoutEngine is not a production layout system
- The slot model is not a stable or canonical API
- Deep (3+) layout inheritance is not supported by design
- No CSS, design tokens, or styling is emitted
- No i18n or locale routing (P5 scope)
