# Agent Search Protocol — igniter-lab

Purpose: stop the "stale doc outranks live code" drift. Read this before grepping
the repo for what exists.

## Verify-first (the one rule)

"Is X implemented?" →
1. Check the crate's **`IMPLEMENTED_SURFACE.md`** (e.g. `igniter-vm/IMPLEMENTED_SURFACE.md`).
2. **Grep the live source** (`src/**`).
3. Only then trust any doc's "not implemented / deferred / blocked" claim.

A doc and the code disagree → **the code wins**; the doc is the bug. Cards and old
proof prose are evidence, **not current backlog**, unless `lab-docs/STATUS.md` or
the MAP confirms them open. (Protocol: idd-agent-protocol v1.2.0 → Verify-First.)

## What default search actually shows

Important: **`.agents/**` is a hidden (dot) directory** — default ripgrep / the
Grep tool does **not** search it (needs `--hidden`). So the cards, `portfolio-index.md`,
and operational archive under `.agents/` are already invisible to normal search.
The drift does **not** come from there.

The searchable stale surface is **`lab-docs/**`** (not hidden) — that is where a
grep for "deferred / not implemented" finds old claims (e.g. the now-superseded
`igniter-delta-1.md`). This is evidence, so it is **not** blanket-excluded; the
**verify-first rule above** is what neutralizes it.

`.rgignore` excludes only: build artifacts, and specific **superseded** files
(content migrated + banner present, starting with `lab-docs/igniter-delta-1.md`).
A future `lab-docs` staleness sweep will move dead docs into `lab-docs/archive/`,
which the firewall will then exclude wholesale.

## Reaching excluded material on purpose

```sh
rg --no-ignore "<pattern>"        # include archive + everything
rg -g '!*' --no-ignore <path>     # or scope to a specific archived path
```

If you find a stale claim in an archived doc, do **not** plan around it — confirm
against the implemented surface + source, then (if it misleads) supersede the doc.

## Navigation order (capsule layers)

`MAP.md` → `IMPLEMENTED_SURFACE.md` / `lab-docs/STATUS.md` → active cards → archive.
Default reads stop before archive unless a card sends you there.
