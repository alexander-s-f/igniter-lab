# Card Status Normalization Inventory — LAB-HYGIENE-CARD-STATUS-NORMALIZATION-P10

Date: 2026-06-24. Scope: `.agents/work/cards/lang/`. Lab hygiene; no source/test changes.

Machine-friendly inventory of recent card `Status:` headers. Goal: an agent scanning for open work can
trust `^Status: CLOSED` as "closed" and not misread closed cards as live backlog. Only the **leading
status token** was normalized where the card is unambiguously closed with **in-card evidence** (closing
report / acceptance / proof-doc link); embedded closing summaries and dates were preserved.

## Counts (whole `cards/lang/`)

| Metric | Count |
| --- | --- |
| Total cards | 446 |
| Start with `Status: CLOSED` (after this pass) | 200 |
| `Status: DRAFT` | 4 |
| No `Status:` line at all | 234 |
| `Status: DONE …` / `Status: ✅ CLOSED …` remaining | **0** (all normalized) |

## 1. Headers normalized → `Status: CLOSED` (11)

Leading token only; the rest of each line (date + closing summary) is unchanged. Each had clear in-card
closure evidence (acceptance checks and/or a `lab-docs/lang/…-v0.md` proof doc or `lab-docs/STATUS.md`).

| Card | Before (leading token) | After |
| --- | --- | --- |
| `LAB-TODOAPP-API-CREATE-OBJECT-BODY-P35.md` | `Status: DONE (2026-06-23) — …` | `Status: CLOSED (2026-06-23) — …` |
| `LAB-TODOAPP-API-HOST-SURROGATE-ID-P36.md` | `Status: DONE (2026-06-23) — …` | `Status: CLOSED (2026-06-23) — …` |
| `LAB-TODOAPP-API-ACCOUNT-EXISTENCE-P38.md` | `Status: DONE (2026-06-23) — …` | `Status: CLOSED (2026-06-23) — …` |
| `LAB-TODOAPP-API-ERROR-ENVELOPE-READINESS-P39.md` | `Status: DONE (2026-06-23) — …` | `Status: CLOSED (2026-06-23) — …` |
| `LAB-TODOAPP-API-CREATE-BODY-COMPAT-POLICY-P40.md` | `Status: DONE (2026-06-23) — …` | `Status: CLOSED (2026-06-23) — …` |
| `LAB-TODOAPP-API-PRODUCT-SURFACE-P41.md` | `Status: DONE (2026-06-23) — …` | `Status: CLOSED (2026-06-23) — …` |
| `LAB-TODOAPP-API-ACCOUNT-EXISTENCE-SEMANTICS-P37.md` | `Status: ✅ CLOSED — 2026-06-23` | `Status: CLOSED — 2026-06-23` |
| `LAB-IGNITER-WEB-RUNNER-STATUS-HYGIENE-P27.md` | `Status: ✅ CLOSED — 2026-06-22` | `Status: CLOSED — 2026-06-22` |
| `LAB-IGNITER-WEB-RUNNER-DOCS-SWEEP-P30.md` | `Status: ✅ CLOSED — 2026-06-22` | `Status: CLOSED — 2026-06-22` |
| `LAB-IGNITER-WEB-READTHEN-EFFECTHOST-DOC-SWEEP-P32.md` | `Status: ✅ CLOSED — 2026-06-23` | `Status: CLOSED — 2026-06-23` |
| `LAB-IGNITER-WORKSPACE-DRIFT-FORENSICS-P1.md` | `Status: ✅ CLOSED — 2026-06-22` | `Status: CLOSED — 2026-06-22` |

## 2. Closed, left as-is (already `Status: CLOSED…`, safe for open-work scans)

These already begin with `CLOSED`, so a prefix scan classifies them correctly. The trailing qualifier
carries a (small) claim — left untouched to honour "do not change card content except the header":

- `LAB-HYGIENE-SPARKCRM-ROUTE-SCOPE-P8.md` — `Status: CLOSED - 2026-06-22`
- `LAB-HYGIENE-STATUS-CLEAN-P2.md` — `Status: CLOSED - 2026-06-22`
- `LAB-PROVENANCE-BRIDGE-P6.md` — `Status: CLOSED - readiness packet`

Older archive cards also carry qualifier variants (`CLOSED (lab implementation)`, `CLOSED (readiness
packet)`, `CLOSED 2026-06-16 — …`, lowercase `status: CLOSED — N/N PASS`). All start with `CLOSED`;
left as historical record (out of "don't rewrite old archives broadly").

## 3. Needs human review (NOT modified)

Recent cards (`-mtime -5`) that are NOT unambiguously closed — left exactly as found:

**`Status: DRAFT`:**
- `LAB-HYGIENE-CARD-STATUS-NORMALIZATION-P10.md` — this card (in progress).
- `LAB-LANG-APP-SCIENCE-PRESSURE-MAP-P2.md` — open.
- `LAB-TODOAPP-API-NEXT-PRODUCT-SLICE-READINESS-P42.md` — open readiness.
- `LAB-TODOAPP-API-SMOKE-P35-P36-REALIGN-P42.md` — completed during the same harvest pass and closed by the
  owner after this inventory was written. No longer an active blocker.

**No `Status:` line (recent):**
- `LAB-IGNITER-RELATIONAL-CONTRACTS-READINESS-P1.md`
- `LAB-IGNITER-RELATIONAL-CONTRACTS-TODO-P2.md`
- `LAB-IGNITER-RELATIONAL-QUERYPLAN-BRIDGE-P3.md`
- `LAB-MACHINE-POSTGRES-SCHEMA-QUERY-READINESS-P9.md`
- `LAB-STDLIB-NET-P9.md`

## 4. Known backlog (out of scope here)

~229 older cards carry no `Status:` line at all. Adding headers requires per-card closure judgement and
would mean rewriting old archives broadly — explicitly out of this card's scope. Track as a separate
hygiene card if a machine-readable status is wanted for the whole archive.

## Follow-up recommendations

1. If a fully machine-readable archive is desired, open a dedicated card to backfill `Status:` lines on
   the ~229 header-less cards, and to decide whether qualifier suffixes (`CLOSED (readiness packet)`,
   `CLOSED - <date>`) should collapse to bare `Status: CLOSED`.
2. Going forward, prefer `Status: CLOSED` as the leading token (date/summary may follow after `—`).
