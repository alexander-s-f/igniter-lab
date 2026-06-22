# LAB-IGNITER-MACHINE-HOST-IO-SUBSTRATE-READINESS-P1 - common IO/effect substrate beyond web

Status: READY
Lane: machine / host IO / architecture
Type: readiness / architecture packet
Delegation code: OPUS-MACHINE-HOST-IO-SUBSTRATE-P1
Date: 2026-06-22
Skill: idd-agent-protocol

## Context

Gemini correctly flagged the `igweb-serve` async trap:

- `server/igniter-web/src/bin/igweb-serve.rs` uses sync `std::net::TcpListener` + sync `serve_loop`;
- machine-backed effects use `tokio::net::TcpListener` + async `serve_loop_effect`;
- `IgWebServerApp::call` internally uses `rt.block_on(machine.dispatch(...))`, so simply wrapping the
  socket loop in Tokio is not enough.

But the deeper question is not web-only. IO is needed by web, CLI, desktop, science runners, exports, remote
nodes, and future distributed experiments. We need to decide where IO lives in the Igniter architecture.

Working thesis from Alex/Codex:

```text
Language / contracts = pure graph, values, decisions, intents; no ambient IO authority.
VM = executes pure graph, may emit structured intent/decision.
Machine host = capabilities, reads, effects, receipts, idempotency, retry, backpressure, mailbox, policy.
Runners = web / CLI / desktop / experiment / remote-node surfaces that adapt events into host execution.
```

This card should test that thesis against live code and prior proof lanes.

## Goal

Produce a readiness packet that answers:

**What is the common host IO substrate for Igniter, and how should IgWeb become its first full consumer
without making IO a web-only feature or leaking authority into `.ig`?**

No implementation in this card.

## Verify first

Read live code before designing:

```text
server/igniter-web/src/bin/igweb-serve.rs
server/igniter-web/src/lib.rs
server/igniter-server/src/serving_loop.rs
server/igniter-server/src/effect_host.rs
runtime/igniter-machine/src/ingress.rs
runtime/igniter-machine/src/capability*.rs
runtime/igniter-machine/src/postgres*.rs
runtime/igniter-machine/src/experiment.rs
```

Then read the latest relevant proof docs/cards:

```text
lab-docs/lang/lab-igniter-web-effect-host-readiness-p3-v0.md
lab-docs/lang/lab-igniter-web-effect-host-write-p4-v0.md
lab-docs/lang/lab-igniter-web-read-guard-host-readiness-p5-v0.md
lab-docs/lang/lab-igniter-web-read-guard-host-p6-v0.md
lab-docs/lang/lab-igniter-web-effect-host-runner-p9-v0.md
lab-docs/lang/lab-igniter-web-readthen-runner-readiness-p10-v0.md
lab-docs/lang/lab-todoapp-api-runner-productization-p9-v0.md
lab-docs/lang/lab-provenance-bridge-p6-v0.md
```

Also inspect any current experiment/emergence runner docs if they mention IO/export/provenance.

## Questions to answer

1. What are the IO classes Igniter needs?
   - inline read needed before response;
   - deferred effect/write/job;
   - export/project descriptor -> bytes;
   - file/storage IO;
   - remote node call;
   - experiment artifact/provenance write.
2. Which classes need immediate response and which should go through a durable mailbox?
3. Where should a mailbox live: machine, runner, separate process, or external adapter?
4. What already exists in `igniter-machine` that should be reused?
   - `MachineEffectHost`;
   - `IngressRouter`;
   - receipts;
   - duplicate/idempotency gates;
   - Postgres read/write executors;
   - retry/reconcile if present.
5. What is missing for a generic host substrate?
   - async app dispatch seam?
   - capability registry?
   - mailbox/queue abstraction?
   - read continuation driver?
   - runner config/admission?
   - lifecycle / worker pool / backpressure?
6. How should this support web, CLI, desktop, experiment runner, and remote node without making them all share
   web semantics?
7. What is the smallest first implementation slice after this readiness?
   - likely `LAB-IGNITER-WEB-ASYNC-MACHINE-RUNNER-P2`;
   - or a lower-level `LAB-MACHINE-HOST-IO-DRIVER-P2`;
   - justify the order.
8. How do we preserve authority boundaries?
   - `.ig` names logical target/intent only;
   - host owns DSN/secrets/passports/policy;
   - server owns transport only;
   - machine owns receipts/retry/idempotency.
9. What failure/backpressure model is appropriate?
   - queue depth;
   - worker pool max;
   - 202 vs 429/503;
   - timeout/cancel;
   - replay/retry.
10. What should `igweb-serve` become?
    - single binary with modes?
    - separate `igweb-serve` and `igweb-host`?
    - feature-gated machine mode?
    - config shape?
11. What must NOT be done?
    - no hidden `await` in language body;
    - no IO authority in `.ig`;
    - no server route table;
    - no unbounded worker spawning;
    - no fake production claim from direct harness tests.

## Expected deliverable

Create:

```text
lab-docs/lang/lab-igniter-machine-host-io-substrate-readiness-p1-v0.md
```

Recommended structure:

1. Executive summary / decision.
2. Live-code evidence table.
3. IO class taxonomy.
4. Existing substrate inventory.
5. Missing seams.
6. Proposed architecture diagram in text/mermaid.
7. Web/CLI/desktop/science/remote-node mapping.
8. Mailbox vs inline-read decision table.
9. Authority and security boundary.
10. Backpressure/failure model.
11. `igweb-serve` target shape.
12. Next cards with acceptance matrices.

Update this card with a closing report and mark all acceptance checks.

## Closed surfaces

- No code changes.
- No CLI changes.
- No new queue implementation.
- No Postgres/live DB work.
- No network/remote-node implementation.
- No canon claim.
- Do not solve `igweb-serve` directly; name the right next implementation card.

## Acceptance

- [ ] Packet is grounded in live source, not only prior docs.
- [ ] IO taxonomy covers web, CLI, desktop, experiment/science, and remote-node cases.
- [ ] Inline read vs deferred effect/mailbox distinction is explicit.
- [ ] Existing machine capabilities are inventoried with file references.
- [ ] `igweb-serve` async trap is explained as both socket-loop and nested `block_on`/sync app dispatch issue.
- [ ] At least three architecture alternatives are compared.
- [ ] Recommended next implementation slice is named with acceptance criteria.
- [ ] Authority boundaries are explicit and do not leak IO authority into `.ig`.
- [ ] No implementation/code/CLI changes.
- [ ] `git diff --check` clean.

## Closing report

TBD.
