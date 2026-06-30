# LAB-FRAME-VIEW-ELEMENT-TREE-HOST-BRIDGE-P2

Status: CLOSED (2026-06-27)
Route: standard / frame-ui / view-language-pressure / proof
Skill: idd-agent-protocol

## Goal

Prove the smallest bridge from **pure `.ig` authored Element trees** into the current frame-ui host path.

P1 established that Candidate D is the main line:

```text
view = pure Igniter element-contracts + future invocation-form sugar
```

This card should prove the runtime seam before adding syntax:

```text
.ig contracts -> Element { tag, attrs, text, intent, children }
  -> frame-ui bridge
  -> WidgetRenderHost / current frame runtime output
```

Do **not** implement `.igv`, `.ig.html`, parser sugar, cross-module contract refs, or optional/default fields.
This is a host-bridge proof, not a new language feature.

## Current Authority

Live source wins over older packets.

Primary docs and specimens:

- `lab-docs/lang/lab-frame-view-language-pressure-p1-v0.md`
- `lab-docs/lang/lab-frame-dx-view-language-design-p1-v0.md`
- `lab-docs/lang/lab-frame-dx-authoring-surface-recon-p1-v0.md`
- `lab-docs/lang/specimens/dx-view-d/elements.ig`
- `lab-docs/lang/specimens/dx-view-d/list_view_manual.ig`
- `lab-docs/lang/specimens/dx-view-d/list_view_inline.ig`
- `lab-docs/lang/specimens/dx-view-d/list_view_dynamic.ig`

Important live frame-ui anchors:

- `frame-ui/igniter-frame/src/ig_bridge.rs`
- `frame-ui/igniter-frame/src/widget_host.rs`
- `frame-ui/igniter-frame/src/list_screen.rs`
- `frame-ui/igniter-ui-kit/src/view_artifact.rs`

Important live fact from curation:

```bash
ruby -I /Users/alex/dev/projects/igniter-workspace/igniter-lang/lib \
  /Users/alex/dev/projects/igniter-workspace/igniter-lang/bin/igc compile \
  /Users/alex/dev/projects/igniter-workspace/igniter-lab/lab-docs/lang/specimens/dx-view-d/elements.ig \
  --out /tmp/elements.igapp
```

The same command shape compiled `elements.ig`, `list_view_inline.ig`, and `list_view_dynamic.ig` with
`status: ok`. Re-run rather than trusting this note.

## Background Decision

P1 decision to preserve:

- **Candidate D = PUSH:** pure `.ig` element contracts are the main path.
- **ASK1 = PUSH later:** cross-module contract references are a real blocker for reusable `elements.ig`,
  but not this card.
- **ASK2 = PUSH later:** invocation-form body-as-children sugar (`col { row { leaf } }`) is desirable,
  but not this card.
- **Optional/default fields = HOLD.**
- `.igv` remains a fallback / later projection dialect, not the primary route.

The existing `frame-ui/igniter-frame/src/ig_bridge.rs` already names the target shape:

```text
Element { tag: String, attrs: { dir, main, flex, pad, gap }, text, intent, children: [Element] }
```

Use that as the first bridge target unless live code proves it obsolete.

## Questions To Answer

1. Can a compiled `.ig` Element-tree specimen be connected to `ig_bridge.rs` without a new language feature?
2. Does the proof use real `.ig` runtime output, or only a mirrored JSON shape?
3. If mirrored JSON is used, what is the smallest honest next step to remove the mirror?
4. Does `WidgetRenderHost` receive/render nested container + leaf/button structure with dynamic labels preserved?
5. What is the fail-closed behavior for unsupported tags or malformed Element values?
6. What stale specimen comments/docs still claim false blockers, especially around `map`?

## Implementation Guidance

Preferred path:

1. Re-run compile checks for:
   - `elements.ig`
   - `list_view_inline.ig`
   - `list_view_dynamic.ig`
2. Use `list_view_dynamic.ig` or a minimal sibling specimen as the source of truth.
3. If the current toolchain can execute the compiled app and extract the Element output cheaply, do that.
4. Otherwise, write a narrowly scoped frame-ui proof test using a JSON value that mirrors the compiled
   Element schema, and clearly state that VM extraction remains open.
5. Feed the Element tree through the existing `ig_bridge.rs` path into `WidgetRenderHost`.
6. Assert nested output is non-empty and preserves labels/intents from the authored Element tree.
7. Add a fail-closed test for an unknown tag if `ig_bridge.rs` exposes an error path.

Suggested minimal mapping if a bridge adapter must be made explicit:

```text
tag = "col"    -> vertical container
tag = "row"    -> horizontal container
tag = "leaf"   -> text/label node
tag = "button" -> clickable/intent node or closest existing button widget
```

Keep this adapter in frame-ui proof space. Do not move product semantics into compiler/canon.

## Evidence Cleanup

Patch stale comments in specimens if found.

Known stale-risk:

- `list_view_manual.ig` may still imply that `map` is unavailable.
- `list_view_dynamic.ig` proves `map` works in this pressure specimen.

Preferred wording:

```text
This static/manual specimen intentionally avoids map for readability.
The dynamic sibling proves map-based body construction.
```

Do not edit old docs broadly; only clean false blockers that would mislead the next agent.

## Boundary

Allowed:

- Add a focused frame-ui proof/test.
- Add a small adapter in frame-ui if needed to connect Element JSON to the existing host path.
- Patch stale comments in `lab-docs/lang/specimens/dx-view-d/*`.
- Write the proof packet.
- Update this card with closing report.

Closed:

- No parser/compiler changes.
- No `.igv` dialect work.
- No `.ig.html` work.
- No invocation-form syntax.
- No cross-module contract reference implementation.
- No canon proposal/spec authority claim.
- No changes to server/machine/web T1 work.
- Do not disturb unrelated dirty files.
- Avoid touching `frame-ui/igniter-frame/Cargo.lock` unless a focused frame-ui test/build truly requires it;
  if it changes, explain why in the closing report.

## Dirty Worktree Warning

At card creation time, the lab worktree contains unrelated active changes in:

- `runtime/igniter-machine/**`
- `server/igniter-server/**`
- `server/igniter-web/**`
- several T1 proof cards/docs/tests
- `frame-ui/igniter-frame/Cargo.lock`

Treat those as other agents' work. Do not stage, revert, rewrite, or rely on them unless live verification
shows the specific frame bridge needs one file.

## Required Packet

Create:

`lab-docs/lang/lab-frame-view-element-tree-host-bridge-p2-v0.md`

Include:

- exact compile commands and results for the `.ig` specimens;
- exact frame-ui host path used (`ig_bridge.rs`, `WidgetRenderHost`, or successor);
- whether the test used real `.ig` runtime output or a mirrored JSON shape;
- adapter/mapping rules, if any;
- fail-closed behavior;
- stale-comment cleanup;
- what remains for ASK1 and ASK2.

## Suggested Verification

```bash
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab

ruby -I /Users/alex/dev/projects/igniter-workspace/igniter-lang/lib \
  /Users/alex/dev/projects/igniter-workspace/igniter-lang/bin/igc compile \
  lab-docs/lang/specimens/dx-view-d/elements.ig \
  --out /tmp/frame-elements.igapp

ruby -I /Users/alex/dev/projects/igniter-workspace/igniter-lang/lib \
  /Users/alex/dev/projects/igniter-workspace/igniter-lang/bin/igc compile \
  lab-docs/lang/specimens/dx-view-d/list_view_inline.ig \
  --out /tmp/frame-list-inline.igapp

ruby -I /Users/alex/dev/projects/igniter-workspace/igniter-lang/lib \
  /Users/alex/dev/projects/igniter-workspace/igniter-lang/bin/igc compile \
  lab-docs/lang/specimens/dx-view-d/list_view_dynamic.ig \
  --out /tmp/frame-list-dynamic.igapp

cargo test -p igniter_frame <focused_test_name>
git diff --check
```

If the frame crate is not a workspace package from this cwd, run the equivalent focused cargo command from
`frame-ui/igniter-frame`.

## Acceptance

- [ ] `elements.ig` compiles with `status: ok`.
- [ ] `list_view_inline.ig` compiles with `status: ok`.
- [ ] `list_view_dynamic.ig` compiles with `status: ok`.
- [ ] A focused frame-ui proof renders a nested Element tree through the current host path.
- [ ] Dynamic labels from the authored/dynamic tree are preserved in rendered output, runtime state, or
      inspectable frame nodes.
- [ ] Unsupported/malformed Element input fails closed, or the packet clearly documents why the current bridge
      cannot express that yet.
- [ ] No parser/compiler/canon changes.
- [ ] No `.igv` or `.ig.html` changes.
- [ ] Stale specimen comments about `map` are corrected if present.
- [ ] Proof packet created.
- [ ] `git diff --check` clean for touched files.

## Closing Report

- **Result:** GREEN. The `.ig` `Element` tree → `ig_bridge.rs` → `solve` → `WidgetRenderHost` bridge is
  proven, end-to-end, with a live browser demo. Nested container + leaf/button structure renders with
  dynamic labels and intents preserved; the `.ig` tree lays out byte-identically to the hand-written
  list. No language/parser/canon change; no `.igv`/`.ig.html`/sugar; no cross-module refs; no T1 files
  touched. Full proof packet: `lab-docs/lang/lab-frame-view-element-tree-host-bridge-p2-v0.md`.

  Q1 (connect without a new feature): YES. Q4 (nested + labels preserved): YES. Q5 (fail-closed):
  malformed JSON → error card; unknown tag → visible `?unknown tag` marker; both tested. Q6 (stale
  `map` claims): cleaned in `list_view_manual.ig` + `list_view_inline.ig`.

- **Files changed:**
  - `frame-ui/igniter-frame/src/ig_bridge.rs` — fail-closed-visible unknown tag + `unknown_tag_*` test
    (the bridge module + 3 other tests already existed from P1's host-bridge commit `061fb5a`).
  - `lab-docs/lang/specimens/dx-view-d/list_view_manual.ig`, `list_view_inline.ig` — stale `map`
    comment cleanup (no semantic change).
  - `lab-docs/lang/lab-frame-view-element-tree-host-bridge-p2-v0.md` — proof packet (new).
  - (already live from P1: `web/ig.html`, `web/list_view.element.json`, `src/wasm.rs::render_ig_view`.)
  - **Cargo.lock NOT touched.** No T1 / machine / server / web files touched.

- **Real `.ig` runtime output or mirrored JSON:** **MIRRORED JSON** — the fixture mirrors the
  type-verified `Element` schema that `list_view_dynamic.ig` emits (`output : Element`), not an executed
  `igc run`. Stated honestly in the packet §3; smallest next step to remove the mirror = a minimal
  `igc run` (passport + input) capturing the real `Element` output and feeding it byte-for-byte.

- **Commands run:**
  - `ruby -I …/igniter-lang/lib …/igniter-lang/bin/igc compile <specimen>.ig --out /tmp/…igapp`
    → `elements.ig` / `list_view_inline.ig` / `list_view_dynamic.ig` all `status: ok`.
  - `cargo test` (from `frame-ui/igniter-frame`) → 65 passed / 0 failed.
  - `git diff --check` → clean.

- **Tests:** 65/0. Bridge: `ig_element_tree_lays_out_like_the_handwritten_list`,
  `renders_ig_tree_to_svg_through_the_shared_host`, `unknown_tag_fails_closed_visibly`,
  `malformed_json_is_total_no_panic`, `deterministic_render`. Live `/ig.html` proof + reflow-on-edit.

- **Remaining blockers:** none for the bridge. The mirror (no live `igc run` extraction) is the one
  open seam — a separate card. ASK1 (cross-module refs) and ASK2 (invocation-form nesting) remain canon
  pressure, now backed by end-to-end UI evidence; optional/default fields stay HELD.

- **Next card:** `LAB-FRAME-VIEW-IGC-RUN-ELEMENT-EXTRACTION-P3` — remove the mirror: produce the
  `Element` JSON from a real `igc run` of `list_view_dynamic.ig` (minimal passport + input) and feed it
  byte-for-byte into `render_ig_view`. Then optionally wire intents to an `.ig`-shaped reducer to make
  the bridged view interactive (close the view+logic loop).
