# idd-agent-protocol — pointer (not the skill)

This directory is **intentionally a thin pointer**, not a skill copy. It holds no
SKILL.md and no references — by design, so it can never silently become a competing
canon.

## Source of truth

`igniter-gov/agent-protocol/idd-agent-protocol/` — see its `VERSION.md` / `SYNC.md`.

- Current version: **v1.1.0** (2026-06-15)
- Runtime use: Codex loads from `~/.codex/skills/idd-agent-protocol`; Claude uses
  its own managed plugin lineage (separate — see `claude-lineage-note.md` in source).

## To read the protocol

Open the source above. Do not re-add content here.

## To re-materialize this copy (only if a tool genuinely needs local files)

```sh
SRC=../../../../igniter-gov/agent-protocol/idd-agent-protocol
cp "$SRC/SKILL.md" . && cp -r "$SRC/references" .
# then verify against SRC/VERSION.md:
shasum -a 256 SKILL.md references/*.md
```

If you re-materialize, treat it as a versioned snapshot pinned to the source hash —
not authority. Prefer keeping this a pointer.
