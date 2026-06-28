# LAB-IGNITER-COMPILER-LOCK-DEFAULT-POLICY-READINESS-P4

Status: CLOSED (2026-06-28)
Route: standard / main-audit / compiler / package trust policy
Skill: idd-agent-protocol
Depends-On: `LAB-IGNITER-COMPILER-LOCK-ON-BUILD-P2`,
`LAB-IGNITER-COMPILER-DEP-PATH-CONTAINMENT-P3`

## Goal

Decide the default policy for project compile lock enforcement now that locked
compile and dependency path containment both exist.

This is audit-control-board row A12 follow-up. It is readiness/policy first:
do not flip defaults in this card unless the analysis proves a tiny safe
implementation and explicitly closes the decision.

## Current Authority

Live source wins. Read first:

- `lab-docs/lang/lab-audit-control-board-v1.md`
- `lab-docs/lang/lab-igniter-compiler-dep-path-containment-p3-v0.md`
- package/workspace implemented surface if present
- `lang/igniter-compiler/src/main.rs`
- `lang/igniter-compiler/src/project.rs`
- `lang/igniter-compiler/tests/package_lockfile_cli_tests.rs`
- `lang/igniter-compiler/tests/package_workspace_tests.rs`

Known live facts to re-verify:

- `compile --project-root ... --locked` / `--frozen` exists and fails before
  emit on missing/stale/integrity-bad locks;
- local dependency paths are contained under the workspace trust root;
- current default compile behavior may still allow unlocked project compile.

## Scope

Allowed:

- Produce a policy/readiness packet comparing default-on lock enforcement,
  warning-only default, explicit `--locked`, and dev escape hatch.
- Run smoke tests to prove current behavior.
- If and only if the safest decision is trivial and evidence is complete, make
  the smallest CLI/doc/test change required by the packet.
- Name exact next implementation card if policy is not implemented here.

Closed:

- No registry/semver/signing implementation.
- No remote source trust implementation.
- No package solver.
- No changes to `.ig` language semantics.
- No broad project-file migration.

## Questions To Answer

1. What is the current default project compile behavior?
2. Should project compile require a current lock by default?
3. Is there a local-dev escape hatch, and what is it called?
4. How does this interact with `igc lock --frozen` and CI?
5. What diagnostics distinguish missing lock, stale lock, integrity fault, and
   explicit unlocked mode?
6. Which examples/fixtures would break if default-on changed today?

## Acceptance

- [ ] Current default behavior is verified by live CLI tests.
- [ ] At least three policy alternatives are compared.
- [ ] Recommendation is explicit: implement now, implement later, or keep
      explicit `--locked` for now.
- [ ] CI/dev/operator consequences are named.
- [ ] If code changes are made, package lockfile/workspace tests are green.
- [ ] If no code changes are made, a concrete next card is named.
- [ ] `git diff --check` passes.
- [ ] Card is closed with a concise report.

## Suggested Verification

```bash
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab
cargo test --manifest-path lang/igniter-compiler/Cargo.toml --test package_lockfile_cli_tests
cargo test --manifest-path lang/igniter-compiler/Cargo.toml --test package_workspace_tests
git diff --check
```

Also run targeted CLI smoke commands in a tempdir/fixture copy, not by mutating
committed fixtures in place.

## Required Packet

Create:

```text
lab-docs/lang/lab-igniter-compiler-lock-default-policy-readiness-p4-v0.md
```

Packet must include:

- current behavior transcript;
- policy alternatives;
- recommendation;
- exact implementation card if not implemented here.

## Closing Report (2026-06-28)

Outcome: **readiness/policy decided — no default flipped, no code change.**

Decision: **keep the explicit `--locked` gate for now** (policy option C). Default-on lock
enforcement is **deferred** to `LAB-IGNITER-COMPILER-LOCK-DEFAULT-ENFORCE-P5`, gated on a
non-local trust surface (registry / remote source / signing) landing first.

Why no flip here: the card permits a default change only if *tiny and safe*. It is neither —
flipping default-on would `OOF-LOCK-MISSING` all **26** `project_mode` fixtures (the repo
ships **zero** committed `igniter.lock`), break every lockless project build and the dev inner
loop, invert a regression test, and require a brand-new `--no-lock` escape hatch. The threat
it guards (remote/registry tampering) does not exist in the LOCAL-v0 package model, and the
opt-in stack (`compile --locked` + `lock --frozen` + `verify --strict` + `package admit
--require-lock`) already delivers the guarantee for anyone who wants it.

Deliverable: `lab-docs/lang/lab-igniter-compiler-lock-default-policy-readiness-p4-v0.md`
(current-behavior transcript, 4 policy alternatives, recommendation, CI/dev/operator
consequences, next-card spec, all 6 card questions answered).

Acceptance:

- [x] Current default behavior verified by live CLI tests
      (`cli_compile_without_locked_allows_missing_lock`) + tempdir smoke transcript.
- [x] Four policy alternatives compared (A default-on / B warning-only / C explicit / D
      auto-when-present).
- [x] Recommendation explicit: **keep explicit `--locked` for now** (defer default-on to P5).
- [x] CI / dev / operator consequences named.
- [x] No code changes made → concrete next card named (`…LOCK-DEFAULT-ENFORCE-P5`).
- [x] `git diff --check` passes.
- [x] Card closed with this report.

Side update: audit-board A12 → "PARTLY CLOSED (default policy decided)"; remaining work now
points at P5 gated on registry/signing/remote readiness.

Verification:

```text
cargo test --manifest-path lang/igniter-compiler/Cargo.toml --test package_lockfile_cli_tests   → 55 passed; 0 failed
cargo test --manifest-path lang/igniter-compiler/Cargo.toml --test package_workspace_tests       → 53 passed; 0 failed
git diff --check  → PASS
```

