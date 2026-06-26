# LAB-HYGIENE-DOC-PATH-AUTHORITY-P14

Status: CLOSED (2026-06-26)
Route: standard / hygiene
Skill: idd-agent-protocol

## Goal

Fix path-authority drift in active docs and cards:

```text
/Users/alex/dev/projects/igniter                         -> command center / meta docs
/Users/alex/dev/projects/igniter-workspace/igniter-lang  -> canon language/spec repo
/Users/alex/dev/projects/igniter-workspace/igniter-lab   -> lab evidence / implementation proofs
```

The recursive `TypeDecl` clarification surfaced this because the first card pointed at `/igniter` as canon,
but the live Covenant/Ch13/Ch2 spec lives in `igniter-workspace/igniter-lang`.

## Current Authority

Read first:

- `/Users/alex/dev/projects/igniter/README.md`
- `/Users/alex/dev/projects/igniter/docs/current-waves-2026-06-26.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/lab-docs/lang/lab-canon-recursive-typedecl-clarification-p1-v0.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/work/cards/lang/LAB-CANON-RECURSIVE-TYPEDECL-CLARIFICATION-P1.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lang/MAP.md`

## Task

Perform a narrow active-doc sweep for path drift:

- docs/cards that call `/Users/alex/dev/projects/igniter` "canon";
- docs/cards that should point to `igniter-workspace/igniter-lang` for Covenant/spec;
- docs/cards that should point to command-center for wave maps only.

Prefer active front doors, current wave docs, cards, and recent proof docs. Do not rewrite old historical
packets unless they are active references.

## Boundary

Allowed:

- Update command-center docs, lab active docs/cards, and small path-reference notes.
- Add a short authority table if needed.
- Update this card with closing report.

Closed:

- No code changes.
- No canon/spec edits unless the owning repo has an explicit path typo in a front door.
- No broad archive rewrite.
- No moving files.

## Required Verification

Run and report:

```bash
rg -n "/Users/alex/dev/projects/igniter|igniter-workspace/igniter-lang|canon|command center|command-center" \
  /Users/alex/dev/projects/igniter \
  /Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/work/cards/lang \
  /Users/alex/dev/projects/igniter-workspace/igniter-lab/lab-docs/lang

git -C /Users/alex/dev/projects/igniter diff --check
git -C /Users/alex/dev/projects/igniter-workspace/igniter-lab diff --check
```

## Acceptance

- [x] Active docs no longer describe `/Users/alex/dev/projects/igniter` as the canon spec repo.
- [x] Active docs point to `igniter-workspace/igniter-lang` for Covenant/spec.
- [x] Command-center role remains coordination, not canon.
- [x] Historical/archived docs are not churned unnecessarily.
- [x] `git diff --check` clean in touched repos.

## Reporting

Close with:

- exact docs touched;
- any stale historical references intentionally left alone;
- whether a persistent front-door path table now exists.

## Closing Report (2026-06-26)

Status: path-authority refresh complete.

Docs touched:

- `/Users/alex/dev/projects/igniter/README.md`
  - added `igniter-workspace/igniter-lang` to the persistent command-center path table as the canon
    language/spec repo for Covenant, spec chapters, PROP/gate surfaces;
  - narrowed `igniter-lab` wording to lab evidence / implementation proofs, not canon authority.
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/work/cards/lang/LAB-CANON-RECURSIVE-TYPEDECL-CLARIFICATION-P1.md`
  - corrected the live "Current Authority" path list to point Covenant/Ch13/Ch2/source checks at
    `igniter-workspace/igniter-lang`;
  - kept `/Users/alex/dev/projects/igniter` only as command-center wave-map context.
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/work/cards/lang/LAB-HYGIENE-DOC-PATH-AUTHORITY-P14.md`
  - added this closing report.

Stale references intentionally left alone:

- Older proof packets and broad historical cards still contain many `canon` and absolute-path mentions. They
  were not rewritten unless they were active references for this path-authority question.
- `lab-canon-recursive-typedecl-clarification-p1-v0.md` already has an explicit path note and uses
  `igniter-lang/...` citations, so it was left intact.
- Older command-center wave indexes remain dated coordination snapshots; the current 2026-06-26 wave already
  names `igniter-lang` as canon.

Persistent front-door table:

- Yes: `/Users/alex/dev/projects/igniter/README.md` now has the command-center path table with
  `igniter-lang` as canon and `/Users/alex/dev/projects/igniter` as coordination only.

Verification:

- Required broad `rg` sweep completed; output is intentionally noisy because historical cards/proof packets
  include many canon/boundary mentions.
- Focused stale-path sweep found no remaining active command-center-as-spec authority paths after the patch.
- `git -C /Users/alex/dev/projects/igniter diff --check` clean.
- `git -C /Users/alex/dev/projects/igniter-workspace/igniter-lab diff --check` clean.
