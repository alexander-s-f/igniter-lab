# LAB-RACK-P2

**Card ID:** LAB-RACK-P2
**Category:** lang / web
**Track:** lab-rack-core-contract-shape-and-pipeline-proof-v0
**Route:** EXPERIMENTAL / LAB-ONLY
**Date:** 2026-06-08
**Status:** ✅ DONE — 46/46 PASS

---

## D — Deliverables

- `igniter-view-engine/fixtures/rack_core/env_get_valid.json`
- `igniter-view-engine/fixtures/rack_core/env_post_valid.json`
- `igniter-view-engine/fixtures/rack_core/env_invalid_method.json`
- `igniter-view-engine/fixtures/rack_core/env_invalid_path.json`
- `igniter-view-engine/fixtures/rack_core/response_200_chunks.json`
- `igniter-view-engine/fixtures/rack_core/response_400_chunks.json`
- `igniter-view-engine/fixtures/rack_core/response_invalid_status.json`
- `igniter-view-engine/fixtures/rack_core/response_invalid_headers.json`
- `igniter-view-engine/fixtures/rack_core/response_invalid_body.json`
- `igniter-view-engine/proofs/rack_core_proof.rb` — **main deliverable, 46/46 PASS**
- `lab-docs/lang/lab-rack-core-contract-shape-and-pipeline-proof-v0.md`
- `.agents/work/cards/lang/LAB-RACK-P2.md` (this receipt)

---

## S — Summary

Proved the core Rack-shaped contract algebra in Igniter at the type-system level:

- **HttpRequest Record** with `Collection[String]` body — richer than P1's `Option[String]`
- **HttpResponse Record** with full schema validation
- **RackEnvAdapter** — Rack env hash → typed `HttpRequest` (field mapping, header normalization, body chunking)
- **RackTupleAdapter** — `HttpResponse` → `[status, headers, body]` Rack triple
- **HandlerContract** = `ContractRef[HttpRequest, HttpResponse]` analog — dispatch with input AND output type-boundary enforcement
- **Middleware wrapping model** — `HandlerContract → HandlerContract` shape; pipeline of 1, 2, 3 layers all preserve `HttpRequest → HttpResponse`; broken outermost middleware caught regardless of chain depth
- **Typed failure taxonomy** — `failed` / `timed_out` / `unknown_external_state`; unknown classes rejected
- **Closed-surface scan** — no real socket classes, no accept-loop forms, no runtime execution surfaces, no canon-authority or stable-API claims

---

## Proof Matrix Coverage

| Item | Status |
|------|--------|
| P2-1: HttpRequest positive fixture | ✅ 2 checks |
| P2-2: HttpResponse positive fixture | ✅ 2 checks |
| P2-3: RackEnvAdapter env→HttpRequest | ✅ 8 checks |
| P2-4: RackTupleAdapter HttpResponse→tuple | ✅ 4 checks |
| P2-5: Status outside 100..599 fails | ✅ 2 checks |
| P2-6: Invalid header key/value fails | ✅ 2 checks |
| P2-7: Invalid body chunk type fails | ✅ 3 checks |
| P2-8: HandlerContract mismatch fails | ✅ 5 checks |
| P2-9: Static pipeline preserves shape | ✅ 4 checks |
| P2-10: Middleware mismatch fails closed | ✅ 3 checks |
| P2-11: Typed failures → bounded outcomes | ✅ 5 checks |
| P2-12: No real network I/O | ✅ 2 checks |
| P2-13: No accept-loop authority | ✅ 2 checks |
| P2-14: No canon/stable/production claims | ✅ 2 checks |

---

## Gaps NOT closed by this card

| Gap | Status | Path |
|-----|--------|------|
| Dynamic ContractRef dispatch in VM | Open | LAB-RACK-P3 |
| Network I/O capability | Open | LAB-STDLIB-NET-P7+ |
| Accept-loop / service-loop | Blocked (PROP-037, Stage 4) | Future |
| Streaming bodies | Blocked (PROP-023, Stage 2) | Future |

---

## Closes gap in

- LAB-RACK-P1 row: "ContractRef dispatch: MEDIUM (Type system present; runtime dispatch unproven)"
  → now proven at proof-local level: static pipeline algebra + type-boundary enforcement confirmed.

---

## Next route recommendation

**LAB-RACK-P3: ContractRef VM dispatch preflight**
Prove that a `HandlerContract` value can be stored and dispatched at runtime in
the Rust lab VM — closes the remaining "dynamic dispatch unproven" gap and
prepares the ground for a route-dispatch proof.
