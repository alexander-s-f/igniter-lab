# LAB-HYGIENE-CARD-ID-COLLISION-INDEX-P4 - make duplicated P-suffixes navigable without mass rename

Status: CLOSED
Lane: workspace hygiene / agent navigation
Type: documentation cleanup / index
Delegation code: OPUS-HYGIENE-CARD-ID-COLLISION-INDEX-P4
Date: 2026-06-22
Skill: idd-agent-protocol

## Context

Gemini drift forensics found repeated suffixes in the flat card directory:

- many unrelated `P9` cards;
- many unrelated `P22` cards;
- agents often say "P9" or "P22" in chat and may open the wrong card.

Renaming every historical card is risky and noisy. The safer first hygiene move is to make the collision
visible and navigable, then recommend whether any specific live/open card deserves a rename.

## Goal

Create a durable collision index for ambiguous card suffixes and a short agent rule:

```text
Never treat a bare suffix like P9/P22 as unique. Resolve by full card id, lane, or latest chat context.
```

## Verify first

Run from `igniter-lab`:

```text
find .agents/work/cards/lang -maxdepth 1 -type f -name '*.md' -print
python3 - <<'PY'
from pathlib import Path
from collections import defaultdict
cards = list(Path('.agents/work/cards/lang').glob('*.md'))
by = defaultdict(list)
for p in cards:
    stem = p.stem
    suffix = stem.rsplit('-', 1)[-1]
    if suffix.startswith('P') and suffix[1:].isdigit():
        by[suffix].append(stem)
for suffix, names in sorted(by.items(), key=lambda kv: (int(kv[0][1:]), kv[0])):
    if len(names) > 1:
        print(suffix, len(names))
        for n in sorted(names):
            print('  ', n)
PY
```

Use live filenames, not Gemini's partial list.

## Allowed changes

- Add one compact index file under `.agents/work/` or `.agents/work/cards/` (choose the least surprising location).
- Optionally add a one-line pointer in `.agents/work/README.md` if such a file exists.
- Update this card with a closing report.

## Closed surfaces

- Do not rename historical cards in this card.
- Do not edit closed card contents except this card.
- Do not change lab docs or production code.
- Do not invent a global card registry format.

## Acceptance

- [x] Collision index lists all duplicated numeric suffixes, not just P9/P22.
- [x] Index includes full filenames and lane hints where cheaply inferable from the card title.
- [x] Index states the agent rule: bare `P<n>` is never unique in the flat folder.
- [x] No card renames or file moves.
- [x] `git diff --check` clean.

## Closing report

Closed 2026-06-22.

Added `.agents/work/cards/CARD-SUFFIX-COLLISIONS.md` as the durable navigation index for
duplicated numeric suffixes in `.agents/work/cards/lang/*.md`.

Live scan result:

- duplicated suffix groups: 26 (`P0` through `P25`);
- duplicated card rows listed in the index: 392;
- agent rule recorded in the index: never treat a bare suffix like `P9` or `P22` as unique;
- each row includes the full filename and a lane/title hint where available from the card body.

This card did not rename, move, or edit historical card files. This card did not change lab docs or
production code.
No `.agents/work/README.md` pointer was added because that file is not present in the current tree.

Validation:

- regenerated the index from the live `.agents/work/cards/lang/*.md` directory;
- verified the generated index is ASCII-only;
- verified the rule and representative `P22` entries are present with `rg`;
- `git diff --check` passed.
