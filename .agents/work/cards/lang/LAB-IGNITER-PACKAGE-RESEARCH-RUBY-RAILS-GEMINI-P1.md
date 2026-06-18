# Card: LAB-IGNITER-PACKAGE-RESEARCH-RUBY-RAILS-GEMINI-P1 — RubyGems, Bundler, and Rails engines lessons for Igniter packages

**Lane:** background / research  
**Status:** CLOSED (Research report delivered)  
**Date opened:** 2026-06-18  
**Date closed:** 2026-06-18  
**Delegation-Code:** `GEMINI-20260618-PACKAGES-C`  
**Research label:** `BACKGROUND-RESEARCH`  
**Authority:** Research only. No code. No package spec authority. No canon.

## Parent card

`LAB-IGNITER-PACKAGE-MANAGER-READINESS-P1`

## Goal

Research RubyGems, Bundler, and Rails engines/plugins from the viewpoint of a Ruby-rooted Igniter
ecosystem: app-local ownership, lockfiles, executables, engines, migrations/assets, and plugin
boundaries.

## Scope

Compare:

- RubyGems gemspec and published gems.
- Bundler Gemfile / Gemfile.lock / groups / source.
- Rails engines/plugins: app extension, routes, migrations, assets, initializers.

## Output contract

Write exactly one report:

`lab-docs/lang/lab-igniter-package-research-ruby-rails-gemini-p1-v0.md`

Then update only this card with a closing report.

## Required sections

1. Executive summary.
2. Comparative table rows using the parent table schema.
3. What Bundler gets right for local-first reproducibility.
4. Rails engines as a warning: app extension without app ownership.
5. Migration/assets pitfalls and Igniter analogues.
6. Igniter package lessons for app/domain packages vs stdlib/canon packages.
7. Future card ideas.

## Closed surfaces

- Do not edit parent card or sibling reports.
- Do not change Ruby gem code.
- Do not propose Rails semantics as Igniter authority.
- No code changes.

## Acceptance

- [x] Report covers RubyGems, Bundler, and Rails engines/plugins.
- [x] Report has table rows in the parent schema.
- [x] Report distinguishes app-local packages from canon/stdlib packages.
- [x] Report identifies migration/assets/initializer anti-patterns to avoid.
- [x] No code changed.

---

## Closing Report — 2026-06-18

**Outcome:** Completed the packaging research survey for RubyGems, Bundler, and Rails engines/plugins, analyzing Gemfile local-first reproducibility, engine-coupling anti-patterns, database/assets sync desyncs, and app-local vs core boundaries.

**Deliverable:** `lab-docs/lang/lab-igniter-package-research-ruby-rails-gemini-p1-v0.md`

**Sources/Ecosystems Reviewed:** RubyGems gemspec specs, Bundler lockfile graph resolution, and Rails engines runtime configuration/asset hooks.

**Recommended v0 package model implications:** Reconfirmed path-based relative overrides as a primary developer ergonomic. Supported strict isolation of database schemas and route mappings: library packages must never dynamically alter the host memory or schema; extensions must lower to explicit, statically analyzable contract dispatch calls.

**Top Anti-patterns identified to avoid:**
1. **Dynamic Initializers:** Dynamic boot-phase code execution that mutates core system state.
2. **Database Migration Splitting:** Copying database scripts from libraries to host repositories, causing desynchronization.
3. **Asset Scope Pollution:** Dropping scripts and stylesheets into global namespaces.
4. **Post-Install Compiles:** Executing native build files (C extensions) during the installation phase.

**Verification:** No code or spec files were changed. The research report has been written exactly to the specified path.
