# lab-machine-igniter-server-gemini-wave-a-synthesis-v0

**Delegation-Code:** `GEMINI-20260618-SERVER-WAVE-A`  
**Status:** CURATED SYNTHESIS - Gemini output normalized by Codex.  
**Authority:** Evidence and backlog shaping only. No canon claim. No live/SparkCRM authority.

## Purpose

This packet records what was useful from the Gemini parallel review wave and, more importantly,
sets the seed style for future delegated research waves.

Gemini is useful as a broad reader/reviewer, but its raw output must not be treated as authority.
It tends to over-create artifacts, write to the wrong repository, and promote "recommended" into
"canonical" unless the task gives a strict output contract.

## Raw Agent Outcomes

| Agent | Topic | Raw value | Curated decision |
|---|---|---|---|
| `GEM-SERVER-A1` | Server protocol review | Useful review of `ServerRequest -> ServerApp -> ServerDecision -> host`; good extra acceptance ideas. | Keep as raw evidence. Do not commit as-is. Fold key tests into future cards. |
| `GEM-SERVER-A2` | Middleware shape | Useful wrapper-based middleware packet. | Curated and committed as `lab-machine-igniter-server-middleware-shape-v0.md`. |
| `GEM-SERVER-A3` | Hot reload readiness | Useful `Arc` swap idea and tests, but wrote to `igniter-gov/cards` and overreached authority. | Rewritten as lab card `LAB-MACHINE-IGNITER-SERVER-HOT-RELOAD-P4`. |
| `GEM-SERVER-A4` | SparkCRM ServerApp shape | Useful product shape for targets, normalization, duplicate policy, and live gate. Stale next-routes and live-DB drift. | Rewritten as lab card `LAB-MACHINE-SPARKCRM-SERVER-APP-READINESS-P1`. |

## Top Risks Found

1. **Authority drift:** Gemini wrote a lab card into `igniter-gov/cards`. Future tasks must explicitly
   state the repo/path and forbid `igniter-gov` unless governance is the actual lane.
2. **Status drift:** Gemini suggested already-closed cards as next work. Future tasks must require
   checking live status before proposing next routes.
3. **Over-claiming:** Terms like `canonical`, `proven`, and `fully preserved` appeared without a
   matching authority/test. Future tasks must use `v0`, `recommended`, or `targeted` unless the card
   grants stronger authority.
4. **Extra artifacts:** Gemini created `task.md`, `walkthrough.md`, and session copies under
   `~/.gemini`. Future tasks should allow exactly one repo artifact unless asked otherwise.
5. **Live drift:** SparkCRM/DB suggestions slipped toward live DB or real external API wording.
   Future tasks must keep live/staging behind the existing human gate.

## Useful Findings To Preserve

- `ServerApp` protocol still has the right split: app emits decisions; host/machine owns authority
  and effect execution.
- Middleware v0 should be wrapper-based structs implementing `ServerApp`, not a route framework.
- Hot reload should swap an `Arc<dyn ServerApp>` between requests; in-flight requests keep the app
  instance they started with.
- SparkCRM-shaped app should map vendor requests to logical targets and duplicate policy; it must
  not hardcode effect identity or live credentials in `igniter-server`.

## Future Gemini Output Contract

Use this block at the top of future Gemini tasks:

```text
Mode: research/readiness/review only unless this card explicitly says implementation.
Delegation-Code: <code>
Repo target: igniter-lab only.
Allowed output: exactly one repo artifact at the path named by the card.
Do not write to igniter-gov unless the card explicitly says governance/portfolio/gate.
Do not create task.md, walkthrough.md, implementation_plan.md, or session artifact copies.
Do not edit code or commit unless explicitly authorized.

Before suggesting next cards:
- check git log recent commits;
- check the relevant CLOSED cards/proof docs;
- check IMPLEMENTED_SURFACE.md when available.

Vocabulary:
- use "v0" or "recommended" for design suggestions;
- use "proven" only when a passing test/proof doc exists;
- never use "canonical" unless the card grants canon authority.

Closed surfaces:
- no live SparkCRM;
- no live DB;
- no public listener;
- no credentials;
- no effect identity in app decisions.
```

## Curated Next Cards

- `LAB-MACHINE-IGNITER-SERVER-HOT-RELOAD-P4` - implement safe app swap between requests.
- `LAB-MACHINE-SPARKCRM-SERVER-APP-READINESS-P1` - shape a SparkCRM-like app locally, without live
  ingress/egress.

