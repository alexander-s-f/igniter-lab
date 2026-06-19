# Igniter Lang — Brand & Design System

## Status
Lab-only design-system snapshot. These artifacts are useful implementation references, but they are not canonical public brand authority, stable UI guidance, production website material, or release evidence.

## Core System
- **Mark engine:** `assets/ig-mark.js` — SVG renders asterisk (6 rays, ignition orange on ink, 60° steps), Original (logo), Oval (sub-product огонёк)
- **Brand CSS:** `assets/ig-brand.css` — Ember-on-Ink palette, typography (IBM Plex Mono/Sans), semantic colors (core/escape/temporal/oof)
- **Color palette:**
  - **Ink:** #1a1510 (base), #221b15 (layer 2), #2b221b (line)
  - **Ignition (Ember):** #ff6a3d (canonical, warm orange)
  - **Amber (Escape):** #f0a868 (brand yellow, side effects)
  - **Temporal (Cyan):** #5ec8d8 (time/history, only cool accent)
  - **Oof (Signal):** #d9694a (errors, warm red)
  - **Greys:** 
    - `--grey-3` (#e7ddd2) — text
    - `--grey-2` (#c4b6a8) — secondary
    - `--grey` (#8a7964) — tertiary
    - `--grey-2` (#6f6256) — UI separators

## Design Artifacts (all in project root)

### 1. **Igniter-Lang Brand System.html** (reference)
- Asterisk as canon, Original/Oval system, construction, lockups, reverse/scale
- Voice section (developer-friendly, warm tone)
- Color palette, type scale
- Status: lab snapshot v0.2

### 2. **Igniter-Lang README.html** (GitHub README mockup)
- Branded hero banner with Asterisk mark
- Badge row (stars, version, license)
- Real `.ig` code examples (add.ig, bid_summary.ig)
- Quick start, install, documentation links
- Status: lab snapshot

### 3. **Igniter-Lang Landing.html** (landing-page mockup)
- Hero: "A language that shows its work"
- Three promises: declared, observable, time-aware
- Contract anatomy section with visual breakdown
- Receipt-style proof section
- Full-width CTA band
- Status: lab snapshot, text-wrapping checked

### 4. **Igniter-Lang Syntax.html** (theme specification)
- Specimen window: `settlement.ig` in igniter-dark theme
- Token legend (9 categories: keyword, type, number, string, symbol, identifier, delimiter, comment)
- Monarch token map (Monaco integration guide)
- Semantic colors section (core/escape/temporal/oof meanings)
- Light variant (igniter-paper) for docs/print
- Monaco `defineTheme()` drop-in code (ready for MonacoEditor.svelte)
- Status: lab snapshot

### 5. **Igniter IDE.html** (sub-product reference)
- Full VS Code-style shell (Tauri mockup visual)
- Sub-product mark: **Oval** (огонёк) in titlebar + status bar
- Layout: left icon strip → left panel (project tree) → main (editor + tabs) → right panel (inspector) → right strip
- File tabs with syntax-aware icons (◈ for .ig, ✓ for compiled, ● for dirty)
- Tool tabs (Blueprint, Dispatch, DAG, System, Tracer, Timeline)
- Editor with line numbers, current-line highlight, syntax tokens, blinking cursor
- Inline Run panel (floating, with inputs/results)
- Bottom output log (single-line entries, semantic coloring)
- Right Inspector (contract hero, ports, invariants, action buttons)
- Status bar with Oval mark + "Igniter" label
- Status: lab snapshot

### 6. **Igniter Design System Plan.html** (implementation brief)
- Handoff document for dev agent
- Directory structure (Svelte components to touch)
- Color token map (CSS variable names for Tailwind)
- Syntax theme implementation (exact hex codes, Monaco rules)
- Sub-product mark usage (Oval in IDE, where to place)
- File-by-file changes (app.css, tailwind.config.js, MonacoEditor.svelte, components)
- Status: lab snapshot

## Navigation
All pages cross-link via top nav:
- Brand System ↔ Landing ↔ README ↔ Syntax ↔ IDE ↔ Plan

## For Implementation Agent
Use **Igniter Design System Plan.html** as a lab implementation reference. It covers:
1. Update CSS tokens in `app.css` (Ember-on-Ink palette)
2. Modify `tailwind.config.js` (semantic color tokens)
3. Drop Monaco theme rules into `MonacoEditor.svelte` (igniter-dark theme)
4. Swap mark SVG data in icon components (use Oval for IDE)
5. Reskin UI panels, buttons, tabs to match mockup (exact colors, spacing, hover states)
6. Update syntax highlighting classes to use new token colors

## Notes
- **Mark variants:** Use Original (asterisk 01) for main branding, Oval (огонёк) as sub-product identifier for IDE
- **Semantic colors** are NOT decoration — they classify language fragments (core = pure, escape = side effects, temporal = time, oof = error)
- **Light theme** (igniter-paper) is ready for printed docs; preserve token identity, darken lightness only
- Hex codes are the current lab snapshot; future canonical brand work may revise them
- Speech/copy on landing assumes expert audience (developers); tone is warm and confident, not tutorial-y

## Deliverables Checklist
- [x] Brand mark engine (SVG + JS)
- [x] CSS token system
- [x] Brand System reference page
- [x] GitHub README mockup
- [x] Landing page
- [x] Syntax theme spec + specimens (dark + light)
- [x] IDE shell mockup
- [x] Implementation plan (code-ready)
- [x] Cross-navigation between all pages
