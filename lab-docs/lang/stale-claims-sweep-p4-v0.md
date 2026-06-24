# LAB-HYGIENE-STALE-CLAIMS-SWEEP-P4

Status: documentation audit + targeted stale-claim fixes
Date: 2026-06-24
Authority: lab evidence navigation only

## Scope

This sweep inspected high-risk phrases that can misroute agents: "not implemented",
"deferred", "harness only", "legacy string body", "idempotency key", "eq-only",
"no raw response", "ReadThen", "MachineEffectHost", "zip", "linalg", and
"cross-arch".

The sweep did not change production code, feature behavior, old card status, or public
emergence claims. Historical proof packets remain historical; only routing-dangerous claims
were patched with supersession notes.

## Live Anchors Checked

- `server/igniter-web/IMPLEMENTED_SURFACE.md:27` for the ReadThen status vocabulary.
- `server/igniter-web/IMPLEMENTED_SURFACE.md:40` for bounded `ReadThen { plan, then, carry }`.
- `server/igniter-web/IMPLEMENTED_SURFACE.md:42` for final `InvokeEffect` via `MachineEffectHost`.
- `server/igniter-web/IMPLEMENTED_SURFACE.md:61` for `Render` raw HTML response.
- `server/igniter-web/IMPLEMENTED_SURFACE.md:72` for object create body.
- `server/igniter-web/IMPLEMENTED_SURFACE.md:73` for removed legacy string create body.
- `server/igniter-web/IMPLEMENTED_SURFACE.md:74` for host-minted Todo surrogate ids.
- `server/igniter-web/IMPLEMENTED_SURFACE.md:77` for Todo delete.
- `server/igniter-web/IMPLEMENTED_SURFACE.md:78` for keyset pagination.
- `runtime/igniter-machine/IMPLEMENTED_SURFACE.md:55` for Text range/order.
- `runtime/igniter-machine/IMPLEMENTED_SURFACE.md:58` for opt-in real local Postgres write.
- `runtime/igniter-machine/IMPLEMENTED_SURFACE.md:59` for substrate delete op.
- `runtime/igniter-machine/IMPLEMENTED_SURFACE.md:348` for still-deferred Postgres boundaries.
- `lang/igniter-vm/IMPLEMENTED_SURFACE.md:65` for collection `zip`.
- `lang/igniter-vm/IMPLEMENTED_SURFACE.md:69` for Mat3 package proof.
- `lang/igniter-vm/IMPLEMENTED_SURFACE.md:80` for local deterministic `igc package admit`.
- `server/igniter-server/src/protocol.rs:37` for `ResponseBody::Raw`.
- `server/igniter-server/src/host.rs:255` for verbatim raw-byte writes.

## Patched Claims

| Path | Claim risk | Action |
| --- | --- | --- |
| `lab-docs/lang/lab-igniter-web-readthen-runner-readiness-p10-v0.md` | "not implemented", "harness only", "runner deferred" could override current ReadThen runner integration. | Added a 2026-06-24 supersession note and relabeled the old live-state block as historical P10 status. |
| `lab-docs/lang/lab-todoapp-api-local-postgres-p8-v0.md` | "runner-harness-only / deferred to P9" could hide later MachineEffectHost runner work. | Added a supersession note and relabeled the P8 runner scope as historical. |
| `lab-docs/lang/lab-igniter-web-file-export-thread-v0.md` | "No raw response implementation" was too broad after raw-byte/HTML response support landed. | Narrowed the statement to generic file/download response and export projectors. |
| `lab-docs/lang/lab-machine-igniter-server-wave-checkpoint-p14-v0.md` | JSON-only / no raw-byte response language was stale in a self-described front door. | Added a supersession note, replaced the raw-byte gap with app/export-specific delivery gaps, and updated the next-substrate route. |

## Claims Inspected

| # | Claim / phrase | Path | Result |
| --- | --- | --- | --- |
| 1 | `ReadThen` is not implemented | `lab-igniter-web-readthen-runner-readiness-p10-v0.md` | Stale as current status; patched with supersession note. |
| 2 | `ReadThen` not runner-integrated | `lab-igniter-web-readthen-runner-readiness-p10-v0.md` | Stale as current status; patched. |
| 3 | "Staged read TODAY = harness only" | `lab-igniter-web-readthen-runner-readiness-p10-v0.md` | Stale wording; relabeled as historical P10 state. |
| 4 | Full async runner "still deferred" | `lab-igniter-web-readthen-runner-readiness-p10-v0.md` | Historical P10 design context; supersession note points to current surface. |
| 5 | P8 write "Runner-harness-only (deferred to P9)" | `lab-todoapp-api-local-postgres-p8-v0.md` | Stale as planning guidance; patched. |
| 6 | MachineEffectHost typed-write contour deferred | `lab-todoapp-api-local-postgres-p8-v0.md` | Historical P8 scope; patched to avoid current misrouting. |
| 7 | "No raw response implementation" | `lab-igniter-web-file-export-thread-v0.md` | Too broad; patched to generic file/download response only. |
| 8 | "No raw HTML/SVG/binary response protocol" | `lab-machine-igniter-server-wave-checkpoint-p14-v0.md` | Stale; patched against `ResponseBody::Raw`. |
| 9 | Raw-byte responses listed as not implemented | `lab-machine-igniter-server-wave-checkpoint-p14-v0.md` | Stale guard; patched to app/export-specific file delivery. |
| 10 | Next substrate work = raw response | `lab-machine-igniter-server-wave-checkpoint-p14-v0.md` | Stale route; patched to app/export file delivery. |
| 11 | Sync observed mode leaves `InvokeEffect` observed | `server/igniter-web/IMPLEMENTED_SURFACE.md` | Current-true; no edit. |
| 12 | Async machine mode executes ReadThen/Postgres | `server/igniter-web/examples/todo_postgres_app/API.md` | Current-true; no edit. |
| 13 | Legacy string create body removed | `server/igniter-web/examples/todo_postgres_app/API.md` | Current-true and desirable drift guard; no edit. |
| 14 | Business id decoupled from idempotency key | `server/igniter-web/examples/todo_postgres_app/API.md` | Current-true; no edit. |
| 15 | Delete endpoint is implemented | `server/igniter-web/examples/todo_postgres_app/API.md` | Current-true; no edit. |
| 16 | Keyset pagination uses `?after=` | `server/igniter-web/examples/todo_postgres_app/API.md` | Current-true; no edit. |
| 17 | Read filters are not eq-only anymore | `server/igniter-web/examples/todo_postgres_app/host_policy.md` | Current-true (`eq`/`in`/range); no edit. |
| 18 | Global protocol error envelope remains deferred | `server/igniter-web/IMPLEMENTED_SURFACE.md` | Current-true; app errors have `RespondError`, host-wide envelope stays deferred. |
| 19 | Typed row destructuring remains not implemented | `server/igniter-web/IMPLEMENTED_SURFACE.md` | Current-true; no edit. |
| 20 | Postgres is fake-only | `runtime/igniter-machine/IMPLEMENTED_SURFACE.md` | False as current status; current surface already correct, no edit needed. |
| 21 | No `zip` / statistics blocked forever | `lang/igniter-vm/IMPLEMENTED_SURFACE.md` | False as current status; current surface already correct, no edit needed. |
| 22 | No linalg beyond Vec3 | `lang/igniter-vm/IMPLEMENTED_SURFACE.md` | False as current status; Mat3 proof is current, no edit needed. |
| 23 | Deterministic math evidence implies canon promotion | `lang/igniter-vm/IMPLEMENTED_SURFACE.md` | False boundary; current surface keeps canon separate, no edit needed. |
| 24 | `package admit` implies registry/signing/deploy/execution | `lang/igniter-vm/IMPLEMENTED_SURFACE.md` | False boundary; current surface already warns against inference, no edit needed. |

## Decision

Direct patches were enough for high-impact drift. The remaining inspected phrases are either already
correct in current front-door docs or intentionally historical inside closed proof packets. Do not
rewrite old proof packets for style; add supersession notes only when a stale claim is likely to route
new work incorrectly.
