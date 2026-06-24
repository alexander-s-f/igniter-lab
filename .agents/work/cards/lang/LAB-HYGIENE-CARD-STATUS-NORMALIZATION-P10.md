# LAB-HYGIENE-CARD-STATUS-NORMALIZATION-P10 - normalize recent card status vocabulary

Status: CLOSED
Lane: lab hygiene / card index / agent clarity
Type: documentation hygiene
Date: 2026-06-24
Skill: idd-agent-protocol

## Context

Recent waves used mixed card status vocabulary:

- `Status: CLOSED`
- `Status: DONE (...)`
- `Status: ✅ CLOSED`
- missing `Status:` lines on a few older/newer cards

Humans can understand this, but agents scanning for open work can misclassify closed cards as live backlog.
This is especially noisy in the Todo API / IgWeb / hygiene waves where many cards closed quickly.

## Goal

Produce a normalized, machine-friendly view of recent card status and patch only low-risk status headers when
the card is clearly closed.

## Verify First

- Scan recent cards in `.agents/work/cards/lang/`.
- Use the card's closing report / acceptance / changed files as evidence.
- Do not infer closure from memory alone.
- If a card lacks a clear closing report, list it as "needs human review" instead of changing it.

Suggested scan:

```bash
find .agents/work/cards/lang -maxdepth 1 -type f -mtime -5 -print
rg -n "^Status:" .agents/work/cards/lang
rg -n "Closing report|Closing Report|Acceptance|DONE|CLOSED" .agents/work/cards/lang
```

## Allowed Changes

- Normalize unambiguous closed headers to `Status: CLOSED`.
- Add a small status inventory proof doc under `lab-docs/lang/`.
- Optionally add a short note to the current implemented-surface / status doc pointing to the inventory.

## Closed Surfaces

- Do not change card content, claims, or closing evidence except the status header.
- Do not mark ambiguous cards closed.
- Do not edit production code.
- Do not rewrite old archives broadly.

## Acceptance

- [x] Inventory lists recent closed / open / ambiguous cards.
- [x] Any status header changed has clear in-card evidence.
- [x] Ambiguous cards are explicitly listed, not silently modified.
- [x] No source/test changes.
- [x] `git diff --check` clean.

## Output Shape

Close with:

- number of headers normalized;
- number of ambiguous cards left untouched;
- exact paths changed;
- recommended follow-up if a real open-card drift exists.

## Closing Report

Date: 2026-06-24

Normalized 11 unambiguous recent closed-card headers to start with `Status: CLOSED`, preserving trailing
dates/summaries. Wrote the inventory proof doc:

```text
lab-docs/lang/lab-hygiene-card-status-normalization-p10-v0.md
```

Ambiguous/open cards were left untouched and listed in the proof doc. During curation,
`LAB-TODOAPP-API-SMOKE-P35-P36-REALIGN-P42` was closed separately, so its earlier "needs owner close"
inventory note is historical to this pass rather than an active blocker.

No source/test behavior changes were made by this status-normalization card. `git diff --check` clean.
