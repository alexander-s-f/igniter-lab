# LAB-HYGIENE-NET-P9-PATHS-P5 - fix stale deliverable paths in LAB-STDLIB-NET-P9

Status: CLOSED
Lane: workspace hygiene / path drift
Type: card/doc cleanup
Delegation code: OPUS-HYGIENE-NET-P9-PATHS-P5
Date: 2026-06-22
Skill: idd-agent-protocol

## Context

Gemini initially reported missing deliverables for `LAB-STDLIB-NET-P9`, but curation found the files do exist
after rehome:

```text
igniter-lab/frame-ui/igniter-view-engine/fixtures/network_http_client/mock_transport_table_domain.json
igniter-lab/frame-ui/igniter-view-engine/proofs/network_http_upstream_call_contract_proof.rb
```

The card originally listed pre-rehome paths under `igniter-view-engine/...`.

## Goal

Update stale paths in `LAB-STDLIB-NET-P9` and any adjacent proof doc references so agents do not treat
existing deliverables as missing.

## Verify first

Run:

```text
find /Users/alex/dev/projects/igniter-workspace -path '*mock_transport_table_domain.json' -o -path '*network_http_upstream_call_contract_proof.rb'
rg -n 'network_http_upstream_call_contract_proof|mock_transport_table_domain|LAB-STDLIB-NET-P9' /Users/alex/dev/projects/igniter-workspace/igniter-lab
```

Do not rerun old Ruby proofs unless the existing scripts are directly runnable and cheap. This is path hygiene,
not proof revalidation.

## Acceptance

- [x] `LAB-STDLIB-NET-P9.md` points at current `frame-ui/igniter-view-engine/...` paths.
- [x] Adjacent proof docs/cards with the same stale paths are updated, if found.
- [x] No claim changes from "proved" to anything broader; this is path correction only.
- [x] No file moves/deletes.
- [x] No production code changes.
- [x] `git diff --check` clean.

## Closed scope

No network feature work, no proof recreation, no card renaming, no archive cleanup.

## Next

If more stale path clusters are found, create a separate path-sweep card instead of broadening this one.

## Closing Report

Closed on 2026-06-22.

Verified live deliverables exist at:

```text
igniter-lab/frame-ui/igniter-view-engine/fixtures/network_http_client/mock_transport_table_domain.json
igniter-lab/frame-ui/igniter-view-engine/proofs/network_http_upstream_call_contract_proof.rb
```

Updated stale path references in:

```text
igniter-lab/.agents/work/cards/lang/LAB-STDLIB-NET-P9.md
igniter-lab/lab-docs/lang/lab-network-http-upstream-call-contract-composition-proof-v0.md
igniter-lab/lab-docs/lang/lab-igniter-workspace-drift-forensics-p1-v0.md
```

No proof claims changed, no Ruby proof rerun, no file moves/deletes, and no
production code changes. This was path hygiene only.
