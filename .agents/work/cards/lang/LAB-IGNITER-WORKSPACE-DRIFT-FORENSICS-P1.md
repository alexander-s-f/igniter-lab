# LAB-IGNITER-WORKSPACE-DRIFT-FORENSICS-P1 - live-truth sweep for weak spots and false blockers

Status: CLOSED — 2026-06-22
Lane: workspace hygiene / agent forensics / live truth
Type: readiness + forensic report
Delegation code: GEMINI-IGNITER-WORKSPACE-DRIFT-FORENSICS-P1
Date: 2026-06-22
Skill: idd-agent-protocol

## Context

Igniter now has several active engines:

- business/web/app runner (`igniter-web`, TodoApp, Postgres, ReadThen/effect-host);
- science/reproducibility (`Kuramoto`, experiment runner, random/math/statistics);
- package/trust (`igpkg`, lock/verify/admit, remote trust);
- language ergonomics (`signature surface`, HOF/lambda, records, loops).

The workspace is large and multi-agent. Agents often reach correct conclusions only after walking through stale
docs, old "deferred" claims, duplicated card numbers, path reorg drift, or false blockers. This card asks Gemini
to act as a detective/reverse engineer and produce a live-truth drift report.

## Goal

Find weak spots, contradictions, stale blockers, and ambiguous claims across the current workspace so the next
wave can do hygiene before building on noisy assumptions.

The report should answer:

```text
What does live code prove today?
What do docs/cards still claim incorrectly?
What looks blocked but is already implemented?
What looks implemented but is only readiness/evidence?
Where are naming/status/path ambiguities likely to mislead agents?
What small hygiene cards should we open next?
```

## Scope

Primary:

- `/Users/alex/dev/projects/igniter-workspace/igniter-lab`
- `/Users/alex/dev/projects/igniter-workspace/igniter-emergence`
- `/Users/alex/dev/projects/igniter/README.md` and current-wave command-center docs, if relevant.

Secondary only when directly referenced by the primary scope:

- `igniter-home-lab`
- old sibling/archive paths
- SparkCRM route pressure docs.

## Verify-first method

Do not trust old docs or card prose without live verification.

For every candidate inconsistency, capture at least two of:

- exact live file path + line evidence;
- exact card/proof-doc path + line evidence;
- exact command output (`git status`, `rg`, `cargo test`, `cargo tree`, etc.);
- exact current card status (`Status: OPEN/CLOSED`);
- current commit hash when relevant.

Search for stale-risk phrases:

```text
deferred
blocked
not implemented
unsupported
missing
TODO
OPEN
can't / cannot
fails
stale
readiness only
proof only
canon
lab v0
```

Then compare against live code/tests/cards.

## Required report sections

Write:

```text
lab-docs/lang/lab-igniter-workspace-drift-forensics-p1-v0.md
```

with these sections:

1. Executive summary: top 5 drift risks.
2. False blockers: docs/cards say "blocked/deferred" but live code/tests show it exists.
3. Real blockers: still blocked after live verification.
4. Overclaims: docs/cards imply production/canon/stable behavior that is only lab evidence.
5. Status hygiene: cards/proofs whose status or acceptance does not match live files.
6. Path/reorg drift: stale paths after repo/domain moves.
7. Naming collisions / ambiguous IDs: duplicated P numbers, confusing next-card IDs.
8. Agent footguns: patterns that repeatedly waste agent time.
9. Recommended hygiene cards: 5-10 concrete small cards, each with scope and why.
10. Appendix: commands run and skipped checks.

## Known high-value lenses

Check these especially:

- `.igweb` / IgWeb runner claims: loopback-only, bounded, no public CLI/canon unless proven.
- ReadThen/effect-host: readiness vs implementation vs runner integration.
- Package trust: archive/verify/admit vs remote node/network/signing.
- Experiment provenance: package artifact identity is present as a field but not yet wired from admission.
- Random/math/science: native stdlib support vs language bitops; Float determinism claims.
- HOF/lambda/records: record construction in lambdas, nested map/fold/reduce parity, stale workaround comments.
- Cards left OPEN despite proof docs, or CLOSED cards without proof docs.
- Duplicate P numbers across lanes.

## Gemini-specific cautions

Past Gemini research was useful but needed curation. Avoid these pitfalls:

- Do not output `file://` links; use paths.
- Do not call a markdown/report artifact "compile-clean" unless a compile command was actually run.
- Do not promote lab evidence to canon.
- Do not hardcode `sha256` / stable digest claims unless live code proves that exact substrate.
- Do not treat a proof doc as current truth when code disagrees.
- Do not implement fixes in this card.

## Acceptance

- [x] Report exists at `lab-docs/lang/lab-igniter-workspace-drift-forensics-p1-v0.md`.
- [x] At least 12 candidate inconsistencies were checked.
- [x] At least 5 findings include exact file/card line evidence.
- [x] False blockers and real blockers are separated.
- [x] Lab evidence vs canon vs production/remote trust is clearly separated.
- [x] Recommended next hygiene cards are concrete and small.
- [x] No production code changes.
- [x] No file moves/deletes.
- [x] `git diff --check` clean.

## Closed scope

No implementation, no refactor, no card mass-close, no docs rewrite beyond the report and this card's closing
report, no canon decisions, no public release claims.

## Next

Codex curates the Gemini report into a small hygiene wave, then resumes the main wave:

- experiment package provenance bridge;
- ReadThen dispatch implementation;
- language-surface/app-pressure work.
